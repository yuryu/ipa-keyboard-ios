//
//  LayoutDraft.swift
//  IPAKeyboard
//
//  Working-copy view model for the key-level layout editor (issue #6). Owns a
//  mutable copy of a user layout; every edit goes through the kit's pure
//  editing API (`LayoutEditing.swift`) against that copy, so Cancel simply
//  discards it and Save commits the whole document through
//  `LayoutLibrary.update` → `LayoutStore`. Built-ins never reach this type:
//  the UI only offers key editing for `isBuiltIn == false` layouts, and
//  `LayoutLibrary.update` refuses built-ins anyway (copy-on-write).
//
//  Unicode exactness: this type never transforms key text — strings from the
//  form fields land in the working copy byte-for-byte (no trimming, no
//  normalization), so ɡ (U+0261), ː (U+02D0), and combining marks round-trip
//  untouched.
//

import Foundation
import Observation
import IPAKeyboardKit

@Observable
@MainActor
final class LayoutDraft {
    /// The document being edited. Mutated only through the methods below.
    private(set) var workingCopy: KeyboardLayout
    /// The saved document the draft started from; `hasChanges` compares to it.
    let original: KeyboardLayout

    /// Which panel of the primary arrangement the editor is showing. Clamped
    /// on use so a reset (which can change the panel count) can't strand it.
    var panelIndex = 0

    /// User-facing message for the most recent failed save, or nil. The
    /// editor sheet presents this itself — the layout list's root alert can't
    /// present while the editor sheet is up.
    var saveErrorMessage: String?

    private let library: LayoutLibrary

    init(layout: KeyboardLayout, library: LayoutLibrary) {
        self.original = layout
        self.workingCopy = layout
        self.library = library
    }

    /// Whether the working copy differs from the saved document. Drives the
    /// Save button, the discard confirmation, and interactive-dismiss locking.
    var hasChanges: Bool { workingCopy != original }

    // MARK: Panel addressing

    /// Panels of the primary arrangement — the only arrangement the editor
    /// (like the renderer) surfaces until arrangement selection lands.
    var panels: [Panel] { workingCopy.primaryArrangement?.panels ?? [] }

    private var panelPath: PanelPath {
        PanelPath(
            arrangementIndex: 0,
            panelIndex: min(max(panelIndex, 0), max(panels.count - 1, 0)))
    }

    /// Rows of the currently selected panel.
    var rows: [KeyRow] { workingCopy.panel(at: panelPath)?.rows ?? [] }

    // MARK: Row editing

    func addRow() {
        workingCopy.appendRow(inPanelAt: panelPath)
    }

    func removeRows(atOffsets offsets: IndexSet) {
        workingCopy.removeRows(atOffsets: offsets, inPanelAt: panelPath)
    }

    func moveRows(fromOffsets source: IndexSet, toOffset destination: Int) {
        workingCopy.moveRows(fromOffsets: source, toOffset: destination, inPanelAt: panelPath)
    }

    // MARK: Key editing

    func keys(inRowAt rowIndex: Int) -> [Key] {
        workingCopy.row(at: rowIndex, inPanelAt: panelPath)?.keys ?? []
    }

    func appendKey(_ key: Key, toRowAt rowIndex: Int) {
        workingCopy.appendKey(key, inRowAt: rowIndex, inPanelAt: panelPath)
    }

    func removeKeys(atOffsets offsets: IndexSet, inRowAt rowIndex: Int) {
        workingCopy.removeKeys(atOffsets: offsets, inRowAt: rowIndex, inPanelAt: panelPath)
    }

    func moveKeys(fromOffsets source: IndexSet, toOffset destination: Int, inRowAt rowIndex: Int) {
        workingCopy.moveKeys(
            fromOffsets: source, toOffset: destination,
            inRowAt: rowIndex, inPanelAt: panelPath)
    }

    func replaceKey(at index: Int, inRowAt rowIndex: Int, with key: Key) {
        workingCopy.replaceKey(at: index, inRowAt: rowIndex, inPanelAt: panelPath, with: key)
    }

    // MARK: Reset to default

    /// The built-in this layout was forked from, when it still exists.
    var builtInSource: KeyboardLayout? {
        guard let sourceID = original.derivedFrom else { return nil }
        return library.builtInLayouts.first { $0.id == sourceID }
    }

    var canResetToDefault: Bool { builtInSource != nil }

    /// Replace the draft's panels/rows/keys with the source built-in's. A
    /// draft operation like any other: nothing persists until Save, and
    /// Cancel still restores the saved version.
    func resetToDefault() {
        guard let source = builtInSource else { return }
        workingCopy = workingCopy.resettingContent(from: source)
        panelIndex = 0
    }

    // MARK: Save

    /// Commit the working copy through the library/store. Returns whether it
    /// stuck; on failure `saveErrorMessage` carries the user-facing reason
    /// (including the friendly no-shared-storage explanation used elsewhere).
    func save() -> Bool {
        do {
            try library.update(workingCopy)
            return true
        } catch LayoutStore.StoreError.sharedContainerUnavailable {
            saveErrorMessage = "Couldn’t save your changes. Saving layouts needs "
                + "the keyboard’s shared storage, which isn’t set up yet."
            return false
        } catch {
            saveErrorMessage = "Couldn’t save your changes. \(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - Editor display helpers

extension KeyAction {
    /// The inserted text when this is an `.insert`, else nil.
    var insertText: String? {
        if case .insert(let text) = self { return text }
        return nil
    }

    /// Short human-readable name for editor rows and the key form.
    var editorName: String {
        switch self {
        case .insert: return "Insert"
        case .backspace: return "Backspace"
        case .space: return "Space"
        case .return: return "Return"
        case .nextKeyboard: return "Next keyboard (globe)"
        case .switchPanel(let target): return "Switch to “\(target)”"
        case .spacer: return "Spacer (flexible gap)"
        @unknown default: return "Unknown"
        }
    }
}

extension Key {
    /// Compact glyph for editor lists: the display label, falling back to the
    /// action's name for keys that render no glyph (space, backspace, spacer…).
    var editorGlyph: String {
        let label = displayLabel
        return label.isEmpty ? action.editorName : label
    }
}
