//
//  LayoutExportItem.swift
//  IPAKeyboard
//
//  Transferable wrapper that lets a `ShareLink` export a layout as its JSON
//  document (issue #8). All of the actual encoding lives in the kit
//  (`LayoutTransfer.exportData` / `exportFileName`) so the exported bytes are
//  exactly what `LayoutStore` persists; this type only stages the file for
//  the share sheet.
//
//  `nonisolated`: the app target defaults to MainActor isolation, but
//  `Transferable`'s requirements (and `FileRepresentation`'s @Sendable
//  exporting closure) are nonisolated, so the whole type opts out. It only
//  holds an immutable, Sendable `KeyboardLayout`.
//

import CoreTransferable
import UniformTypeIdentifiers
import IPAKeyboardKit

nonisolated struct LayoutExportItem: Transferable {
    let layout: KeyboardLayout

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            // A unique staging directory per export so concurrent shares (or
            // same-named layouts) never clobber each other; the system copies
            // the file out, and temporaryDirectory is purged by the OS.
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LayoutExports", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(
                LayoutTransfer.exportFileName(for: item.layout))
            try LayoutTransfer.exportData(for: item.layout).write(to: fileURL, options: .atomic)
            return SentTransferredFile(fileURL)
        }
    }
}
