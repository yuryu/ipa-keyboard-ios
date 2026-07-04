---
name: swiftui-gesture-limits-alternates-popup
description: Why the alternates popup uses a UIKit recognizer overlay — SwiftUI gesture compositions freeze List scrolling, and other verified gesture/XCUITest gotchas from issue #104
metadata:
  type: project
---

The alternates popup (hold → slide → release-to-commit) is driven by a UIKit
`UILongPressGestureRecognizer` overlay (`AlternatesPressTracker` in
KeyboardView.swift), not SwiftUI gestures. **Why** (all verified empirically
on the iOS 26 SDK simulator, issue #104):

- `.onLongPressGesture` completes at `minimumDuration` and then delivers NO
  callback at the physical finger-up — there is no SwiftUI-modifier way to
  observe the release after a completed long press.
- Composing `LongPressGesture.sequenced(before: DragGesture(...))` to get the
  release **freezes UIScrollView/List scrolling** over the keys — swipes over
  the preview move zero pixels. This holds even via `.simultaneousGesture`
  and even with `minimumDistance: 12` (not just 0). Symptom: host detail
  screens with dense-alternates previews (ipa-full) became unscrollable;
  KeyEditor/ImportExport UI tests failed at "Duplicate to Edit did not
  appear".
- SwiftUI `TapGesture`/`.onTapGesture` fails on movement, **not duration** —
  a stationary hold of any length still fires the tap on release. Two
  consequences: (a) a separate tap alongside a hold-commit path double-types;
  UIKit `tap.require(toFail: longPress)` prevents this by construction;
  (b) XCUITest gotcha below.

**How to apply:** don't "simplify" the tracker back to SwiftUI gestures; any
key interaction needing both press-phase locations and scroll cooperation
belongs in a UIKit recognizer overlay (same pattern as the globe-key
`nextKeyboardOverlay`).

XCUITest gotchas hit while writing the regression tests:

- Synthesized `press(forDuration:)` is perfectly stationary, so the SwiftUI
  tap still succeeded on release and masked the stranded-popup bug (the old
  code passed a naive test). Reproducing hold-related bugs needs movement:
  `press(forDuration:thenDragTo:)`. Real fingers micro-move; synthesized ones
  don't.
- SwiftUI accessibility modifiers applied *after* an `.overlay(...)` stamp
  their identifier/label over every element inside the overlay (popup cells
  used to surface as a second `key-insert-ɹ`). Apply per-element modifiers
  before adding overlays.
- Positive slide-select coverage uses the symbol editor's scratchpad
  (`layout-editor-scratch`) as the only preview surface that records emitted
  actions; the popup cell can't be queried mid-gesture, so the drag endpoint
  must be a coordinate offset (documented exception in
  AlternatesPopupUITests).
