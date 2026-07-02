//
//  KeyRepeatCadenceTests.swift
//  IPAKeyboardKitTests
//
//  Verifies the pure backspace-autorepeat timing policy: an initial delay
//  before repeating starts, then a geometrically accelerating interval that
//  clamps to a floor and never speeds back down below it.
//

import Foundation
import Testing
@testable import IPAKeyboardKit

struct KeyRepeatCadenceTests {

    private let cadence = KeyRepeatCadence.backspace

    @Test func firstWaitIsTheInitialDelay() {
        #expect(cadence.interval(beforeTick: 0) == cadence.initialDelay)
    }

    @Test func repeatPhaseStartsAtTheInitialInterval() {
        #expect(cadence.interval(beforeTick: 1) == cadence.initialInterval)
    }

    @Test func initialDelayExceedsTheRepeatInterval() {
        // The hold must feel deliberate: a noticeably longer pause before the
        // first repeat than between subsequent repeats.
        #expect(cadence.initialDelay > cadence.initialInterval)
    }

    @Test func repeatIntervalsNeverIncrease() {
        for tick in 1..<60 {
            #expect(cadence.interval(beforeTick: tick + 1) <= cadence.interval(beforeTick: tick))
        }
    }

    @Test func repeatIntervalsClampToTheMinimum() {
        for tick in 1..<200 {
            #expect(cadence.interval(beforeTick: tick) >= cadence.minimumInterval)
        }
        // The default policy actually reaches its floor (it accelerates all
        // the way, rather than decaying forever above it).
        #expect(cadence.interval(beforeTick: 200) == cadence.minimumInterval)
    }

    @Test func repeatingAccelerates() {
        #expect(cadence.interval(beforeTick: 20) < cadence.interval(beforeTick: 1))
    }

    @Test func customPolicyDecaysGeometricallyThenClamps() {
        let custom = KeyRepeatCadence(
            initialDelay: 1.0,
            initialInterval: 0.4,
            minimumInterval: 0.1,
            accelerationDecay: 0.5)
        #expect(custom.interval(beforeTick: 0) == 1.0)
        #expect(custom.interval(beforeTick: 1) == 0.4)
        #expect(custom.interval(beforeTick: 2) == 0.2)
        #expect(custom.interval(beforeTick: 3) == 0.1)  // 0.4 * 0.5² = 0.1
        #expect(custom.interval(beforeTick: 4) == 0.1)  // clamped
        #expect(custom.interval(beforeTick: 100) == 0.1)
    }

    @Test func intervalsAreNeverNegative() {
        // A misconfigured policy must still be safe to sleep on.
        let broken = KeyRepeatCadence(
            initialDelay: -1,
            initialInterval: -1,
            minimumInterval: -1,
            accelerationDecay: 0.5)
        #expect(broken.interval(beforeTick: 0) >= 0)
        #expect(broken.interval(beforeTick: 1) >= 0)
        #expect(broken.interval(beforeTick: 10) >= 0)
    }

    @Test func accelerationScheduleMatchesDocumentedValues() {
        // Locks the exact tuning documented on the type: the default
        // `.backspace` policy starts repeating at 0.12s and decays by 0.9x
        // per tick. Regression-protects the tuning constants themselves, not
        // just the general shape of the curve.
        let expected: [Int: Double] = [
            1: 0.12,
            2: 0.108,
            3: 0.0972,
            4: 0.08748,
            5: 0.078732,
            6: 0.0708588,
            7: 0.06377292,
            8: 0.057395628,
            9: 0.0516560652,
        ]
        for (tick, value) in expected {
            let actual = cadence.interval(beforeTick: tick)
            #expect(abs(actual - value) < 1e-9, "tick \(tick) expected \(value) got \(actual)")
        }
    }

    @Test func accelerationReachesTheFloorAtTickTen() {
        // Tick 9 is still (just) above the floor; tick 10 is the first tick
        // whose geometric value would fall below it and gets clamped.
        #expect(cadence.interval(beforeTick: 9) > cadence.minimumInterval)
        #expect(cadence.interval(beforeTick: 10) == cadence.minimumInterval)
    }

    @Test func nonPositiveTicksAllUseTheInitialDelay() {
        // The guard is `tick > 0`, so zero AND negative ticks both fall back
        // to `initialDelay` rather than being fed into the geometric formula.
        #expect(cadence.interval(beforeTick: 0) == cadence.initialDelay)
        #expect(cadence.interval(beforeTick: -1) == cadence.initialDelay)
        #expect(cadence.interval(beforeTick: Int.min) == cadence.initialDelay)
    }

    @Test func veryLargeTickCountsStayPinnedAtTheFloor() {
        // A key held for a very long time must not overflow, crash, or drift
        // the interval back up — `pow` with a huge negative-trending exponent
        // underflows toward 0 and the result stays clamped to the floor.
        #expect(cadence.interval(beforeTick: 1_000_000) == cadence.minimumInterval)
        #expect(cadence.interval(beforeTick: Int.max) == cadence.minimumInterval)
    }
}
