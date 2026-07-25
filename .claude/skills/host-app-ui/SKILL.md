---
name: host-app-ui
description: Screen map, view models, and architecture rules for the IPAKeyboard host app — layout library, detail/editor screens, symbol reference, onboarding, import/export. Use when touching IPAKeyboard/** (host-app screens, navigation, or view models).
---

# Host app UI

## Screen map

`LayoutListView` (browse built-in + user layouts) → `LayoutDetailView` (metadata, live `KeyboardView` preview, set-active, "Duplicate to Edit" fork, export, delete) → `LayoutEditorView` (per-layout symbol curation with live preview + typing scratchpad), backed by the `LayoutLibrary` view model over `LayoutStore` + `KeyboardPreferences`.

Also on the list screen: `OnboardingView` (enable-the-keyboard guidance), `SymbolReferenceView` (searchable IPA reference), and layout **import** via `.fileImporter`. Export is a `ShareLink` on the detail screen, carrying `LayoutExportItem` over the kit's `LayoutTransfer`.

Key-level editing of user layouts ships as `LayoutKeyEditorView` (sheet from `LayoutDetailView`: add/remove/reorder rows, per-key edits via `KeyRowEditorView`/`KeyEditorForm`, live draft preview; user layouts only — built-ins go through "Duplicate to Edit").

The `IPAKeyboard/*.swift` file list is the authoritative surface — check it before assuming a screen doesn't exist yet.

## Architecture rules for host-app UI work

- **Persistence goes through `LayoutStore`.** Read built-ins and user layouts via the store; write user layouts back through it. Never read or write the App Group container or the bundled JSON directly from a view.
- **Preferences go through `KeyboardPreferences`** (active layout ID, per-layout hidden symbols), and any "which layout is active" display must use `ActiveLayoutResolver.resolve(activeID:in:)` — the same resolution the extension uses — so the host UI and the keyboard can never disagree. Symbol curation is non-destructive — preview with `applyingHiddenSymbols(_:)` and store the hidden set in preferences (curation semantics: the `layout-schema` skill).
- **Copy-on-write forking.** Built-ins are read-only: editing one means `KeyboardLayout.makeEditableCopy(named:)` and saving the copy (forking semantics: the `layout-schema` skill). Surface "this is a default, editing will create your copy" in the UI, and offer reset-to-default.
- **Degrade gracefully without the App Group.** The store may fall back to bundled defaults with a nil container (e.g. unsigned CI builds). The UI must still load and present built-ins; saving may be unavailable in that state — handle it without crashing and ideally tell the user why.
- Preserve exact Unicode when displaying or editing key text (e.g. `ɡ` U+0261 ≠ ASCII `g`, `ː` U+02D0 ≠ colon). Don't normalize away combining diacritics in text fields.
