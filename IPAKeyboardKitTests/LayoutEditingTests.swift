//
//  LayoutEditingTests.swift
//  IPAKeyboardKitTests
//
//  Covers the key-level editing engine in LayoutEditing.swift: PanelPath
//  addressing, the lookup helpers, insert/append/remove/move for both rows
//  and keys, replaceKey field updates, resettingContent(from:), exact-Unicode
//  round-trips through Codable after edits, and value semantics — editing a
//  working copy must never mutate the source layout.
//
//  Note: mutating methods (insertRow, removeKeys, replaceKey, etc.) are never
//  called directly inside `#expect(...)` — the Swift Testing macro expansion
//  fails to compile ("cannot use mutating member on immutable value: '$0' is
//  immutable") when its argument expression calls a mutating method on a
//  `var`. Every mutating call below is captured in a `let` first, then
//  asserted on.
//

import Foundation
import Testing
@testable import IPAKeyboardKit

// MARK: - Helper factories

private func row(_ actions: KeyAction...) -> KeyRow {
    KeyRow(keys: actions.map { Key(action: $0) })
}

/// Two panels ("IPA" primary with two 2-key rows, "More" secondary with one
/// row) plus a shared function row — exercises PanelPath addressing beyond
/// the default single-arrangement/single-panel shape.
private func makeTwoPanelLayout() -> KeyboardLayout {
    KeyboardLayout(
        name: "Test", locale: "en-US",
        arrangements: [
            Arrangement(
                name: "Split",
                panels: [
                    Panel(name: "IPA", rows: [
                        row(.insert("p"), .insert("b")),
                        row(.insert("t"), .insert("d")),
                    ]),
                    Panel(name: "More", rows: [row(.insert("ʔ"))]),
                ],
                functionRow: row(.backspace)
            )
        ])
}

/// A single-panel layout with three rows, for row reordering/removal tests
/// that need more than two rows to move within.
private func makeThreeRowLayout() -> KeyboardLayout {
    KeyboardLayout(
        name: "Test", locale: "en-US",
        rows: [row(.insert("p")), row(.insert("t")), row(.insert("k"))]
    )
}

/// A single-panel, single-row layout with three keys, for key reordering
/// tests that need more than two keys to move within.
private func makeThreeKeyRowLayout() -> KeyboardLayout {
    KeyboardLayout(
        name: "Test", locale: "en-US",
        rows: [row(.insert("p"), .insert("t"), .insert("k"))]
    )
}

/// Extracts the inserted text from a `.insert` action, or nil for any other
/// action kind — used to assert exact Unicode scalars survive a round trip.
private func insertText(_ action: KeyAction?) -> String? {
    guard case .insert(let text) = action else { return nil }
    return text
}

// MARK: - PanelPath

struct PanelPathTests {

    @Test func defaultInitIsArrangementZeroPanelZero() {
        let path = PanelPath()
        #expect(path.arrangementIndex == 0)
        #expect(path.panelIndex == 0)
    }

    @Test func primaryStaticEqualsDefaultInit() {
        #expect(PanelPath.primary == PanelPath(arrangementIndex: 0, panelIndex: 0))
    }
}

// MARK: - Lookup helpers

struct LayoutEditingLookupTests {

    @Test func panelAtValidPathReturnsPanel() {
        let layout = makeTwoPanelLayout()
        #expect(layout.panel(at: PanelPath(panelIndex: 1))?.name == "More")
    }

    @Test func panelAtInvalidArrangementIndexReturnsNil() {
        let layout = makeTwoPanelLayout()
        #expect(layout.panel(at: PanelPath(arrangementIndex: 5)) == nil)
    }

    @Test func panelAtInvalidPanelIndexReturnsNil() {
        let layout = makeTwoPanelLayout()
        #expect(layout.panel(at: PanelPath(panelIndex: 5)) == nil)
    }

    @Test func rowAtValidIndexReturnsRow() {
        let layout = makeTwoPanelLayout()
        #expect(layout.row(at: 1, inPanelAt: .primary)?.keys.first?.action == .insert("t"))
    }

    @Test func rowAtInvalidIndexReturnsNil() {
        let layout = makeTwoPanelLayout()
        #expect(layout.row(at: 5, inPanelAt: .primary) == nil)
    }

    @Test func rowAtInvalidPanelPathReturnsNil() {
        let layout = makeTwoPanelLayout()
        #expect(layout.row(at: 0, inPanelAt: PanelPath(panelIndex: 9)) == nil)
    }

    @Test func keyAtValidIndexReturnsKey() {
        let layout = makeTwoPanelLayout()
        #expect(layout.key(at: 1, inRowAt: 0, inPanelAt: .primary)?.action == .insert("b"))
    }

    @Test func keyAtInvalidIndexReturnsNil() {
        let layout = makeTwoPanelLayout()
        #expect(layout.key(at: 9, inRowAt: 0, inPanelAt: .primary) == nil)
    }

    @Test func keyAtInvalidRowIndexReturnsNil() {
        let layout = makeTwoPanelLayout()
        #expect(layout.key(at: 0, inRowAt: 9, inPanelAt: .primary) == nil)
    }
}

// MARK: - Row editing

struct RowEditingTests {

    // MARK: insertRow

    @Test func insertRowAtMiddleIndexInsertsAtPosition() {
        var layout = makeTwoPanelLayout()
        let ok = layout.insertRow(row(.insert("k")), at: 1, inPanelAt: .primary)
        #expect(ok)
        let rows = layout.panel(at: .primary)?.rows
        #expect(rows?.count == 3)
        #expect(rows?[1].keys.first?.action == .insert("k"))
    }

    @Test func insertRowAtZeroInsertsAtStart() {
        var layout = makeTwoPanelLayout()
        _ = layout.insertRow(row(.insert("k")), at: 0, inPanelAt: .primary)
        #expect(layout.panel(at: .primary)?.rows.first?.keys.first?.action == .insert("k"))
    }

    @Test func insertRowAtCountAppendsAtEnd() {
        var layout = makeTwoPanelLayout()
        let count = layout.panel(at: .primary)?.rows.count ?? 0
        let ok = layout.insertRow(row(.insert("k")), at: count, inPanelAt: .primary)
        #expect(ok)
        #expect(layout.panel(at: .primary)?.rows.last?.keys.first?.action == .insert("k"))
    }

    @Test func insertRowDefaultsToEmptyRowWhenNoneProvided() {
        var layout = makeTwoPanelLayout()
        let ok = layout.insertRow(at: 0, inPanelAt: .primary)
        #expect(ok)
        #expect(layout.panel(at: .primary)?.rows.first?.keys.isEmpty == true)
    }

    @Test func insertRowOutOfBoundsReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeTwoPanelLayout()
        let before = layout
        let ok = layout.insertRow(at: 99, inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }

    @Test func insertRowNegativeIndexReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeTwoPanelLayout()
        let before = layout
        let ok = layout.insertRow(at: -1, inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }

    @Test func insertRowAtInvalidPanelPathReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeTwoPanelLayout()
        let before = layout
        let ok = layout.insertRow(at: 0, inPanelAt: PanelPath(panelIndex: 9))
        #expect(!ok)
        #expect(layout == before)
    }

    // MARK: appendRow

    @Test func appendRowAddsToEnd() {
        var layout = makeTwoPanelLayout()
        let ok = layout.appendRow(row(.insert("k")), inPanelAt: .primary)
        #expect(ok)
        #expect(layout.panel(at: .primary)?.rows.count == 3)
        #expect(layout.panel(at: .primary)?.rows.last?.keys.first?.action == .insert("k"))
    }

    @Test func appendRowDefaultsToEmptyRowWhenNoneProvided() {
        var layout = makeTwoPanelLayout()
        let ok = layout.appendRow(inPanelAt: .primary)
        #expect(ok)
        #expect(layout.panel(at: .primary)?.rows.last?.keys.isEmpty == true)
    }

    @Test func appendRowAtInvalidPanelPathReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeTwoPanelLayout()
        let before = layout
        let ok = layout.appendRow(inPanelAt: PanelPath(panelIndex: 9))
        #expect(!ok)
        #expect(layout == before)
    }

    // MARK: removeRows

    @Test func removeRowsRemovesAtOffsets() {
        var layout = makeTwoPanelLayout()
        let ok = layout.removeRows(atOffsets: IndexSet([0]), inPanelAt: .primary)
        #expect(ok)
        #expect(layout.panel(at: .primary)?.rows.count == 1)
        #expect(layout.panel(at: .primary)?.rows.first?.keys.first?.action == .insert("t"))
    }

    @Test func removeRowsSupportsMultipleOffsets() {
        var layout = makeThreeRowLayout()
        let ok = layout.removeRows(atOffsets: IndexSet([0, 2]), inPanelAt: .primary)
        #expect(ok)
        let rows = layout.primaryArrangement?.primaryPanel?.rows
        #expect(rows?.count == 1)
        #expect(rows?.first?.keys.first?.action == .insert("t"))
    }

    @Test func removeRowsWithEmptyOffsetsReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeTwoPanelLayout()
        let before = layout
        let ok = layout.removeRows(atOffsets: IndexSet(), inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }

    @Test func removeRowsOutOfBoundsReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeTwoPanelLayout()
        let before = layout
        let ok = layout.removeRows(atOffsets: IndexSet([99]), inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }

    @Test func removeRowsAtInvalidPanelPathReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeTwoPanelLayout()
        let before = layout
        let ok = layout.removeRows(atOffsets: IndexSet([0]), inPanelAt: PanelPath(panelIndex: 9))
        #expect(!ok)
        #expect(layout == before)
    }

    // MARK: moveRows

    @Test func moveRowsToEndOfPanelMovesRowToLastPosition() {
        var layout = makeTwoPanelLayout()
        // destination == count means "to the end" (SwiftUI onMove semantics).
        let ok = layout.moveRows(fromOffsets: IndexSet([0]), toOffset: 2, inPanelAt: .primary)
        #expect(ok)
        let rows = layout.panel(at: .primary)?.rows
        #expect(rows?.first?.keys.first?.action == .insert("t"))
        #expect(rows?.last?.keys.first?.action == .insert("p"))
    }

    @Test func moveRowsFromMiddleToFrontReordersRows() {
        var layout = makeThreeRowLayout()
        let ok = layout.moveRows(fromOffsets: IndexSet([1]), toOffset: 0, inPanelAt: .primary)
        #expect(ok)
        let actions = layout.primaryArrangement?.primaryPanel?.rows.map { $0.keys.first?.action }
        #expect(actions == [.insert("t"), .insert("p"), .insert("k")])
    }

    @Test func moveRowsWithEmptySourceReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeTwoPanelLayout()
        let before = layout
        let ok = layout.moveRows(fromOffsets: IndexSet(), toOffset: 0, inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }

    @Test func moveRowsOutOfBoundsSourceReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeTwoPanelLayout()
        let before = layout
        let ok = layout.moveRows(fromOffsets: IndexSet([99]), toOffset: 0, inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }

    @Test func moveRowsInvalidDestinationReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeTwoPanelLayout()
        let before = layout
        let ok = layout.moveRows(fromOffsets: IndexSet([0]), toOffset: 99, inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }
}

// MARK: - Key editing

struct KeyEditingTests {

    // MARK: insertKey

    @Test func insertKeyAtMiddleIndexInsertsAtPosition() {
        var layout = makeThreeKeyRowLayout()
        let ok = layout.insertKey(Key(action: .insert("d")), at: 1, inRowAt: 0, inPanelAt: .primary)
        #expect(ok)
        let keys = layout.row(at: 0, inPanelAt: .primary)?.keys.map(\.action)
        #expect(keys == [.insert("p"), .insert("d"), .insert("t"), .insert("k")])
    }

    @Test func insertKeyAtZeroInsertsAtStart() {
        var layout = makeThreeKeyRowLayout()
        _ = layout.insertKey(Key(action: .insert("d")), at: 0, inRowAt: 0, inPanelAt: .primary)
        #expect(layout.row(at: 0, inPanelAt: .primary)?.keys.first?.action == .insert("d"))
    }

    @Test func insertKeyOutOfBoundsReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeThreeKeyRowLayout()
        let before = layout
        let ok = layout.insertKey(Key(action: .insert("d")), at: 99, inRowAt: 0, inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }

    @Test func insertKeyAtInvalidRowReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeThreeKeyRowLayout()
        let before = layout
        let ok = layout.insertKey(Key(action: .insert("d")), at: 0, inRowAt: 9, inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }

    @Test func insertKeyAtInvalidPanelPathReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeThreeKeyRowLayout()
        let before = layout
        let ok = layout.insertKey(
            Key(action: .insert("d")), at: 0, inRowAt: 0, inPanelAt: PanelPath(panelIndex: 9))
        #expect(!ok)
        #expect(layout == before)
    }

    // MARK: appendKey

    @Test func appendKeyAddsToEndOfRow() {
        var layout = makeThreeKeyRowLayout()
        let ok = layout.appendKey(Key(action: .insert("d")), inRowAt: 0, inPanelAt: .primary)
        #expect(ok)
        #expect(layout.row(at: 0, inPanelAt: .primary)?.keys.last?.action == .insert("d"))
    }

    @Test func appendKeyAtInvalidRowReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeThreeKeyRowLayout()
        let before = layout
        let ok = layout.appendKey(Key(action: .insert("d")), inRowAt: 9, inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }

    // MARK: removeKeys

    @Test func removeKeysRemovesAtOffsets() {
        var layout = makeThreeKeyRowLayout()
        let ok = layout.removeKeys(atOffsets: IndexSet([1]), inRowAt: 0, inPanelAt: .primary)
        #expect(ok)
        let keys = layout.row(at: 0, inPanelAt: .primary)?.keys.map(\.action)
        #expect(keys == [.insert("p"), .insert("k")])
    }

    @Test func removeKeysSupportsMultipleOffsets() {
        var layout = makeThreeKeyRowLayout()
        let ok = layout.removeKeys(atOffsets: IndexSet([0, 2]), inRowAt: 0, inPanelAt: .primary)
        #expect(ok)
        let keys = layout.row(at: 0, inPanelAt: .primary)?.keys.map(\.action)
        #expect(keys == [.insert("t")])
    }

    @Test func removeKeysWithEmptyOffsetsReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeThreeKeyRowLayout()
        let before = layout
        let ok = layout.removeKeys(atOffsets: IndexSet(), inRowAt: 0, inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }

    @Test func removeKeysOutOfBoundsReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeThreeKeyRowLayout()
        let before = layout
        let ok = layout.removeKeys(atOffsets: IndexSet([99]), inRowAt: 0, inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }

    @Test func removeKeysAtInvalidRowReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeThreeKeyRowLayout()
        let before = layout
        let ok = layout.removeKeys(atOffsets: IndexSet([0]), inRowAt: 9, inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }

    // MARK: moveKeys

    @Test func moveKeysFromEndToFrontReordersKeys() {
        var layout = makeThreeKeyRowLayout()
        let ok = layout.moveKeys(fromOffsets: IndexSet([2]), toOffset: 0, inRowAt: 0, inPanelAt: .primary)
        #expect(ok)
        let keys = layout.row(at: 0, inPanelAt: .primary)?.keys.map(\.action)
        #expect(keys == [.insert("k"), .insert("p"), .insert("t")])
    }

    @Test func moveKeysToEndOfRowMovesKeyToLastPosition() {
        var layout = makeThreeKeyRowLayout()
        let ok = layout.moveKeys(fromOffsets: IndexSet([0]), toOffset: 3, inRowAt: 0, inPanelAt: .primary)
        #expect(ok)
        let keys = layout.row(at: 0, inPanelAt: .primary)?.keys.map(\.action)
        #expect(keys == [.insert("t"), .insert("k"), .insert("p")])
    }

    @Test func moveKeysWithEmptySourceReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeThreeKeyRowLayout()
        let before = layout
        let ok = layout.moveKeys(fromOffsets: IndexSet(), toOffset: 0, inRowAt: 0, inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }

    @Test func moveKeysOutOfBoundsSourceReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeThreeKeyRowLayout()
        let before = layout
        let ok = layout.moveKeys(fromOffsets: IndexSet([99]), toOffset: 0, inRowAt: 0, inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }

    @Test func moveKeysInvalidDestinationReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = makeThreeKeyRowLayout()
        let before = layout
        let ok = layout.moveKeys(fromOffsets: IndexSet([0]), toOffset: 99, inRowAt: 0, inPanelAt: .primary)
        #expect(!ok)
        #expect(layout == before)
    }
}

// MARK: - replaceKey field updates

struct KeyFieldUpdateTests {

    @Test func replaceKeyUpdatesInsertedText() {
        var layout = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("p"))])
        let original = layout.key(at: 0, inRowAt: 0, inPanelAt: .primary)
        let edited = Key(id: original?.id ?? UUID(), action: .insert("b"))
        let ok = layout.replaceKey(at: 0, inRowAt: 0, inPanelAt: .primary, with: edited)
        #expect(ok)
        #expect(layout.key(at: 0, inRowAt: 0, inPanelAt: .primary)?.action == .insert("b"))
    }

    @Test func replaceKeyUpdatesLabel() {
        var layout = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("ə"))])
        let edited = Key(action: .insert("ə"), label: "SCHWA")
        let ok = layout.replaceKey(at: 0, inRowAt: 0, inPanelAt: .primary, with: edited)
        #expect(ok)
        #expect(layout.key(at: 0, inRowAt: 0, inPanelAt: .primary)?.label == "SCHWA")
    }

    @Test func replaceKeyUpdatesAccessibilityLabel() {
        var layout = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("ə"))])
        let edited = Key(action: .insert("ə"), accessibilityLabel: "schwa")
        let ok = layout.replaceKey(at: 0, inRowAt: 0, inPanelAt: .primary, with: edited)
        #expect(ok)
        #expect(layout.key(at: 0, inRowAt: 0, inPanelAt: .primary)?.accessibilityLabel == "schwa")
    }

    @Test func replaceKeyUpdatesAlternates() {
        var layout = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("p"))])
        let edited = Key(action: .insert("p"), alternates: [Key(action: .insert("pʰ"))])
        let ok = layout.replaceKey(at: 0, inRowAt: 0, inPanelAt: .primary, with: edited)
        #expect(ok)
        let alternates = layout.key(at: 0, inRowAt: 0, inPanelAt: .primary)?.alternates.map(\.action)
        #expect(alternates == [.insert("pʰ")])
    }

    @Test func replaceKeyUpdatesWidthFactor() {
        var layout = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.space)])
        let edited = Key(action: .space, widthFactor: 4.0)
        let ok = layout.replaceKey(at: 0, inRowAt: 0, inPanelAt: .primary, with: edited)
        #expect(ok)
        #expect(layout.key(at: 0, inRowAt: 0, inPanelAt: .primary)?.widthFactor == 4.0)
    }

    @Test func replaceKeyPreservesArrayPositionAmongSiblings() {
        var layout = makeThreeKeyRowLayout()
        let ok = layout.replaceKey(at: 1, inRowAt: 0, inPanelAt: .primary, with: Key(action: .insert("d")))
        #expect(ok)
        let actions = layout.row(at: 0, inPanelAt: .primary)?.keys.map(\.action)
        #expect(actions == [.insert("p"), .insert("d"), .insert("k")])
    }

    @Test func replaceKeyOutOfBoundsReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("p"))])
        let before = layout
        let ok = layout.replaceKey(at: 9, inRowAt: 0, inPanelAt: .primary, with: Key(action: .insert("x")))
        #expect(!ok)
        #expect(layout == before)
    }

    @Test func replaceKeyAtInvalidRowReturnsFalseAndLeavesLayoutUnchanged() {
        var layout = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("p"))])
        let before = layout
        let ok = layout.replaceKey(at: 0, inRowAt: 9, inPanelAt: .primary, with: Key(action: .insert("x")))
        #expect(!ok)
        #expect(layout == before)
    }
}

// MARK: - resettingContent(from:)

struct ResettingContentTests {

    private func makeBuiltIn() -> KeyboardLayout {
        KeyboardLayout(name: "Source", locale: "en-US", isBuiltIn: true, rows: [row(.insert("p"))])
    }

    @Test func resettingContentKeepsOwnIdentityAndMetadata() {
        let builtIn = makeBuiltIn()
        var draft = builtIn.makeEditableCopy()
        _ = draft.appendKey(Key(action: .insert("x")), inRowAt: 0, inPanelAt: .primary)

        let reset = draft.resettingContent(from: builtIn)

        #expect(reset.id == draft.id)
        #expect(reset.name == draft.name)
        #expect(reset.locale == draft.locale)
        #expect(reset.isBuiltIn == draft.isBuiltIn)
        #expect(reset.derivedFrom == draft.derivedFrom)
        // Identity comes from the draft, not the source it's reset from.
        #expect(reset.id != builtIn.id)
    }

    @Test func resettingContentReplacesArrangementsWithSources() {
        let builtIn = makeBuiltIn()
        var draft = builtIn.makeEditableCopy()
        _ = draft.appendKey(Key(action: .insert("x")), inRowAt: 0, inPanelAt: .primary)
        #expect(draft.arrangements != builtIn.arrangements)

        let reset = draft.resettingContent(from: builtIn)
        #expect(reset.arrangements == builtIn.arrangements)
    }

    @Test func resettingContentDoesNotMutateSource() {
        let builtIn = makeBuiltIn()
        let builtInBeforeReset = builtIn
        let draft = builtIn.makeEditableCopy()
        _ = draft.resettingContent(from: builtIn)
        // resettingContent(from:) takes `source` by value; passing it must not
        // mutate the caller's `builtIn`.
        #expect(builtIn == builtInBeforeReset)
    }

    @Test func resettingContentDoesNotMutateTheDraftItIsCalledOn() {
        let builtIn = makeBuiltIn()
        var draft = builtIn.makeEditableCopy()
        _ = draft.appendKey(Key(action: .insert("x")), inRowAt: 0, inPanelAt: .primary)
        let draftBeforeReset = draft

        // resettingContent returns a new value; it must not mutate `draft`.
        _ = draft.resettingContent(from: builtIn)
        #expect(draft == draftBeforeReset)
    }
}

// MARK: - Exact-Unicode round-trips through Codable after edits

struct LayoutEditingUnicodeRoundTripTests {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    @Test func combiningDiacriticSurvivesReplaceKeyThenCodableRoundTrip() throws {
        var layout = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("e"))])
        // "e" + combining acute accent U+0301 — one grapheme, two scalars.
        let combined = "e\u{0301}"
        let original = try #require(layout.key(at: 0, inRowAt: 0, inPanelAt: .primary))
        let edited = Key(id: original.id, action: .insert(combined), accessibilityLabel: "e with acute")
        let ok = layout.replaceKey(at: 0, inRowAt: 0, inPanelAt: .primary, with: edited)
        #expect(ok)

        let decoded = try decoder.decode(KeyboardLayout.self, from: try encoder.encode(layout))
        let text = try #require(insertText(decoded.key(at: 0, inRowAt: 0, inPanelAt: .primary)?.action))
        #expect(text == combined)
        #expect(text.unicodeScalars.map(\.value) == [0x65, 0x0301])
    }

    @Test func exactIPAScalarsSurviveAppendKeyThenCodableRoundTrip() throws {
        var layout = KeyboardLayout(name: "Test", locale: "en-US", rows: [row()])
        // ɡ U+0261 (script g, not ASCII "g" U+0067); ː U+02D0 (length mark, not
        // colon U+003A); ɹ U+0279 (turned r, the primary General American rhotic).
        let ok1 = layout.appendKey(Key(action: .insert("ɡ")), inRowAt: 0, inPanelAt: .primary)
        let ok2 = layout.appendKey(Key(action: .insert("ː")), inRowAt: 0, inPanelAt: .primary)
        let ok3 = layout.appendKey(Key(action: .insert("ɹ")), inRowAt: 0, inPanelAt: .primary)
        #expect(ok1)
        #expect(ok2)
        #expect(ok3)

        let decoded = try decoder.decode(KeyboardLayout.self, from: try encoder.encode(layout))
        let keys = decoded.row(at: 0, inPanelAt: .primary)?.keys ?? []
        #expect(keys.count == 3)

        let g = try #require(insertText(keys[0].action))
        #expect(g.unicodeScalars.map(\.value) == [0x0261])
        let length = try #require(insertText(keys[1].action))
        #expect(length.unicodeScalars.map(\.value) == [0x02D0])
        let rhotic = try #require(insertText(keys[2].action))
        #expect(rhotic.unicodeScalars.map(\.value) == [0x0279])
    }

    @Test func alternatesPreserveCombiningMarksThroughInsertKeyAndCodableRoundTrip() throws {
        var layout = KeyboardLayout(name: "Test", locale: "en-US", rows: [row()])
        // "o" + combining diaeresis U+0308 as a long-press alternate.
        let combined = "o\u{0308}"
        let key = Key(action: .insert("o"), alternates: [Key(action: .insert(combined))])
        let ok = layout.insertKey(key, at: 0, inRowAt: 0, inPanelAt: .primary)
        #expect(ok)

        let decoded = try decoder.decode(KeyboardLayout.self, from: try encoder.encode(layout))
        let alternate = decoded.key(at: 0, inRowAt: 0, inPanelAt: .primary)?.alternates.first
        let text = try #require(insertText(alternate?.action))
        #expect(text == combined)
        #expect(text.unicodeScalars.map(\.value) == [0x6F, 0x0308])
    }

    @Test func resettingContentPreservesExactUnicodeFromSource() throws {
        let builtIn = KeyboardLayout(
            name: "Source", locale: "en-US", isBuiltIn: true,
            rows: [row(.insert("ɡ"), .insert("ː"))]
        )
        var draft = builtIn.makeEditableCopy()
        // Corrupt the draft, then reset it back to the built-in's content.
        let ok = draft.replaceKey(at: 0, inRowAt: 0, inPanelAt: .primary, with: Key(action: .insert("x")))
        #expect(ok)

        let reset = draft.resettingContent(from: builtIn)
        let decoded = try decoder.decode(KeyboardLayout.self, from: try encoder.encode(reset))
        let keys = decoded.row(at: 0, inPanelAt: .primary)?.keys ?? []
        #expect(insertText(keys.first?.action)?.unicodeScalars.map(\.value) == [0x0261])
        #expect(insertText(keys.last?.action)?.unicodeScalars.map(\.value) == [0x02D0])
    }
}

// MARK: - Value semantics: editing a working copy never mutates the source

struct LayoutEditingValueSemanticsTests {

    @Test func insertRowOnCopyDoesNotMutateSource() {
        let source = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("p"))])
        var copy = source
        _ = copy.insertRow(row(.insert("t")), at: 0, inPanelAt: .primary)
        #expect(source.primaryArrangement?.primaryPanel?.rows.count == 1)
        #expect(copy.primaryArrangement?.primaryPanel?.rows.count == 2)
    }

    @Test func removeRowsOnCopyDoesNotMutateSource() {
        let source = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("p")), row(.insert("t"))])
        var copy = source
        _ = copy.removeRows(atOffsets: IndexSet([0]), inPanelAt: .primary)
        #expect(source.primaryArrangement?.primaryPanel?.rows.count == 2)
        #expect(copy.primaryArrangement?.primaryPanel?.rows.count == 1)
    }

    @Test func moveRowsOnCopyDoesNotMutateSource() {
        let source = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("p")), row(.insert("t"))])
        var copy = source
        _ = copy.moveRows(fromOffsets: IndexSet([0]), toOffset: 2, inPanelAt: .primary)
        #expect(source.row(at: 0, inPanelAt: .primary)?.keys.first?.action == .insert("p"))
        #expect(copy.row(at: 0, inPanelAt: .primary)?.keys.first?.action == .insert("t"))
    }

    @Test func insertKeyOnCopyDoesNotMutateSource() {
        let source = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("p"))])
        var copy = source
        _ = copy.insertKey(Key(action: .insert("b")), at: 0, inRowAt: 0, inPanelAt: .primary)
        #expect(source.row(at: 0, inPanelAt: .primary)?.keys.count == 1)
        #expect(copy.row(at: 0, inPanelAt: .primary)?.keys.count == 2)
    }

    @Test func removeKeysOnCopyDoesNotMutateSource() {
        let source = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("p"), .insert("b"))])
        var copy = source
        _ = copy.removeKeys(atOffsets: IndexSet([0]), inRowAt: 0, inPanelAt: .primary)
        #expect(source.row(at: 0, inPanelAt: .primary)?.keys.count == 2)
        #expect(copy.row(at: 0, inPanelAt: .primary)?.keys.count == 1)
    }

    @Test func moveKeysOnCopyDoesNotMutateSource() {
        let source = makeThreeKeyRowLayout()
        var copy = source
        _ = copy.moveKeys(fromOffsets: IndexSet([2]), toOffset: 0, inRowAt: 0, inPanelAt: .primary)
        #expect(source.row(at: 0, inPanelAt: .primary)?.keys.map(\.action) == [.insert("p"), .insert("t"), .insert("k")])
        #expect(copy.row(at: 0, inPanelAt: .primary)?.keys.map(\.action) == [.insert("k"), .insert("p"), .insert("t")])
    }

    @Test func replaceKeyOnCopyDoesNotMutateSource() {
        let source = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("p"))])
        var copy = source
        _ = copy.replaceKey(at: 0, inRowAt: 0, inPanelAt: .primary, with: Key(action: .insert("b")))
        #expect(source.key(at: 0, inRowAt: 0, inPanelAt: .primary)?.action == .insert("p"))
        #expect(copy.key(at: 0, inRowAt: 0, inPanelAt: .primary)?.action == .insert("b"))
    }

    @Test func editingOneLayoutInAnArrayDoesNotMutateAnEqualNeighbor() {
        // Guards against accidental shared storage across value-type copies
        // held in a collection, mirroring how a host view model holds layouts.
        let original = KeyboardLayout(name: "Test", locale: "en-US", rows: [row(.insert("p"))])
        var layouts = [original, original]
        _ = layouts[0].appendKey(Key(action: .insert("x")), inRowAt: 0, inPanelAt: .primary)
        #expect(layouts[0].row(at: 0, inPanelAt: .primary)?.keys.count == 2)
        #expect(layouts[1].row(at: 0, inPanelAt: .primary)?.keys.count == 1)
    }
}
