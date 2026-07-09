//
//  RecentSymbolsStoreTests.swift
//  IPAKeyboardKitTests
//
//  RecentSymbolsStore keeps a most-recent-first, de-duplicated, capacity-capped
//  list of typed symbols over an injectable UserDefaults suite (issue #16),
//  filters out symbols hidden for the active layout, and round-trips across
//  instances the way the keyboard extension relies on.
//

import Foundation
import Testing
@testable import IPAKeyboardKit

struct RecentSymbolsStoreTests {

    /// A fresh, isolated UserDefaults suite so tests don't touch real prefs or
    /// each other. Cleaned up by the caller via the returned suite name.
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "RecentSymbolsStoreTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func recordsMostRecentFirst() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecentSymbolsStore(defaults: defaults)
        store.record("p")
        store.record("t")
        store.record("k")
        #expect(store.recentSymbols() == ["k", "t", "p"])
    }

    @Test func recordingAnExistingSymbolMovesItToTheFront() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecentSymbolsStore(defaults: defaults)
        store.record("p")
        store.record("t")
        store.record("k")
        store.record("p") // already present: moves to front, no duplicate
        #expect(store.recentSymbols() == ["p", "k", "t"])
    }

    @Test func capacityEvictsTheOldest() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecentSymbolsStore(defaults: defaults, capacity: 3)
        store.record("a")
        store.record("b")
        store.record("c")
        store.record("d") // pushes "a" (the oldest) out
        #expect(store.recentSymbols() == ["d", "c", "b"])
    }

    @Test func recentSymbolsExcludeTheActiveLayoutsHiddenSet() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecentSymbolsStore(defaults: defaults)
        store.record("p")
        store.record("ə") // U+0259
        store.record("t")
        #expect(store.recentSymbols(excludingHidden: ["ə"]) == ["t", "p"])
    }

    @Test func recordsPersistAcrossInstancesOverTheSameSuite() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        RecentSymbolsStore(defaults: defaults).record("ɡ") // U+0261
        RecentSymbolsStore(defaults: defaults).record("ʃ") // U+0283
        // A fresh instance over the same suite reads the same list.
        #expect(RecentSymbolsStore(defaults: defaults).recentSymbols() == ["ʃ", "ɡ"])
    }

    @Test func emptySymbolIsIgnored() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecentSymbolsStore(defaults: defaults)
        store.record("")
        #expect(store.recentSymbols().isEmpty)
    }

    @Test func absentRecentsAreEmpty() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(RecentSymbolsStore(defaults: defaults).recentSymbols().isEmpty)
    }

    @Test func clearForgetsEverythingIncludingInTheSuite() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RecentSymbolsStore(defaults: defaults)
        store.record("p")
        store.record("t")
        store.clear()
        #expect(store.recentSymbols().isEmpty)
        // The clear reaches the suite itself, not just this instance's view.
        #expect(RecentSymbolsStore(defaults: defaults).recentSymbols().isEmpty)
    }
}
