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
}
