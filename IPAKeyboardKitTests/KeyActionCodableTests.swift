//
//  KeyActionCodableTests.swift
//  IPAKeyboardKitTests
//
//  Verifies every KeyAction case: Codable round-trips, exact JSON shape
//  (which fields are emitted and which are absent), and decoding from
//  hand-written JSON strings that match the documented format.
//
//  switchPanel and spacer round-trips are also exercised in SchemaV2Tests
//  in their schema-context; the tests here focus on the JSON shape contract.
//

import Foundation
import Testing
@testable import IPAKeyboardKit

struct KeyActionCodableTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: Round-trips — no-payload cases

    // backspace, space, nextKeyboard, spacer carry no associated value;
    // parameterise to avoid repetition. `return` is a Swift keyword and is
    // tested separately below to keep the array literal unambiguous.
    @Test(arguments: [
        KeyAction.backspace,
        KeyAction.space,
        KeyAction.nextKeyboard,
        KeyAction.spacer,
    ])
    func noPayloadActionRoundTrips(_ action: KeyAction) throws {
        let data = try encoder.encode(action)
        let decoded = try decoder.decode(KeyAction.self, from: data)
        #expect(decoded == action)
    }

    @Test func returnActionRoundTrips() throws {
        let data = try encoder.encode(KeyAction.return)
        let decoded = try decoder.decode(KeyAction.self, from: data)
        #expect(decoded == KeyAction.return)
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

    @Test func decodesInsertFromHandWrittenJSON() throws {
        let json = #"{"type":"insert","text":"p"}"#
        let action = try decoder.decode(KeyAction.self, from: Data(json.utf8))
        #expect(action == .insert("p"))
    }

    @Test func decodesBackspaceFromHandWrittenJSON() throws {
        let json = #"{"type":"backspace"}"#
        #expect(try decoder.decode(KeyAction.self, from: Data(json.utf8)) == .backspace)
    }

    @Test func decodesSpaceFromHandWrittenJSON() throws {
        let json = #"{"type":"space"}"#
        #expect(try decoder.decode(KeyAction.self, from: Data(json.utf8)) == .space)
    }

    @Test func decodesReturnFromHandWrittenJSON() throws {
        let json = #"{"type":"return"}"#
        #expect(try decoder.decode(KeyAction.self, from: Data(json.utf8)) == KeyAction.return)
    }

    @Test func decodesNextKeyboardFromHandWrittenJSON() throws {
        let json = #"{"type":"nextKeyboard"}"#
        #expect(try decoder.decode(KeyAction.self, from: Data(json.utf8)) == .nextKeyboard)
    }

    @Test func decodesSwitchPanelFromHandWrittenJSON() throws {
        let json = #"{"type":"switchPanel","target":"More"}"#
        #expect(try decoder.decode(KeyAction.self, from: Data(json.utf8)) == .switchPanel("More"))
    }

    @Test func decodesSpacerFromHandWrittenJSON() throws {
        let json = #"{"type":"spacer"}"#
        #expect(try decoder.decode(KeyAction.self, from: Data(json.utf8)) == .spacer)
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
