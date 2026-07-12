//
//  ToneAndSpacingModifierTests.swift
//  IPAKeyboardKitTests
//
//  Covers issue #29: tone and word-accent marks in the generic layouts, and
//  the en-US spacing modifier letters (aspiration + release variants) for
//  General American narrow transcription (e.g. [pʰɪt]).
//
//  Every new code point is locked by exact Unicode scalar so a lookalike
//  substitution fails loudly — e.g. the legacy full-height arrow ↓ U+2193
//  for downstep ꜜ U+A71C, or the alveolar lateral click ǁ U+01C1 for the
//  major-group mark ‖ U+2016.
//

import Testing
@testable import IPAKeyboardKit

struct ToneAndSpacingModifierTests {

    // MARK: Helpers
    //
    // Key-walking and bundled-layout lookup helpers live in
    // LayoutTestSupport.swift.

    private func enUSLayout() throws -> KeyboardLayout {
        try bundledLayout(locale: "en-US")
    }

    // MARK: en-US spacing modifiers (issue #29 — aspiration and releases)

    /// The four spacing modifier letters added for GA narrow transcription,
    /// with their exact scalars and spoken names. Sources: Ladefoged & Johnson,
    /// *A Course in Phonetics* (GA allophone rules: aspiration, anticipatory
    /// rounding, lateral and nasal release); code points per the Unicode UCD.
    private static let expectedSpacingModifiers: [(scalar: Unicode.Scalar, accessibilityLabel: String)] = [
        (Unicode.Scalar(0x02B0)!, "aspirated"),       // ʰ MODIFIER LETTER SMALL H
        (Unicode.Scalar(0x02B7)!, "labialized"),      // ʷ MODIFIER LETTER SMALL W
        (Unicode.Scalar(0x02E1)!, "lateral release"), // ˡ MODIFIER LETTER SMALL L
        (Unicode.Scalar(0x207F)!, "nasal release"),   // ⁿ SUPERSCRIPT LATIN SMALL LETTER N
    ]

    @Test(arguments: ToneAndSpacingModifierTests.expectedSpacingModifiers)
    func enUSContainsTheSpacingModifierKey(_ expected: (scalar: Unicode.Scalar, accessibilityLabel: String)) throws {
        let layout = try enUSLayout()
        let text = String(expected.scalar)
        let modifierKey = try #require(
            key(inserting: text, in: layout),
            "expected en-US to contain an insert key for U+\(String(expected.scalar.value, radix: 16, uppercase: true))")
        #expect(modifierKey.accessibilityLabel == expected.accessibilityLabel)
        // Exactly one scalar each — no lookalike or precomposed drift.
        #expect(text.unicodeScalars.count == 1)
        #expect(text.unicodeScalars.first?.value == expected.scalar.value)
    }

    @Test func enUSSpacingModifiersLiveInTheMorePanel() throws {
        // Additive change: narrow-transcription marks belong on the secondary
        // panel, not the restructured primary panel (issue #39/#41).
        let layout = try enUSLayout()
        let arrangement = try #require(layout.primaryArrangement)
        let morePanel = try #require(arrangement.panels.first { $0.name != arrangement.primaryPanel?.name })
        let moreTexts = Set(morePanel.rows.flatMap(\.keys).compactMap(insertText(of:)))
        let modifierTexts = Set(Self.expectedSpacingModifiers.map { String($0.scalar) })
        #expect(modifierTexts.isSubset(of: moreTexts))
    }

    @Test func aspirationIsASpacingLetterNotACombiningMark() {
        // ʰ U+02B0 is a *spacing* modifier letter: [pʰ] is two user-perceived
        // characters, so one backspace removes just the ʰ — unlike the
        // combining diacritics, which delete together with their base.
        let context = "p\u{02B0}"
        #expect(Array(context.unicodeScalars) == [Unicode.Scalar(0x0070)!, Unicode.Scalar(0x02B0)!])
        #expect(context.count == 2)
        #expect(GraphemeText.deletionScalarCount(before: context) == 1)
    }

    @Test func narrowTranscriptionOfPitUsesExactScalars() {
        // The motivating example from issue #29: en-US can now write [pʰɪt].
        let pit = "p\u{02B0}\u{026A}t"
        #expect(pit == "pʰɪt")
        #expect(pit.unicodeScalars.map(\.value) == [0x70, 0x2B0, 0x26A, 0x74])
    }

    // MARK: "IPA — Full (QWERTY)" tone letters and word accents

    @Test func fullLayoutInsertsAllToneBarsAndWordAccents() throws {
        let texts = insertTexts(in: try bundledLayout(named: "IPA — Full (QWERTY)"))
        let required: [(String, String)] = [
            ("\u{02E5}", "extra-high tone bar ˥"),
            ("\u{02E6}", "high tone bar ˦"),
            ("\u{02E7}", "mid tone bar ˧"),
            ("\u{02E8}", "low tone bar ˨"),
            ("\u{02E9}", "extra-low tone bar ˩"),
            ("\u{A71C}", "downstep ꜜ"),
            ("\u{A71B}", "upstep ꜛ"),
            ("\u{2197}", "global rise ↗"),
            ("\u{2198}", "global fall ↘"),
        ]
        for (text, what) in required {
            #expect(texts.contains(text), "IPA — Full should insert \(what)")
        }
    }

    @Test func fullLayoutGroupsToneBarsUnderTheExtraHighKey() throws {
        // One compact key: ˥ primary, the remaining bars as long-press
        // alternates, high to extra-low in chart order.
        let layout = try bundledLayout(named: "IPA — Full (QWERTY)")
        let toneKey = try #require(key(inserting: "\u{02E5}", in: layout))
        #expect(toneKey.alternates.compactMap(insertText(of:)) ==
                ["\u{02E6}", "\u{02E7}", "\u{02E8}", "\u{02E9}"])
    }

    @Test func fullLayoutGroupsWordAccentsUnderDownstep() throws {
        // ꜜ primary (downstep is the common mark in tone-language description),
        // with upstep and the global rise/fall arrows as alternates.
        let layout = try bundledLayout(named: "IPA — Full (QWERTY)")
        let downstepKey = try #require(key(inserting: "\u{A71C}", in: layout))
        #expect(downstepKey.accessibilityLabel == "downstep")
        #expect(downstepKey.alternates.compactMap(insertText(of:)) ==
                ["\u{A71B}", "\u{2197}", "\u{2198}"])
    }

    // MARK: "IPA — Chart" Tones panel

    private func chartTonesPanel() throws -> Panel {
        let layout = try bundledLayout(named: "IPA — Chart")
        let arrangement = try #require(layout.primaryArrangement)
        return try #require(arrangement.panels.first { $0.name == "Tones" },
                            "the chart layout should have a Tones panel")
    }

    @Test func chartTonesPanelJoinsThePanelCycle() throws {
        let layout = try bundledLayout(named: "IPA — Chart")
        let arrangement = try #require(layout.primaryArrangement)
        let more = try #require(arrangement.panels.first { $0.name == "More" })
        #expect(more.switchKey?.action == .switchPanel("Tones"))
        let tones = try chartTonesPanel()
        let primary = try #require(arrangement.primaryPanel)
        #expect(tones.switchKey?.action == .switchPanel(primary.name))
    }

    @Test func chartTonesPanelStaysWithinTheHeightAndDensityBudget() throws {
        // Adding the panel must not grow the keyboard: the tallest panel still
        // sets the height, and rows stay within the shared density budget.
        let tones = try chartTonesPanel()
        #expect(tones.rows.count <= 3)
        for row in tones.rows {
            #expect(row.keys.filter { !$0.isSpacer }.count <= 10)
            #expect(row.keys.reduce(0.0) { $0 + $1.widthFactor } <= 12.0)
        }
    }

    /// Chart level tones: bar letter primary, combining diacritic equivalent
    /// as the long-press alternate — the two notations the IPA chart shows
    /// side by side ("e̋ or ˥"). Code points per the Unicode UCD.
    private static let expectedLevelTones: [(bar: Unicode.Scalar, combining: Unicode.Scalar, name: String)] = [
        (Unicode.Scalar(0x02E5)!, Unicode.Scalar(0x030B)!, "extra-high"), // ˥ / COMBINING DOUBLE ACUTE ACCENT
        (Unicode.Scalar(0x02E6)!, Unicode.Scalar(0x0301)!, "high"),       // ˦ / COMBINING ACUTE ACCENT
        (Unicode.Scalar(0x02E7)!, Unicode.Scalar(0x0304)!, "mid"),        // ˧ / COMBINING MACRON
        (Unicode.Scalar(0x02E8)!, Unicode.Scalar(0x0300)!, "low"),        // ˨ / COMBINING GRAVE ACCENT
        (Unicode.Scalar(0x02E9)!, Unicode.Scalar(0x030F)!, "extra-low"),  // ˩ / COMBINING DOUBLE GRAVE ACCENT
    ]

    @Test func chartLevelToneBarsCarryTheirCombiningEquivalents() throws {
        let layout = try bundledLayout(named: "IPA — Chart")
        let dottedCircle = String(Unicode.Scalar(0x25CC)!)
        for expected in Self.expectedLevelTones {
            let barText = String(expected.bar)
            let barKey = try #require(
                key(inserting: barText, in: layout),
                "chart should have a \(expected.name) tone bar key")
            #expect(barKey.accessibilityLabel == "\(expected.name) tone bar")

            let combiningText = String(expected.combining)
            let alternate = try #require(
                barKey.alternates.first { insertText(of: $0) == combiningText },
                "\(expected.name) bar should carry U+\(String(expected.combining.value, radix: 16, uppercase: true)) as its alternate")
            #expect(alternate.label == dottedCircle + combiningText)
            #expect(alternate.accessibilityLabel == "combining \(expected.name) tone")
            #expect(combiningText.unicodeScalars.count == 1)
        }
    }

    @Test func chartContourKeysUseTheUncontestedBarSequences() throws {
        // Only rising ˩˥ and falling ˥˩ ship as sequences — chart
        // reproductions disagree on the finer contours (high rising etc.), so
        // those are composed from the level bars instead of being hardcoded.
        let layout = try bundledLayout(named: "IPA — Chart")

        let rising = try #require(key(inserting: "\u{02E9}\u{02E5}", in: layout))
        #expect(rising.accessibilityLabel == "rising tone")
        #expect(rising.alternates.compactMap(insertText(of:)) == ["\u{030C}"]) // COMBINING CARON

        let falling = try #require(key(inserting: "\u{02E5}\u{02E9}", in: layout))
        #expect(falling.accessibilityLabel == "falling tone")
        #expect(falling.alternates.compactMap(insertText(of:)) == ["\u{0302}"]) // COMBINING CIRCUMFLEX ACCENT
    }

    @Test func chartWordAccentAndGroupMarksUseExactCodePoints() throws {
        let layout = try bundledLayout(named: "IPA — Chart")
        let texts = insertTexts(in: layout)
        let required: [(String, String)] = [
            ("\u{A71C}", "downstep ꜜ"),
            ("\u{A71B}", "upstep ꜛ"),
            ("\u{2197}", "global rise ↗"),
            ("\u{2198}", "global fall ↘"),
            ("\u{2016}", "major group mark ‖"),
        ]
        for (text, what) in required {
            #expect(texts.contains(text), "chart layout should insert \(what)")
        }

        // The major group mark ‖ U+2016 must not be confused with the
        // alveolar lateral click ǁ U+01C1 — both are on this layout and they
        // are distinct code points (and ASCII '|' appears nowhere).
        #expect(texts.contains("\u{01C1}"))
        #expect("\u{2016}" != "\u{01C1}")
        #expect(!texts.contains("|"))
        #expect(!texts.contains("\u{2193}"), "downstep must be ꜜ U+A71C, not the arrow ↓ U+2193")
        #expect(!texts.contains("\u{2191}"), "upstep must be ꜛ U+A71B, not the arrow ↑ U+2191")
    }

    // MARK: Grapheme behavior of the tone marks
    //
    // The combining tone diacritics' cluster-deletion behavior is asserted
    // per mark by GraphemeTextTests.basePlusOneCombiningMarkDeletesAsOneCluster;
    // only the spacing-letter contrast stays here.

    @Test func toneBarsAreSpacingLettersDeletedOneAtATime() {
        // Chao tone letters are spacing characters: a contour like ˩˥ is two
        // clusters, so backspace peels off one bar per press.
        let contour = "\u{02E9}\u{02E5}"
        #expect(contour.count == 2)
        #expect(GraphemeText.deletionScalarCount(before: contour) == 1)
    }
}
