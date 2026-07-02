---
name: host-ui-patterns
description: Established SwiftUI view-model and navigation patterns for the IPAKeyboard host app (library, detail, curation, key editor)
metadata:
  type: project
---

The host app's layout-management UI follows these patterns (library increment
3a; key-level editor added for issue #6).

- **App target has `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** (verified in
  project.pbxproj; the kit/extension targets do NOT). So app-side view inits can
  construct `@MainActor` objects freely; kit code must stay nonisolated-safe.
- **`LayoutLibrary`** (`IPAKeyboard/LayoutLibrary.swift`) is the `@Observable @MainActor`
  view model wrapping `LayoutStore`. `fork`/`delete` set `errorMessage` (root-list
  alert); **`update(_:) throws`** instead — the key-editor sheet presents its own
  error alert because the root alert can't present under a sheet.
- **Navigation**: `LayoutListView` root — `NavigationStack` + value-based
  `.navigationDestination(for: KeyboardLayout.self)` → `LayoutDetailView`.
  `LayoutDetailView` resolves a fresh copy by id (`current`) from the library so
  post-save edits refresh; the navigation value is a stale snapshot.
- **Cancelable editing**: `LayoutKeyEditorView` is a sheet with its own
  NavigationStack; `LayoutDraft` (`@Observable @MainActor`) holds `workingCopy` +
  `original`, `hasChanges` (value equality) drives Save/discard-confirm/
  `interactiveDismissDisabled`. All mutations go through the kit's pure editing
  API (`IPAKeyboardKit/Model/LayoutEditing.swift`: `PanelPath`, insert/append/
  remove/move rows+keys, `replaceKey`, `resettingContent(from:)`) so the engine
  is unit-testable in `IPAKeyboardKitTests`. Offset semantics match SwiftUI
  `onDelete`/`onMove` (IndexSet + pre-removal destination).
- **Live preview** reuses the kit's `KeyboardView(layout:) { _ in }` with a no-op
  onAction, framed at `KeyboardMetrics().totalHeight(for: layout.primaryArrangement)`.
- **Reset-to-default** is a *draft* operation: `LayoutDraft.resetToDefault()`
  re-derives content from `builtInSource` (lookup of `original.derivedFrom` in
  `library.builtInLayouts` — bundled JSON pins stable UUIDs, so this works
  across launches); nothing persists until Save.
- **Unicode exactness in editors**: every editing TextField sets
  `.autocorrectionDisabled(true)` + `.textInputAutocapitalization(.never)`; no
  trimming/normalization anywhere; `KeyEditorForm` shows a code-point readout
  ("U+0261") under the symbol field. Only exactly-empty alternate texts are
  dropped on commit.

**Why:** keeps edit state cancelable and logic unit-testable, per the architecture
in CLAUDE.md.
**How to apply:** extend the same shapes (working-copy VM + kit engine + sheet
with Save/Cancel) for future editors (e.g. arrangement/function-row editing);
don't introduce ObservableObject or NavigationView.
