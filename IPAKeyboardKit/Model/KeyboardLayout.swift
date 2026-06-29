//
//  KeyboardLayout.swift
//  IPAKeyboardKit
//
//  The user-customizable layout document. Layouts are DATA, not code:
//  built-in defaults ship read-only in the framework bundle, and users
//  fork/edit them (copy-on-write) into the App Group container.
//

import Foundation

public struct KeyRow: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var keys: [Key]

    public init(id: UUID = UUID(), keys: [Key]) {
        self.id = id
        self.keys = keys
    }

    private enum CodingKeys: String, CodingKey { case id, keys }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        keys = try container.decode([Key].self, forKey: .keys)
    }
}

public struct KeyboardLayout: Codable, Sendable, Hashable, Identifiable {
    /// Current on-disk schema version. Bump when the format changes and add
    /// a migration; older files are recognized via the decoded `schemaVersion`.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    /// User-facing name.
    public var name: String
    /// BCP-47 language-dialect this layout targets, e.g. "en-US".
    public var locale: String
    /// True for bundled defaults (read-only). User copies set this false.
    public var isBuiltIn: Bool
    /// When this layout was forked from a built-in, the source's id.
    public var derivedFrom: UUID?
    public var rows: [KeyRow]

    public init(
        schemaVersion: Int = KeyboardLayout.currentSchemaVersion,
        id: UUID = UUID(),
        name: String,
        locale: String,
        isBuiltIn: Bool = false,
        derivedFrom: UUID? = nil,
        rows: [KeyRow]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.locale = locale
        self.isBuiltIn = isBuiltIn
        self.derivedFrom = derivedFrom
        self.rows = rows
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, locale, isBuiltIn, derivedFrom, rows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? KeyboardLayout.currentSchemaVersion
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        locale = try container.decode(String.self, forKey: .locale)
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        derivedFrom = try container.decodeIfPresent(UUID.self, forKey: .derivedFrom)
        rows = try container.decode([KeyRow].self, forKey: .rows)
    }

    /// Produce an editable, user-owned copy of a built-in layout
    /// (copy-on-write editing). Never mutate the bundled file in place.
    public func makeEditableCopy(named newName: String? = nil) -> KeyboardLayout {
        KeyboardLayout(
            schemaVersion: schemaVersion,
            id: UUID(),
            name: newName ?? "\(name) (Custom)",
            locale: locale,
            isBuiltIn: false,
            derivedFrom: id,
            rows: rows
        )
    }
}
