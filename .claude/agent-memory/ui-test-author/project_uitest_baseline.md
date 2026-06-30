---
name: project_uitest_baseline
description: Established UITest baseline — what exists today, screen objects, identifiers, and simulator constraint
metadata:
  type: project
---

Baseline UITests updated 2026-06-29. build-for-testing passes on iPhone 17 (OS 26.5).

**Files:**
- `IPAKeyboardUITests/IPAKeyboardUITests.swift` — main functional tests (`@MainActor`, async setUp/tearDown)
- `IPAKeyboardUITests/LibraryScreen.swift` — page objects `LibraryScreen` and `LayoutDetailScreen`; `@MainActor struct`
- `IPAKeyboardUITests/ContentScreen.swift` — RETIRED (contains only a header comment; old ContentView types removed)
- `IPAKeyboardUITests/IPAKeyboardUITestsLaunchTests.swift` — launch screenshot + assertion, `runsForEachTargetApplicationUIConfiguration = true`

**Accessibility identifiers in host app (verified in source):**
- `layout-list` — the `List` in `LayoutListView` (UICollectionView on iOS 16+, query as `app.collectionViews["layout-list"]`)
- `layout-list-builtin-section`, `layout-list-user-section` — section headers
- `layout-row-<UUID>` — each row cell; English (US) stable ID: `layout-row-7E5A1C00-0000-4000-8000-00656E2D5553` (uppercase)
- `layout-list-container-unavailable` — footer notice when App Group container is absent; treat as best-effort
- `layout-detail-preview` — live `KeyboardView` container; query as `app.otherElements["layout-detail-preview"]`
- `layout-detail-duplicate-button` — "Duplicate to Edit" button (built-ins only); query as `app.buttons[...]`
- `layout-detail-delete-button` — "Delete" button (user layouts only)

**Test inventory:**
- `test_launch_mainWindowExists` — main window appears within 10 s
- `test_library_showsBuiltInLayout` — English (US) row exists and is hittable; name label cross-check
- `test_library_openDetail_showsPreview` — tapping built-in row shows preview + duplicate button
- `test_library_detail_backNavigatesToList` — back button returns to library list
- `testLaunchPerformance` — cold-launch metric
- `testLaunch` (LaunchTests) — window + navigation bar present; screenshot kept always

**Important constraints:**
- Do NOT assert that forking/saving persisted a user layout — the App Group container is unavailable without provisioning
- Back button in detail screen is `app.navigationBars.buttons["Layouts"]` (parent title label)
- `LibraryScreen.waitForContent` anchors on `app.navigationBars["Layouts"]`
- `LayoutDetailScreen.waitForContent` anchors on `app.buttons["layout-detail-duplicate-button"]`

**Simulator constraint:** Use `name=iPhone 17` (OS 26.5). No iPhone 16 simulator present.

**Why:** Tests cover the layout-library UI (LayoutListView + LayoutDetailView). The old ContentView smoke tests were retired when the stock template was replaced.

**How to apply:** Use `LibraryScreen` and `LayoutDetailScreen` from `LibraryScreen.swift` before querying elements directly. Add new screen objects as new `.swift` files in `IPAKeyboardUITests/` — `PBXFileSystemSynchronizedRootGroup` auto-includes them without project-file edits. See [[feedback_swift6_xcuitest]] for async setUp/tearDown pattern.
