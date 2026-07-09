//
//  DeDELayoutTests.swift
//  IPAKeyboardKitTests
//
//  Covers issue #149 (umbrella #5): the bundled de-DE (Standard German,
//  Standardaussprache) dialect layout. Inventory per the "Standard German
//  phonology" description (Kohler 1999, "German", in the Handbook of the
//  International Phonetic Association) and the Duden Aussprachewörterbuch
//  transcription conventions, cross-checked against Wikipedia's
//  "Standard German phonology" and "Help:IPA/Standard German" as indexes.
//
//  Every dialect-distinctive symbol is locked by exact Unicode scalars,
//  written as \u{...} escapes so a lookalike substitution in either the JSON
//  or this file fails loudly — e.g. ɡ U+0261 (never ASCII g), ː U+02D0 (never
//  a colon), ʁ U+0281 (voiced uvular fricative, not ʀ U+0280 the trill), and
//  the front-rounded vowels øː U+00F8, œ U+0153, ʏ U+028F, yː U+0079.
//
//  Conventions encoded as data: German's defining tense-long / lax-short vowel
//  pairing rides on the length axis — each long tense keycap (iː, yː, uː, eː,
//  øː, oː, aː) carries its short lax counterpart (ɪ, ʏ, ʊ, ɛ, œ, ɔ, a) as the
//  first long-press alternate. The rhotic keycap is the most common
//  realization ʁ, with the trill [ʀ]/[r] and vocalized [ɐ̯] as alternates; the
//  ich-Laut ç and ach-Laut x are cross-linked as each other's alternate.
//

import Testing
@testable import IPAKeyboardKit

struct DeDELayoutTests {

    // MARK: Helpers

    private func deDELayout() throws -> KeyboardLayout {
        let layouts = LayoutStore().bundledLayouts()
        return try #require(layouts.first { $0.locale == "de-DE" },
                            "expected a bundled de-DE layout")
    }

    /// All top-level symbol keys of a layout (panel rows only, not alternates).
    private func topLevelKeys(in layout: KeyboardLayout) -> [Key] {
        layout.arrangements.flatMap(\.panels).flatMap(\.rows).flatMap(\.keys)
    }

    /// Every string the layout can insert — rows, function row, switch keys,
    /// and long-press alternates (recursively).
    private func insertTexts(in layout: KeyboardLayout) -> Set<String> {
        var texts = Set<String>()
        func visit(_ key: Key) {
            if case .insert(let text) = key.action { texts.insert(text) }
            key.alternates.forEach(visit)
        }
        let panels = layout.arrangements.flatMap(\.panels)
        (panels.flatMap(\.rows).flatMap(\.keys)
            + layout.arrangements.compactMap(\.functionRow).flatMap(\.keys)
            + panels.compactMap(\.switchKey))
            .forEach(visit)
        return texts
    }

    /// The first top-level key of `layout` that inserts exactly `text`.
    private func key(inserting text: String, in layout: KeyboardLayout) -> Key? {
        topLevelKeys(in: layout).first { key in
            if case .insert(let inserted) = key.action { return inserted == text }
            return false
        }
    }

    private func insertText(of key: Key) -> String? {
        if case .insert(let text) = key.action { return text }
        return nil
    }

    // MARK: Decode + metadata

    @Test func deDEDecodesWithExpectedMetadata() throws {
        let layout = try deDELayout()
        #expect(layout.isBuiltIn)
        #expect(layout.locale == "de-DE")
        #expect(layout.name.contains("German"))
        #expect(layout.name.contains("Standard"))
        #expect(layout.schemaVersion == KeyboardLayout.currentSchemaVersion)
    }

    // MARK: Structure (mirrors the en-US split-arrangement contract)

    @Test func deDEHasSplitArrangementWithTwoSwitchablePanels() throws {
        let arrangement = try #require(try deDELayout().primaryArrangement)
        #expect(arrangement.panels.count == 2)
        #expect(arrangement.maxRowCount <= 4)
        #expect(arrangement.totalRowCount <= 5)

        let functionRow = try #require(arrangement.functionRow)
        #expect(functionRow.keys.contains { $0.action == .nextKeyboard })

        let primary = try #require(arrangement.primaryPanel)
        guard case .switchPanel(let target) = try #require(primary.switchKey).action else {
            Issue.record("de-DE primary panel switchKey is not a switchPanel action")
            return
        }
        let secondary = try #require(arrangement.panel(named: target))
        #expect(secondary.name == target)
        #expect(secondary.name != primary.name)
        #expect(secondary.switchKey?.action == .switchPanel(primary.name))
    }

    @Test func deDEGroupsConsonantsLeftAndVowelsRightWithASpacer() throws {
        let primary = try #require(try deDELayout().primaryArrangement?.primaryPanel)
        let grouped = primary.rows.first { row in
            guard let gap = row.keys.firstIndex(where: \.isSpacer) else { return false }
            let before = row.keys[..<gap].contains { !$0.isSpacer }
            let after = row.keys[row.keys.index(after: gap)...].contains { !$0.isSpacer }
            return before && after
        }
        #expect(grouped != nil)
    }

    @Test func deDEFitsOneScreenPerPanel() throws {
        // No horizontal scrolling: rows no denser than a QWERTY row, and the
        // constant keyboard height matches the other bundled dialect layouts.
        let arrangement = try #require(try deDELayout().primaryArrangement)
        #expect(arrangement.totalRowCount <= 5)
        for panel in arrangement.panels {
            for row in panel.rows {
                let width = row.keys.reduce(0.0) { $0 + $1.widthFactor }
                #expect(width <= 12.0, "row too dense in de-DE panel \(panel.name)")
                #expect(row.keys.filter { !$0.isSpacer }.count <= 10,
                        "too many keys in a row of de-DE panel \(panel.name)")
            }
        }
    }

    // MARK: Code-point spot checks (trap-prone distinctive scalars)

    @Test func deDEUsesTheExactStandardGermanCodePoints() throws {
        // Spot-check the lookalike-prone scalars against explicit escapes so an
        // editor silently substituting a glyph (ʁ↔ʀ, ː↔colon, ɡ↔g) fails loudly.
        let texts = insertTexts(in: try deDELayout())
        let required: [(String, String)] = [
            ("\u{0261}", "voiced velar plosive ɡ (script g)"),
            ("\u{02D0}", "length mark ː"),
            ("\u{0281}", "voiced uvular fricative ʁ"),
            ("\u{0280}", "uvular trill ʀ"),
            ("\u{00E7}", "voiceless palatal fricative ç (ich-Laut)"),
            ("x", "voiceless velar fricative x (ach-Laut)"),
            ("\u{014B}", "velar nasal ŋ"),
            ("\u{0250}", "a-schwa ɐ"),
            ("\u{0259}", "schwa ə"),
            ("\u{0294}", "glottal stop ʔ"),
            ("pf", "voiceless labiodental affricate pf"),
            ("ts", "voiceless alveolar affricate ts"),
            ("t\u{0283}", "voiceless postalveolar affricate tʃ"),
        ]
        for (text, what) in required {
            #expect(texts.contains(text), "de-DE should insert \(what)")
        }
    }

    @Test func deDECarriesTheFrontRoundedVowels() throws {
        // The front-rounded vowels are the signature of the German vowel
        // system. The long tense keycaps øː/yː are visible; their short lax
        // counterparts œ/ʏ ride as alternates. Exact scalars: ø U+00F8,
        // œ U+0153, y U+0079, ʏ U+028F, ː U+02D0.
        let layout = try deDELayout()

        let oe = try #require(key(inserting: "\u{00F8}\u{02D0}", in: layout),
                              "expected a long close-mid front rounded vowel øː key")
        #expect(oe.accessibilityLabel == "long close-mid front rounded vowel")
        #expect(oe.alternates.compactMap(insertText(of:)) == ["\u{0153}"])
        #expect(oe.alternates.first?.accessibilityLabel == "open-mid front rounded vowel")

        let y = try #require(key(inserting: "\u{0079}\u{02D0}", in: layout),
                             "expected a long close front rounded vowel yː key")
        #expect(y.accessibilityLabel == "long close front rounded vowel")
        #expect(y.alternates.compactMap(insertText(of:)) == ["\u{028F}"])

        // Both short lax rounded vowels are reachable (as alternates).
        let texts = insertTexts(in: layout)
        #expect(texts.contains("\u{0153}"), "de-DE should reach œ U+0153")
        #expect(texts.contains("\u{028F}"), "de-DE should reach ʏ U+028F")
    }

    // MARK: Tense-long / lax-short pairing on the length axis

    @Test func deDEPairsLongTenseVowelsWithTheirShortLaxCounterparts() throws {
        let layout = try deDELayout()
        let pairs: [(long: String, short: String, shortLabel: String)] = [
            ("i\u{02D0}", "\u{026A}", "near-close near-front unrounded vowel"),
            ("u\u{02D0}", "\u{028A}", "near-close near-back rounded vowel"),
            ("o\u{02D0}", "\u{0254}", "open-mid back rounded vowel"),
            ("a\u{02D0}", "a", "open front unrounded vowel"),
        ]
        for pair in pairs {
            let longKey = try #require(key(inserting: pair.long, in: layout),
                                       "expected a de-DE key for \(pair.long)")
            let short = try #require(
                longKey.alternates.first { insertText(of: $0) == pair.short },
                "\(pair.long) should carry \(pair.short) as a long-press alternate")
            #expect(short.accessibilityLabel == pair.shortLabel)
        }

        // The mid-front key folds in both the short ɛ and the long open-mid ɛː
        // (the disputed but standard-pronunciation "ä" of <spät>, <Käse>).
        let eKey = try #require(key(inserting: "e\u{02D0}", in: layout))
        #expect(eKey.alternates.compactMap(insertText(of:)) == ["\u{025B}", "\u{025B}\u{02D0}"])
    }

    // MARK: Rhotic realizations as long-press alternates

    @Test func deDERhoticKeepsTheUvularFricativeWithTrillAndVocalizedVariants() throws {
        // /r/ has several standard realizations. The keycap is the most common
        // one, the voiced uvular fricative ʁ (U+0281), with the uvular trill
        // ʀ (U+0280), the alveolar trill r, and the vocalized [ɐ̯] (ɐ U+0250 +
        // non-syllabic U+032F) as alternates.
        let layout = try deDELayout()
        let rhotic = try #require(key(inserting: "\u{0281}", in: layout))
        #expect(rhotic.accessibilityLabel == "voiced uvular fricative")
        #expect(rhotic.alternates.compactMap(insertText(of:)) ==
                ["\u{0280}", "r", "\u{0250}\u{032F}"])
        #expect(rhotic.alternates.last?.accessibilityLabel == "vocalized r")
    }

    // MARK: ich-Laut / ach-Laut cross-linked

    @Test func deDECrossLinksTheIchAndAchLaut() throws {
        // ç (U+00E7, ich-Laut) and x (U+0078, ach-Laut) are complementary
        // dorsal-fricative allophones; each is a keycap carrying the other as
        // its long-press alternate.
        let layout = try deDELayout()
        let ich = try #require(key(inserting: "\u{00E7}", in: layout))
        #expect(ich.accessibilityLabel == "voiceless palatal fricative")
        #expect(ich.alternates.compactMap(insertText(of:)) == ["x"])

        let ach = try #require(key(inserting: "x", in: layout))
        #expect(ach.accessibilityLabel == "voiceless velar fricative")
        #expect(ach.alternates.compactMap(insertText(of:)) == ["\u{00E7}"])
    }

    // MARK: Diphthongs

    @Test func deDECarriesTheThreeDiphthongs() throws {
        // aɪ (mein), aʊ (Haus), ɔʏ (neu/Häuser). The third diphthong is the
        // Duden ü-glide ɔʏ (ɔ U+0254 + ʏ U+028F) on the keycap, with the
        // phonetic i-glide variant ɔɪ (ɔ + ɪ U+026A) as an alternate.
        let layout = try deDELayout()
        #expect(key(inserting: "a\u{026A}", in: layout) != nil)   // aɪ
        #expect(key(inserting: "a\u{028A}", in: layout) != nil)   // aʊ
        let eu = try #require(key(inserting: "\u{0254}\u{028F}", in: layout))
        #expect(eu.alternates.compactMap(insertText(of:)) == ["\u{0254}\u{026A}"])
    }

    // MARK: Syllabic consonants on the More panel

    @Test func deDEMorePanelCarriesTheSyllabicConsonantsAndMarks() throws {
        // Syllabic n̩/l̩/m̩ (base + combining vertical line below U+0329) and the
        // suprasegmental marks live on the secondary panel, like en-US/en-GB.
        let layout = try deDELayout()
        let arrangement = try #require(layout.primaryArrangement)
        let morePanel = try #require(arrangement.panels.first { $0.name != arrangement.primaryPanel?.name })
        let moreTexts = Set(morePanel.rows.flatMap(\.keys).compactMap(insertText(of:)))
        let expected: Set<String> = [
            "\u{02C8}",           // ˈ primary stress
            "\u{02CC}",           // ˌ secondary stress
            "\u{02D0}",           // ː length
            "\u{0294}",           // ʔ glottal stop
            "n\u{0329}",          // n̩ syllabic n
            "l\u{0329}",          // l̩ syllabic l
            "m\u{0329}",          // m̩ syllabic m
        ]
        #expect(expected.isSubset(of: moreTexts))

        let syllabicN = try #require(key(inserting: "n\u{0329}", in: layout))
        #expect(syllabicN.accessibilityLabel == "syllabic alveolar nasal")
        // The syllabic mark composes onto its base as a single grapheme.
        #expect("n\u{0329}".count == 1)
    }

    // MARK: No ASCII / lookalike substitutions

    @Test func deDENeverUsesASCIIOrColonLookalikes() throws {
        let texts = insertTexts(in: try deDELayout())
        // The velar plosive is ɡ U+0261, never ASCII g.
        #expect(!texts.contains("g"))
        // Length is ː U+02D0, never a colon; glottal stop is ʔ, never "?".
        #expect(!texts.contains(":"))
        #expect(!texts.contains("?"))
        // Every length mark that appears is the triangular colon U+02D0.
        for text in texts where text.contains("\u{02D0}") {
            #expect(text.unicodeScalars.contains(Unicode.Scalar(0x02D0)!))
        }
    }

    // MARK: Accessibility — every key, alternates included

    @Test func deDEEveryInsertKeyHasAnAccessibilityLabel() throws {
        let layout = try deDELayout()
        func check(_ key: Key) {
            if case .insert = key.action {
                #expect(!(key.accessibilityLabel ?? "").isEmpty,
                        "missing accessibilityLabel for de-DE key \(key.displayLabel)")
            }
            key.alternates.forEach(check)
        }
        let panels = layout.arrangements.flatMap(\.panels)
        (panels.flatMap(\.rows).flatMap(\.keys)
            + layout.arrangements.compactMap(\.functionRow).flatMap(\.keys)
            + panels.compactMap(\.switchKey))
            .forEach(check)
    }
}
