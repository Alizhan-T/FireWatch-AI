"""API-тесты (DEMO-детектор, чтобы быть быстрыми и не зависеть от весов)."""


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    j = r.json()
    assert j["status"] == "ok" and j["database"] is True
    assert j["detector"]["mode"] == "demo_heuristic"
    assert j["firebase"] == "not_configured"
    assert j["camera_auto_scan_enabled"] is False
    assert j["camera_auto_scan_active"] is False


def test_docs_available(client):
    assert client.get("/docs").status_code == 200
    spec = client.get("/openapi.json").json()
    for path in ["/health", "/cameras", "/incidents", "/incidents/{incident_id}",
                 "/detect", "/register_device", "/simulate_fire",
                 "/cameras/{camera_id}/analyze", "/incidents/{incident_id}/status"]:
        assert path in spec["paths"], path


def test_cors_header(client):
    r = client.options("/incidents", headers={
        "Origin": "http://localhost:1234", "Access-Control-Request-Method": "GET"})
    assert r.status_code == 200
    assert r.headers.get("access-control-allow-origin") in ("*", "http://localhost:1234")


def test_cameras(client):
    r = client.get("/cameras")
    assert r.status_code == 200
    assert all({"id", "name", "lat", "lon"} <= c.keys() for c in r.json())


def test_create_get_list_incident(client):
    r = client.post("/incidents", json={"title": "Дым у озера", "lat": 53.1, "lon": 70.2,
                                        "severity": "medium"})
    assert r.status_code == 201, r.text
    inc = r.json()
    assert inc["status"] == "new" and inc["detection_mode"] == "manual"
    assert inc["is_demo"] is False
    assert client.get(f"/incidents/{inc['id']}").json()["title"] == "Дым у озера"
    ids = [i["id"] for i in client.get("/incidents").json()]
    assert inc["id"] in ids
    assert client.get("/incidents?severity=critical").json() == []


def test_incident_validation(client):
    assert client.post("/incidents", json={"title": "x", "lat": 200, "lon": 0}).status_code == 422
    assert client.post("/incidents", json={"title": "x", "lat": 1, "lon": 1,
                                           "severity": "extreme"}).status_code == 422
    assert client.post("/incidents", json={"lat": 1, "lon": 1}).status_code == 422


def test_incident_not_found(client):
    assert client.get("/incidents/nope").status_code == 404
    assert client.patch("/incidents/nope/status", json={"status": "resolved"}).status_code == 404


def test_update_status(client):
    inc = client.post("/incidents", json={"title": "t", "lat": 1, "lon": 1}).json()
    r = client.patch(f"/incidents/{inc['id']}/status", json={"status": "resolved"})
    assert r.status_code == 200 and r.json()["status"] == "resolved"
    bad = client.patch(f"/incidents/{inc['id']}/status", json={"status": "deleted"})
    assert bad.status_code == 422


def test_register_device(client):
    r = client.post("/register_device", json={"token": "a" * 40, "name": "iPhone"})
    assert r.status_code == 200 and r.json()["devices"] == 1
    r = client.post("/register_device", json={"token": "a" * 40, "name": "iPhone 2"})
    assert r.json()["devices"] == 1  # upsert, не дубль
    assert client.post("/register_device", json={"token": "short"}).status_code == 422


def test_simulate_fire_without_camera(client):
    r = client.post("/simulate_fire", json={"severity": "critical"})
    assert r.status_code == 201, r.text
    inc = r.json()
    assert inc["is_demo"] is True
    assert inc["detection_mode"] == "simulated"
    assert inc["confidence"] is None  # симуляция не выдаёт фейковую уверенность
    assert inc["severity"] == "critical"
    assert inc["media_url"] and client.get(inc["media_url"]).status_code == 200
    assert "DEMO" in inc["media_note"]
    # попадает в список, статистику и зоны риска
    assert client.get("/incidents").json()[0]["id"] == inc["id"]
    st = client.get("/stats").json()
    assert st["incidents"]["total"] == 1 and st["incidents"]["demo"] == 1
    assert st["high_risk_zones"] == 1
    zones = client.get("/risk_zones").json()
    assert zones[0]["incident_ids"] == [inc["id"]]


def test_simulate_fire_empty_body_and_unknown_camera(client):
    assert client.post("/simulate_fire").status_code == 201
    assert client.post("/simulate_fire", json={"camera_id": "nope"}).status_code == 404


def test_detect_rejects_bad_files(client):
    r = client.post("/detect", files={"file": ("a.txt", b"hello", "text/plain")})
    assert r.status_code == 415
    r = client.post("/detect", files={"file": ("a.jpg", b"", "image/jpeg")})
    assert r.status_code == 400
    assert client.post("/detect").status_code == 422


def test_detect_and_save_incident(client, fire_jpg):
    r = client.post("/detect", files={"file": ("fire.jpg", fire_jpg, "image/jpeg")})
    assert r.status_code == 200, r.text
    det = r.json()
    assert det["status"] == "completed"
    assert det["mode"] == "demo_heuristic"
    assert "DEMO" in det["disclaimer"]
    assert client.get(det["image_url"]).status_code == 200
    inc = client.post("/incidents", json={"title": "Из детекции", "lat": 50, "lon": 70,
                                          "severity": "high", "detection_id": det["id"]})
    assert inc.status_code == 201
    j = inc.json()
    assert j["source"] == "detection" and j["detection_mode"] == "demo_heuristic"
    assert j["detection_id"] == det["id"] and j["media_type"] == "image"


def test_detect_save_incident_flag(client, fire_jpg):
    r = client.post("/detect", data={"save_incident": "true", "lat": "51.0", "lon": "71.0"},
                    files={"file": ("fire.jpg", fire_jpg, "image/jpeg")})
    j = r.json()
    assert j["classification"] != "none"
    assert j["incident_id"]
    inc = client.get(f"/incidents/{j['incident_id']}").json()
    assert inc["lat"] == 51.0 and inc["source"] == "detection"


def test_network_info_and_cameras_crud(client, tmp_path, monkeypatch):
    r = client.get("/network_info")
    assert r.status_code == 200
    net = r.json()
    assert "lan_ip" in net and "lan_url" in net and "localhost_url" in net

    # Redirect cameras_file to tmp_path so test doesn't mutate repo's cameras.json
    cam_file = tmp_path / "cameras_test.json"
    cam_file.write_text("[]", encoding="utf-8")
    monkeypatch.setattr(client.app.state.settings, "cameras_file", cam_file)

    assert client.get("/cameras").json() == []
    added = client.post("/cameras", json={
        "name": "Тестовая RTSP камера",
        "url": "rtsp://192.168.1.50:554/stream1",
        "lat": 43.25,
        "lon": 76.95,
    })
    assert added.status_code == 201
    cam_id = added.json()["id"]
    assert len(client.get("/cameras").json()) == 1

    deleted = client.delete(f"/cameras/{cam_id}")
    assert deleted.status_code == 200 and deleted.json()["remaining"] == 0


def test_demo_videos_and_frame_analysis_and_history(client):
    r = client.get("/demo_videos")
    assert r.status_code == 200
    videos = r.json()
    assert len(videos) >= 1
    first = videos[0]
    assert first["is_demo"] is True and first["badge"] == "DEMO VIDEO"
    assert client.get(first["video_url"]).status_code == 200

    res = client.post(
        f"/demo_videos/{first['id']}/analyze_frame",
        json={"timestamp_sec": 1.0, "save_incident": True},
    )
    assert res.status_code == 200, res.text
    det = res.json()
    assert det["status"] == "completed"
    assert det["source_video_id"] == first["id"]
    assert det["frame_timestamp_sec"] == 1.0
    assert client.get(det["image_url"]).status_code == 200

    # Check GET /detections/{id} and GET /detections
    single = client.get(f"/detections/{det['id']}")
    assert single.status_code == 200 and single.json()["id"] == det["id"]
    assert client.get("/detections/nonexistent").status_code == 404

    hist = client.get("/detections").json()
    assert any(d["id"] == det["id"] and d["source_video_id"] == first["id"] for d in hist)

    # Check out-of-range timestamp_sec -> 422
    bad_ts = client.post(
        f"/demo_videos/{first['id']}/analyze_frame",
        json={"timestamp_sec": 9999.0, "save_incident": False},
    )
    assert bad_ts.status_code == 422

    # Check nonexistent demo video -> 404
    assert client.post(
        "/demo_videos/no_such_video/analyze_frame",
        json={"timestamp_sec": 0.5},
    ).status_code == 404


def test_incident_idempotency_filter_search_and_delete(client, fire_jpg):
    r = client.post("/detect", files={"file": ("fire.jpg", fire_jpg, "image/jpeg")})
    det = r.json()

    # Creating incident twice for the same detection_id is idempotent (no duplicate)
    inc1 = client.post(
        "/incidents",
        json={"title": "Пожар в сосновом бору", "lat": 50.5, "lon": 70.5, "detection_id": det["id"]},
    )
    inc2 = client.post(
        "/incidents",
        json={"title": "Пожар в сосновом бору", "lat": 50.5, "lon": 70.5, "detection_id": det["id"]},
    )
    assert inc1.status_code == 201 and inc2.status_code in (200, 201)
    assert inc1.json()["id"] == inc2.json()["id"]

    inc_id = inc1.json()["id"]

    # Search filter `q`
    found = client.get("/incidents", params={"q": "сосновом"}).json()
    assert len(found) == 1 and found[0]["id"] == inc_id
    assert client.get("/incidents", params={"q": "несуществующий_запрос"}).json() == []

    # Type filter (`fire` vs `smoke`)
    fire_list = client.get("/incidents", params={"type": "fire"}).json()
    assert any(i["id"] == inc_id for i in fire_list)

    # Delete incident
    del_res = client.delete(f"/incidents/{inc_id}")
    assert del_res.status_code == 200 and del_res.json()["deleted"] == inc_id
    assert client.get(f"/incidents/{inc_id}").status_code == 404
    assert client.delete(f"/incidents/{inc_id}").status_code == 404


def test_camera_validation_and_stream_check(client, tmp_path, monkeypatch):
    cam_file = tmp_path / "cameras_check.json"
    cam_file.write_text("[]", encoding="utf-8")
    monkeypatch.setattr(client.app.state.settings, "cameras_file", cam_file)

    # Invalid URL rejected with 422
    bad = client.post("/cameras", json={"name": "Bad Cam", "url": "ftp://invalid", "lat": 43.0, "lon": 76.0})
    assert bad.status_code == 422

    # Valid camera created with status='unchecked'
    added = client.post("/cameras", json={
        "name": "Local Unreachable Stream",
        "url": "http://127.0.0.1:65530/nonexistent.m3u8",
        "lat": 43.25,
        "lon": 76.95,
    })
    assert added.status_code == 201
    cam = added.json()
    assert cam["status"] == "unchecked"

    # Stream check records offline status and error message in SQLite
    checked = client.post(f"/cameras/{cam['id']}/check")
    assert checked.status_code == 200
    cj = checked.json()
    assert cj["status"] == "offline"
    assert cj["last_checked_at"] is not None
    assert cj["last_error"] is not None


def test_corrupted_video_upload_rejected(client):
    # Empty file -> 400
    r_empty = client.post("/demo_videos/upload", files={"file": ("empty.mp4", b"", "video/mp4")})
    assert r_empty.status_code == 400

    # Wrong extension -> 415
    r_ext = client.post("/demo_videos/upload", files={"file": ("bad.txt", b"not video", "text/plain")})
    assert r_ext.status_code == 415

    # Corrupted bytes with .mp4 extension -> 415 (ffprobe rejects non-video stream)
    r_corrupt = client.post(
        "/demo_videos/upload",
        files={"file": ("corrupt.mp4", b"not a valid mp4 container header", "video/mp4")},
    )
    assert r_corrupt.status_code == 415


def test_stats_breakdown_and_latest_detection(client, fire_jpg):
    client.post("/detect", files={"file": ("fire.jpg", fire_jpg, "image/jpeg")})
    st = client.get("/stats").json()
    assert "fire_detections" in st
    assert "smoke_detections" in st
    assert "clear_detections" in st
    assert st["fire_detections"] >= 1
    assert st["latest_detection"] is not None
    assert "id" in st["latest_detection"] and "classification" in st["latest_detection"]



def test_camera_frame_analysis_creates_reviewable_incident(client, tmp_path, monkeypatch, fire_jpg):
    from app import capture

    cam_file = tmp_path / "camera_analyze.json"
    cam_file.write_text("[]", encoding="utf-8")
    monkeypatch.setattr(client.app.state.settings, "cameras_file", cam_file)
    added = client.post("/cameras", json={
        "name": "Test public HLS camera",
        "url": "https://camera.example/live.m3u8",
        "lat": 43.25,
        "lon": 76.95,
    })
    assert added.status_code == 201, added.text
    camera = added.json()

    async def fake_grab_stream_frame(stream_url, output_jpg, timeout=15):
        output_jpg.parent.mkdir(parents=True, exist_ok=True)
        output_jpg.write_bytes(fire_jpg)
        return output_jpg

    monkeypatch.setattr(capture, "grab_stream_frame", fake_grab_stream_frame)
    response = client.post(f"/cameras/{camera['id']}/analyze")
    assert response.status_code == 200, response.text
    detection = response.json()
    assert detection["status"] == "completed"
    assert detection["mode"] == "demo_heuristic"
    assert detection["incident_id"]

    incident = client.get(f"/incidents/{detection['incident_id']}").json()
    assert incident["source"] == "camera"
    assert incident["camera_id"] == camera["id"]
    assert incident["is_demo"] is True
    assert incident["status"] == "new"

    # Repeated detections from the same camera are linked to the existing active incident.
    repeated = client.post(f"/cameras/{camera['id']}/analyze")
    assert repeated.status_code == 200, repeated.text
    assert repeated.json()["id"] != detection["id"]
    assert repeated.json()["incident_id"] == detection["incident_id"]


def test_optional_api_key_guard(tmp_path):
    from fastapi.testclient import TestClient
    from app.config import Settings
    from app.main import create_app

    settings = Settings()
    settings.database_path = tmp_path / "secure.db"
    settings.media_dir = tmp_path / "secure-media"
    settings.demo_assets_dir = tmp_path / "demo_assets"
    settings.cameras_file = tmp_path / "cameras.json"
    settings.cameras_file.write_text("[]", encoding="utf-8")
    settings.detector = "heuristic"
    settings.firebase_credentials = ""
    settings.api_access_token = "test-secret-token"

    with TestClient(create_app(settings)) as secure_client:
        assert secure_client.get("/health").status_code == 200
        assert secure_client.get("/stats").status_code == 401
        ok = secure_client.get("/stats", headers={"X-API-Key": "test-secret-token"})
        assert ok.status_code == 200


def test_auto_scan_requires_real_detector(tmp_path):
    from fastapi.testclient import TestClient
    from app.config import Settings
    from app.main import create_app

    settings = Settings()
    settings.database_path = tmp_path / "auto-scan.db"
    settings.media_dir = tmp_path / "auto-scan-media"
    settings.demo_assets_dir = tmp_path / "demo_assets"
    settings.cameras_file = tmp_path / "auto-scan-cameras.json"
    settings.cameras_file.write_text("[]", encoding="utf-8")
    settings.detector = "heuristic"
    settings.firebase_credentials = ""
    settings.camera_auto_scan_enabled = True

    with TestClient(create_app(settings)) as scan_client:
        health = scan_client.get("/health").json()
        assert health["camera_auto_scan_enabled"] is True
        assert health["camera_auto_scan_active"] is False
