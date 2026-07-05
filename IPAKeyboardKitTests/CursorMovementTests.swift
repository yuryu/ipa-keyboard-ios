//
//  CursorMovementTests.swift
//  IPAKeyboardKitTests
//
//  Verifies the space bar's trackpad-style cursor mode logic (issue #70):
//  the grapheme-cluster-aware UTF-16 offsets fed to
//  `adjustTextPosition(byCharacterOffset:)`, and the drag-to-steps
//  quantization policy.
//

import CoreGraphics
import Testing
@testable import IPAKeyboardKit

struct CursorMovementTests {

    // MARK: Degenerate inputs

    @Test func zeroStepsMovesNothing() {
        let offset = CursorMovement.utf16Offset(
            steps: 0, contextBefore: "abc", contextAfter: "def")
        #expect(offset == 0)
    }

    @Test func nilContextMovesNothing() {
        let left = CursorMovement.utf16Offset(
            steps: -1, contextBefore: nil, contextAfter: "abc")
        let right = CursorMovement.utf16Offset(
            steps: 1, contextBefore: "abc", contextAfter: nil)
        #expect(left == 0)
        #expect(right == 0)
    }

    @Test func emptyContextMovesNothing() {
        let left = CursorMovement.utf16Offset(
            steps: -1, contextBefore: "", contextAfter: "abc")
        let right = CursorMovement.utf16Offset(
            steps: 1, contextBefore: "abc", contextAfter: "")
        #expect(left == 0)
        #expect(right == 0)
    }

    // MARK: Single steps

    @Test func asciiStepsAreOneCodeUnit() {
        let left = CursorMovement.utf16Offset(
            steps: -1, contextBefore: "abc", contextAfter: "def")
        let right = CursorMovement.utf16Offset(
            steps: 1, contextBefore: "abc", contextAfter: "def")
        #expect(left == -1)
        #expect(right == 1)
    }

    @Test func combiningSequenceStepsAsOneCluster() {
        // ə U+0259 + combining tilde U+0303 (nasalized schwa): one grapheme,
        // two UTF-16 code units. One step must traverse both so the cursor
        // never lands between the base glyph and its diacritic.
        let nasalizedSchwa = "\u{0259}\u{0303}"
        #expect(nasalizedSchwa.count == 1)
        let left = CursorMovement.utf16Offset(
            steps: -1, contextBefore: "p\(nasalizedSchwa)", contextAfter: "t")
        let right = CursorMovement.utf16Offset(
            steps: 1, contextBefore: "p", contextAfter: "\(nasalizedSchwa)t")
        #expect(left == -2)
        #expect(right == 2)
    }

    @Test func multiMarkClusterMovesAsOneUnit() {
        // "n" + combining vertical line below U+0329 + combining acute
        // U+0301 (stressed syllabic n): one grapheme, three code units.
        let cluster = "n\u{0329}\u{0301}"
        #expect(cluster.count == 1)
        let left = CursorMovement.utf16Offset(
            steps: -1, contextBefore: "bɪt\(cluster)", contextAfter: nil)
        #expect(left == -3)
    }

    @Test func spacingModifierLetterIsItsOwnCluster() {
        // ː U+02D0 (length mark) is a *spacing* modifier letter, not a
        // combining mark — "ɑː" is two graphemes, and one step from the end
        // moves over just the length mark.
        let context = "\u{0251}\u{02D0}"
        #expect(context.count == 2)
        let left = CursorMovement.utf16Offset(
            steps: -1, contextBefore: context, contextAfter: nil)
        #expect(left == -1)
    }

    @Test func nonBMPScalarCountsUTF16CodeUnits() {
        // 👍 U+1F44D is one scalar but a surrogate pair in UTF-16.
        // `adjustTextPosition` counts UTF-16 code units, so stepping over it
        // needs an offset of 2 — this pins that the helper counts code
        // units, not scalars (deletion's unit) or characters.
        let right = CursorMovement.utf16Offset(
            steps: 1, contextBefore: nil, contextAfter: "👍x")
        #expect(right == 2)
    }

    // MARK: Multiple steps

    @Test func multipleStepsSumAdjacentClusters() {
        // "pẽt" — moving two left from the end crosses t (1) then the
        // two-unit nasalized e; moving two right from the start crosses
        // p (1) then the nasalized e.
        let before = "pe\u{0303}t"
        let left = CursorMovement.utf16Offset(
            steps: -2, contextBefore: before, contextAfter: nil)
        let right = CursorMovement.utf16Offset(
            steps: 2, contextBefore: nil, contextAfter: before)
        #expect(left == -3)
        #expect(right == 3)
    }

    @Test func stepsClampToVisibleContext() {
        // The proxy exposes a limited window; a burst of steps must not
        // overshoot past what is measurable.
        let left = CursorMovement.utf16Offset(
            steps: -5, contextBefore: "ab", contextAfter: nil)
        let right = CursorMovement.utf16Offset(
            steps: 5, contextBefore: nil, contextAfter: "e\u{0303}")
        #expect(left == -2)
        #expect(right == 2)
    }
}

/// The per-drag context mirror: successive steps must compute correct
/// offsets *without* re-reading the proxy, whose context windows update
/// asynchronously after `adjustTextPosition` (re-reading is what could
/// split a cluster under a sustained drag — the staleness defect).
struct CursorMovementContextTests {

    @Test func successiveLeftStepsAdvanceLocally() {
        // The staleness scenario: context before cursor is "ə̃a"
        // (U+0259 U+0303 = one cluster, two code units; then "a").
        // Two consecutive single steps left must yield -1 then -2 —
        // a stale re-read would repeat -1 and park the cursor between
        // U+0259 and U+0303.
        var context = CursorMovement.Context(
            contextBefore: "\u{0259}\u{0303}a", contextAfter: nil)
        let first = context.utf16Offset(steps: -1)
        let second = context.utf16Offset(steps: -1)
        #expect(first == -1)
        #expect(second == -2)
        #expect(context.contextBefore.isEmpty)
        #expect(context.contextAfter == "\u{0259}\u{0303}a")
    }

    @Test func successiveRightStepsAdvanceLocally() {
        var context = CursorMovement.Context(
            contextBefore: nil, contextAfter: "\u{0259}\u{0303}a")
        let first = context.utf16Offset(steps: 1)
        let second = context.utf16Offset(steps: 1)
        #expect(first == 2)
        #expect(second == 1)
        #expect(context.contextBefore == "\u{0259}\u{0303}a")
        #expect(context.contextAfter.isEmpty)
    }

    @Test func reversalRetraversesTheSameCluster() {
        // Left over the nasalized schwa, then right again: the same
        // two-code-unit cluster moves back, symmetric in magnitude.
        var context = CursorMovement.Context(
            contextBefore: "p\u{0259}\u{0303}", contextAfter: "t")
        let left = context.utf16Offset(steps: -1)
        let right = context.utf16Offset(steps: 1)
        #expect(left == -2)
        #expect(right == 2)
        #expect(context.contextBefore == "p\u{0259}\u{0303}")
        #expect(context.contextAfter == "t")
    }

    @Test func batchedStepsSumWithinOneCall() {
        // One `.moved` can carry several steps (a fast sample); the batch
        // sums the traversed clusters like the stateless helper does.
        var context = CursorMovement.Context(
            contextBefore: "pe\u{0303}t", contextAfter: nil)
        let offset = context.utf16Offset(steps: -2)
        #expect(offset == -3)
        #expect(context.contextBefore == "p")
        #expect(context.contextAfter == "e\u{0303}t")
    }

    @Test func clampsAtTheWindowEdgeAndStaysClamped() {
        var context = CursorMovement.Context(contextBefore: "ab", contextAfter: nil)
        let clamped = context.utf16Offset(steps: -5)
        let after = context.utf16Offset(steps: -1)
        #expect(clamped == -2)
        #expect(after == 0)
    }

    @Test func nilContextMirrorsAsEmpty() {
        var context = CursorMovement.Context(contextBefore: nil, contextAfter: nil)
        let left = context.utf16Offset(steps: -1)
        let right = context.utf16Offset(steps: 1)
        #expect(left == 0)
        #expect(right == 0)
    }

    @Test func midClusterSeamRejoinsLikeTheRealDocument() {
        // Cursor parked *inside* a base+mark sequence (a host app can place
        // it there): stepping right escapes just the mark (+1), after which
        // the reunited cluster "ẽ" on the before side traverses as one unit
        // (-2) — exactly what a fresh proxy read would report.
        var context = CursorMovement.Context(
            contextBefore: "e", contextAfter: "\u{0303}x")
        let escape = context.utf16Offset(steps: 1)
        let back = context.utf16Offset(steps: -1)
        #expect(escape == 1)
        #expect(back == -2)
        #expect(context.contextBefore.isEmpty)
        #expect(context.contextAfter == "e\u{0303}x")
    }

    @Test func statelessHelperMatchesASingleContextStep() {
        // The static helper is a one-shot convenience over Context; the two
        // must never disagree on a first step.
        let before = "pe\u{0303}"
        let after = "\u{0251}\u{02D0}t"
        var context = CursorMovement.Context(contextBefore: before, contextAfter: after)
        let stateless = CursorMovement.utf16Offset(
            steps: -1, contextBefore: before, contextAfter: after)
        let stateful = context.utf16Offset(steps: -1)
        #expect(stateful == stateless)
    }
}

struct CursorDragStepperTests {

    @Test func firstSampleAnchorsWithoutStepping() {
        var stepper = CursorDragStepper()
        let steps = stepper.steps(movingTo: 500)
        #expect(steps == 0)
    }

    @Test func subThresholdMovementEmitsNoSteps() {
        var stepper = CursorDragStepper(pointsPerStep: 8)
        _ = stepper.steps(movingTo: 0)
        let steps = stepper.steps(movingTo: 7.9)
        #expect(steps == 0)
    }

    @Test func crossingThresholdEmitsOneStep() {
        var stepper = CursorDragStepper(pointsPerStep: 8)
        _ = stepper.steps(movingTo: 0)
        let steps = stepper.steps(movingTo: 8)
        #expect(steps == 1)
    }

    @Test func fastDragEmitsMultipleSteps() {
        var stepper = CursorDragStepper(pointsPerStep: 8)
        _ = stepper.steps(movingTo: 0)
        let steps = stepper.steps(movingTo: 41)
        #expect(steps == 5)
    }

    @Test func leftwardDragEmitsNegativeSteps() {
        var stepper = CursorDragStepper(pointsPerStep: 8)
        _ = stepper.steps(movingTo: 100)
        let steps = stepper.steps(movingTo: 83)
        #expect(steps == -2)
    }

    @Test func stepsAccumulateAcrossSamples() {
        // Partial travel carries over: crossing the grid line matters, not
        // per-sample deltas.
        var stepper = CursorDragStepper(pointsPerStep: 8)
        _ = stepper.steps(movingTo: 0)
        let first = stepper.steps(movingTo: 5)   // 5 pt in: no step
        let second = stepper.steps(movingTo: 9)  // crossed 8: one step
        let third = stepper.steps(movingTo: 12)  // 4 pt past the anchor at 8
        let fourth = stepper.steps(movingTo: 17) // crossed 16: one step
        #expect(first == 0)
        #expect(second == 1)
        #expect(third == 0)
        #expect(fourth == 1)
    }

    @Test func reversalCrossesBackOverTheGrid() {
        // After two rightward steps the anchor sits at 16; turning around
        // emits the first leftward step only when the finger crosses back
        // to 8 — the remainder of the current cell is the hysteresis.
        var stepper = CursorDragStepper(pointsPerStep: 8)
        _ = stepper.steps(movingTo: 0)
        let rightward = stepper.steps(movingTo: 20)
        let withinCell = stepper.steps(movingTo: 9)
        let crossed = stepper.steps(movingTo: 8)
        #expect(rightward == 2)
        #expect(withinCell == 0)
        #expect(crossed == -1)
    }

    @Test func customPointsPerStepChangesSensitivity() {
        var stepper = CursorDragStepper(pointsPerStep: 20)
        _ = stepper.steps(movingTo: 0)
        let below = stepper.steps(movingTo: 19)
        let crossed = stepper.steps(movingTo: 20)
        #expect(below == 0)
        #expect(crossed == 1)
    }

    @Test func nonPositivePointsPerStepEmitsNothing() {
        // Defensive: a zero threshold must not divide by zero or spin.
        var stepper = CursorDragStepper(pointsPerStep: 0)
        _ = stepper.steps(movingTo: 0)
        let steps = stepper.steps(movingTo: 100)
        #expect(steps == 0)
    }
}
