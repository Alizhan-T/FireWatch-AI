"""DEMO / SIMULATED DETECTION: детерминированный цветовой анализ (НЕ нейросеть).

Используется, только если реальная модель недоступна. Считает долю пикселей
«цвета пламени» (ярко-оранжевые/красные) и «цвета дыма» (серые, малонасыщенные).
Результат детерминирован (нет random), но это эвристика с большим числом
ложных срабатываний (закаты, осенняя листва, облака).
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

from .base import BoxOut, DetectorOutput

FIRE_RATIO_THRESHOLD = 0.015
SMOKE_RATIO_THRESHOLD = 0.30


def _bbox(mask: np.ndarray, scale: float) -> tuple[float, float, float, float] | None:
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None
    return (xs.min() * scale, ys.min() * scale, (xs.max() + 1) * scale, (ys.max() + 1) * scale)


class HeuristicFireDetector:
    mode = "demo_heuristic"
    provider = "color-heuristic"
    model_name = "HSV color heuristic v1 (not a trained model)"
    disclaimer = (
        "DEMO / SIMULATED DETECTION: обученная модель не загружена. Используется простой "
        "цветовой анализ пикселей. Это НЕ искусственный интеллект, скор не является "
        "вероятностью, возможны частые ложные срабатывания."
    )

    def analyze(self, image_path: Path) -> dict:
        img = Image.open(image_path).convert("RGB")
        w0 = img.width
        img.thumbnail((320, 320))
        scale = w0 / img.width
        rgb = np.asarray(img, dtype=np.float32) / 255.0
        hsv = np.asarray(img.convert("HSV"), dtype=np.float32) / 255.0
        h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
        r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]

        fire = ((h <= 0.14) | (h >= 0.97)) & (s >= 0.45) & (v >= 0.55) & (r > g) & (g >= b)
        smoke = (s <= 0.18) & (v >= 0.35) & (v <= 0.88) & (np.abs(r - b) < 0.12)
        return {
            "fire_mask": fire, "smoke_mask": smoke, "scale": scale,
            "fire_ratio": float(fire.mean()), "smoke_ratio": float(smoke.mean()),
        }

    def detect(self, image_path: Path) -> DetectorOutput:
        a = self.analyze(image_path)
        fire_ratio, smoke_ratio = a["fire_ratio"], a["smoke_ratio"]
        fire_score = min(1.0, fire_ratio / (FIRE_RATIO_THRESHOLD * 6))
        smoke_score = min(1.0, smoke_ratio / (SMOKE_RATIO_THRESHOLD * 2))
        fire = fire_ratio >= FIRE_RATIO_THRESHOLD
        smoke = smoke_ratio >= SMOKE_RATIO_THRESHOLD
        boxes: list[BoxOut] = []
        if fire and (bb := _bbox(a["fire_mask"], a["scale"])):
            boxes.append(BoxOut("fire", round(fire_score, 4), *bb))
        if smoke and (bb := _bbox(a["smoke_mask"], a["scale"])):
            boxes.append(BoxOut("smoke", round(smoke_score, 4), *bb))
        score = max([b.confidence for b in boxes], default=max(fire_score, smoke_score))
        return DetectorOutput(fire, smoke, round(score, 4), boxes)
