//
//  LayoutTransfer.swift
//  IPAKeyboardKit
//
//  Import/export of layout documents as files (issue #8). Layouts are
//  hand-editable, diff-friendly JSON by design, so the exchange format *is*
//  the on-disk document format — export emits the document exactly as the
//  store would persist it, and import runs the same decode rules the store
//  uses (a v1 file migrates structurally on decode; a newer-than-supported
//  `schemaVersion` is rejected, never downgraded).
//
//  Imported layouts always get user-owned identity: `isBuiltIn` is forced
//  false (read-only status is not importable), and a fresh `id` is minted
//  when the document's id is already taken, so an import can never
//  overwrite an existing layout.
//

import Foundation

/// Why an imported layout document was refused. User-visible: the host app
/// surfaces `errorDescription` in its error alert, so keep these phrasings
/// actionable for end users, not developers.
public enum LayoutImportError: Error, Equatable, LocalizedError {
    /// The bytes are not a decodable layout document — malformed JSON, or
    /// valid JSON that doesn't describe a layout.
    case malformedDocument
    /// The document declares a schema version newer than this build supports.
    /// Same refuse-don't-downgrade rule as `KeyboardLayout`'s decoder, but as
    /// a distinct, explainable error instead of a generic decode failure.
    case unsupportedSchemaVersion(found: Int, supported: Int)

    public var errorDescription: String? {
        switch self {
        case .malformedDocument:
            return "This file isn’t a valid keyboard layout."
        case .unsupportedSchemaVersion(let found, let supported):
            return "This layout uses a newer format (version \(found)) than this "
                + "version of the app can read (up to version \(supported)). "
                + "Update the app and try again."
        }
    }
}

/// Pure encode/decode half of layout file exchange. Stateless and
/// container-independent so it stays fully unit-testable before the App
/// Group is provisioned; `LayoutStore.importLayout(from:)` below is the
/// persisting wrapper the host app calls.
public enum LayoutTransfer {

    /// A fresh encoder configured the way layout documents are persisted and
    /// exported: stable, diff-friendly JSON. `JSONEncoder` leaves non-ASCII
    /// text unescaped, so exact IPA code points (ɡ U+0261, ː U+02D0,
    /// combining diacritics) pass through byte-for-byte as UTF-8. A fresh
    /// instance per call because `JSONEncoder` is not documented thread-safe.
    static func makeDocumentEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// The layout encoded as its canonical JSON document — exactly what
    /// `LayoutStore.save` would write, so export → import round-trips
    /// losslessly. Works for built-ins and user layouts alike (the document
    /// is emitted as-is; the *importer* is what strips built-in identity).
    public static func exportData(for layout: KeyboardLayout) throws -> Data {
        try makeDocumentEncoder().encode(layout)
    }

    /// Suggested file name for an exported layout: the user-facing name with
    /// path-hostile separators replaced, plus the `.json` extension. All
    /// other characters — including non-ASCII IPA glyphs — are kept exactly.
    public static func exportFileName(for layout: KeyboardLayout) -> String {
        // "/" is the path separator and ":" its legacy HFS-era equivalent;
        // both are rewritten by the system in unpredictable ways, so
        // substitute them up front. No trimming/normalization beyond that.
        let sanitized = String(layout.name.map { "/:".contains($0) ? "-" : $0 })
        return (sanitized.isEmpty ? "Layout" : sanitized) + ".json"
    }

    /// Decode `data` as a layout document and give it user-owned identity.
    ///
    /// Validation is the store's own decode path (`KeyboardLayout.init(from:)`),
    /// so a v1 flat-`rows` file migrates to the current schema on the way in,
    /// and a document claiming a newer `schemaVersion` than this build
    /// supports is rejected — surfaced as the specific
    /// `.unsupportedSchemaVersion` error rather than a generic decode failure.
    ///
    /// The result is never `isBuiltIn`, and gets a fresh `id` when the
    /// document's id is already in `existingIDs` (e.g. re-importing an
    /// exported copy of a layout you already have), so importing can never
    /// overwrite an existing layout. Without a collision the document's id is
    /// preserved. Nothing is persisted here — pass the result to
    /// `LayoutStore.save`, or use `LayoutStore.importLayout(from:)`.
    public static func importableLayout(
        from data: Data,
        existingIDs: Set<UUID>
    ) throws -> KeyboardLayout {
        let decoder = JSONDecoder()

        // Probe the declared schema version first so a file from a newer app
        // gets the specific, actionable error. This mirrors — never replaces —
        // the guard inside KeyboardLayout's decoder, which still runs during
        // the full decode below.
        struct VersionProbe: Decodable { var schemaVersion: Int? }
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else {
            throw LayoutImportError.malformedDocument
        }
        if let declared = probe.schemaVersion, declared > KeyboardLayout.currentSchemaVersion {
            throw LayoutImportError.unsupportedSchemaVersion(
                found: declared, supported: KeyboardLayout.currentSchemaVersion)
        }

        guard var layout = try? decoder.decode(KeyboardLayout.self, from: data) else {
            throw LayoutImportError.malformedDocument
        }

        layout.isBuiltIn = false
        if existingIDs.contains(layout.id) {
            layout.id = UUID()
        }
        return layout
    }
}

extension LayoutStore {
    /// Validate `data` as a layout document and persist it as a new user
    /// layout, returning the layout as saved (post identity adjustments).
    ///
    /// Order matters for error quality: decode/validation runs *before* the
    /// container check, so malformed input reports `LayoutImportError` even
    /// when the App Group container is unavailable, and only a valid document
    /// that can't be persisted surfaces
    /// `StoreError.sharedContainerUnavailable` (the host app's existing
    /// "shared storage isn't set up yet" degraded-state message).
    @discardableResult
    public func importLayout(from data: Data) throws -> KeyboardLayout {
        let layout = try LayoutTransfer.importableLayout(
            from: data,
            existingIDs: Set(allLayouts().map(\.id)))
        try save(layout)
        return layout
    }
}
