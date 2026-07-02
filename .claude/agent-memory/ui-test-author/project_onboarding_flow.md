---
name: project_onboarding_flow
description: Onboarding-flow (issue #7) UI test coverage — launch args, identifiers, screen object
metadata:
  type: project
---

Added 2026-07-01 in worktree `wf_a1cff817-afa-3` (issue #7, "Onboarding: guide users to enable the keyboard"). Host-app implementation (`IPAKeyboard/OnboardingState.swift`, `IPAKeyboard/OnboardingView.swift`) was already in place from `layout-editor-ui`; this covers the UI-test side.

**Files:**
- `IPAKeyboardUITests/OnboardingScreen.swift` — page object for the "Enable the Keyboard" sheet. Sentinel: `app.navigationBars["Enable the Keyboard"]`. Root scroll view via `app.scrollViews["onboarding-view"]`. The "Full Access not required" callout and the "Settings open failed" note are `.accessibilityElement(children: .combine)` containers with an ambiguous resulting `XCUIElementType` — looked up via a type-erasing `app.descendants(matching: .any).matching(identifier:)` helper rather than a typed query. Also carries `waitForDismissal(timeout:)` (NSPredicate `exists == false` + `XCTWaiter`) since XCUIElement has no built-in negative wait.
- `IPAKeyboardUITests/OnboardingUITests.swift` — 4 tests: force-show auto-presents + Done dismisses back to the library; help button reopens after force-skip; Full-Access-not-required callout text + Settings button existence (never tap it — backgrounds the app); force-skip shows the list immediately with no sheet. All 4 passed on `iPhone 17 Pro Max` (OS 26.5).
- `LibraryScreen.swift` gained `helpButton` (`app.buttons["layout-list-help-button"]`).

**Launch-argument overrides** (mirrors `OnboardingState.forceShowArgument`/`forceSkipArgument`, redeclared as `OnboardingScreen.forceShowArgument`/`forceSkipArgument` string constants since the UI-test target can't import the app module's types): `--uitest-show-onboarding` always auto-presents; `--uitest-skip-onboarding` never auto-presents (skip wins if both passed).

**Retrofit of pre-existing tests:** on a fresh/first-run simulator the onboarding sheet auto-presents and can occlude the library, so `IPAKeyboardUITests.setUp()` now appends `OnboardingScreen.forceSkipArgument` to `app.launchArguments` for the whole suite (covers `test_launch_mainWindowExists`, the three library tests, and `testLaunchPerformance`'s local `XCUIApplication()`), and `IPAKeyboardUITestsLaunchTests.testLaunch()` does the same for its own local `app`. This makes the whole suite hermetic/order-independent regardless of a prior run's first-run UserDefaults state, per CLAUDE.md's hermetic-test rule.

**How to apply:** Future onboarding-adjacent tests should use `OnboardingScreen`'s constants rather than hardcoding the launch-arg strings again. See [[project_uitest_baseline]] for the unrelated regression discovered while retrofitting the three pre-existing library tests (they still fail even with the skip flag, for a different reason).
