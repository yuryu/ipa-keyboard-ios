//
//  LayoutStore.swift
//  IPAKeyboardKit
//
//  Loads built-in default layouts from the framework bundle and user
//  layouts from the App Group container, and persists user edits. Works
//  with bundled defaults alone even before the App Group is configured.
//

import Foundation

public final class LayoutStore {
    public enum StoreError: Error {
        /// The App Group container is unavailable, so user layouts can't be
        /// written. Enable the App Group capability on both targets in Xcode.
        case sharedContainerUnavailable
    }

    private let fileManager: FileManager
    private let bundle: Bundle
    private let containerURL: URL?

    /// - Parameter containerURL: Root of the shared container user layouts
    ///   are persisted under (a `"Layouts"` subdirectory is created inside
    ///   it). Defaults to `AppGroup.containerURL`, which is `nil` until the
    ///   App Group capability is provisioned — callers get the same
    ///   graceful degradation to bundled-only behavior as before. Tests can
    ///   inject a temporary directory here to exercise the full save/delete
    ///   I/O path hermetically, without App Group provisioning.
    public init(
        fileManager: FileManager = .default,
        bundle: Bundle = IPAResources.bundle,
        containerURL: URL? = AppGroup.containerURL
    ) {
        self.fileManager = fileManager
        self.bundle = bundle
        self.containerURL = containerURL
    }

    // MARK: Reading

    /// Built-in default layouts shipped read-only in the framework bundle,
    /// auto-discovered so adding a new locale JSON needs no code change.
    public func bundledLayouts() -> [KeyboardLayout] {
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return urls.compactMap { url in
            guard var layout = try? decodeLayout(at: url) else { return nil }
            layout.isBuiltIn = true // bundle copies are always read-only
            return layout
        }
        .sorted { $0.name < $1.name }
    }

    /// User-created and user-edited layouts from the shared container.
    public func userLayouts() -> [KeyboardLayout] {
        guard let dir = userLayoutsDirectory,
              let urls = try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decodeLayout(at: $0) }
            .sorted { $0.name < $1.name }
    }

    /// Built-ins plus user layouts — the full set the editor and keyboard show.
    public func allLayouts() -> [KeyboardLayout] {
        bundledLayouts() + userLayouts()
    }

    // MARK: Writing (user layouts only)

    public func save(_ layout: KeyboardLayout) throws {
        guard let dir = userLayoutsDirectory else { throw StoreError.sharedContainerUnavailable }
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        // Fresh encoder per save (`makeDocumentEncoder` is documented
        // fresh-per-call; `JSONEncoder` isn't documented thread-safe), shared
        // with `LayoutTransfer.exportData` so a saved document and an exported
        // one are byte-for-byte the same format.
        let data = try LayoutTransfer.makeDocumentEncoder().encode(layout)
        try data.write(to: fileURL(for: layout.id, in: dir), options: .atomic)
    }

    public func delete(id: UUID) throws {
        guard let dir = userLayoutsDirectory else { throw StoreError.sharedContainerUnavailable }
        let url = fileURL(for: id, in: dir)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: Helpers

    private var userLayoutsDirectory: URL? {
        containerURL?.appendingPathComponent("Layouts", isDirectory: true)
    }

    private func fileURL(for id: UUID, in dir: URL) -> URL {
        dir.appendingPathComponent("\(id.uuidString).json")
    }

    private func decodeLayout(at url: URL) throws -> KeyboardLayout {
        try decoder.decode(KeyboardLayout.self, from: Data(contentsOf: url))
    }

    private let decoder = JSONDecoder()
}
