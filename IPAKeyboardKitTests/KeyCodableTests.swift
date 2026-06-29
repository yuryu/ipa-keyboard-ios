//
//  KeyCodableTests.swift
//  IPAKeyboardKitTests
//
//  Verifies Key Codable behaviour: defaults applied when optional fields are
//  absent from JSON, id auto-generation on decode, full round-trips, and
//  the displayLabel / isSpacer convenience API.
//

import Foundation
import Testing
@testable import IPAKeyboardKit

struct KeyCodableTests {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: Defaults applied on decode

    @Test func terseJSONAppliesAllDefaults() throws {
        // Only the required `action` field present; every optional must
        // resolve to its documented default value.
        let json = #"{"action":{"type":"insert","text":"p"}}"#
        let key = try decoder.decode(Key.self, from: Data(json.utf8))
        #expect(key.label == nil)
        #expect(key.accessibilityLabel == nil)
        #expect(key.alternates.isEmpty)
        #expect(key.widthFactor == 1.0)
    }

    @Test func idIsGeneratedWhenOmittedFromJSON() throws {
        // Two identical terse JSON strings must each decode to a distinct UUID.
        let json = #"{"action":{"type":"insert","text":"ə"}}"#
        let key1 = try decoder.decode(Key.self, from: Data(json.utf8))
        let key2 = try decoder.decode(Key.self, from: Data(json.utf8))
        #expect(key1.id != key2.id)
    }

    @Test func idIsPreservedWhenPresentInJSON() throws {
        let fixedID = UUID()
        let json = #"{"id":"\#(fixedID.uuidString)","action":{"type":"backspace"}}"#
        let key = try decoder.decode(Key.self, from: Data(json.utf8))
        #expect(key.id == fixedID)
    }

    // MARK: Optional fields

    @Test func labelAndAccessibilityLabelArePreserved() throws {
        let json = """
        {
          "action": {"type":"insert","text":"ɑ"},
          "label": "ɑ",
          "accessibilityLabel": "open back unrounded vowel"
        }
        """
        let key = try decoder.decode(Key.self, from: Data(json.utf8))
        #expect(key.label == "ɑ")
        #expect(key.accessibilityLabel == "open back unrounded vowel")
    }

    @Test func widthFactorIsPreserved() throws {
        let json = #"{"action":{"type":"space"},"widthFactor":3.0}"#
        let key = try decoder.decode(Key.self, from: Data(json.utf8))
        #expect(key.widthFactor == 3.0)
    }

    @Test func alternatesRoundTripWithTheirOwnDefaults() throws {
        let key = Key(
            action: .insert("ɹ"),
            alternates: [Key(action: .insert("r"), accessibilityLabel: "alveolar trill")]
        )
        let data = try encoder.encode(key)
        let decoded = try decoder.decode(Key.self, from: data)
        #expect(decoded.alternates.count == 1)
        let alt = try #require(decoded.alternates.first)
        #expect(alt.action == .insert("r"))
        #expect(alt.accessibilityLabel == "alveolar trill")
        // The alternate itself has default widthFactor and no explicit label.
        #expect(alt.widthFactor == 1.0)
        #expect(alt.label == nil)
    }

    // MARK: Full round-trip

    @Test func fullKeyRoundTrips() throws {
        let id = UUID()
        let original = Key(
            id: id,
            action: .insert("ə"),
            label: "ə",
            accessibilityLabel: "schwa",
            alternates: [Key(action: .insert("ɚ"))],
            widthFactor: 1.5
        )
        let decoded = try decoder.decode(Key.self, from: try encoder.encode(original))
        #expect(decoded.id == id)
        #expect(decoded.action == .insert("ə"))
        #expect(decoded.label == "ə")
        #expect(decoded.accessibilityLabel == "schwa")
        #expect(decoded.alternates.count == 1)
        #expect(decoded.alternates.first?.action == .insert("ɚ"))
        #expect(decoded.widthFactor == 1.5)
    }

    // MARK: displayLabel

    @Test func displayLabelFallsBackToInsertedText() {
        let key = Key(action: .insert("ə"))
        #expect(key.displayLabel == "ə")
    }

    @Test func displayLabelPrefersExplicitLabelOverInsertedText() {
        let key = Key(action: .insert("ə"), label: "schwa")
        #expect(key.displayLabel == "schwa")
    }

    @Test func displayLabelIsEmptyForNonInsertActionsWithNoExplicitLabel() {
        // backspace, space etc. have no natural glyph — displayLabel returns "".
        #expect(Key(action: .backspace).displayLabel == "")
        #expect(Key(action: .space).displayLabel == "")
        #expect(Key(action: .nextKeyboard).displayLabel == "")
    }

    @Test func displayLabelReturnsExplicitLabelEvenForNonInsertAction() {
        let key = Key(action: .backspace, label: "⌫")
        #expect(key.displayLabel == "⌫")
    }

    // MARK: isSpacer

    @Test func isSpacerTrueForKeySpacerStaticFactory() {
        #expect(Key.spacer.isSpacer)
    }

    @Test func isSpacerFalseForInsertKey() {
        #expect(!Key(action: .insert("p")).isSpacer)
    }

    @Test func isSpacerFalseForBackspaceKey() {
        #expect(!Key(action: .backspace).isSpacer)
    }

    // MARK: Convenience factory

    @Test func insertFactoryProducesInsertAction() {
        let key = Key.insert("i")
        #expect(key.action == .insert("i"))
    }

    @Test func insertFactoryPropagatesAlternates() {
        let alt = Key(action: .insert("ɪ"))
        let key = Key.insert("i", alternates: [alt])
        #expect(key.alternates.count == 1)
        #expect(key.alternates.first?.action == .insert("ɪ"))
    }
}
