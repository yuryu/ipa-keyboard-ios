//
//  SymbolReferenceModelTests.swift
//  IPAKeyboardTests
//
//  Display ranking of symbol-reference search results (issue #98).
//  `SymbolReferenceModel.rank(_:matching:)` is a pure, stable, order-only
//  partition over the kit's match set: the scalar-exact symbol leads,
//  glyph-contains matches follow, and spoken-name/code-point matches keep
//  their first-seen inventory order behind them. Which entries match at all
//  stays the kit's business (`SymbolInventory.filter`, tested in
//  IPAKeyboardKitTests) — these tests cover only the ordering the model
//  adds on top, plus the issue's acceptance criterion against the real
//  bundled layouts.
//

import Foundation
import Testing
import IPAKeyboardKit
@testable import IPAKeyboard

@MainActor
struct SymbolReferenceModelTests {

    // MARK: Fixtures

    /// Mirrors the shape of the reported bug: consonants whose spoken names
    /// contain the letter "i" sit before the /i/ vowel in inventory order,
    /// so an unranked filter buries the exact match mid-list.
    private let entries = [
        SymbolEntry(text: "p", spokenName: "voiceless bilabial plosive"),
        SymbolEntry(text: "\u{0261}", spokenName: "voiced velar plosive"),
        SymbolEntry(text: "i\u{02D0}", spokenName: "long close front unrounded vowel"),
        SymbolEntry(text: "i", spokenName: "close front unrounded vowel"),
    ]

    /// The exact flow the view renders: kit match set, model ranking.
    private func filteredAndRanked(
        _ entries: [SymbolEntry], query: String
    ) -> [SymbolEntry] {
        SymbolReferenceModel.rank(
            SymbolInventory.filter(entries, matching: query), matching: query)
    }

    // MARK: Tier order

    @Test func exactSymbolLeadsThenGlyphContainsThenNameMatches() {
        // All four entries match "i" (two by glyph, two only by spoken
        // name). Exact /i/ first, "iː" (glyph contains) second, and the
        // name-only matches keep their relative inventory order behind.
        let ranked = filteredAndRanked(entries, query: "i")
        #expect(ranked.map(\.text) == ["i", "i\u{02D0}", "p", "\u{0261}"])
    }

    @Test func whitespaceAroundTheQueryStillBoostsTheExactSymbol() {
        let ranked = filteredAndRanked(entries, query: "  i  ")
        #expect(ranked.first?.codePointNotation == "U+0069")
    }

    @Test func emptyQueryKeepsInventoryOrder() {
        #expect(SymbolReferenceModel.rank(entries, matching: "") == entries)
        #expect(SymbolReferenceModel.rank(entries, matching: "   ") == entries)
    }

    // MARK: Scalar exactness

    @Test func asciiQueryNeverBoostsTheLookalikeIpaSymbol() {
        // ɡ U+0261 and ASCII g U+0067 are distinct entries; each query
        // boosts only its own scalar, never the look-alike.
        let asciiG = SymbolEntry(text: "g", spokenName: "hard g")
        let scriptG = SymbolEntry(text: "\u{0261}", spokenName: "voiced velar plosive")

        let forAscii = SymbolReferenceModel.rank([scriptG, asciiG], matching: "g")
        #expect(forAscii.map(\.codePointNotation) == ["U+0067", "U+0261"])

        let forScript = SymbolReferenceModel.rank([asciiG, scriptG], matching: "\u{0261}")
        #expect(forScript.map(\.codePointNotation) == ["U+0261", "U+0067"])
    }

    @Test func exactnessIsScalarExactNotCanonicalEquivalence() {
        // The inventory keeps NFC é (U+00E9) and NFD é (U+0065 U+0301)
        // distinct; an NFC query is exact only for the NFC entry. String
        // equality would conflate them (canonical equivalence) — the NFD
        // spelling ranks as a mere glyph-contains match behind it.
        let nfd = SymbolEntry(text: "e\u{0301}", spokenName: "decomposed e acute")
        let nfc = SymbolEntry(text: "\u{00E9}", spokenName: "precomposed e acute")
        let ranked = SymbolReferenceModel.rank([nfd, nfc], matching: "\u{00E9}")
        #expect(ranked.map(\.codePointNotation) == ["U+00E9", "U+0065 U+0301"])
    }

    // MARK: Order-only contract

    @Test func rankIsOrderOnlyAndTreatsTheDisplayLabelAsAGlyphAlias() {
        // rank never adds or drops entries — it only orders whatever list
        // it is given. The explicit display label counts as the symbol's
        // glyph: the combining tilde presents as "◌̃" (U+25CC U+0303) but
        // inserts bare U+0303, so searching by its label outranks entries
        // with no glyph relationship to the query.
        let tilde = SymbolEntry(
            text: "\u{0303}", displayLabel: "\u{25CC}\u{0303}", spokenName: "nasalized")
        let plosive = SymbolEntry(text: "p", spokenName: "voiceless bilabial plosive")
        let ranked = SymbolReferenceModel.rank(
            [plosive, tilde], matching: "\u{25CC}\u{0303}")
        #expect(ranked.map(\.codePointNotation) == ["U+0303", "U+0070"])
    }

    // MARK: Acceptance against the bundled data

    @Test func bundledInventoryPutsTheExactAsciiVowelFirst() {
        // Issue #98's report, against the real bundled layouts: searching
        // "i" must surface /i/ (plain ASCII U+0069) at the top even though
        // nearly every spoken name contains the letter i. A nil container
        // keeps the store on bundled defaults only, hermetically.
        let model = SymbolReferenceModel(store: LayoutStore(containerURL: nil))
        model.query = "i"
        let filtered = model.filtered

        #expect(filtered.first?.codePointNotation == "U+0069")
        // Ranking reorders the kit's match set, never changes membership.
        #expect(Set(filtered.map(\.id))
            == Set(SymbolInventory.filter(model.entries, matching: "i").map(\.id)))
    }
}
