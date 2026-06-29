//
//  ArrangementTests.swift
//  IPAKeyboardKitTests
//
//  Tests Arrangement.totalRowCount / maxRowCount / panel(named:) / primaryPanel,
//  the KeyboardLayout(rows:) convenience init, KeyboardLayout.makeEditableCopy,
//  and KeyboardLayout.filteringKeys.
//

import Foundation
import Testing
@testable import IPAKeyboardKit

// MARK: - Helper factories

private func row(_ actions: KeyAction...) -> KeyRow {
    KeyRow(keys: actions.map { Key(action: $0) })
}

// MARK: - Arrangement geometry

struct ArrangementGeometryTests {

    @Test func totalRowCountEqualsPanelRowsPlusFunctionRow() {
        let arrangement = Arrangement(
            name: "Split",
            panels: [Panel(name: "IPA", rows: [row(.insert("p")), row(.insert("b"))])],
            functionRow: row(.backspace)
        )
        // 2 symbol rows + 1 function row
        #expect(arrangement.maxRowCount == 2)
        #expect(arrangement.totalRowCount == 3)
    }

    @Test func totalRowCountWithNoFunctionRowEqualsSymbolRows() {
        let arrangement = Arrangement(
            name: "Default",
            panels: [Panel(name: "Main", rows: [row(.insert("p")), row(.insert("b"))])],
            functionRow: nil
        )
        #expect(arrangement.totalRowCount == 2)
    }

    @Test func totalRowCountUsesMaxAcrossPanels() {
        // IPA panel: 2 rows, More panel: 1 row → max = 2
        let arrangement = Arrangement(
            name: "Split",
            panels: [
                Panel(name: "IPA", rows: [row(.insert("p")), row(.insert("b"))]),
                // ː U+02D0 long vowel mark, not a colon
                Panel(name: "More", rows: [row(.insert("ː"))]),
            ],
            functionRow: row(.backspace)
        )
        #expect(arrangement.maxRowCount == 2)
        #expect(arrangement.totalRowCount == 3)   // 2 symbol + 1 function
    }

    @Test func totalRowCountOfEmptyArrangementIsZero() {
        let arrangement = Arrangement(name: "Empty", panels: [], functionRow: nil)
        #expect(arrangement.maxRowCount == 0)
        #expect(arrangement.totalRowCount == 0)
    }

    @Test func totalRowCountEmptyPanelsWithFunctionRowIsOne() {
        let arrangement = Arrangement(
            name: "Minimal",
            panels: [Panel(name: "Main", rows: [])],
            functionRow: row(.nextKeyboard)
        )
        // max symbol rows = 0, function row = 1 → total = 1
        #expect(arrangement.maxRowCount == 0)
        #expect(arrangement.totalRowCount == 1)
    }

    // MARK: panel(named:)

    @Test func panelNamedReturnsPanelByName() {
        let arrangement = Arrangement(
            name: "Split",
            panels: [Panel(name: "IPA", rows: []), Panel(name: "More", rows: [])]
        )
        #expect(arrangement.panel(named: "More")?.name == "More")
        #expect(arrangement.panel(named: "IPA")?.name == "IPA")
    }

    @Test func panelNamedNilReturnsPrimaryPanel() {
        let arrangement = Arrangement(
            name: "Split",
            panels: [Panel(name: "IPA", rows: []), Panel(name: "More", rows: [])]
        )
        #expect(arrangement.panel(named: nil)?.name == "IPA")
    }

    @Test func panelNamedUnknownFallsBackToPrimaryPanel() {
        let arrangement = Arrangement(
            name: "Split",
            panels: [Panel(name: "IPA", rows: []), Panel(name: "More", rows: [])]
        )
        #expect(arrangement.panel(named: "Nonexistent")?.name == "IPA")
    }

    @Test func primaryPanelIsFirstPanel() {
        let arrangement = Arrangement(
            name: "Split",
            panels: [Panel(name: "IPA", rows: []), Panel(name: "More", rows: [])]
        )
        #expect(arrangement.primaryPanel?.name == "IPA")
    }

    @Test func primaryPanelIsNilForEmptyPanelList() {
        let arrangement = Arrangement(name: "Empty", panels: [])
        #expect(arrangement.primaryPanel == nil)
    }
}

// MARK: - KeyboardLayout(rows:) convenience init

struct KeyboardLayoutRowsInitTests {

    @Test func rowsInitProducesExactlyOneArrangementAndOnePanel() {
        let layout = KeyboardLayout(
            name: "Test", locale: "en-US",
            rows: [row(.insert("p")), row(.insert("ə"))]
        )
        #expect(layout.arrangements.count == 1)
        #expect(layout.primaryArrangement?.panels.count == 1)
    }

    @Test func rowsInitPreservesAllRows() {
        let layout = KeyboardLayout(
            name: "Test", locale: "en-US",
            rows: [row(.insert("p")), row(.insert("b")), row(.insert("ə"))]
        )
        #expect(layout.primaryArrangement?.primaryPanel?.rows.count == 3)
    }

    @Test func rowsInitArrangementIsNamedDefault() {
        let layout = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("p"))])
        #expect(layout.primaryArrangement?.name == "Default")
    }

    @Test func rowsInitPanelIsNamedMain() {
        let layout = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("p"))])
        #expect(layout.primaryArrangement?.primaryPanel?.name == "Main")
    }

    @Test func rowsInitHasNoFunctionRow() {
        // A convenience-init layout keeps function keys inline; no shared bar.
        let layout = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.nextKeyboard)])
        #expect(layout.primaryArrangement?.functionRow == nil)
    }

    @Test func rowsInitSchemaVersionIsCurrentVersion() {
        let layout = KeyboardLayout(name: "Test", locale: "en-US", rows: [])
        #expect(layout.schemaVersion == KeyboardLayout.currentSchemaVersion)
    }
}

// MARK: - makeEditableCopy

struct KeyboardLayoutForkTests {

    private func makeBuiltIn() -> KeyboardLayout {
        KeyboardLayout(
            name: "Source",
            locale: "en-US",
            isBuiltIn: true,
            arrangements: [
                Arrangement(
                    name: "Split",
                    panels: [Panel(name: "IPA", rows: [row(.insert("p"))])],
                    functionRow: row(.backspace)
                )
            ]
        )
    }

    @Test func makeEditableCopyProducesNewID() {
        let source = makeBuiltIn()
        let copy = source.makeEditableCopy()
        #expect(copy.id != source.id)
    }

    @Test func makeEditableCopyIsNotBuiltIn() {
        let copy = makeBuiltIn().makeEditableCopy()
        #expect(copy.isBuiltIn == false)
    }

    @Test func makeEditableCopyRecordsDerivedFromSourceID() {
        let source = makeBuiltIn()
        let copy = source.makeEditableCopy()
        #expect(copy.derivedFrom == source.id)
    }

    @Test func makeEditableCopyArrangementsEqualSource() {
        let source = makeBuiltIn()
        let copy = source.makeEditableCopy()
        #expect(copy.arrangements == source.arrangements)
    }

    @Test func makeEditableCopyDoesNotMutateSource() {
        let source = makeBuiltIn()
        let sourceName = source.name
        _ = source.makeEditableCopy()
        #expect(source.name == sourceName)
        #expect(source.isBuiltIn == true)
    }

    @Test func makeEditableCopyUsesDefaultNameWhenNilPassed() {
        let source = makeBuiltIn()
        let copy = source.makeEditableCopy()
        #expect(copy.name == "\(source.name) (Custom)")
    }

    @Test func makeEditableCopyNamedParameterOverridesDefaultName() {
        let copy = makeBuiltIn().makeEditableCopy(named: "My Custom Layout")
        #expect(copy.name == "My Custom Layout")
    }

    @Test func makeEditableCopyPreservesLocale() {
        let copy = makeBuiltIn().makeEditableCopy()
        #expect(copy.locale == "en-US")
    }
}

// MARK: - filteringKeys

struct KeyboardLayoutFilteringTests {

    @Test func filteringKeysRemovesMatchingKeysFromSymbolRows() {
        let layout = KeyboardLayout(
            name: "Test", locale: "en-US",
            rows: [KeyRow(keys: [Key(action: .nextKeyboard), Key(action: .insert("p"))])]
        )
        let filtered = layout.filteringKeys { $0.action == .nextKeyboard }
        let firstRow = filtered.primaryArrangement?.primaryPanel?.rows.first
        #expect(firstRow?.keys.count == 1)
        #expect(firstRow?.keys.first?.action == .insert("p"))
    }

    @Test func filteringKeysRemovesMatchingKeysFromFunctionRow() {
        let layout = KeyboardLayout(
            name: "Test", locale: "en-US",
            arrangements: [
                Arrangement(
                    name: "Split",
                    panels: [Panel(name: "IPA", rows: [row(.insert("p"))])],
                    functionRow: KeyRow(keys: [
                        Key(action: .nextKeyboard),
                        Key(action: .backspace),
                    ])
                )
            ]
        )
        let filtered = layout.filteringKeys { $0.action == .nextKeyboard }
        let functionRow = filtered.primaryArrangement?.functionRow
        #expect(functionRow?.keys.count == 1)
        #expect(functionRow?.keys.first?.action == .backspace)
    }

    @Test func filteringKeysNilsSwitchKeyWhenMatched() {
        let layout = KeyboardLayout(
            name: "Test", locale: "en-US",
            arrangements: [
                Arrangement(
                    name: "Split",
                    panels: [
                        Panel(
                            name: "IPA",
                            switchKey: Key(action: .switchPanel("More")),
                            rows: [row(.insert("p"))]
                        )
                    ]
                )
            ]
        )
        let filtered = layout.filteringKeys { key in
            if case .switchPanel = key.action { return true }
            return false
        }
        #expect(filtered.primaryArrangement?.primaryPanel?.switchKey == nil)
    }

    @Test func filteringKeysDoesNotMutateSource() {
        let layout = KeyboardLayout(
            name: "Test", locale: "en-US",
            rows: [KeyRow(keys: [Key(action: .nextKeyboard), Key(action: .insert("p"))])]
        )
        _ = layout.filteringKeys { $0.action == .nextKeyboard }
        // The original layout is a value type; the source row is unchanged.
        #expect(layout.primaryArrangement?.primaryPanel?.rows.first?.keys.count == 2)
    }

    @Test func filteringKeysWithNoMatchPreservesAllKeys() {
        let layout = KeyboardLayout(
            name: "Test", locale: "en-US",
            rows: [KeyRow(keys: [Key(action: .insert("p")), Key(action: .insert("b"))])]
        )
        let filtered = layout.filteringKeys { _ in false }
        #expect(filtered.primaryArrangement?.primaryPanel?.rows.first?.keys.count == 2)
    }
}
