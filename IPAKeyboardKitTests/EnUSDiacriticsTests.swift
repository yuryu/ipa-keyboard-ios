//
//  EnUSDiacriticsTests.swift
//  IPAKeyboardKitTests
//
//  Covers issue #15: en-US narrow-transcription combining diacritics.
//  Verifies (1) base + combining mark forms one grapheme cluster and one
//  grapheme-aware backspace deletes the whole cluster, with exact scalars
//  asserted, and (2) en-US.json bundles the five diacritic keys with their
//  accessibility labels.
//

import Testing
@testable import IPAKeyboardKit

struct EnUSDiacriticsTests {

    // MARK: Grapheme-cluster behavior of the new marks

    @Test func nasalizedTildeCombinesWithBaseVowelAsOneCluster() {
        // æ (U+00E6) + combining tilde (U+0303), as in "man" [mæ̃n].
        let context = "æ\u{0303}"
        #expect(Array(context.unicodeScalars) == [Unicode.Scalar(0x00E6)!, Unicode.Scalar(0x0303)!])
        #expect(context.count == 1) // one user-perceived character
        #expect(GraphemeText.deletionScalarCount(before: context) == 2)
    }

    @Test func voicelessRingBelowCombinesWithApproximantAsOneCluster() {
        // l (U+006C) + combining ring below (U+0325), as in "play" [pl̥eɪ].
        let context = "l\u{0325}"
        #expect(Array(context.unicodeScalars) == [Unicode.Scalar(0x006C)!, Unicode.Scalar(0x0325)!])
        #expect(context.count == 1)
        #expect(GraphemeText.deletionScalarCount(before: context) == 2)
    }

    @Test func syllabicVerticalLineBelowCombinesWithNasalAsOneCluster() {
        // n (U+006E) + combining vertical line below (U+0329), as in "button" [ˈbʌʔn̩].
        let context = "n\u{0329}"
        #expect(Array(context.unicodeScalars) == [Unicode.Scalar(0x006E)!, Unicode.Scalar(0x0329)!])
        #expect(context.count == 1)
        #expect(GraphemeText.deletionScalarCount(before: context) == 2)
    }

    @Test func dentalBridgeBelowCombinesWithAlveolarAsOneCluster() {
        // t (U+0074) + combining bridge below (U+032A), as in "tenth" [tɛn̪θ].
        let context = "t\u{032A}"
        #expect(Array(context.unicodeScalars) == [Unicode.Scalar(0x0074)!, Unicode.Scalar(0x032A)!])
        #expect(context.count == 1)
        #expect(GraphemeText.deletionScalarCount(before: context) == 2)
    }

    @Test func noAudibleReleaseCombinesWithStopAsOneCluster() {
        // t (U+0074) + combining left angle above (U+031A), as in "cat" [kæt̚].
        let context = "t\u{031A}"
        #expect(Array(context.unicodeScalars) == [Unicode.Scalar(0x0074)!, Unicode.Scalar(0x031A)!])
        #expect(context.count == 1)
        #expect(GraphemeText.deletionScalarCount(before: context) == 2)
    }

    @Test func fullWordWithTrailingDiacriticDeletesOnlyTheLastCluster() {
        // Deleting from the end of "n̩" leaves just the preceding text, i.e. one
        // backspace removes the whole two-scalar cluster, not just the mark.
        let word = "bʌʔn\u{0329}"
        #expect(GraphemeText.deletionScalarCount(before: word) == 2)
    }

    // MARK: Bundled en-US.json content

    private func enUSLayout() throws -> KeyboardLayout {
        let layouts = LayoutStore().bundledLayouts()
        return try #require(layouts.first { $0.locale == "en-US" })
    }

    /// The five combining marks this issue adds, in the order the row
    /// declares them, alongside their expected spoken accessibility labels.
    private static let expectedDiacritics: [(scalar: Unicode.Scalar, accessibilityLabel: String)] = [
        (Unicode.Scalar(0x0303)!, "nasalized"),
        (Unicode.Scalar(0x0325)!, "voiceless"),
        (Unicode.Scalar(0x0329)!, "syllabic"),
        (Unicode.Scalar(0x032A)!, "dental"),
        (Unicode.Scalar(0x031A)!, "no audible release"),
    ]

    @Test func enUSDecodesAndContainsTheFiveDiacriticKeys() throws {
        let layout = try enUSLayout()
        let panels = layout.arrangements.flatMap(\.panels)
        let allKeys = panels.flatMap(\.rows).flatMap(\.keys)

        for expected in Self.expectedDiacritics {
            let text = String(expected.scalar)
            let key = try #require(
                allKeys.first { key in
                    if case .insert(let insertedText) = key.action { return insertedText == text }
                    return false
                },
                "expected en-US to contain an insert key for U+\(String(expected.scalar.value, radix: 16, uppercase: true))")
            #expect(key.accessibilityLabel == expected.accessibilityLabel)
            // Each key inserts exactly one bare combining scalar, no normalization drift.
            #expect(text.unicodeScalars.count == 1)
            #expect(text.unicodeScalars.first?.value == expected.scalar.value)
        }
    }

    @Test func enUSDiacriticKeysUseDottedCircleLabels() throws {
        let layout = try enUSLayout()
        let panels = layout.arrangements.flatMap(\.panels)
        let allKeys = panels.flatMap(\.rows).flatMap(\.keys)
        let dottedCircle = Unicode.Scalar(0x25CC)! // U+25CC DOTTED CIRCLE

        for expected in Self.expectedDiacritics {
            let text = String(expected.scalar)
            let key = try #require(allKeys.first { key in
                if case .insert(let insertedText) = key.action { return insertedText == text }
                return false
            })
            let label = try #require(key.label, "expected a dotted-circle label for \(expected.accessibilityLabel)")
            #expect(label == "\(String(dottedCircle))\(text)")
        }
    }

    @Test func enUSDiacriticsRowSitsInTheMorePanel() throws {
        let layout = try enUSLayout()
        let arrangement = try #require(layout.primaryArrangement)
        let morePanel = try #require(arrangement.panels.first { $0.name != arrangement.primaryPanel?.name })

        let diacriticTexts = Set(Self.expectedDiacritics.map { String($0.scalar) })
        let morePanelInsertTexts = Set(morePanel.rows.flatMap(\.keys).compactMap { key -> String? in
            if case .insert(let text) = key.action { return text }
            return nil
        })
        #expect(diacriticTexts.isSubset(of: morePanelInsertTexts))
    }
}
