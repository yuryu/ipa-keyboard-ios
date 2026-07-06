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

/// A cursor-mode lifecycle event from the space bar's trackpad-style drag,
/// delivered through `KeyboardView`'s `onCursorMove` callback.
///
/// The lifecycle matters, not just the steps: `adjustTextPosition` round-
/// trips to the host process and the proxy's `documentContextBeforeInput`/
/// `AfterInput` windows update asynchronously, so a consumer that re-read
/// them per step could compute step N+1 from pre-step-N context and park
/// the cursor inside a combining sequence. `began` (the completed hold,
/// before any movement — the document has been quiet for the whole hold, so
/// the context is settled) is the one safe moment to snapshot the context
/// into a `CursorMovement.Context`; `ended` (finger up or cancelled)
/// discards it.
public enum CursorMoveEvent: Equatable, Sendable {
    /// Cursor mode engaged (the 0.3 s hold completed); no movement yet.
    case began
    /// The drag crossed `steps` more grid cells: positive right, negative
    /// left. Only sent for non-zero steps.
    case moved(steps: Int)
    /// The finger lifted or the gesture was cancelled; cursor mode ends.
    case ended
}

/// Grapheme-cluster-aware cursor offsets for
/// `UITextDocumentProxy.adjustTextPosition(byCharacterOffset:)`.
///
/// Despite its parameter name, `adjustTextPosition` counts **UTF-16 code
/// units** (UIKit text positions are `NSString`-indexed; confirmed
/// empirically on the iOS 26.5 simulator — see
/// `SystemKeyboardSmokeUITests`), not user-perceived characters — so moving
/// "one character" over a base glyph plus combining diacritics, or over a
/// non-BMP scalar, needs an offset larger than 1.
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
    /// cannot measure. Returns 0 when there is nowhere to move.
    ///
    /// Stateless convenience over `Context` for a *single* read-compute-apply
    /// round. Successive calls against re-read proxy context are unsafe (the
    /// windows update asynchronously after `adjustTextPosition`); a drag
    /// session must instead seed one `Context` and step it locally.
    public static func utf16Offset(
        steps: Int,
        contextBefore: String?,
        contextAfter: String?
    ) -> Int {
        var context = Context(contextBefore: contextBefore, contextAfter: contextAfter)
        return context.utf16Offset(steps: steps)
    }

    /// A local mirror of the document context around the insertion point,
    /// kept for the duration of one cursor-mode drag.
    ///
    /// `adjustTextPosition(byCharacterOffset:)` round-trips to the host app,
    /// and the proxy's context windows update asynchronously — the proxy
    /// cannot fully re-slice its limited cached window locally the way it
    /// can for `insertText`/`deleteBackward`. A sustained drag emits a step
    /// every few milliseconds, so recomputing each step's offset from a
    /// fresh `documentContextBeforeInput`/`AfterInput` read can act on
    /// pre-previous-step context and split a grapheme cluster — the exact
    /// defect this feature exists to prevent. The mirror is seeded once,
    /// when cursor mode engages (the hold guarantees the document has been
    /// quiet, so the snapshot is settled), then advanced locally: each step
    /// moves whole grapheme clusters between the before/after sides, which
    /// is exactly how the real context evolves for pure cursor movement over
    /// an unchanged document.
    ///
    /// Movement clamps to the seeded window on each side. That bounds a
    /// single drag to what was visible when the hold began — in practice not
    /// a limit, because one drag is itself bounded by the keyboard's width
    /// (~48 steps across an iPhone), far less than the proxy's typical
    /// sentence-or-paragraph window — and every new hold re-seeds fresh.
    public struct Context: Equatable, Sendable {
        /// The mirrored text left of the insertion point.
        public private(set) var contextBefore: String
        /// The mirrored text right of the insertion point.
        public private(set) var contextAfter: String

        /// Seeds the mirror from the proxy's context windows (`nil` — nothing
        /// visible on that side — mirrors as empty).
        public init(contextBefore: String?, contextAfter: String?) {
            self.contextBefore = contextBefore ?? ""
            self.contextAfter = contextAfter ?? ""
        }

        /// Returns the value to pass to `adjustTextPosition(byCharacterOffset:)`
        /// for `steps` user-perceived characters of movement, and advances the
        /// mirror by the same clusters so the next call continues from the
        /// new cursor position without re-reading the proxy.
        ///
        /// Clusters re-form at the seam exactly as they would in the real
        /// document: e.g. stepping right from inside a base+mark sequence
        /// escapes just the mark, after which the reunited cluster on the
        /// before side traverses as one unit. Clamps to the mirrored window;
        /// returns 0 when there is nowhere to move.
        public mutating func utf16Offset(steps: Int) -> Int {
            if steps > 0 {
                let crossed = contextAfter.prefix(steps)
                guard !crossed.isEmpty else { return 0 }
                let moved = String(crossed)
                contextAfter.removeSubrange(crossed.startIndex..<crossed.endIndex)
                contextBefore.append(moved)
                return moved.utf16.count
            }
            if steps < 0 {
                let magnitude = Int(clamping: steps.magnitude)
                let crossed = contextBefore.suffix(magnitude)
                guard !crossed.isEmpty else { return 0 }
                let moved = String(crossed)
                contextBefore.removeSubrange(crossed.startIndex..<crossed.endIndex)
                contextAfter.insert(contentsOf: moved, at: contextAfter.startIndex)
                return -moved.utf16.count
            }
            return 0
        }
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
