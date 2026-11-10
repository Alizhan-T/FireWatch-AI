"""Real FFmpeg + YOLO against a local HLS fixture, never an external camera."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import shutil
import subprocess
import threading
import time

import pytest
from fastapi.testclient import TestClient

from app.main import create_app

pytest.importorskip("ultralytics")
pytestmark = pytest.mark.skipif(not shutil.which("ffmpeg"), reason="FFmpeg required")


def test_hls_capture_yolo_monitoring_and_reconnection(settings, tmp_path):
    video = Path(__file__).resolve().parents[1] / "demo_assets/videos/demo_wildfire_active.mp4"
    stream_dir = tmp_path / "hls"
    stream_dir.mkdir()
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(video),
                    "-c:v", "copy", "-an", "-hls_time", "1", "-hls_list_size", "0",
                    "-hls_segment_filename", str(stream_dir / "part%03d.ts"),
                    str(stream_dir / "stream.m3u8")], check=True, timeout=30)
    server = ThreadingHTTPServer(("127.0.0.1", 0),
                                partial(SimpleHTTPRequestHandler, directory=str(stream_dir)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    settings.detector = "yolo"
    settings.camera_auto_scan_interval_sec = 0.05
    settings.camera_confirmation_frames = 3
    settings.api_access_token = "local-pipeline-test-key"
    try:
        with TestClient(create_app(settings)) as client:
            client.headers["X-API-Key"] = settings.api_access_token
            cam = client.post("/cameras", json={"id": "fixture", "name": "LOCAL TEST VIDEO",
                "url": f"http://127.0.0.1:{server.server_port}/stream.m3u8", "lat": 0, "lon": 0})
            assert cam.status_code == 201
            checked = client.post("/cameras/fixture/check").json()
            assert checked["status"] == "online"
            assert client.get(checked["snapshot_url"]).status_code == 200
            # A real HTTP outage must change status, then a restored stream must recover.
            playlist = stream_dir / "stream.m3u8"
            playlist.rename(stream_dir / "paused.m3u8")
            assert client.post("/cameras/fixture/check").json()["status"] == "offline"
            (stream_dir / "paused.m3u8").rename(playlist)
            assert client.post("/cameras/fixture/check").json()["status"] == "online"
            assert client.post("/monitoring/start").status_code == 200
            deadline = time.monotonic() + 25
            while not client.get("/incidents").json():
                assert time.monotonic() < deadline
                time.sleep(0.1)
            incident = client.get("/incidents").json()[0]
            assert incident["detection_mode"] == "real_model"
            assert incident["classification"] in ("fire", "fire_smoke")
            assert client.get(incident["media_url"]).status_code == 200
            assert client.get("/monitoring/status").json()["metrics"]["succeeded"] >= 3
            assert client.get("/ready").status_code == 200
            client.post("/monitoring/stop")
            assert client.get("/ready").status_code == 503
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
