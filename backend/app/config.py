"""Конфигурация из переменных окружения / backend/.env (Local Development vs Production)."""
from __future__ import annotations

import os
import socket
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")


def _path(value: str) -> Path:
    p = Path(value)
    return p if p.is_absolute() else (BASE_DIR / p).resolve()


def detect_mac_lan_ip() -> str:
    """Определить текущий Wi-Fi/LAN IP на Mac, игнорируя виртуальные и туннельные интерфейсы."""
    override = os.getenv("MAC_LAN_IP", "").strip()
    if override:
        return override

    # 1. Приоритет: физические интерфейсы macOS Wi-Fi / Ethernet (en0, en1)
    for iface in ("en0", "en1"):
        try:
            res = subprocess.run(
                ["ipconfig", "getifaddr", iface],
                capture_output=True,
                text=True,
                timeout=1.5,
                check=False,
            )
            ip = res.stdout.strip()
            if ip and not ip.startswith("127.") and not ip.startswith("169.254."):
                return ip
        except Exception:
            pass

    # 2. Fallback через UDP-маршрут по умолчанию (без отправки пакетов)
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.168.1.1", 80))
            ip = s.getsockname()[0]
            if ip and not ip.startswith("127.") and not ip.startswith("169.254."):
                return ip
    except Exception:
        pass

    return "127.0.0.1"


@dataclass
class Settings:
    env_mode: str = field(
        default_factory=lambda: os.getenv("ENV_MODE", "local_dev").strip().lower()
    )
    host: str = field(default_factory=lambda: os.getenv("HOST", "0.0.0.0").strip())
    api_access_token: str = field(default_factory=lambda: os.getenv("API_ACCESS_TOKEN", "").strip())
    camera_auto_scan_enabled: bool = field(
        default_factory=lambda: os.getenv("CAMERA_AUTO_SCAN_ENABLED", "false").strip().lower()
        in ("1", "true", "yes", "on")
    )
    camera_auto_scan_interval_sec: int = field(
        default_factory=lambda: max(30, int(os.getenv("CAMERA_AUTO_SCAN_INTERVAL_SEC", "120")))
    )
    port: int = field(default_factory=lambda: int(os.getenv("PORT", "8000")))

    database_path: Path = field(
        default_factory=lambda: _path(os.getenv("DATABASE_PATH", "data/firewatch.db"))
    )
    media_dir: Path = field(
        default_factory=lambda: _path(os.getenv("MEDIA_DIR", "data/media"))
    )
    cameras_file: Path = field(
        default_factory=lambda: _path(os.getenv("CAMERAS_FILE", "cameras.json"))
    )
    demo_assets_dir: Path = field(default_factory=lambda: BASE_DIR / "demo_assets")

    # auto | yolo | heuristic
    detector: str = field(
        default_factory=lambda: os.getenv("DETECTOR", "auto").lower()
    )
    yolo_weights: Path = field(
        default_factory=lambda: _path(
            os.getenv("YOLO_WEIGHTS", "models/fire_smoke_yolov8n.pt")
        )
    )
    detection_conf: float = field(
        default_factory=lambda: float(os.getenv("DETECTION_CONF", "0.25"))
    )

    firebase_credentials: str = field(
        default_factory=lambda: os.getenv("FIREBASE_CREDENTIALS", "").strip()
    )
    public_base_url: str = field(
        default_factory=lambda: os.getenv("PUBLIC_BASE_URL", "").strip().rstrip("/")
    )
    clip_seconds: int = field(
        default_factory=lambda: int(os.getenv("CLIP_SECONDS", "5"))
    )
    default_camera_id: str = field(
        default_factory=lambda: os.getenv("DEFAULT_CAMERA_ID", "cam4")
    )
    cors_origins: list[str] = field(
        default_factory=lambda: [
            o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",")
        ]
    )
    max_upload_mb: int = field(
        default_factory=lambda: int(os.getenv("MAX_UPLOAD_MB", "30"))
    )
    max_video_upload_mb: int = field(
        default_factory=lambda: int(os.getenv("MAX_VIDEO_UPLOAD_MB", "200"))
    )
    # Сколько тяжёлых задач (YOLO / FFmpeg) обрабатывать одновременно
    max_concurrent_jobs: int = field(
        default_factory=lambda: int(os.getenv("MAX_CONCURRENT_JOBS", "2"))
    )

    def firebase_credentials_path(self) -> str:
        return (
            str(_path(self.firebase_credentials)) if self.firebase_credentials else ""
        )

    def lan_ip(self) -> str:
        return detect_mac_lan_ip()

    def lan_base_url(self) -> str:
        return f"http://{self.lan_ip()}:{self.port}"


def get_settings() -> Settings:
    return Settings()
