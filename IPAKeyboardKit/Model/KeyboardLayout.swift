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
    /// Current on-disk schema version. Bump when the format changes and add a
    /// migration. Old files are recognized *structurally* on decode (a v1 file
    /// has flat `rows`, a v2 file has `arrangements`); a file claiming a *newer*
    /// version than this is rejected rather than silently downgraded.
    ///
    /// v1: flat `rows`. v2: `arrangements` → `panels` → `rows`.
    public static let currentSchemaVersion = 2

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
    /// One or more arrangements of this dialect's symbols; index 0 is shown
    /// by default until arrangement selection (host app) lands.
    public var arrangements: [Arrangement]

    public init(
        schemaVersion: Int = KeyboardLayout.currentSchemaVersion,
        id: UUID = UUID(),
        name: String,
        locale: String,
        isBuiltIn: Bool = false,
        derivedFrom: UUID? = nil,
        arrangements: [Arrangement]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.locale = locale
        self.isBuiltIn = isBuiltIn
        self.derivedFrom = derivedFrom
        self.arrangements = arrangements
    }

    /// Convenience for building a layout from a single flat grid of rows,
    /// wrapping them in one default arrangement/panel. Used by terse call
    /// sites (extension fallback, previews, tests) and by the v1→v2 migration.
    public init(
        schemaVersion: Int = KeyboardLayout.currentSchemaVersion,
        id: UUID = UUID(),
        name: String,
        locale: String,
        isBuiltIn: Bool = false,
        derivedFrom: UUID? = nil,
        rows: [KeyRow]
    ) {
        self.init(
            schemaVersion: schemaVersion,
            id: id,
            name: name,
            locale: locale,
            isBuiltIn: isBuiltIn,
            derivedFrom: derivedFrom,
            arrangements: KeyboardLayout.singleArrangement(rows: rows))
    }

    /// Wrap a flat grid of rows in one default arrangement/panel. Shared by the
    /// terse `rows:` initializer and the v1→v2 decode migration so both build
    /// the same shape. A migrated v1 layout has no separate `functionRow` — its
    /// function keys stay inline in the rows.
    static func singleArrangement(rows: [KeyRow]) -> [Arrangement] {
        [Arrangement(name: "Default", panels: [Panel(name: "Main", rows: rows)], functionRow: nil)]
    }

    /// The arrangement shown by default; nil only for a malformed layout.
    public var primaryArrangement: Arrangement? { arrangements.first }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, locale, isBuiltIn, derivedFrom, arrangements, rows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Refuse to silently downgrade a file written by a newer build; we have
        // no way to migrate a format we don't know. Older/equal versions are
        // normalized up to the current version once migrated below.
        let onDisk = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? KeyboardLayout.currentSchemaVersion
        guard onDisk <= KeyboardLayout.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container,
                debugDescription: "layout schemaVersion \(onDisk) is newer than supported "
                    + "\(KeyboardLayout.currentSchemaVersion)")
        }
        schemaVersion = KeyboardLayout.currentSchemaVersion

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        locale = try container.decode(String.self, forKey: .locale)
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        derivedFrom = try container.decodeIfPresent(UUID.self, forKey: .derivedFrom)

        // A present-but-empty `arrangements` is treated as absent so it can't
        // produce a silent blank keyboard: fall back to the v1 `rows` migration,
        // and if there are no rows either the document is malformed.
        if let arrangements = try container.decodeIfPresent([Arrangement].self, forKey: .arrangements),
           !arrangements.isEmpty {
            self.arrangements = arrangements
        } else if let rows = try container.decodeIfPresent([KeyRow].self, forKey: .rows) {
            self.arrangements = KeyboardLayout.singleArrangement(rows: rows)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "layout has neither non-empty `arrangements` nor `rows`"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(locale, forKey: .locale)
        try container.encode(isBuiltIn, forKey: .isBuiltIn)
        try container.encodeIfPresent(derivedFrom, forKey: .derivedFrom)
        try container.encode(arrangements, forKey: .arrangements)
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
            arrangements: arrangements
        )
    }

    /// A copy with every key matching `shouldRemove` dropped — across each
    /// panel's rows, the shared `functionRow`, and per-panel `switchKey`s, and
    /// pruned from surviving keys' long-press `alternates`. The single place
    /// that walks the whole arrangements→panels→rows→keys tree, so callers
    /// (e.g. hiding the globe key, applying a user's enabled set) don't
    /// re-implement the traversal.
    public func filteringKeys(_ shouldRemove: (Key) -> Bool) -> KeyboardLayout {
        var copy = self
        copy.arrangements = arrangements.map { arrangement in
            var arrangement = arrangement
            arrangement.panels = arrangement.panels.map { panel in
                var panel = panel
                if let key = panel.switchKey, shouldRemove(key) { panel.switchKey = nil }
                panel.rows = panel.rows.map { row in
                    var row = row
                    row.keys = row.keys.compactMap { KeyboardLayout.pruning($0, shouldRemove) }
                    return row
                }
                return panel
            }
            if var functionRow = arrangement.functionRow {
                functionRow.keys = functionRow.keys.compactMap { KeyboardLayout.pruning($0, shouldRemove) }
                arrangement.functionRow = functionRow
            }
            return arrangement
        }
        return copy
    }

    /// Drop `key` if it matches; otherwise keep it but prune matching keys from
    /// its `alternates` (recursively), so hiding a symbol that appears only as a
    /// long-press alternate actually removes it. A surviving key whose alternates
    /// are all pruned still renders — just without a long-press popup.
    private static func pruning(_ key: Key, _ shouldRemove: (Key) -> Bool) -> Key? {
        guard !shouldRemove(key) else { return nil }
        var key = key
        key.alternates = key.alternates.compactMap { pruning($0, shouldRemove) }
        return key
    }

    /// A copy with every `.insert` key whose text is in `hidden` removed — from
    /// panel rows, the function row, switch keys, and long-press alternates —
    /// and any row left with no interactive key dropped so hiding never reserves
    /// blank rows. Only `.insert` keys are eligible, so required affordances
    /// (space, return, backspace, the globe, spacers, panel switches) can never
    /// be hidden and the keyboard is never blanked. `hidden` is keyed by
    /// inserted string (see `KeyboardPreferences`); an empty set is a no-op.
    public func applyingHiddenSymbols(_ hidden: Set<String>) -> KeyboardLayout {
        guard !hidden.isEmpty else { return self }
        var result = filteringKeys { key in
            if case .insert(let text) = key.action { return hidden.contains(text) }
            return false
        }
        result.arrangements = result.arrangements.map { arrangement in
            var arrangement = arrangement
            arrangement.panels = arrangement.panels.map { panel in
                var panel = panel
                panel.rows = panel.rows.filter { row in row.keys.contains { !$0.isSpacer } }
                return panel
            }
            return arrangement
        }
        return result
    }
}
