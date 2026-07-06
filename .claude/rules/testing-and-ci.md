---
paths:
  - "IPAKeyboardKitTests/**"
  - "IPAKeyboardTests/**"
  - "IPAKeyboardUITests/**"
  - ".github/workflows/**"
---

# Test coverage and CI lanes

Existing coverage spans kit Codable round-trips, `LayoutStore` I/O (via the injectable `containerURL` seam), schema v2 + migration, grapheme deletion, arrangement/bundled-layout checks, app view models (`LayoutDraft`, `OnboardingState`), and host library-UI flows.

CI (`macos-26`) runs two unsigned-simulator jobs:

- `build-and-test` — build-for-testing all three targets + the app-hosted unit-test and UI-test bundles, then kit unit tests and `-only-testing:IPAKeyboardTests`, sequential.
- `ui-test` — build app scheme for testing; fully boot the simulator with `simctl bootstatus -b` — launching the XCUITest runner mid-boot fails with "Busy"; run `IPAKeyboardUITests` sequentially, `-parallel-testing-enabled NO`, via `test-without-building`.

No signed/device/archive lane yet (deferred until provisioning).
