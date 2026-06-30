---
name: accessibility-ids
description: Accessibility identifiers on host-app layout-library screens, for ui-test-author to target
metadata:
  type: project
---

Accessibility identifiers added to the host-app layout library (increment 3a),
for `ui-test-author` to match in `IPAKeyboardUITests`:

- `layout-list` — the root List (`LayoutListView`)
- `layout-list-builtin-section` — "Built-in" section
- `layout-list-user-section` — "My Layouts" section
- `layout-row-<layout.id.uuidString>` — each row. Keyed by the layout's UUID
  (stable) rather than name (user-mutable). Built-in UUIDs come from the bundled
  JSON / decode; user-layout UUIDs are minted by `makeEditableCopy()`.
- `layout-list-container-unavailable` — the built-in section footer shown only
  when saving is unavailable (App Group container nil)
- `layout-detail-preview` — the live `KeyboardView` preview container in `LayoutDetailView`
- `layout-detail-duplicate-button` — "Duplicate to Edit" (built-ins only)
- `layout-detail-delete-button` — "Delete" (user layouts only)

**How to apply:** when adding screens, keep this scheme; document new ids here and
in a header comment in the view file so the UI-test author can find them.
