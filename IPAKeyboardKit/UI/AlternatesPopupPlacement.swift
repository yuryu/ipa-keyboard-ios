//
//  AlternatesPopupPlacement.swift
//  IPAKeyboardKit
//
//  Pure geometry for the long-press alternates popup (issue #122): where
//  the measured popup sits relative to the pressed key. Every row places
//  the popup the same way — floating above the key cap, like the system
//  keyboard — and, because a custom keyboard cannot draw outside its own
//  view, the frame is clamped fully inside the keyboard's bounds: edge
//  keys shift it inward, and top-row keys (no room above within the
//  keyboard) shift it down over their own cap, exactly like the key-press
//  preview balloon (`KeyPreviewPlacement`). Extracted from `KeyboardView`
//  so the rules are unit-testable; all coordinates are in the keyboard
//  view's own space.
//

import CoreGraphics

enum AlternatesPopupPlacement {

    /// Gap kept between the popup's bottom edge and the key cap's top, so
    /// the popup floats clear of the cap (and of the finger on it).
    static let capClearance: CGFloat = 4
    /// Minimum inset kept between the popup and the keyboard's edges.
    static let edgeMargin: CGFloat = 2

    /// Where the popup renders for the pressed key at `keyFrame`, in the
    /// same coordinate space as `keyboardBounds`. `popupSize` is the
    /// popup's measured natural size — it self-sizes to its cells, so the
    /// size is an input here, not derived from the key cap the way
    /// `KeyPreviewPlacement.balloonSize` is.
    ///
    /// Preferred placement is centered over the key with the popup's
    /// bottom `capClearance` above the cap's top — floating above the
    /// touch, over the row above. The frame is then clamped to stay at
    /// least `edgeMargin` inside `keyboardBounds` on every side: edge keys
    /// shift the popup inward, and top-row keys (no room above within the
    /// keyboard) shift it down over their own cap. If the popup cannot fit
    /// at all (never the case for real layouts), the top-leading edges win
    /// the clamp.
    static func popupFrame(
        popupSize: CGSize,
        keyFrame: CGRect,
        keyboardBounds: CGRect
    ) -> CGRect {
        let limits = keyboardBounds.insetBy(dx: edgeMargin, dy: edgeMargin)
        var origin = CGPoint(
            x: keyFrame.midX - popupSize.width / 2,
            y: keyFrame.minY - capClearance - popupSize.height)
        origin.x = max(min(origin.x, limits.maxX - popupSize.width), limits.minX)
        origin.y = max(min(origin.y, limits.maxY - popupSize.height), limits.minY)
        return CGRect(origin: origin, size: popupSize)
    }
}
