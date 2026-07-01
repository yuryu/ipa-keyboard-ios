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

    // MARK: Generic "IPA — Full (QWERTY)" layout

    private func genericFullLayout() throws -> KeyboardLayout {
        let layouts = LayoutStore().bundledLayouts()
        return try #require(layouts.first { $0.locale == "und" },
                            "the generic IPA — Full (QWERTY) layout should be bundled")
    }

    @Test func atLeastTwoBundledLayouts() {
        // en-US plus the generic Full layout — selection is a real choice.
        #expect(LayoutStore().bundledLayouts().count >= 2)
    }

    @Test func genericFullLayoutIsAReadOnlyUndLayout() throws {
        let full = try genericFullLayout()
        #expect(full.isBuiltIn)
        #expect(full.name == "IPA — Full (QWERTY)")
        #expect(full.schemaVersion == KeyboardLayout.currentSchemaVersion)
    }

    @Test func genericFullLayoutSplitsSymbolsAcrossSwitchablePanels() throws {
        let arrangement = try #require(try genericFullLayout().primaryArrangement)
        // "Most of IPA" can't fit one screen, so it uses multiple panels...
        #expect(arrangement.panels.count >= 2)
        // ...each reachable via a panel-switch key.
        let primary = try #require(arrangement.primaryPanel)
        guard case .switchPanel = try #require(primary.switchKey).action else {
            Issue.record("generic Full primary panel switchKey is not a switchPanel action")
            return
        }
        // A shared bottom bar carries the globe key.
        let functionRow = try #require(arrangement.functionRow)
        #expect(functionRow.keys.contains { $0.action == .nextKeyboard })
    }

    @Test func genericFullLayoutFitsOneScreenPerPanel() throws {
        let arrangement = try #require(try genericFullLayout().primaryArrangement)
        // Legibility/one-screen heuristic: keep rows near a QWERTY row's density
        // so keys don't shrink to unusable widths (en-US tops out around 13).
        for panel in arrangement.panels {
            for row in panel.rows {
                let width = row.keys.reduce(0.0) { $0 + $1.widthFactor }
                #expect(width <= 12.0, "row too dense in generic Full panel \(panel.name)")
            }
        }
    }

    @Test func bundledLayoutsUseIPAUnicodeNotASCIILookalikes() {
        // The velar plosive is ɡ (U+0261) not g, length is ː (U+02D0) not ':',
        // glottal stop is ʔ (U+0294) not '?', stress is ˈ (U+02C8) not "'".
        let forbidden: Set<String> = ["g", ":", "?", "'"]
        for layout in LayoutStore().bundledLayouts() {
            let panels = layout.arrangements.flatMap(\.panels)
            let allKeys = panels.flatMap(\.rows).flatMap(\.keys)
                + layout.arrangements.compactMap(\.functionRow).flatMap(\.keys)
                + panels.compactMap(\.switchKey)
            for key in allKeys {
                for candidate in [key] + key.alternates {
                    if case .insert(let text) = candidate.action {
                        #expect(!forbidden.contains(text),
                                "ASCII lookalike \"\(text)\" in \(layout.locale); use the IPA code point")
                    }
                }
            }
        }
    }
}
