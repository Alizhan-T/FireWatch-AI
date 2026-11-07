"""Пайплайн детекции: реальная модель YOLO (если доступна) и DEMO-эвристика."""
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.detection import build_detector, severity_for
from app.detection.heuristic_provider import HeuristicFireDetector
from app.main import create_app

from .conftest import FIXTURES, make_settings

WEIGHTS = Path(__file__).resolve().parent.parent / "models" / "fire_smoke_yolov8n.pt"


def _ultralytics_available() -> bool:
    try:
        import ultralytics  # noqa: F401
        return True
    except ImportError:
        return False


needs_model = pytest.mark.skipif(
    not (WEIGHTS.exists() and _ultralytics_available()),
    reason="нет весов YOLO или ultralytics — реальная модель не тестируется",
)


def test_heuristic_is_deterministic_and_labeled():
    d = HeuristicFireDetector()
    a = d.detect(FIXTURES / "fire_crop.jpg")
    b = d.detect(FIXTURES / "fire_crop.jpg")
    assert a == b  # без random
    assert d.mode == "demo_heuristic" and "DEMO" in d.disclaimer
    assert a.fire_detected
    neg = d.detect(FIXTURES / "no_fire.jpg")
    assert not neg.fire_detected and neg.classification in ("none", "smoke")


def test_severity_rules():
    assert severity_for("fire_smoke", 0.9) == "critical"
    assert severity_for("fire", 0.8) == "high"
    assert severity_for("fire", 0.3) == "medium"
    assert severity_for("smoke", 0.3) == "low"
    assert severity_for("none", 0.0) == "low"


def test_auto_falls_back_to_demo_when_weights_missing(tmp_path):
    s = make_settings(tmp_path, detector="auto")
    s.yolo_weights = tmp_path / "missing.pt"
    det, reason = build_detector(s)
    assert det.mode == "demo_heuristic" and reason


@needs_model
def test_real_model_detects_fire(tmp_path):
    s = make_settings(tmp_path, detector="yolo")
    s.yolo_weights = WEIGHTS
    det, reason = build_detector(s)
    assert det.mode == "real_model" and reason is None
    out = det.detect(FIXTURES / "fire_crop.jpg")
    assert out.fire_detected, out
    assert 0 < out.confidence <= 1
    assert all(b.label in ("fire", "smoke") for b in out.boxes)
    neg = det.detect(FIXTURES / "no_fire.jpg")
    assert not neg.fire_detected


@needs_model
def test_detect_endpoint_with_real_model(tmp_path):
    s = make_settings(tmp_path, detector="yolo")
    s.yolo_weights = WEIGHTS
    with TestClient(create_app(s)) as c:
        assert c.get("/health").json()["detector"]["mode"] == "real_model"
        r = c.post("/detect", files={"file": ("f.jpg", (FIXTURES / "fire_crop.jpg").read_bytes(),
                                               "image/jpeg")})
        j = r.json()
        assert r.status_code == 200 and j["mode"] == "real_model"
        assert j["fire_detected"] and j["annotated_image_url"]
        assert "REAL MODEL" in j["disclaimer"]
        assert c.get(j["annotated_image_url"]).status_code == 200
        stats = c.get("/stats").json()["detections"]
        assert stats["total"] == 1 and stats["by_mode"] == {"real_model": 1}

        # Verify FFmpeg frame extraction + YOLOv8n inference on DEMO VIDEO (Wildfire Active)
        vr = c.post(
            "/demo_videos/demo_wildfire_active/analyze_frame",
            json={"timestamp_sec": 1.2, "save_incident": True},
        )
        assert vr.status_code == 200, vr.text
        vj = vr.json()
        assert vj["mode"] == "real_model"
        assert vj["fire_detected"] is True
        assert vj["confidence"] > 0.3
        assert len(vj["boxes"]) >= 1
        assert vj["annotated_image_url"] is not None
        assert vj["incident_id"] is not None

        # Verify FFmpeg frame extraction + YOLOv8n inference on DEMO VIDEO (Forest Clear — no fire)
        cr = c.post(
            "/demo_videos/demo_forest_clear/analyze_frame",
            json={"timestamp_sec": 1.0, "save_incident": True},
        )
        assert cr.status_code == 200, cr.text
        cj = cr.json()
        assert cj["mode"] == "real_model"
        assert cj["fire_detected"] is False
        assert cj["classification"] == "none"
        assert cj["incident_id"] is None
