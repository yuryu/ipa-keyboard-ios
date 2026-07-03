//
//  OnboardingStateTests.swift
//  IPAKeyboardTests
//
//  OnboardingState (issue #7) decides when the enable-the-keyboard guidance
//  auto-presents: first run gated on the has-seen flag, UI-test launch
//  arguments overriding it (--uitest-skip-onboarding wins over
//  --uitest-show-onboarding), and a one-shot latch so the sheet auto-presents
//  at most once per process. Every test injects an isolated UserDefaults
//  suite and an explicit launch-arguments array, so nothing touches the real
//  process state.
//

import Foundation
import Testing
@testable import IPAKeyboard

@MainActor
struct OnboardingStateTests {

    /// A fresh, isolated UserDefaults suite so tests don't touch real prefs
    /// or each other. Callers clean up via the returned suite name.
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "OnboardingStateTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    // MARK: First-run gating

    @Test func firstRunAutoPresents() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = OnboardingState(defaults: defaults, launchArguments: [])

        #expect(!state.isPresented)
        state.presentIfFirstRun()
        #expect(state.isPresented)
        // Presenting alone must not record the guide as seen — only an
        // explicit markSeen() (sheet dismissal) does.
        #expect(!state.hasSeenGuide)
    }

    @Test func seenGuideSuppressesAutoPresent() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: OnboardingState.hasSeenGuideKey)

        let state = OnboardingState(defaults: defaults, launchArguments: [])
        state.presentIfFirstRun()
        #expect(!state.isPresented)
    }

    @Test func markSeenPersistsAcrossInstances() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = OnboardingState(defaults: defaults, launchArguments: [])
        #expect(!first.hasSeenGuide)
        first.markSeen()
        #expect(first.hasSeenGuide)

        // A fresh instance over the same defaults (a relaunch) sees the flag
        // and no longer auto-presents.
        let second = OnboardingState(defaults: defaults, launchArguments: [])
        second.presentIfFirstRun()
        #expect(!second.isPresented)
    }

    // MARK: One-shot latch

    @Test func autoPresentFiresAtMostOncePerInstance() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = OnboardingState(defaults: defaults, launchArguments: [])

        state.presentIfFirstRun()
        #expect(state.isPresented)

        // Dismiss without marking seen — the latch alone (not the stored
        // flag) must keep re-appearing views from re-presenting.
        state.isPresented = false
        state.presentIfFirstRun()
        #expect(!state.isPresented)
    }

    // MARK: Launch-argument overrides

    @Test func forceShowOverridesSeenFlag() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: OnboardingState.hasSeenGuideKey)

        let state = OnboardingState(
            defaults: defaults,
            launchArguments: [OnboardingState.forceShowArgument])
        state.presentIfFirstRun()
        #expect(state.isPresented)
    }

    @Test func forceSkipSuppressesFirstRunPresentation() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = OnboardingState(
            defaults: defaults,
            launchArguments: [OnboardingState.forceSkipArgument])
        state.presentIfFirstRun()
        #expect(!state.isPresented)
    }

    @Test func skipWinsWhenBothArgumentsArePassed() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = OnboardingState(
            defaults: defaults,
            launchArguments: [
                OnboardingState.forceShowArgument,
                OnboardingState.forceSkipArgument,
            ])
        state.presentIfFirstRun()
        #expect(!state.isPresented)
    }

    // MARK: Manual presentation

    @Test func presentManuallyWorksDespiteSkipAndLatch() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = OnboardingState(
            defaults: defaults,
            launchArguments: [OnboardingState.forceSkipArgument])
        state.presentIfFirstRun() // suppressed, and spends the latch
        #expect(!state.isPresented)

        // The help affordance must still open the sheet.
        state.presentManually()
        #expect(state.isPresented)
    }

    // MARK: UI-test contract

    @Test func launchArgumentSpellingsMatchTheUITestContract() {
        // IPAKeyboardUITests passes these exact strings; a silent rename here
        // would quietly disable the overrides there.
        #expect(OnboardingState.forceShowArgument == "--uitest-show-onboarding")
        #expect(OnboardingState.forceSkipArgument == "--uitest-skip-onboarding")
    }
}
