//
//  AlternatesAccessibility.swift
//  IPAKeyboardKit
//
//  The VoiceOver-facing view of a key's alternates (issue #114). The
//  popup's hold-slide-release interaction is not operable under VoiceOver,
//  so `KeyboardView` also exposes each alternate as an accessibility custom
//  action on the base key (swipe up/down to choose, double-tap to commit).
//  Extracted from the view so the naming and ordering rules are
//  unit-testable.
//

import Foundation

enum AlternatesAccessibility {

    /// One custom action: the name VoiceOver speaks and the `KeyAction`
    /// committing it emits — the same action a slide-and-release on the
    /// alternate's popup cell would commit.
    struct CustomAction: Equatable, Identifiable {
        /// The alternate key's own `id`, so SwiftUI can diff the actions.
        let id: UUID
        /// Spoken name: the alternate's `accessibilityLabel` where present
        /// ("aspirated p", not the raw glyph "pʰ"), else its display label.
        let name: String
        let action: KeyAction
    }

    /// The custom actions for `key`, one per alternate in popup order;
    /// empty for keys without alternates.
    static func customActions(for key: Key) -> [CustomAction] {
        key.alternates.map { alternate in
            CustomAction(
                id: alternate.id,
                name: alternate.accessibilityLabel ?? alternate.displayLabel,
                action: alternate.action)
        }
    }
}
