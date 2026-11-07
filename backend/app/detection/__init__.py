"""Выбор детектора: DETECTOR=auto|yolo|heuristic."""
from __future__ import annotations

import logging

from ..config import Settings
from .base import Detector, DetectorOutput
from .heuristic_provider import HeuristicFireDetector

log = logging.getLogger("firewatch.detect")

__all__ = ["Detector", "DetectorOutput", "build_detector", "severity_for"]


def build_detector(settings: Settings) -> tuple[Detector, str | None]:
    """Вернуть (детектор, причина_фоллбэка_или_None)."""
    if settings.detector == "heuristic":
        return HeuristicFireDetector(), "DETECTOR=heuristic задан в конфиге"
    try:
        from .yolo_provider import YoloFireDetector

        return YoloFireDetector(
            settings.yolo_weights,
            conf=settings.detection_conf,
            config_dir=settings.database_path.parent / ".ultralytics",
        ), None
    except Exception as e:  # noqa: BLE001 — любая ошибка загрузки -> демо-режим
        if settings.detector == "yolo":
            raise
        reason = f"{type(e).__name__}: {e}"
        # Не раскрываем мобильному клиенту внутренние пути файловой системы Mac
        reason = reason.replace(str(settings.yolo_weights), settings.yolo_weights.name).replace(
            str(settings.yolo_weights.parent.parent), "")
        log.warning("Real model unavailable, using DEMO heuristic. Reason: %s", reason)
        return HeuristicFireDetector(), reason


def severity_for(classification: str, confidence: float) -> str:
    """Правило перевода результата детекции в уровень угрозы (задокументировано в README)."""
    if classification == "fire_smoke":
        return "critical" if confidence >= 0.6 else "high"
    if classification == "fire":
        return "high" if confidence >= 0.5 else "medium"
    if classification == "smoke":
        return "medium" if confidence >= 0.5 else "low"
    return "low"
