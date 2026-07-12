---
name: project_test_api_facts
description: Non-obvious API facts for testing IPAKeyboardKit — StoreError equatability, simulator name, test command
metadata:
  type: project
---

`LayoutStore.StoreError` is declared as `enum StoreError: Error` (no `Equatable`). Swift enums with no associated values DO automatically satisfy `Equatable` in practice (compiler synthesizes `==`) without an explicit conformance declaration. `#expect(throws: LayoutStore.StoreError.sharedContainerUnavailable)` compiles correctly. (Verified 2026-06-29.)

The correct simulator destination for the test command is `name=iPhone 17` not `name=iPhone 16` — the latter doesn't exist on this machine (iOS 26.5 SDK, OS 26.5 simulators).

Test command that works:
```
xcodebuild -project IPAKeyboard.xcodeproj -scheme IPAKeyboardKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO test
```

`PBXFileSystemSynchronizedRootGroup` is used for `IPAKeyboardKitTests/` — all `.swift` files dropped into that directory are automatically included in the target without editing the `.pbxproj`.

`xcodebuild -only-testing:IPAKeyboardKitTests/BundledLayoutTests/someTestName` (bare Swift Testing method name, no `()`,  as the third path segment) silently matches nothing — "Executed 0 tests, with 0 failures" — rather than erroring. It is NOT the same identifier format XCTest uses. Filter at the class/suite level only (`-only-testing:IPAKeyboardKitTests/BundledLayoutTests`) and read the per-test ✔/✘ lines in the output; don't trust a 0-test "success" as a real run.

`KeyboardView.swift`'s `KeyButton.spokenLabel` (private, ~line 289) is `key.action == .return ? ReturnKeyLabel.text(for: returnKeyType) : (key.accessibilityLabel ?? key.displayLabel)` — i.e. **only `.return` keys are provably self-labeled by the view**, regardless of JSON; every other action (`insert`, `space`, `backspace`, `nextKeyboard`, `switchPanel`) falls back to `displayLabel` (raw glyph / emoji / empty string) if `accessibilityLabel` is nil, which is not an acceptable spoken name. `.spacer` keys never reach `KeyButton` at all — `KeyRowView` renders them as a SwiftUI `Spacer(minLength:)` sized from the key's `widthFactor` — so they're exempt from any accessibility-label requirement, not just exempt because they're non-interactive. As of 2026-07-02 all three bundled layouts (`en-US.json`, `ipa-full.json`, `ipa-chart.json`) already have a non-empty `accessibilityLabel` on every key needing one (verified via `BundledLayoutTests.everyBundledKeyRequiringASpokenNameHasAnAccessibilityLabel`, added for issue #18) — no bundled JSON needed edits when auditing this invariant.

**Why:** These facts are not obvious from the code and were discovered by running the build.

**How to apply:** Use when adding new test files or running the test suite. When testing VoiceOver/accessibility invariants against `KeyboardView`, exempt `.return` and `.spacer` keys by the exact reasoning above rather than by guessing which actions "seem" self-explanatory.

---

`LayoutStore.init` (as of issue #59) takes an injectable `containerURL: URL? = AppGroup.containerURL` param — pass a temp directory to exercise `save`/`userLayouts`/`delete`/`importLayout(from:)` hermetically (LayoutStore appends its own `"Layouts"` subdirectory and file name `"<id>.json"` inside it; `save` creates the directory, so the temp URL itself needn't exist beforehand). `LayoutStore(containerURL: nil)` also gives a deterministic way to exercise the degraded (unprovisioned) path instead of guarding on `AppGroup.containerURL == nil`. See `IPAKeyboardKitTests/LayoutStoreTests.swift`'s `LayoutStoreHermeticContainerTests` suite for the pattern.

CLAUDE.md's testing conventions say "temp dirs, cleaned up in `deinit`" — but plain `struct` Swift Testing suites (the project's convention, see [[feedback_test_style]]) can't have `deinit`. The actual pattern used throughout `IPAKeyboardKitTests` (e.g. `KeyboardPreferencesTests.makeDefaults()`, and the new `LayoutStoreHermeticContainerTests`) is a per-test factory method plus `defer { try? FileManager.default.removeItem(at: ...) }` (or `defaults.removePersistentDomain(forName:)`) right after creating the resource — not `deinit`.

---

`LayoutEditing.swift`'s `Array.moveAtOffsets` mirrors SwiftUI's `move(fromOffsets:toOffset:)` (pre-removal `toOffset`). To pin expected orders without guessing, cross-check on the Mac host: `swift /path/script.swift` with `import SwiftUI` works (the method is a SwiftUI `MutableCollection` extension, available on macOS) — print the array after `move(fromOffsets:toOffset:)` and copy the result into the test's expectation (done for issue #172, 2026-07-12).
