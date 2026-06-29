//
//  KeyAction.swift
//  IPAKeyboardKit
//
//  What a key does when tapped. Encodes to a clean, hand-editable
//  discriminated-union JSON form, e.g.
//      { "type": "insert", "text": "ə" }
//      { "type": "backspace" }
//

import Foundation

public enum KeyAction: Sendable, Hashable {
    /// Insert a string into the document (one grapheme, a digraph like "tʃ",
    /// or a base glyph followed by a combining diacritic).
    case insert(String)
    /// Delete one user-perceived character (grapheme cluster) before the cursor.
    case backspace
    /// Insert a single space.
    case space
    /// Insert a newline / submit, per the field's return-key type.
    case `return`
    /// Advance to the next keyboard (the required globe key).
    case nextKeyboard
    /// Switch the visible panel within the current arrangement, by panel name
    /// (e.g. "More"). Handled by the renderer; never reaches the host document.
    case switchPanel(String)
    /// A non-interactive flexible gap in a row. Absorbs leftover width so the
    /// keys after it are pushed to the right (e.g. consonants grouped left,
    /// vowels right). Renders nothing and emits no action.
    case spacer
}

extension KeyAction: Codable {
    private enum CodingKeys: String, CodingKey { case type, text, target }

    private enum Kind: String, Codable {
        case insert, backspace, space, `return`, nextKeyboard, switchPanel, spacer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .insert:
            self = .insert(try container.decode(String.self, forKey: .text))
        case .backspace: self = .backspace
        case .space: self = .space
        case .return: self = .return
        case .nextKeyboard: self = .nextKeyboard
        case .switchPanel:
            self = .switchPanel(try container.decode(String.self, forKey: .target))
        case .spacer: self = .spacer
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .insert(let text):
            try container.encode(Kind.insert, forKey: .type)
            try container.encode(text, forKey: .text)
        case .backspace: try container.encode(Kind.backspace, forKey: .type)
        case .space: try container.encode(Kind.space, forKey: .type)
        case .return: try container.encode(Kind.return, forKey: .type)
        case .nextKeyboard: try container.encode(Kind.nextKeyboard, forKey: .type)
        case .switchPanel(let target):
            try container.encode(Kind.switchPanel, forKey: .type)
            try container.encode(target, forKey: .target)
        case .spacer: try container.encode(Kind.spacer, forKey: .type)
        }
    }
}
