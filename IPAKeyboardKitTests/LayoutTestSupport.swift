//
//  LayoutTestSupport.swift
//  IPAKeyboardKitTests
//
//  Shared lookup and key-walking helpers for tests that inspect the bundled
//  layouts. One definition for the whole target — the per-layout test files
//  used to carry byte-identical private copies that drifted independently
//  (issue #186).
//

import Testing
@testable import IPAKeyboardKit

/// The bundled layout with the given BCP-47 locale. Dialect layouts only —
/// several generic layouts share the `und` locale; look those up by name.
func bundledLayout(locale: String) throws -> KeyboardLayout {
    let layouts = LayoutStore().bundledLayouts()
    return try #require(layouts.first { $0.locale == locale },
                        "expected a bundled \(locale) layout")
}

/// The bundled layout with the given display name.
func bundledLayout(named name: String) throws -> KeyboardLayout {
    let layouts = LayoutStore().bundledLayouts()
    return try #require(layouts.first { $0.name == name },
                        "expected a bundled layout named \(name)")
}

/// All top-level symbol keys of a layout (panel rows only, not alternates).
func topLevelKeys(in layout: KeyboardLayout) -> [Key] {
    layout.arrangements.flatMap(\.panels).flatMap(\.rows).flatMap(\.keys)
}

/// Every string the layout can insert — rows, function row, switch keys,
/// and long-press alternates (recursively).
func insertTexts(in layout: KeyboardLayout) -> Set<String> {
    var texts = Set<String>()
    func visit(_ key: Key) {
        if case .insert(let text) = key.action { texts.insert(text) }
        key.alternates.forEach(visit)
    }
    let panels = layout.arrangements.flatMap(\.panels)
    (panels.flatMap(\.rows).flatMap(\.keys)
        + layout.arrangements.compactMap(\.functionRow).flatMap(\.keys)
        + panels.compactMap(\.switchKey))
        .forEach(visit)
    return texts
}

/// The first top-level key of `layout` that inserts exactly `text`.
func key(inserting text: String, in layout: KeyboardLayout) -> Key? {
    topLevelKeys(in: layout).first { key in
        if case .insert(let inserted) = key.action { return inserted == text }
        return false
    }
}

/// The inserted text of an insert-action key, or nil for any other action.
func insertText(of key: Key) -> String? {
    if case .insert(let text) = key.action { return text }
    return nil
}
