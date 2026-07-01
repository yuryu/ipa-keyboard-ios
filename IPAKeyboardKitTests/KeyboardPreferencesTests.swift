//
//  KeyboardPreferencesTests.swift
//  IPAKeyboardKitTests
//
//  KeyboardPreferences round-trips the active-layout selection through an
//  injectable UserDefaults suite, and AppGroup.sharedAvailable stays honest
//  about the process-local pre-provisioning state.
//

import Foundation
import Testing
@testable import IPAKeyboardKit

struct KeyboardPreferencesTests {

    /// A fresh, isolated UserDefaults suite so tests don't touch real prefs or
    /// each other. Cleaned up by the caller via the returned suite name.
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "KeyboardPreferencesTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func activeLayoutIDRoundTripsAcrossInstances() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        KeyboardPreferences(defaults: defaults).activeLayoutID = id
        // A fresh instance over the same suite reads the same value.
        #expect(KeyboardPreferences(defaults: defaults).activeLayoutID == id)
    }

    @Test func absentActiveLayoutIDIsNil() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(KeyboardPreferences(defaults: defaults).activeLayoutID == nil)
    }

    @Test func settingNilClearsActiveLayoutID() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = KeyboardPreferences(defaults: defaults)
        prefs.activeLayoutID = UUID()
        prefs.activeLayoutID = nil
        #expect(prefs.activeLayoutID == nil)
    }

    @Test func clearActiveLayoutIfEqualsClearsOnlyMatchingID() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = KeyboardPreferences(defaults: defaults)
        let id = UUID()
        prefs.activeLayoutID = id
        prefs.clearActiveLayout(ifEquals: UUID()) // different id: no-op
        #expect(prefs.activeLayoutID == id)
        prefs.clearActiveLayout(ifEquals: id)     // matching id: clears
        #expect(prefs.activeLayoutID == nil)
    }

    @Test func malformedStoredStringReadsAsNil() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("not-a-uuid", forKey: "activeLayoutID")
        #expect(KeyboardPreferences(defaults: defaults).activeLayoutID == nil)
    }

    @Test func sharedAvailableFollowsContainerProbe() {
        // Honesty guard: an unprovisioned suite is non-nil but process-local, so
        // sharedAvailable must track the container probe, not suite creation.
        #expect(AppGroup.sharedAvailable == (AppGroup.containerURL != nil))
    }
}
