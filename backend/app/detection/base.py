"""Модульный интерфейс детекторов огня/дыма."""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal, Protocol

Mode = Literal["real_model", "demo_heuristic"]


@dataclass
class BoxOut:
    label: Literal["fire", "smoke"]
    confidence: float
    x1: float
    y1: float
    x2: float
    y2: float


@dataclass
class DetectorOutput:
    fire_detected: bool
    smoke_detected: bool
    confidence: float
    boxes: list[BoxOut] = field(default_factory=list)

    @property
    def classification(self) -> str:
        if self.fire_detected and self.smoke_detected:
            return "fire_smoke"
        if self.fire_detected:
            return "fire"
        if self.smoke_detected:
            return "smoke"
        return "none"


class Detector(Protocol):
    mode: Mode
    provider: str
    model_name: str
    disclaimer: str

    def detect(self, image_path: Path) -> DetectorOutput: ...
