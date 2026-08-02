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

`KeyboardExtension/KeyboardViewController.swift`: `LayoutStore().allLayouts()` → `ActiveLayoutResolver.resolve(activeID:in:)` (using `KeyboardPreferences.activeLayoutID`) → apply that layout's hidden-symbols curation → render the shared SwiftUI `KeyboardView` (hosted via `UIHostingController` inside the `UIInputViewController`) → apply emitted `KeyAction`s to the `textDocumentProxy`. `LayoutStore` degrades gracefully to bundled defaults when the App Group container is nil (any `CODE_SIGNING_ALLOWED=NO` build; CI's app lanes sign ad-hoc and do have a container), so nothing may crash on a nil container. `Arrangement.totalRowCount` sizes the keyboard's constant height; keep sizing correct for portrait, landscape, and iPad.

## Runtime constraints (these cause real crashes/rejections)

- **Memory:** keyboard extensions are killed around ~48–66 MB. Do not load large assets, big images, or heavy frameworks into the extension. Lazy-load layout data; keep the IPA tables compact.
- **No network by default.** Don't add networking to the extension; anything needing the network belongs in the host app.
- **"Allow Full Access"** (`RequestsOpenAccess`) is `false` in `KeyboardExtension/Info.plist`, and onboarding promises the user it isn't needed (`OnboardingView.swift`: "Full Access is not required"). What makes that safe is that every read on the render path is *total*: `LayoutStore` falls back to bundled defaults, `KeyboardPreferences` falls back to `.standard`, and `ActiveLayoutResolver.resolve` always returns a layout. Keep it that way — nothing on the render path may require the shared container to be readable, and flipping `RequestsOpenAccess` is a product decision (file an issue), not an implementation detail. Note `AppGroup.sharedAvailable` gates on the *container probe*: an unprovisioned suite is non-nil but process-local, so `UserDefaults(suiteName:) != nil` proves nothing on its own.
- **The globe/Next-Keyboard key**: don't reinvent it. `needsInputModeSwitchKey` decides whether it appears at all (the controller strips the key from the layout when it's false), and the interaction is a UIKit control laid over the SwiftUI keycap that forwards real `UIEvent`s to `handleInputModeList(from:with:)` — see `KeyboardExtension/NextKeyboardKeyOverlay.swift`, which explains why a SwiftUI gesture cannot substitute (the system needs the real event to tell tap from hold and to anchor the picker). The `advanceToNextInputMode()` call in the action handler is only a safety net for a layout rendered without the overlay; a gesture calling it directly loses the long-press switcher.
- Insert text via `textDocumentProxy` (`insertText`, `deleteBackward`). Handle IPA combining diacritics correctly — inserting a base glyph then a combining mark is a sequence of `insertText` calls; deletion must remove the whole grapheme cluster, not one code point (the kit's `GraphemeText` helpers exist for this — use them, don't reimplement).
- Provide proper accessibility labels on every key (spoken name, e.g. "schwa", not the raw glyph "ə") — never ship keys without labels.
- `APPLICATION_EXTENSION_API_ONLY = YES` is set on the framework because it links into the `.appex` — don't call extension-unavailable APIs from kit code. And never name a public kit type the same as the module (`IPAKeyboardKit`), even in `UI/` — with `BUILD_LIBRARY_FOR_DISTRIBUTION = YES` it shadows the module and breaks `.swiftinterface` verification (detail: the `layout-schema` skill).
