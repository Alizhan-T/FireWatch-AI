import json
import time
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient

from app import capture, main, push
from app.config import Settings
from app.detection.base import BoxOut, DetectorOutput
from app.main import create_app
from app.monitoring import ConfirmationTracker


def test_production_rejects_missing_security_and_demo_fallback():
    settings = Settings(env_mode="production", detector="yolo", api_access_token="",
                        public_base_url="https://firewatch.example.com")
    with pytest.raises(ValueError, match="API_ACCESS_TOKEN"):
        settings.validate()
    settings.api_access_token = "x" * 48
    for invalid in ("http://example.com", "https://user:password@example.com", "https://example.com/api"):
        settings.public_base_url = invalid
        with pytest.raises(ValueError, match="PUBLIC_BASE_URL"):
            settings.validate()
    settings.public_base_url = "https://firewatch.example.com"
    settings.detector = "auto"
    with pytest.raises(ValueError, match="DETECTOR=yolo"):
        settings.validate()
    settings.detector = "yolo"
    settings.validate()


def test_only_liveness_is_public(settings):
    settings.api_access_token = "test-key"
    with TestClient(create_app(settings)) as client:
        assert client.get("/live").json() == {"status": "alive"}
        assert client.head("/live").status_code == 200
        for path in ("/ready", "/health", "/monitoring/status", "/media/demo_videos/demo_forest_clear.mp4"):
            assert client.get(path).status_code == 401
        response = client.get("/ready", headers={"X-API-Key": "test-key"})
        assert response.status_code == 503
        assert "real_model_unavailable" in response.json()["reasons"]
        assert "monitoring_inactive" in response.json()["reasons"]


def test_confirmation_resets_for_clear_low_confidence_outage_and_new_hazard():
    gate = ConfirmationTracker(3, 0.5)
    assert not gate.observe("one", "fire", 0.9)
    assert not gate.observe("one", "fire_smoke", 0.9)
    assert not gate.observe("two", "fire", 0.9)  # isolated cameras
    assert not gate.observe("one", "none", 0)
    assert not gate.observe("one", "fire", 0.9)
    assert not gate.observe("one", "fire", 0.49)
    assert not gate.observe("one", "smoke", 0.9)
    assert not gate.observe("one", "fire", 0.9)  # smoke cannot confirm fire
    gate.reset("one")  # stream failure breaks the sequence
    assert not gate.observe("one", "fire", 0.9)
    assert not gate.observe("one", "fire_smoke", 0.9)
    assert gate.observe("one", "fire", 0.9)
    assert gate.pending() == {"two": 1}


def test_camera_registry_survives_concurrent_writes(settings, tmp_path):
    settings.cameras_file = tmp_path / "cameras.json"
    with TestClient(create_app(settings)) as client:
        def add(index):
            return client.post("/cameras", json={"id": f"cam-{index}", "name": f"Camera {index}",
                "url": "https://camera.example/stream.m3u8", "lat": 51, "lon": 71}).status_code
        with ThreadPoolExecutor(max_workers=8) as executor:
            assert list(executor.map(add, range(20))) == [201] * 20
        assert len(json.loads(settings.cameras_file.read_text())) == 20
        assert len(client.get("/cameras").json()) == 20


def test_monitoring_recovers_confirms_deduplicates_and_cleans_frames(settings, tmp_path, monkeypatch, fire_jpg):
    class Detector:
        mode, provider, model_name, disclaimer = "real_model", "test", "test", "test"

        def detect(self, _):
            return DetectorOutput(True, False, 0.9, [BoxOut("fire", 0.9, 10, 10, 100, 100)])

    settings.cameras_file = tmp_path / "cameras.json"
    settings.cameras_file.write_text(json.dumps([{"id": "cam", "name": "Test",
        "url": "https://camera.example/live.m3u8", "lat": 51, "lon": 71}]))
    settings.camera_auto_scan_enabled = True
    settings.camera_auto_scan_interval_sec = 0.02
    settings.camera_confirmation_frames = 3
    monkeypatch.setattr(main, "build_detector", lambda _: (Detector(), None))
    monkeypatch.setattr(capture, "ffmpeg_available", lambda: True)
    calls, sends = [], []

    async def grab(_, output, timeout):
        calls.append(True)
        if len(calls) == 2:
            raise capture.CaptureError("offline")
        output.write_bytes(fire_jpg)
        return output

    monkeypatch.setattr(capture, "grab_stream_frame", grab)
    monkeypatch.setattr(push, "send_incident_alert", lambda *args: sends.append(args) or {"sent": 1, "failed": 0})
    with TestClient(create_app(settings)) as client:
        deadline = time.monotonic() + 5
        while client.get("/monitoring/status").json()["metrics"]["succeeded"] < 7:
            assert time.monotonic() < deadline
            time.sleep(0.02)
        assert client.get("/ready").status_code == 200
        incidents = client.get("/incidents").json()
        assert len(incidents) == 1
        assert len(sends) == 1
        assert incidents[0]["is_demo"] is False
        metrics = client.get("/monitoring/status").json()["metrics"]
        assert metrics["failed"] == 1
        client.post("/monitoring/stop")
        assert client.get("/ready").status_code == 503
        assert len(list((settings.media_dir / "uploads").glob("*_camera.jpg"))) == 1
        assert client.app.state.db.detection_stats()["total"] == 1


def test_push_test_targets_only_registered_device(client, monkeypatch):
    monkeypatch.setattr(push, "is_enabled", lambda: False)
    assert client.post("/push/test", json={"token": "test-device-token"}).status_code == 503
    monkeypatch.setattr(push, "is_enabled", lambda: True)
    assert client.post("/push/test", json={"token": "test-device-token"}).status_code == 404
    client.post("/register_device", json={"token": "test-device-token"})
    calls = []
    monkeypatch.setattr(push, "send_incident_alert", lambda *args: calls.append(args) or
                        {"enabled": True, "sent": 1, "failed": 0, "invalid_tokens": []})
    result = client.post("/push/test", json={"token": "test-device-token"})
    assert result.json() == {"enabled": True, "sent": 1, "failed": 0}
    assert calls[0][0] == ["test-device-token"]
    assert calls[0][3] == {"type": "test"}


def test_push_batches_and_invalid_token_cleanup(monkeypatch):
    from types import SimpleNamespace
    from firebase_admin import messaging

    class UnregisteredError(Exception):
        pass

    monkeypatch.setattr(push, "is_enabled", lambda: True)
    batches = []

    def send(message):
        batches.append(message.tokens)
        responses = [SimpleNamespace(success=True, exception=None) for _ in message.tokens]
        if len(batches) == 1:
            responses[0] = SimpleNamespace(success=False, exception=UnregisteredError())
        return SimpleNamespace(responses=responses,
            success_count=sum(r.success for r in responses), failure_count=sum(not r.success for r in responses))

    monkeypatch.setattr(messaging, "send_each_for_multicast", send)
    result = push.send_incident_alert([f"token-{i}" for i in range(1001)], "test", "test", {})
    assert [len(b) for b in batches] == [500, 500, 1]
    assert result["sent"] == 1000 and result["failed"] == 1
    assert result["invalid_tokens"] == ["token-0"]
