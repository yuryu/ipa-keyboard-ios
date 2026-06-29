//
//  Key.swift
//  IPAKeyboardKit
//
//  A single key in a layout. In JSON, every field except `action` is
//  optional so default layouts stay terse; `id` is generated on decode
//  when omitted.
//

import Foundation

public struct Key: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// What tapping the key does.
    public var action: KeyAction
    /// The glyph shown on the key. When nil, derived from the action
    /// (the inserted text for `.insert`).
    public var label: String?
    /// Spoken VoiceOver name, e.g. "schwa" rather than the raw glyph "ə".
    public var accessibilityLabel: String?
    /// Keys offered on long-press (e.g. a vowel and its diacritic variants).
    public var alternates: [Key]
    /// Relative width; 1.0 is a standard key. Space bars use a larger value.
    public var widthFactor: Double

    public init(
        id: UUID = UUID(),
        action: KeyAction,
        label: String? = nil,
        accessibilityLabel: String? = nil,
        alternates: [Key] = [],
        widthFactor: Double = 1.0
    ) {
        self.id = id
        self.action = action
        self.label = label
        self.accessibilityLabel = accessibilityLabel
        self.alternates = alternates
        self.widthFactor = widthFactor
    }

    /// Convenience for the common case of a character key.
    public static func insert(
        _ text: String,
        accessibilityLabel: String? = nil,
        alternates: [Key] = []
    ) -> Key {
        Key(action: .insert(text), accessibilityLabel: accessibilityLabel, alternates: alternates)
    }

    /// A non-interactive flexible gap (see `KeyAction.spacer`).
    public static var spacer: Key { Key(action: .spacer) }

    /// Whether this key is a flexible gap rather than an interactive key.
    public var isSpacer: Bool { action == .spacer }

    /// The glyph to render, falling back to the inserted text.
    public var displayLabel: String {
        if let label { return label }
        if case .insert(let text) = action { return text }
        return ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, action, label, accessibilityLabel, alternates, widthFactor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        action = try container.decode(KeyAction.self, forKey: .action)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        accessibilityLabel = try container.decodeIfPresent(String.self, forKey: .accessibilityLabel)
        alternates = try container.decodeIfPresent([Key].self, forKey: .alternates) ?? []
        widthFactor = try container.decodeIfPresent(Double.self, forKey: .widthFactor) ?? 1.0
    }
}
