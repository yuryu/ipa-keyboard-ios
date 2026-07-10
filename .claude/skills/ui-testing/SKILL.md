---
name: ui-testing
description: Authoring standards, flake rules, and run instructions for XCUITests in the IPAKeyboardUITests target. Use BEFORE writing a new UI test, modifying or debugging an existing one, or running the UI-test suite.
---

# UI testing (IPAKeyboardUITests)

Binding guidance for all XCUITest work in this repo. Subagents without the Skill tool read this file directly (`.claude/skills/ui-testing/SKILL.md`).

## Authoring standards

- Universal app (iPhone + iPad): no hard-coded coordinates; tests must pass on both idioms.
- Locate elements by `accessibilityIdentifier` first, then label, then type query — never index or coordinates. If a stable identifier is missing, add it in app code (or call out the exact string to add).
- Synchronize with `waitForExistence(timeout:)` / expectations, never `sleep`.
- Hermetic, order-independent tests: drive state via `launchArguments`/`launchEnvironment`, `continueAfterFailure = false`. Use the Screen/Page-Object pattern — screen objects already exist in the target (e.g. `LibraryScreen`, `ContentScreen`); extend them before inventing new ones. Reuse existing identifiers and launch args before adding new ones.
- Name tests `test_<flow>_<expectation>`; keep arrange/act/assert clear. Attach screenshots on failure; use `addUIInterruptionMonitor` for system alerts.
- The keyboard extension is a system keyboard; enabling it and "Allow Full Access" are environment preconditions you cannot script. Prefer host-app flows; when full keyboard E2E is infeasible, build the best approximation and state the limitation.
- IPA text is exact, grapheme-cluster-aware Unicode (`ɡ` U+0261, `ː` U+02D0, `ɹ` U+0279) — assert on exact scalars.

## Flake rules

From the issue #119 flake sweep; binding on all new XCUITests. The helper code is readable in `IPAKeyboardUITests` — what's listed here is the non-obvious *why*:

- **Tap-after-scroll needs a settle probe** — inertial `swipeUp` leaves the list decelerating and the next tap is swallowed as a scroll-stop touch. Use `revealTapAndSettle` / `LibraryScreen.openRow` (LibraryScreen.swift); they end after one sentinel-probe re-tap and the *caller's* `.postNavigation` first-wait supplies the full window — don't add a second long wait inside helpers.
- **Tests presenting remote system UI (share sheet) must dismiss in-test AND register a terminate backstop** — a live sheet makes the next `launch()` kill the app mid-presentation. Follow `test_exportBuiltIn_presentsShareSheet`: `dismissShareSheet`, an `addTeardownBlock` that terminates and waits for `.notRunning`, and tearDown screenshots guarded by `app.state != .notRunning`. The iOS 26 sheet is out-of-process with no Close/Cancel button in the app's hierarchy, so dismissal is coordinate-based (tap the dimmed area, then drag the sheet off the bottom edge); probe sheet signatures in both the app and SpringBoard hierarchies plus `app.popovers` (iPad). Don't assert on the underlying screen after dismissal — it never left the hierarchy, so the wait is pure timeout burn.
- **Never poll `app.keyboards` for typing readiness** — it burns the full timeout whenever the simulator's Connect Hardware Keyboard setting suppresses the software keyboard. Use the event-driven `waitForKeyboardFocus` gate (`hasKeyboardFocus == true` predicate, ~5s, one re-tap on miss; duplicated by design in SymbolReferenceScreen.swift and KeyEditorScreen.swift).
- **Orientation**: `IPAKeyboardUITestsLaunchTests.tearDown` restores portrait and terminates (it was the only source of leftover-landscape); the functional suites' portrait one-liners in setUp are belt-and-braces — keep both, and do NOT add per-suite window-geometry gates (redundant, and a full-timeout burn on a legitimately-landscape iPad).
- **Negative-assertion polarity**: something that existed and is going away gets `waitForNonExistence(timeout:)` (eventual state), not `XCTAssertFalse(waitForExistence(2))` (snapshot race). Keep the `XCTAssertFalse` form only for things that must *never* appear, and run that probe first so its window doubles as the settle time the wrong outcome would need.

## Running the suite

Per CLAUDE.md's Commands section, via XcodeBuildMCP: set `scheme` = `IPAKeyboard` with `session_set_defaults` (the build/test tools take no `scheme` arg), then `test_sim` with `extraArgs: ["-only-testing:IPAKeyboardUITests"]`; scope to one test with `-only-testing:IPAKeyboardUITests/<Class>/<method>`. A full app build signs automatically under the configured team — if signing blocks the run, surface it rather than skipping silently. CI-lane specifics (simulator boot gate, sequential execution) are in the `testing-and-ci` skill (`.claude/skills/testing-and-ci/SKILL.md`).
