---
name: keyboard-extension
description: Runtime constraints, App Group data sharing, and KeyboardViewController wiring for the KeyboardExtension appex and the shared SwiftUI KeyboardView. Use when touching KeyboardExtension/** or IPAKeyboardKit/UI/**, or when reasoning about extension memory, full access, or the render path.
---

# Keyboard extension: constraints and wiring

Applies to `KeyboardViewController` and anything that runs in the extension (including the shared SwiftUI `KeyboardView` in `IPAKeyboardKit/UI/`).

## Target architecture

A custom keyboard is TWO app targets plus a shared framework, all present and wired: the **host container app** (`IPAKeyboard` target — where users browse, add, and modify layouts) and the **keyboard extension** (`KeyboardExtension` target, `.appex`, principal class `KeyboardViewController: UIInputViewController` — what actually types into other apps). The extension links `IPAKeyboardKit` as **Do Not Embed**.

The two share data through the App Group `group.net.yuryu.IPAKeyboard` — the identifier must match `AppGroup.identifier` in code and both `.entitlements` files. User layouts live as files in the App Group container (extension reads, host app writes); bundled defaults ship read-only in the framework's resources. All shared logic lives in `IPAKeyboardKit` — never duplicate layout loading, resolution, or rendering between targets.

## Render path (host preview mirrors it, so they can never disagree)

`KeyboardExtension/KeyboardViewController.swift`: `LayoutStore().allLayouts()` → `ActiveLayoutResolver.resolve(activeID:in:)` (using `KeyboardPreferences.activeLayoutID`) → apply that layout's hidden-symbols curation → render the shared SwiftUI `KeyboardView` (hosted via `UIHostingController` inside the `UIInputViewController`) → apply emitted `KeyAction`s to the `textDocumentProxy`. `LayoutStore` degrades gracefully to bundled defaults when the App Group container is nil (provisioning is deferred), so nothing may crash on a nil container. `Arrangement.totalRowCount` sizes the keyboard's constant height; keep sizing correct for portrait, landscape, and iPad.

## Runtime constraints (these cause real crashes/rejections)

- **Memory:** keyboard extensions are killed around ~48–66 MB. Do not load large assets, big images, or heavy frameworks into the extension. Lazy-load layout data; keep the IPA tables compact.
- **No network by default.** Don't add networking to the extension; anything needing the network belongs in the host app.
- **"Allow Full Access"** (`RequestsOpenAccess`) is OFF by default. Without it the extension cannot read the App Group's *shared UserDefaults* reliably and loses some capabilities. Design so the core typing experience works WITHOUT full access; gate only true extras behind it. Prefer the App Group **file container** over shared UserDefaults for layout data so it works without full access.
- **The globe/Next-Keyboard key is required:** respect `needsInputModeSwitchKey` / `advanceToNextInputMode()` so users can switch keyboards; long-press should offer the keyboard switcher.
- Insert text via `textDocumentProxy` (`insertText`, `deleteBackward`). Handle IPA combining diacritics correctly — inserting a base glyph then a combining mark is a sequence of `insertText` calls; deletion must remove the whole grapheme cluster, not one code point (the kit's `GraphemeText` helpers exist for this — use them, don't reimplement).
- Provide proper accessibility labels on every key (spoken name, e.g. "schwa", not the raw glyph "ə") — never ship keys without labels.
- `APPLICATION_EXTENSION_API_ONLY = YES` is set on the framework because it links into the `.appex` — don't call extension-unavailable APIs from kit code.
