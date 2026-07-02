//
//  KeyRepeatCadence.swift
//  IPAKeyboardKit
//
//  The timing policy for held-key autorepeat (backspace): an initial delay,
//  then a repeat interval that accelerates geometrically down to a floor,
//  like the system keyboard's delete key. Pure data + math so the cadence is
//  unit-testable without timers or UI — the view layer owns the clock and
//  asks this type how long to wait before each repeat tick.
//

import Foundation

public struct KeyRepeatCadence: Sendable, Hashable {
    /// Pause between the initial key-down action and the first repeat tick.
    public var initialDelay: TimeInterval
    /// Interval before the second repeat tick — where the repeat phase starts.
    public var initialInterval: TimeInterval
    /// The fastest the repeat is allowed to get.
    public var minimumInterval: TimeInterval
    /// Per-tick multiplier applied to the repeat interval (values below 1
    /// accelerate the repeat until it reaches `minimumInterval`).
    public var accelerationDecay: Double

    public init(
        initialDelay: TimeInterval = 0.5,
        initialInterval: TimeInterval = 0.12,
        minimumInterval: TimeInterval = 0.05,
        accelerationDecay: Double = 0.9
    ) {
        self.initialDelay = initialDelay
        self.initialInterval = initialInterval
        self.minimumInterval = minimumInterval
        self.accelerationDecay = accelerationDecay
    }

    /// The policy used for a held backspace key. Tuned by feel against the
    /// system keyboard: half a second before repeating starts, then roughly
    /// eight deletions per second accelerating to twenty.
    public static let backspace = KeyRepeatCadence()

    /// How long to wait before repeat tick `tick` fires, where tick 0 is the
    /// first *repeated* action after the initial key-down action. Tick 0 waits
    /// `initialDelay`; later ticks start at `initialInterval` and decay
    /// geometrically, clamped to `minimumInterval`. Never negative.
    public func interval(beforeTick tick: Int) -> TimeInterval {
        guard tick > 0 else { return max(initialDelay, 0) }
        let decayed = initialInterval * pow(accelerationDecay, Double(tick - 1))
        return max(max(decayed, minimumInterval), 0)
    }
}
