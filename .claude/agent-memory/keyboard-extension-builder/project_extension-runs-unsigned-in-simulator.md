---
name: extension-runs-unsigned-in-simulator
description: The unsigned keyboard extension runs on the simulator — enable via Settings UI (not AppleKeyboards defaults); custom keyboards expose no Keyboard AX element
metadata:
  type: project
---

Verified 2026-07-04 (iPhone Air, iOS 26.5 simulator, issue #70 fix round): the keyboard extension **can be enabled and exercised on a simulator from a fully unsigned build** (`CODE_SIGNING_ALLOWED=NO build-for-testing`, `simctl install` the built `IPAKeyboard.app`). Provisioning is NOT a blocker for extension-side empirical verification; only the App Group container is nil (LayoutStore degrades to bundled defaults as designed).

**Prefer ad-hoc signing now (2026-08-02, issue #210):** build with `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-` instead of `CODE_SIGNING_ALLOWED=NO` and you get everything above *plus* a live App Group container — still with no certificate, provisioning profile, or Apple account, because `-` resolves to "Sign to Run Locally" on a simulator destination. Confirmed by `simctl get_app_container <udid> net.yuryu.IPAKeyboard groups`, which prints a real path for the ad-hoc build and nothing for the unsigned one. Use unsigned only when deliberately exercising the nil-container degradation.

Hard-won specifics:

- **Enabling**: `simctl spawn <udid> defaults write com.apple.Preferences AppleKeyboards -array …` does *not* reach the live text-input system (even after device reboot — the Settings list stays unchanged). The working path is the Settings app UI: General → Keyboard → Keyboards (`cells["AddNewKeyboard"]`) → tap the app name. Automatable once via a throwaway XCUITest driving `XCUIApplication(bundleIdentifier: "com.apple.Preferences")`.
- **Switching to it in a test**: globe *tap*-cycling is unreliable; long-press the system globe (`app.buttons["Next keyboard"]`, sits below the keyboard) and tap the picker cell whose label begins with the extension's display name ("KeyboardExtension — IPAKeyboard").
- **Accessibility shape**: while a custom keyboard is up there is **no `Keyboard`-type element** (`app.keyboards` matches nothing — a system keyboard shows `Keyboard` + `Key` elements instead). Our keys surface app-wide as `StaticText` with their `key-*` identifiers in a separate window at the bottom of the screen. Host-app previews render the *same* identifiers, so disambiguate by geometry (extension keys lay out below the focused text field) — see `SystemKeyboardSmokeUITests.extensionKey(_:)`.
- `XCUICoordinate.press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)` drives the space-bar hold+drag cursor mode fine; 8 pt/step grid means a 12 pt drag is exactly one step.
- Empirical result pinned by those tests: `adjustTextPosition(byCharacterOffset:)` counts **UTF-16 code units** (a -2 offset from after "ə̃" lands between "t" and "ə̃", not before "t").

**How to apply:** any extension-behavior claim ("works only on device", "needs provisioning") should be tested against this recipe first; run `SystemKeyboardSmokeUITests` (it skips when the keyboard isn't enabled). Related: [[simulator-visual-verification]].
