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

**Why:** These facts are not obvious from the code and were discovered by running the build.

**How to apply:** Use when adding new test files or running the test suite.

---

`LayoutStore.init` (as of issue #59) takes an injectable `containerURL: URL? = AppGroup.containerURL` param — pass a temp directory to exercise `save`/`userLayouts`/`delete`/`importLayout(from:)` hermetically (LayoutStore appends its own `"Layouts"` subdirectory and file name `"<id>.json"` inside it; `save` creates the directory, so the temp URL itself needn't exist beforehand). `LayoutStore(containerURL: nil)` also gives a deterministic way to exercise the degraded (unprovisioned) path instead of guarding on `AppGroup.containerURL == nil`. See `IPAKeyboardKitTests/LayoutStoreTests.swift`'s `LayoutStoreHermeticContainerTests` suite for the pattern.

CLAUDE.md's testing conventions say "temp dirs, cleaned up in `deinit`" — but plain `struct` Swift Testing suites (the project's convention, see [[feedback_test_style]]) can't have `deinit`. The actual pattern used throughout `IPAKeyboardKitTests` (e.g. `KeyboardPreferencesTests.makeDefaults()`, and the new `LayoutStoreHermeticContainerTests`) is a per-test factory method plus `defer { try? FileManager.default.removeItem(at: ...) }` (or `defaults.removePersistentDomain(forName:)`) right after creating the resource — not `deinit`.
