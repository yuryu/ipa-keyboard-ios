//
//  ActiveLayoutResolver.swift
//  IPAKeyboardKit
//
//  Resolves which `KeyboardLayout` to render from an optional selected id and
//  the list of available layouts. Pure and total: for any inputs it returns a
//  usable layout — never nil, never blank — so the extension can call it
//  directly without its own fallback logic, and the host can preview exactly
//  what the extension would show. `nonisolated`/static so both the `@MainActor`
//  host and the extension controller share one code path.
//

import Foundation

public enum ActiveLayoutResolver {
    /// The layout to show, in preference order:
    /// 1. the layout whose id matches `activeID`,
    /// 2. the bundled `en-US` default,
    /// 3. the first available layout,
    /// 4. a minimal built-in fallback (so the keyboard is never blank).
    ///
    /// - Parameter layouts: the available layouts (e.g. `LayoutStore.allLayouts()`),
    ///   injected rather than read from `AppGroup` so this stays a pure function.
    public static func resolve(activeID: UUID?, in layouts: [KeyboardLayout]) -> KeyboardLayout {
        if let activeID, let match = layouts.first(where: { $0.id == activeID }) {
            return match
        }
        if let enUS = layouts.first(where: { $0.locale == "en-US" }) {
            return enUS
        }
        return layouts.first ?? fallback
    }

    /// A tiny, always-valid layout used only when no layouts are available at
    /// all (e.g. a broken install). Never blank. Kept here so host and extension
    /// share one fallback rather than each defining their own.
    public static var fallback: KeyboardLayout {
        KeyboardLayout(
            name: "Fallback",
            locale: "en-US",
            rows: [KeyRow(keys: [
                .insert("ə"),
                Key(action: .space, label: "space", widthFactor: 3.0),
                Key(action: .backspace, label: "⌫", widthFactor: 1.5),
            ])]
        )
    }
}
