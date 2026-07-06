//
//  KeyRowSizing.swift
//  IPAKeyboardKit
//
//  Pure width math for one keyboard row, extracted from `KeyRowView` so the
//  rules are unit-testable (issue #117).
//
//  Two regimes:
//
//  - **Plain rows** (no spacer) fill the available width proportionally:
//    `unit = (width − spacing·(n−1)) / totalFactor`, each key `factor·unit`.
//  - **Grid rows** — rows containing a `spacer` — size their keys off the
//    shared `gridReferenceFactor` (the densest rendered row) so grouped keys
//    match that row instead of stretching. When such a row's factors sum to
//    the *whole* grid reference, the row is on the grid exactly, and it is
//    laid out pixel-exactly: the unit derives from the grid's factor total
//    rather than the row's element count
//    (`unit = (width − spacing·(R−1)) / R`), and every element spans its
//    internal gaps (`factor·unit + (factor−1)·spacing`), the way the system
//    space bar covers the columns *and* the gaps beneath it. A row of
//    factors `f₁…fₙ` summing to `R` then totals
//    `R·unit + (R−n)·spacing + (n−1)·spacing = R·unit + (R−1)·spacing`
//    — independent of `n` — so a 1.0-factor cap is the same width in every
//    full-grid row no matter how many spacers flank it (ipa-full's QWERTY
//    rows: 10 keys vs 9 keys + 2 spacers vs 7 keys + 2 spacers).
//
//  Grid rows that *under*-fill the reference (their factors sum below it)
//  keep the pre-#117 best-effort math — unit from the reference factor but
//  spacing from their own element count — so existing layouts like en-US's
//  split rows render exactly as before.
//

import CoreGraphics

struct KeyRowSizing {

    /// How close a grid row's factor total must be to the reference to count
    /// as spanning the whole grid. Halves and quarters sum exactly in binary;
    /// the tolerance only absorbs accumulation error from unusual
    /// user-authored factors (e.g. 0.1).
    static let gridMatchTolerance: Double = 1e-6

    /// Point width of a 1.0-factor element in this row.
    let unitWidth: CGFloat
    /// Whether the row spans the shared grid exactly, so its elements use
    /// gap-spanning widths (see the file header).
    let isOnSharedGrid: Bool
    private let keySpacing: CGFloat

    /// The shared grid basis for a set of rendered rows: the largest total
    /// `widthFactor` (spacers counted, default 1.0 each) across them.
    static func gridReferenceFactor(rows: [KeyRow]) -> Double {
        rows.map { row in row.keys.reduce(0.0) { $0 + $1.widthFactor } }
            .max() ?? 0
    }

    init(
        row: KeyRow,
        availableWidth: CGFloat,
        keySpacing: CGFloat,
        gridReferenceFactor: Double
    ) {
        let keys = row.keys
        let hasSpacer = keys.contains(where: \.isSpacer)
        let totalFactor = keys.reduce(0.0) { $0 + $1.widthFactor }
        self.keySpacing = keySpacing

        isOnSharedGrid = hasSpacer
            && gridReferenceFactor > 0
            && abs(totalFactor - gridReferenceFactor) <= Self.gridMatchTolerance

        if isOnSharedGrid {
            // Spacing share from the grid's own factor total, so the unit is
            // identical for every full-grid row regardless of element count.
            unitWidth = (availableWidth - keySpacing * CGFloat(gridReferenceFactor - 1))
                / CGFloat(gridReferenceFactor)
        } else {
            let referenceFactor = hasSpacer ? gridReferenceFactor : totalFactor
            let gapCount = CGFloat(max(keys.count - 1, 0))
            unitWidth = referenceFactor > 0
                ? (availableWidth - keySpacing * gapCount) / CGFloat(referenceFactor)
                : 0
        }
    }

    /// The rendered width for one of the row's elements — a key's fixed frame
    /// width, or a spacer's minimum length (spacers may still grow to
    /// right-align the keys after them when the row under-fills the grid).
    func width(for key: Key) -> CGFloat {
        let width = isOnSharedGrid
            ? unitWidth * key.widthFactor + keySpacing * CGFloat(key.widthFactor - 1)
            : unitWidth * key.widthFactor
        return max(width, 0)
    }
}
