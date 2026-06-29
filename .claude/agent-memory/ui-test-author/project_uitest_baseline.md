---
name: project_uitest_baseline
description: Established UITest baseline — what exists today, identifiers in use, simulator constraint
metadata:
  type: project
---

Baseline UITests committed 2026-06-29. All 9 test executions passed on iPhone 17 (OS 26.5) — iPhone 16 is not available in this environment.

**Files:**
- `IPAKeyboardUITests/IPAKeyboardUITests.swift` — main functional tests (`@MainActor`, async setUp/tearDown)
- `IPAKeyboardUITests/ContentScreen.swift` — page object for root `ContentView`; `@MainActor struct`
- `IPAKeyboardUITests/IPAKeyboardUITestsLaunchTests.swift` — launch screenshot + assertion, `runsForEachTargetApplicationUIConfiguration = true`

**Accessibility identifiers added to host app (`IPAKeyboard/ContentView.swift`):**
- `"content-view-globe-image"` on the globe SF Symbol `Image`
- `"content-view-hello-world-label"` on the `Text("Hello, world!")`

No identifier was added to the root `VStack` — the text/image identifiers are sufficient for current smoke tests.

**Simulator constraint:** No iPhone 16 simulator present; use `name=iPhone 17` (id `29DAA8FD-BAAE-41C1-AB47-9A3E10B4D8F1`, OS 26.5). IPad simulators also available.

**Why:** These are placeholder smoke tests against the stock SwiftUI template. Update `ContentScreen` and add new screen objects as real settings/onboarding/layout-management UI is built.

**How to apply:** When writing new tests, check `ContentScreen.swift` for existing element accessors before querying the app directly. Add new screen objects (e.g. `LayoutListScreen`, `OnboardingScreen`) as new files in `IPAKeyboardUITests/` — the target uses `PBXFileSystemSynchronizedRootGroup`, so no project-file edits needed.
