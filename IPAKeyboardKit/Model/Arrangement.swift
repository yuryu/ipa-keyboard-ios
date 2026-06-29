//
//  Arrangement.swift
//  IPAKeyboardKit
//
//  An arrangement is one way of laying out a dialect's shared symbol
//  inventory (e.g. a phonetically-organized "split" arrangement or a
//  QWERTY-style one). Each arrangement holds one or more panels; the first
//  panel is primary, and additional panels (the "more" symbols panel) are
//  reached via a `KeyAction.switchPanel` key, the way the system keyboard
//  switches between its `123` / `#+=` panels.
//
//  Like `KeyRow`, `id` is generated on decode when omitted so hand-authored
//  default JSON stays terse.
//

import Foundation

public struct Panel: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// Display name and the target a `switchPanel` key refers to, e.g. "More".
    public var name: String
    /// The panel-specific key shown at the start of the arrangement's shared
    /// bottom bar — the affordance that *leaves* this panel (its
    /// `switchPanel(target)` names the panel to show). nil for panels with no
    /// way out (e.g. a single-panel arrangement).
    public var switchKey: Key?
    public var rows: [KeyRow]

    public init(id: UUID = UUID(), name: String, switchKey: Key? = nil, rows: [KeyRow]) {
        self.id = id
        self.name = name
        self.switchKey = switchKey
        self.rows = rows
    }

    private enum CodingKeys: String, CodingKey { case id, name, switchKey, rows }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        switchKey = try container.decodeIfPresent(Key.self, forKey: .switchKey)
        rows = try container.decode([KeyRow].self, forKey: .rows)
    }
}

public struct Arrangement: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// User-facing name of the arrangement, e.g. "Split".
    public var name: String
    /// Panels in display order; index 0 is the primary panel.
    public var panels: [Panel]
    /// The persistent bottom bar shared by every panel (globe / space / ⌫). It
    /// stays pinned while the symbol rows above it swap between panels, the way
    /// the system keyboard keeps its bottom row across `123` / `#+=`. nil for a
    /// v1-migrated layout, which keeps its function keys inline in the rows.
    public var functionRow: KeyRow?

    public init(id: UUID = UUID(), name: String, panels: [Panel], functionRow: KeyRow? = nil) {
        self.id = id
        self.name = name
        self.panels = panels
        self.functionRow = functionRow
    }

    /// The panel shown first; nil only for a malformed (empty) arrangement.
    public var primaryPanel: Panel? { panels.first }

    /// The largest symbol-row count across this arrangement's panels (excludes
    /// the shared `functionRow`).
    public var maxRowCount: Int { panels.map(\.rows.count).max() ?? 0 }

    /// Total rendered row count: the tallest panel's symbol rows plus the shared
    /// bottom bar, if any. The renderer sizes the keyboard to this so switching
    /// panels doesn't resize it.
    public var totalRowCount: Int { maxRowCount + (functionRow == nil ? 0 : 1) }

    /// The panel with the given name, falling back to the primary panel.
    public func panel(named name: String?) -> Panel? {
        guard let name else { return primaryPanel }
        return panels.first { $0.name == name } ?? primaryPanel
    }

    private enum CodingKeys: String, CodingKey { case id, name, panels, functionRow }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        panels = try container.decode([Panel].self, forKey: .panels)
        functionRow = try container.decodeIfPresent(KeyRow.self, forKey: .functionRow)
    }
}
