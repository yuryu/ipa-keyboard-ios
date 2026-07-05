//
//  AlternatesPopupPlacementTests.swift
//  IPAKeyboardKitTests
//
//  Verifies the pure placement rules behind the long-press alternates
//  popup (issue #122): centered above the pressed key cap on every row —
//  the top row included, matching the system keyboard — and, because a
//  custom keyboard cannot draw outside its own view, always clamped fully
//  inside the keyboard's bounds, with edge keys shifting the popup inward
//  and top-row keys shifting it down over their own cap (never below the
//  key). The fixture geometry mirrors the default `KeyboardMetrics`:
//  50-pt rows, 8-pt row spacing, 4-pt outer padding, on a 390-pt-wide
//  iPhone keyboard; the popup sizes mirror the rendered popup's 36×40
//  minimum cells, 4 pt apart, inside 6 pt of padding.
//

import CoreGraphics
import Testing
@testable import IPAKeyboardKit

struct AlternatesPopupPlacementTests {

    /// A five-row default-metrics keyboard: 390 × 290 with its origin at
    /// the top-left, rows at y = 4, 62, 120, …
    private let keyboard = CGRect(x: 0, y: 0, width: 390, height: 290)
    /// The clamp limits: `edgeMargin` inside the keyboard on every side.
    private var limits: CGRect {
        keyboard.insetBy(
            dx: AlternatesPopupPlacement.edgeMargin,
            dy: AlternatesPopupPlacement.edgeMargin)
    }
    /// A single-alternate popup (en-US `ɹ` → `r`): one 36-pt cell plus
    /// padding.
    private let singleCellPopup = CGSize(width: 48, height: 52)
    /// A three-alternate popup, wide enough to need the horizontal clamp
    /// near the keyboard's edges.
    private let threeCellPopup = CGSize(width: 128, height: 52)

    // MARK: Preferred placement (room on every side)

    @Test func midKeyboardKeyGetsACenteredPopupAboveTheCap() {
        let key = CGRect(x: 150, y: 120, width: 40, height: 50)
        let frame = AlternatesPopupPlacement.popupFrame(
            popupSize: singleCellPopup, keyFrame: key, keyboardBounds: keyboard)
        // Centered on the key, floating `capClearance` clear of the cap's
        // top — over the row above, like the system keyboard's popup.
        #expect(frame.midX == key.midX)
        #expect(frame.maxY == key.minY - AlternatesPopupPlacement.capClearance)
        #expect(frame.size == singleCellPopup)
        #expect(limits.contains(frame))
    }

    @Test func secondRowPopupStillFitsAboveTheCap() {
        // Row 1 (y = 62) is the tightest unclamped fit: the popup's top
        // (62 − 4 − 52 = 6) still clears the margin line.
        let key = CGRect(x: 150, y: 62, width: 40, height: 50)
        let frame = AlternatesPopupPlacement.popupFrame(
            popupSize: singleCellPopup, keyFrame: key, keyboardBounds: keyboard)
        #expect(frame.midX == key.midX)
        #expect(frame.maxY == key.minY - AlternatesPopupPlacement.capClearance)
        #expect(limits.contains(frame))
    }

    // MARK: Clamping

    @Test func topRowKeyShiftsThePopupDownIntoBounds() {
        // A top-row key has no room above it inside the keyboard, so the
        // popup pins to the top margin and covers its own cap — above the
        // pressed key like every other row, never flipped below it into
        // the next row (the issue #122 regression).
        let key = CGRect(x: 150, y: 4, width: 40, height: 50)
        let frame = AlternatesPopupPlacement.popupFrame(
            popupSize: singleCellPopup, keyFrame: key, keyboardBounds: keyboard)
        #expect(frame.minY == limits.minY)
        #expect(frame.midX == key.midX)
        // In-frame placement necessarily overlaps the cap it belongs to…
        #expect(frame.maxY > key.minY)
        // …but never dips below the pressed key's row.
        #expect(frame.maxY <= key.maxY + AlternatesPopupPlacement.capClearance)
        #expect(limits.contains(frame))
    }

    @Test func compactMetricsTopRowPopupStaysInBounds() {
        // iPhone-landscape metrics: 34-pt rows, 5-pt spacing, 3-pt outer
        // padding — a 196-pt-tall five-row keyboard. The clamped popup is
        // taller than the top row, spilling into the second row's area
        // (the z-order raise in `KeyboardView` keeps it in front); the
        // placement itself just has to stay inside the keyboard.
        let compactKeyboard = CGRect(x: 0, y: 0, width: 390, height: 196)
        let key = CGRect(x: 150, y: 3, width: 40, height: 34)
        let frame = AlternatesPopupPlacement.popupFrame(
            popupSize: singleCellPopup, keyFrame: key, keyboardBounds: compactKeyboard)
        let compactLimits = compactKeyboard.insetBy(
            dx: AlternatesPopupPlacement.edgeMargin,
            dy: AlternatesPopupPlacement.edgeMargin)
        #expect(frame.minY == compactLimits.minY)
        #expect(compactLimits.contains(frame))
    }

    @Test func leftEdgeKeyShiftsThePopupRightIntoBounds() {
        let key = CGRect(x: 4, y: 120, width: 40, height: 50)
        let frame = AlternatesPopupPlacement.popupFrame(
            popupSize: threeCellPopup, keyFrame: key, keyboardBounds: keyboard)
        #expect(frame.minX == limits.minX)
        // Vertical placement is untouched by a horizontal clamp.
        #expect(frame.maxY == key.minY - AlternatesPopupPlacement.capClearance)
        #expect(limits.contains(frame))
    }

    @Test func rightEdgeKeyShiftsThePopupLeftIntoBounds() {
        let key = CGRect(x: 346, y: 120, width: 40, height: 50)
        let frame = AlternatesPopupPlacement.popupFrame(
            popupSize: threeCellPopup, keyFrame: key, keyboardBounds: keyboard)
        #expect(frame.maxX == limits.maxX)
        #expect(frame.maxY == key.minY - AlternatesPopupPlacement.capClearance)
        #expect(limits.contains(frame))
    }

    @Test func topLeftCornerKeyClampsOnBothAxes() {
        let key = CGRect(x: 4, y: 4, width: 40, height: 50)
        let frame = AlternatesPopupPlacement.popupFrame(
            popupSize: threeCellPopup, keyFrame: key, keyboardBounds: keyboard)
        #expect(frame.minX == limits.minX)
        #expect(frame.minY == limits.minY)
        #expect(limits.contains(frame))
    }

    @Test func oversizedPopupClampsToTheTopLeadingEdges() {
        // Degenerate input (never the case for real layouts): a popup that
        // cannot fit still yields a deterministic frame anchored to the
        // top-leading margin instead of a negative-origin one.
        let tiny = CGRect(x: 0, y: 0, width: 60, height: 40)
        let key = CGRect(x: 10, y: 4, width: 40, height: 30)
        let frame = AlternatesPopupPlacement.popupFrame(
            popupSize: CGSize(width: 100, height: 100),
            keyFrame: key, keyboardBounds: tiny)
        let tinyLimits = tiny.insetBy(
            dx: AlternatesPopupPlacement.edgeMargin,
            dy: AlternatesPopupPlacement.edgeMargin)
        #expect(frame.origin == CGPoint(x: tinyLimits.minX, y: tinyLimits.minY))
    }

    @Test func everyKeyPositionYieldsAFullyInBoundsPopup() {
        // Sweep a key across the whole keyboard, corners included: the
        // popup must never poke past the margin line on any side.
        for x in stride(from: CGFloat(0), through: 350, by: 34.6) {
            for y in stride(from: CGFloat(0), through: 240, by: 29.5) {
                let key = CGRect(x: x, y: y, width: 40, height: 50)
                let frame = AlternatesPopupPlacement.popupFrame(
                    popupSize: threeCellPopup, keyFrame: key, keyboardBounds: keyboard)
                #expect(limits.contains(frame), "key at (\(x), \(y))")
            }
        }
    }
}
