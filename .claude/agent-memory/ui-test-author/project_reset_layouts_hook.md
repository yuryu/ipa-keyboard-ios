---
name: project_reset_layouts_hook
description: UI-test launch hook to reset persisted user layouts (issue #27) — launch arg, kit API, and the retired swipe-to-delete self-healing pattern
metadata:
  type: project
---

Added 2026-07-02 in worktree `wf_1bab3af1-883-4` (issue #27). Extends the
`--uitest-show-onboarding`/`--uitest-skip-onboarding` launch-arg pattern
(see [[project_onboarding_flow]]) to persisted user layouts, and the
launch-environment-hook pattern already established by
`LayoutLibrary.uiTestImportEnvironmentKey` (`UITEST_IMPORT_JSON`, issue #8).

**New launch argument:** `--uitest-reset-layouts`, declared as
`LayoutLibrary.resetLayoutsArgument` (`IPAKeyboard/LayoutLibrary.swift`) and
redeclared for the test target as `LibraryScreen.resetLayoutsArgument`
(`IPAKeyboardUITests/LibraryScreen.swift`, in a new "Launch arguments"
`MARK:` section — mirrors where `OnboardingScreen` keeps its own launch-arg
statics). Checked in `LayoutLibrary.init`, applied **before** the first
`reload()` (not from `onAppear` like the import hook, since there's no error
alert to present against an attached view — this also means the library
never transiently shows stale rows before they'd be cleared). Calls
`try? store.deleteAllUserLayouts()` then `preferences.resetAll()`; both are
safe no-ops when the App Group container is unavailable (every unsigned
build today).

**New kit API** (both added, following existing doc-comment/no-throw style):
- `LayoutStore.deleteAllUserLayouts() throws` (`IPAKeyboardKit/Store/LayoutStore.swift`) — removes every `*.json` in the user-layouts directory; throws `StoreError.sharedContainerUnavailable` when the container is nil (same contract as `save`/`delete`), and is a silent no-op if the directory doesn't exist yet.
- `KeyboardPreferences.resetAll()` (`IPAKeyboardKit/Store/KeyboardPreferences.swift`) — clears `activeLayoutID` and the whole `hiddenSymbols` dictionary (every layout's curation, not just one). Never throws (same as the rest of the type).

**Retired swipe-to-delete self-healing:** both `KeyEditorUITests.swift` and
`ImportExportUITests.swift` used to delete leftover forked/imported rows via
`row.swipeLeft()` + tap `app.buttons["Delete"]` at the start of every test
(or before/after the import in `ImportExportUITests`). Both now just add
`LibraryScreen.resetLayoutsArgument` to `app.launchArguments` (`KeyEditorUITests.setUp()`; `ImportExportUITests`'s shared `launch()` helper) and the
swipe-based helpers (`cleanUpForkedSourceLayout()`,
`cleanUpImportedLayoutRows()`) were deleted entirely — `openSourceLayoutDetail()` now just waits for the library, and `test_importValid_succeedsOrDegradesGracefully` collapsed from a double-launch (clean, terminate, relaunch-with-import) into one `launch(importJSON:)` call, since the reset always runs before that same launch's injected import (reset is in `LayoutLibrary.init`, import runs later from `LayoutListView.onAppear` — order is guaranteed, so a reset arg and an import env var are safe to combine in one launch).

**Verified 2026-07-02** on `iPhone 17 Pro Max` (OS 26.5), unsigned
(`CODE_SIGNING_ALLOWED=NO`): `IPAKeyboardKit` scheme build + full unit-test
run (284 tests, all suites) passed; `IPAKeyboard` scheme
`build-for-testing` succeeded; `-only-testing:IPAKeyboardUITests/KeyEditorUITests`
ran all 4 tests (2 pass, 2 `XCTSkip` as expected — container still
unavailable, see [[project_key_editor_flow]]); `-only-testing:IPAKeyboardUITests/ImportExportUITests`
ran all 5, all passed. The reset hook itself is still only exercised on its
no-op path (container unavailable) — like the fork/persistence tests it
pairs with, it needs provisioning (#3) to verify the actual-deletion path
end-to-end.

**How to apply:** any new UI test that persists a user layout (fork, import,
or future flows) should add `LibraryScreen.resetLayoutsArgument` to its
launch arguments instead of inventing another swipe-to-delete cleanup
helper — put it in `setUp()`/the shared launch helper, not per-test, so
every test in the class benefits uniformly.
