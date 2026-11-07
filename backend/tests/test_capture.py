"""Симуляция с «камерой»: недоступный поток -> DEMO-ролик через FFmpeg (переиспользует capture.py)."""
import json
import shutil

import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="FFmpeg не установлен")
def test_simulate_with_unreachable_camera_falls_back_to_demo_clip(settings, tmp_path):
    cams = tmp_path / "cams.json"
    cams.write_text(json.dumps([{"id": "dead", "name": "Недоступная камера",
                                 "url": "http://127.0.0.1:9/none.m3u8", "lat": 50, "lon": 70}]))
    settings.cameras_file = cams
    settings.clip_seconds = 2
    with TestClient(create_app(settings)) as c:
        r = c.post("/simulate_fire", json={"camera_id": "dead", "capture_from_camera": True})
        assert r.status_code == 201, r.text
        inc = r.json()
        assert inc["media_type"] == "video"
        assert inc["media_url"].endswith(".mp4")
        assert "DEMO" in inc["media_note"]
        clip = c.get(inc["media_url"])
        assert clip.status_code == 200 and len(clip.content) > 1000
