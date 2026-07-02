//
//  LayoutTransferTests.swift
//  IPAKeyboardKitTests
//
//  Import/export of layouts as files (issue #8): lossless export → import
//  round-trips with exact Unicode scalar preservation, v1 migration on
//  import, newer-schema rejection, malformed-input rejection, user-owned
//  identity on import (never isBuiltIn; fresh id on collision), export file
//  naming, and LayoutStore.importLayout's validate-before-persist ordering
//  (so decode errors surface even when the App Group container is nil).
//

import Foundation
import Testing
@testable import IPAKeyboardKit

struct LayoutTransferTests {

    // MARK: Fixtures

    /// A layout exercising the Unicode cases that must survive a round trip
    /// byte-for-byte: ɡ U+0261 (not ASCII g), ː U+02D0 (not colon), a
    /// combining-diacritic sequence e+U+0303 (not the precomposed ẽ U+1EBD),
    /// and a long-press alternate carrying U+02B0.
    private func makeUnicodeLayout(
        id: UUID = UUID(),
        isBuiltIn: Bool = false
    ) -> KeyboardLayout {
        KeyboardLayout(
            id: id,
            name: "Round Trip ɡː",
            locale: "en-US",
            isBuiltIn: isBuiltIn,
            rows: [
                KeyRow(keys: [
                    Key(
                        action: .insert("\u{0261}"),
                        accessibilityLabel: "voiced velar plosive",
                        alternates: [Key(action: .insert("p\u{02B0}"), accessibilityLabel: "aspirated p")]),
                    Key(action: .insert("\u{02D0}"), accessibilityLabel: "length mark"),
                    Key(action: .insert("e\u{0303}"), accessibilityLabel: "nasalized e"),
                    Key(action: .space, widthFactor: 3.0),
                ]),
            ])
    }

    /// The keys of the first (only) row of the round-trip fixture layout.
    private func firstRowKeys(of layout: KeyboardLayout) throws -> [Key] {
        let arrangement = try #require(layout.primaryArrangement)
        let panel = try #require(arrangement.primaryPanel)
        let row = try #require(panel.rows.first)
        return row.keys
    }

    private func insertedText(of key: Key) throws -> String {
        guard case .insert(let text) = key.action else {
            throw TestFailure.notAnInsertKey
        }
        return text
    }

    private enum TestFailure: Error { case notAnInsertKey }

    // MARK: Export → import round trip

    @Test func roundTripPreservesTheWholeDocument() throws {
        let original = makeUnicodeLayout()
        let data = try LayoutTransfer.exportData(for: original)
        let imported = try LayoutTransfer.importableLayout(from: data, existingIDs: [])

        // Key/row/arrangement ids are encoded, so full value equality is the
        // strongest possible losslessness check.
        #expect(imported == original)
    }

    @Test func roundTripPreservesExactUnicodeScalars() throws {
        let original = makeUnicodeLayout()
        let data = try LayoutTransfer.exportData(for: original)
        let imported = try LayoutTransfer.importableLayout(from: data, existingIDs: [])

        let keys = try firstRowKeys(of: imported)

        // ɡ must still be U+0261, never normalized to ASCII g (U+0067).
        let gText = try insertedText(of: keys[0])
        #expect(gText.unicodeScalars.map(\.value) == [0x0261])
        #expect(gText != "g")

        // ː must still be U+02D0, never a colon (U+003A).
        let lengthText = try insertedText(of: keys[1])
        #expect(lengthText.unicodeScalars.map(\.value) == [0x02D0])
        #expect(lengthText != ":")

        // The combining sequence must stay decomposed: e (U+0065) + combining
        // tilde (U+0303), not the precomposed ẽ (U+1EBD).
        let nasalText = try insertedText(of: keys[2])
        #expect(nasalText.unicodeScalars.map(\.value) == [0x0065, 0x0303])
        #expect(nasalText.unicodeScalars.map(\.value) != [0x1EBD])

        // The long-press alternate survives with its modifier letter intact.
        let alternate = try #require(keys[0].alternates.first)
        let alternateText = try insertedText(of: alternate)
        #expect(alternateText.unicodeScalars.map(\.value) == [0x0070, 0x02B0])
    }

    @Test func exportedJSONKeepsNonASCIIUnescaped() throws {
        // Guard against a regression to \uXXXX escaping: the exported UTF-8
        // bytes should contain the raw IPA glyphs.
        let data = try LayoutTransfer.exportData(for: makeUnicodeLayout())
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\u{0261}"))
        #expect(text.contains("\u{02D0}"))
        #expect(text.contains("Round Trip ɡː"))
    }

    // MARK: Imported identity

    @Test func importIsNeverBuiltIn() throws {
        let builtIn = makeUnicodeLayout(isBuiltIn: true)
        let data = try LayoutTransfer.exportData(for: builtIn)
        let imported = try LayoutTransfer.importableLayout(from: data, existingIDs: [])
        #expect(imported.isBuiltIn == false)
    }

    @Test func importPreservesIDWhenThereIsNoCollision() throws {
        let original = makeUnicodeLayout()
        let data = try LayoutTransfer.exportData(for: original)
        let imported = try LayoutTransfer.importableLayout(
            from: data, existingIDs: [UUID(), UUID()])
        #expect(imported.id == original.id)
    }

    @Test func importMintsFreshIDOnCollision() throws {
        let original = makeUnicodeLayout()
        let data = try LayoutTransfer.exportData(for: original)
        let imported = try LayoutTransfer.importableLayout(
            from: data, existingIDs: [original.id])

        #expect(imported.id != original.id)
        // Only the identity changes — content is untouched.
        #expect(imported.name == original.name)
        #expect(imported.locale == original.locale)
        #expect(imported.arrangements == original.arrangements)
    }

    // MARK: v1 migration on import

    @Test func importMigratesV1FlatRowsDocument() throws {
        let v1JSON = """
        {
          "schemaVersion": 1,
          "name": "Legacy",
          "locale": "en-US",
          "rows": [
            { "keys": [ { "action": { "type": "insert", "text": "ə" } } ] }
          ]
        }
        """
        let imported = try LayoutTransfer.importableLayout(
            from: Data(v1JSON.utf8), existingIDs: [])

        #expect(imported.schemaVersion == KeyboardLayout.currentSchemaVersion)
        #expect(imported.arrangements.count == 1)
        let keys = try firstRowKeys(of: imported)
        #expect(keys.count == 1)
        #expect(try insertedText(of: keys[0]) == "ə")
    }

    // MARK: Rejection

    @Test func importRejectsNewerSchemaVersion() throws {
        let newer = KeyboardLayout.currentSchemaVersion + 1
        let json = """
        {
          "schemaVersion": \(newer),
          "name": "From The Future",
          "locale": "und",
          "arrangements": []
        }
        """
        #expect(throws: LayoutImportError.unsupportedSchemaVersion(
            found: newer, supported: KeyboardLayout.currentSchemaVersion)
        ) {
            try LayoutTransfer.importableLayout(from: Data(json.utf8), existingIDs: [])
        }
    }

    @Test func importRejectsMalformedJSON() {
        #expect(throws: LayoutImportError.malformedDocument) {
            try LayoutTransfer.importableLayout(
                from: Data("{ this is not JSON".utf8), existingIDs: [])
        }
    }

    @Test func importRejectsValidJSONThatIsNotALayout() {
        #expect(throws: LayoutImportError.malformedDocument) {
            try LayoutTransfer.importableLayout(
                from: Data(#"{"hello": "world"}"#.utf8), existingIDs: [])
        }
    }

    @Test func importRejectsNonObjectTopLevelJSON() {
        #expect(throws: LayoutImportError.malformedDocument) {
            try LayoutTransfer.importableLayout(
                from: Data("[1, 2, 3]".utf8), existingIDs: [])
        }
    }

    @Test func importRejectsLayoutWithNoRowsOrArrangements() {
        // Valid JSON, correct version, but neither non-empty `arrangements`
        // nor `rows` — the decoder's blank-keyboard guard must reject it.
        let json = #"{"schemaVersion": 2, "name": "Empty", "locale": "und", "arrangements": []}"#
        #expect(throws: LayoutImportError.malformedDocument) {
            try LayoutTransfer.importableLayout(from: Data(json.utf8), existingIDs: [])
        }
    }

    // MARK: Export file name

    @Test func exportFileNameSanitizesSeparatorsAndKeepsUnicode() {
        let slashy = KeyboardLayout(
            name: "en/US: ɡː", locale: "en-US",
            rows: [KeyRow(keys: [.insert("ə")])])
        #expect(LayoutTransfer.exportFileName(for: slashy) == "en-US- ɡː.json")

        let plain = KeyboardLayout(
            name: "My Layout", locale: "und",
            rows: [KeyRow(keys: [.insert("ə")])])
        #expect(LayoutTransfer.exportFileName(for: plain) == "My Layout.json")
    }

    @Test func exportFileNameFallsBackForEmptyName() {
        let unnamed = KeyboardLayout(
            name: "", locale: "und",
            rows: [KeyRow(keys: [.insert("ə")])])
        #expect(LayoutTransfer.exportFileName(for: unnamed) == "Layout.json")
    }

    // MARK: LayoutStore.importLayout (persisting wrapper)

    @Test func storeImportValidatesBeforeTouchingTheContainer() {
        // Decode errors must win over the container check, so the user gets
        // "this file is bad", not "storage isn't set up", for bad input —
        // in every environment, provisioned or not.
        #expect(throws: LayoutImportError.malformedDocument) {
            try LayoutStore().importLayout(from: Data("not json".utf8))
        }
    }

    @Test func storeImportOfValidDataThrowsStoreErrorWhenContainerUnavailable() throws {
        guard AppGroup.containerURL == nil else {
            // App Group unexpectedly provisioned here; the degraded-state
            // path can't be exercised (same guard as LayoutStoreTests).
            return
        }
        let data = try LayoutTransfer.exportData(for: makeUnicodeLayout())
        #expect(throws: LayoutStore.StoreError.self) {
            try LayoutStore().importLayout(from: data)
        }
    }

    @Test func storeImportMintsFreshIDWhenDocumentIDMatchesABundledLayout() throws {
        // Exporting a built-in and re-importing it must produce a user copy,
        // not a document that collides with the bundled layout's pinned id.
        let store = LayoutStore()
        let bundled = try #require(store.bundledLayouts().first)
        let data = try LayoutTransfer.exportData(for: bundled)

        let imported = try LayoutTransfer.importableLayout(
            from: data,
            existingIDs: Set(store.allLayouts().map(\.id)))

        #expect(imported.id != bundled.id)
        #expect(imported.isBuiltIn == false)
        #expect(imported.arrangements == bundled.arrangements)
    }
}
