//
//  KeyRowSizingTests.swift
//  IPAKeyboardKitTests
//
//  Verifies the pure row-width math behind `KeyRowView` (issue #117): rows
//  that span the shared spacer grid exactly are laid out pixel-exactly —
//  the unit width derives from the grid's factor total, not the row's
//  element count, and elements span their internal gaps — so letter caps
//  are identical point widths across ipa-full's three QWERTY rows. Every
//  row that does *not* span the grid (spacer-free rows, en-US's under-full
//  split rows, the bottom bar) must size exactly as the pre-#117 renderer
//  did; the bundled-layout sweep pins that down layout by layout.
//

import CoreGraphics
import Testing
@testable import IPAKeyboardKit

struct KeyRowSizingTests {

    /// Default metrics' key spacing on a 382-pt row (a 390-pt iPhone
    /// keyboard minus the 4-pt outer padding per side).
    private let width: CGFloat = 382
    private let spacing: CGFloat = 6

    /// The rows the view renders for a panel: its symbol rows plus the pinned
    /// bottom bar (switch key + shared function row), mirroring
    /// `KeyboardView.bottomBar` — the grid reference spans all of them.
    private func renderedRows(panel: Panel, arrangement: Arrangement) -> [KeyRow] {
        let bottomKeys = (panel.switchKey.map { [$0] } ?? [])
            + (arrangement.functionRow?.keys ?? [])
        return panel.rows + (bottomKeys.isEmpty ? [] : [KeyRow(keys: bottomKeys)])
    }

    /// The pre-#117 renderer math, kept verbatim as the regression oracle:
    /// per-row spacing from the row's own element count, widths a plain
    /// multiple of the unit.
    private func legacyWidths(for row: KeyRow, gridReferenceFactor: Double) -> [CGFloat] {
        let hasSpacer = row.keys.contains(where: \.isSpacer)
        let totalFactor = row.keys.reduce(0.0) { $0 + $1.widthFactor }
        let referenceFactor = hasSpacer ? gridReferenceFactor : totalFactor
        let gapCount = CGFloat(max(row.keys.count - 1, 0))
        let unit = referenceFactor > 0 ? (width - spacing * gapCount) / CGFloat(referenceFactor) : 0
        return row.keys.map { max(unit * $0.widthFactor, 0) }
    }

    // Bundled-layout lookup comes from LayoutTestSupport.swift.

    // MARK: Pixel-exact widths on the shared grid (the issue's fix)

    @Test func qwertyLetterCapsAreIdenticalWidthsAcrossAllThreeRows() throws {
        // ipa-full's QWERTY panel: 10 keys / 9 keys + two 0.5 spacers /
        // 7 keys + two 1.5 spacers, every row totalling the 10-unit grid.
        // Before #117 the differing element counts (10 vs 11 vs 9) left the
        // letter caps ~0.6 pt apart; they must now be exactly equal.
        let full = try bundledLayout(named: "IPA — Full (QWERTY)")
        let arrangement = try #require(full.primaryArrangement)
        let panel = try #require(arrangement.primaryPanel)
        try #require(panel.rows.count == 3)
        let reference = KeyRowSizing.gridReferenceFactor(
            rows: renderedRows(panel: panel, arrangement: arrangement))

        // Hold across representative widths: iPhone portrait, iPhone
        // landscape-ish, and an iPad-class width.
        for width in [width, CGFloat(654), CGFloat(1180)] {
            var letterWidths: Set<CGFloat> = []
            for row in panel.rows {
                let sizing = KeyRowSizing(
                    row: row,
                    availableWidth: width,
                    keySpacing: spacing,
                    gridReferenceFactor: reference)
                for key in row.keys where !key.isSpacer {
                    letterWidths.insert(sizing.width(for: key))
                }
            }
            #expect(letterWidths.count == 1,
                    "letter caps at width \(width) should share one exact width, got \(letterWidths)")
        }
    }

    @Test func fullGridRowsExactlyFillTheAvailableWidth() throws {
        // The grid math must not overflow or underfill: minimum element
        // widths plus the HStack's gaps come out to the row width exactly,
        // so the spacers sit at their minimum with zero slack.
        let full = try bundledLayout(named: "IPA — Full (QWERTY)")
        let arrangement = try #require(full.primaryArrangement)
        let panel = try #require(arrangement.primaryPanel)
        let reference = KeyRowSizing.gridReferenceFactor(
            rows: renderedRows(panel: panel, arrangement: arrangement))

        for (index, row) in panel.rows.enumerated() {
            let sizing = KeyRowSizing(
                row: row,
                availableWidth: width,
                keySpacing: spacing,
                gridReferenceFactor: reference)
            let elementTotal = row.keys.reduce(CGFloat(0)) { $0 + sizing.width(for: $1) }
            let total = elementTotal + spacing * CGFloat(max(row.keys.count - 1, 0))
            #expect(abs(total - width) < 0.0001,
                    "QWERTY row \(index + 1) should fill \(width) pt exactly, got \(total)")
        }
    }

    @Test func gridElementsSpanTheirInternalGaps() {
        // On the grid, a multi-unit element covers its columns *and* the gaps
        // between them (like the system space bar), and a fractional spacer
        // gives its share of a gap back — that is what makes row totals
        // element-count-independent.
        let wide = Key(action: .insert("ə"), widthFactor: 2.0)
        let row = KeyRow(keys: [
            Key(action: .spacer, widthFactor: 0.5),
            wide,
            .insert("i"),
            Key(action: .spacer, widthFactor: 0.5),
        ])
        let sizing = KeyRowSizing(
            row: row, availableWidth: width, keySpacing: spacing, gridReferenceFactor: 4.0)
        let unit = (width - spacing * 3) / 4
        #expect(sizing.isOnSharedGrid)
        #expect(sizing.width(for: wide) == unit * 2 + spacing)
        #expect(sizing.width(for: row.keys[2]) == unit)
        #expect(sizing.width(for: row.keys[0]) == unit * 0.5 - spacing * 0.5)
    }

    // MARK: No behavior change off the grid (the issue's regression guard)

    @Test func everyBundledRowExceptTheIndentedQwertyRowsKeepsItsLegacyWidths() {
        // The acceptance criterion "no behavior change for layouts that don't
        // opt into the shared grid": sweep every rendered row of every
        // bundled layout and require bit-identical widths to the pre-#117
        // math. The only rows allowed (and required) to move are ipa-full's
        // two indented QWERTY rows — full-grid spacer rows whose element
        // count differs from the grid total, which is precisely the
        // divergence this issue fixes. Full-grid spacer rows elsewhere
        // (en-US IPA row 4, all en-GB IPA rows, ja-JP IPA row 4, three
        // ipa-chart rows) have element count equal to the factor total with
        // all-1.0 factors, where the two formulas coincide exactly.
        for layout in LayoutStore().bundledLayouts() {
            for arrangement in layout.arrangements {
                for panel in arrangement.panels {
                    let rows = renderedRows(panel: panel, arrangement: arrangement)
                    let reference = KeyRowSizing.gridReferenceFactor(rows: rows)
                    for (index, row) in rows.enumerated() {
                        let sizing = KeyRowSizing(
                            row: row,
                            availableWidth: width,
                            keySpacing: spacing,
                            gridReferenceFactor: reference)
                        let widths = row.keys.map { sizing.width(for: $0) }
                        let legacy = legacyWidths(for: row, gridReferenceFactor: reference)
                        let isIndentedQwertyRow = layout.name == "IPA — Full (QWERTY)"
                            && panel.name == "QWERTY"
                            && (index == 1 || index == 2)
                        if isIndentedQwertyRow {
                            #expect(widths != legacy,
                                    "QWERTY row \(index + 1) is the row #117 fixes; it should differ from the legacy math")
                        } else {
                            #expect(widths == legacy,
                                    "row \(index) of \(layout.name)/\(panel.name) must keep its legacy widths")
                        }
                    }
                }
            }
        }
    }

    @Test func spacerFreeRowsKeepPlainProportionalFill() {
        // A spacer-free row never joins the grid, even when its factors sum
        // to the reference — the bottom bar (1.5 + 3.0 + 1.5 + 1.5 + 1.5)
        // must keep its plain multiples, not gain gap-spanning widths.
        let space = Key(action: .space, widthFactor: 3.0)
        let row = KeyRow(keys: [
            Key(action: .switchPanel("More"), widthFactor: 1.5),
            Key(action: .nextKeyboard, widthFactor: 1.5),
            space,
            Key(action: .backspace, widthFactor: 1.5),
            Key(action: .return, widthFactor: 1.5),
        ])
        let sizing = KeyRowSizing(
            row: row, availableWidth: width, keySpacing: spacing, gridReferenceFactor: 9.0)
        let unit = (width - spacing * 4) / 9
        #expect(!sizing.isOnSharedGrid)
        #expect(sizing.width(for: space) == unit * 3)
        #expect(sizing.width(for: row.keys[0]) == unit * 1.5)
    }

    @Test func underFullSpacerRowsKeepTheLegacyBestEffortSizing() {
        // A spacer row whose factors sum below the grid reference (en-US's
        // split rows) keeps the old math: unit from the reference, spacing
        // from its own element count, and the spacer free to stretch.
        let row = KeyRow(keys: [.insert("p"), .spacer, .insert("i")])
        let sizing = KeyRowSizing(
            row: row, availableWidth: width, keySpacing: spacing, gridReferenceFactor: 12.0)
        let unit = (width - spacing * 2) / 12
        #expect(!sizing.isOnSharedGrid)
        #expect(sizing.width(for: row.keys[0]) == unit)
        #expect(sizing.width(for: row.keys[1]) == unit)
    }

    // MARK: Degenerate input

    @Test func emptyAndZeroFactorRowsProduceZeroWidthsWithoutCrashing() {
        let empty = KeyRowSizing(
            row: KeyRow(keys: []), availableWidth: width, keySpacing: spacing,
            gridReferenceFactor: 0)
        #expect(empty.unitWidth == 0)

        // All-zero factors: no division by zero, widths clamp at 0.
        let zeroKey = Key(action: .insert("ə"), widthFactor: 0)
        let zero = KeyRowSizing(
            row: KeyRow(keys: [zeroKey, Key(action: .spacer, widthFactor: 0)]),
            availableWidth: width, keySpacing: spacing, gridReferenceFactor: 0)
        #expect(zero.width(for: zeroKey) == 0)

        // A zero-factor key on a live grid spans a negative gap share; the
        // rendered width still clamps at 0.
        let grid = KeyRowSizing(
            row: KeyRow(keys: [zeroKey, .spacer, .insert("i")]),
            availableWidth: width, keySpacing: spacing, gridReferenceFactor: 2.0)
        #expect(grid.width(for: zeroKey) == 0)
    }
}
