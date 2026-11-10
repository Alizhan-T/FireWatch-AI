# FireWatch Native — stability checklist

The supported iOS app is SwiftUI in FireWatchNative/. Public HLS viewing works without any FireWatch server. AI inference and incident management still need the optional backend.

## CI gate (required before merging)

- Generate the Xcode project with XcodeGen.
- Build the FireWatchNative scheme for the iOS Simulator.
- Run FireWatchNativeTests on an available iPhone Simulator: camera bookmark persistence, duplicates, invalid URLs. These tests should fail the CI job, not be skipped.
- For optional backend changes, require the existing backend, real YOLO/HLS pipeline, and Docker tests.
- A green Simulator build or test suite **does not prove** a public HLS feed works on a real iPhone.

## Required physical iPhone smoke checks (iOS 17+)

1. Start with **no** FireWatch server configured: Dashboard, Map, and Cameras must open without a connection warning or an infinite spinner.
2. Open a public HLS candidate on both Wi-Fi and mobile data. Do not mark it verified until video frames actually play. Document the observed URL, operator and timestamp.
3. Use a deliberately offline/unreachable HLS address. The app should report a timeout, stop after at most two automatic retries, and allow an explicit retry.
4. Open a working stream, lock the phone or background the app, then reopen it. Streaming should stop in background and restart after foreground activation.
5. Add a personal HLS URL with a query string, force quit the app, relaunch and confirm the bookmark still exists; then delete it and relaunch.
6. Without a server, revisit all five tabs. No missing-server error should block direct camera viewing.
7. Configure an optional AI backend, then disconnect it during a request. Switching back to standalone mode must not show stale cameras or incidents from the old server.
8. Compare behavior after network loss, Wi-Fi/mobile handover, poor LTE and a source serving HTTP errors or expired playback URLs.
9. Observe battery, memory, network use and any crash logs during at least one hour of representative viewing. Longer real-world trials must precede any reliability claims.

## Camera catalogue policy

- Six bundled Aktau HLS entries are *candidates*, not verified working feeds or forest lookout cameras.
- Never change a candidate to “online” solely because its URL exists or AVPlayer reports ready; require frame playback.
- Check operator terms before ingesting/recording/automatically analyzing footage. Public viewing alone does not imply AI-processing permission.
- Do not store private tokens or passwords in URLs in plain UserDefaults; use Keychain for sensitive credentials in a future authenticated-camera design.
- Availability and authorization need periodic re-verification; the app cannot guarantee third-party camera uptime.

## Remaining work before real wildfire monitoring

- Implement a separately validated on-device Core ML + Vision detector (tracked in issue #4). Existing backend YOLO .pt weights do not run on the iPhone by themselves.
- Test false positives/negatives with many labelled day/night/fog/sunset wildfire and non-fire frames, not only the bundled two fixtures.
- Design iOS foreground/background limits explicitly: normal iOS apps cannot promise continuous 24/7 background HLS AI scanning.
- Obtain permission and verify actual nature/forest feeds (tracked in issue #5).
- Set up crash reporting with a documented consent/privacy policy before wider distribution.
- Add an iPhone-based regression pass before TestFlight; stable production deployment should also include accessibility and security review.

## Running locally

    brew install xcodegen
    cd FireWatchNative
    xcodegen generate
    open FireWatchNative.xcodeproj

Run the FireWatchNative scheme in Xcode on an iPhone or Simulator. XCTest checks are in FireWatchNativeTests/. GitHub Actions runs them automatically.

**Important:** FireWatch is an experimental monitoring aid, not a certified emergency dispatch tool.
