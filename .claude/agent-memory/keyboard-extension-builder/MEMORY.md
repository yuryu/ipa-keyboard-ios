# Memory index

- [KeyboardExtension folder target membership](project_keyboardextension-folder-syncs-to-kit.md) — KeyboardExtension/ now syncs to the appex target (Info.plist excepted); new files join it directly
- [Extension runs unsigned in simulator](project_extension-runs-unsigned-in-simulator.md) — enable via Settings UI (not AppleKeyboards defaults); no Keyboard AX element; adjustTextPosition counts UTF-16
- [Simulator visual verification](project_simulator-visual-verification.md) — xcodebuild clones sims unless -parallel-testing-enabled NO; rotation needs an XCUITest attachment
- [SwiftUI gesture limits / alternates popup](project_swiftui-gesture-limits-alternates-popup.md) — LongPress+Drag compositions freeze List scrolling; taps don't fail on duration; use the UIKit tracker overlay
- [VoiceOver custom-actions testing](project_voiceover-custom-actions-testing.md) — XCUITest can't invoke custom actions; unit-test the pure mapping, manual VO check stays with the user
