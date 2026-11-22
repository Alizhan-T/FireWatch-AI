## Summary
Briefly describe what changed and why.

## Verification
- [ ] `FireWatchNativeTests` pass (`xcodegen generate` + iOS Simulator build/test)
- [ ] `backend/tests` pass (`pytest`) if backend changed
- [ ] Confirmed DEMO overlays / heuristic fallbacks remain explicitly labelled
- [ ] Confirmed no secrets (`.env.production`, `GoogleService-Info.plist`, Firebase keys) are staged
- [ ] Reviewed [`docs/STABILITY_CHECKLIST.md`](./docs/STABILITY_CHECKLIST.md) for physical-device checks
