//
//  BottomBarOrder.swift
//  IPAKeyboardKit
//
//  Where the active panel's switch key sits in the pinned bottom bar,
//  extracted from `KeyboardView` so the rule is unit-testable (issue #208).
//
//  The bar merges the panel's `switchKey` into the arrangement's shared
//  `functionRow` (globe / space / ⌫ / return). The two idioms' system
//  keyboards disagree about the resulting order, and we follow each:
//
//  - **iPad** — the globe/emoji key holds the bottom-left corner with
//    `.?123` to its right, so the switch key yields the left edge to a
//    leading globe: `🌐 more space ⌫ return`.
//  - **iPhone** — `123` holds the bottom-left corner with the globe between
//    it and the space bar, so the switch key keeps the left edge:
//    `more 🌐 space ⌫ return`.
//
//  Only a *leading* globe displaces the switch key. A user layout that puts
//  the globe elsewhere in its function row has authored its own order, so
//  the switch key stays at the front rather than being spliced into an
//  arbitrary spot. When the extension strips the globe entirely
//  (`needsInputModeSwitchKey == false`), both idioms collapse to the same
//  bar with the switch key leftmost.
//

import UIKit

enum BottomBarOrder {

    /// The bottom bar's keys: `switchKey` (if any) merged into
    /// `functionRowKeys` at the position `idiom`'s system keyboard uses.
    /// Never reorders the function row itself.
    static func keys(
        switchKey: Key?,
        functionRowKeys: [Key],
        idiom: UIUserInterfaceIdiom
    ) -> [Key] {
        guard let switchKey else { return functionRowKeys }
        var keys = functionRowKeys
        keys.insert(
            switchKey,
            at: switchKeyIndex(functionRowKeys: functionRowKeys, idiom: idiom))
        return keys
    }

    /// Index the switch key is inserted at: the left edge (0) everywhere
    /// except iPad, where it goes after the function row's leading globe run
    /// so the globe keeps the corner. The run — rather than just index 0 —
    /// keeps a layout that somehow declares two leading globes from splitting
    /// them around the switch key.
    private static func switchKeyIndex(
        functionRowKeys: [Key],
        idiom: UIUserInterfaceIdiom
    ) -> Int {
        guard idiom == .pad else { return 0 }
        return functionRowKeys.prefix { $0.action == .nextKeyboard }.count
    }
}
