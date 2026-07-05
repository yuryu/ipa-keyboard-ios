//
//  CursorMovement.swift
//  IPAKeyboardKit
//
//  The pure logic behind the space bar's trackpad-style cursor mode
//  (issue #70): quantizing a horizontal drag into cursor steps, and turning
//  those steps into the offsets `UITextDocumentProxy` expects. Both live
//  here as plain values/functions so they are unit-testable without the
//  extension runtime, like `GraphemeText` and `KeyRepeatCadence`.
//

import CoreGraphics
import Foundation

/// Grapheme-cluster-aware cursor offsets for
/// `UITextDocumentProxy.adjustTextPosition(byCharacterOffset:)`.
///
/// Despite its parameter name, `adjustTextPosition` counts **UTF-16 code
/// units** (UIKit text positions are `NSString`-indexed), not user-perceived
/// characters — so moving "one character" over a base glyph plus combining
/// diacritics, or over a non-BMP scalar, needs an offset larger than 1.
/// These helpers compute the correct offset from the visible document
/// context so one cursor step always traverses one whole grapheme cluster
/// and can never land inside a combining sequence — the cursor-movement
/// twin of `GraphemeText.deletionScalarCount(before:)`.
public enum CursorMovement {
    /// The value to pass to `adjustTextPosition(byCharacterOffset:)` to move
    /// the insertion point by `steps` user-perceived characters: negative
    /// steps walk left through the trailing grapheme clusters of
    /// `contextBefore`, positive steps walk right through the leading
    /// clusters of `contextAfter`.
    ///
    /// Movement clamps to the visible context (the proxy exposes a limited
    /// window around the cursor, and `nil` means nothing is visible on that
    /// side), so a burst of steps never overshoots into text the caller
    /// cannot measure — the next drag sample sees fresh context and
    /// continues from there. Returns 0 when there is nowhere to move.
    public static func utf16Offset(
        steps: Int,
        contextBefore: String?,
        contextAfter: String?
    ) -> Int {
        if steps > 0 {
            guard let after = contextAfter else { return 0 }
            return after.prefix(steps).reduce(0) { $0 + $1.utf16.count }
        }
        if steps < 0 {
            guard let before = contextBefore else { return 0 }
            let magnitude = Int(clamping: steps.magnitude)
            return before.suffix(magnitude).reduce(0) { $0 - $1.utf16.count }
        }
        return 0
    }
}

/// Quantizes the space bar's cursor-mode drag into whole cursor steps, like
/// the system keyboard's trackpad mode: every `pointsPerStep` points of
/// horizontal travel is one step, right positive, left negative.
///
/// Feed it the finger's absolute horizontal position (any coordinate space,
/// as long as it is consistent for the life of one drag). The first sample
/// anchors the gesture; each later sample returns only the steps newly
/// crossed, so the caller emits them incrementally. The anchor advances by
/// the points consumed — reversing direction first crosses back over the
/// remainder of the current cell, giving the same gentle hysteresis as a
/// grid.
public struct CursorDragStepper: Sendable {
    /// Points of horizontal travel per cursor step. The default is tuned to
    /// the system trackpad's feel: ~8 pt per character puts a full-width
    /// swipe across an iPhone keyboard at roughly 48 characters. Points are
    /// density-independent, so the same value feels consistent on iPad.
    public var pointsPerStep: CGFloat

    public static let defaultPointsPerStep: CGFloat = 8

    /// The horizontal position corresponding to zero pending movement;
    /// `nil` until the first sample anchors the drag.
    private var anchorX: CGFloat?

    public init(pointsPerStep: CGFloat = CursorDragStepper.defaultPointsPerStep) {
        self.pointsPerStep = pointsPerStep
    }

    /// Consume a position sample and return the whole steps crossed since
    /// the last emission (+right / −left). The first sample anchors the
    /// drag and always returns 0.
    public mutating func steps(movingTo x: CGFloat) -> Int {
        guard let anchor = anchorX else {
            anchorX = x
            return 0
        }
        guard pointsPerStep > 0 else { return 0 }
        let steps = Int(((x - anchor) / pointsPerStep).rounded(.towardZero))
        if steps != 0 {
            anchorX = anchor + CGFloat(steps) * pointsPerStep
        }
        return steps
    }
}
