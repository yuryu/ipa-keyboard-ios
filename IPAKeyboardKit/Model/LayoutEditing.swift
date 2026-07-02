//
//  LayoutEditing.swift
//  IPAKeyboardKit
//
//  Pure, bounds-checked editing operations on a layout's
//  arrangements → panels → rows → keys tree — the engine behind the host
//  app's key-level editor. Every operation mutates the value it is called
//  on and reports whether it applied, so a view model can hold a working
//  copy, edit it freely, and commit (or discard) the whole document.
//
//  Policy-free by design: like `filteringKeys`, these functions don't check
//  `isBuiltIn` — copy-on-write is enforced where layouts are persisted
//  (built-ins are never written back; see `KeyboardLayout.makeEditableCopy`).
//
//  Offset semantics match SwiftUI's `onDelete`/`onMove` (`IndexSet` plus a
//  destination expressed in pre-removal offsets), implemented locally so the
//  model layer needs no UI-framework import.
//

import Foundation

/// Addresses one panel inside a layout: the arrangement's position in
/// `KeyboardLayout.arrangements` and the panel's position in
/// `Arrangement.panels`. Editing operations that take a `PanelPath` are
/// no-ops (returning false) when the path doesn't exist.
public struct PanelPath: Hashable, Sendable {
    public var arrangementIndex: Int
    public var panelIndex: Int

    public init(arrangementIndex: Int = 0, panelIndex: Int = 0) {
        self.arrangementIndex = arrangementIndex
        self.panelIndex = panelIndex
    }

    /// The primary panel of the primary arrangement.
    public static let primary = PanelPath()
}

extension KeyboardLayout {

    // MARK: Lookup

    /// The panel at `path`, or nil when the path doesn't exist.
    public func panel(at path: PanelPath) -> Panel? {
        guard arrangements.indices.contains(path.arrangementIndex) else { return nil }
        let panels = arrangements[path.arrangementIndex].panels
        guard panels.indices.contains(path.panelIndex) else { return nil }
        return panels[path.panelIndex]
    }

    /// The row at `rowIndex` within the panel at `path`, or nil.
    public func row(at rowIndex: Int, inPanelAt path: PanelPath) -> KeyRow? {
        guard let panel = panel(at: path), panel.rows.indices.contains(rowIndex) else { return nil }
        return panel.rows[rowIndex]
    }

    /// The key at `keyIndex` in the row at `rowIndex` within the panel at
    /// `path`, or nil.
    public func key(at keyIndex: Int, inRowAt rowIndex: Int, inPanelAt path: PanelPath) -> Key? {
        guard let row = row(at: rowIndex, inPanelAt: path),
              row.keys.indices.contains(keyIndex) else { return nil }
        return row.keys[keyIndex]
    }

    // MARK: Row editing

    /// Insert `row` at `index` (0...count) in the panel at `path`.
    @discardableResult
    public mutating func insertRow(
        _ row: KeyRow = KeyRow(keys: []),
        at index: Int,
        inPanelAt path: PanelPath
    ) -> Bool {
        mutateRows(inPanelAt: path) { rows in
            guard index >= 0, index <= rows.count else { return false }
            rows.insert(row, at: index)
            return true
        }
    }

    /// Append `row` (an empty row by default) to the panel at `path`.
    @discardableResult
    public mutating func appendRow(
        _ row: KeyRow = KeyRow(keys: []),
        inPanelAt path: PanelPath
    ) -> Bool {
        mutateRows(inPanelAt: path) { rows in
            rows.append(row)
            return true
        }
    }

    /// Remove the rows at `offsets` from the panel at `path`. Refuses (false)
    /// when `offsets` is empty or reaches out of bounds.
    @discardableResult
    public mutating func removeRows(atOffsets offsets: IndexSet, inPanelAt path: PanelPath) -> Bool {
        mutateRows(inPanelAt: path) { rows in
            guard !offsets.isEmpty, offsets.allSatisfy({ rows.indices.contains($0) }) else { return false }
            rows.removeAtOffsets(offsets)
            return true
        }
    }

    /// Move the rows at `source` so they end up before the row currently at
    /// `destination` (pre-removal offsets — SwiftUI `onMove` semantics;
    /// `destination == count` means "to the end").
    @discardableResult
    public mutating func moveRows(
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        inPanelAt path: PanelPath
    ) -> Bool {
        mutateRows(inPanelAt: path) { rows in
            guard !source.isEmpty,
                  source.allSatisfy({ rows.indices.contains($0) }),
                  destination >= 0, destination <= rows.count else { return false }
            rows.moveAtOffsets(source, toOffset: destination)
            return true
        }
    }

    // MARK: Key editing

    /// Insert `key` at `index` (0...count) in the row at `rowIndex`.
    @discardableResult
    public mutating func insertKey(
        _ key: Key,
        at index: Int,
        inRowAt rowIndex: Int,
        inPanelAt path: PanelPath
    ) -> Bool {
        mutateKeys(inRowAt: rowIndex, inPanelAt: path) { keys in
            guard index >= 0, index <= keys.count else { return false }
            keys.insert(key, at: index)
            return true
        }
    }

    /// Append `key` to the row at `rowIndex`.
    @discardableResult
    public mutating func appendKey(_ key: Key, inRowAt rowIndex: Int, inPanelAt path: PanelPath) -> Bool {
        mutateKeys(inRowAt: rowIndex, inPanelAt: path) { keys in
            keys.append(key)
            return true
        }
    }

    /// Remove the keys at `offsets` from the row at `rowIndex`. Refuses
    /// (false) when `offsets` is empty or reaches out of bounds.
    @discardableResult
    public mutating func removeKeys(
        atOffsets offsets: IndexSet,
        inRowAt rowIndex: Int,
        inPanelAt path: PanelPath
    ) -> Bool {
        mutateKeys(inRowAt: rowIndex, inPanelAt: path) { keys in
            guard !offsets.isEmpty, offsets.allSatisfy({ keys.indices.contains($0) }) else { return false }
            keys.removeAtOffsets(offsets)
            return true
        }
    }

    /// Move the keys at `source` so they end up before the key currently at
    /// `destination` (pre-removal offsets — SwiftUI `onMove` semantics).
    @discardableResult
    public mutating func moveKeys(
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        inRowAt rowIndex: Int,
        inPanelAt path: PanelPath
    ) -> Bool {
        mutateKeys(inRowAt: rowIndex, inPanelAt: path) { keys in
            guard !source.isEmpty,
                  source.allSatisfy({ keys.indices.contains($0) }),
                  destination >= 0, destination <= keys.count else { return false }
            keys.moveAtOffsets(source, toOffset: destination)
            return true
        }
    }

    /// Replace the key at `index` in the row at `rowIndex` with `key`. The
    /// editor passes an edited copy that keeps the original key's `id`, so
    /// identity (and SwiftUI diffing) is stable across edits.
    @discardableResult
    public mutating func replaceKey(
        at index: Int,
        inRowAt rowIndex: Int,
        inPanelAt path: PanelPath,
        with key: Key
    ) -> Bool {
        mutateKeys(inRowAt: rowIndex, inPanelAt: path) { keys in
            guard keys.indices.contains(index) else { return false }
            keys[index] = key
            return true
        }
    }

    // MARK: Reset

    /// A copy whose `arrangements` (all panels, rows, and keys) are replaced
    /// by `source`'s, keeping this layout's own identity and metadata (`id`,
    /// `name`, `locale`, `isBuiltIn`, `derivedFrom`). The reset-to-default
    /// operation for a forked layout: callers pass the built-in referenced by
    /// `derivedFrom`. Pure — nothing is persisted.
    public func resettingContent(from source: KeyboardLayout) -> KeyboardLayout {
        var copy = self
        copy.arrangements = source.arrangements
        return copy
    }

    // MARK: Mutation plumbing

    /// Run `body` against the rows of the panel at `path`, or return false
    /// when the path doesn't exist.
    private mutating func mutateRows(
        inPanelAt path: PanelPath,
        _ body: (inout [KeyRow]) -> Bool
    ) -> Bool {
        guard arrangements.indices.contains(path.arrangementIndex),
              arrangements[path.arrangementIndex].panels.indices.contains(path.panelIndex)
        else { return false }
        return body(&arrangements[path.arrangementIndex].panels[path.panelIndex].rows)
    }

    /// Run `body` against the keys of the row at `rowIndex` in the panel at
    /// `path`, or return false when either doesn't exist.
    private mutating func mutateKeys(
        inRowAt rowIndex: Int,
        inPanelAt path: PanelPath,
        _ body: (inout [Key]) -> Bool
    ) -> Bool {
        mutateRows(inPanelAt: path) { rows in
            guard rows.indices.contains(rowIndex) else { return false }
            return body(&rows[rowIndex].keys)
        }
    }
}

// MARK: - Offset helpers

extension Array {
    /// Remove the elements at `offsets` (descending, so earlier offsets stay
    /// valid). Callers bounds-check first.
    fileprivate mutating func removeAtOffsets(_ offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            remove(at: index)
        }
    }

    /// Move the elements at `source` so they end up before the element
    /// currently at `destination`, with `destination` expressed in
    /// pre-removal offsets and `destination == count` meaning "to the end" —
    /// the same semantics as SwiftUI's `onMove`. Implemented locally so the
    /// model layer doesn't depend on a UI framework. Callers bounds-check.
    fileprivate mutating func moveAtOffsets(_ source: IndexSet, toOffset destination: Int) {
        let indices = source.sorted()
        let moved = indices.map { self[$0] }
        for index in indices.reversed() {
            remove(at: index)
        }
        let adjusted = destination - indices.filter { $0 < destination }.count
        insert(contentsOf: moved, at: adjusted)
    }
}
