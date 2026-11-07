# FireWatch Native — SwiftUI iOS client

Native iPhone client for the existing FireWatch-AI FastAPI + YOLO backend. Flutter is not required.

## Generate and open the Xcode project

Install XcodeGen on macOS (`brew install xcodegen`), then:

```bash
cd FireWatchNative
xcodegen generate
open FireWatchNative.xcodeproj
```

In Xcode, select your Apple development team under **Signing & Capabilities**, choose your iPhone and Run. Deployment target is iOS 17+. The project uses SwiftUI, MapKit, AVKit, PhotosUI and Foundation, with no third-party iOS packages.

**Note:** This branch has not yet been built on macOS/Xcode in this environment; resolve any Xcode-specific diagnostics before shipping.

## Backend

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Follow backend configuration instructions in the repository's root README. For the physical iPhone, both devices must be on the same network. In the app's Settings use `http://YOUR_MAC_LAN_IP:8000` (never `localhost`). Only local network HTTP is intended for development; use HTTPS and authentication before exposing the service to the internet.

## Camera integration

1. Obtain an **authorized** RTSP or HTTP(S) HLS (`.m3u8`) URL from the camera operator.
2. Open **Cameras → +**, enter the name, stream URL and actual coordinates.
3. Open the saved camera and tap **Check stream via FFmpeg**. The backend attempts to grab a real frame and reports online/offline.
4. For HLS, the app also plays the live stream with AVPlayer. RTSP is not natively played on iOS; convert it to HLS with a trusted gateway if live playback is needed.

The server must have FFmpeg installed. Camera URLs must be reachable **from the server**, not only the iPhone. The current backend stores camera URLs in `cameras.json` and returns them via the API: do not store embedded camera passwords or expose the API publicly until authentication and secret handling are implemented. Use dedicated read-only camera credentials when permitted.

### Public camera directories (not pre-approved ingest feeds)

- https://pocketworld.org/ru/webcams/country/kz
- https://qgeo.tech/ru/data/layers/public_cameras

A camera appearing in a directory does **not** establish redistribution/automated-analysis permission, or guarantee an accessible HLS URL. Verify the operator's terms and actual stream before adding it. Government/surveillance camera systems are not public RTSP sources.

## AI

The AI tab uploads a selected photo to `POST /detect` and displays the backend's classification, confidence and **real_model vs demo_heuristic** mode. Do not treat demo detections as actual fire alarms. No autonomous camera scanning scheduler or incident escalation has been added.

## Status

Implemented: native dashboard, MapKit incident markers, incidents list, camera CRUD and real FFmpeg probe, HLS AVPlayer, image upload for AI, backend settings.

Not yet production-ready: server authentication, credential storage, authorization to access third-party streams, automated live stream inference, APNs device registration, full incident workflows, robust camera stream gateway, CI-tested iOS build and field testing.
