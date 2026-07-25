//
//  SchemaV2Tests.swift
//  IPAKeyboardKitTests
//
//  Covers the v2 schema (arrangements → panels) and the v1→v2 decode
//  migration. Bare KeyAction Codable behavior lives in
//  KeyActionCodableTests; copy-on-write forking in
//  ArrangementTests.KeyboardLayoutForkTests.
//

import Foundation
import Testing
@testable import IPAKeyboardKit

struct SchemaV2Tests {

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: Migration

    @Test func v1FlatRowsMigrateToSingleArrangementAndPanel() throws {
        let v1 = """
        {
          "schemaVersion": 1,
          "name": "Legacy",
          "locale": "en-US",
          "rows": [
            { "keys": [ { "action": { "type": "insert", "text": "ə" } } ] },
            { "keys": [ { "action": { "type": "backspace" } } ] }
          ]
        }
        """
        let layout = try decoder.decode(KeyboardLayout.self, from: Data(v1.utf8))

        #expect(layout.schemaVersion == KeyboardLayout.currentSchemaVersion)
        #expect(layout.arrangements.count == 1)
        let panel = try #require(layout.primaryArrangement?.primaryPanel)
        #expect(layout.primaryArrangement?.panels.count == 1)
        // A migrated v1 layout keeps its function keys inline — no shared bar.
        #expect(layout.primaryArrangement?.functionRow == nil)
        #expect(panel.rows.count == 2)
        #expect(panel.rows.first?.keys.first?.action == .insert("ə"))
    }

    @Test func newerSchemaVersionIsRejectedNotSilentlyDowngraded() {
        let future = """
        {
          "schemaVersion": 99,
          "name": "From the future",
          "locale": "en-US",
          "arrangements": []
        }
        """
        #expect(throws: DecodingError.self) {
            try decoder.decode(KeyboardLayout.self, from: Data(future.utf8))
        }
    }

    @Test func emptyArrangementsFallsBackToRowsMigration() throws {
        // A present-but-empty `arrangements` must not yield a blank keyboard;
        // it falls back to the legacy `rows`.
        let json = """
        {
          "schemaVersion": 2,
          "name": "Empty arrangements",
          "locale": "en-US",
          "arrangements": [],
          "rows": [ { "keys": [ { "action": { "type": "insert", "text": "i" } } ] } ]
        }
        """
        let layout = try decoder.decode(KeyboardLayout.self, from: Data(json.utf8))
        #expect(layout.primaryArrangement?.primaryPanel?.rows.first?.keys.first?.action == .insert("i"))
    }

    @Test func malformedLayoutWithNeitherArrangementsNorRowsThrows() {
        let json = """
        { "schemaVersion": 2, "name": "Nothing", "locale": "en-US" }
        """
        #expect(throws: DecodingError.self) {
            try decoder.decode(KeyboardLayout.self, from: Data(json.utf8))
        }
    }

    // MARK: v2 round-trip

    @Test func v2EncodesArrangementsAndRoundTrips() throws {
        let layout = KeyboardLayout(
            name: "Two panels",
            locale: "en-US",
            arrangements: [
                Arrangement(
                    name: "Split",
                    panels: [
                        Panel(name: "IPA",
                              switchKey: Key(action: .switchPanel("More"), label: "more"),
                              rows: [KeyRow(keys: [.insert("i"), .spacer, .insert("u")])]),
                        Panel(name: "More",
                              switchKey: Key(action: .switchPanel("IPA"), label: "IPA"),
                              rows: [KeyRow(keys: [.insert("ʔ")])]),
                    ],
                    functionRow: KeyRow(keys: [
                        Key(action: .nextKeyboard, label: "🌐"),
                        Key(action: .space, label: "space", widthFactor: 3.0),
                        Key(action: .backspace, label: "⌫", widthFactor: 1.5),
                    ]))
            ])

        let data = try encoder.encode(layout)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("arrangements"))
        #expect(json.contains("functionRow"))
        #expect(json.contains("switchKey"))

        let decoded = try decoder.decode(KeyboardLayout.self, from: data)
        #expect(decoded.arrangements == layout.arrangements)
        #expect(decoded.primaryArrangement?.functionRow?.keys.first?.action == .nextKeyboard)
        #expect(decoded.primaryArrangement?.primaryPanel?.switchKey?.action == .switchPanel("More"))
        #expect(decoded.primaryArrangement?.panel(named: "More")?.rows.first?.keys.first?.action == .insert("ʔ"))
        // The shared bar adds a row on top of the tallest panel's symbol rows.
        #expect(decoded.primaryArrangement?.totalRowCount == 2)
    }
}
