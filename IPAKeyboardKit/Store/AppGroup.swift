//
//  AppGroup.swift
//  IPAKeyboardKit
//
//  Shared container coordinates between the host app (writes layouts) and
//  the keyboard extension (reads them). `containerURL` is nil until the
//  App Group capability is enabled on both targets in Xcode.
//

import Foundation

public enum AppGroup {
    public static let identifier = "group.net.yuryu.IPAKeyboard"

    /// Root of the shared container, or nil if the App Group capability
    /// is not yet configured (signing/provisioning pending). Callers should
    /// degrade gracefully to bundled defaults when this is nil.
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// `UserDefaults` backed by the App Group suite, used for small shared
    /// preferences (the active layout, per-layout curation). Non-nil even
    /// before provisioning — but in that state it is *process-local*, not
    /// actually shared between the app and the extension. See `sharedAvailable`.
    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    /// Whether App-Group-backed storage is genuinely shared across processes.
    /// Gated on the container probe: an unprovisioned suite is non-nil but
    /// process-local, so `UserDefaults(suiteName:) != nil` is *not* a reliable
    /// signal on its own. The host surfaces a degraded state when this is false.
    public static var sharedAvailable: Bool {
        containerURL != nil
    }
}
