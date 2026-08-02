---
name: ui-testing
description: Authoring standards, flake rules, and run instructions for XCUITests in the IPAKeyboardUITests target. Use BEFORE writing a new UI test, modifying or debugging an existing one, or running the UI-test suite.
---

# UI testing (IPAKeyboardUITests)

Binding guidance for all XCUITest work in this repo. Subagents without the Skill tool read this file directly (`.claude/skills/ui-testing/SKILL.md`).

## Authoring standards

- Universal app (iPhone + iPad): no hard-coded coordinates; tests must pass on both idioms.
- Locate elements by `accessibilityIdentifier` first, then label, then type query — never index or coordinates. If a stable identifier is missing, add it in app code (or call out the exact string to add).
- **`confirmationDialog` action buttons need `.firstMatch`.** On iOS 26 one identified dialog action surfaces as two nested `Button` elements both carrying the identifier, so a plain `app.buttons[id]` query fails with "Multiple matching elements found" — at *tap* time, since `waitForExistence` tolerates multiplicity. The app can't control the dialog's hierarchy, so this is a test-side convention, not a bug to fix in the view (issue #192; same family as the identifier bleeds tracked by #83).
- Synchronize with `waitForExistence(timeout:)` / expectations, never `sleep`.
- **A live App Group container is a precondition, not a maybe.** Every lane that runs this suite signs the app — locally automatic under the project's team, in CI ad-hoc (`CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-`, no credentials needed on a simulator destination) — so `AppGroup.containerURL` is non-nil and saves/forks/imports persist. Tests that need persistence must **fail** when it's missing, never `XCTSkip`: a skip reads as a pass and would hide a signing regression (issue #210). The nil-container degraded paths are covered deterministically in `IPAKeyboardTests/LayoutLibraryTests.swift` via `LayoutStore(containerURL: nil)` — don't re-cover them here.
- Hermetic, order-independent tests: drive state via `launchArguments`/`launchEnvironment`, `continueAfterFailure = false`. Persisted user layouts now survive across launches *and across suites*, so any suite whose assertions depend on the library's contents must pass `LibraryScreen.resetLayoutsArgument`. Use the Screen/Page-Object pattern — the `*Screen.swift` files in `IPAKeyboardUITests/` are the current page objects (`LibraryScreen`, `OnboardingScreen`, `KeyEditorScreen`, `SymbolReferenceScreen`); extend them before inventing new ones, and note `ContentScreen.swift` is a retired tombstone, not a screen object. Reuse existing identifiers and launch args before adding new ones.
- Name tests `test_<flow>_<expectation>`; keep arrange/act/assert clear. Attach screenshots on failure; use `addUIInterruptionMonitor` for system alerts.
- The keyboard extension is a system keyboard; enabling it and "Allow Full Access" are environment preconditions you cannot script. Prefer host-app flows; when full keyboard E2E is infeasible, build the best approximation and state the limitation.
- IPA text is exact, grapheme-cluster-aware Unicode (`ɡ` U+0261, `ː` U+02D0, `ɹ` U+0279) — assert on exact scalars.

## Flake rules

From the issue #119 flake sweep; binding on all new XCUITests. The helper code is readable in `IPAKeyboardUITests` — what's listed here is the non-obvious *why*:

- **Tap-after-scroll needs a settle probe** — inertial `swipeUp` leaves the list decelerating and the next tap is swallowed as a scroll-stop touch. Use `revealTapAndSettle` / `LibraryScreen.openRow` (LibraryScreen.swift); they end after one sentinel-probe re-tap and the *caller's* `.postNavigation` first-wait supplies the full window — don't add a second long wait inside helpers.
- **Tests presenting remote system UI (share sheet) must dismiss in-test AND register a terminate backstop** — a live sheet makes the next `launch()` kill the app mid-presentation. Follow `test_exportBuiltIn_presentsShareSheet`: `dismissShareSheet`, an `addTeardownBlock` that terminates and waits for `.notRunning`, and tearDown screenshots guarded by `app.state != .notRunning`. The iOS 26 sheet is out-of-process with no Close/Cancel button in the app's hierarchy, so dismissal is coordinate-based (tap the dimmed area, then drag the sheet off the bottom edge); probe sheet signatures in both the app and SpringBoard hierarchies plus `app.popovers` (iPad). Don't assert on the underlying screen after dismissal — it never left the hierarchy, so the wait is pure timeout burn.
- **Never poll `app.keyboards` for typing readiness** — it burns the full timeout whenever the simulator's Connect Hardware Keyboard setting suppresses the software keyboard. Use the event-driven `waitForKeyboardFocus` gate (`hasKeyboardFocus == true` predicate, ~5s, one re-tap on miss; duplicated by design in SymbolReferenceScreen.swift, KeyEditorScreen.swift, and SystemKeyboardSmokeUITests.swift — the latter gates the smoke suite's skip decision so a swallowed focus tap can't masquerade as "extension not enabled").
- **Orientation**: `IPAKeyboardUITestsLaunchTests.tearDown` restores portrait and terminates (it was the only source of leftover-landscape); the functional suites' portrait one-liners in setUp are belt-and-braces — keep both, and do NOT add per-suite window-geometry gates (redundant, and a full-timeout burn on a legitimately-landscape iPad).
- **Negative-assertion polarity**: something that existed and is going away gets `waitForNonExistence(timeout:)` (eventual state), not `XCTAssertFalse(waitForExistence(2))` (snapshot race). Keep the `XCTAssertFalse` form only for things that must *never* appear, and run that probe first so its window doubles as the settle time the wrong outcome would need.

## Running the suite

Run recipes, the zero-tests false-green guard, and the CI lane specifics (boot gate, sequential execution) live in the `testing-and-ci` skill (`.claude/skills/testing-and-ci/SKILL.md`) — read it before running the suite.

The system-keyboard smoke tests are the local trap: they need the simulator's **Connect Hardware Keyboard turned off** and the keyboard enabled in Settings, neither of which a test can arrange. Without those they skip, and a skip reads as a pass. Confirm the preconditions or report the run as inconclusive.
