"""Демо-ассеты: синтетическая картинка-заглушка и локальные DEMO-видеоролики (MP4)."""
from __future__ import annotations

import logging
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

log = logging.getLogger("firewatch.demo_assets")

BUILTIN_DEMO_VIDEOS_META = {
    "demo_wildfire_active": {
        "title": "Burabay Sector 4 — Wildfire Outbreak (DEMO VIDEO)",
        "description": "Локальная предзаписанная видеозапись очага возгорания для демонстрации FFmpeg + YOLOv8n.",
        "location_name": "Burabay National Park, Sector 4 (DEMO)",
        "lat": 53.0833,
        "lon": 70.3000,
    },
    "demo_forest_clear": {
        "title": "Ile-Alatau Gorge — Clear Forest Patrol (DEMO VIDEO)",
        "description": "Локальная предзаписанная видеозапись чистого лесного массива без огня и дыма (контрольный образец).",
        "location_name": "Ile-Alatau Sector 7 (DEMO)",
        "lat": 43.0500,
        "lon": 76.9800,
    },
    "demo_sector_patrol": {
        "title": "Karkaraly Ridge — Patrol Sequence 0–3s Clear / 3–6s Fire (DEMO VIDEO)",
        "description": "Комбинированный локальный DEMO-ролик: первые 3 секунды — спокойный лес, с 3-й по 6-ю секунду — появление огня.",
        "location_name": "Karkaraly Forestry Sector 2 (DEMO)",
        "lat": 49.4167,
        "lon": 75.4667,
    },
}


def ensure_demo_image(path: Path) -> Path:
    """Нарисованная (не реальная) заглушка для симуляции, если нет FFmpeg/камеры."""
    if path.exists():
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    w, h = 1280, 720
    img = Image.new("RGB", (w, h), (16, 19, 24))
    d = ImageDraw.Draw(img)
    for i in range(0, w, 40):
        top = 380 + (i * 37) % 60
        d.polygon([(i, 720), (i + 20, top), (i + 40, 720)], fill=(28, 52, 42))
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    g = ImageDraw.Draw(glow)
    for r, col in ((220, (120, 30, 0)), (160, (230, 90, 10)), (100, (255, 170, 40))):
        g.ellipse((640 - r, 560 - r, 640 + r, 560 + r // 2), fill=col)
    glow = glow.filter(ImageFilter.GaussianBlur(30))
    img.paste(glow, (0, 0), glow.convert("L"))
    d = ImageDraw.Draw(img)
    for k in range(6):
        d.ellipse((560 + k * 25, 200 - k * 30, 760 + k * 25, 330 - k * 30), fill=(90, 90, 90))
    d.rectangle((0, 0, w, 64), fill=(255, 69, 58))
    d.text((20, 18), "DEMO / SIMULATED IMAGE - not a real camera frame", fill=(255, 255, 255))
    img.save(path, "JPEG", quality=88)
    return path


def _build_single_image_mp4(img_path: Path, out_mp4: Path, duration: int = 5) -> bool:
    if not shutil.which("ffmpeg") or not img_path.exists():
        return False
    tmp = out_mp4.with_suffix(".part.mp4")
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-loop", "1", "-framerate", "24", "-i", str(img_path),
        "-t", str(duration),
        "-vf", "scale='trunc(iw/2)*2:trunc(ih/2)*2'",
        "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        str(tmp),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=30, check=False)
    if res.returncode == 0 and tmp.exists() and tmp.stat().st_size > 0:
        tmp.replace(out_mp4)
        return True
    tmp.unlink(missing_ok=True)
    return False


def _build_transition_mp4(clear_img: Path, fire_img: Path, out_mp4: Path) -> bool:
    if not shutil.which("ffmpeg") or not clear_img.exists() or not fire_img.exists():
        return False
    tmp = out_mp4.with_suffix(".part.mp4")
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-loop", "1", "-t", "3", "-framerate", "24", "-i", str(clear_img),
        "-loop", "1", "-t", "3", "-framerate", "24", "-i", str(fire_img),
        "-filter_complex",
        "[0:v]scale=640:480:force_original_aspect_ratio=decrease,pad=640:480:(ow-iw)/2:(oh-ih)/2,setsar=1[v0];"
        "[1:v]scale=640:480:force_original_aspect_ratio=decrease,pad=640:480:(ow-iw)/2:(oh-ih)/2,setsar=1[v1];"
        "[v0][v1]concat=n=2:v=1:a=0[v]",
        "-map", "[v]",
        "-c:v", "libx264", "-preset", "ultrafast", "-crf", "18",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        str(tmp),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=40, check=False)
    if res.returncode == 0 and tmp.exists() and tmp.stat().st_size > 0:
        tmp.replace(out_mp4)
        return True
    tmp.unlink(missing_ok=True)
    return False


def ensure_demo_videos(demo_assets_dir: Path, fixtures_dir: Path | None = None) -> Path:
    """Гарантировать наличие локальных DEMO MP4 роликов для демонстрации без внешних камер."""
    videos_dir = demo_assets_dir / "videos"
    videos_dir.mkdir(parents=True, exist_ok=True)

    # Если уже есть готовые MP4 в основном каталоге demo_assets/videos, копируем их без перекодирования
    repo_videos = Path(__file__).resolve().parent.parent / "demo_assets" / "videos"
    if repo_videos.exists() and repo_videos.resolve() != videos_dir.resolve():
        for existing_mp4 in repo_videos.glob("*.mp4"):
            dst = videos_dir / existing_mp4.name
            if not dst.exists():
                shutil.copy(existing_mp4, dst)

    fire_img = demo_assets_dir / "sample_fire.jpg"
    clear_img = demo_assets_dir / "sample_clear.jpg"
    if not fire_img.exists() and fixtures_dir and (fixtures_dir / "fire_crop.jpg").exists():
        shutil.copy(fixtures_dir / "fire_crop.jpg", fire_img)
    if not clear_img.exists() and fixtures_dir and (fixtures_dir / "no_fire.jpg").exists():
        shutil.copy(fixtures_dir / "no_fire.jpg", clear_img)

    fire_mp4 = videos_dir / "demo_wildfire_active.mp4"
    clear_mp4 = videos_dir / "demo_forest_clear.mp4"
    patrol_mp4 = videos_dir / "demo_sector_patrol.mp4"

    try:
        if not fire_mp4.exists() and fire_img.exists():
            _build_single_image_mp4(fire_img, fire_mp4, duration=5)
        if not clear_mp4.exists() and clear_img.exists():
            _build_single_image_mp4(clear_img, clear_mp4, duration=5)
        if not patrol_mp4.exists() and clear_img.exists() and fire_img.exists():
            _build_transition_mp4(clear_img, fire_img, patrol_mp4)
    except Exception as e:
        log.warning("Could not pre-generate demo MP4 videos: %s", e)

    return videos_dir
