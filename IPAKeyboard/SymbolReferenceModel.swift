//
//  SymbolReferenceModel.swift
//  IPAKeyboard
//
//  View model for the symbol reference (issue #17). Thin @Observable shell
//  over the kit's `SymbolInventory`: the aggregation, code-point formatting,
//  and search matching all live in IPAKeyboardKit where they are unit-tested;
//  this type holds the UI state (query, scratchpad) on the main actor plus
//  the display ranking of matches (issue #98, `rank(_:matching:)` — a pure
//  stable partition, unit-tested in IPAKeyboardTests).
//
//  The inventory is built from the bundled layouts through `LayoutStore` at
//  runtime — never a hand-maintained table that could drift from the JSON.
//  Reading bundled layouts works even before App Group provisioning (the
//  store's graceful-degradation path), so this screen never needs the shared
//  container.
//

import Foundation
import Observation
import IPAKeyboardKit

@Observable
@MainActor
final class SymbolReferenceModel {
    /// Every distinct symbol across the bundled layouts, first-seen order.
    private(set) var entries: [SymbolEntry] = []

    /// The live search text (bound to `.searchable`).
    var query = ""

    /// Symbols the user has collected to copy as one string. Built by exact
    /// concatenation — no normalization — so pasted text carries the precise
    /// code points shown in the reference.
    private(set) var scratchpad = ""

    init(store: LayoutStore = LayoutStore()) {
        entries = SymbolInventory.build(from: store.bundledLayouts())
    }

    /// Entries matching the current query (all of them, in inventory order,
    /// when it's empty), ranked so the best hit leads — see `rank(_:matching:)`.
    var filtered: [SymbolEntry] {
        Self.rank(SymbolInventory.filter(entries, matching: query), matching: query)
    }

    /// Display order for search matches (issue #98). Which entries match is
    /// the kit's business (`SymbolInventory.filter`); this only reorders,
    /// never adds or drops. Three stable tiers:
    ///
    /// 1. The entry whose inserted text IS the query — searching "i" puts
    ///    /i/ on top instead of mid-list (nearly every spoken name contains
    ///    the letter i, so name matches would otherwise bury it). A
    ///    code-point query gets the same boost (issue #116): "U+0069",
    ///    "u+0069", or bare hex "0069" put /i/ first, ahead of the
    ///    multi-scalar entries (like /iː/) that merely contain the scalar.
    /// 2. Entries whose glyph merely contains the query, in text or in the
    ///    explicit display label (the label is how a bare combining mark
    ///    presents, e.g. "◌̃" for U+0303).
    /// 3. Everything else (spoken-name fragments, code-point containment),
    ///    keeping today's first-seen inventory order.
    ///
    /// Exactness is scalar-exact, compared via `SymbolInventory
    /// .codePointNotation(for:)` — and, for code-point queries,
    /// `codePointNotation(fromCodePointQuery:)` — rather than String
    /// equality: Swift's `==` is canonical-equivalence-based and would
    /// conflate the NFC/NFD spellings the inventory deliberately keeps
    /// distinct (and ASCII "g" must never rank as an exact hit for ɡ
    /// U+0261). The inventory dedups entries by code points, so each
    /// exactness test admits at most one entry into tier 1 and the whole
    /// order stays deterministic. Pure, nonisolated, and internal so
    /// IPAKeyboardTests can exercise it with fixture entries.
    nonisolated static func rank(
        _ matches: [SymbolEntry], matching query: String
    ) -> [SymbolEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return matches }
        let exactNotation = SymbolInventory.codePointNotation(for: trimmed)
        let queriedNotation = SymbolInventory.codePointNotation(fromCodePointQuery: trimmed)
        var exact: [SymbolEntry] = []
        var glyphContains: [SymbolEntry] = []
        var byNameOrCodePoint: [SymbolEntry] = []
        for entry in matches {
            if entry.codePointNotation == exactNotation
                || entry.codePointNotation == queriedNotation {
                exact.append(entry)
            } else if entry.text.contains(trimmed) || entry.displayLabel.contains(trimmed) {
                glyphContains.append(entry)
            } else {
                byNameOrCodePoint.append(entry)
            }
        }
        return exact + glyphContains + byNameOrCodePoint
    }

    /// Append a symbol's exact inserted text to the scratchpad.
    func addToScratchpad(_ entry: SymbolEntry) {
        scratchpad += entry.text
    }

    func clearScratchpad() {
        scratchpad = ""
    }
}
