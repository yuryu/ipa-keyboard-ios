//
//  OnboardingState.swift
//  IPAKeyboard
//
//  View model for the enable-the-keyboard onboarding (issue #7): decides when
//  the guidance sheet auto-presents (first run) and records that the user has
//  seen it. The seen flag is host-only state, so it lives in standard
//  UserDefaults — deliberately NOT the App Group: the extension never needs
//  it, and the shared container may not exist before provisioning.
//
//  UI-test overrides (checked against the process launch arguments):
//    --uitest-show-onboarding — always auto-present the sheet on launch,
//                               regardless of the stored seen flag.
//    --uitest-skip-onboarding — never auto-present (the help button still
//                               opens the sheet manually).
//  Skip wins if both are passed.
//

import Foundation
import Observation

@Observable
@MainActor
final class OnboardingState {
    /// Whether the onboarding sheet is currently presented. Bound to
    /// `.sheet(isPresented:)` by the hosting view.
    var isPresented = false

    /// UserDefaults key for the has-seen flag. Host-local by design (see the
    /// header comment).
    static let hasSeenGuideKey = "hasSeenKeyboardOnboarding"

    /// Launch argument that forces the sheet to auto-present (UI tests).
    static let forceShowArgument = "--uitest-show-onboarding"
    /// Launch argument that suppresses auto-presentation (UI tests).
    static let forceSkipArgument = "--uitest-skip-onboarding"

    private let defaults: UserDefaults
    private let forceShow: Bool
    private let forceSkip: Bool
    /// One-shot latch so `presentIfFirstRun()` fires at most once per process,
    /// however many times the hosting view re-appears.
    private var hasAutoPresented = false

    init(
        defaults: UserDefaults = .standard,
        launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.defaults = defaults
        self.forceShow = launchArguments.contains(Self.forceShowArgument)
        self.forceSkip = launchArguments.contains(Self.forceSkipArgument)
    }

    /// True once the user has dismissed the guidance at least once.
    var hasSeenGuide: Bool {
        defaults.bool(forKey: Self.hasSeenGuideKey)
    }

    /// Auto-present the sheet on first run, or when forced by launch argument.
    /// Call from the root view's `onAppear`.
    func presentIfFirstRun() {
        guard !hasAutoPresented else { return }
        hasAutoPresented = true
        guard !forceSkip else { return }
        if forceShow || !hasSeenGuide {
            isPresented = true
        }
    }

    /// Open the guidance on demand (the persistent help affordance).
    func presentManually() {
        isPresented = true
    }

    /// Record that the user has seen the guidance; call on sheet dismissal.
    func markSeen() {
        defaults.set(true, forKey: Self.hasSeenGuideKey)
    }
}
