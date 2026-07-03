---
name: accessibility-ids
description: Accessibility identifiers and UI-test launch arguments on host-app screens (library, detail, curation, key editor, onboarding), for ui-test-author to target
metadata:
  type: project
---

Accessibility identifiers in the host app, for `ui-test-author` to match in
`IPAKeyboardUITests`. Each view file also lists its own ids in its header comment.

Layout library (`LayoutListView`):
- `layout-list` — the root List
- `layout-list-builtin-section` / `layout-list-user-section`
- `layout-row-<layout.id.uuidString>` — each row. Keyed by the layout's UUID
  (stable) rather than name (user-mutable). Built-in UUIDs are pinned in the
  bundled JSON; user-layout UUIDs are minted by `makeEditableCopy()`.
- `layout-list-container-unavailable` — footer shown only when saving is
  unavailable (App Group container nil)
- `layout-list-help-button` — toolbar button that reopens the onboarding sheet
  anytime (issue #7)
- `layout-list-import-button` — toolbar button opening `.fileImporter` (issue #8)
- After PR #31 (issue #9): section identifiers live on the header `Text`s, not
  the `Section` (Section-level ids bleed onto every descendant on iOS 26), and
  rows surface as `Button`s inside cells — query `app.buttons`, not `app.cells`.

Detail (`LayoutDetailView`):
- `layout-detail-preview` — live `KeyboardView` preview container (bleeds onto
  every key on iOS 26 — see ui-test-author's project_uitest_baseline.md; fix
  tracked in issue #25)
- `layout-detail-use-button` / `layout-detail-active-label`
- `layout-detail-customize-link` — symbol curation (all layouts)
- `layout-detail-duplicate-button` — "Duplicate to Edit" (built-ins only)
- `layout-detail-edit-keys-button` — "Edit Keys" sheet (user layouts only)
- `layout-detail-export-button` — "Export Layout" ShareLink (all layouts, issue #8);
  sits in its own section just above the action section, so
  `LayoutDetailScreen.waitForContent` (scrolls to the duplicate button) loads it
- `layout-detail-delete-button` — "Delete" (user layouts only)

Symbol curation (`LayoutEditorView`):
- `layout-editor-preview`, `layout-editor-scratch`, `layout-editor-clear`,
  `layout-editor-toggle-<symbol>`

Key editor sheet (`LayoutKeyEditorView`, issue #6):
- `key-editor` (root List), `key-editor-cancel`, `key-editor-save`,
  `key-editor-preview`, `key-editor-panel-picker` (only when >1 panel),
  `key-editor-row-<index>` (0-based), `key-editor-add-row`,
  `key-editor-reset`, `key-editor-reset-confirm`, `key-editor-discard-confirm`

Row editor (`KeyRowEditorView`, pushed inside the sheet):
- `row-editor` (List), `row-editor-key-<index>` (0-based), `row-editor-add-key`

Key form (`KeyEditorForm`, sheet-on-sheet):
- `key-form-text`, `key-form-unicode` (code-point readout, e.g. "U+0261"),
  `key-form-label`, `key-form-accessibility-label`, `key-form-width-stepper`,
  `key-form-alternate-text-<i>` / `key-form-alternate-a11y-<i>` (0-based),
  `key-form-add-alternate`, `key-form-done` (labelled "Add" for new keys),
  `key-form-cancel`

Symbol reference (issue #17, `SymbolReferenceView.swift`):
- `layout-list-symbol-reference-button` — LayoutListView toolbar entry point
- `symbol-reference-list` (root List), `symbol-reference-row-<text>` (keyed by
  the exact inserted string, e.g. `…-row-ɡ` with U+0261),
  `symbol-reference-copy-<text>` (issue #69: inline per-row copy button, same
  key as the row; `.borderless` so it doesn't trigger the NavigationLink;
  spoken label "Copy <name>", flips to sticky "Copied" — moves to another row
  only when that row is copied),
  `symbol-reference-empty`, `symbol-reference-done`,
  `symbol-reference-scratch` / `…-scratch-copy` / `…-scratch-clear`
- Detail: `symbol-detail-glyph`, `symbol-detail-spoken-name`,
  `symbol-detail-codepoint-<n>` (0-based, label is exactly "U+XXXX"),
  `symbol-detail-copy` (label flips to "Copied" and stays — sticky by design
  so tests are race-free), `symbol-detail-add-scratch`
- The search field takes no custom identifier (SwiftUI `.searchable`); match
  `app.searchFields.firstMatch`. Placement is
  `.navigationBarDrawer(displayMode: .always)` so no reveal swipe is needed.
- Page object: `SymbolReferenceScreen.swift` (self-contained — no shared
  helpers, so rewrites of other page objects can't break it).
- Gotcha: the detail screen's back button is labelled "Symbol Reference" —
  the same label as the library's toolbar entry, which stays in the
  accessibility hierarchy under the sheet. Any nav-bar query for that label
  must exclude `layout-list-symbol-reference-button` or it is ambiguous.

Onboarding (issue #7, `OnboardingView.swift` + `OnboardingState.swift`):
- `onboarding-view` — the sheet's root ScrollView (`app.scrollViews[...]`)
- `onboarding-full-access-note` — the "Full Access is not required" callout
- `onboarding-open-settings-button` — the Settings deep-link button
- `onboarding-settings-open-failed` — inline fallback shown only after a
  failed Settings open
- `onboarding-done-button` — Done button dismissing the sheet

Onboarding launch-argument overrides (checked in `OnboardingState.init`):
- `--uitest-show-onboarding` — always auto-present the sheet on launch
- `--uitest-skip-onboarding` — never auto-present (skip wins if both passed)

Import hook (issue #8, checked in `LayoutLibrary.init`, run one-shot from
`LayoutListView.onAppear` via `performLaunchImportIfRequested()`):
- launch *environment* `UITEST_IMPORT_JSON` = a layout JSON document — fed
  through the real import pipeline (kit validation → store save → root error
  alert). Exists because XCUITest can't drive the system document picker.
  Error alert title "Something went wrong"; import messages start with
  "Couldn’t import this layout." (curly apostrophe).
The sheet auto-presents on FIRST launch of a fresh install, so pre-existing
UI tests that interact with the list must pass `--uitest-skip-onboarding`.
Seen-flag lives in standard (host-local) UserDefaults key
`hasSeenKeyboardOnboarding`, not the App Group.

**How to apply:** when adding screens, keep this scheme; document new ids here and
in a header comment in the view file so the UI-test author can find them.
