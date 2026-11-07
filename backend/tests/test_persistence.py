"""Персистентность SQLite: данные переживают перезапуск приложения."""
from fastapi.testclient import TestClient

from app.db import Database
from app.main import create_app


def test_incident_survives_restart(settings):
    with TestClient(create_app(settings)) as c:
        inc = c.post("/simulate_fire", json={"severity": "high"}).json()
        c.patch(f"/incidents/{inc['id']}/status", json={"status": "acknowledged"})
        c.post("/register_device", json={"token": "t" * 32})

    # «перезапуск»: новое приложение на том же файле БД
    with TestClient(create_app(settings)) as c2:
        got = c2.get(f"/incidents/{inc['id']}")
        assert got.status_code == 200
        assert got.json()["status"] == "acknowledged"
        assert got.json()["lat"] == inc["lat"]
        assert c2.get("/health").json()["devices_registered"] == 1


def test_database_direct(tmp_path):
    db = Database(tmp_path / "x.db")
    row = db.create_incident(title="a", source="manual", lat=1.5, lon=2.5, severity="low",
                             detection_mode="manual")
    db2 = Database(tmp_path / "x.db")
    assert db2.get_incident(row["id"])["lat"] == 1.5
    assert db2.incident_stats()["total"] == 1
    assert db2.update_incident_status("missing", "resolved") is None


def test_severity_check_constraint(tmp_path):
    import sqlite3

    import pytest

    db = Database(tmp_path / "y.db")
    with pytest.raises(sqlite3.IntegrityError):
        db.create_incident(title="a", source="manual", lat=0, lon=0, severity="extreme",
                           detection_mode="manual")


def test_camera_status_keeps_last_good_snapshot_when_scan_does_not_replace_it(tmp_path):
    from app.db import Database

    db = Database(tmp_path / "camera-status.db")
    db.upsert_camera_status(
        "cam-1", status="online", last_error=None,
        snapshot_path="snapshots/cam-1.jpg",
    )
    updated = db.upsert_camera_status(
        "cam-1", status="online", last_error=None,
        snapshot_path=None,
    )
    assert updated["snapshot_path"] == "snapshots/cam-1.jpg"
