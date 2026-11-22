# Contributing to FireWatch AI

Thank you for contributing to **FireWatch AI**. Because this project deals with live camera streams and safety-sensitive fire/smoke analysis, please follow the engineering and transparency rules below.

## Core Principles

1. **Honest Status Representation:** Never label catalogued camera links as `LIVE` without verified playback, and never present DEMO VFX or heuristic fallbacks as real neural-network detections.
2. **Permitted Sources Only:** Do not add private, authenticated, geo-restricted, or non-permitted streams. Public viewing does not grant permission for automated AI processing or redistribution.
3. **Standalone iPhone First:** Keep `FireWatchNative` runnable on a free Apple Personal Team without requiring a running backend or paid Push Notifications entitlement.

## Running Tests Locally

### Native iOS (`FireWatchNative`)
```bash
cd FireWatchNative
xcodegen generate
open FireWatchNative.xcodeproj
# Press Cmd + U to run FireWatchNativeTests
```

### Optional Backend (`backend`)
```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pytest -q
```

## Pull Request Checklist

- Ensure GitHub Actions workflows (`native-ios.yml`, `backend-tests.yml`) pass.
- Do not commit `.env`, `.env.production`, `secrets/`, `GoogleService-Info.plist`, or Firebase Admin JSON keys.
- Document any physical-device verification needed in the PR description (see [`docs/STABILITY_CHECKLIST.md`](./docs/STABILITY_CHECKLIST.md)).
