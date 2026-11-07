#!/usr/bin/env bash
# Скачать предобученную модель огня/дыма YOLOv8n (D-Fire), лицензия AGPL-3.0
# https://huggingface.co/rabahdev/fire-smoke-yolov8n
set -e
cd "$(dirname "$0")"
mkdir -p models
curl -L --fail -o models/fire_smoke_yolov8n.pt \
  https://huggingface.co/rabahdev/fire-smoke-yolov8n/resolve/main/best.pt
ls -la models/
