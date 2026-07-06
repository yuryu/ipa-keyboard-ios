---
name: host-app-ui
description: Screen map, view models, and architecture rules for the IPAKeyboard host app's layout-management UI. Use when touching IPAKeyboard/** — host-app screens, navigation, view models, onboarding, or settings.
---

# Host app UI

The **IPAKeyboard** app target is the host app + layout-management UI; it embeds both the keyboard extension and the framework.

## Screen map

`LayoutListView` (browse built-in + user layouts) → `LayoutDetailView` (metadata, live `KeyboardView` preview, set-active, "Duplicate to Edit" fork, delete) → `LayoutEditorView` (per-layout symbol curation with live preview + typing scratchpad), backed by the `LayoutLibrary` view model over `LayoutStore` + `KeyboardPreferences`.

Key-level editing of user layouts ships as `LayoutKeyEditorView` (sheet from `LayoutDetailView`: add/remove/reorder rows, per-key edits via `KeyRowEditorView`/`KeyEditorForm`, live draft preview; user layouts only — built-ins go through "Duplicate to Edit").

## Architecture rules for host-app UI work

- **Persistence goes through `LayoutStore`.** Read built-ins and user layouts via the store; write user layouts back through it. Never read or write the App Group container or the bundled JSON directly from a view.
- **Preferences go through `KeyboardPreferences`** (active layout ID, per-layout hidden symbols), and any "which layout is active" display must use `ActiveLayoutResolver.resolve(activeID:in:)` — the same resolution the extension uses — so the host UI and the keyboard can never disagree. Symbol curation is non-destructive: preview it with `applyingHiddenSymbols(_:)`, store the hidden set in preferences, never edit the layout document.
- **Copy-on-write forking.** Built-ins are read-only (`isBuiltIn == true`). Editing one means calling `KeyboardLayout.makeEditableCopy(named:)` and saving the copy — never mutate a bundled layout. Surface "this is a default, editing will create your copy" in the UI, and offer reset-to-default.
- **Degrade gracefully before provisioning.** Signing/App Group provisioning is deferred, so the store may fall back to bundled defaults with a nil container. The UI must still load and present built-ins; saving may be unavailable in that state — handle it without crashing and ideally tell the user why.
- Preserve exact Unicode when displaying or editing key text (e.g. `ɡ` U+0261 ≠ ASCII `g`, `ː` U+02D0 ≠ colon). Don't normalize away combining diacritics in text fields.
