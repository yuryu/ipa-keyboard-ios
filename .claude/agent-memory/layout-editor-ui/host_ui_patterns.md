---
name: host-ui-patterns
description: Established SwiftUI view-model and navigation patterns for the IPAKeyboard host app (layout library increment 3a)
metadata:
  type: project
---

The host app's layout-management UI (replacing the stock `ContentView`) follows
these patterns, established in increment 3a (layout library: browse/preview/fork/delete).

- **`LayoutLibrary`** (`IPAKeyboard/LayoutLibrary.swift`) is the `@Observable @MainActor`
  view model wrapping `LayoutStore`. Holds `builtInLayouts` / `userLayouts` (both
  `private(set)`), `containerAvailable: Bool`, `errorMessage: String?`. Uses
  `import Observation` + the `@Observable` macro (not ObservableObject).
- **Navigation**: `LayoutListView` is the root — `NavigationStack` + `List` with a
  `.navigationDestination(for: KeyboardLayout.self)` pushing `LayoutDetailView`.
  `KeyboardLayout` is `Hashable`/`Identifiable`, so value-based nav works directly.
  Library held with `@State private var library = LayoutLibrary()` at the root and
  passed down by reference to detail views.
- **Live preview** reuses the kit's `KeyboardView(layout:) { _ in }` with a no-op
  onAction, framed at `KeyboardMetrics().totalHeight(for: layout.primaryArrangement)`.
- Per-key editing is NOT yet built (deferred past increment 3a).

**Why:** keeps edit state cancelable and logic unit-testable, per the architecture
in CLAUDE.md.
**How to apply:** when extending to the key editor, add a working-copy view model
that commits through `LayoutStore` on save; follow the same `@Observable` + value-nav
shape rather than introducing ObservableObject or NavigationView.
