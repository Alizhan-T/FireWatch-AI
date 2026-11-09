"""Read-only monitoring probe; writes JSONL samples and a summary, no notifications."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys
import time

import httpx


def run(url: str, duration: float, interval: float, output: Path) -> int:
    if duration <= 0 or interval <= 0:
        raise ValueError("Duration and interval must be positive")
    token = os.environ.get("API_ACCESS_TOKEN", "")
    if not token:
        raise ValueError("Set API_ACCESS_TOKEN in the environment (never as a command-line argument)")
    samples = failures = 0
    last_attempted = None
    restarts = 0
    started = time.monotonic()
    output.parent.mkdir(parents=True, exist_ok=True)
    # Never follow a redirect with the custom API-key header to a different origin.
    with httpx.Client(base_url=url.rstrip("/"), headers={"X-API-Key": token},
                      timeout=30, follow_redirects=False) as client, output.open("x") as stream:
        while True:
            stamp = datetime.now(timezone.utc).isoformat()
            try:
                response = client.get("/ready")
                body = response.json() if response.status_code in (200, 503) else {}
                good = response.status_code == 200 and body.get("ready") is True
                metrics = body.get("monitoring", {}).get("metrics", {})
                attempted = metrics.get("attempted")
                if attempted is not None and last_attempted is not None and attempted < last_attempted:
                    restarts += 1
                    good = False
                last_attempted = attempted
                sample = {"at": stamp, "ok": good, "http": response.status_code,
                          "reasons": body.get("reasons", []), "metrics": metrics}
            except (httpx.HTTPError, ValueError) as exc:
                good = False
                sample = {"at": stamp, "ok": False, "error_type": type(exc).__name__}
            samples += 1
            failures += int(not good)
            stream.write(json.dumps(sample) + "\n")
            stream.flush()
            remaining = duration - (time.monotonic() - started)
            if remaining <= 0:
                break
            time.sleep(min(interval, remaining))
    summary = {"samples": samples, "failed_samples": failures, "observed_restarts": restarts,
               "elapsed_sec": round(time.monotonic() - started, 2),
               "passed": failures == 0, "scope": "Readiness sampled at intervals; not proof of uninterrupted uptime."}
    output.with_suffix(".summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary))
    return int(failures > 0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True)
    parser.add_argument("--duration", type=float, default=86400)
    parser.add_argument("--interval", type=float, default=60)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    sys.exit(run(args.url, args.duration, args.interval, args.output))
