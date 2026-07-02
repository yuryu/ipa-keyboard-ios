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

    @Test func enUSKeepsTheFullVowelInventoryOnThePrimaryPanel() throws {
        // Issue #39: the high-frequency diphthongs and the rhotic schwa must be
        // visible by default, not parked behind the "More" panel switch.
        let layouts = LayoutStore().bundledLayouts()
        let enUS = try #require(layouts.first { $0.locale == "en-US" })
        let primary = try #require(enUS.primaryArrangement?.primaryPanel)
        let inserted = Set(primary.rows.flatMap(\.keys).compactMap { key -> String? in
            if case .insert(let text) = key.action { return text }
            return nil
        })
        let vowels: Set<String> = [
            "i", "ɪ", "u", "ʊ", "ɛ", "æ", "ə", "ʌ", "ɑ", "ɔ",
            "eɪ", "oʊ", "aɪ", "aʊ", "ɔɪ", "ɚ",
        ]
        #expect(vowels.isSubset(of: inserted))
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
        // Selected by name: there are several bundled `und` layouts.
        let layouts = LayoutStore().bundledLayouts()
        return try #require(layouts.first { $0.name == "IPA — Full (QWERTY)" },
                            "the generic IPA — Full (QWERTY) layout should be bundled")
    }

    @Test func atLeastTwoBundledLayouts() {
        // en-US plus the generic Full layout — selection is a real choice.
        #expect(LayoutStore().bundledLayouts().count >= 2)
    }

    @Test func genericFullLayoutIsAReadOnlyUndLayout() throws {
        let full = try genericFullLayout()
        #expect(full.isBuiltIn)
        #expect(full.locale == "und")
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
        // glottal stop is ʔ (U+0294) not '?', stress is ˈ (U+02C8) not "'",
        // the (post)alveolar click is ǃ (U+01C3) not '!', and the dental
        // click is ǀ (U+01C0) not '|'.
        let forbidden: Set<String> = ["g", ":", "?", "'", "!", "|"]
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

    // MARK: Generic "IPA — Chart" layout

    private func genericChartLayout() throws -> KeyboardLayout {
        let layouts = LayoutStore().bundledLayouts()
        return try #require(layouts.first { $0.name == "IPA — Chart" },
                            "the generic IPA — Chart layout should be bundled")
    }

    /// Every string a layout can insert — panel rows, the function row, switch
    /// keys, and long-press alternates (recursively).
    private func insertTexts(in layout: KeyboardLayout) -> Set<String> {
        var texts = Set<String>()
        func visit(_ key: Key) {
            if case .insert(let text) = key.action { texts.insert(text) }
            key.alternates.forEach(visit)
        }
        let panels = layout.arrangements.flatMap(\.panels)
        (panels.flatMap(\.rows).flatMap(\.keys)
            + layout.arrangements.compactMap(\.functionRow).flatMap(\.keys)
            + panels.compactMap(\.switchKey))
            .forEach(visit)
        return texts
    }

    @Test func genericChartLayoutIsAReadOnlyUndLayout() throws {
        let chart = try genericChartLayout()
        #expect(chart.isBuiltIn)
        #expect(chart.locale == "und")
        #expect(chart.schemaVersion == KeyboardLayout.currentSchemaVersion)
    }

    @Test func genericChartLayoutPanelSwitchKeysFormACycle() throws {
        // Stops → Fricatives → Vowels → More → Stops, the way ipa-full cycles
        // its panels: every panel is reachable and the cycle closes.
        let arrangement = try #require(try genericChartLayout().primaryArrangement)
        #expect(arrangement.panels.count == 4)
        let start = try #require(arrangement.primaryPanel)
        var current = start
        var visited: Set<String> = []
        for _ in arrangement.panels.indices {
            visited.insert(current.name)
            guard case .switchPanel(let target) = try #require(current.switchKey).action else {
                Issue.record("chart panel \(current.name) switchKey is not a switchPanel action")
                return
            }
            current = try #require(arrangement.panel(named: target))
        }
        #expect(current.name == start.name, "chart panel switch keys should cycle back to the first panel")
        #expect(visited.count == arrangement.panels.count, "chart panel cycle should visit every panel once")
    }

    @Test func genericChartLayoutStaysWithinTheFullLayoutHeightBudget() throws {
        // The keyboard is sized to totalRowCount; the chart layout must not
        // render taller than the already-shipped generic layout.
        let chart = try #require(try genericChartLayout().primaryArrangement)
        let full = try #require(try genericFullLayout().primaryArrangement)
        #expect(chart.totalRowCount <= full.totalRowCount)
        let functionRow = try #require(chart.functionRow)
        #expect(functionRow.keys.contains { $0.action == .nextKeyboard })
    }

    @Test func genericChartLayoutFitsOneScreenPerPanel() throws {
        // Same density heuristics as the Full layout: no horizontal scrolling,
        // keys no denser than a QWERTY row (ipa-full's widest row is 10 keys).
        let arrangement = try #require(try genericChartLayout().primaryArrangement)
        for panel in arrangement.panels {
            for row in panel.rows {
                let width = row.keys.reduce(0.0) { $0 + $1.widthFactor }
                #expect(width <= 12.0, "row too dense in chart panel \(panel.name)")
                #expect(row.keys.filter { !$0.isSpacer }.count <= 10,
                        "too many keys in a row of chart panel \(panel.name)")
            }
        }
    }

    @Test func genericChartLayoutUsesTheExactChartCodePoints() throws {
        // Spot-check the trap-prone code points against the Unicode escapes so
        // an editor silently substituting a lookalike glyph fails loudly.
        // Clicks intentionally follow IPA values, not Unicode names (U+01C3 is
        // *named* "retroflex click" but is the IPA (post)alveolar click ǃ).
        let texts = insertTexts(in: try genericChartLayout())
        let required: [(String, String)] = [
            ("\u{0261}", "voiced velar plosive ɡ"),
            ("\u{014B}", "voiced velar nasal ŋ"),
            ("\u{02D0}", "length mark ː"),
            ("\u{0298}", "bilabial click ʘ"),
            ("\u{01C0}", "dental click ǀ"),
            ("\u{01C3}", "(post)alveolar click ǃ"),
            ("\u{01C2}", "palatoalveolar click ǂ"),
            ("\u{01C1}", "alveolar lateral click ǁ"),
            ("\u{0253}", "voiced bilabial implosive ɓ"),
            ("\u{0257}", "voiced alveolar implosive ɗ"),
            ("\u{0284}", "voiced palatal implosive ʄ"),
            ("\u{0260}", "voiced velar implosive ɠ"),
            ("\u{029B}", "voiced uvular implosive ʛ"),
            ("\u{02BC}", "ejective mark ʼ"),
            ("\u{0299}", "voiced bilabial trill ʙ"),
            ("\u{2C71}", "voiced labiodental flap ⱱ"),
            ("\u{0361}", "tie bar ◌͡◌"),
            ("\u{0259}", "schwa ə"),
        ]
        for (text, what) in required {
            #expect(texts.contains(text), "chart layout should insert \(what)")
        }
    }

    @Test func genericChartLayoutEveryKeyHasAnAccessibilityLabel() throws {
        // The chart layout promises a spoken IPA name on every symbol key,
        // long-press alternates included.
        let layout = try genericChartLayout()
        func check(_ key: Key) {
            if case .insert = key.action {
                #expect(!(key.accessibilityLabel ?? "").isEmpty,
                        "missing accessibilityLabel for chart key \(key.displayLabel)")
            }
            key.alternates.forEach(check)
        }
        let panels = layout.arrangements.flatMap(\.panels)
        (panels.flatMap(\.rows).flatMap(\.keys)
            + layout.arrangements.compactMap(\.functionRow).flatMap(\.keys)
            + panels.compactMap(\.switchKey))
            .forEach(check)
    }
}
