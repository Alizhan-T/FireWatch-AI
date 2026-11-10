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

The bundled list includes XCOM Aktau amphitheater 15A/15B and Yntymak Square, which XCOM's public page currently labels "online", along with published direct HLS candidates for other Aktau views. Camera availability is **not** hard-coded as online: the app probes each .m3u8 playlist over HTTPS at runtime, places responding manifests in a separate section, and leaves failures accessible for manual retry. A successful playlist probe does not prove that video segments can be decoded, that a stream will remain online, or that the operator approves automated AI analysis.

The publicly listed HLS URLs are dependent on independent providers; FireWatch cannot guarantee uptime or work around access controls. Using the app to view them needs internet, but no FireWatch server. Sources: https://xcom.kz/cam/ and https://pikniktv.info/viewtopic.php?start=50&t=9395.

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
