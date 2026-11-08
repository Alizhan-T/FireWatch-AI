# FireWatch Native — SwiftUI iOS client

Native iPhone client for the FireWatch-AI FastAPI + YOLO backend. The native client does not use Flutter.

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
- Native SwiftUI dashboard, five-tab navigation, MapKit markers.
- Typed API client with detailed HTTP errors, server health checks and secure Keychain API-key storage.
- Camera registration/deletion, FFmpeg stream check, HLS playback and manual single-frame AI analysis.
- Direct viewing of the bundled public HLS candidates without a backend; AI analysis and continuous monitoring still require the FastAPI backend.
- Photo upload to YOLO backend, incident details/evidence, status update and deletion.
- Optional Firebase Messaging integration, gated on the user's Firebase/APNs configuration.
- GitHub Actions compile workflow and backend pytest workflow.

Still requires deployment-specific setup and field verification:
- Add permitted camera stream URLs and confirm each source is reachable from the backend.
- Configure API key/HTTPS for any non-private network.
- Configure Firebase/APNs for actual push delivery.
- Test on the target iPhone, local Wi-Fi and cellular network.
- Run the 24-hour camera check on the deployed host; continuous monitoring, confirmation and status endpoints are implemented, but field uptime is not yet verified.

FireWatch AI is an operator-assistance tool, not a certified emergency dispatch system. Do not rely on it as the sole fire detection or emergency response mechanism.
