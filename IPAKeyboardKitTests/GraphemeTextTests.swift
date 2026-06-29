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
}
