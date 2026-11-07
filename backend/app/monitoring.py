"""Consecutive-frame confirmation for automatic alerts (manual analysis is unchanged)."""
from __future__ import annotations


class ConfirmationTracker:
    def __init__(self, required_frames: int, min_confidence: float):
        self.required_frames = required_frames
        self.min_confidence = min_confidence
        self._streaks: dict[str, tuple[str, int]] = {}

    def reset(self, camera_id: str) -> None:
        self._streaks.pop(camera_id, None)

    def clear(self) -> None:
        self._streaks.clear()

    def observe(self, camera_id: str, classification: str, confidence: float) -> bool:
        if classification == "none" or confidence < self.min_confidence:
            self.reset(camera_id)
            return False
        # fire and fire+smoke both confirm fire; smoke alone cannot confirm fire.
        hazard = "fire" if classification in ("fire", "fire_smoke") else "smoke"
        previous, count = self._streaks.get(camera_id, ("", 0))
        count = min(count + 1, self.required_frames) if previous == hazard else 1
        self._streaks[camera_id] = (hazard, count)
        return count >= self.required_frames

    def pending(self) -> dict[str, int]:
        return {camera: count for camera, (_, count) in list(self._streaks.items())
                if count < self.required_frames}
