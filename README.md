# 🔥 FireWatch AI — iOS Wildfire Monitoring & AI Detection MVP

**FireWatch AI** is a full-stack wildfire monitoring, computer vision fire/smoke detection, and incident response Minimum Viable Product (MVP) built for iOS.

The current iPhone app is [FireWatchNative (SwiftUI)](FireWatchNative/README.md).
See [server deployment and field checks](deploy/README.md) for Docker, HTTPS, API-key protection, push testing and 24-hour monitoring verification. The Flutter instructions below describe the earlier client.

---

## 1. Project Overview & Transparency Policy

FireWatch AI provides forestry dispatchers and rangers with:
- **Real-time Dashboard**: System health, configured camera nodes, active fire incidents, derived high-risk zones, and AI scan metrics.
- **Interactive Live Map**: OpenStreetMap visualization of fire incidents, camera nodes, risk radii, and user geolocation.
- **AI Fire & Smoke Detection**: Upload or capture photos to detect visible fire and smoke using a pretrained **YOLOv8n (D-Fire)** model (`REAL MODEL DETECTION`), with automatic fallback to a deterministic color-heuristic detector (`DEMO / SIMULATED DETECTION`) if model weights are absent.
- **Fire Simulation (Demo Mode)**: One-tap generation of clearly labeled simulated wildfire incidents (`is_demo = true`), persisted in SQLite, with optional 5-second FFmpeg video capture/generation and instant in-app alert banners.
- **Incident Management & Emergency Response**: Severity classification (`Low`, `Medium`, `High`, `Critical`), status workflow (`New`, `Acknowledged`, `Resolved`, `False Alarm`), 112 emergency dialer, and incident report brief generation.

> **Transparency & Honesty Policy**:
> - Simulated incidents and heuristic detections are **explicitly labeled as `DEMO`** in both API responses and the mobile UI.
> - Configured camera entries in `cameras.json` represent stream endpoints, not physical hardware telemetry sensors.
> - The "Report Incident" action copies a structured brief and updates SQLite status; it never claims to dispatch government emergency services automatically.

---

## 2. Architecture

```text
FIreAlizh/
├── backend/                     # Python FastAPI + SQLite + YOLOv8 + FFmpeg + FCM
│   ├── main.py                  # Uvicorn entrypoint
│   ├── app/
│   │   ├── main.py              # FastAPI routes, CORS, static media, web control panel
│   │   ├── config.py            # Environment settings (.env)
│   │   ├── db.py                # Thread-safe SQLite persistence (incidents, detections, devices)
│   │   ├── schemas.py           # Pydantic request/response models
│   │   ├── capture.py           # FFmpeg 5s stream recorder + DEMO clip generator
│   │   ├── push.py              # Optional Firebase Cloud Messaging (APNs) sender
│   │   ├── demo_assets.py       # Synthetic labeled DEMO image generator
│   │   └── detection/
│   │       ├── base.py          # Modular Detector protocol
│   │       ├── yolo_provider.py # REAL MODEL DETECTION (Ultralytics YOLOv8n D-Fire)
│   │       └── heuristic_provider.py # DEMO / SIMULATED DETECTION (HSV color heuristic)
│   ├── models/
│   │   └── fire_smoke_yolov8n.pt # Pretrained YOLOv8n fire & smoke weights (D-Fire)
│   ├── demo_assets/             # Sample images for Simulator detection testing
│   ├── tests/                   # Pytest suite (API, SQLite persistence, CV pipeline, FFmpeg)
│   ├── cameras.json             # Configured camera endpoints & coordinates
│   ├── requirements.txt
│   ├── .env.example
│   └── run.sh
└── mobile/                      # Flutter iOS Application (Riverpod)
    ├── pubspec.yaml
    ├── ios/                     # Xcode workspace & Info.plist (ATS configured for local dev)
    ├── lib/
    │   ├── main.dart            # App bootstrap, ProviderScope, safe Firebase init
    │   ├── providers.dart       # Riverpod state management & persistence
    │   ├── theme/app_theme.dart # Dark UI theme (#0B1410, #17231C, #35C979, #FF453A)
    │   ├── models/incident.dart # Incident, CameraNode, RiskZone, DetectionResultModel, SystemStats
    │   ├── services/
    │   │   ├── api_service.dart # FastAPI HTTP client + Offline Demo Mode store
    │   │   └── push_service.dart# FCM handler + in-app MaterialBanner alerts
    │   └── screens/
    │       ├── main_shell.dart      # 5-tab bottom navigation
    │       ├── dashboard_screen.dart# A. Dashboard & Fire Simulation
    │       ├── map_screen.dart      # B. Live OpenStreetMap
    │       ├── detection_screen.dart# C. AI Fire & Smoke Detection
    │       ├── alerts_screen.dart   # D. Alerts & Read/Unread filters
    │       ├── incident_screen.dart # E. Incident Details, Video/Image, 112 & Report
    │       └── profile_screen.dart  # F. Profile, Backend URL & Notification Settings
    └── test/widget_test.dart    # Flutter unit & widget tests
```

---

## 3. Technologies

- **Mobile**: Flutter 3.x (Dart 3), `flutter_riverpod`, `flutter_map` + `latlong2` (OpenStreetMap), `video_player`, `image_picker`, `geolocator`, `url_launcher`, `shared_preferences`, `firebase_core`, `firebase_messaging`.
- **Backend**: Python 3.11+, FastAPI, Uvicorn, SQLite3 (WAL mode), Pydantic v2, Ultralytics YOLOv8 (`torch` + `ultralytics`), Pillow, NumPy, FFmpeg, `yt-dlp`, `firebase-admin`.
- **Testing**: `pytest` + `fastapi.testclient` (Backend), `flutter test` + `flutter analyze` (Mobile).

---

## 4. Installation & Startup

### Prerequisites (macOS)
```bash
brew install python ffmpeg
brew install --cask flutter
```

### Backend Startup
```bash
cd backend
./run.sh
```
What `./run.sh` does:
1. Creates `backend/.venv` and installs `requirements.txt` if not already installed.
2. Copies `.env.example` to `.env` if `.env` does not exist.
3. Starts FastAPI with Uvicorn on `http://0.0.0.0:8000`.
- **Web Demo Control Panel**: `http://127.0.0.1:8000/`
- **Swagger UI Documentation**: `http://127.0.0.1:8000/docs`

### Mobile Startup (iOS Simulator)
```bash
cd mobile
flutter pub get
open -a Simulator
flutter run
```
To build an unsigned iOS Simulator bundle for verification:
```bash
cd mobile
flutter build ios --simulator --no-codesign
```

---

## 5. iOS Simulator Setup

- **Local Backend Address**: Because the iOS Simulator shares the host Mac's loopback network interface, the default backend URL in the app is preconfigured to:
  ```text
  http://127.0.0.1:8000
  ```
- **Network Permissions**: `mobile/ios/Runner/Info.plist` includes `NSAppTransportSecurity` with `NSAllowsLocalNetworking = true` and `NSAllowsArbitraryLoads = true` for local HTTP development, as well as `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, and `NSLocationWhenInUseUsageDescription`.
- **Testing Camera/Photos on Simulator**: Since the iOS Simulator does not have a hardware camera and default Simulator photo libraries do not contain wildfire images, the **AI Detect** screen includes one-tap **"Sample: Forest Fire"** and **"Sample: Clear Forest"** buttons that load real test JPEG bytes from the backend and run them through `POST /detect`.

---

## 6. API Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/health` | System status, SQLite connectivity, active CV detector mode, FFmpeg & Firebase status |
| `GET` | `/stats` | Aggregated incident counts, AI detection breakdown, and derived high-risk zone count |
| `GET` | `/cameras` | List configured camera endpoints and coordinates from `cameras.json` |
| `GET` | `/risk_zones` | Derived high-risk circular zones grouped from active `high`/`critical` incidents |
| `GET` | `/incidents` | List incidents (supports `?severity=`, `?status=`, `?limit=`) |
| `GET` | `/incidents/{id}` | Get full details of a single incident |
| `POST` | `/incidents` | Create a manual incident or save an AI detection (`detection_id`) as an incident |
| `PATCH` | `/incidents/{id}/status` | Update incident status (`new`, `acknowledged`, `resolved`, `false_alarm`) |
| `POST` | `/detect` | Upload an image (`multipart/form-data`) for fire/smoke CV analysis |
| `POST` | `/simulate_fire` | Generate a labeled DEMO fire incident (`camera_id`, `severity`, `capture_from_camera`) |
| `POST` | `/register_device` | Store an iOS FCM device token in SQLite |
| `GET` | `/demo_samples/{kind}` | Fetch sample test JPEG (`fire` or `clear`) for Simulator detection testing |

---

## 7. Demo Mode Instructions

### Scenario 1: Connected Demo (FastAPI + SQLite + YOLOv8)
1. Start the backend (`cd backend && ./run.sh`).
2. Launch the iOS app (`cd mobile && flutter run`).
3. On the **Dashboard** tab, locate the **Fire Simulation Scenario (DEMO MODE)** card.
4. Select a camera sector, choose severity (`Low`, `Medium`, `High`, `Critical`), optionally enable **Record 5s video clip via FFmpeg**, and tap **SIMULATE FIRE (DEMO)**.
5. The incident is saved in SQLite, an in-app alert banner appears at the top of the screen, Dashboard counters increment, the **Live Map** plots the fire marker and risk zone, and tapping **OPEN** launches **Incident Details** with media playback.

### Scenario 2: Standalone Offline Demo Mode (No Backend Required)
- If the backend is not running, tap **Switch to Offline Demo Mode** on the Dashboard error card (or toggle **Offline Demo Mode** in **Profile & Settings**).
- All screens, fire simulation, alert filtering, status updates, and demo detection continue to work using the clearly labeled in-memory `LocalDemoStore`.

---

## 8. AI Model Configuration

Configured via `backend/.env` (see `backend/.env.example`):
- `DETECTOR=auto` (default): Loads `backend/models/fire_smoke_yolov8n.pt` (YOLOv8n trained on the D-Fire dataset, classes: `0: smoke`, `1: fire`). Responses return `mode: "real_model"`.
- `DETECTOR=heuristic`: Forces the deterministic HSV color/smoke pixel analyzer (`mode: "demo_heuristic"`).
- To re-download the pretrained YOLOv8n weights at any time:
  ```bash
  cd backend && ./download_model.sh
  ```

---

## 9. Firebase Cloud Messaging (FCM) Configuration

The application works out-of-the-box **without Firebase** using in-app alert banners. To enable remote APNs push notifications on a physical iPhone:
1. Create a project in [Firebase Console](https://console.firebase.google.com/) and register an iOS app with bundle ID `com.firewatch.firewatch`.
2. Download `GoogleService-Info.plist` and place it in `mobile/ios/Runner/GoogleService-Info.plist` (add to the `Runner` target in Xcode).
3. Upload your Apple Developer `.p8` APNs Auth Key in Firebase Console → **Project Settings → Cloud Messaging → Apple app configuration**.
4. In Firebase Console → **Project Settings → Service accounts**, generate a private key JSON, save it as `backend/firebase-service-account.json`, and set `FIREBASE_CREDENTIALS=./firebase-service-account.json` in `backend/.env`.
5. In Xcode (`open mobile/ios/Runner.xcworkspace`), add **Push Notifications** and **Background Modes → Remote notifications** capabilities.

---

## 10. Known Limitations

1. **Camera & Call Hardware on iOS Simulator**: The iOS Simulator does not provide a physical camera or phone dialer (`tel:112`). The app catches these platform limitations gracefully and provides gallery/sample image upload and a copyable incident report brief.
2. **APNs on Simulator / Unconfigured Firebase**: Remote push notifications require `GoogleService-Info.plist` and an Apple Developer APNs key; when unconfigured, the app automatically falls back to in-app notification banners.
3. **Computer Vision Accuracy**: YOLOv8n (D-Fire) is a lightweight edge model (`mAP50 = 0.754` on D-Fire test split) and can produce false positives on bright sunsets, glare, or dense fog. Human verification is always required.
