//
//  KeyActionCodableTests.swift
//  IPAKeyboardKitTests
//
//  Verifies every KeyAction case: Codable round-trips, exact JSON shape
//  (which fields are emitted and which are absent), and decoding from
//  hand-written JSON strings that match the documented format. This is the
//  canonical home for bare KeyAction Codable coverage; the schema-context
//  counterpart is SchemaV2Tests.v2EncodesArrangementsAndRoundTrips, which
//  round-trips the actions inside a whole layout document.
//

import Foundation
import Testing
@testable import IPAKeyboardKit

struct KeyActionCodableTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: Round-trips — no-payload cases

    // backspace, space, return, nextKeyboard, spacer carry no associated
    // value; parameterise to avoid repetition. (`return` is a Swift keyword
    // but the type-qualified spelling is unambiguous in the array literal.)
    @Test(arguments: [
        KeyAction.backspace,
        KeyAction.space,
        KeyAction.return,
        KeyAction.nextKeyboard,
        KeyAction.spacer,
    ])
    func noPayloadActionRoundTrips(_ action: KeyAction) throws {
        let data = try encoder.encode(action)
        let decoded = try decoder.decode(KeyAction.self, from: data)
        #expect(decoded == action)
    }

    // MARK: Round-trips — payload cases

    @Test func insertActionRoundTrips() throws {
        let action = KeyAction.insert("ə")
        let data = try encoder.encode(action)
        #expect(try decoder.decode(KeyAction.self, from: data) == action)
    }

    // MARK: JSON shape

    @Test func insertActionEmitsTypeAndTextField() throws {
        let data = try encoder.encode(KeyAction.insert("ɑ"))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"insert\""))
        #expect(json.contains("\"text\""))
        #expect(json.contains("\"ɑ\""))
    }

    @Test func backspaceActionHasNoTextField() throws {
        let data = try encoder.encode(KeyAction.backspace)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"backspace\""))
        #expect(!json.contains("\"text\""))
    }

    @Test func switchPanelActionEmitsTargetNotText() throws {
        let data = try encoder.encode(KeyAction.switchPanel("IPA"))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"switchPanel\""))
        #expect(json.contains("\"target\""))
        #expect(!json.contains("\"text\""))
    }

    @Test func spacerActionHasOnlyTypeField() throws {
        let data = try encoder.encode(KeyAction.spacer)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"spacer\""))
        #expect(!json.contains("\"text\""))
        #expect(!json.contains("\"target\""))
    }

    // MARK: Decoding from hand-written JSON

    // One case per action type, matching the documented hand-editable format;
    // per-argument reporting keeps failure locality per case.
    @Test(arguments: [
        (json: #"{"type":"insert","text":"p"}"#, expected: KeyAction.insert("p")),
        (json: #"{"type":"backspace"}"#, expected: KeyAction.backspace),
        (json: #"{"type":"space"}"#, expected: KeyAction.space),
        (json: #"{"type":"return"}"#, expected: KeyAction.return),
        (json: #"{"type":"nextKeyboard"}"#, expected: KeyAction.nextKeyboard),
        (json: #"{"type":"switchPanel","target":"More"}"#, expected: KeyAction.switchPanel("More")),
        (json: #"{"type":"spacer"}"#, expected: KeyAction.spacer),
    ])
    func decodesEveryActionFromHandWrittenJSON(_ testCase: (json: String, expected: KeyAction)) throws {
        let action = try decoder.decode(KeyAction.self, from: Data(testCase.json.utf8))
        #expect(action == testCase.expected)
    }

    // MARK: Error cases

    @Test func insertMissingTextFieldThrows() {
        let json = #"{"type":"insert"}"#
        #expect(throws: DecodingError.self) {
            try decoder.decode(KeyAction.self, from: Data(json.utf8))
        }
    }

    @Test func switchPanelMissingTargetFieldThrows() {
        let json = #"{"type":"switchPanel"}"#
        #expect(throws: DecodingError.self) {
            try decoder.decode(KeyAction.self, from: Data(json.utf8))
        }
    }

    @Test func unknownTypeThrowsDecodingError() {
        let json = #"{"type":"unknownAction"}"#
        #expect(throws: DecodingError.self) {
            try decoder.decode(KeyAction.self, from: Data(json.utf8))
        }
    }
}
