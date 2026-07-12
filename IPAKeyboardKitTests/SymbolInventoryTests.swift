//
//  SymbolInventoryTests.swift
//  IPAKeyboardKitTests
//
//  SymbolInventory (issue #17) derives the host app's searchable symbol
//  reference from layout documents at runtime. These tests pin down the
//  aggregation (dedup by exact scalars, alternates flagged, non-insert keys
//  excluded, name back-fill), the exact "U+XXXX" formatting, and the search
//  matching (name fragment, exact glyph — never a look-alike — and
//  code-point queries), plus an end-to-end pass over the real bundled data.
//
//  Unicode exactness matters throughout: ɡ is U+0261 (never ASCII g U+0067),
//  ː is U+02D0 (never a colon), and NFC/NFD spellings stay distinct entries.
//

import Foundation
import Testing
@testable import IPAKeyboardKit

struct SymbolInventoryTests {

    // MARK: Fixtures

    /// Two panels + a function row. "p" carries an aspirated long-press
    /// alternate; the "More" panel holds a length mark and a bare combining
    /// tilde with an explicit dotted-circle label.
    private func alpha() -> KeyboardLayout {
        KeyboardLayout(
            name: "Alpha", locale: "en-US",
            arrangements: [
                Arrangement(
                    name: "Split",
                    panels: [
                        Panel(
                            name: "IPA",
                            switchKey: Key(action: .switchPanel("More")),
                            rows: [
                                KeyRow(keys: [
                                    Key(action: .insert("\u{0261}"), accessibilityLabel: "voiced velar plosive"),
                                    Key(
                                        action: .insert("p"),
                                        accessibilityLabel: "voiceless bilabial plosive",
                                        alternates: [
                                            Key(action: .insert("p\u{02B0}"), accessibilityLabel: "aspirated p")
                                        ]),
                                    Key(action: .insert("\u{014B}"), accessibilityLabel: "velar nasal"),
                                    .spacer,
                                ])
                            ]),
                        Panel(
                            name: "More",
                            switchKey: Key(action: .switchPanel("IPA")),
                            rows: [
                                KeyRow(keys: [
                                    Key(action: .insert("\u{02D0}"), accessibilityLabel: "long"),
                                    Key(
                                        action: .insert("\u{0303}"), label: "◌̃",
                                        accessibilityLabel: "nasalized"),
                                ])
                            ]),
                    ],
                    functionRow: KeyRow(keys: [
                        Key(action: .nextKeyboard),
                        Key(action: .space, widthFactor: 3),
                        Key(action: .backspace),
                    ]))
            ])
    }

    /// A flat-`rows` layout (single "Main" panel via the convenience init):
    /// repeats ɡ without a spoken name, and adds an ASCII g and a schwa.
    private func beta() -> KeyboardLayout {
        KeyboardLayout(
            name: "Beta", locale: "und",
            rows: [
                KeyRow(keys: [
                    Key(action: .insert("\u{0261}")),
                    Key(action: .insert("g"), accessibilityLabel: "ascii g"),
                    Key(action: .insert("\u{0259}"), accessibilityLabel: "schwa"),
                ])
            ])
    }

    private func entry(_ text: String, in entries: [SymbolEntry]) -> SymbolEntry? {
        entries.first { $0.codePointNotation == SymbolInventory.codePointNotation(for: text) }
    }

    // MARK: Aggregation

    @Test func buildDeduplicatesAcrossLayoutsByExactScalars() {
        let entries = SymbolInventory.build(from: [alpha(), beta()])
        // Alpha: ɡ, p, pʰ (alternate), ŋ, ː, combining tilde. Beta adds g, ə.
        #expect(entries.count == 8)

        let g = entry("\u{0261}", in: entries)
        #expect(g != nil)
        #expect(g?.occurrences == [
            SymbolOccurrence(layoutName: "Alpha", panelName: "IPA", isAlternate: false),
            SymbolOccurrence(layoutName: "Beta", panelName: "Main", isAlternate: false),
        ])
    }

    @Test func scriptGAndAsciiGAreDistinctEntries() {
        let entries = SymbolInventory.build(from: [alpha(), beta()])
        let scriptG = entry("\u{0261}", in: entries)
        let asciiG = entry("g", in: entries)
        #expect(scriptG != nil)
        #expect(asciiG != nil)
        #expect(scriptG?.codePointNotation == "U+0261")
        #expect(asciiG?.codePointNotation == "U+0067")
        #expect(scriptG?.id != asciiG?.id)
    }

    @Test func alternatesAreCollectedAndFlagged() {
        let entries = SymbolInventory.build(from: [alpha()])
        let aspirated = entry("p\u{02B0}", in: entries)
        #expect(aspirated?.occurrences == [
            SymbolOccurrence(layoutName: "Alpha", panelName: "IPA", isAlternate: true)
        ])
        let plain = entry("p", in: entries)
        #expect(plain?.occurrences.allSatisfy { !$0.isAlternate } == true)
    }

    @Test func primaryAndAlternateInOnePanelCollapseToOnePrimaryOccurrence() {
        // "x" is both a primary key and another key's long-press alternate in
        // the same panel (as in the bundled ipa-full QWERTY panel). The entry
        // must carry a single occurrence, not flagged alternate-only —
        // regardless of whether the primary or the alternate is seen first.
        func layout(primaryFirst: Bool) -> KeyboardLayout {
            let primary = Key(action: .insert("x"))
            let carrier = Key(action: .insert("\u{03C7}"), alternates: [Key(action: .insert("x"))])
            return KeyboardLayout(
                name: "Gamma", locale: "und",
                rows: [KeyRow(keys: primaryFirst ? [primary, carrier] : [carrier, primary])])
        }
        for primaryFirst in [true, false] {
            let entries = SymbolInventory.build(from: [layout(primaryFirst: primaryFirst)])
            let x = entry("x", in: entries)
            #expect(x?.occurrences == [
                SymbolOccurrence(layoutName: "Gamma", panelName: "Main", isAlternate: false)
            ])
        }
    }

    @Test func nonInsertKeysAreExcluded() {
        // Globe/space/backspace (function row), the panel switch keys, and the
        // spacer contribute no entries: only .insert keys are symbols.
        let entries = SymbolInventory.build(from: [alpha()])
        #expect(entries.count == 6)
        #expect(entries.allSatisfy { !$0.text.isEmpty })
        #expect(entry(" ", in: entries) == nil)
    }

    @Test func spokenNameBackfillsFromALaterLayout() {
        // Beta (ɡ with no spoken name) is indexed first; Alpha's name for the
        // same scalars fills the gap without disturbing first-seen order.
        let entries = SymbolInventory.build(from: [beta(), alpha()])
        let g = entry("\u{0261}", in: entries)
        #expect(g?.spokenName == "voiced velar plosive")
        #expect(entries.first?.codePointNotation == "U+0261")
    }

    @Test func explicitLabelWinsOverRawTextForDisplay() {
        let entries = SymbolInventory.build(from: [alpha()])
        let tilde = entry("\u{0303}", in: entries)
        #expect(tilde?.displayLabel == "◌̃")
        #expect(tilde?.text == "\u{0303}") // the raw combining mark is preserved
        // A key without an explicit label falls back to its inserted text.
        #expect(entry("\u{02D0}", in: entries)?.displayLabel == "\u{02D0}")
    }

    @Test func nfcAndNfdSpellingsStayDistinctEntries() {
        // é precomposed (U+00E9) vs decomposed (U+0065 U+0301): Swift String
        // equality would conflate them, but the inventory is scalar-exact.
        let layout = KeyboardLayout(
            name: "Gamma", locale: "und",
            rows: [KeyRow(keys: [
                Key(action: .insert("\u{00E9}")),
                Key(action: .insert("e\u{0301}")),
            ])])
        let entries = SymbolInventory.build(from: [layout])
        #expect(entries.count == 2)
        #expect(entries.map(\.codePointNotation) == ["U+00E9", "U+0065 U+0301"])
    }

    // MARK: Code-point formatting

    @Test func codePointNotationIsExactPerScalar() {
        #expect(SymbolInventory.codePointNotation(for: "\u{0261}") == "U+0261")
        #expect(SymbolInventory.codePointNotation(for: "p\u{02B0}") == "U+0070 U+02B0")
        #expect(SymbolInventory.codePointNotation(for: "\u{02D0}") == "U+02D0")
        #expect(SymbolInventory.codePointNotation(for: "e\u{0301}") == "U+0065 U+0301")
    }

    @Test func codePointsCarryOrdinalsAndUnicodeNames() {
        let points = SymbolInventory.codePoints(for: "p\u{02B0}")
        #expect(points.count == 2)
        #expect(points[0].ordinal == 0)
        #expect(points[0].notation == "U+0070")
        #expect(points[1].ordinal == 1)
        #expect(points[1].notation == "U+02B0")
        #expect(SymbolInventory.codePoints(for: "\u{0261}").first?.unicodeName
            == "LATIN SMALL LETTER SCRIPT G")
    }

    @Test func codePointNotationFromQueryParsesTheSameShapesMatchingAccepts() {
        // "U+XXXX", "u+xxxx", and bare hex (2–6 digits) all normalize to the
        // uppercase four-digit-minimum notation entries carry, so the host
        // app's ranking can boost the exact symbol for code-point queries
        // (issue #116).
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "U+0069") == "U+0069")
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "u+0261") == "U+0261")
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "0261") == "U+0261")
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "69") == "U+0069")
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "U+1D15E") == "U+1D15E")
    }

    @Test func codePointNotationFromQueryRejectsNonCodePointQueries() {
        // Plain text, name fragments, and out-of-shape hex are nil so text
        // searches are never mistaken for code-point ones.
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "i") == nil)
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "nasal") == nil)
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "\u{0261}") == nil)
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "U+") == nil)
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "0") == nil)
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "1234567") == nil)
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "U+00GG") == nil)
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "") == nil)
    }

    @Test func codePointNotationFromQueryRejectsInvalidScalarValues() {
        // Well-shaped hex that denotes no valid Unicode scalar — surrogates
        // and values past U+10FFFF — is nil too: such values can never occur
        // in any entry's text, so treating them as code-point queries would
        // break the "nil means not a code-point query" contract.
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "U+D800") == nil)
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "DFFF") == nil)
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "U+110000") == nil)
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "FFFFFF") == nil)
        // The scalar-range boundaries stay accepted.
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "U+D7FF") == "U+D7FF")
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "U+E000") == "U+E000")
        #expect(SymbolInventory.codePointNotation(fromCodePointQuery: "U+10FFFF") == "U+10FFFF")
    }

    // MARK: Search matching

    // A missing entry below is a lookup regression to *report*, so these use
    // try #require — a force-unwrap would crash the in-process runner and
    // lose every other test's results (#188).

    @Test func matchesNameFragmentCaseInsensitively() throws {
        let entries = SymbolInventory.build(from: [alpha(), beta()])
        let velarNasal = try #require(entry("\u{014B}", in: entries))
        #expect(velarNasal.matches("nasal"))
        #expect(velarNasal.matches("NASAL"))
        #expect(velarNasal.matches("  nasal  ")) // whitespace is trimmed
        let schwa = try #require(entry("\u{0259}", in: entries))
        #expect(!schwa.matches("nasal"))
    }

    @Test func matchesExactGlyphNeverALookalike() throws {
        let entries = SymbolInventory.build(from: [alpha(), beta()])
        let scriptG = try #require(entry("\u{0261}", in: entries))
        let asciiG = try #require(entry("g", in: entries))
        #expect(scriptG.matches("\u{0261}"))
        #expect(!scriptG.matches("g")) // ASCII g must never find ɡ
        #expect(!asciiG.matches("\u{0261}")) // and ɡ must never find ASCII g
        // A pasted digraph finds its exact entry.
        let aspirated = try #require(entry("p\u{02B0}", in: entries))
        #expect(aspirated.matches("p\u{02B0}"))
    }

    @Test func matchesCodePointQueries() throws {
        let entries = SymbolInventory.build(from: [alpha(), beta()])
        let scriptG = try #require(entry("\u{0261}", in: entries))
        #expect(scriptG.matches("U+0261"))
        #expect(scriptG.matches("u+0261"))
        #expect(scriptG.matches("0261"))
        #expect(!scriptG.matches("0067")) // ASCII g's code point
        let asciiG = try #require(entry("g", in: entries))
        #expect(asciiG.matches("0067"))
    }

    @Test func emptyAndWhitespaceQueriesMatchEverything() {
        let entries = SymbolInventory.build(from: [alpha(), beta()])
        #expect(SymbolInventory.filter(entries, matching: "") == entries)
        #expect(SymbolInventory.filter(entries, matching: "   ") == entries)
    }

    @Test func filterPreservesOrderAndDropsNonMatches() {
        let entries = SymbolInventory.build(from: [alpha(), beta()])
        let nasals = SymbolInventory.filter(entries, matching: "nasal")
        // ŋ ("velar nasal") and the combining tilde ("nasalized"), in
        // first-seen order.
        #expect(nasals.map(\.codePointNotation) == ["U+014B", "U+0303"])
    }

    // MARK: Real bundled data (no hand-maintained table to drift)

    @Test func bundledLayoutsProduceASearchableInventory() {
        let entries = SymbolInventory.build(from: LayoutStore().bundledLayouts())
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { !$0.occurrences.isEmpty })

        // ɡ is U+0261 in every bundled layout, named "voiced velar plosive".
        let scriptG = entry("\u{0261}", in: entries)
        #expect(scriptG != nil)
        #expect(scriptG?.codePointNotation == "U+0261")
        #expect(scriptG?.spokenName == "voiced velar plosive")
        #expect(entry("g", in: entries) == nil) // no bundled layout inserts ASCII g

        // The acceptance-criteria search: a name fragment finds the nasals.
        let nasals = SymbolInventory.filter(entries, matching: "nasal")
        #expect(nasals.contains { $0.codePointNotation == "U+014B" }) // ŋ

        // ː is the modifier-letter length mark, never an ASCII colon.
        let length = entry("\u{02D0}", in: entries)
        #expect(length?.codePointNotation == "U+02D0")
        #expect(entry(":", in: entries) == nil)
    }
}
