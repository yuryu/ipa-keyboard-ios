//
//  ScratchInput.swift
//  IPAKeyboard
//
//  Shared reducer applying a preview `KeyAction` to an in-host scratch
//  buffer, so every host scratchpad (the layout editor's, issue #57; the
//  layout list's, issues #103/#115) interprets preview key presses exactly
//  the same way. Mirrors what the extension does to the document proxy:
//  backspace removes one grapheme cluster (`String.removeLast()` is
//  cluster-aware), so combining diacritics delete as a single
//  user-perceived character.
//

import IPAKeyboardKit

/// Namespace for the scratch-buffer reducer (no instances).
enum ScratchInput {
    /// Apply a preview key press to `scratch`. Panel switches are handled
    /// inside `KeyboardView`; the globe and spacers have no meaning in a
    /// host preview, so they are ignored.
    static func apply(_ action: KeyAction, to scratch: inout String) {
        switch action {
        case .insert(let text): scratch += text
        case .space: scratch += " "
        case .return: scratch += "\n"
        case .backspace: if !scratch.isEmpty { scratch.removeLast() }
        case .nextKeyboard, .switchPanel, .spacer: break
        @unknown default: break
        }
    }
}
