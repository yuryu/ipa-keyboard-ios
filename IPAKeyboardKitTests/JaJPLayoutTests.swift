//
//  JaJPLayoutTests.swift
//  IPAKeyboardKitTests
//
//  Covers issue #75: the bundled ja-JP (Japanese, Tokyo standard) dialect
//  layout. Inventory per Okada (1999), "Japanese", in the Handbook of the
//  International Phonetic Association (IPA illustration), supplemented by
//  Vance (2008), *The Sounds of Japanese*, and Labrune (2012), *The
//  Phonology of Japanese*, for the allophones [ɕ ʑ tɕ dʑ dz ɸ ç ɲ ŋ ɺ],
//  the palatalized series, devoicing, and pitch-accent notation.
//
//  Every dialect-distinctive symbol is locked by exact Unicode scalar so a
//  lookalike substitution fails loudly — e.g. ɡ U+0261 (never ASCII g),
//  ɯ U+026F (never u), ː U+02D0 (never a colon), precomposed ç U+00E7
//  (never c + combining cedilla).
//
//  Conventions encoded as data (per Okada 1999): gemination is written by
//  doubling the consonant letter ([ɡakkoː]) and vowel length with ː, so
//  there is deliberately no dedicated sokuon key; pitch accent is the acute
//  accent on the accented mora ("A mora transcribed with an acute accent,
//  á, is said to be accented and is high"), with ꜜ downstep as the
//  accent-kernel notation common in the wider literature.
//

import Testing
@testable import IPAKeyboardKit

struct JaJPLayoutTests {

    // MARK: Helpers

    private func jaJPLayout() throws -> KeyboardLayout {
        let layouts = LayoutStore().bundledLayouts()
        return try #require(layouts.first { $0.locale == "ja-JP" },
                            "expected a bundled ja-JP layout")
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

    @Test func jaJPDecodesAsABuiltInTokyoLayout() throws {
        let layout = try jaJPLayout()
        #expect(layout.isBuiltIn)
        #expect(layout.locale == "ja-JP")
        #expect(layout.schemaVersion == KeyboardLayout.currentSchemaVersion)
        #expect(layout.name.contains("Japanese"))
        #expect(layout.name.contains("Tokyo"))
    }

    @Test func jaJPHasSplitArrangementWithTwoSwitchablePanels() throws {
        let layout = try jaJPLayout()
        let arrangement = try #require(layout.primaryArrangement)
        #expect(arrangement.panels.count == 2)

        // Same height budget as en-US: totalRowCount 5 (4 symbol rows + bar).
        #expect(arrangement.maxRowCount <= 4)
        #expect(arrangement.totalRowCount <= 5)

        // The shared bottom bar carries the globe key.
        let functionRow = try #require(arrangement.functionRow)
        #expect(functionRow.keys.contains { $0.action == .nextKeyboard })

        // The primary panel's switch key reaches the secondary panel, whose
        // switch key returns to the primary.
        let primary = try #require(arrangement.primaryPanel)
        guard case .switchPanel(let target) = try #require(primary.switchKey).action else {
            Issue.record("ja-JP primary panel switchKey is not a switchPanel action")
            return
        }
        let secondary = try #require(arrangement.panel(named: target))
        #expect(secondary.name == target)
        #expect(secondary.name != primary.name)
        #expect(secondary.switchKey?.action == .switchPanel(primary.name))
    }

    @Test func jaJPGroupsConsonantsLeftAndVowelsRightWithASpacer() throws {
        let layout = try jaJPLayout()
        let primary = try #require(layout.primaryArrangement?.primaryPanel)
        let grouped = primary.rows.first { row in
            guard let gap = row.keys.firstIndex(where: \.isSpacer) else { return false }
            let before = row.keys[..<gap].contains { !$0.isSpacer }
            let after = row.keys[row.keys.index(after: gap)...].contains { !$0.isSpacer }
            return before && after
        }
        #expect(grouped != nil)
    }

    @Test func jaJPFitsOneScreenPerPanel() throws {
        // Same density heuristics as the other bundled layouts: no horizontal
        // scrolling, rows no denser than a QWERTY row.
        let arrangement = try #require(try jaJPLayout().primaryArrangement)
        for panel in arrangement.panels {
            for row in panel.rows {
                #expect(row.keys.reduce(0.0) { $0 + $1.widthFactor } <= 12.0,
                        "row too dense in ja-JP panel \(panel.name)")
                #expect(row.keys.filter { !$0.isSpacer }.count <= 10,
                        "too many keys in a row of ja-JP panel \(panel.name)")
            }
        }
    }

    // MARK: Code-point spot checks (Okada 1999 inventory)

    @Test func jaJPUsesTheExactTokyoCodePoints() throws {
        let texts = insertTexts(in: try jaJPLayout())
        let required: [(String, String)] = [
            ("\u{026F}", "close back unrounded vowel ɯ"),
            ("\u{0274}", "moraic nasal ɴ (small capital)"),
            ("\u{0255}", "voiceless alveolo-palatal fricative ɕ"),
            ("\u{0291}", "voiced alveolo-palatal fricative ʑ"),
            ("t\u{0255}", "voiceless alveolo-palatal affricate tɕ"),
            ("d\u{0291}", "voiced alveolo-palatal affricate dʑ"),
            ("ts", "voiceless alveolar affricate ts"),
            ("dz", "voiced alveolar affricate dz"),
            ("\u{0278}", "voiceless bilabial fricative ɸ"),
            ("\u{00E7}", "voiceless palatal fricative ç"),
            ("\u{027E}", "alveolar tap ɾ"),
            ("\u{0261}", "voiced velar plosive ɡ (script g)"),
            ("\u{014B}", "velar nasal ŋ"),
            ("\u{0272}", "palatal nasal ɲ"),
            ("\u{0294}", "glottal stop ʔ"),
            ("\u{02D0}", "length mark ː"),
        ]
        for (text, what) in required {
            #expect(texts.contains(text), "ja-JP should insert \(what)")
        }
    }

    @Test func jaJPNeverUsesASCIIOrDecomposedLookalikes() throws {
        let texts = insertTexts(in: try jaJPLayout())
        // The velar plosive is ɡ U+0261, never ASCII g.
        #expect(!texts.contains("g"))
        // ç ships precomposed (NFC, U+00E7), never c + combining cedilla.
        // Swift String equality is canonical-equivalence-based ("ç" ==
        // "c\u{0327}"), so the decomposed form must be ruled out at the
        // scalar level.
        #expect(!texts.contains { $0.unicodeScalars.contains(Unicode.Scalar(0x0327)!) })
        for text in texts where text.contains("\u{00E7}") {
            #expect(text.unicodeScalars.contains(Unicode.Scalar(0x00E7)!))
        }
        // Length is ː U+02D0, not a colon; no full-height arrow for downstep.
        #expect(!texts.contains(":"))
        #expect(!texts.contains("\u{2193}"), "downstep must be ꜜ U+A71C, not the arrow ↓ U+2193")
    }

    // MARK: Vowels — ɯ primary, u as the broad-transcription alternate

    @Test func jaJPHighBackVowelIsUnroundedWithRoundedAlternate() throws {
        // Okada (1999): /u/ "resembling [ɯ] auditorily, has compressed lips,
        // so that it is unrounded"; Vance (2008) and Labrune (2012) transcribe
        // [ɯ]. The key is ɯ with u as the broad/phonemic long-press variant.
        let layout = try jaJPLayout()
        let vowel = try #require(key(inserting: "\u{026F}", in: layout))
        #expect(vowel.accessibilityLabel == "close back unrounded vowel")
        #expect(vowel.alternates.compactMap(insertText(of:)) == ["u"])
        #expect(vowel.alternates.first?.accessibilityLabel == "close back rounded vowel")
    }

    @Test func jaJPKeepsTheFiveVowelsAndLengthOnThePrimaryPanel() throws {
        // The five short vowels plus the length mark (long vowels and the
        // second half of geminates are written with ː per Okada 1999).
        let layout = try jaJPLayout()
        let primary = try #require(layout.primaryArrangement?.primaryPanel)
        let inserted = Set(primary.rows.flatMap(\.keys).compactMap(insertText(of:)))
        let vowels: Set<String> = ["a", "i", "\u{026F}", "e", "o", "\u{02D0}"]
        #expect(vowels.isSubset(of: inserted))
    }

    // MARK: Palatalized series as long-press alternates

    @Test func jaJPPalatalizedSeriesRideAsAlternates() throws {
        // Okada (1999): "/j/ affects the preceding consonant as /i/ does"
        // (e.g. /mjaku/ [mʲaku]); Labrune (2012): /p b k ɡ ɾ/ (and m)
        // palatalize with superscript ʲ, palatalized n is [ɲ] (its own key).
        let layout = try jaJPLayout()
        let pairs: [(base: String, palatalized: String)] = [
            ("p", "p\u{02B2}"),
            ("b", "b\u{02B2}"),
            ("k", "k\u{02B2}"),
            ("\u{0261}", "\u{0261}\u{02B2}"),
            ("m", "m\u{02B2}"),
            ("\u{027E}", "\u{027E}\u{02B2}"),
        ]
        for pair in pairs {
            let base = try #require(key(inserting: pair.base, in: layout),
                                    "expected a ja-JP key for \(pair.base)")
            let alternate = try #require(
                base.alternates.first { insertText(of: $0) == pair.palatalized },
                "\(pair.base) should carry \(pair.palatalized) as a long-press alternate")
            let label = try #require(alternate.accessibilityLabel)
            #expect(label.hasPrefix("palatalized"))
            // The superscript j is the spacing modifier letter U+02B2.
            #expect(pair.palatalized.unicodeScalars.last?.value == 0x02B2)
        }
    }

    @Test func jaJPTapCarriesTheLiquidVariants() throws {
        // Okada (1999): the liquid is a postalveolar tap, with lateral and
        // approximant realizations "not unusual in all positions"; the lateral
        // flap [ɺ] per Vance (2008); the approximant [ɹ] U+0279 is attested in
        // the same variant set; r is the phonemic symbol of Okada's chart
        // (IPA: trill).
        let layout = try jaJPLayout()
        let tap = try #require(key(inserting: "\u{027E}", in: layout))
        #expect(tap.accessibilityLabel == "alveolar tap")
        #expect(tap.alternates.compactMap(insertText(of:)) ==
                ["\u{027E}\u{02B2}", "\u{027A}", "l", "\u{0279}", "r"])
    }

    @Test func jaJPAffricateTcAlsoOffersTheVoicedCounterpart() throws {
        // [dʑ] is the common utterance-initial realization of /z/ before the
        // palatal vowels; surfacing it on tɕ (its voiceless counterpart) as
        // well as on ʑ saves a hunt across keys. Duplicate alternate texts
        // across keys are deliberate and harmless.
        let layout = try jaJPLayout()
        let tc = try #require(key(inserting: "t\u{0255}", in: layout))
        #expect(tc.alternates.compactMap(insertText(of:)).contains("d\u{0291}"))
    }

    // MARK: Devoicing, nasalization, centralization diacritics

    @Test func jaJPDevoicingRingIsBelowWithRingAboveAlternate() throws {
        // Okada (1999): "/i, u/ tend to be devoiced ... between voiceless
        // consonants". Ring below U+0325 is the IPA voiceless diacritic; the
        // chart licenses ring above U+030A for symbols with descenders (ŋ̊).
        let layout = try jaJPLayout()
        let ring = try #require(key(inserting: "\u{0325}", in: layout))
        #expect(ring.accessibilityLabel == "voiceless")
        #expect(ring.label == "\u{25CC}\u{0325}")
        let above = try #require(ring.alternates.first { insertText(of: $0) == "\u{030A}" })
        #expect(above.label == "\u{25CC}\u{030A}")
        #expect((above.accessibilityLabel ?? "").hasPrefix("voiceless"))
    }

    @Test func jaJPMorePanelCarriesTheDiacriticsAndAccentMarks() throws {
        let layout = try jaJPLayout()
        let arrangement = try #require(layout.primaryArrangement)
        let morePanel = try #require(arrangement.panels.first { $0.name != arrangement.primaryPanel?.name })
        let moreTexts = Set(morePanel.rows.flatMap(\.keys).compactMap(insertText(of:)))
        let expected: Set<String> = [
            "\u{0301}", // combining acute — pitch accent (Okada 1999)
            "\u{A71C}", // downstep ꜜ
            "\u{0325}", // voiceless ring below
            "\u{0303}", // nasalized (moraic nasal as nasalized vowel)
            "\u{0308}", // centralized (Okada's narrow [ɯ̈])
            "\u{031E}", // lowered (mid vowels [e̞ o̞], Vance 2008)
            "\u{02B2}", // palatalized ʲ
        ]
        #expect(expected.isSubset(of: moreTexts))
    }

    // MARK: Pitch accent

    @Test func jaJPPitchAccentUsesTheAcuteAccentPlusDownstep() throws {
        // Okada (1999): "A mora transcribed with an acute accent, á, is said
        // to be accented and is high." ꜜ U+A71C marks the accent kernel in
        // the wider Japanese phonology literature. The spoken name matches
        // ipa-chart.json's key for the identical inserted string, so U+0301
        // has one VoiceOver name across the whole bundle.
        let layout = try jaJPLayout()
        let acute = try #require(key(inserting: "\u{0301}", in: layout))
        #expect(acute.accessibilityLabel == "combining high tone")
        #expect(acute.label == "\u{25CC}\u{0301}")

        let downstep = try #require(key(inserting: "\u{A71C}", in: layout))
        #expect(downstep.accessibilityLabel == "downstep")
    }

    // MARK: Accessibility

    @Test func jaJPEveryInsertKeyHasAnAccessibilityLabel() throws {
        // Every symbol key promises a spoken IPA name, alternates included.
        let layout = try jaJPLayout()
        func check(_ key: Key) {
            if case .insert = key.action {
                #expect(!(key.accessibilityLabel ?? "").isEmpty,
                        "missing accessibilityLabel for ja-JP key \(key.displayLabel)")
            }
            key.alternates.forEach(check)
        }
        let panels = layout.arrangements.flatMap(\.panels)
        (panels.flatMap(\.rows).flatMap(\.keys)
            + layout.arrangements.compactMap(\.functionRow).flatMap(\.keys)
            + panels.compactMap(\.switchKey))
            .forEach(check)
    }

    // MARK: Grapheme behavior of the marks this layout composes

    @Test func devoicedVowelFormsOneClusterDeletedAsAUnit() {
        // ɯ (U+026F) + combining ring below (U+0325), as in [sɯ̥ki].
        let context = "\u{026F}\u{0325}"
        #expect(Array(context.unicodeScalars) == [Unicode.Scalar(0x026F)!, Unicode.Scalar(0x0325)!])
        #expect(context.count == 1) // one user-perceived character
        #expect(GraphemeText.deletionScalarCount(before: context) == 2)
    }

    @Test func accentedMoraFormsOneClusterDeletedAsAUnit() {
        // a (U+0061) + combining acute (U+0301), as in [háɕi] "chopsticks".
        let context = "a\u{0301}"
        #expect(Array(context.unicodeScalars) == [Unicode.Scalar(0x0061)!, Unicode.Scalar(0x0301)!])
        #expect(context.count == 1)
        #expect(GraphemeText.deletionScalarCount(before: context) == 2)
    }

    @Test func palatalizedConsonantIsTwoClustersLikeAspiration() {
        // ʲ U+02B2 is a *spacing* modifier letter: [kʲ] is two user-perceived
        // characters, so one backspace removes just the ʲ.
        let context = "k\u{02B2}"
        #expect(context.count == 2)
        #expect(GraphemeText.deletionScalarCount(before: context) == 1)
    }

    @Test func longVowelAndGeminateTranscriptionsUseExactScalars() {
        // Okada (1999) writes long vowels with ː and geminates by doubling:
        // 学校 [ɡakkoː] "school" — no sokuon key needed, ever.
        let gakkou = "\u{0261}akko\u{02D0}"
        #expect(gakkou == "ɡakkoː")
        #expect(gakkou.unicodeScalars.map(\.value) == [0x261, 0x61, 0x6B, 0x6B, 0x6F, 0x2D0])
    }
}
