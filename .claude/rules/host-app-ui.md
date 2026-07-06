---
paths:
  - "IPAKeyboard/**"
---

# Host app UI map

The **IPAKeyboard** app target is the host app + layout-management UI: `LayoutListView` (browse built-in + user layouts) → `LayoutDetailView` (metadata, live `KeyboardView` preview, set-active, "Duplicate to Edit" fork, delete) → `LayoutEditorView` (per-layout symbol curation with live preview + typing scratchpad), backed by the `LayoutLibrary` view model over `LayoutStore` + `KeyboardPreferences`.

Key-level editing of user layouts ships as `LayoutKeyEditorView` (sheet from `LayoutDetailView`: add/remove/reorder rows, per-key edits via `KeyRowEditorView`/`KeyEditorForm`, live draft preview; user layouts only — built-ins go through "Duplicate to Edit").

The app target embeds both the keyboard extension and the framework.
