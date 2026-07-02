//
//  NextKeyboardKeyOverlay.swift
//  KeyboardExtension
//
//  Created by Emma Haruka Iwao on 7/2/26.
//

import SwiftUI
import UIKit

/// A UIKit control laid over the shared SwiftUI globe keycap. Wiring every
/// touch event to `handleInputModeList(from:with:)` hands the interaction to
/// the system, which provides both behaviors Apple expects of the globe key:
/// a quick tap advances to the next keyboard and a long-press presents the
/// input-mode picker. A SwiftUI gesture can't call `handleInputModeList`
/// correctly because the system needs the real `UIEvent` to distinguish tap
/// from hold and to anchor the picker.
struct NextKeyboardKeyOverlay: UIViewRepresentable {
    /// The extension's input view controller; weak because the controller
    /// owns the view hierarchy this button lives in.
    weak var controller: UIInputViewController?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIButton {
        let button = HighlightingKeyButton(type: .custom)
        button.backgroundColor = .clear
        button.layer.cornerRadius = 6
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        // The SwiftUI keycap underneath keeps the accessibility label
        // ("next keyboard") and keyboard-key trait; VoiceOver activation
        // synthesizes a touch that lands on this button.
        button.isAccessibilityElement = false
        if let controller {
            button.addTarget(
                controller,
                action: #selector(UIInputViewController.handleInputModeList(from:with:)),
                for: .allTouchEvents)
        }
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.playClick),
            for: .touchDown)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}

    @MainActor
    final class Coordinator: NSObject {
        /// Match the shared keycaps' key-down click (audible because the
        /// input view adopts `UIInputViewAudioFeedback`; still subject to
        /// the user's keyboard sound setting).
        @objc func playClick() {
            UIDevice.current.playInputClick()
        }
    }
}

/// Mirrors the SwiftUI keycaps' pressed-state highlight, since the UIKit
/// globe control swallows the touches the SwiftUI key would otherwise track.
private final class HighlightingKeyButton: UIButton {
    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted
                ? UIColor.label.withAlphaComponent(0.12)
                : .clear
        }
    }
}
