# ``IPAKeyboardKit``

The shared model, storage, and rendering for IPAKeyboard — the customizable
IPA keyboard. Layouts are data (versioned `Codable` JSON), not code.

## Overview

`IPAKeyboardKit` is linked by both the host app and the keyboard extension. It
holds the layout schema, the ``LayoutStore`` that loads bundled defaults and
persists user layouts through the App Group, and the SwiftUI ``KeyboardView``
that renders a layout for both the extension and the host app's previews.

A ``KeyboardLayout`` is a document of one or more ``Arrangement``s; each
arrangement has ``Panel``s (swapped by a ``KeyAction/switchPanel(_:)`` key)
plus a shared function row (the pinned bottom bar). Built-in layouts are
read-only; users fork them copy-on-write with
``KeyboardLayout/makeEditableCopy(named:)`` and never mutate a bundled file in
place.

## Topics

### Layout schema

- ``KeyboardLayout``
- ``Arrangement``
- ``Panel``
- ``KeyRow``
- ``Key``
- ``KeyAction``

### Storage

- ``LayoutStore``
- ``AppGroup``

### Rendering

- ``KeyboardView``
- ``KeyboardMetrics``

### Text input

- ``GraphemeText``
