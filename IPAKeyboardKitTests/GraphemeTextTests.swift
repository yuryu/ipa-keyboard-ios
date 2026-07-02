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

    @Test func basePlusCombiningDiacriticDeletesAsOneCluster() {
        // "e" + combining acute accent U+0301 is one grapheme, two scalars.
        let context = "e\u{0301}"
        #expect(context.count == 1) // one user-perceived character
        #expect(GraphemeText.deletionScalarCount(before: context) == 2)
    }

    @Test func multiScalarEmojiDeletesAsOneCluster() {
        // Family emoji built from several scalars joined by ZWJ.
        let family = "👨‍👩‍👧‍👦"
        #expect(family.count == 1)
        #expect(GraphemeText.deletionScalarCount(before: "hi \(family)") == family.unicodeScalars.count)
    }

    @Test func syllabicConsonantDiacriticDeletesAsOneCluster() {
        // "n" + combining vertical line below U+0329 marks a syllabic
        // consonant (IPA syllabic n, "n̩") — one grapheme, two scalars.
        let context = "n\u{0329}"
        #expect(context.count == 1)
        #expect(GraphemeText.deletionScalarCount(before: context) == 2)
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
