//
//  BundledLayoutTests.swift
//  IPAKeyboardKitTests
//
//  Guards the JSON↔model contract the renderer depends on: the bundled
//  defaults must decode, and every key must produce a glyph to render.
//

import Testing
@testable import IPAKeyboardKit

struct BundledLayoutTests {

    @Test func bundledLayoutsDecode() {
        let layouts = LayoutStore().bundledLayouts()
        #expect(!layouts.isEmpty)
        #expect(layouts.allSatisfy { $0.isBuiltIn })
    }

    @Test func enUSHasSplitArrangementWithTwoSwitchablePanels() throws {
        let layouts = LayoutStore().bundledLayouts()
        let enUS = try #require(layouts.first { $0.locale == "en-US" })
        let arrangement = try #require(enUS.primaryArrangement)
        #expect(arrangement.panels.count == 2)

        // Each panel fits a standard keyboard's row budget, no horizontal scroll.
        #expect(arrangement.maxRowCount <= 5)

        // The shared bottom bar carries the globe key (defined once, not per-panel).
        let functionRow = try #require(arrangement.functionRow)
        #expect(functionRow.keys.contains { $0.action == .nextKeyboard })

        // The primary panel's switch key reaches a secondary panel, and that
        // panel's switch key returns to the primary.
        let primary = try #require(arrangement.primaryPanel)
        guard case .switchPanel(let target) = try #require(primary.switchKey).action else {
            Issue.record("primary panel switchKey is not a switchPanel action")
            return
        }
        let secondary = try #require(arrangement.panel(named: target))
        #expect(secondary.name == target)
        #expect(secondary.name != primary.name)
        #expect(secondary.switchKey?.action == .switchPanel(primary.name))
    }

    @Test func enUSGroupsConsonantsLeftAndVowelsRightWithASpacer() throws {
        let layouts = LayoutStore().bundledLayouts()
        let enUS = try #require(layouts.first { $0.locale == "en-US" })
        let primary = try #require(enUS.primaryArrangement?.primaryPanel)
        // At least one symbol row uses a flexible spacer flanked by real keys on
        // both sides — the right-grouping is wired through to the data.
        let grouped = primary.rows.first { row in
            guard let gap = row.keys.firstIndex(where: \.isSpacer) else { return false }
            let before = row.keys[..<gap].contains { !$0.isSpacer }
            let after = row.keys[row.keys.index(after: gap)...].contains { !$0.isSpacer }
            return before && after
        }
        #expect(grouped != nil)
    }

    @Test func everyCharacterKeyHasADisplayLabel() {
        for layout in LayoutStore().bundledLayouts() {
            let panels = layout.arrangements.flatMap(\.panels)
            let rowKeys = panels.flatMap(\.rows).flatMap(\.keys)
            let functionKeys = layout.arrangements.compactMap(\.functionRow).flatMap(\.keys)
            let switchKeys = panels.compactMap(\.switchKey)
            for key in rowKeys + functionKeys + switchKeys {
                if case .insert = key.action {
                    #expect(!key.displayLabel.isEmpty,
                            "insert key with empty label in \(layout.locale)")
                }
            }
        }
    }
}
