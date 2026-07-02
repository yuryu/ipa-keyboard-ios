//
//  SymbolInventory.swift
//  IPAKeyboardKit
//
//  A searchable inventory of every symbol a set of layouts can insert
//  (issue #17: the host app's symbol reference). The inventory is DERIVED
//  from the layout documents at runtime — never a hand-maintained table
//  that can drift from the bundled JSON.
//
//  Identity is scalar-exact: entries are keyed by their exact Unicode code
//  point sequence, so look-alikes are never conflated (ɡ U+0261 ≠ ASCII g
//  U+0067) and even canonically-equivalent NFC/NFD spellings stay distinct —
//  a reference tool must report what the data actually contains.
//

import Foundation

/// Where a symbol appears: one layout/panel combination. A symbol reachable
/// only via long-press is flagged so the reference can say so.
public struct SymbolOccurrence: Sendable, Hashable {
    public let layoutName: String
    public let panelName: String
    /// True when the symbol appears (in this layout/panel) only as a
    /// long-press alternate of another key.
    public let isAlternate: Bool

    public init(layoutName: String, panelName: String, isAlternate: Bool) {
        self.layoutName = layoutName
        self.panelName = panelName
        self.isAlternate = isAlternate
    }
}

/// One Unicode scalar of a symbol's inserted text, with its formal name when
/// the system knows it (e.g. U+0261 "LATIN SMALL LETTER SCRIPT G").
public struct SymbolCodePoint: Sendable, Hashable, Identifiable {
    /// Position of the scalar within the symbol's text (0-based), so repeated
    /// scalars stay identifiable in SwiftUI lists.
    public let ordinal: Int
    /// "U+XXXX" notation, uppercase hex, minimum four digits.
    public let notation: String
    /// The scalar's Unicode character name, when available.
    public let unicodeName: String?

    public var id: Int { ordinal }

    public init(ordinal: Int, notation: String, unicodeName: String?) {
        self.ordinal = ordinal
        self.notation = notation
        self.unicodeName = unicodeName
    }
}

/// One distinct insertable symbol aggregated across layouts: its exact text,
/// how it presents (glyph + spoken name), and everywhere it appears.
public struct SymbolEntry: Sendable, Hashable, Identifiable {
    /// The exact string a key inserts. Never normalized or trimmed.
    public let text: String
    /// The glyph to show: the first explicit key `label` seen (e.g. "◌̃" for
    /// a bare combining diacritic), falling back to `text`.
    public let displayLabel: String
    /// The first spoken (VoiceOver) name seen across occurrences, e.g.
    /// "voiced velar plosive" for ɡ — nil when no layout names it.
    public let spokenName: String?
    /// Scalar-exact identity, e.g. "U+0070 U+02B0" for "pʰ". Stored (not
    /// computed) so it participates in Hashable — two entries whose texts are
    /// canonically equivalent but scalar-different never compare equal.
    public let codePointNotation: String
    /// Every layout/panel the symbol appears in, in first-seen order,
    /// de-duplicated.
    public let occurrences: [SymbolOccurrence]

    public var id: String { codePointNotation }

    /// Per-scalar breakdown (notation + Unicode name) for detail display.
    public var codePoints: [SymbolCodePoint] { SymbolInventory.codePoints(for: text) }

    public init(
        text: String,
        displayLabel: String? = nil,
        spokenName: String? = nil,
        occurrences: [SymbolOccurrence] = []
    ) {
        self.text = text
        self.displayLabel = displayLabel ?? text
        self.spokenName = spokenName
        self.codePointNotation = SymbolInventory.codePointNotation(for: text)
        self.occurrences = occurrences
    }

    /// Whether this entry matches a user search. An empty/whitespace query
    /// matches everything. A non-empty query matches when:
    /// - the exact glyph is contained in `text` (a pasted "ɡ" finds U+0261
    ///   and digraphs containing it, but ASCII "g" never finds ɡ), or
    /// - it appears in the explicit display label (e.g. "◌̃"), or
    /// - it is a case-insensitive fragment of the spoken name ("nasal"
    ///   finds "velar nasal"), or
    /// - it names a code point ("U+0261", "u+0261", or bare hex "0261")
    ///   that occurs in `text`.
    public func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if text.contains(trimmed) { return true }
        if displayLabel.contains(trimmed) { return true }
        if let spokenName, spokenName.range(of: trimmed, options: .caseInsensitive) != nil {
            return true
        }
        if let value = SymbolInventory.scalarValue(fromCodePointQuery: trimmed),
           text.unicodeScalars.contains(where: { $0.value == value }) {
            return true
        }
        return false
    }
}

/// Builds and filters the symbol inventory. Pure functions over layout
/// values — no storage access, so it stays trivially unit-testable and the
/// caller decides which layouts (bundled, user, or both) to index.
public enum SymbolInventory {

    /// Aggregate every `.insert` key across `layouts` into distinct entries,
    /// in first-seen order. Walks each arrangement's panels (rows and
    /// `switchKey`), the shared function row, and long-press `alternates`
    /// recursively. Non-insert keys (space, return, backspace, globe, panel
    /// switches, spacers) are never symbols. Later occurrences of a known
    /// symbol back-fill a missing display label or spoken name and extend
    /// `occurrences` (de-duplicated).
    public static func build(from layouts: [KeyboardLayout]) -> [SymbolEntry] {
        struct Builder {
            var text: String
            var explicitLabel: String?
            var spokenName: String?
            var occurrences: [SymbolOccurrence] = []
            var seen: Set<SymbolOccurrence> = []
        }

        var order: [String] = []
        var builders: [String: Builder] = [:]

        func collect(_ key: Key, layoutName: String, panelName: String, isAlternate: Bool) {
            if case .insert(let text) = key.action, !text.isEmpty {
                let identity = codePointNotation(for: text)
                if builders[identity] == nil {
                    builders[identity] = Builder(text: text)
                    order.append(identity)
                }
                if builders[identity]!.explicitLabel == nil {
                    builders[identity]!.explicitLabel = key.label
                }
                if builders[identity]!.spokenName == nil {
                    builders[identity]!.spokenName = key.accessibilityLabel
                }
                let occurrence = SymbolOccurrence(
                    layoutName: layoutName, panelName: panelName, isAlternate: isAlternate)
                if builders[identity]!.seen.insert(occurrence).inserted {
                    builders[identity]!.occurrences.append(occurrence)
                }
            }
            for alternate in key.alternates {
                collect(alternate, layoutName: layoutName, panelName: panelName, isAlternate: true)
            }
        }

        for layout in layouts {
            for arrangement in layout.arrangements {
                for panel in arrangement.panels {
                    if let switchKey = panel.switchKey {
                        collect(switchKey, layoutName: layout.name, panelName: panel.name, isAlternate: false)
                    }
                    for row in panel.rows {
                        for key in row.keys {
                            collect(key, layoutName: layout.name, panelName: panel.name, isAlternate: false)
                        }
                    }
                }
                if let functionRow = arrangement.functionRow {
                    for key in functionRow.keys {
                        collect(key, layoutName: layout.name, panelName: "Bottom bar", isAlternate: false)
                    }
                }
            }
        }

        return order.compactMap { identity in
            guard let builder = builders[identity] else { return nil }
            return SymbolEntry(
                text: builder.text,
                displayLabel: builder.explicitLabel,
                spokenName: builder.spokenName,
                occurrences: builder.occurrences)
        }
    }

    /// Entries matching `query`, preserving order (see `SymbolEntry.matches`).
    public static func filter(_ entries: [SymbolEntry], matching query: String) -> [SymbolEntry] {
        entries.filter { $0.matches(query) }
    }

    /// Exact per-scalar "U+XXXX" notation for `text`, space-separated:
    /// "ɡ" → "U+0261", "pʰ" → "U+0070 U+02B0". Never normalizes.
    public static func codePointNotation(for text: String) -> String {
        text.unicodeScalars
            .map { String(format: "U+%04X", $0.value) }
            .joined(separator: " ")
    }

    /// Per-scalar breakdown of `text` with Unicode character names.
    public static func codePoints(for text: String) -> [SymbolCodePoint] {
        text.unicodeScalars.enumerated().map { ordinal, scalar in
            SymbolCodePoint(
                ordinal: ordinal,
                notation: String(format: "U+%04X", scalar.value),
                unicodeName: scalar.properties.name)
        }
    }

    /// Parse a code-point search query: "U+0261", "u+0261", or bare hex with
    /// 2–6 digits ("0261"). Returns nil when the query isn't one, so plain
    /// text searches are unaffected (code-point matching only ever adds
    /// matches — it never suppresses a name or glyph match).
    static func scalarValue(fromCodePointQuery query: String) -> UInt32? {
        var hex = Substring(query)
        if hex.count > 2, hex.hasPrefix("U+") || hex.hasPrefix("u+") {
            hex = hex.dropFirst(2)
        }
        guard (2...6).contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(hex, radix: 16)
    }
}
