#!/usr/bin/env bash
# Запуск локального демонстрационного бэкенда FireWatch AI (Mac + iPhone по Wi-Fi)
set -euo pipefail
cd "$(dirname "$0")"

echo "========================================================"
echo "  FireWatch AI — Local Demonstration Backend (No VPS)"
echo "========================================================"

# 1. Проверка Python и виртуального окружения
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ Ошибка: python3 не найден в PATH. Установите Python 3.10+ (brew install python)."
  exit 1
fi

if [ ! -d .venv ]; then
  echo "⚙️  Создание виртуального окружения .venv..."
  python3 -m venv .venv
  .venv/bin/pip install --upgrade pip
  .venv/bin/pip install -r requirements.txt
fi

# 2. Проверка обязательных Python-пакетов
if ! .venv/bin/python -c "import fastapi, uvicorn, PIL, pydantic, dotenv" >/dev/null 2>&1; then
  echo "⚙️  Установка недостающих зависимостей из requirements.txt..."
  .venv/bin/pip install -r requirements.txt
fi

# 3. Проверка конфигурации .env
[ -f .env ] || cp .env.example .env

# 4. Проверка FFmpeg и ffprobe
if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
  FFMPEG_VER=$(ffmpeg -version | head -n 1 | awk '{print $3}')
  echo "✅ FFmpeg & ffprobe доступны (версия: ${FFMPEG_VER})"
else
  echo "⚠️  FFmpeg/ffprobe не найдены в PATH. Установите через: brew install ffmpeg"
fi

# 5. Проверка модели YOLOv8n
if [ -f models/fire_smoke_yolov8n.pt ]; then
  echo "✅ Модель YOLOv8n найдена: models/fire_smoke_yolov8n.pt (REAL MODEL INFERENCE)"
else
  echo "⚠️  Нет весов models/fire_smoke_yolov8n.pt — детекция будет в DEMO-режиме. Скачать: ./download_model.sh"
fi

# 6. Определение текущего локального Wi-Fi IP Mac
LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")
PORT="${FIREWATCH_PORT:-8000}"

# 7. Не завершаем чужой процесс на занятом порту.
EXISTING_PIDS=$(lsof -ti tcp:"${PORT}" 2>/dev/null || true)
if [ -n "${EXISTING_PIDS}" ]; then
  echo "❌ Порт ${PORT} занят. Остановите предыдущий сервер или задайте FIREWATCH_PORT."
  exit 1
fi

echo "--------------------------------------------------------"
echo "  Mac Local URL   : http://127.0.0.1:${PORT}"
echo "  iPhone Wi-Fi URL: http://${LAN_IP}:${PORT}"
echo "  Health Check    : http://${LAN_IP}:${PORT}/health"
echo "  Swagger API Docs: http://${LAN_IP}:${PORT}/docs"
echo "--------------------------------------------------------"

UVICORN_PID=""
cleanup() {
  if [ -n "${UVICORN_PID}" ] && kill -0 "${UVICORN_PID}" 2>/dev/null; then
    echo ""
    echo "🛑 Остановка FireWatch AI Backend (PID ${UVICORN_PID})..."
    kill "${UVICORN_PID}" 2>/dev/null || true
    wait "${UVICORN_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# 8. Запуск FastAPI на 0.0.0.0:8000 и проверка /health
.venv/bin/uvicorn main:app --host 0.0.0.0 --port "${PORT}" &
UVICORN_PID=$!

for i in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/live" >/dev/null 2>&1; then
    echo "✅ Backend готов к работе и отвечает на http://${LAN_IP}:${PORT}/health"
    break
  fi
  if ! kill -0 "${UVICORN_PID}" 2>/dev/null; then
    echo "❌ Процесс Uvicorn завершился с ошибкой при старте."
    wait "${UVICORN_PID}"
    exit 1
  fi
  sleep 0.5
done

wait "${UVICORN_PID}"
