#!/usr/bin/env bash
# Safe local launcher for FireWatch AI (Mac backend + iPhone over Wi-Fi).
set -Eeuo pipefail
cd "$(dirname "$0")"

APP_NAME="FireWatch AI"
PORT="${FIREWATCH_PORT:-${PORT:-8000}}"
HOST="${HOST:-0.0.0.0}"
VENV_PY=".venv/bin/python"
UVICORN=".venv/bin/uvicorn"

echo "========================================================"
echo "  ${APP_NAME} — Local Backend"
echo "========================================================"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found. Install Python 3.10+."
  exit 1
fi

if [ ! -d .venv ]; then
  echo "Creating Python virtual environment..."
  python3 -m venv .venv
fi

if ! "${VENV_PY}" -c "import fastapi, uvicorn, PIL, pydantic_settings" >/dev/null 2>&1; then
  echo "Installing backend dependencies..."
  "${VENV_PY}" -m pip install --upgrade pip
  "${VENV_PY}" -m pip install -r requirements.txt
fi

if [ ! -f .env ]; then
  if [ -f .env.example ]; then
    cp .env.example .env
    echo "Created .env from .env.example. Review settings before use."
  else
    echo "ERROR: .env and .env.example are both missing."
    exit 1
  fi
fi

if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  echo "WARNING: FFmpeg/ffprobe not found. Video processing will be unavailable."
else
  echo "FFmpeg: $(ffmpeg -version | head -n 1)"
fi

if [ -f models/fire_smoke_yolov8n.pt ]; then
  echo "YOLO weights: found"
else
  echo "WARNING: YOLO weights missing. Detector behavior depends on DETECTOR setting."
fi

# Never terminate an arbitrary process just because it owns the configured port.
if command -v lsof >/dev/null 2>&1; then
  EXISTING_PIDS="$(lsof -tiTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null || true)"
  if [ -n "${EXISTING_PIDS}" ]; then
    if curl --silent --show-error --fail --max-time 2 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
      echo "A service already responds on port ${PORT}."
      echo "If this is FireWatch AI, reuse it. Otherwise choose another port:"
      echo "  FIREWATCH_PORT=8001 ./run.sh"
      exit 0
    fi
    echo "ERROR: port ${PORT} is occupied by another process (PID: ${EXISTING_PIDS})."
    echo "The process was NOT terminated. Stop it yourself or choose another port."
    echo "  FIREWATCH_PORT=8001 ./run.sh"
    exit 1
  fi
fi

LAN_IP=""
if command -v ipconfig >/dev/null 2>&1; then
  LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
  if [ -z "${LAN_IP}" ]; then
    LAN_IP="$(ipconfig getifaddr en1 2>/dev/null || true)"
  fi
fi
if [ -z "${LAN_IP}" ] && command -v hostname >/dev/null 2>&1; then
  LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
fi

echo "Mac URL:      http://127.0.0.1:${PORT}"
if [ -n "${LAN_IP}" ] && [ "${LAN_IP}" != "127.0.0.1" ]; then
  echo "iPhone URL:   http://${LAN_IP}:${PORT}"
else
  echo "iPhone URL:   LAN address not detected. Check System Settings → Wi-Fi."
fi
echo "Health:       http://127.0.0.1:${PORT}/health"
echo "API docs:     http://127.0.0.1:${PORT}/docs"
echo "--------------------------------------------------------"

UVICORN_PID=""
cleanup() {
  if [ -n "${UVICORN_PID}" ] && kill -0 "${UVICORN_PID}" 2>/dev/null; then
    echo
    echo "Stopping FireWatch AI backend (PID ${UVICORN_PID})..."
    kill -TERM "${UVICORN_PID}" 2>/dev/null || true
    wait "${UVICORN_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

"${UVICORN}" main:app --host "${HOST}" --port "${PORT}" &
UVICORN_PID=$!

READY=0
for _ in $(seq 1 40); do
  if curl --silent --fail --max-time 1 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    READY=1
    break
  fi
  if ! kill -0 "${UVICORN_PID}" 2>/dev/null; then
    echo "ERROR: Uvicorn exited before becoming healthy."
    wait "${UVICORN_PID}" || true
    exit 1
  fi
  sleep 0.5
done

if [ "${READY}" -ne 1 ]; then
  echo "ERROR: backend did not become healthy within 20 seconds."
  exit 1
fi

echo "Backend is healthy and listening on ${HOST}:${PORT}."
wait "${UVICORN_PID}"
