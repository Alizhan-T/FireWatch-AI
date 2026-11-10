"""Evaluate labelled frames and measure CPU inference; never sends notifications."""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import statistics
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.config import Settings
from app.detection import build_detector


def evaluate(manifest: Path, repeats: int) -> dict:
    with manifest.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    if not rows or repeats < 1:
        raise ValueError("Provide at least one labelled frame and a positive repeat count")
    allowed = {"fire", "smoke", "fire_smoke", "none"}
    for row in rows:
        if row["label"] not in allowed or not (manifest.parent / row["path"]).is_file():
            raise ValueError("Invalid evaluation label or missing frame")
    detector, _ = build_detector(Settings(detector="yolo"))
    detector.detect(manifest.parent / rows[0]["path"])  # warm-up excluded from latency
    counts = {name: {"tp": 0, "fp": 0, "fn": 0, "tn": 0} for name in ("fire", "smoke")}
    elapsed, frames = [], []
    for row in rows:
        predictions = []
        for _ in range(repeats):
            started = time.perf_counter()
            output = detector.detect(manifest.parent / row["path"])
            elapsed.append((time.perf_counter() - started) * 1000)
            predictions.append(output.classification)
        for hazard, predicted in (("fire", output.fire_detected), ("smoke", output.smoke_detected)):
            expected = hazard in row["label"]
            key = ("tp" if expected else "fp") if predicted else ("fn" if expected else "tn")
            counts[hazard][key] += 1
        frames.append({"frame": row["path"], "expected": row["label"],
                       "predicted": output.classification, "confidence": output.confidence,
                       "repeat_predictions": predictions})
    ordered = sorted(elapsed)
    return {"mode": detector.mode, "model": detector.model_name, "frames": len(rows),
            "inferences": len(elapsed), "counts": counts, "results": frames,
            "latency_ms": {"median": round(statistics.median(elapsed), 2),
                           "p95": round(ordered[min(len(ordered)-1, int(len(ordered)*0.95))], 2)},
            "scope": "Only these labelled frames; repeats measure load, not dataset size. No field accuracy or uptime claim."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = evaluate(args.manifest, args.repeats)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: report[k] for k in ("frames", "inferences", "counts", "latency_ms")}))
