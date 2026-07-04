//
//  KeyPreviewPlacement.swift
//  IPAKeyboardKit
//
//  Pure geometry for the key-press preview balloon (issue #71): how large
//  the balloon is for a given key cap, and where it sits. A custom keyboard
//  cannot draw outside its own view — anything past the edge is clipped by
//  the system, not drawn over the host app like the system keyboard's
//  balloons — so the placement clamps the balloon fully inside the
//  keyboard's bounds. Extracted from `KeyboardView` so the rules are
//  unit-testable; all coordinates are in the keyboard view's own space.
//

import CoreGraphics

enum KeyPreviewPlacement {

    /// How far the balloon extends past the key cap on each side.
    static let horizontalOutset: CGFloat = 12
    /// How much taller than the key cap the balloon is.
    static let verticalOutset: CGFloat = 10
    /// How far the balloon's bottom edge reaches down over the key cap's
    /// top, visually connecting the two like the system keyboard's balloon.
    static let capOverlap: CGFloat = 4
    /// Minimum inset kept between the balloon and the keyboard's edges.
    static let edgeMargin: CGFloat = 2

    /// The balloon's size for a pressed key cap: a little wider and taller
    /// than the cap, so the magnified glyph reads clearly without covering
    /// the neighboring keys' own caps.
    static func balloonSize(forKeyCap keyCap: CGSize) -> CGSize {
        CGSize(
            width: keyCap.width + horizontalOutset * 2,
            height: keyCap.height + verticalOutset)
    }

    /// Where the balloon renders for the pressed key at `keyFrame`, in the
    /// same coordinate space as `keyboardBounds`.
    ///
    /// Preferred placement is centered over the key with the balloon's
    /// bottom overlapping the cap's top by `capOverlap` — floating above
    /// the touch, over the row above. The frame is then clamped to stay at
    /// least `edgeMargin` inside `keyboardBounds` on every side: edge keys
    /// shift the balloon inward, and top-row keys (no room above within the
    /// keyboard) shift it down over their own cap. If the balloon cannot
    /// fit at all (never the case for real layouts), the top-leading edges
    /// win the clamp.
    static func balloonFrame(
        keyFrame: CGRect,
        keyboardBounds: CGRect
    ) -> CGRect {
        let size = balloonSize(forKeyCap: keyFrame.size)
        let limits = keyboardBounds.insetBy(dx: edgeMargin, dy: edgeMargin)
        var origin = CGPoint(
            x: keyFrame.midX - size.width / 2,
            y: keyFrame.minY + capOverlap - size.height)
        origin.x = max(min(origin.x, limits.maxX - size.width), limits.minX)
        origin.y = max(min(origin.y, limits.maxY - size.height), limits.minY)
        return CGRect(origin: origin, size: size)
    }
}
