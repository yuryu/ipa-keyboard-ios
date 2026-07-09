//
//  RecentSymbolsStore.swift
//  IPAKeyboardKit
//
//  A most-recent-first list of the symbols the user has typed, surfaced as a
//  quick-access row on the keyboard (issue #16). Persists through the same
//  App Group `UserDefaults` suite as `KeyboardPreferences` (the keyboard
//  extension writes on every insert and reads to render the row; the host app
//  could offer a "clear" action), and — like the rest of the store layer —
//  degrades gracefully before provisioning: the suite is still writable, just
//  process-local until the App Group is enabled (see `AppGroup.sharedAvailable`).
//
//  Uses `UserDefaults`, not the pasteboard, deliberately: recents work within
//  a keyboard session (and, once provisioned, across sessions) *without* the
//  extension needing "Allow Full Access".
//

import Foundation

public final class RecentSymbolsStore {
    private let defaults: UserDefaults
    private let capacity: Int

    /// How many recents are retained. One keyboard row's worth on a typical
    /// iPhone (the rendered row stretches to fill the width, so this many
    /// single-glyph caps stay comfortably tappable); the oldest are evicted
    /// past it. The rendered recents row shows at most this many.
    public static let defaultCapacity = 12

    /// - Parameters:
    ///   - defaults: injectable for tests. Defaults to the shared App Group
    ///     suite, falling back to `.standard` if the suite can't be opened —
    ///     matching `KeyboardPreferences`.
    ///   - capacity: retained-recents cap; injectable so tests can exercise
    ///     eviction with a small bound. Clamped to be non-negative.
    public init(
        defaults: UserDefaults = AppGroup.sharedDefaults ?? .standard,
        capacity: Int = RecentSymbolsStore.defaultCapacity
    ) {
        self.defaults = defaults
        self.capacity = max(0, capacity)
    }

    private enum Keys {
        static let recentSymbols = "recentSymbols"
    }

    /// The retained symbols, most-recent-first. Stored as a plain string
    /// array (a property-list-native type) under one key.
    private var stored: [String] {
        get { defaults.stringArray(forKey: Keys.recentSymbols) ?? [] }
        set {
            if newValue.isEmpty {
                defaults.removeObject(forKey: Keys.recentSymbols)
            } else {
                defaults.set(newValue, forKey: Keys.recentSymbols)
            }
        }
    }

    /// Record a just-inserted symbol at the front. Recording a symbol already
    /// present moves it to the front (no duplicates), and the list is capped
    /// at `capacity` with the oldest evicted. Empty strings are ignored so a
    /// non-`.insert` action can never seed a blank recent.
    public func record(_ symbol: String) {
        guard !symbol.isEmpty else { return }
        var list = stored
        list.removeAll { $0 == symbol }
        list.insert(symbol, at: 0)
        if list.count > capacity {
            list.removeLast(list.count - capacity)
        }
        stored = list
    }

    /// The recents to display, most-recent-first, with any symbol hidden for
    /// the active layout filtered out so curation is respected (a symbol the
    /// user has hidden must not resurface here). Pass the active layout's
    /// hidden set from `KeyboardPreferences.hiddenSymbols(for:)`; the default
    /// empty set returns everything.
    public func recentSymbols(excludingHidden hidden: Set<String> = []) -> [String] {
        hidden.isEmpty ? stored : stored.filter { !hidden.contains($0) }
    }

    /// Forget every recorded recent.
    public func clear() {
        stored = []
    }
}
