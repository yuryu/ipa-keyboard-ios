---
name: simulator-visual-verification
description: Gotchas when visually verifying keyboard rendering on headless simulators (cloning, rotation, screenshots)
metadata:
  type: project
---

Verified workflow facts for driving simulators from the CLI to visually check `KeyboardView` rendering (used for issue #13 appearance work):

- `xcodebuild test` on a `-destination id=<udid>` **clones** the simulator by default; the clone gets the rotation/appearance changes and your original device may be left shut down (subsequent `simctl io screenshot` fails with "Timeout waiting for screen surfaces" until re-boot). Pass `-parallel-testing-enabled NO` to run tests on the destination device itself.
- `simctl` cannot rotate a device (`simctl ui` only does appearance/contrast/content size), and when an app rotates, the captured framebuffer **stays portrait-dimensioned** — you cannot detect landscape by screenshot width. The reliable path: a throwaway XCUITest that sets `XCUIDevice.shared.orientation = .landscapeLeft`, attaches `XCTAttachment(screenshot: XCUIScreen.main.screenshot())` with `.lifetime = .keepAlways`, then `xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>`.
- `simctl ui <udid> appearance dark` + host-app screenshots is enough to verify the kit palette both schemes; the extension itself cannot run unsigned, so its `keyboardAppearance` override is code-review-only until provisioning.
- Onboarding sheet blocks first-run screenshots; launch with `--uitest-skip-onboarding`.

**Why:** the extension can't be exercised unsigned, so host-app previews on a dedicated simulator are the only visual evidence path; these four traps each cost real time.
**How to apply:** any future visual check of keyboard rendering (colors, metrics, landscape) — create a dedicated sim (`simctl create`), build-for-testing unsigned, install the app, and follow the steps above; delete the sim after.
