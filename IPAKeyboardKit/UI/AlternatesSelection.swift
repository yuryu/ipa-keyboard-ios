//
//  AlternatesSelection.swift
//  IPAKeyboardKit
//
//  Pure hit-testing for the long-press alternates popup: which cell the
//  sliding finger highlights, and what lifting the finger should commit.
//  Extracted from `KeyboardView` so the geometry rules are unit-testable.
//  All coordinates are in the pressed key's own space (origin at the key
//  cap's top-left corner); the cell frames come from the rendered popup, so
//  the rules track the real layout instead of duplicating its constants.
//

import CoreGraphics

enum AlternatesSelection {

    /// How far outside a frame a touch still counts as inside it. Bridges
    /// the visual gaps between the popup cells, and between the popup and
    /// the key cap, so slightly imprecise fingers still land.
    static let touchSlop: CGFloat = 12

    /// What lifting the finger should do.
    enum ReleaseTarget: Equatable {
        /// Commit the alternate at this index into the popup's cells.
        case alternate(Int)
        /// Commit the key's own action (the finger never left the key cap,
        /// or the popup opened and closed without a drag sample).
        case baseKey
        /// Close the popup and type nothing (released away from both).
        case dismiss
    }

    /// The index of the popup cell under `location`, or nil when the finger
    /// is over none of them. Frames are matched with `slop` tolerance; where
    /// expanded frames overlap, the nearest cell center wins. Unmeasured
    /// (`.null`) frames never match.
    static func highlightedIndex(
        at location: CGPoint,
        cellFrames: [CGRect],
        slop: CGFloat = touchSlop
    ) -> Int? {
        var best: (index: Int, squaredDistance: CGFloat)?
        for (index, frame) in cellFrames.enumerated() {
            guard !frame.isNull,
                  frame.insetBy(dx: -slop, dy: -slop).contains(location)
            else { continue }
            let dx = location.x - frame.midX
            let dy = location.y - frame.midY
            let squared = dx * dx + dy * dy
            if best == nil || squared < best!.squaredDistance {
                best = (index, squared)
            }
        }
        return best?.index
    }

    /// Classifies a finger release. A nil `location` means the drag phase
    /// never delivered a value — the finger lifted right as the popup
    /// opened, still on the key cap — so it commits the base key, like the
    /// system keyboard's pre-highlighted popup does.
    static func releaseTarget(
        at location: CGPoint?,
        cellFrames: [CGRect],
        keyCapBounds: CGRect,
        slop: CGFloat = touchSlop
    ) -> ReleaseTarget {
        guard let location else { return .baseKey }
        if let index = highlightedIndex(at: location, cellFrames: cellFrames, slop: slop) {
            return .alternate(index)
        }
        if keyCapBounds.insetBy(dx: -slop, dy: -slop).contains(location) {
            return .baseKey
        }
        return .dismiss
    }
}
