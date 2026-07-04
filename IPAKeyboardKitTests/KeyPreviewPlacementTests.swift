//
//  KeyPreviewPlacementTests.swift
//  IPAKeyboardKitTests
//
//  Verifies the pure placement rules behind the key-press preview balloon
//  (issue #71): sized up from the key cap, centered above the touch, and —
//  because a custom keyboard cannot draw outside its own view — always
//  clamped fully inside the keyboard's bounds, with edge keys shifting the
//  balloon inward and top-row keys shifting it down. The fixture geometry
//  mirrors the default `KeyboardMetrics`: 50-pt rows, 8-pt row spacing,
//  4-pt outer padding, on a 390-pt-wide iPhone keyboard.
//

import CoreGraphics
import Testing
@testable import IPAKeyboardKit

struct KeyPreviewPlacementTests {

    /// A five-row default-metrics keyboard: 390 × 290 with its origin at
    /// the top-left, rows at y = 4, 62, 120, …
    private let keyboard = CGRect(x: 0, y: 0, width: 390, height: 290)
    /// The clamp limits: `edgeMargin` inside the keyboard on every side.
    private var limits: CGRect {
        keyboard.insetBy(
            dx: KeyPreviewPlacement.edgeMargin,
            dy: KeyPreviewPlacement.edgeMargin)
    }

    // MARK: Size

    @Test func balloonOutgrowsTheKeyCapOnEverySide() {
        let size = KeyPreviewPlacement.balloonSize(
            forKeyCap: CGSize(width: 40, height: 50))
        #expect(size.width == 40 + KeyPreviewPlacement.horizontalOutset * 2)
        #expect(size.height == 50 + KeyPreviewPlacement.verticalOutset)
    }

    @Test func balloonSizeTracksCompactKeyCaps() {
        // iPhone-landscape metrics use 34-pt rows; the balloon shrinks with
        // the cap instead of using fixed dimensions.
        let size = KeyPreviewPlacement.balloonSize(
            forKeyCap: CGSize(width: 40, height: 34))
        #expect(size.height == 34 + KeyPreviewPlacement.verticalOutset)
    }

    // MARK: Preferred placement (room on every side)

    @Test func midKeyboardKeyGetsACenteredBalloonAboveTheCap() {
        let key = CGRect(x: 150, y: 120, width: 40, height: 50)
        let frame = KeyPreviewPlacement.balloonFrame(
            keyFrame: key, keyboardBounds: keyboard)
        // Centered on the key, bottom edge overlapping the cap's top — the
        // glyph floats above the touch, over the row above.
        #expect(frame.midX == key.midX)
        #expect(frame.maxY == key.minY + KeyPreviewPlacement.capOverlap)
        #expect(frame.size == KeyPreviewPlacement.balloonSize(forKeyCap: key.size))
        #expect(limits.contains(frame))
    }

    @Test func secondRowBalloonStaysInsideTheKeyboardTop() {
        // Row 1 (y = 62) is the tightest unclamped fit: the balloon's top
        // lands exactly on the margin line.
        let key = CGRect(x: 150, y: 62, width: 40, height: 50)
        let frame = KeyPreviewPlacement.balloonFrame(
            keyFrame: key, keyboardBounds: keyboard)
        #expect(frame.midX == key.midX)
        #expect(frame.maxY == key.minY + KeyPreviewPlacement.capOverlap)
        #expect(limits.contains(frame))
    }

    // MARK: Clamping

    @Test func topRowKeyShiftsTheBalloonDownIntoBounds() {
        // A top-row key has no room above it inside the keyboard, so the
        // balloon pins to the top margin and covers its own cap instead of
        // being clipped by the system.
        let key = CGRect(x: 150, y: 4, width: 40, height: 50)
        let frame = KeyPreviewPlacement.balloonFrame(
            keyFrame: key, keyboardBounds: keyboard)
        #expect(frame.minY == limits.minY)
        #expect(frame.midX == key.midX)
        #expect(limits.contains(frame))
    }

    @Test func leftEdgeKeyShiftsTheBalloonRightIntoBounds() {
        let key = CGRect(x: 4, y: 120, width: 40, height: 50)
        let frame = KeyPreviewPlacement.balloonFrame(
            keyFrame: key, keyboardBounds: keyboard)
        #expect(frame.minX == limits.minX)
        // Vertical placement is untouched by a horizontal clamp.
        #expect(frame.maxY == key.minY + KeyPreviewPlacement.capOverlap)
        #expect(limits.contains(frame))
    }

    @Test func rightEdgeKeyShiftsTheBalloonLeftIntoBounds() {
        let key = CGRect(x: 346, y: 120, width: 40, height: 50)
        let frame = KeyPreviewPlacement.balloonFrame(
            keyFrame: key, keyboardBounds: keyboard)
        #expect(frame.maxX == limits.maxX)
        #expect(frame.maxY == key.minY + KeyPreviewPlacement.capOverlap)
        #expect(limits.contains(frame))
    }

    @Test func topLeftCornerKeyClampsOnBothAxes() {
        let key = CGRect(x: 4, y: 4, width: 40, height: 50)
        let frame = KeyPreviewPlacement.balloonFrame(
            keyFrame: key, keyboardBounds: keyboard)
        #expect(frame.minX == limits.minX)
        #expect(frame.minY == limits.minY)
        #expect(limits.contains(frame))
    }

    @Test func everyKeyPositionYieldsAFullyInBoundsBalloon() {
        // Sweep a key across the whole keyboard, corners included: the
        // balloon must never poke past the margin line on any side.
        for x in stride(from: CGFloat(0), through: 350, by: 34.6) {
            for y in stride(from: CGFloat(0), through: 240, by: 29.5) {
                let key = CGRect(x: x, y: y, width: 40, height: 50)
                let frame = KeyPreviewPlacement.balloonFrame(
                    keyFrame: key, keyboardBounds: keyboard)
                #expect(limits.contains(frame), "key at (\(x), \(y))")
            }
        }
    }
}
