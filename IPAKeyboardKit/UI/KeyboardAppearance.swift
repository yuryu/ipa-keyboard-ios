//
//  KeyboardAppearance.swift
//  IPAKeyboardKit
//
//  Appearance parity with the system keyboard (issue #13): the keycap and
//  chrome palette that adapts to light/dark, and the return-key label derived
//  from the host field's `UIReturnKeyType`.
//
//  Every color is a *dynamic* `UIColor`, so a single definition serves both
//  render paths: the keyboard extension overrides its input view's
//  `overrideUserInterfaceStyle` from `textDocumentProxy.keyboardAppearance`
//  (a dark host field gets a dark keyboard even in a light app), and the host
//  app's previews simply follow the app's own color scheme. `KeyboardView`
//  resolves these through the SwiftUI trait environment, so both targets can
//  never disagree about what a keycap looks like.
//

import UIKit

/// The display text for the return key, mirroring how the system keyboard
/// relabels it per the host field's `returnKeyType` (Go/Search/Done…). The
/// same string doubles as the key's spoken VoiceOver label — they are plain
/// words, matching the system keyboard's lowercase labels.
public enum ReturnKeyLabel {
    public static func text(for type: UIReturnKeyType) -> String {
        switch type {
        case .go: "go"
        case .join: "join"
        case .next: "next"
        case .route: "route"
        case .search: "search"
        case .send: "send"
        case .done: "done"
        case .emergencyCall: "emergency call"
        case .continue: "continue"
        // `.default`, the deprecated `.google`/`.yahoo`, and any future type.
        default: "return"
        }
    }
}

/// The keyboard's chrome (background) color for contexts that don't sit on
/// the system keyboard blur — the host app's previews. The extension keeps a
/// clear background so the real `UIInputView` material shows through; these
/// values approximate that material so previews and the live keyboard match.
public enum KeyboardChrome {
    public static let background = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
            : UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1)
    }
}

/// System-keyboard-like keycap colors (internal; `KeyboardView` applies them
/// through `KeyStyle`).
enum KeyPalette {
    /// Character keycaps (symbol keys and the space bar): white in light,
    /// the system keyboard's medium gray in dark.
    static let characterKey = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1)
            : .white
    }
    /// Function keycaps (globe, backspace, panel switch, plain return):
    /// the darker gray tier, both schemes.
    static let functionKey = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1)
            : UIColor(red: 0.68, green: 0.70, blue: 0.75, alpha: 1)
    }
    /// The tinted return key shown when the host field requests a special
    /// action (Search, Go, …), like the system keyboard's blue return key.
    static let prominentReturn = UIColor.systemBlue
    static let prominentReturnPressed = UIColor.systemBlue.withAlphaComponent(0.75)
    /// The 1-pt drop shadow under every keycap, same in both schemes; it also
    /// keeps white keycaps legible on the host previews' light chrome.
    static let keycapShadow = UIColor.black.withAlphaComponent(0.3)
}

/// Which palette tier styles a key, derived from its action and — for the
/// return key — the host field's `returnKeyType`.
enum KeyStyle {
    case character
    case function
    case prominentReturn

    init(key: Key, returnKeyType: UIReturnKeyType) {
        switch key.action {
        case .insert, .space:
            self = .character
        case .return:
            self = returnKeyType == .default ? .function : .prominentReturn
        case .backspace, .nextKeyboard, .switchPanel, .spacer:
            self = .function
        }
    }

    /// Pressed keycaps swap between the character and function fills — the
    /// closest match to the system keyboard's press feedback that works in
    /// both schemes (light function keys flash white, dark keys lighten).
    func fill(isPressed: Bool) -> UIColor {
        switch self {
        case .character:
            isPressed ? KeyPalette.functionKey : KeyPalette.characterKey
        case .function:
            isPressed ? KeyPalette.characterKey : KeyPalette.functionKey
        case .prominentReturn:
            isPressed ? KeyPalette.prominentReturnPressed : KeyPalette.prominentReturn
        }
    }

    var textColor: UIColor {
        switch self {
        case .prominentReturn: .white
        case .character, .function: .label
        }
    }
}
