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

**Simulator constraint:** Use `name=iPhone 17` (OS 26.5). No iPhone 16 simulator present. Prefer a specific named simulator (e.g. `iPhone 17 Pro Max`) over a bare `iPhone 17` if another agent may already have that one booted — `xcodebuild test` with the default parallel-testing setting will otherwise spin up multiple clones and burn ~3–4 minutes just getting one to boot successfully.

**Why:** Tests cover the layout-library UI (LayoutListView + LayoutDetailView). The old ContentView smoke tests were retired when the stock template was replaced.

**How to apply:** Use `LibraryScreen` and `LayoutDetailScreen` from `LibraryScreen.swift` before querying elements directly. Add new screen objects as new `.swift` files in `IPAKeyboardUITests/` — `PBXFileSystemSynchronizedRootGroup` auto-includes them without project-file edits. See [[feedback_swift6_xcuitest]] for async setUp/tearDown pattern.

## KNOWN REGRESSION (found 2026-07-01, still present on `main`): row/section identifiers broken

`LayoutListView`'s `layout-row-<UUID>` cell identifiers (and every other per-element identifier inside `builtInSection`/`userSection`/`activeSection`) are **not reachable** on iOS 26.5 / this Xcode toolchain: applying `.accessibilityIdentifier(...)` to a SwiftUI `Section` inside a `List` makes *every descendant element in that section* (including `ForEach` rows and their subviews) report the **section's** identifier instead of its own. Confirmed via the runtime accessibility-hierarchy dump (`xcrun xcresulttool export attachments`, "App UI hierarchy" attachment) on a real failing run: the English (US) row's `Button` had `identifier: 'layout-list-builtin-section'` (the *Section's* id), not `layout-row-7E5A1C00-...`; likewise every static text inside the "Active" section reported `identifier: 'layout-list-active-section'`.

- Confirmed via `git diff main -- IPAKeyboard/LayoutListView.swift` that the affected lines (`.accessibilityIdentifier("layout-list-builtin-section")` on the `Section`, `.accessibilityIdentifier("layout-row-\(layout.id.uuidString)")` on each row) are **unmodified on `main`** — this is not caused by any in-flight branch, it's a live regression on `main` today.
- Breaks `LibraryScreen.englishUSRow` and any row-level lookup by UUID identifier. All three pre-onboarding-branch tests that depend on it (`test_library_showsBuiltInLayout`, `test_library_openDetail_showsPreview`, `test_library_detail_backNavigatesToList`) fail with "No matches found for ... layout-row-<UUID> ... from input {(Cell, Cell, ...)}" — the cells exist, just under the wrong identifier.
- Does NOT affect screens without a `Section`-level `.accessibilityIdentifier` (confirmed: all 4 onboarding-flow tests over `OnboardingView`, a plain `ScrollView`, pass cleanly).
- **Do not "fix" this by loosening test assertions to a label-based fallback** — that would silently mask a real app-code accessibility defect. File/flag it as a `host-app` + `testing` issue instead; the eventual app-side fix likely means moving the identifier off the `Section` itself (e.g. onto the header `Text`) or restructuring so the section container isn't tagged with an identifier at all.
- CI still only does `build-for-testing` for `IPAKeyboardUITests` (never executes it), which is why this had gone unnoticed.
- Workaround established 2026-07-01 (issue #6 work, `LibraryScreen.row(labelContains:)`/`row(labelContainsAll:)`): the row's `label` (not `identifier`) is unaffected — SwiftUI still merges each `NavigationLink`/`Button` row into one accessibility element whose `label` concatenates its visible text, e.g. `"IPA — Full (QWERTY), und, Built-in, read-only"` or, forked, `"IPA — Full (QWERTY) (Custom), und"`. `app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name))` reliably finds and taps a specific row. Caveat: the *active* layout's name renders **twice** (once as plain `Text` in the "Active" section, once as the tappable row) — pick a layout that's never the default active one (`ActiveLayoutResolver` prefers bundled `en-US`) to keep the substring match unambiguous, e.g. `"IPA — Full (QWERTY)"` (`ipa-full.json`, locale `und`).

## SECOND identifier-bleed bug (found 2026-07-01, distinct from the Section one above): `.accessibilityIdentifier` on a `KeyboardView` container also bleeds

`layout-detail-preview` (`LayoutDetailView`) and `key-editor-preview` (`LayoutKeyEditorView`) apply `.accessibilityIdentifier(...)` directly to the `KeyboardView(...)` call — not to a `Section`, so the Section-bleed explanation above doesn't apply — yet the SAME symptom occurs: confirmed via the runtime accessibility snapshot, there is no single container element carrying that identifier. Instead **every individual rendered key** becomes its own `StaticText` with that exact `identifier` and `label` equal to the key's spoken name (`key.accessibilityLabel ?? key.displayLabel`), e.g. `StaticText, identifier: 'layout-detail-preview', label: 'voiceless uvular plosive'`. Consequences:
- `app.otherElements["layout-detail-preview"]` (the pre-2026-07-01 `LayoutDetailScreen.preview` implementation) never matches anything — confirmed this **also** silently broke the pre-existing `test_library_openDetail_showsPreview`'s `detail.preview.exists` assertion (independent of the row-tap regression above, which fails first and masks it).
- Fixed in `LibraryScreen.swift`: `preview` now queries `app.descendants(matching: .any).matching(identifier: "layout-detail-preview").firstMatch` (any match proves the preview rendered), and a new `previewElements(withLabel:) -> XCUIElementQuery` finds one specific key by its exact spoken name/label — this is the reliable way to assert "this specific key's content is visible in the live preview" anywhere in this app, since `KeyButton` in `KeyboardView.swift` has no per-key accessibilityIdentifier at all (flag as a missing-identifier gap: individual keys are only reachable by their accessibility label, which prefers `accessibilityLabel` over `displayLabel`/inserted text — editing a key's *inserted text* alone, when it already has a spoken name set, is therefore NOT independently verifiable in the live preview; edit the spoken-name field instead if the test needs to confirm the change rendered).
- Same bleed pattern very likely affects any other `.accessibilityIdentifier` applied directly to a `KeyboardView(...)` call — check first before trusting a fresh one.

## Lists needing scroll-to-reveal (found 2026-07-01, issue #6 work)

`LayoutDetailView`'s `List` (metadata + live `KeyboardView` preview + "Use this Layout" + "Customize symbols", all *ahead* of the action section) and `LayoutListView`'s `List` ("Active" + "Built-in" sections ahead of "My Layouts") can both be taller than one screen — confirmed via the runtime accessibility snapshot (a "2 pages" vertical scroll bar at 0%, with the not-yet-visible section's `Cell`s genuinely absent from the lazily-composed `UICollectionView`, not just off-screen). A bare `waitForExistence` on `layout-detail-duplicate-button`/`layout-detail-edit-keys-button`/a "My Layouts" row can time out even though the element renders fine once scrolled into range — this is NOT flakiness, it reproduces every time for layouts with enough preview rows (e.g. `ipa-full.json`, which has more rows than `en-US.json`). Fixed via a shared top-level helper `waitForRevealed(_:scrollingIn:timeout:maxSwipes:)` in `LibraryScreen.swift` (swipes the given `List`/`UICollectionView` up between existence checks, bounded iterations) — `LayoutDetailScreen.waitForContent`/`waitForUserLayoutContent`, `LibraryScreen.waitForRow(labelContains:)`/`waitForRow(labelContainsAll:)`, and `LayoutKeyEditorScreen.waitForRow(at:)`/`KeyRowEditorScreen.waitForKey(at:)` all use it. Reuse this helper for any new list-based screen rather than a bare `waitForExistence`.

## App Group container is UNAVAILABLE in every currently-buildable configuration (confirmed 2026-07-01, not assumed)

`LayoutStore.save`/`delete` (`IPAKeyboardKit/Store/LayoutStore.swift`) throw `StoreError.sharedContainerUnavailable` whenever `AppGroup.containerURL` is nil, which requires the App Group *entitlement* to actually be embedded in the running process — i.e. a code-signed build. Every UI-test build in this project currently uses `CODE_SIGNING_ALLOWED=NO` (CLAUDE.md: "Signing is deferred" — Apple developer account mid-relocation), so the entitlement is **never** embedded and `AppGroup.containerURL` is **always** nil in any run reachable by this agent. Confirmed empirically (not inferred): tapping "Duplicate to Edit" reliably shows `LayoutListView`'s "Something went wrong" / "Couldn't save your copy. Saving layouts needs the keyboard's shared storage, which isn't set up yet." alert (`app.alerts["Something went wrong"]`), never a persisted row. Practical fallout:
- **Any UI-test flow that requires an actual *user* layout to exist (fork a built-in, then act on the fork) cannot be driven end-to-end today.** `KeyEditorUITests.swift`'s two flow tests (`test_editorFlow_editedKeyPersistsToDetailPreview`, `test_editorFlow_cancelWithChangesDiscardsDraft`) detect this via `duplicateBuiltInLayout(from:library:)` and `throw XCTSkip(...)` with an explicit message rather than failing — they will self-activate once provisioning lands. **Do not delete/weaken these skips or the underlying flow code** — it's the correct, forward-looking coverage; only the skip guard is temporary.
- Container-independent coverage that *does* run and pass today: `test_builtInDetail_doesNotOfferEditKeys` (gating), `test_duplicateBuiltIn_succeedsOrDegradesGracefully` (exercises `LayoutLibrary.fork`'s error-handling path, asserting the app degrades gracefully either way — passes regardless of container availability, so it's real, always-green coverage, not just a placeholder).
- No launch-argument exists to reset/seed `LayoutStore`'s user-layout storage (checked: zero `ProcessInfo`/`launchArguments` usage anywhere in the app as of 2026-07-01). If the App Group ever *does* become available in a test run, forked layouts persist across `app.launch()` calls within the same session — `KeyEditorUITests`'s `cleanUpForkedSourceLayout()` self-heals via the library row's swipe-to-delete (no confirmation dialog on that path, unlike the detail screen's Delete, so it's idiom-agnostic).
