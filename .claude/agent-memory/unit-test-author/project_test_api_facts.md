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
