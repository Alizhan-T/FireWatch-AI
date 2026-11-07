"""REAL MODEL DETECTION: YOLOv8, дообученная на D-Fire (классы smoke, fire)."""
from __future__ import annotations

import logging
import os
import threading
from pathlib import Path

from .base import BoxOut, DetectorOutput

log = logging.getLogger("firewatch.detect.yolo")


class YoloFireDetector:
    mode = "real_model"
    provider = "ultralytics-yolov8"

    def __init__(self, weights: Path, conf: float = 0.25, config_dir: Path | None = None):
        if not weights.exists():
            raise FileNotFoundError(f"Нет весов модели: models/{weights.name}")
        if config_dir:
            config_dir.mkdir(parents=True, exist_ok=True)
            os.environ.setdefault("YOLO_CONFIG_DIR", str(config_dir))
        os.environ.setdefault("YOLO_OFFLINE", "1")
        from ultralytics import YOLO  # тяжёлый импорт — только когда нужен

        self.weights = weights
        self.conf = conf
        self._model = YOLO(str(weights))
        self._lock = threading.Lock()
        self.names = {int(k): str(v).lower() for k, v in self._model.names.items()}
        self.model_name = f"{weights.name} (YOLOv8, классы: {', '.join(self.names.values())})"
        self.disclaimer = (
            "REAL MODEL DETECTION: обученная нейросеть YOLOv8n (датасет D-Fire). "
            "Уверенность — score модели, а не гарантия. Возможны ошибки; "
            "решения принимает человек."
        )
        log.info("YOLO loaded: %s classes=%s", weights, self.names)

    def detect(self, image_path: Path) -> DetectorOutput:
        with self._lock:
            results = self._model.predict(
                source=str(image_path), conf=self.conf, verbose=False, device="cpu"
            )
        boxes: list[BoxOut] = []
        for r in results:
            for b in r.boxes:
                label = self.names.get(int(b.cls[0]), "")
                if label not in ("fire", "smoke"):
                    continue
                x1, y1, x2, y2 = (float(v) for v in b.xyxy[0].tolist())
                boxes.append(BoxOut(label, round(float(b.conf[0]), 4), x1, y1, x2, y2))
        boxes.sort(key=lambda b: b.confidence, reverse=True)
        return DetectorOutput(
            fire_detected=any(b.label == "fire" for b in boxes),
            smoke_detected=any(b.label == "smoke" for b in boxes),
            confidence=boxes[0].confidence if boxes else 0.0,
            boxes=boxes,
        )
