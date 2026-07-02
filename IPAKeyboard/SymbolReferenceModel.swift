//
//  SymbolReferenceModel.swift
//  IPAKeyboard
//
//  View model for the symbol reference (issue #17). Thin @Observable shell
//  over the kit's `SymbolInventory`: the aggregation, code-point formatting,
//  and search matching all live in IPAKeyboardKit where they are unit-tested;
//  this type only holds the UI state (query, scratchpad) on the main actor.
//
//  The inventory is built from the bundled layouts through `LayoutStore` at
//  runtime — never a hand-maintained table that could drift from the JSON.
//  Reading bundled layouts works even before App Group provisioning (the
//  store's graceful-degradation path), so this screen never needs the shared
//  container.
//

import Foundation
import Observation
import IPAKeyboardKit

@Observable
@MainActor
final class SymbolReferenceModel {
    /// Every distinct symbol across the bundled layouts, first-seen order.
    private(set) var entries: [SymbolEntry] = []

    /// The live search text (bound to `.searchable`).
    var query = ""

    /// Symbols the user has collected to copy as one string. Built by exact
    /// concatenation — no normalization — so pasted text carries the precise
    /// code points shown in the reference.
    private(set) var scratchpad = ""

    init(store: LayoutStore = LayoutStore()) {
        entries = SymbolInventory.build(from: store.bundledLayouts())
    }

    /// Entries matching the current query (all of them when it's empty).
    var filtered: [SymbolEntry] { SymbolInventory.filter(entries, matching: query) }

    /// Append a symbol's exact inserted text to the scratchpad.
    func addToScratchpad(_ entry: SymbolEntry) {
        scratchpad += entry.text
    }

    func clearScratchpad() {
        scratchpad = ""
    }
}
