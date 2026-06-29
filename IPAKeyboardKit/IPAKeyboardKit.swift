//
//  IPAKeyboardKit.swift
//  IPAKeyboardKit
//
//  Created by Emma Haruka Iwao on 6/28/26.
//

import Foundation

/// Anchor type used to resolve this framework's resource bundle.
///
/// Xcode framework targets do not get the SwiftPM-generated `Bundle.module`,
/// so we locate resources via `Bundle(for:)` against a type in this module.
final class IPAKeyboardKitBundleToken {}

public enum IPAResources {
    /// The framework's resource bundle (where the built-in default layouts live).
    public static let bundle = Bundle(for: IPAKeyboardKitBundleToken.self)
}
