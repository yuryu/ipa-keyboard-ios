//
//  KeyboardPreferences.swift
//  IPAKeyboardKit
//
//  Small cross-target preferences shared by the host app (writes) and the
//  keyboard extension (reads) through the App Group's `UserDefaults` suite —
//  currently which layout is active. Like `LayoutStore`, it degrades
//  gracefully before provisioning: the suite is still writable, just
//  process-local until the App Group is enabled (see `AppGroup.sharedAvailable`).
//

import Foundation

public final class KeyboardPreferences {
    private let defaults: UserDefaults

    /// - Parameter defaults: injectable for tests. Defaults to the shared App
    ///   Group suite, falling back to `.standard` if the suite can't be opened.
    public init(defaults: UserDefaults = AppGroup.sharedDefaults ?? .standard) {
        self.defaults = defaults
    }

    private enum Keys {
        static let activeLayoutID = "activeLayoutID"
        static let hiddenSymbols = "hiddenSymbols"
    }

    /// The id of the layout the keyboard should render, or nil to fall back to
    /// the default (see `ActiveLayoutResolver`). Stored as a UUID string.
    public var activeLayoutID: UUID? {
        get {
            guard let string = defaults.string(forKey: Keys.activeLayoutID) else { return nil }
            return UUID(uuidString: string)
        }
        set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: Keys.activeLayoutID)
            } else {
                defaults.removeObject(forKey: Keys.activeLayoutID)
            }
        }
    }

    /// Clear the active-layout selection when `id` is the one being removed, so
    /// a deleted layout can't leave a dangling selection — the resolver then
    /// falls back to the default. No-op when `id` isn't the active one.
    public func clearActiveLayout(ifEquals id: UUID) {
        if activeLayoutID == id { activeLayoutID = nil }
    }

    // MARK: Hidden symbols (per-layout curation)

    /// The inserted-symbol strings the user has hidden for `layoutID`. Stored as
    /// a sidecar keyed by inserted string (layout JSON omits key ids, which
    /// regenerate on decode), so the layout stays byte-identical and curation is
    /// reversible.
    public func hiddenSymbols(for layoutID: UUID) -> Set<String> {
        let all = defaults.dictionary(forKey: Keys.hiddenSymbols) as? [String: [String]] ?? [:]
        return Set(all[layoutID.uuidString] ?? [])
    }

    /// Replace the hidden set for `layoutID` (an empty set clears the entry).
    public func setHiddenSymbols(_ symbols: Set<String>, for layoutID: UUID) {
        var all = defaults.dictionary(forKey: Keys.hiddenSymbols) as? [String: [String]] ?? [:]
        all[layoutID.uuidString] = symbols.isEmpty ? nil : symbols.sorted()
        if all.isEmpty {
            defaults.removeObject(forKey: Keys.hiddenSymbols)
        } else {
            defaults.set(all, forKey: Keys.hiddenSymbols)
        }
    }

    /// Remove any curation stored for `layoutID` (e.g. when the layout is deleted).
    public func clearHiddenSymbols(for layoutID: UUID) {
        setHiddenSymbols([], for: layoutID)
    }

    // MARK: Bulk reset

    /// Clear every stored preference: the active-layout selection and all
    /// per-layout hidden-symbol curation. UI-test reset hook (issue #27),
    /// paired with `LayoutStore.deleteAllUserLayouts()` so a test can start
    /// each run from a clean slate instead of self-healing via
    /// swipe-to-delete. Always succeeds — like the rest of this type, it
    /// degrades to the process-local `.standard` suite before provisioning
    /// rather than needing a container to exist.
    public func resetAll() {
        activeLayoutID = nil
        defaults.removeObject(forKey: Keys.hiddenSymbols)
    }
}
