"""FireWatch AI — FastAPI приложение."""
from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
import io
import json
import hmac
import logging
import random
import shutil
import time
import uuid
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit, urlunsplit

from fastapi import (BackgroundTasks, FastAPI, File, Form, HTTPException, Query, Request,
                     UploadFile)
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from PIL import Image, ImageDraw, ImageOps
from pydantic import BaseModel, Field

from . import capture, push
from .config import BASE_DIR, Settings, get_settings
from .db import Database, new_id, now_iso
from .demo_assets import BUILTIN_DEMO_VIDEOS_META, ensure_demo_image, ensure_demo_videos
from .detection import build_detector, severity_for
from .schemas import (AnalyzeVideoFrameRequest, Camera, CameraCreate, CameraWithStatus,
                      DemoVideo,
                      DetectionResult, DeviceIn, Incident, IncidentCreate,
                      IncidentStatusUpdate, Severity)

log = logging.getLogger("firewatch")

DEFAULT_LOCATION = {"id": "default", "name": "Зона мониторинга (по умолчанию)",
                    "url": "", "lat": 43.2389, "lon": 76.8897}
SEVERITY_RADIUS_M = {"low": 500, "medium": 1000, "high": 2000, "critical": 3500}
SEVERITY_TITLES = {"low": "Низкий", "medium": "Средний", "high": "Высокий",
                   "critical": "Критический"}


class SimulateRequest(BaseModel):
    camera_id: str | None = None
    severity: Severity = "high"
    capture_from_camera: bool = Field(
        default=False,
        description="Попытаться записать клип с реальной камеры (нужны FFmpeg и интернет). "
                    "При неудаче используется DEMO-ассет.")


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    settings.media_dir.mkdir(parents=True, exist_ok=True)
    (settings.media_dir / "uploads").mkdir(exist_ok=True)
    (settings.media_dir / "clips").mkdir(exist_ok=True)
    media_demo_videos_dir = settings.media_dir / "demo_videos"
    media_demo_videos_dir.mkdir(exist_ok=True)
    (settings.media_dir / "snapshots").mkdir(exist_ok=True)

    scanner_task: asyncio.Task | None = None
    scanner_enabled = False
    scanner_last_error: str | None = None
    scanner_last_run_at: str | None = None
    scanner_current_camera: str | None = None

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        nonlocal scanner_last_error
        if settings.camera_auto_scan_enabled:
            try:
                start_camera_auto_scan(require_cameras=False)
            except HTTPException as exc:
                scanner_last_error = str(exc.detail)
                log.error("Camera auto-scan was not started: %s", scanner_last_error)
        try:
            yield
        finally:
            await stop_camera_auto_scan()

    app = FastAPI(
        title="FireWatch AI API",
        version="1.0.0",
        description="Мониторинг лесных пожаров: инциденты, AI-детекция огня/дыма, "
                    "демо-симуляция, push-уведомления.",
        lifespan=lifespan,
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    @app.middleware("http")
    async def api_key_guard(request: Request, call_next):
        expected = settings.api_access_token
        if expected and request.method != "OPTIONS":
            supplied = request.headers.get("x-api-key", "")
            if not hmac.compare_digest(supplied, expected):
                return JSONResponse(status_code=401, content={"detail": "API key required or invalid"})
        return await call_next(request)

    app.mount("/media", StaticFiles(directory=settings.media_dir), name="media")

    db = Database(settings.database_path)
    detector, detector_fallback_reason = build_detector(settings)
    push.init_firebase(settings.firebase_credentials_path())
    demo_image = ensure_demo_image(settings.demo_assets_dir / "demo_fire.jpg")
    ensure_demo_videos(settings.demo_assets_dir, BASE_DIR / "tests" / "fixtures")

    app.state.settings = settings
    app.state.db = db
    app.state.detector = detector

    # Ограничение одновременных тяжёлых задач (YOLO-инференс / FFmpeg), чтобы не исчерпать RAM.
    heavy_jobs = asyncio.Semaphore(max(1, settings.max_concurrent_jobs))
    duration_cache: dict[tuple[str, float, int], float] = {}

    # ---------------- helpers ----------------
    def video_duration(f: Path) -> float:
        st = f.stat()
        key = (f.name, st.st_mtime, st.st_size)
        if key not in duration_cache:
            duration_cache[key] = capture.probe_video_duration_sync(f)
        return duration_cache[key]

    def sync_demo_videos_dir() -> list[dict]:
        """Синхронизирует MP4 из demo_assets/videos в media/demo_videos и возвращает список DemoVideo."""
        src_dir = settings.demo_assets_dir / "videos"
        if src_dir.exists():
            for src_file in sorted(src_dir.iterdir()):
                if src_file.suffix.lower() in (".mp4", ".mov", ".m4v") and src_file.is_file():
                    dst_file = media_demo_videos_dir / src_file.name
                    if not dst_file.exists():
                        shutil.copy(src_file, dst_file)

        items: list[dict] = []
        for f in sorted(media_demo_videos_dir.iterdir()):
            if not f.is_file() or f.suffix.lower() not in (".mp4", ".mov", ".m4v"):
                continue
            if f.name.endswith(".part.mp4"):
                continue
            meta = BUILTIN_DEMO_VIDEOS_META.get(f.stem)
            dur = video_duration(f)
            if dur <= 0:
                # Повреждённый/нечитаемый файл не показываем как доступное видео
                continue
            if meta:
                items.append(
                    DemoVideo(
                        id=f.stem,
                        title=str(meta["title"]),
                        filename=f.name,
                        video_url=f"/media/demo_videos/{f.name}",
                        duration_sec=dur if dur > 0 else 5.0,
                        description=str(meta["description"]),
                        location_name=str(meta["location_name"]),
                        lat=float(meta["lat"]),
                        lon=float(meta["lon"]),
                        is_demo=True,
                        badge="DEMO VIDEO",
                    ).model_dump()
                )
            else:
                clean_title = f.stem.replace("_", " ").replace("-", " ").strip().title()
                items.append(
                    DemoVideo(
                        id=f.stem,
                        title=f"DEMO VIDEO — {clean_title}",
                        filename=f.name,
                        video_url=f"/media/demo_videos/{f.name}",
                        duration_sec=dur if dur > 0 else 5.0,
                        description="Пользовательский локальный видеоролик для демонстрации FFmpeg + YOLOv8n.",
                        location_name="Локальное демо-видео (Пользовательский файл)",
                        lat=DEFAULT_LOCATION["lat"],
                        lon=DEFAULT_LOCATION["lon"],
                        is_demo=True,
                        badge="DEMO VIDEO",
                    ).model_dump()
                )
        return items

    sync_demo_videos_dir()

    def cleanup_orphan_media(max_age_sec: int = 3600) -> int:
        """Удаляет временные/осиротевшие файлы (упавшие запросы), не связанные с записями SQLite."""
        referenced = db.referenced_media()
        removed = 0
        now = time.time()
        for sub in ("uploads", "snapshots", "demo_videos"):
            for f in (settings.media_dir / sub).glob("*"):
                if not f.is_file():
                    continue
                rel = f"{sub}/{f.name}"
                is_tmp = ".part" in f.name
                orphan = sub == "uploads" and rel not in referenced
                if (is_tmp or orphan) and now - f.stat().st_mtime > max_age_sec:
                    f.unlink(missing_ok=True)
                    removed += 1
        if removed:
            log.info("Cleaned %d orphan/temporary media files", removed)
        return removed

    cleanup_orphan_media()

    def load_cameras() -> dict[str, dict]:
        try:
            data = json.loads(settings.cameras_file.read_text("utf-8"))
            return {c["id"]: Camera(**c).model_dump() for c in data}
        except FileNotFoundError:
            return {}
        except (json.JSONDecodeError, KeyError, TypeError, ValueError) as e:
            log.error("cameras.json invalid: %s", e)
            return {}

    def save_cameras(cams: dict[str, dict]) -> None:
        settings.cameras_file.parent.mkdir(parents=True, exist_ok=True)
        settings.cameras_file.write_text(
            json.dumps(list(cams.values()), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def to_incident(row: dict) -> dict:
        r = dict(row)
        path = r.pop("media_path", None)
        r["media_url"] = f"/media/{path}" if path else None
        r["is_demo"] = bool(r["is_demo"])
        return Incident(**r).model_dump()

    def notify(incident: dict, background: BackgroundTasks) -> None:
        title = f"🔥 FireWatch AI: {incident['title']}"
        body = (f"Угроза: {SEVERITY_TITLES[incident['severity']]}. "
                f"{incident.get('location_name') or ''}").strip()
        data = {"incident_id": incident["id"], "lat": incident["lat"], "lon": incident["lon"],
                "severity": incident["severity"], "is_demo": int(incident["is_demo"])}

        def _send() -> None:
            res = push.send_incident_alert(db.device_tokens(), title, body, data)
            db.delete_devices(res.get("invalid_tokens") or [])
            log.info("push for %s: %s", incident["id"], res)

        background.add_task(_send)

    def annotate(src: Path, dst: Path, boxes: list[dict]) -> None:
        img = Image.open(src).convert("RGB")
        d = ImageDraw.Draw(img)
        lw = max(2, img.width // 300)
        for b in boxes:
            color = (255, 69, 58) if b["label"] == "fire" else (200, 200, 200)
            d.rectangle((b["x1"], b["y1"], b["x2"], b["y2"]), outline=color, width=lw)
            text = f"{b['label']} {b['confidence']:.2f}"
            d.rectangle((b["x1"], max(0, b["y1"] - 16), b["x1"] + 8 * len(text),
                         max(16, b["y1"])), fill=color)
            d.text((b["x1"] + 3, max(0, b["y1"] - 15)), text, fill=(0, 0, 0))
        img.save(dst, "JPEG", quality=88)

    def detector_info() -> dict:
        return {"mode": detector.mode, "provider": detector.provider,
                "model_name": detector.model_name, "disclaimer": detector.disclaimer,
                "fallback_reason": detector_fallback_reason}

    def safe_camera_url(raw_url: str) -> str:
        """Не возвращать RTSP userinfo с логином/паролем в API-ответах."""
        parts = urlsplit(raw_url)
        if not parts.username and not parts.password:
            return raw_url
        host = parts.hostname or ""
        if ":" in host and not host.startswith("["):
            host = f"[{host}]"
        if parts.port:
            host = f"{host}:{parts.port}"
        return urlunsplit((parts.scheme, host, parts.path, parts.query, parts.fragment))

    def camera_with_status(cam: dict) -> dict:
        st = db.get_camera_status(cam["id"]) or {}
        snap = st.get("snapshot_path")
        return {
            **cam,
            "url": safe_camera_url(cam["url"]),
            "status": st.get("status", "unchecked"),
            "last_checked_at": st.get("last_checked_at"),
            "last_frame_at": st.get("last_frame_at"),
            "last_error": st.get("last_error"),
            "snapshot_url": f"/media/{snap}" if snap else None,
        }

    def to_detection_result(r: dict) -> DetectionResult:
        cls = r["classification"]
        return DetectionResult(
            id=r["id"], status=r["status"], mode=r["mode"], provider=r["provider"],
            model_name=r["model_name"], classification=cls,
            fire_detected=cls in ("fire", "fire_smoke"),
            smoke_detected=cls in ("smoke", "fire_smoke"),
            confidence=r["confidence"], boxes=r["boxes"], processing_ms=r["processing_ms"],
            image_url=f"/media/{r['image_path']}",
            annotated_image_url=(f"/media/{r['annotated_path']}"
                                 if r.get("annotated_path") else None),
            disclaimer=detector.disclaimer, incident_id=r.get("incident_id"),
            source_video_id=r.get("source_video_id"),
            frame_timestamp_sec=r.get("frame_timestamp_sec"),
            created_at=r["created_at"],
        )

    async def run_inference(img_path: Path, rel: str):
        """Run the loaded detector without forcing every camera frame into persistent storage."""
        async with heavy_jobs:
            t0 = time.perf_counter()
            try:
                out = await run_in_threadpool(detector.detect, img_path)
            except Exception as e:  # noqa: BLE001
                log.exception("Detection failed for %s", rel)
                raise HTTPException(500, f"Ошибка AI-анализа ({type(e).__name__})")
            ms = int((time.perf_counter() - t0) * 1000)
        return out, ms

    async def persist_detection(img_path: Path, rel: str, det_id: str, out, ms: int, *,
                                source_video_id: str | None = None,
                                frame_ts: float | None = None):
        boxes = [b.__dict__ for b in out.boxes]
        ann_rel = None
        if boxes:
            ann_rel = f"uploads/{det_id}_annotated.jpg"
            await run_in_threadpool(annotate, img_path, settings.media_dir / ann_rel, boxes)
        det = db.create_detection(
            id=det_id, status="completed", mode=detector.mode, provider=detector.provider,
            model_name=detector.model_name, classification=out.classification,
            confidence=out.confidence, boxes=boxes, processing_ms=ms,
            image_path=rel, annotated_path=ann_rel,
            source_video_id=source_video_id, frame_timestamp_sec=frame_ts,
        )
        return det, ann_rel

    async def infer_and_store(img_path: Path, rel: str, det_id: str, *,
                              source_video_id: str | None = None,
                              frame_ts: float | None = None):
        out, ms = await run_inference(img_path, rel)
        det, ann_rel = await persist_detection(
            img_path, rel, det_id, out, ms,
            source_video_id=source_video_id, frame_ts=frame_ts,
        )
        return out, det, ann_rel

    # ---------------- errors ----------------
    @app.exception_handler(Exception)
    async def unhandled(_: Request, exc: Exception):  # pragma: no cover
        log.exception("Unhandled error: %s", exc)
        return JSONResponse(status_code=500, content={"detail": "Внутренняя ошибка сервера"})

    # ---------------- system ----------------
    @app.get("/health", tags=["system"])
    def health():
        db_ok = False
        try:
            db_ok = db.ping()
        except Exception:  # noqa: BLE001
            log.exception("DB ping failed")
        return {
            "status": "ok" if db_ok else "degraded",
            "env_mode": settings.env_mode,
            "database": db_ok,
            "detector": detector_info(),
            "ffmpeg": capture.ffmpeg_available(),
            "firebase": push.status(),
            "camera_auto_scan_enabled": scanner_enabled,
            "camera_auto_scan_active": scanner_task is not None and not scanner_task.done(),
            "camera_auto_scan_interval_sec": settings.camera_auto_scan_interval_sec,
            "camera_auto_scan_last_error": scanner_last_error,
            "camera_auto_scan_last_run_at": scanner_last_run_at,
            "camera_auto_scan_current_camera": scanner_current_camera,
            "cameras_configured": len(load_cameras()),
            "demo_videos_available": len(sync_demo_videos_dir()),
            "devices_registered": len(db.device_tokens()),
            "server_time": now_iso(),
            "network": {
                "lan_ip": settings.lan_ip(),
                "lan_url": settings.lan_base_url(),
                "localhost_url": f"http://127.0.0.1:{settings.port}",
            },
        }


    @app.get("/monitoring/status", tags=["monitoring"])
    def monitoring_status():
        return camera_monitoring_status()

    @app.post("/monitoring/start", tags=["monitoring"])
    async def start_monitoring():
        start_camera_auto_scan(require_cameras=True)
        return camera_monitoring_status()

    @app.post("/monitoring/stop", tags=["monitoring"])
    async def stop_monitoring():
        await stop_camera_auto_scan()
        return camera_monitoring_status()

    @app.get("/network_info", tags=["system"])
    def network_info():
        return {
            "env_mode": settings.env_mode,
            "host": settings.host,
            "port": settings.port,
            "lan_ip": settings.lan_ip(),
            "lan_url": settings.lan_base_url(),
            "localhost_url": f"http://127.0.0.1:{settings.port}",
        }

    @app.get("/camera-candidates", tags=["cameras"])
    def camera_candidates():
        """Unverified public HLS candidates; users must check availability and operator permissions."""
        source_note = (
            "Кандидат из открытых каталогов веб-камер Казахстана. "
            "HLS-адрес найден в опубликованном M3U-списке и не проверен этим сервером. "
            "Перед AI-анализом проверьте доступность и разрешение оператора."
        )
        source_url = "https://cam.xcom.kz/"
        catalog_url = "https://pocketworld.org/ru/webcams/country/kz"
        rows = [
            ("aktau-caspian-14", "Актау — Каспий, 14-й микрорайон",
             "https://cam.xcom.kz:8081/caspy14/tracks-v1/mono.m3u8", 43.6545, 51.1385),
            ("aktau-caspian-15", "Актау — Каспий, 15-й микрорайон",
             "https://cam.xcom.kz:8081/caspy15/tracks-v1/mono.m3u8", 43.6560, 51.1375),
            ("aktau-caspian-4", "Актау — Каспий, 4-й микрорайон",
             "https://cam.xcom.kz:8081/caspy4/tracks-v1/mono.m3u8", 43.6364, 51.1551),
            ("aktau-yntymak", "Актау — площадь Ынтымак",
             "https://cam.xcom.kz:8081/yntymak/tracks-v1/mono.m3u8", 43.6445, 51.1530),
            ("aktau-drama", "Актау — драматический театр",
             "https://cam.xcom.kz:8081/dramteatr/tracks-v1/mono.m3u8", 43.6397, 51.1521),
            ("aktau-13-microdistrict", "Актау — 13-й микрорайон",
             "https://cam.xcom.kz:8081/13-1/tracks-v1/index.m3u8", 43.6315, 51.1595),
        ]
        return [
            {"id": item[0], "name": item[1], "url": item[2], "lat": item[3],
             "lon": item[4], "source_name": "XCOM Aktau",
             "source_url": source_url, "catalog_url": catalog_url,
             "verification_note": source_note, "verified": False}
            for item in rows
        ]

    # ---------------- cameras (только реально добавленные RTSP/HLS) ----------------
    @app.get("/cameras", tags=["cameras"], response_model=list[CameraWithStatus])
    def cameras():
        return [camera_with_status(c) for c in load_cameras().values()]

    @app.post("/cameras", tags=["cameras"], response_model=CameraWithStatus, status_code=201)
    def add_camera(body: CameraCreate):
        url = body.url.strip()
        if not url.lower().startswith(("rtsp://", "rtsps://", "http://", "https://")):
            raise HTTPException(422, "URL камеры должен начинаться с rtsp://, rtsps://, http:// или https://")
        cams = load_cameras()
        cam_id = (body.id or new_id("cam")).strip()
        if cam_id in cams:
            raise HTTPException(409, f"Камера с id '{cam_id}' уже существует")
        cam = Camera(id=cam_id, name=body.name.strip(), url=url,
                     lat=body.lat, lon=body.lon).model_dump()
        cams[cam_id] = cam
        save_cameras(cams)
        return camera_with_status(cam)

    @app.delete("/cameras/{camera_id}", tags=["cameras"])
    def delete_camera(camera_id: str):
        cams = load_cameras()
        if camera_id not in cams:
            raise HTTPException(404, "Камера не найдена")
        cams.pop(camera_id)
        save_cameras(cams)
        db.delete_camera_status(camera_id)
        return {"ok": True, "deleted": camera_id, "remaining": len(cams)}

    @app.post("/cameras/{camera_id}/check", tags=["cameras"], response_model=CameraWithStatus)
    async def check_camera(camera_id: str):
        """Реальная проверка потока: FFmpeg пытается получить один кадр (таймаут 15 c)."""
        cams = load_cameras()
        cam = cams.get(camera_id)
        if not cam:
            raise HTTPException(404, "Камера не найдена")
        rel = f"snapshots/{camera_id}.jpg"
        tmp = settings.media_dir / f"snapshots/{camera_id}.{uuid.uuid4().hex[:6]}.part.jpg"
        async with heavy_jobs:
            try:
                await capture.grab_stream_frame(cam["url"], tmp, timeout=15)
                tmp.replace(settings.media_dir / rel)
                db.upsert_camera_status(camera_id, status="online", last_error=None,
                                        snapshot_path=rel)
            except capture.CaptureError as e:
                tmp.unlink(missing_ok=True)
                db.upsert_camera_status(camera_id, status="offline", last_error=str(e)[:300],
                                        snapshot_path=None)
        return camera_with_status(cam)

    @app.post("/cameras/{camera_id}/analyze", tags=["cameras"], response_model=DetectionResult)
    async def analyze_camera_frame(camera_id: str, background: BackgroundTasks):
        """Захватить текущий кадр разрешённой камеры и проанализировать его текущим детектором."""
        cams = load_cameras()
        cam = cams.get(camera_id)
        if not cam:
            raise HTTPException(404, "Камера не найдена")

        det_id = new_id("det")
        rel = f"uploads/{det_id}_camera.jpg"
        img_path = settings.media_dir / rel
        try:
            async with heavy_jobs:
                await capture.grab_stream_frame(cam["url"], img_path, timeout=20)
            db.upsert_camera_status(camera_id, status="online", last_error=None,
                                    snapshot_path=None)
            out, det, ann_rel = await infer_and_store(img_path, rel, det_id)
        except capture.CaptureError as e:
            img_path.unlink(missing_ok=True)
            db.upsert_camera_status(camera_id, status="offline", last_error=str(e)[:300],
                                    snapshot_path=None)
            raise HTTPException(502, f"Не удалось получить кадр камеры: {e}")

        incident_id = None
        if out.classification != "none":
            existing = db.find_active_camera_incident(
                camera_id, out.classification, det["mode"]
            )
            if existing:
                # Сохраняем новую детекцию, но не плодим одинаковые активные тревоги.
                db.link_detection(det_id, existing["id"])
                incident_id = existing["id"]
            else:
                cls_ru = {"fire": "огонь", "smoke": "дым", "fire_smoke": "огонь и дым"}
                row = db.create_incident(
                    title=f"Камера «{cam['name']}»: обнаружены {cls_ru[out.classification]}",
                    description="Автоматически создано после анализа одного кадра камеры. "
                                "Требуется проверка оператором.",
                    source="camera", camera_id=camera_id,
                    location_name=cam["name"], lat=cam["lat"], lon=cam["lon"],
                    severity=severity_for(out.classification, out.confidence),
                    classification=out.classification, confidence=out.confidence,
                    detection_mode=det["mode"], media_type="image",
                    media_path=ann_rel or rel,
                    media_note=("Кадр получен из подключённого видеопотока. "
                                "Демо-эвристика не является подтверждённым обнаружением."
                                if det["mode"] != "real_model" else
                                "Кадр из видеопотока, проанализированный YOLO. Требуется подтверждение человеком."),
                    is_demo=det["mode"] != "real_model", detection_id=det_id,
                )
                db.link_detection(det_id, row["id"])
                incident_id = row["id"]
                if det["mode"] == "real_model":
                    notify(to_incident(row), background)
                det = db.get_detection(det_id) or det

        result = to_detection_result(det)
        result.incident_id = incident_id
        return result

    @app.get("/stats", tags=["system"])
    def stats():
        inc = db.incident_stats()
        det = db.detection_stats()
        by_cls = det.get("by_classification", {})
        cams = load_cameras().values()
        return {
            "incidents": inc,
            "detections": det,
            "fire_detections": by_cls.get("fire", 0) + by_cls.get("fire_smoke", 0),
            "smoke_detections": by_cls.get("smoke", 0) + by_cls.get("fire_smoke", 0),
            "clear_detections": by_cls.get("none", 0),
            "latest_detection": db.latest_detection_summary(),
            "high_risk_zones": len(compute_risk_zones()),
            "cameras_configured": len(cams),
            "cameras_online": sum(
                1 for c in cams if (db.get_camera_status(c["id"]) or {}).get("status") == "online"),
            "demo_videos_available": len(sync_demo_videos_dir()),
            "devices_registered": len(db.device_tokens()),
            "detector": detector_info(),
            "firebase": push.status(),
        }

    def compute_risk_zones() -> list[dict]:
        """Зоны риска = активные инциденты high/critical, сгруппированные по сетке ~5 км."""
        zones: dict[tuple[int, int], dict] = {}
        for r in db.list_incidents(limit=500):
            if r["status"] not in ("new", "acknowledged") or r["severity"] not in (
                    "high", "critical"):
                continue
            key = (round(r["lat"] / 0.05), round(r["lon"] / 0.05))
            z = zones.setdefault(key, {"lats": [], "lons": [], "severity": "high", "ids": [],
                                       "demo": True})
            z["lats"].append(r["lat"])
            z["lons"].append(r["lon"])
            z["ids"].append(r["id"])
            z["demo"] = z["demo"] and bool(r["is_demo"])
            if r["severity"] == "critical":
                z["severity"] = "critical"
        out = []
        for z in zones.values():
            n = len(z["ids"])
            out.append({
                "lat": sum(z["lats"]) / n, "lon": sum(z["lons"]) / n,
                "severity": z["severity"],
                "radius_m": SEVERITY_RADIUS_M[z["severity"]] + 300 * (n - 1),
                "incident_count": n, "incident_ids": z["ids"], "is_demo": z["demo"],
            })
        return out

    @app.get("/risk_zones", tags=["incidents"])
    def risk_zones():
        """Производные зоны риска по активным инцидентам High/Critical (не прогноз)."""
        return compute_risk_zones()

    # ---------------- incidents ----------------
    @app.get("/incidents", tags=["incidents"], response_model=list[Incident])
    def list_incidents(
        severity: Severity | None = None,
        status: str | None = Query(default=None,
                                   pattern="^(new|acknowledged|resolved|false_alarm)$"),
        type: str | None = Query(default=None, pattern="^(fire|smoke|fire_smoke|none)$"),
        q: str | None = Query(default=None, max_length=100),
        limit: int = Query(default=100, ge=1, le=500),
    ):
        return [to_incident(r) for r in db.list_incidents(
            severity=severity, status=status, classification=type, search=q, limit=limit)]

    @app.get("/incidents/{incident_id}", tags=["incidents"], response_model=Incident)
    def get_incident(incident_id: str):
        row = db.get_incident(incident_id)
        if not row:
            raise HTTPException(404, "Инцидент не найден")
        return to_incident(row)

    def incident_fields_from_detection(det: dict) -> dict[str, Any]:
        vid = det.get("source_video_id")
        ts = det.get("frame_timestamp_sec")
        model_note = ("нейросеть YOLOv8n" if det["mode"] == "real_model"
                      else "DEMO-эвристика (не нейросеть)")
        if vid:
            note = f"DEMO VIDEO «{vid}», кадр {ts or 0:.1f} c — проанализирован: {model_note}"
        else:
            note = f"Фото, проанализированное: {model_note}"
        return dict(
            source="detection", detection_id=det["id"], detection_mode=det["mode"],
            classification=det["classification"], confidence=det["confidence"],
            media_type="image", media_path=det["annotated_path"] or det["image_path"],
            media_note=note, is_demo=bool(vid) or det["mode"] != "real_model",
            camera_id=f"demo_video:{vid}" if vid else None,
        )

    @app.post("/incidents", tags=["incidents"], response_model=Incident, status_code=201)
    def create_incident(body: IncidentCreate, background: BackgroundTasks,
                        response: Response):
        fields: dict[str, Any] = {
            "title": body.title, "description": body.description, "source": "manual",
            "camera_id": body.camera_id, "location_name": body.location_name,
            "lat": body.lat, "lon": body.lon, "severity": body.severity,
            "classification": body.classification, "confidence": body.confidence,
            "detection_mode": "manual", "is_demo": False,
        }
        if body.detection_id:
            det = db.get_detection(body.detection_id)
            if not det:
                raise HTTPException(404, "Детекция не найдена")
            # Идемпотентность: повторное нажатие не создаёт дубликат инцидента
            if det.get("incident_id") and db.get_incident(det["incident_id"]):
                response.status_code = 200
                return to_incident(db.get_incident(det["incident_id"]))  # type: ignore[arg-type]
            fields.update(incident_fields_from_detection(det))
        row = db.create_incident(**fields)
        if body.detection_id:
            db.link_detection(body.detection_id, row["id"])
        inc = to_incident(row)
        if not inc["is_demo"]:
            notify(inc, background)
        return inc

    @app.patch("/incidents/{incident_id}/status", tags=["incidents"], response_model=Incident)
    def update_status(incident_id: str, body: IncidentStatusUpdate):
        row = db.update_incident_status(incident_id, body.status)
        if not row:
            raise HTTPException(404, "Инцидент не найден")
        return to_incident(row)

    @app.delete("/incidents/{incident_id}", tags=["incidents"])
    def delete_incident(incident_id: str):
        if not db.delete_incident(incident_id):
            raise HTTPException(404, "Инцидент не найден")
        return {"ok": True, "deleted": incident_id}

    # ---------------- detection ----------------
    @app.post("/detect", tags=["detection"], response_model=DetectionResult)
    async def detect(
        background: BackgroundTasks,
        file: UploadFile = File(..., description="JPEG/PNG/WebP/HEIC изображение"),
        save_incident: bool = Form(False),
        lat: float | None = Form(None, ge=-90, le=90),
        lon: float | None = Form(None, ge=-180, le=180),
        location_name: str | None = Form(None, max_length=200),
    ):
        raw = await file.read(settings.max_upload_mb * 1024 * 1024 + 1)
        if not raw:
            raise HTTPException(400, "Пустой файл")
        if len(raw) > settings.max_upload_mb * 1024 * 1024:
            raise HTTPException(413, f"Файл больше {settings.max_upload_mb} МБ")
        try:
            img = Image.open(io.BytesIO(raw))
            img = ImageOps.exif_transpose(img).convert("RGB")
            # Большие фото уменьшаем — YOLO всё равно работает на 640px, экономим RAM/диск
            img.thumbnail((1920, 1920))
        except Exception:  # noqa: BLE001 — UnidentifiedImageError, OSError, HEIF-плагины
            raise HTTPException(415, "Файл не является поддерживаемым изображением")

        det_id = new_id("det")
        rel = f"uploads/{det_id}.jpg"
        img_path = settings.media_dir / rel
        img.save(img_path, "JPEG", quality=90)

        out, det, ann_rel = await infer_and_store(img_path, rel, det_id)

        incident_id = None
        if save_incident and out.classification != "none":
            cls_ru = {"fire": "огонь", "smoke": "дым", "fire_smoke": "огонь и дым"}
            row = db.create_incident(
                title=f"AI-детекция: {cls_ru[out.classification]}",
                source="detection", lat=lat if lat is not None else DEFAULT_LOCATION["lat"],
                lon=lon if lon is not None else DEFAULT_LOCATION["lon"],
                location_name=location_name or ("Координаты не переданы — зона по умолчанию"
                                                if lat is None else None),
                severity=severity_for(out.classification, out.confidence),
                **{k: v for k, v in incident_fields_from_detection(det).items()
                   if k not in ("source",)},
            )
            db.link_detection(det_id, row["id"])
            incident_id = row["id"]
            # Heuristic/demo results remain visible in-app but never trigger emergency push alerts.
            if not bool(row.get("is_demo")):
                notify(to_incident(row), background)
            det = db.get_detection(det_id) or det

        res = to_detection_result(det)
        res.incident_id = incident_id or res.incident_id
        return res

    @app.get("/detections", tags=["detection"], response_model=list[DetectionResult])
    def list_detections(limit: int = Query(default=30, ge=1, le=200)):
        return [to_detection_result(r) for r in db.list_detections(limit=limit)]

    @app.get("/detections/{detection_id}", tags=["detection"], response_model=DetectionResult)
    def get_detection(detection_id: str):
        r = db.get_detection(detection_id)
        if not r:
            raise HTTPException(404, "Детекция не найдена")
        return to_detection_result(r)

    # ---------------- local video demo ----------------
    @app.get("/demo_videos", tags=["demo"], response_model=list[DemoVideo])
    def get_demo_videos():
        """Список предзаписанных локальных DEMO VIDEO (MP4/MOV) для демонстрации без живых камер."""
        return sync_demo_videos_dir()

    @app.post("/demo_videos/upload", tags=["demo"], response_model=DemoVideo, status_code=201)
    async def upload_demo_video(
        file: UploadFile = File(..., description="MP4/MOV видеофайл для локальной демонстрации"),
    ):
        orig_name = Path(file.filename or "uploaded_demo.mp4").name
        suffix = Path(orig_name).suffix.lower()
        if suffix not in (".mp4", ".mov", ".m4v"):
            raise HTTPException(415, "Поддерживаются только видеофайлы .mp4, .mov, .m4v")
        if not capture.ffmpeg_available():
            raise HTTPException(503, "FFmpeg не установлен на Mac. Выполните: brew install ffmpeg")

        safe_stem = "".join(c if (c.isalnum() or c in ("_", "-")) else "_"
                            for c in Path(orig_name).stem)[:28] or "video"
        vid_id = f"custom_{safe_stem}_{uuid.uuid4().hex[:6]}"
        dst_path = media_demo_videos_dir / f"{vid_id}{suffix}"
        tmp_path = media_demo_videos_dir / f"{vid_id}.part{suffix}.tmp"
        max_bytes = settings.max_video_upload_mb * 1024 * 1024
        written = 0
        try:
            with tmp_path.open("wb") as fh:
                while chunk := await file.read(1024 * 1024):
                    written += len(chunk)
                    if written > max_bytes:
                        raise HTTPException(
                            413, f"Видео больше {settings.max_video_upload_mb} МБ")
                    fh.write(chunk)
            if written == 0:
                raise HTTPException(400, "Пустой видеофайл")
            dur = await run_in_threadpool(capture.probe_video_duration_sync, tmp_path)
            if dur <= 0:
                raise HTTPException(
                    415, "FFmpeg не смог прочитать видео (файл повреждён или кодек не поддерживается)")
            tmp_path.replace(dst_path)
        finally:
            tmp_path.unlink(missing_ok=True)

        return DemoVideo(
            id=vid_id,
            title=f"DEMO VIDEO — {safe_stem.replace('_', ' ').title()}",
            filename=dst_path.name,
            video_url=f"/media/demo_videos/{dst_path.name}",
            duration_sec=dur,
            description="Загруженный пользователем локальный видеоролик (DEMO VIDEO).",
            location_name="Локальное демо-видео (координаты не известны)",
            lat=DEFAULT_LOCATION["lat"],
            lon=DEFAULT_LOCATION["lon"],
            is_demo=True,
            badge="DEMO VIDEO",
        )

    @app.delete("/demo_videos/{video_id}", tags=["demo"])
    def delete_demo_video(video_id: str):
        """Удалить только загруженные пользователем видео (встроенные защищены)."""
        if not video_id.startswith("custom_"):
            raise HTTPException(403, "Встроенные DEMO-видео удалить нельзя")
        videos = {v["id"]: v for v in sync_demo_videos_dir()}
        if video_id not in videos:
            raise HTTPException(404, "Демо-видео не найдено")
        (media_demo_videos_dir / videos[video_id]["filename"]).unlink(missing_ok=True)
        return {"ok": True, "deleted": video_id}

    @app.post("/demo_videos/{video_id}/analyze_frame", tags=["demo"],
              response_model=DetectionResult)
    async def analyze_demo_video_frame(
        video_id: str,
        background: BackgroundTasks,
        body: AnalyzeVideoFrameRequest | None = None,
    ):
        """Извлекает кадр из локального DEMO VIDEO через FFmpeg и запускает реальную YOLOv8n."""
        body = body or AnalyzeVideoFrameRequest()
        if not capture.ffmpeg_available():
            raise HTTPException(503, "FFmpeg не установлен на Mac. Выполните: brew install ffmpeg")
        videos = {v["id"]: v for v in sync_demo_videos_dir()}
        if video_id not in videos:
            raise HTTPException(404, f"Демо-видео '{video_id}' не найдено")

        vmeta = videos[video_id]
        video_path = media_demo_videos_dir / vmeta["filename"]
        if not video_path.exists():
            raise HTTPException(404, "Файл демо-видео отсутствует на диске")

        duration = float(vmeta["duration_sec"])
        if body.timestamp_sec > duration + 0.5:
            raise HTTPException(
                422, f"timestamp_sec={body.timestamp_sec} больше длительности видео ({duration} c)")
        ts = round(min(max(0.0, float(body.timestamp_sec)), max(0.0, duration - 0.15)), 2)

        det_id = new_id("det")
        rel = f"uploads/{det_id}.jpg"
        img_path = settings.media_dir / rel

        async with heavy_jobs:
            try:
                await run_in_threadpool(capture.extract_frame_sync, video_path, ts, img_path)
            except capture.CaptureError as e:
                img_path.unlink(missing_ok=True)
                raise HTTPException(422, f"Ошибка извлечения кадра FFmpeg: {e}")

        out, det, ann_rel = await infer_and_store(
            img_path, rel, det_id, source_video_id=video_id, frame_ts=ts)

        if body.save_incident and out.classification != "none":
            cls_ru = {"fire": "огонь", "smoke": "дым", "fire_smoke": "огонь и дым"}
            row = db.create_incident(
                title=f"DEMO VIDEO AI: {cls_ru[out.classification]} — {vmeta['title']}",
                description=f"Кадр на {ts:.1f} c из предзаписанного ролика «{vmeta['title']}», "
                            f"проанализирован моделью {detector.model_name}.",
                lat=body.lat if body.lat is not None else float(vmeta["lat"]),
                lon=body.lon if body.lon is not None else float(vmeta["lon"]),
                location_name=body.location_name or f"{vmeta['location_name']} [DEMO VIDEO]",
                severity=severity_for(out.classification, out.confidence),
                **incident_fields_from_detection(det),
            )
            db.link_detection(det_id, row["id"])
            # DEMO VIDEO events are intentionally not sent as fire push alerts.
            det = db.get_detection(det_id) or det

        return to_detection_result(det)

    # ---------------- devices ----------------
    @app.post("/register_device", tags=["push"])
    def register_device(body: DeviceIn):
        count = db.upsert_device(body.token, body.name, body.platform)
        return {"ok": True, "devices": count, "firebase": push.status()}

    # ---------------- simulation ----------------
    @app.post("/simulate_fire", tags=["demo"], response_model=Incident, status_code=201)
    async def simulate_fire(background: BackgroundTasks, body: SimulateRequest | None = None):
        """DEMO: создаёт СИМУЛИРОВАННЫЙ инцидент (is_demo=true). Не реальное обнаружение."""
        body = body or SimulateRequest()
        cams = load_cameras()
        if body.camera_id and body.camera_id not in cams:
            raise HTTPException(404, f"Неизвестная камера. Доступны: {list(cams)}")
        cam = cams.get(body.camera_id or settings.default_camera_id) or \
            (next(iter(cams.values())) if cams else DEFAULT_LOCATION)

        inc_id = new_id("inc")
        media_type, media_path, note = "image", None, None

        if body.capture_from_camera and cam.get("url"):
            clip_rel = f"clips/{inc_id}.mp4"
            try:
                await capture.record_clip(cam["url"], settings.media_dir / clip_rel,
                                          settings.clip_seconds)
                media_type, media_path = "video", clip_rel
                note = (f"Реальная запись {settings.clip_seconds} c с камеры «{cam['name']}». "
                        "Пожар на ней СИМУЛИРОВАН (кадры не содержат реального возгорания).")
            except capture.CaptureError as e:
                log.warning("Camera capture failed, using demo asset: %s", e)
                try:
                    await capture.generate_fallback_clip(
                        settings.media_dir / clip_rel, settings.clip_seconds, cam["id"],
                        image=demo_image)
                    media_type, media_path = "video", clip_rel
                    note = f"DEMO-ролик (камера недоступна: {str(e)[:120]})"
                except capture.CaptureError:
                    pass

        if media_path is None:
            img_rel = f"clips/{inc_id}.jpg"
            shutil.copy(demo_image, settings.media_dir / img_rel)
            media_type, media_path = "image", img_rel
            note = note or "DEMO-изображение (нарисованная заглушка, не кадр камеры)"

        # Небольшое смещение, чтобы маркеры повторных симуляций не накладывались
        lat = cam["lat"] + random.uniform(-0.02, 0.02)
        lon = cam["lon"] + random.uniform(-0.02, 0.02)
        row = db.create_incident(
            id=inc_id, title=f"Симуляция: возгорание — {cam['name']}",
            description="Демонстрационный инцидент, созданный кнопкой «Симулировать пожар». "
                        "Не является реальным обнаружением.",
            source="simulation", camera_id=cam["id"] if cam["id"] != "default" else None,
            location_name=cam["name"], lat=round(lat, 6), lon=round(lon, 6),
            severity=body.severity, classification="fire", confidence=None,
            detection_mode="simulated", media_type=media_type, media_path=media_path,
            media_note=note, is_demo=True,
        )
        # Simulated incidents are visible in-app but never trigger emergency push alerts.
        inc = to_incident(row)
        return inc

    @app.get("/demo_samples/{kind}", tags=["demo"])
    def demo_sample(kind: str):
        """Тестовые изображения для проверки /detect из iOS Simulator (fire | clear)."""
        if kind == "fire":
            p = BASE_DIR / "demo_assets" / "sample_fire.jpg"
            return FileResponse(p if p.exists() else demo_image, media_type="image/jpeg")
        if kind == "clear":
            p = BASE_DIR / "demo_assets" / "sample_clear.jpg"
            if p.exists():
                return FileResponse(p, media_type="image/jpeg")
        raise HTTPException(404, "Доступны образцы: fire, clear")

    # ---------------- web control panel ----------------
    @app.get("/", response_class=HTMLResponse, include_in_schema=False)
    def control_panel():
        options = "".join(f'<option value="{c["id"]}">{c["name"]}</option>'
                          for c in load_cameras().values())
        return _PANEL_HTML.replace("{{OPTIONS}}", options)

    def camera_monitoring_status() -> dict:
        return {
            "enabled": scanner_enabled,
            "active": scanner_task is not None and not scanner_task.done(),
            "interval_sec": settings.camera_auto_scan_interval_sec,
            "last_error": scanner_last_error,
            "last_run_at": scanner_last_run_at,
            "current_camera": scanner_current_camera,
            "detector_mode": detector.mode,
            "ffmpeg_available": capture.ffmpeg_available(),
            "cameras_configured": len(load_cameras()),
        }

    def start_camera_auto_scan(*, require_cameras: bool) -> None:
        nonlocal scanner_task, scanner_enabled, scanner_last_error
        if detector.mode != "real_model":
            raise HTTPException(409, "Автомониторинг доступен только при загруженной реальной YOLO-модели. Сейчас активен DEMO-режим.")
        if not capture.ffmpeg_available():
            raise HTTPException(503, "Для мониторинга камер установите FFmpeg на сервер.")
        if require_cameras and not load_cameras():
            raise HTTPException(409, "Сначала добавьте хотя бы одну камеру и проверьте её подключение.")
        if scanner_task is not None and not scanner_task.done():
            scanner_enabled = True
            scanner_last_error = None
            return
        scanner_enabled = True
        scanner_last_error = None
        scanner_task = asyncio.create_task(camera_auto_scan_loop())
        log.warning("Camera auto-scan started: interval=%ss cameras=%s",
                    settings.camera_auto_scan_interval_sec, len(load_cameras()))

    async def stop_camera_auto_scan() -> None:
        nonlocal scanner_task, scanner_enabled, scanner_current_camera
        scanner_enabled = False
        task = scanner_task
        if task is not None:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
            scanner_task = None
        scanner_current_camera = None
        log.info("Camera auto-scan stopped")

    async def scan_camera_once(camera_id: str, background: BackgroundTasks) -> None:
        """Analyze one live frame; persist only new alerts or stronger evidence."""
        cam = load_cameras().get(camera_id)
        if not cam:
            return
        det_id = new_id("det")
        rel = f"uploads/{det_id}_camera.jpg"
        img_path = settings.media_dir / rel
        try:
            async with heavy_jobs:
                await capture.grab_stream_frame(cam["url"], img_path, timeout=20)
            db.upsert_camera_status(camera_id, status="online", last_error=None,
                                    snapshot_path=None)
            out, processing_ms = await run_inference(img_path, rel)
        except capture.CaptureError as exc:
            img_path.unlink(missing_ok=True)
            db.upsert_camera_status(camera_id, status="offline", last_error=str(exc)[:300],
                                    snapshot_path=None)
            raise HTTPException(502, f"Не удалось получить кадр камеры: {exc}")
        except Exception:
            img_path.unlink(missing_ok=True)
            raise

        if out.classification == "none":
            img_path.unlink(missing_ok=True)
            return

        severity = severity_for(out.classification, out.confidence)
        existing = db.find_active_camera_incident(camera_id, out.classification, detector.mode)
        if existing:
            old_confidence = float(existing.get("confidence") or 0.0)
            order = {"low": 0, "medium": 1, "high": 2, "critical": 3}
            old_severity = existing["severity"]
            if out.confidence <= old_confidence and order[severity] <= order[old_severity]:
                img_path.unlink(missing_ok=True)
                return

            det, ann_rel = await persist_detection(img_path, rel, det_id, out, processing_ms)
            db.link_detection(det_id, existing["id"])
            stronger_severity = severity if order[severity] > order[old_severity] else old_severity
            updated = db.update_camera_incident_evidence(
                existing["id"],
                severity=stronger_severity,
                confidence=max(old_confidence, out.confidence),
                media_path=ann_rel or rel,
                media_note="Обновлено по более уверенному кадру автоматического мониторинга. Требуется подтверждение оператором.",
                detection_id=det_id,
            )
            if updated and order[stronger_severity] > order[old_severity]:
                notify(to_incident(updated), background)
            return

        det, ann_rel = await persist_detection(img_path, rel, det_id, out, processing_ms)
        cls_ru = {"fire": "огонь", "smoke": "дым", "fire_smoke": "огонь и дым"}
        row = db.create_incident(
            title=f"Камера «{cam['name']}»: обнаружены {cls_ru[out.classification]}",
            description="Автоматический анализ видеопотока обнаружил признаки огня или дыма. Требуется обязательная проверка оператором.",
            source="camera", camera_id=camera_id,
            location_name=cam["name"], lat=cam["lat"], lon=cam["lon"],
            severity=severity, classification=out.classification,
            confidence=out.confidence, detection_mode=det["mode"],
            media_type="image", media_path=ann_rel or rel,
            media_note="Кадр из видеопотока, проанализированный реальной YOLO-моделью. Результат требует проверки человеком.",
            is_demo=False, detection_id=det_id,
        )
        db.link_detection(det_id, row["id"])
        notify(to_incident(row), background)

    async def camera_auto_scan_loop() -> None:
        """Периодически проверяет все разрешённые камеры реальной YOLO-моделью."""
        nonlocal scanner_last_error, scanner_last_run_at, scanner_current_camera
        while scanner_enabled:
            cameras_snapshot = list(load_cameras().values())
            for cam in cameras_snapshot:
                if not scanner_enabled:
                    return
                scanner_current_camera = cam["name"]
                background = BackgroundTasks()
                try:
                    # Дедупликация выполняется при создании инцидента, поэтому сканируем
                    # камеру и после тревоги: это позволяет заметить изменение smoke -> fire.
                    await scan_camera_once(cam["id"], background)
                    await background()
                    scanner_last_error = None
                    scanner_last_run_at = now_iso()
                except HTTPException as exc:
                    scanner_last_error = f"{cam['name']}: {exc.detail}"[:500]
                    scanner_last_run_at = now_iso()
                    log.warning("Auto-scan camera %s skipped: %s", cam["id"], exc.detail)
                except asyncio.CancelledError:
                    raise
                except Exception as exc:
                    scanner_last_error = f"{cam['name']}: {type(exc).__name__}"[:500]
                    scanner_last_run_at = now_iso()
                    log.exception("Auto-scan camera %s failed", cam["id"])
                finally:
                    scanner_current_camera = None
            if scanner_enabled:
                await asyncio.sleep(settings.camera_auto_scan_interval_sec)

    return app


_PANEL_HTML = """<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>FireWatch AI — пульт</title>
<style>body{font-family:-apple-system,sans-serif;background:#101318;color:#F5F7FA;max-width:680px;margin:32px auto;padding:0 16px}
select,button,label{font-size:17px;display:block;width:100%;margin:6px 0}select,button{padding:12px;border-radius:12px;border:0}
select{background:#1C2330;color:#F5F7FA}button{background:#FF453A;color:#fff;font-weight:700;cursor:pointer}
button:disabled{opacity:.5}pre{background:#1C2330;padding:12px;border-radius:12px;white-space:pre-wrap;font-size:13px}
.tag{background:#5B9BFF;color:#fff;padding:2px 8px;border-radius:6px;font-size:12px}a{color:#5B9BFF}
img,video{width:100%;border-radius:12px;margin-top:10px}</style></head><body>
<h1>🔥 FireWatch AI <span class="tag">DEMO MODE</span></h1>
<p>Создаёт <b>симулированный</b> инцидент. <a href="/docs">Swagger API</a></p>
<label>Камера / зона<select id="cam">{{OPTIONS}}</select></label>
<label>Уровень угрозы<select id="sev"><option>high</option><option>critical</option><option>medium</option><option>low</option></select></label>
<label><input type="checkbox" id="cap" style="width:auto;display:inline"> Записать 5 c с реальной камеры (FFmpeg + интернет)</label>
<button id="go">СИМУЛИРОВАТЬ ПОЖАР</button><pre id="out">…</pre><div id="media"></div>
<script>
const out=document.getElementById('out'),go=document.getElementById('go'),media=document.getElementById('media');
fetch('/health').then(r=>r.json()).then(h=>out.textContent=JSON.stringify(h,null,2));
go.onclick=async()=>{go.disabled=true;out.textContent='Создаю инцидент…';
 try{const r=await fetch('/simulate_fire',{method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify({camera_id:cam.value||null,severity:sev.value,capture_from_camera:cap.checked})});
  const j=await r.json();out.textContent=JSON.stringify(j,null,2);
  if(j.media_url){media.innerHTML=j.media_type==='video'?`<video src="${j.media_url}" controls autoplay muted loop playsinline></video>`:`<img src="${j.media_url}">`;}
 }catch(e){out.textContent='Ошибка: '+e}go.disabled=false;};
</script></body></html>"""

