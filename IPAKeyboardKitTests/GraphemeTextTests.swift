//
//  GraphemeTextTests.swift
//  IPAKeyboardKitTests
//
//  Verifies grapheme-cluster-aware deletion counts so one backspace removes
//  one user-perceived character even when it spans several Unicode scalars.
//

import Testing
@testable import IPAKeyboardKit

struct GraphemeTextTests {

    @Test func emptyContextDeletesNothing() {
        #expect(GraphemeText.deletionScalarCount(before: "") == 0)
    }

    @Test func asciiDeletesOneScalar() {
        #expect(GraphemeText.deletionScalarCount(before: "abc") == 1)
    }

    @Test func plainIPAGlyphDeletesOneScalar() {
        // ə U+0259 is a single scalar.
        #expect(GraphemeText.deletionScalarCount(before: "ðə") == 1)
    }

    /// Canonical cluster-deletion contract for base + one combining mark
    /// (issue #186): grapheme segmentation doesn't branch on which combining
    /// mark follows the base, so every pair the bundled layouts compose is
    /// asserted here once — exact scalars, one user-perceived character,
    /// deleted as a unit — instead of per-layout copies.
    private static let combiningPairs: [(base: Unicode.Scalar, mark: Unicode.Scalar)] = [
        // Combining tone diacritics of the generic layouts (issue #29).
        (Unicode.Scalar(0x0065)!, Unicode.Scalar(0x0300)!), // e + grave (low tone)
        (Unicode.Scalar(0x0065)!, Unicode.Scalar(0x0301)!), // e + acute (high tone)
        (Unicode.Scalar(0x0065)!, Unicode.Scalar(0x0302)!), // e + circumflex (falling)
        (Unicode.Scalar(0x0065)!, Unicode.Scalar(0x0304)!), // e + macron (mid tone)
        (Unicode.Scalar(0x0065)!, Unicode.Scalar(0x030B)!), // e + double acute (extra-high)
        (Unicode.Scalar(0x0065)!, Unicode.Scalar(0x030C)!), // e + caron (rising)
        (Unicode.Scalar(0x0065)!, Unicode.Scalar(0x030F)!), // e + double grave (extra-low)
        // en-US narrow-transcription diacritics (issue #15).
        (Unicode.Scalar(0x00E6)!, Unicode.Scalar(0x0303)!), // æ + nasalized tilde, [mæ̃n]
        (Unicode.Scalar(0x006C)!, Unicode.Scalar(0x0325)!), // l + voiceless ring below, [pl̥eɪ]
        (Unicode.Scalar(0x006E)!, Unicode.Scalar(0x0329)!), // n + syllabic line below, [ˈbʌʔn̩]
        (Unicode.Scalar(0x0074)!, Unicode.Scalar(0x032A)!), // t + dental bridge below, [tɛn̪θ]
        (Unicode.Scalar(0x0074)!, Unicode.Scalar(0x031A)!), // t + no-audible-release, [kæt̚]
        // ja-JP devoicing and pitch accent (issue #75).
        (Unicode.Scalar(0x026F)!, Unicode.Scalar(0x0325)!), // ɯ + ring below, [sɯ̥ki]
        (Unicode.Scalar(0x0061)!, Unicode.Scalar(0x0301)!), // a + acute, [háɕi] "chopsticks"
    ]

    @Test(arguments: GraphemeTextTests.combiningPairs)
    func basePlusOneCombiningMarkDeletesAsOneCluster(_ pair: (base: Unicode.Scalar, mark: Unicode.Scalar)) {
        let context = String(pair.base) + String(pair.mark)
        #expect(Array(context.unicodeScalars) == [pair.base, pair.mark])
        #expect(context.count == 1) // one user-perceived character
        #expect(GraphemeText.deletionScalarCount(before: context) == 2)
    }

    @Test func multiScalarEmojiDeletesAsOneCluster() {
        // Family emoji built from several scalars joined by ZWJ.
        let family = "👨‍👩‍👧‍👦"
        #expect(family.count == 1)
        #expect(GraphemeText.deletionScalarCount(before: "hi \(family)") == family.unicodeScalars.count)
    }

    @Test func autorepeatTicksDeleteSyllabicConsonantClusterOneAtATime() {
        // Simulate holding backspace over "bɪtn̩" ("bitten" in IPA, ending in
        // a syllabic n formed from "n" + combining vertical line below
        // U+0329). Each autorepeat tick must remove exactly one
        // user-perceived character, and the two-scalar syllabic cluster must
        // come off in a single tick rather than leaving a bare diacritic.
        var context = "bɪtn\u{0329}"
        #expect(context.count == 4)

        var scalarCountsPerTick: [Int] = []
        while !context.isEmpty {
            let before = context.count
            let n = GraphemeText.deletionScalarCount(before: context)
            scalarCountsPerTick.append(n)
            var scalars = Array(context.unicodeScalars)
            scalars.removeLast(n)
            context = String(String.UnicodeScalarView(scalars))
            #expect(context.count == before - 1)
        }

        // Four ticks for four graphemes; the first tick removes the
        // two-scalar syllabic n from the end, the rest are single scalars.
        #expect(scalarCountsPerTick == [2, 1, 1, 1])
    }

    @Test func autorepeatTicksDeleteOneClusterEach() {
        // Backspace autorepeat emits one `.backspace` per tick; the extension
        // turns each into `deletionScalarCount` scalar deletions. Simulate
        // that loop over "pə̃t" — p, then ə U+0259 + combining tilde U+0303
        // (one grapheme, two scalars: a nasalized schwa), then t — and verify
        // every tick removes exactly one user-perceived character.
        var context = "pə\u{0303}t"
        #expect(context.count == 3)

        var scalarCountsPerTick: [Int] = []
        while !context.isEmpty {
            let before = context.count
            let n = GraphemeText.deletionScalarCount(before: context)
            scalarCountsPerTick.append(n)
            var scalars = Array(context.unicodeScalars)
            scalars.removeLast(n)
            context = String(String.UnicodeScalarView(scalars))
            #expect(context.count == before - 1)
        }

        // Three ticks for three graphemes; the middle one spans two scalars.
        #expect(scalarCountsPerTick == [1, 2, 1])
    }
}
