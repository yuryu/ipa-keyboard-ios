---
paths:
  - "KeyboardExtension/**"
  - "IPAKeyboardKit/UI/**"
---

# Keyboard extension constraints

For `KeyboardViewController` and anything that runs in the extension (including the shared SwiftUI `KeyboardView` in `IPAKeyboardKit/UI/`):

- Tight memory budget (~48–66 MB); no network by default.
- "Allow Full Access" (`RequestsOpenAccess`) is off by default — assume no full access.
- The globe/Next-Keyboard key is required; respect `needsInputModeSwitchKey`.
- Text edits must be grapheme-cluster-aware so combining diacritics insert/delete as single user-perceived characters.

## KeyboardViewController wiring

`KeyboardExtension/KeyboardViewController.swift` resolves the active layout (`ActiveLayoutResolver.resolve(activeID:in:)` over `KeyboardPreferences.activeLayoutID` + `LayoutStore().allLayouts()`, then applies that layout's hidden-symbols curation), renders the shared SwiftUI `KeyboardView`, and applies each emitted `KeyAction` to the document proxy (grapheme-cluster-aware backspace; globe key gated on `needsInputModeSwitchKey`). The target links `IPAKeyboardKit` as **Do Not Embed**.
