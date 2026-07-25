# UI Test Author Memory Index

- [Swift 6 XCUITest @MainActor pattern](feedback_swift6_xcuitest.md) — use async setUp/tearDown with @MainActor; do NOT use setUpWithError/tearDownWithError in Swift 6
- [UITest baseline (2026-06-29, updated 2026-07-01)](project_uitest_baseline.md) — screen objects, identifiers, simulator constraint; 2 identifier-bleed bugs (Section + KeyboardView container), list scroll-to-reveal, App Group always unavailable when unsigned
- [Onboarding flow (issue #7)](project_onboarding_flow.md) — OnboardingScreen page object, launch-arg overrides, OnboardingUITests coverage
- [Key editor flow (issue #6)](project_key_editor_flow.md) — KeyEditorScreen page objects, KeyEditorUITests, XCTSkip guard for App-Group-unavailable persistence tests
- [Known pre-failing UI tests (2026-07-12)](project_known_prefailing_uitests.md) — importValid + editor discard-confirm fail on signed fresh sim, pre-existing (stash-verified)
- [Reset-layouts launch hook (issue #27)](project_reset_layouts_hook.md) — --uitest-reset-layouts arg, LayoutStore.deleteAllUserLayouts/KeyboardPreferences.resetAll, retired swipe-to-delete self-healing
- [Press interactions (issues #120/#183)](project_press_interactions.md) — key-preview-balloon identifier, gesture-on-main + pre-resolved activity-free AX-snapshot observer for transient UI (queries AND per-poll snapshotWithError crash the runner), cap-release commit test

Flake-hardening rules from issue #119 (settle-tap, share-sheet lifecycle, keyboard-focus gate, launch-tests tearDown, negative-assertion polarity) were promoted to CLAUDE.md ("UI-test flake rules") — follow them in every new test.
