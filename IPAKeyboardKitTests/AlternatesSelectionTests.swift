//
//  AlternatesSelectionTests.swift
//  IPAKeyboardKitTests
//
//  Verifies the pure hit-testing behind the long-press alternates popup
//  (issue #104): slide-to-highlight matching with touch slop and
//  nearest-cell tie-breaking, and release classification (alternate / base
//  key / dismiss). The fixture geometry mirrors the rendered popup — 36×40
//  cells 4 pt apart, floating 56 pt above a 44×50 key cap whose top-left
//  corner is the coordinate origin.
//

import CoreGraphics
import Testing
@testable import IPAKeyboardKit

struct AlternatesSelectionTests {

    /// A 44×50 key cap at the origin with two popup cells centered above
    /// it: cell 0 spans x ∈ [-16, 20], cell 1 spans x ∈ [24, 60], both
    /// spanning y ∈ [-50, -10].
    private let keyCap = CGRect(x: 0, y: 0, width: 44, height: 50)
    private let cells = [
        CGRect(x: -16, y: -50, width: 36, height: 40),
        CGRect(x: 24, y: -50, width: 36, height: 40),
    ]

    // MARK: Highlighting while the finger slides

    @Test func fingerInsideACellHighlightsIt() {
        #expect(AlternatesSelection.highlightedIndex(
            at: CGPoint(x: 2, y: -30), cellFrames: cells) == 0)
        #expect(AlternatesSelection.highlightedIndex(
            at: CGPoint(x: 42, y: -30), cellFrames: cells) == 1)
    }

    @Test func gapBetweenCellsResolvesToTheNearestCellCenter() {
        // x = 21 and x = 23 both sit in the 4-pt gap, inside both expanded
        // frames; the nearer center (cell 0 at x = 2, cell 1 at x = 42) wins.
        #expect(AlternatesSelection.highlightedIndex(
            at: CGPoint(x: 21, y: -30), cellFrames: cells) == 0)
        #expect(AlternatesSelection.highlightedIndex(
            at: CGPoint(x: 23, y: -30), cellFrames: cells) == 1)
    }

    @Test func slopExtendsEachCellsReach() {
        // 8 pt below cell 0's bottom edge (y = -10): within the 12-pt slop,
        // so a slide that stops just short of the popup still selects.
        #expect(AlternatesSelection.highlightedIndex(
            at: CGPoint(x: 2, y: -2), cellFrames: cells) == 0)
    }

    @Test func fingerBeyondTheSlopHighlightsNothing() {
        // Well inside the key cap (below the popup's slop band).
        #expect(AlternatesSelection.highlightedIndex(
            at: CGPoint(x: 2, y: 20), cellFrames: cells) == nil)
        // Off the popup's left end.
        #expect(AlternatesSelection.highlightedIndex(
            at: CGPoint(x: -40, y: -30), cellFrames: cells) == nil)
    }

    @Test func unmeasuredFramesNeverMatch() {
        let unmeasured: [CGRect] = [.null, .null]
        #expect(AlternatesSelection.highlightedIndex(
            at: CGPoint(x: 2, y: -30), cellFrames: unmeasured) == nil)
    }

    // MARK: Release classification

    @Test func releaseOnACellCommitsThatAlternate() {
        #expect(AlternatesSelection.releaseTarget(
            at: CGPoint(x: 42, y: -30), cellFrames: cells, keyCapBounds: keyCap)
            == .alternate(1))
    }

    @Test func releaseOnTheKeyCapCommitsTheBaseKey() {
        #expect(AlternatesSelection.releaseTarget(
            at: CGPoint(x: 22, y: 25), cellFrames: cells, keyCapBounds: keyCap)
            == .baseKey)
    }

    @Test func releaseJustOffTheKeyCapStillCommitsTheBaseKey() {
        // 6 pt right of and 5 pt below the cap: within its slop.
        #expect(AlternatesSelection.releaseTarget(
            at: CGPoint(x: 50, y: 55), cellFrames: cells, keyCapBounds: keyCap)
            == .baseKey)
    }

    @Test func releaseWithoutADragSampleCommitsTheBaseKey() {
        // The finger lifted right as the popup opened, before the drag
        // phase delivered a location — it was still on the key cap.
        #expect(AlternatesSelection.releaseTarget(
            at: nil, cellFrames: cells, keyCapBounds: keyCap) == .baseKey)
    }

    @Test func releaseFarAwayDismissesWithoutTyping() {
        #expect(AlternatesSelection.releaseTarget(
            at: CGPoint(x: 22, y: 120), cellFrames: cells, keyCapBounds: keyCap)
            == .dismiss)
        #expect(AlternatesSelection.releaseTarget(
            at: CGPoint(x: -80, y: 25), cellFrames: cells, keyCapBounds: keyCap)
            == .dismiss)
    }

    @Test func aCellBeatsTheKeyCapWhereSlopRegionsOverlap() {
        // y = -8 is within slop of both cell 0's bottom edge (-10) and the
        // key cap's top edge (0); the popup cell wins, so slides that stop
        // just short of a cell still select it.
        #expect(AlternatesSelection.releaseTarget(
            at: CGPoint(x: 2, y: -8), cellFrames: cells, keyCapBounds: keyCap)
            == .alternate(0))
    }

    @Test func cellsClampedOverTheCapWinOverTheBaseKey() {
        // Top-row keys clamp the popup down over their own cap — there is
        // no headroom inside the keyboard (issue #122) — so the cells and
        // the cap overlap. The visible highlight is the source of truth:
        // a release on the cap commits the highlighted cell, not the base
        // key, exactly what the popup showed the finger resting on.
        let overlapping = [
            CGRect(x: -16, y: -2, width: 36, height: 40),
            CGRect(x: 24, y: -2, width: 36, height: 40),
        ]
        #expect(AlternatesSelection.releaseTarget(
            at: CGPoint(x: 2, y: 20), cellFrames: overlapping, keyCapBounds: keyCap)
            == .alternate(0))
    }
}
