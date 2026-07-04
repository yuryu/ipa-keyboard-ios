# UI Test Author Memory Index

- [Swift 6 XCUITest @MainActor pattern](feedback_swift6_xcuitest.md) — use async setUp/tearDown with @MainActor; do NOT use setUpWithError/tearDownWithError in Swift 6
- [UITest baseline (2026-06-29, updated 2026-07-01)](project_uitest_baseline.md) — screen objects, identifiers, simulator constraint; 2 identifier-bleed bugs (Section + KeyboardView container), list scroll-to-reveal, App Group always unavailable when unsigned
- [Onboarding flow (issue #7)](project_onboarding_flow.md) — OnboardingScreen page object, launch-arg overrides, OnboardingUITests coverage
- [Key editor flow (issue #6)](project_key_editor_flow.md) — KeyEditorScreen page objects, KeyEditorUITests, XCTSkip guard for App-Group-unavailable persistence tests
- [Reset-layouts launch hook (issue #27)](project_reset_layouts_hook.md) — --uitest-reset-layouts arg, LayoutStore.deleteAllUserLayouts/KeyboardPreferences.resetAll, retired swipe-to-delete self-healing
- [Flake hardening (issue #119, 2026-07-04)](project_flake_hardening.md) — settle-tap helpers, share-sheet lifecycle/terminate backstop, keyboard-focus gate, launch-tests tearDown, PR #118 coexistence
