# FireWatch Native — SwiftUI-only iOS client

## November 2026 — lightweight native stability pass

The iPhone application now launches as pure SwiftUI without the Firebase / APNs SDK. This removes optional remote-notification dependencies that added binary size and build time even though a free Apple Personal Team cannot enable the necessary Push Notifications entitlement. **Remote push and Firebase device registration are not part of this build**; camera viewing, local event reports and DEMO simulations still work.

The dashboard is now camera-first, with a high-contrast action card, accurate source counts (catalogued, not claimed online), quick DEMO/manual event creation, and a smaller events preview. The optional FastAPI connection remains available for the existing server-side YOLO processing.

An earlier user screenshot showed iOS terminating the app with **SIGKILL**. This alone does not establish a root cause; removing an unused Firebase dependency is preventive simplification, not proof of a crash fix. For physical-device diagnostics, inspect the iOS crash/termination report in Xcode Devices and Simulators and note its **Termination Reason**. CI simulator tests cannot reproduce every device-only termination.

---


## November 2026: Cities, local events, icon, and Core ML

**City-only forms.** In AI photo analysis and when registering a camera with the optional backend, choose a Kazakhstan city instead of latitude and longitude. Coordinates are assigned from the city centroid **only for rough display**. A centroid is NOT the actual location of a fire.

**Events.** The Events tab now works offline. Use «Создать событие» for a user-entered, unverified observation; use «Имитация» for a clearly labelled DEMO event. Both are stored locally on the phone. You can mark them resolved, delete them, and see them on the dashboard and map. Manual/DEMO events are not real AI detections, emergency dispatches or APNs pushes.

**Cameras.** Seven previously audited Aktau HLS streams are kept. The city filter now adds a Semey Central Square publisher view and Shymbulak/Almaty publisher view INSIDE FireWatch; neither is a verified direct HLS. The Semey source is classified as unstable by its public listing. Web publishers may restrict embedding. The app does not bypass those restrictions or present an unavailable video as LIVE. You may save a direct permitted HLS URL yourself.

**Icon.** Native XcodeGen builds generate a minimal orange fire/shield AppIcon using the macOS Swift/AppKit script at tools/generate_app_icon.swift. No external graphics package is required.

**Real AI on iPhone.** The Core ML/Vision photo-inference path is now present, but cannot run until a trained, compatible Core ML model is generated and bundled. The PyTorch checkpoint cannot run in iOS on its own. An optional server with the existing YOLO model is still the only immediately available real-model inference if the Core ML artifact has not been installed.

To prepare the model on a developer Mac (optional):

    cd FireWatch-AI
    python3 -m pip install ultralytics coremltools
    python3 backend/tools/export_coreml.py
    cd FireWatchNative
    xcodegen generate
    open FireWatchNative.xcodeproj

The exporter validates that the expected classes are fire and smoke and selects NMS for Vision. The iPhone displays detections only for a compatible object-detection output and confidence >=65%. Conversion and a confidence threshold alone DO NOT make wildfire detection trustworthy. Field testing needs many varied labelled fire and non-fire images, careful false-positive/negative evaluation and a real iPhone. iOS cannot promise unlimited 24/7 background camera scanning.

**Personal Team** signing remains available without the paid APNs capability by default.

---


## Kazakhstan city cameras and training SOS (November 2026)

The camera picker now includes **Astana, Almaty, Semey and Aktau**:
- Aktau: seven public direct HTTPS HLS streams.
- Almaty: two *newly probed* Shymbulak HTTPS HLS streams and publisher alternatives. A GitHub Actions manifest test on 10 November 2026 received valid HLS playlists from **9/9** catalogue links (seven Aktau + two Almaty), but this is **not** proof that video segments render on a physical iPhone, that streams remain available, or that the operators permit automatic analysis.
- Astana: a published Atameken Business city livestream shown inside the app using a YouTube embed; the owner may block embedding or terminate the live session.
- Semey: the Central Square Geocam/gorset.kz publisher page is still marked *unstable* and may not play on an iPhone. There is no verified direct HLS for Semey yet.

**DEMO simulation**: Choose «Имитировать пожар», select a city, and tap «Запустить DEMO». FireWatch opens a camera-backed training screen (defaults to a camera from the selected city if available; falls back to an available catalogue option), with an animated **artificial flame/smoke overlay** and persistent, unmissable «DEMO / НЕ РЕАЛЬНЫЙ ПОЖАР» label. The original stream is not changed or recorded. The actual camera city is shown separately from the simulated incident city to avoid confusion.

Starting a DEMO requests iPhone notification permission when required and schedules a **local** «SOS · ДЕМО · УЧЕБНАЯ ТРЕВОГА» notification. Foreground banners are supported and there is a button to re-send the test. This is entirely on-device: no APNs/Firebase service, backend, emergency-number call, dispatch, broadcast or third-party message occurs. Denied permissions are reported inside the app. Manually entered non-DEMO events cannot produce this test SOS payload.

Physical-device verification is still required for stream decoding, permissions and notifications. Real autonomous fire/smoke detection is **not implemented by this feature** and requires a separately evaluated Core ML model or the existing optional server. Public viewing alone does not authorize AI analysis of third-party feeds.

## First launch: server-free camera viewing

This native SwiftUI application (iOS 17+) is the sole supported iPhone client. **A FireWatch backend is optional.** Generate the Xcode project with XcodeGen, open the app, and go to **Камеры** to watch the built-in public HLS camera candidates directly through AVPlayer. You may add personal HTTP(S) .m3u8 streams under **Мои HLS-камеры · без сервера**; they persist in UserDefaults on the iPhone. The map displays published camera coordinates even when no backend is configured.

Public streams may be offline and their operators may prohibit automated processing. The app indicates AVPlayer preparation/failure, not guaranteed uptime. No realtime AI fire detection, incident database or remote push (disabled in Personal Team build) is provided in server-free mode.

To opt into the existing remote AI features later, configure the optional backend using the instructions below. A future truly server-free detector will require a separately converted and validated Core ML model.

---

Native iPhone client for the FireWatch-AI FastAPI + YOLO backend. The native client does not use Flutter.

## Free Apple Personal Team: iPhone signing

**Remote APNs Push Notifications are intentionally disabled by default.** A free Apple Account (Personal Team) cannot provision the Push Notifications capability, and the main workflow (viewing Kazakhstan HLS streams inside the native app) does not need push or a FireWatch server.

To update an existing XcodeGen checkout when signing previously failed:

```bash
# Run from the repository root on branch main
git stash push -m "local Xcode signing changes" -- FireWatchNative/Info.plist FireWatchNative/project.yml
git pull origin main
cd FireWatchNative
xcodegen generate
open FireWatchNative.xcodeproj
```

In Xcode choose your iPhone, select your **Personal Team** under **Signing & Capabilities**, and press **Cmd+R**. If the generated target still shows a **Push Notifications** capability, close Xcode, make sure `FireWatchNative/project.yml` is up to date, regenerate the project and reopen it. Do not apply the saved stash automatically: it can reintroduce the unsupported entitlement.

To enable real background remote APNs/FCM push notifications later, enrol in the paid Apple Developer Program, enable Push Notifications for your app identifier, add the push capability/entitlement and configure the APNs/Firebase credentials. These optional steps are independent of HLS playback.

---

## 1. Generate and open the Xcode project

Install XcodeGen on macOS:

```bash
brew install xcodegen
cd FireWatchNative
xcodegen generate
open FireWatchNative.xcodeproj
```

In Xcode:
1. Select the **FireWatchNative** scheme.
2. Open **Signing & Capabilities** and select your Apple development team.
3. Choose your physical iPhone and press Run.
4. Accept the Local Network permission prompt when iOS asks.

The deployment target is iOS 17+. The GitHub Actions workflow generates the Xcode project and compiles it for the iOS Simulator. A successful simulator build does not replace testing on your physical iPhone.

## 2. Start the backend on your Mac

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
brew install ffmpeg
uvicorn main:app --host 0.0.0.0 --port 8000
```

The first start may take longer while the Python dependencies and YOLO runtime are prepared. The model weights are in `backend/models/fire_smoke_yolov8n.pt`. The app's dashboard shows whether the server loaded `real_model` or fell back to `demo_heuristic`. A heuristic result is explicitly a demo and must not be treated as a confirmed fire.

Find your Mac's Wi-Fi IP in **System Settings → Wi-Fi → Details**. In the iPhone app open **Settings** and enter:

`http://YOUR_MAC_LAN_IP:8000`

Do not use `localhost` or `127.0.0.1` on the iPhone; those addresses refer to the phone itself. The Mac and iPhone must be on the same network, and macOS Firewall must allow incoming connections to Python/Uvicorn.

## 3. Protect the backend

For a trusted local development network, the API key can remain empty. Before exposing the backend beyond your private network:
1. Put a long random value in `API_ACCESS_TOKEN` in `backend/.env`.
2. Enter the same value in the iOS app's **API key** field. It is stored in the iOS Keychain.
3. Use HTTPS through a properly configured reverse proxy. Do not expose a development Uvicorn server directly to the public internet.

All diagnostic/data routes, including `/health` and `/ready`, require `X-API-Key` when configured. Only the minimal `/live` process probe is public. The iOS client sends the key from Keychain. Production deployment and verification: [deployment guide](../deploy/README.md).

## 4. Camera workflow

The **Cameras** tab includes a bundled list of six public HLS links from the Aktau XCOM catalogue. You can open and watch these feeds on an iPhone without configuring or running a FireWatch server. The list is a set of candidates: availability can change, and permission to view does not automatically grant permission for AI processing. These are city/coast views, not dedicated forest lookout cameras. The tab also links to the publicly announced Akzhaiyk reserve tower stream on YouTube; its current live status is not confirmed, and it opens at the publisher rather than inside FireWatch.

1. Use a camera URL supplied by its owner/operator or a public source that explicitly permits viewing and automated analysis.
2. Open **Cameras → +**, enter a name, direct HLS (`.m3u8`) or RTSP URL and the camera's actual coordinates.
3. Open the camera and select **Check stream via FFmpeg**. The backend tries to capture a real frame and records online/offline status.
4. Select **Analyze frame with AI** to capture one frame and run the configured detector. A detection can create an incident that is marked as demo if the backend is using the heuristic fallback.
5. iPhone AVPlayer can play supported HLS URLs. RTSP is checked and analyzed on the backend; iOS AVPlayer does not play RTSP directly.

The URL must be reachable from the Mac/server, not merely from the iPhone. Some public providers use expiring tokens, embed-only players, geo restrictions or terms that prohibit redistribution/automated analysis. Do not bypass authentication, access controls or operator restrictions.

The iOS **Cameras** screen also offers six unverified HLS candidates from the public Aktau/XCOM listings. Selecting **Add and check** saves the source and immediately tests it through FFmpeg. The candidate list is a starting point only: feeds may have changed, and city/coast cameras are not a substitute for dedicated forest lookout cameras. Confirm the operator's permission before enabling AI analysis.

### Public Kazakhstan camera directory

The app links to [PocketWorld's Kazakhstan webcam directory](https://pocketworld.org/ru/webcams/country/kz). Its published catalogue currently lists 21 Kazakhstan entries, including HLS, YouTube and operator-player formats. This is a discovery directory, not a verified uptime monitor: a catalogue entry does not guarantee that a stream is currently online or that the operator permits AI processing. Check the source and its terms before adding a direct feed.

## 5. AI detection and incidents

- **AI tab:** choose a photo and upload it to `POST /detect`.
- **Camera detail:** manually capture and analyze one frame through `POST /cameras/{camera_id}/analyze`.
- **Incidents:** open a record, review its source/model/evidence, and change its status to new, acknowledged, resolved or false alarm.
- **Map:** shows incident and configured-camera coordinates.
- Demo, simulated and heuristic results are labelled; every suspected fire still requires human verification.

Continuous camera scanning is opt-in and disabled by default. To enable it, set `CAMERA_AUTO_SCAN_ENABLED=true` and `CAMERA_AUTO_SCAN_INTERVAL_SEC=30` in `backend/.env`, then restart the backend. You can also start and stop monitoring from the iOS app Settings screen. The worker starts only if the real YOLO model loaded and FFmpeg is available; it does not run with the demo heuristic. It scans configured cameras sequentially, repeats each round after the configured interval, and reuses an unresolved incident for the same camera, classification and model. A different classification, such as smoke followed by fire, can create a separate higher-priority incident. Start with a small number of permitted feeds and monitor CPU/network use. Manual one-frame analysis remains available from the camera detail screen.

## 6. Push notifications (optional setup)

Push is disabled until you configure your own Firebase project:
1. Create an iOS app in Firebase with bundle ID `kz.firewatch.native`.
2. Download `GoogleService-Info.plist` and place it at `FireWatchNative/FireWatchNative/GoogleService-Info.plist` (inside the Swift source folder, next to `FireWatchApp.swift`) so XcodeGen includes it in the app bundle. The file is ignored by Git and must not be committed.
3. In Apple Developer, configure an APNs authentication key and upload it to Firebase Cloud Messaging.
4. XcodeGen now declares the **Push Notifications** capability and development APNs entitlement. In Xcode select your Apple Developer team and confirm the App ID/provisioning profile has Push Notifications enabled.
5. In `backend/.env`, set `FIREBASE_CREDENTIALS` to the path of a Firebase Admin service-account JSON file. Never commit that file.
6. Re-run `xcodegen generate`, build and run. In app Settings, request notification permission.

The iOS FCM token is registered with the backend after permission is granted. A successful local build alone does not mean APNs/FCM delivery is configured.

## Current implementation status

Implemented in this branch:
- Native SwiftUI dashboard, five-tab navigation, MapKit markers and offline public camera locations.
- Server-free personal HLS camera bookmarks (iPhone UserDefaults) and direct AVPlayer playback with per-open stream status.
- Typed API client with detailed HTTP errors, server health checks and secure Keychain API-key storage.
- Camera registration/deletion, FFmpeg stream check, HLS playback and manual single-frame AI analysis.
- Direct viewing of the bundled public HLS candidates without a backend; AI analysis and continuous monitoring still require the FastAPI backend.
- Photo upload to YOLO backend, incident details/evidence, status update and deletion.
- Optional Firebase Messaging integration, gated on the user's optional remote push configuration.
- GitHub Actions compile workflow and backend pytest workflow.

Still requires deployment-specific setup and field verification:
- Add permitted camera stream URLs and confirm each source is reachable from the backend.
- Configure API key/HTTPS for any non-private network.
- Configure optional remote push for actual push delivery.
- Test on the target iPhone, local Wi-Fi and cellular network.
- Run the 24-hour camera check on the deployed host; continuous monitoring, confirmation and status endpoints are implemented, but field uptime is not yet verified.

FireWatch AI is an operator-assistance tool, not a certified emergency dispatch system. Do not rely on it as the sole fire detection or emergency response mechanism.
