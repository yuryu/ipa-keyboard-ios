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
never transiently shows stale rows before they'd be cleared) and, since
issue #191, only for the caller that claims
`LayoutLibrary.LaunchResetGate.process` — once per process, not per
instance. Calls
`store.deleteAllUserLayouts()` in a do/catch that swallows only the expected
`StoreError.sharedContainerUnavailable` (the pre-provisioning case — every
unsigned build today) and hits `assertionFailure` on any other error, then
`preferences.resetAll()`, which always runs (against the fallback
process-local `.standard` suite before provisioning).

**New kit API** (both added, following existing doc-comment/no-throw style):
- `LayoutStore.deleteAllUserLayouts() throws` (`IPAKeyboardKit/Store/LayoutStore.swift`) — removes every `*.json` in the user-layouts directory; throws `StoreError.sharedContainerUnavailable` when the container is nil (same contract as `save`/`delete`), and is a silent no-op if the directory doesn't exist yet.
- `KeyboardPreferences.resetAll()` (`IPAKeyboardKit/Store/KeyboardPreferences.swift`) — clears `activeLayoutID` and the whole `hiddenSymbols` dictionary (every layout's curation, not just one). Never throws (same as the rest of the type).

**Retired swipe-to-delete self-healing:** both `KeyEditorUITests.swift` and
`ImportExportUITests.swift` used to delete leftover forked/imported rows via
`row.swipeLeft()` + tap `app.buttons["Delete"]` at the start of every test
(or before/after the import in `ImportExportUITests`). Both now just add
`LibraryScreen.resetLayoutsArgument` to `app.launchArguments` (`KeyEditorUITests.setUp()`; `ImportExportUITests`'s shared `launch()` helper) and the
swipe-based helpers (`cleanUpForkedSourceLayout()`,
`cleanUpImportedLayoutRows()`) were deleted entirely — `openSourceLayoutDetail()` now just waits for the library, and the valid-import test (then `test_importValid_succeedsOrDegradesGracefully`, renamed `test_importValid_persistsImportedLayout` in issue #210) collapsed from a double-launch (clean, terminate, relaunch-with-import) into one `launch(importJSON:)` call, combining a reset arg and an import env var in the same launch.

**Combining the two hooks was NOT actually safe until issue #191** (fixed
2026-07-25). The original reasoning recorded here — "reset is in
`LayoutLibrary.init`, import runs later from `LayoutListView.onAppear`, so
order is guaranteed" — missed that SwiftUI re-evaluates
`@State private var library = LayoutLibrary()` on every re-init of the view
struct, and the import's own `reload()` provokes exactly that: instrumented
launch showed `init #1 → reset → import (userLayouts=1) → init #2 → reset`,
the throwaway deleting the just-imported layout with no error to surface.
The per-process `LaunchResetGate` is what makes the combination safe now.

**Verified 2026-07-02** on `iPhone 17 Pro Max` (OS 26.5), unsigned
(`CODE_SIGNING_ALLOWED=NO`): `IPAKeyboardKit` scheme build + full unit-test
run (284 tests, all suites) passed; `IPAKeyboard` scheme
`build-for-testing` succeeded; `-only-testing:IPAKeyboardUITests/KeyEditorUITests`
ran all 4 tests (2 pass, 2 `XCTSkip` as expected — container still
unavailable, see [[project_key_editor_flow]]); `-only-testing:IPAKeyboardUITests/ImportExportUITests`
ran all 5, all passed.

**The actual-deletion path is now exercised (2026-08-02, issue #210).** That
earlier run only ever hit the hook's no-op path, because an unsigned build
has no App Group container and so nothing was ever persisted to clear. Every
lane now signs the app (locally automatic; CI ad-hoc via
`CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-`), so forks and imports really
persist and the reset really deletes them — see [[project_uitest_baseline]].
This also makes the suite stateful *across* suites in one session, which is
what makes the hook load-bearing rather than belt-and-braces.

**How to apply:** any new UI test that persists a user layout (fork, import,
or future flows) should add `LibraryScreen.resetLayoutsArgument` to its
launch arguments instead of inventing another swipe-to-delete cleanup
helper — put it in `setUp()`/the shared launch helper, not per-test, so
every test in the class benefits uniformly.
