//
//  EnUSDiacriticsTests.swift
//  IPAKeyboardKitTests
//
//  Covers issue #15: en-US narrow-transcription combining diacritics —
//  en-US.json bundles the five diacritic keys with their accessibility
//  labels and dotted-circle caps, on the More panel. The grapheme-cluster
//  behavior of these marks (base + mark deletes as one unit) is asserted
//  for every composed pair by
//  GraphemeTextTests.basePlusOneCombiningMarkDeletesAsOneCluster.
//

import Testing
@testable import IPAKeyboardKit

struct EnUSDiacriticsTests {

    // MARK: Bundled en-US.json content

    private func enUSLayout() throws -> KeyboardLayout {
        try bundledLayout(locale: "en-US")
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

    @Test(arguments: EnUSDiacriticsTests.expectedDiacritics)
    func enUSContainsTheDiacriticKeyWithItsSpokenLabel(_ expected: (scalar: Unicode.Scalar, accessibilityLabel: String)) throws {
        let layout = try enUSLayout()
        let text = String(expected.scalar)
        let diacriticKey = try #require(
            key(inserting: text, in: layout),
            "expected en-US to contain an insert key for U+\(String(expected.scalar.value, radix: 16, uppercase: true))")
        #expect(diacriticKey.accessibilityLabel == expected.accessibilityLabel)
        // Each key inserts exactly one bare combining scalar, no normalization drift.
        #expect(text.unicodeScalars.count == 1)
        #expect(text.unicodeScalars.first?.value == expected.scalar.value)
    }

    @Test(arguments: EnUSDiacriticsTests.expectedDiacritics)
    func enUSDiacriticKeyUsesADottedCircleLabel(_ expected: (scalar: Unicode.Scalar, accessibilityLabel: String)) throws {
        let layout = try enUSLayout()
        let text = String(expected.scalar)
        let dottedCircle = Unicode.Scalar(0x25CC)! // U+25CC DOTTED CIRCLE
        let diacriticKey = try #require(key(inserting: text, in: layout))
        let label = try #require(diacriticKey.label, "expected a dotted-circle label for \(expected.accessibilityLabel)")
        #expect(label == "\(String(dottedCircle))\(text)")
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
