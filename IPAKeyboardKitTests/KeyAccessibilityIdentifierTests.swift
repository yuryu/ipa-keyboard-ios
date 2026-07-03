//
//  KeyAccessibilityIdentifierTests.swift
//  IPAKeyboardKitTests
//
//  Pins the per-key accessibility-identifier scheme rendered by KeyboardView
//  (issue #25). The exact strings are load-bearing: IPAKeyboardUITests
//  hard-codes them (e.g. `previewKey(inserting:)` builds "key-insert-<text>"),
//  so any drift here silently breaks preview assertions in the UI suite.
//

import Foundation
import Testing
@testable import IPAKeyboardKit

struct KeyAccessibilityIdentifierTests {

    @Test func insertUsesExactInsertedText() {
        // Exact IPA code points, not the display label: ə U+0259.
        #expect(Key.insert("ə").accessibilityIdentifier == "key-insert-ə")
        // Multi-scalar inserted text is carried verbatim (q U+0071 + ʰ U+02B0).
        #expect(Key.insert("q\u{02B0}").accessibilityIdentifier == "key-insert-q\u{02B0}")
    }

    @Test func insertIgnoresDisplayLabelAndAccessibilityLabel() {
        // The identifier keys off what the key *types*, so relabeling a key
        // (display or spoken) never changes how tests address it.
        let key = Key(
            action: .insert("ɡ"), // U+0261, not ASCII g
            label: "g (voiced velar)",
            accessibilityLabel: "voiced velar plosive")
        #expect(key.accessibilityIdentifier == "key-insert-ɡ")
    }

    @Test func functionKeysUseFixedNames() {
        #expect(Key(action: .backspace).accessibilityIdentifier == "key-backspace")
        #expect(Key(action: .space).accessibilityIdentifier == "key-space")
        #expect(Key(action: .return).accessibilityIdentifier == "key-return")
        #expect(Key(action: .nextKeyboard).accessibilityIdentifier == "key-nextKeyboard")
    }

    @Test func switchPanelCarriesTargetName() {
        #expect(
            Key(action: .switchPanel("More")).accessibilityIdentifier == "key-switchPanel-More")
    }

    @Test func spacerHasTotalityValueOnly() {
        // Never rendered as an accessibility element; defined for totality.
        #expect(Key.spacer.accessibilityIdentifier == "key-spacer")
    }
}
