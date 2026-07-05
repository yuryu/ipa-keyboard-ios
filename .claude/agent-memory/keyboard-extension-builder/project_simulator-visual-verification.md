---
name: simulator-visual-verification
description: Gotchas when visually verifying keyboard rendering on headless simulators (cloning, rotation, screenshots)
metadata:
  type: project
---

Verified workflow facts for driving simulators from the CLI to visually check `KeyboardView` rendering (used for issue #13 appearance work):

- `xcodebuild test` on a `-destination id=<udid>` **clones** the simulator by default; the clone gets the rotation/appearance changes and your original device may be left shut down (subsequent `simctl io screenshot` fails with "Timeout waiting for screen surfaces" until re-boot). Pass `-parallel-testing-enabled NO` to run tests on the destination device itself.
- `simctl` cannot rotate a device (`simctl ui` only does appearance/contrast/content size), and when an app rotates, the captured framebuffer **stays portrait-dimensioned** — you cannot detect landscape by screenshot width. The reliable path: a throwaway XCUITest that sets `XCUIDevice.shared.orientation = .landscapeLeft`, attaches `XCTAttachment(screenshot: XCUIScreen.main.screenshot())` with `.lifetime = .keepAlways`, then `xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>`.
- `simctl ui <udid> appearance dark` + host-app screenshots is enough to verify the kit palette both schemes. (An earlier version of this note claimed the extension cannot run unsigned — **wrong**: it runs fine on a simulator once enabled through the Settings UI, see [[extension-runs-unsigned-in-simulator]].)
- Onboarding sheet blocks first-run screenshots; launch with `--uitest-skip-onboarding`.
- **Mid-gesture visuals** (e.g. the long-press alternates popup, which only exists while a finger is down — used to verify the issue #122 fix): XCUITest gesture calls block, so you can't attach a screenshot mid-press from inside the test. Instead run the UI test in the background (`xcodebuild ... test-without-building ... &`, `-parallel-testing-enabled NO` so it uses the real device) and take a `simctl io <udid> screenshot` burst (~3 fps loop) from the host during the window; locate the interesting frames afterward by file-size clustering (each screen has a stable PNG size; transitions stand out). A 0.8 s hold yields 2–3 popup frames at that rate. Time the burst from the *test case start* log line, not xcodebuild launch — warm-cache startup is ~5 s, cold is ~10+ s.

**Why:** these traps each cost real time when driving simulators headlessly.
**How to apply:** any future visual check of keyboard rendering (colors, metrics, landscape) — create a dedicated sim (`simctl create`), build-for-testing unsigned, install the app, and follow the steps above; delete the sim after.
