#!/usr/bin/env python3
"""Export the project's trained YOLOv8 fire/smoke weights for optional on-iPhone AI.

Run on macOS with the Python dependencies installed; not part of normal builds.
The .mlpackage must be validated before it is shipped as a safety feature.
"""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[2]
source = root / "backend" / "models" / "fire_smoke_yolov8n.pt"
destination = root / "FireWatchNative" / "FireWatchNative" / "Models" / "fire_smoke_yolov8n.mlpackage"

if not source.is_file():
    raise SystemExit(f"Missing source weights: {source}")

try:
    from ultralytics import YOLO
except ImportError as exc:
    raise SystemExit("Install first: python3 -m pip install ultralytics coremltools") from exc

model = YOLO(str(source))
names = {str(name).strip().lower() for name in model.names.values()}
if names != {"fire", "smoke"}:
    raise SystemExit(f"Unexpected model classes {names!r}. Refuse unsafe label mapping.")

print("Exporting YOLOv8 detection model with built-in NMS for Vision...")
exported = Path(model.export(format="coreml", imgsz=640, nms=True, device="cpu", batch=1))
if exported.suffix != ".mlpackage" or not exported.exists():
    raise SystemExit(f"Expected a .mlpackage, got {exported}")
destination.parent.mkdir(parents=True, exist_ok=True)
if destination.exists():
    shutil.rmtree(destination)
shutil.copytree(exported, destination)
print(f"Core ML model ready for Xcode: {destination}")
print("Next: regenerate XcodeGen project, build on a physical iPhone, validate on diverse labelled fire/non-fire images.")
print("WARNING: Export does NOT establish real-world detection accuracy or automatic 24/7 monitoring.")
