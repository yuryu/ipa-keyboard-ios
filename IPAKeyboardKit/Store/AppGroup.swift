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
}
