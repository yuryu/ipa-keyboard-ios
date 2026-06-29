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
}

extension KeyAction: Codable {
    private enum CodingKeys: String, CodingKey { case type, text }

    private enum Kind: String, Codable {
        case insert, backspace, space, `return`, nextKeyboard
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
        }
    }
}
