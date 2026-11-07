# FireWatch Native iOS — SwiftUI starter

This is a native SwiftUI client starter for the existing FireWatch-AI FastAPI backend. It is **not** a complete migration or a tested Xcode build. No Flutter runtime is used.

## Open in Xcode
1. Create a new Xcode **iOS App** project named `FireWatchNative`, interface SwiftUI, language Swift, deployment target iOS 17 or later.
2. Remove Xcode's generated `ContentView.swift` and app entry file.
3. Add all `.swift` files from `FireWatchNative/` to the Xcode app target (copy items if needed).
4. Add `NSLocalNetworkUsageDescription` (e.g. `Connect to the FireWatch backend on your Mac`) to the app Info settings.
5. For local HTTP development only, configure App Transport Security with an exception appropriate to your development server. Prefer HTTPS in production. Do not disable ATS globally for release builds.
6. Run the backend on the Mac listening on `0.0.0.0:8000`. In the iPhone app's Settings, use `http://<Mac-LAN-IP>:8000` rather than `localhost`.
7. Select your iPhone in Xcode, set signing team, build and run.

## Implemented
Dashboard stats, incidents list, MapKit markers, cameras list, server settings, live API requests to `/stats`, `/incidents`, `/cameras`, error feedback, pull-to-refresh, demo labels.

## Still to implement
AI upload/detection flow, camera live playback, incident detail/actions, APNs registration, auth/security, production network policies, accessibility review, integration tests and Xcode build validation.
