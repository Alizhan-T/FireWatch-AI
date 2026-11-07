"""Захват N секунд из онлайн-камеры и извлечение кадров из локальных видео через FFmpeg."""
from __future__ import annotations

import asyncio
import logging
import shutil
import subprocess
from pathlib import Path

log = logging.getLogger("firewatch.capture")

_RESOLVE_HOSTS = ("youtube.com", "youtu.be", "twitch.tv")


class CaptureError(RuntimeError):
    pass


async def _run(*cmd: str, timeout: float) -> tuple[int, str, str]:
    proc = await asyncio.create_subprocess_exec(
        *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
    )
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        raise CaptureError(f"{cmd[0]} timed out after {timeout}s")
    return proc.returncode or 0, out.decode(errors="ignore"), err.decode(errors="ignore")


async def resolve_stream_url(url: str) -> str:
    """YouTube/Twitch страницу -> прямой HLS-URL. Остальное отдаём как есть."""
    if not any(h in url for h in _RESOLVE_HOSTS):
        return url
    if not shutil.which("yt-dlp"):
        raise CaptureError("yt-dlp не найден (pip install yt-dlp)")
    code, out, err = await _run(
        "yt-dlp", "-g", "-f", "best[height<=720]/best", "--no-warnings", url, timeout=40
    )
    lines = [l for l in out.splitlines() if l.strip()]
    if code != 0 or not lines:
        raise CaptureError(f"yt-dlp не смог получить поток: {err.strip()[-300:]}")
    return lines[0].strip()


async def record_clip(stream_url: str, output: Path, seconds: int) -> Path:
    """Записать `seconds` секунд из потока в H.264 MP4, совместимый с iOS."""
    if not shutil.which("ffmpeg"):
        raise CaptureError("ffmpeg не найден (brew install ffmpeg)")

    src = await resolve_stream_url(stream_url)
    log.info("Recording %ss from %s", seconds, src[:120])
    tmp = output.with_suffix(".part.mp4")
    code, _, err = await _run(
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", src,
        "-t", str(seconds),
        "-c:v", "libx264", "-preset", "fast", "-pix_fmt", "yuv420p",
        "-vf", "scale='min(1280,iw)':-2",
        "-an",
        "-movflags", "+faststart",
        str(tmp),
        timeout=seconds + 60,
    )
    if code != 0 or not tmp.exists() or tmp.stat().st_size == 0:
        tmp.unlink(missing_ok=True)
        raise CaptureError(f"ffmpeg failed: {err.strip()[-400:]}")
    tmp.replace(output)
    return output


def ffmpeg_available() -> bool:
    return shutil.which("ffmpeg") is not None


def probe_video_duration_sync(video_path: Path) -> float:
    """Длительность видео в секундах через ffprobe. 0.0 — файл не читается (повреждён/не видео)."""
    if not shutil.which("ffprobe") or not video_path.exists():
        return 0.0
    try:
        res = subprocess.run(
            [
                "ffprobe",
                "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                str(video_path),
            ],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
        if res.returncode != 0:
            return 0.0
        return round(max(0.0, float(res.stdout.strip())), 2)
    except Exception:
        return 0.0


async def grab_stream_frame(stream_url: str, output_jpg: Path, timeout: float = 15.0) -> Path:
    """Захватить один кадр из реального RTSP/HLS потока (проверка доступности камеры)."""
    if not ffmpeg_available():
        raise CaptureError("ffmpeg не найден на Mac (brew install ffmpeg)")
    output_jpg.parent.mkdir(parents=True, exist_ok=True)
    src = await resolve_stream_url(stream_url)
    extra = ["-rtsp_transport", "tcp"] if src.lower().startswith("rtsp") else []
    code, _, err = await _run(
        "ffmpeg", "-y", "-loglevel", "error", *extra,
        "-i", src, "-frames:v", "1", "-q:v", "3", str(output_jpg),
        timeout=timeout,
    )
    if code != 0 or not output_jpg.exists() or output_jpg.stat().st_size == 0:
        output_jpg.unlink(missing_ok=True)
        msg = (err.strip().splitlines() or ["поток недоступен"])[-1]
        raise CaptureError(f"Поток недоступен: {msg[:200]}")
    return output_jpg


def extract_frame_sync(
    video_path: Path, timestamp_sec: float, output_jpg: Path
) -> Path:
    """Извлечь один кадр JPEG из локального MP4/MOV видео на отметке `timestamp_sec` через FFmpeg."""
    if not ffmpeg_available():
        raise CaptureError("ffmpeg не найден на Mac (установите: brew install ffmpeg)")
    if not video_path.exists():
        raise CaptureError(f"Видеофайл не найден: {video_path.name}")

    output_jpg.parent.mkdir(parents=True, exist_ok=True)
    duration = probe_video_duration_sync(video_path)
    safe_ts = max(0.0, min(timestamp_sec, max(0.0, duration - 0.1)))

    for candidate_ts in (safe_ts, 0.0):
        try:
            res = subprocess.run(
                [
                    "ffmpeg", "-y", "-loglevel", "error",
                    "-ss", f"{candidate_ts:.2f}",
                    "-i", str(video_path),
                    "-frames:v", "1",
                    "-q:v", "2",
                    str(output_jpg),
                ],
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
        except subprocess.TimeoutExpired:
            continue
        if res.returncode == 0 and output_jpg.exists() and output_jpg.stat().st_size > 0:
            return output_jpg

    raise CaptureError(f"Не удалось извлечь кадр из {video_path.name} через FFmpeg")


async def generate_fallback_clip(
    output: Path, seconds: int, label: str, image: Path | None = None
) -> Path:
    """Запасной DEMO-клип (камера недоступна): анимированная демо-картинка или тест-сигнал."""
    if not ffmpeg_available():
        raise CaptureError("ffmpeg не найден (brew install ffmpeg)")
    if image is not None and image.exists():
        src = ["-loop", "1", "-framerate", "25", "-i", str(image)]
        vf = (
            f"scale=1280:720,zoompan=z='min(zoom+0.0015,1.15)':d={seconds * 25}"
            ":x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=1280x720:fps=25"
        )
    else:
        src = ["-f", "lavfi", "-i", f"testsrc2=size=1280x720:rate=25:duration={seconds}"]
        vf = "hue=h=-20:s=2,drawbox=x=0:y=0:w=iw:h=80:color=red@0.6:t=fill"
    code, _, err = await _run(
        "ffmpeg", "-y", "-loglevel", "error", *src,
        "-t", str(seconds), "-vf", vf,
        "-c:v", "libx264", "-preset", "fast", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        str(output),
        timeout=60,
    )
    if code != 0:
        raise CaptureError(f"ffmpeg fallback failed: {err.strip()[-400:]}")
    log.warning("Used DEMO fallback clip for %s", label)
    return output
