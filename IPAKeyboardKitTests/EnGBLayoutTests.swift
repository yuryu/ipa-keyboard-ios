//
//  EnGBLayoutTests.swift
//  IPAKeyboardKitTests
//
//  Covers issue #74: the bundled en-GB (Standard Southern British) dialect
//  layout. The primary key layer follows the standard UK pronunciation-
//  dictionary convention (Wells LPD / CEPD / OALD; Roach 2004 JIPA
//  "British English: Received Pronunciation"), with contemporary SSB
//  variants (Lindsey 2019, *English After RP*) surfaced as long-press
//  alternates. Every dialect-distinctive symbol is locked by exact Unicode
//  scalars, written as \u{...} escapes so a lookalike substitution in either
//  the JSON or this file fails loudly (ɜ U+025C is not ɛ U+025B, ɑ U+0251 is
//  not ASCII a, ː U+02D0 is not a colon).
//

import Testing
@testable import IPAKeyboardKit

struct EnGBLayoutTests {

    // MARK: Helpers
    //
    // Key-walking helpers live in LayoutTestSupport.swift; the generic
    // structural invariants (split arrangement, spacer grouping, one-screen
    // budget, accessibility labels) are swept across every bundled layout by
    // BundledLayoutTests — only en-GB-specific content is tested here.

    private func enGBLayout() throws -> KeyboardLayout {
        try bundledLayout(locale: "en-GB")
    }

    // MARK: Metadata

    @Test func enGBHasTheExpectedDisplayName() throws {
        // (isBuiltIn and schemaVersion are swept across every bundled layout
        // by BundledLayoutTests.bundledLayoutsDecode and LayoutStoreTests.)
        let layout = try enGBLayout()
        #expect(layout.name == "English (UK) — Standard Southern British")
    }

    // MARK: Dialect-distinctive code points (dictionary convention layer)

    /// SSB/RP symbols that differ from General American, with exact scalars.
    /// Sources: OALD pronunciation key; Roach 2004 JIPA RP illustration;
    /// Wells 1982 lexical sets (trap–bath split BATH = ɑː).
    private static let britishVowels: [(scalars: [UInt32], accessibilityLabel: String)] = [
        ([0x0252], "open back rounded vowel"),                    // ɒ LOT
        ([0x0251, 0x02D0], "long open back unrounded vowel"),     // ɑː BATH/PALM/START
        ([0x0259, 0x028A], "goat diphthong"),                     // əʊ GOAT (not GA oʊ)
        ([0x025C, 0x02D0], "long open-mid central unrounded vowel"), // ɜː NURSE (non-rhotic)
        ([0x0254, 0x02D0], "long open-mid back rounded vowel"),   // ɔː THOUGHT/NORTH
        ([0x026A, 0x0259], "near diphthong"),                     // ɪə NEAR
        ([0x0065, 0x0259], "square diphthong"),                   // eə SQUARE
        ([0x028A, 0x0259], "cure diphthong"),                     // ʊə CURE
        ([0x0069, 0x02D0], "long close front unrounded vowel"),   // iː FLEECE
        ([0x0075, 0x02D0], "long close back rounded vowel"),      // uː GOOSE
    ]

    @Test(arguments: EnGBLayoutTests.britishVowels)
    func enGBUsesTheBritishVowelCodePoints(_ expected: (scalars: [UInt32], accessibilityLabel: String)) throws {
        let layout = try enGBLayout()
        let text = String(String.UnicodeScalarView(expected.scalars.map { Unicode.Scalar($0)! }))
        let vowelKey = try #require(
            key(inserting: text, in: layout),
            "expected en-GB to contain a key inserting \(expected.scalars.map { "U+" + String($0, radix: 16, uppercase: true) }.joined(separator: " "))")
        #expect(vowelKey.accessibilityLabel == expected.accessibilityLabel)
        #expect(text.unicodeScalars.map(\.value) == expected.scalars)
    }

    @Test func enGBKeepsTheFullVowelInventoryOnThePrimaryPanel() throws {
        // 12 monophthongs + 5 closing diphthongs + 3 centring diphthongs, all
        // visible by default (dictionary convention: OALD/LPD/CEPD symbol set).
        let primary = try #require(try enGBLayout().primaryArrangement?.primaryPanel)
        let inserted = Set(primary.rows.flatMap(\.keys).compactMap(insertText(of:)))
        let vowels: Set<String> = [
            "i\u{02D0}", "\u{026A}", "\u{028A}", "u\u{02D0}",
            "e", "\u{00E6}", "\u{028C}", "\u{0252}",
            "\u{0259}", "\u{025C}\u{02D0}", "\u{0251}\u{02D0}", "\u{0254}\u{02D0}",
            "e\u{026A}", "\u{0259}\u{028A}", "a\u{026A}", "a\u{028A}", "\u{0254}\u{026A}",
            "\u{026A}\u{0259}", "e\u{0259}", "\u{028A}\u{0259}",
        ]
        #expect(vowels.isSubset(of: inserted))
    }

    // MARK: Contemporary SSB alternates (Lindsey 2019, English After RP)

    @Test func enGBSurfacesModernSSBVariantsAsAlternates() throws {
        let layout = try enGBLayout()

        // DRESS: dictionary e, Lindsey ɛ (U+025B).
        let dress = try #require(key(inserting: "e", in: layout))
        #expect(dress.alternates.compactMap(insertText(of:)) == ["\u{025B}"])

        // SQUARE: dictionary eə, Lindsey monophthongal ɛː (U+025B U+02D0).
        let square = try #require(key(inserting: "e\u{0259}", in: layout))
        #expect(square.alternates.compactMap(insertText(of:)) == ["\u{025B}\u{02D0}"])

        // NEAR: dictionary ɪə, Lindsey monophthongal ɪː (U+026A U+02D0).
        let near = try #require(key(inserting: "\u{026A}\u{0259}", in: layout))
        #expect(near.alternates.compactMap(insertText(of:)) == ["\u{026A}\u{02D0}"])

        // TRAP: dictionary æ, Lindsey a (U+0061).
        let trap = try #require(key(inserting: "\u{00E6}", in: layout))
        #expect(trap.alternates.compactMap(insertText(of:)) == ["a"])
    }

    @Test func enGBCarriesTheWeakVowels() throws {
        // The neutralized weak vowels of the dictionary convention (happY = i,
        // weak u as in "situation"/"actual") ride as alternates of iː/uː.
        let layout = try enGBLayout()
        let fleece = try #require(key(inserting: "i\u{02D0}", in: layout))
        #expect(fleece.alternates.compactMap(insertText(of:)) == ["i"])
        let goose = try #require(key(inserting: "u\u{02D0}", in: layout))
        #expect(goose.alternates.compactMap(insertText(of:)) == ["u"])
        // lettER/commA is plain schwa in this non-rhotic accent.
        let schwa = try #require(key(inserting: "\u{0259}", in: layout))
        #expect(schwa.accessibilityLabel == "schwa")
    }

    // MARK: Glottal stop and dark l (allophones, so alternates + More panel)

    @Test func enGBCarriesTheGlottalStopWithT() throws {
        // T-glottalling is standard in contemporary SSB (Lindsey 2019 ch. 19:
        // ʔ for /t/ before consonants). ʔ is U+0294, never ASCII "?".
        let layout = try enGBLayout()
        let t = try #require(key(inserting: "t", in: layout))
        #expect(t.alternates.compactMap(insertText(of:)) == ["\u{0294}"])
        #expect(t.alternates.first?.accessibilityLabel == "glottal stop")

        // Also reachable as a plain key on the More panel, like en-US.
        let arrangement = try #require(layout.primaryArrangement)
        let morePanel = try #require(arrangement.panels.first { $0.name != arrangement.primaryPanel?.name })
        let moreTexts = Set(morePanel.rows.flatMap(\.keys).compactMap(insertText(of:)))
        #expect(moreTexts.contains("\u{0294}"))
    }

    @Test func enGBCarriesDarkLWithL() throws {
        // Clear [l] before vowels, dark (velarized) [ɫ] in the coda — the
        // standard GB allophone pair (Cruttenden, Gimson's Pronunciation of
        // English). ɫ is U+026B LATIN SMALL LETTER L WITH MIDDLE TILDE.
        let layout = try enGBLayout()
        let l = try #require(key(inserting: "l", in: layout))
        #expect(l.alternates.compactMap(insertText(of:)) == ["\u{026B}"])
        #expect(l.alternates.first?.accessibilityLabel == "velarized alveolar lateral approximant")
    }

    // MARK: Non-rhoticity — no General American symbols

    @Test func enGBHasNoRhoticOrGeneralAmericanVowels() throws {
        let texts = insertTexts(in: try enGBLayout())
        #expect(!texts.contains("\u{025A}"), "en-GB is non-rhotic: no ɚ")
        #expect(!texts.contains("\u{025D}"), "en-GB is non-rhotic: no ɝ")
        #expect(!texts.contains("o\u{028A}"), "GOAT is əʊ in SSB, not GA oʊ")
        #expect(!texts.contains("\u{027E}"), "the alveolar tap is a GA feature, not SSB")
    }

    // MARK: Consonants and marks

    @Test func enGBBundlesTheFullConsonantSystem() throws {
        // The 24 consonant phonemes shared by SSB and GA (OALD/Roach 2004),
        // with ɡ U+0261 (not ASCII g) and ɹ U+0279 as the rhotic.
        let texts = insertTexts(in: try enGBLayout())
        let consonants: Set<String> = [
            "p", "b", "t", "d", "k", "\u{0261}",
            "t\u{0283}", "d\u{0292}",
            "f", "v", "\u{03B8}", "\u{00F0}", "s", "z", "\u{0283}", "\u{0292}", "h",
            "m", "n", "\u{014B}",
            "l", "\u{0279}", "j", "w",
        ]
        #expect(consonants.isSubset(of: texts))
    }

    @Test func enGBBundlesStressAndLengthMarks() throws {
        let layout = try enGBLayout()
        let stress = try #require(key(inserting: "\u{02C8}", in: layout))
        #expect(stress.accessibilityLabel == "primary stress mark")
        let secondary = try #require(key(inserting: "\u{02CC}", in: layout))
        #expect(secondary.accessibilityLabel == "secondary stress mark")
        let length = try #require(key(inserting: "\u{02D0}", in: layout))
        #expect(length.accessibilityLabel == "length mark")
    }
}
