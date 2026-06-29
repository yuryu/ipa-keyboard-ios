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

    public init(fileManager: FileManager = .default, bundle: Bundle = IPAResources.bundle) {
        self.fileManager = fileManager
        self.bundle = bundle
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
        let data = try encoder.encode(layout)
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
        AppGroup.containerURL?.appendingPathComponent("Layouts", isDirectory: true)
    }

    private func fileURL(for id: UUID, in dir: URL) -> URL {
        dir.appendingPathComponent("\(id.uuidString).json")
    }

    private func decodeLayout(at url: URL) throws -> KeyboardLayout {
        try decoder.decode(KeyboardLayout.self, from: Data(contentsOf: url))
    }

    private let decoder = JSONDecoder()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // Stable, diff-friendly output for layouts saved to the container.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}
