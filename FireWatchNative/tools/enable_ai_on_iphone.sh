#!/usr/bin/env bash
# Prepare an actual YOLO-derived Core ML model for iPhone photo inference.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_DIR="${ROOT}/.venv-coreml"
WEIGHTS="${ROOT}/backend/models/fire_smoke_yolov8n.pt"
MODEL="${ROOT}/FireWatchNative/FireWatchNative/Models/fire_smoke_yolov8n.mlpackage"

if [[ ! -f "${WEIGHTS}" ]]; then
  echo "Missing trained YOLO weights: ${WEIGHTS}"
  exit 1
fi

PYTHON=""
for candidate in python3.12 python3.11 python3; do
  if command -v "${candidate}" >/dev/null 2>&1; then
    if "${candidate}" -c 'import sys; assert sys.version_info >= (3,10)' >/dev/null 2>&1; then
      PYTHON="${candidate}"
      break
    fi
  fi
done
if [[ -z "${PYTHON}" ]]; then
  echo "Need Python 3.10+; recommended: brew install python@3.11"
  exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Need XcodeGen: brew install xcodegen"
  exit 1
fi

echo "1/4 · Preparing Python environment using ${PYTHON}"
"${PYTHON}" -m venv "${ENV_DIR}"
source "${ENV_DIR}/bin/activate"

echo "2/4 · Installing AI conversion dependencies (internet required)"
python -m pip install --upgrade pip
python -m pip install 'ultralytics>=8.3,<9' 'coremltools>=8,<10'

echo "3/4 · Exporting trained YOLO model into Core ML"
python "${ROOT}/backend/tools/export_coreml.py"

if [[ ! -d "${MODEL}" ]] || [[ ! -f "${MODEL}/Manifest.json" ]]; then
  echo "Core ML package was not generated correctly: ${MODEL}"
  exit 1
fi

echo "4/4 · Regenerating iOS project to bundle the model"
(
  cd "${ROOT}/FireWatchNative"
  xcodegen generate
)

echo ""
echo "Core ML model generated for iPhone."
echo "Open: ${ROOT}/FireWatchNative/FireWatchNative.xcodeproj"
echo "In Xcode: Product > Clean Build Folder, then Cmd+R."
echo "In app: AI > select photo > Check locally with Core ML."
echo "CAUTION: A single AI image result never confirms a real fire."
