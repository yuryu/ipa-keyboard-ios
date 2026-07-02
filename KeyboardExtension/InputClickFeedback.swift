//
//  InputClickFeedback.swift
//  KeyboardExtension
//
//  Created by Emma Haruka Iwao on 7/2/26.
//

import UIKit

/// Opts the keyboard's input view into the standard system keyboard click.
/// `UIDevice.current.playInputClick()` — called by the shared `KeyboardView`
/// on key-down — only produces sound when the visible input view adopts
/// `UIInputViewAudioFeedback`; this conformance is that opt-in.
/// `UIInputViewController`'s root view is a `UIInputView`, so conforming the
/// class covers this extension. The system still honors the user's keyboard
/// sound setting, and no Full Access is required. The host app never adopts
/// the protocol, so the same `KeyboardView` stays silent in its previews.
extension UIInputView: @retroactive UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }
}
