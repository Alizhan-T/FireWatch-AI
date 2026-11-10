"""SQLite-хранилище (stdlib sqlite3, одно соединение на операцию)."""
from __future__ import annotations

import json
import sqlite3
import threading
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

SCHEMA = """
CREATE TABLE IF NOT EXISTS incidents (
    id              TEXT PRIMARY KEY,
    title           TEXT NOT NULL,
    description     TEXT,
    source          TEXT NOT NULL,
    camera_id       TEXT,
    location_name   TEXT,
    lat             REAL NOT NULL,
    lon             REAL NOT NULL,
    severity        TEXT NOT NULL CHECK (severity IN ('low','medium','high','critical')),
    status          TEXT NOT NULL DEFAULT 'new'
                    CHECK (status IN ('new','acknowledged','resolved','false_alarm')),
    classification  TEXT,
    confidence      REAL,
    detection_mode  TEXT NOT NULL,
    media_type      TEXT,
    media_path      TEXT,
    media_note      TEXT,
    is_demo         INTEGER NOT NULL DEFAULT 0,
    detection_id    TEXT,
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_incidents_created ON incidents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_incidents_camera_active
    ON incidents(camera_id, status, classification, detection_mode, created_at DESC);

CREATE TABLE IF NOT EXISTS detections (
    id              TEXT PRIMARY KEY,
    status          TEXT NOT NULL,
    mode            TEXT NOT NULL,
    provider        TEXT NOT NULL,
    model_name      TEXT NOT NULL,
    classification  TEXT NOT NULL,
    confidence      REAL NOT NULL,
    boxes_json      TEXT NOT NULL DEFAULT '[]',
    processing_ms   INTEGER NOT NULL,
    image_path      TEXT NOT NULL,
    annotated_path  TEXT,
    incident_id     TEXT,
    created_at      TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS camera_status (
    camera_id       TEXT PRIMARY KEY,
    status          TEXT NOT NULL,
    last_checked_at TEXT NOT NULL,
    last_frame_at   TEXT,
    last_error      TEXT,
    snapshot_path   TEXT
);

CREATE TABLE IF NOT EXISTS devices (
    token       TEXT PRIMARY KEY,
    name        TEXT,
    platform    TEXT,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);
"""


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def new_id(prefix: str) -> str:
    return f"{prefix}_{datetime.now().strftime('%Y%m%d%H%M%S')}_{uuid.uuid4().hex[:6]}"


class Database:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        with self.conn() as c:
            c.executescript(SCHEMA)
            # Лёгкая миграция: новые колонки для старых БД
            det_cols = {r[1] for r in c.execute("PRAGMA table_info(detections)").fetchall()}
            if "source_video_id" not in det_cols:
                c.execute("ALTER TABLE detections ADD COLUMN source_video_id TEXT")
            if "frame_timestamp_sec" not in det_cols:
                c.execute("ALTER TABLE detections ADD COLUMN frame_timestamp_sec REAL")

    @contextmanager
    def conn(self) -> Iterator[sqlite3.Connection]:
        c = sqlite3.connect(self.path, timeout=10)
        c.row_factory = sqlite3.Row
        c.execute("PRAGMA journal_mode=WAL")
        try:
            with self._lock:
                yield c
                c.commit()
        finally:
            c.close()

    def ping(self) -> bool:
        with self.conn() as c:
            return c.execute("SELECT 1").fetchone()[0] == 1

    # ---------- incidents ----------
    def create_incident(self, **fields: Any) -> dict:
        ts = now_iso()
        row = {
            "id": fields.pop("id", None) or new_id("inc"),
            "status": "new",
            "created_at": ts,
            "updated_at": ts,
            **fields,
        }
        row["is_demo"] = int(bool(row.get("is_demo", False)))
        cols = ",".join(row)
        qs = ",".join("?" for _ in row)
        with self.conn() as c:
            c.execute(f"INSERT INTO incidents ({cols}) VALUES ({qs})", list(row.values()))
        return self.get_incident(row["id"])  # type: ignore[return-value]

    def get_incident(self, incident_id: str) -> dict | None:
        with self.conn() as c:
            r = c.execute("SELECT * FROM incidents WHERE id=?", (incident_id,)).fetchone()
        return dict(r) if r else None

    def list_incidents(
        self, *, severity: str | None = None, status: str | None = None,
        classification: str | None = None, search: str | None = None, limit: int = 100
    ) -> list[dict]:
        q, args = "SELECT * FROM incidents WHERE 1=1", []
        if severity:
            q += " AND severity=?"
            args.append(severity)
        if status:
            q += " AND status=?"
            args.append(status)
        if classification:
            if classification == "fire":
                q += " AND classification IN ('fire','fire_smoke')"
            elif classification == "smoke":
                q += " AND classification IN ('smoke','fire_smoke')"
            else:
                q += " AND classification=?"
                args.append(classification)
        if search:
            like = f"%{search.strip()}%"
            q += " AND (title LIKE ? OR id LIKE ? OR IFNULL(location_name,'') LIKE ?)"
            args.extend([like, like, like])
        q += " ORDER BY created_at DESC, rowid DESC LIMIT ?"
        args.append(limit)
        with self.conn() as c:
            return [dict(r) for r in c.execute(q, args).fetchall()]

    def find_active_camera_incident(
        self, camera_id: str, classification: str, detection_mode: str
    ) -> dict | None:
        """Find the latest unresolved alert for this exact camera/class/model."""
        with self.conn() as c:
            row = c.execute(
                "SELECT * FROM incidents WHERE camera_id=? "
                "AND status IN ('new','acknowledged') AND classification=? "
                "AND detection_mode=? ORDER BY created_at DESC, rowid DESC LIMIT 1",
                (camera_id, classification, detection_mode),
            ).fetchone()
        return dict(row) if row else None

    def update_camera_incident_evidence(
        self, incident_id: str, *, severity: str, confidence: float,
        media_path: str, media_note: str, detection_id: str
    ) -> dict | None:
        """Refresh evidence for an unresolved alert when a stronger frame is found."""
        with self.conn() as c:
            c.execute(
                "UPDATE incidents SET severity=?, confidence=?, media_path=?, media_note=?, "
                "detection_id=?, updated_at=? WHERE id=? AND status IN ('new','acknowledged')",
                (severity, confidence, media_path, media_note, detection_id,
                 now_iso(), incident_id),
            )
        return self.get_incident(incident_id)

    def update_incident_status(self, incident_id: str, status: str) -> dict | None:
        with self.conn() as c:
            cur = c.execute(
                "UPDATE incidents SET status=?, updated_at=? WHERE id=?",
                (status, now_iso(), incident_id),
            )
            if cur.rowcount == 0:
                return None
        return self.get_incident(incident_id)

    def delete_incident(self, incident_id: str) -> bool:
        with self.conn() as c:
            c.execute("UPDATE detections SET incident_id=NULL WHERE incident_id=?",
                      (incident_id,))
            cur = c.execute("DELETE FROM incidents WHERE id=?", (incident_id,))
            return cur.rowcount > 0

    def latest_detection_summary(self) -> dict | None:
        with self.conn() as c:
            r = c.execute(
                "SELECT id, classification, confidence, mode, source_video_id, created_at "
                "FROM detections ORDER BY created_at DESC, rowid DESC LIMIT 1").fetchone()
        return dict(r) if r else None

    def referenced_media(self) -> set[str]:
        with self.conn() as c:
            paths = set()
            for row in c.execute("SELECT image_path, annotated_path FROM detections"):
                paths.update(p for p in row if p)
            for row in c.execute("SELECT media_path FROM incidents WHERE media_path IS NOT NULL"):
                paths.add(row[0])
        return paths

    def incident_stats(self) -> dict:
        with self.conn() as c:
            total = c.execute("SELECT COUNT(*) FROM incidents").fetchone()[0]
            active = c.execute(
                "SELECT COUNT(*) FROM incidents WHERE status IN ('new','acknowledged')"
            ).fetchone()[0]
            by_sev = dict(c.execute(
                "SELECT severity, COUNT(*) FROM incidents "
                "WHERE status IN ('new','acknowledged') GROUP BY severity").fetchall())
            last24 = c.execute(
                "SELECT COUNT(*) FROM incidents WHERE created_at >= strftime('%Y-%m-%dT%H:%M:%S','now','-1 day')"
            ).fetchone()[0]
            demo = c.execute("SELECT COUNT(*) FROM incidents WHERE is_demo=1").fetchone()[0]
        return {"total": total, "active": active, "active_by_severity": by_sev,
                "last_24h": last24, "demo": demo}

    # ---------- detections ----------
    def create_detection(self, **fields: Any) -> dict:
        row = {"id": fields.pop("id", None) or new_id("det"), "created_at": now_iso(), **fields}
        row["boxes_json"] = json.dumps(row.pop("boxes", []))
        cols = ",".join(row)
        qs = ",".join("?" for _ in row)
        with self.conn() as c:
            c.execute(f"INSERT INTO detections ({cols}) VALUES ({qs})", list(row.values()))
        return self.get_detection(row["id"])  # type: ignore[return-value]

    def get_detection(self, detection_id: str) -> dict | None:
        with self.conn() as c:
            r = c.execute("SELECT * FROM detections WHERE id=?", (detection_id,)).fetchone()
        if not r:
            return None
        d = dict(r)
        d["boxes"] = json.loads(d.pop("boxes_json") or "[]")
        return d

    def list_detections(self, limit: int = 50) -> list[dict]:
        with self.conn() as c:
            rows = c.execute(
                "SELECT * FROM detections ORDER BY created_at DESC, rowid DESC LIMIT ?",
                (limit,),
            ).fetchall()
        out: list[dict] = []
        for r in rows:
            d = dict(r)
            d["boxes"] = json.loads(d.pop("boxes_json") or "[]")
            out.append(d)
        return out

    def link_detection(self, detection_id: str, incident_id: str) -> None:
        with self.conn() as c:
            c.execute("UPDATE detections SET incident_id=? WHERE id=?", (incident_id, detection_id))

    def detection_stats(self) -> dict:
        with self.conn() as c:
            total = c.execute("SELECT COUNT(*) FROM detections").fetchone()[0]
            by_cls = dict(c.execute(
                "SELECT classification, COUNT(*) FROM detections GROUP BY classification"
            ).fetchall())
            by_mode = dict(c.execute(
                "SELECT mode, COUNT(*) FROM detections GROUP BY mode").fetchall())
            avg_ms = c.execute("SELECT AVG(processing_ms) FROM detections").fetchone()[0]
        return {"total": total, "by_classification": by_cls, "by_mode": by_mode,
                "avg_processing_ms": round(avg_ms) if avg_ms else None}

    # ---------- camera status ----------
    def upsert_camera_status(self, camera_id: str, *, status: str, last_error: str | None,
                             snapshot_path: str | None) -> dict:
        ts = now_iso()
        prev = self.get_camera_status(camera_id) or {}
        last_frame = ts if status == "online" else prev.get("last_frame_at")
        snap = snapshot_path if snapshot_path is not None else prev.get("snapshot_path")
        with self.conn() as c:
            c.execute(
                "INSERT INTO camera_status(camera_id,status,last_checked_at,last_frame_at,"
                "last_error,snapshot_path) VALUES(?,?,?,?,?,?) "
                "ON CONFLICT(camera_id) DO UPDATE SET status=excluded.status, "
                "last_checked_at=excluded.last_checked_at, last_frame_at=excluded.last_frame_at, "
                "last_error=excluded.last_error, snapshot_path=excluded.snapshot_path",
                (camera_id, status, ts, last_frame, last_error, snap),
            )
        return self.get_camera_status(camera_id)  # type: ignore[return-value]

    def get_camera_status(self, camera_id: str) -> dict | None:
        with self.conn() as c:
            r = c.execute("SELECT * FROM camera_status WHERE camera_id=?",
                          (camera_id,)).fetchone()
        return dict(r) if r else None

    def delete_camera_status(self, camera_id: str) -> None:
        with self.conn() as c:
            c.execute("DELETE FROM camera_status WHERE camera_id=?", (camera_id,))

    # ---------- devices ----------
    def upsert_device(self, token: str, name: str | None, platform: str | None) -> int:
        ts = now_iso()
        with self.conn() as c:
            c.execute(
                "INSERT INTO devices(token,name,platform,created_at,updated_at) VALUES(?,?,?,?,?) "
                "ON CONFLICT(token) DO UPDATE SET name=excluded.name, "
                "platform=excluded.platform, updated_at=excluded.updated_at",
                (token, name, platform, ts, ts),
            )
            return c.execute("SELECT COUNT(*) FROM devices").fetchone()[0]

    def device_tokens(self) -> list[str]:
        with self.conn() as c:
            return [r[0] for r in c.execute("SELECT token FROM devices").fetchall()]

    def delete_devices(self, tokens: list[str]) -> None:
        if not tokens:
            return
        with self.conn() as c:
            c.executemany("DELETE FROM devices WHERE token=?", [(t,) for t in tokens])
