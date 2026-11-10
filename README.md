# 🔥 FireWatch AI — native SwiftUI iPhone app

**Current direction: SwiftUI-only, camera viewing first, backend optional.**

FireWatch AI is an iOS 17+ prototype for viewing permitted public or personally supplied HLS camera feeds. The iPhone app is written entirely in **Swift / SwiftUI**. The former Flutter client has been removed.

## Run the iPhone app (no FireWatch server required)

On a Mac with Xcode:

    brew install xcodegen
    cd FireWatchNative
    xcodegen generate
    open FireWatchNative.xcodeproj

Choose an Apple development team in Xcode and run on an iPhone or iOS Simulator.

Without configuring any FireWatch server, you can:
- Open a bundled shortlist of public Kazakhstan HLS (.m3u8) camera **candidates** directly in AVPlayer.
- Add and remove personal HLS links; bookmarks are stored on the iPhone via UserDefaults.
- See the catalogue camera locations on a MapKit map.
- Open the operator website and catalogue sources.
- See whether AVPlayer can prepare a stream, with a clear error when it fails.

**Caution:** Candidate listings are *not* proof of live availability, operator permission for automated analysis, or forestry coverage. The built-in Aktau cameras show city/coast views rather than dedicated forest monitoring towers. Network access is still needed to watch the streams.

## Kazakhstan-only live camera catalogue (no external redirect)

The Cameras tab lists only Kazakhstan public HLS candidates. An entry opens **inside the SwiftUI app** in an AVPlayer-based screen; the primary camera row does not open Safari or a catalog site. The Akzhaiyk video (YouTube) opens an embedded player in-app, subject to the publisher allowing embeds.

The curated list includes 7 published XCOM Aktau HLS streams. A GitHub Actions HTTP playlist audit on 10 November 2026 found 7 responding playlists out of 8 candidates; the failing Caspian 4th microdistrict URL was excluded. XCOM's own page currently labels amphitheater 15A/15B and Yntymak Square as "online". These results are **point-in-time checks from the GitHub runner**, not real iPhone frame-playback verification. Camera availability is **not** hard-coded as online: the app probes each .m3u8 playlist over HTTPS at runtime, places responding manifests in a separate section, and leaves failures accessible for manual retry. A successful playlist probe does not prove that video segments can be decoded, that a stream will remain online, or that the operator approves automated AI analysis.

The publicly listed HLS URLs are dependent on independent providers; FireWatch cannot guarantee uptime or work around access controls. Using the app to view them needs internet, but no FireWatch server. Sources: https://xcom.kz/cam/ and https://pikniktv.info/viewtopic.php?start=50&t=9395.

## Kazakhstan city cameras and training SOS (November 2026)

The camera picker now includes **Astana, Almaty, Semey and Aktau**:
- Aktau: seven public direct HTTPS HLS streams.
- Almaty: two *newly probed* Shymbulak HTTPS HLS streams and publisher alternatives. A GitHub Actions manifest test on 10 November 2026 received valid HLS playlists from **9/9** catalogue links (seven Aktau + two Almaty), but this is **not** proof that video segments render on a physical iPhone, that streams remain available, or that the operators permit automatic analysis.
- Astana: a published Atameken Business city livestream shown inside the app using a YouTube embed; the owner may block embedding or terminate the live session.
- Semey: the Central Square Geocam/gorset.kz publisher page is still marked *unstable* and may not play on an iPhone. There is no verified direct HLS for Semey yet.

**DEMO simulation**: Choose «Имитировать пожар», select a city, and tap «Запустить DEMO». FireWatch opens a camera-backed training screen (defaults to a camera from the selected city if available; falls back to an available catalogue option), with an animated **artificial flame/smoke overlay** and persistent, unmissable «DEMO / НЕ РЕАЛЬНЫЙ ПОЖАР» label. The original stream is not changed or recorded. The actual camera city is shown separately from the simulated incident city to avoid confusion.

Starting a DEMO requests iPhone notification permission when required and schedules a **local** «SOS · ДЕМО · УЧЕБНАЯ ТРЕВОГА» notification. Foreground banners are supported and there is a button to re-send the test. This is entirely on-device: no APNs/Firebase service, backend, emergency-number call, dispatch, broadcast or third-party message occurs. Denied permissions are reported inside the app. Manually entered non-DEMO events cannot produce this test SOS payload.

Physical-device verification is still required for stream decoding, permissions and notifications. Real autonomous fire/smoke detection is **not implemented by this feature** and requires a separately evaluated Core ML model or the existing optional server. Public viewing alone does not authorize AI analysis of third-party feeds.

## Improved training VFX and AI explanations (11 November 2026)

- The training camera overlay uses a continuously animated **procedural** fire effect: irregular flame tongues, rising translucent smoke, embers, and warm light scatter. It no longer uses the cartoon SF Symbols flames/clouds. This is still synthetic VFX, not actual captured fire footage, and is clearly labelled DEMO on screen.
- The image-analysis screen explains what was detected (fire, smoke, both, or neither), what the score means, and what an operator should verify next. Per-object findings can be shown when returned by the server.
- Actual YOLO model results and demo color heuristics are visibly separated. Demo heuristics cannot automatically create an incident from the iOS image-analysis screen. No AI text-generation service or LLM prompts are implied.
- Core ML now respects image orientation and requires explicit class names "fire"/"smoke", rather than guessing what numeric class IDs 0/1 mean. Models with ambiguous labels fail clearly rather than swapping fire and smoke.
- No real fire detection is implied by a DEMO overlay or by a single image. Public camera feeds remain subject to operator permissions. Local test SOS does not notify emergency responders.

## Astana playback and reliability update (11 November 2026)

- The Astana publisher catalogue now prioritizes the **Atameken Business “Astana City View 24/7”** YouTube programme published on 24 February 2026 (source: https://www.youtube.com/watch?v=sR4YuJ-6UO4). The January 2026 publisher programme remains a fallback, and the Khan Shatyr publisher page remains an explicitly unverified alternative. YouTube may have ended either stream or prohibited embedding; **neither is a verified direct HLS feed**.
- The iPhone offers two separate ways to view a publisher's content inside FireWatch: a standard YouTube embed and a tapped in-app Safari publisher browser. The embedded request identifies the FireWatch project with an HTTP Referer as required by [YouTube's embed policy](https://support.google.com/youtube/answer/171780?hl=en) to avoid error 153; successful playback still depends on the publisher. It reports web loading failures; a loaded page is not proof of live decoded frames. No DRM bypass or media extraction.
- Add your own permitted HLS stream under **Cameras → Connect my HLS camera** and choose **Astana** as the actual city. The DEMO scenario will prefer a city-matched personal HLS feed before public publisher alternatives. Previously saved personal links without a city remain supported.
- The AVPlayer live stream controller now watches media playback time to notice a frozen stream when AVPlayer still reports “playing”. Reconnects remain bounded and can fail if the source is actually offline; network diagnostics and the retry button remain available.
- The app still cannot guarantee that public Astana feeds work continuously, nor can it do unattended AI inference on publisher YouTube streams without source permission and a separately tested capture/inference pipeline.

## What requires the optional backend?

The existing backend/ directory is retained because real YOLOv8n fire/smoke inference currently runs there, not on the iPhone. Running FireWatch without a backend **does not provide automatic fire detection, incident persistence, stream scanning or remote push alerts**.

| Feature | iPhone only | Optional backend |
|---|---|---|
| Watch public HLS feeds | Yes | Not needed |
| Store personal HLS bookmarks | Yes | Not needed |
| Show public camera locations | Yes | Not needed |
| Run YOLOv8 fire/smoke detection | No | Yes |
| Scan RTSP feeds via FFmpeg | No | Yes |
| Persist incidents and evidence in SQLite | No | Yes |
| Firebase/APNs remote notifications | No | Yes, with additional setup |

Backend runs on a separate machine or hosted environment when needed. Its configuration is **not required** for basic camera viewing. If the project later becomes fully local AI, a compatible model must be deployed with Core ML + Vision and validated on physical iPhone hardware. The PyTorch .pt file in the backend does not automatically run inside SwiftUI.

For optional AI backend usage see [Native iOS instructions](FireWatchNative/README.md) and [server deployment guidance](deploy/README.md).

## Repository layout

    FireWatchNative/     Only supported iOS app; Swift / SwiftUI / MapKit / AVPlayer
    backend/             Optional FastAPI, YOLOv8n, FFmpeg, SQLite, FCM
    .github/workflows/   Native iOS build and backend CI
    deploy/              Optional Docker/Caddy/HTTPS deployment
    compose.yaml         Optional server configuration

## Stability and QA

See [iPhone reliability checklist](docs/STABILITY_CHECKLIST.md) for simulator tests, bounded HLS retries, physical-device verification and conditions for claiming a camera is online.

## Safety and transparency

- Video stream URLs should be accessed only where the operator allows it.
- A publicly viewable stream is **not** a grant of permission to record, redistribute, or run automated AI inference on it.
- Camera status is checked when opened; a ready AVPlayer item is not an uptime guarantee.
- The built-in catalog is a source of test links, not operational forest surveillance.
- The current product is an experimental operator-assistance tool, not a certified emergency detection or dispatch service.
