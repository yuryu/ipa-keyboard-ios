//
//  SymbolReferenceView.swift
//  IPAKeyboard
//
//  Searchable symbol reference (issue #17): every symbol the bundled layouts
//  can insert — glyph, spoken name, exact Unicode code points, and which
//  layouts/panels contain it — derived at runtime via `SymbolInventory` over
//  `LayoutStore` (see SymbolReferenceModel.swift). Search matches spoken-name
//  fragments ("nasal"), pasted glyphs (scalar-exact: ASCII g never finds ɡ),
//  and code-point queries ("U+0261" or "0261"). Presented as a sheet from the
//  layout list's toolbar.
//
//  Tap a symbol for its detail: exact per-scalar code points with Unicode
//  names, copy-to-pasteboard, and an add-to-scratchpad action that collects
//  symbols into a copyable string on the reference's main screen.
//
//  Accessibility identifier scheme (for ui-test-author):
//    symbol-reference-list           — the root List
//    symbol-reference-row-<text>     — each symbol row (keyed by the exact
//                                      inserted string, e.g. "…-row-ɡ")
//    symbol-reference-empty          — the no-search-results placeholder
//    symbol-reference-done           — toolbar Done button (dismisses sheet)
//    symbol-reference-scratch        — the scratchpad text
//    symbol-reference-scratch-copy   — copies the scratchpad
//    symbol-reference-scratch-clear  — clears the scratchpad
//    symbol-detail-glyph             — the large glyph on the detail screen
//    symbol-detail-spoken-name       — the spoken name on the detail screen
//    symbol-detail-codepoint-<n>     — the n-th (0-based) "U+XXXX" readout
//    symbol-detail-copy              — copies the symbol's exact text
//    symbol-detail-add-scratch       — appends the symbol to the scratchpad
//  The search field carries no custom identifier (SwiftUI `.searchable`
//  doesn't take one); match it with `app.searchFields.firstMatch`. It uses
//  `.navigationBarDrawer(displayMode: .always)` so it is always hittable
//  without a reveal swipe.
//

import SwiftUI
import UIKit
import IPAKeyboardKit

struct SymbolReferenceView: View {
    @State private var model = SymbolReferenceModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                scratchpadSection
                symbolsSection
            }
            .accessibilityIdentifier("symbol-reference-list")
            .navigationTitle("Symbol Reference")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $model.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Name, symbol, or code point")
            // Search input must stay byte-exact: a pasted glyph or a typed
            // code point must never be autocorrected or capitalized away.
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            .navigationDestination(for: SymbolEntry.self) { entry in
                SymbolDetailView(entry: entry, model: model)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("symbol-reference-done")
                }
            }
        }
    }

    @ViewBuilder
    private var scratchpadSection: some View {
        if !model.scratchpad.isEmpty {
            Section {
                Text(model.scratchpad)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("symbol-reference-scratch")
                Button {
                    UIPasteboard.general.string = model.scratchpad
                } label: {
                    Label("Copy Scratchpad", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("symbol-reference-scratch-copy")
                Button("Clear Scratchpad", role: .destructive) {
                    model.clearScratchpad()
                }
                .accessibilityIdentifier("symbol-reference-scratch-clear")
            } header: {
                Text("Scratchpad")
            } footer: {
                Text("Symbols you add from their detail screens, collected "
                    + "into one exact string to copy.")
            }
        }
    }

    @ViewBuilder
    private var symbolsSection: some View {
        if model.filtered.isEmpty {
            Section {
                ContentUnavailableView.search(text: model.query)
                    .accessibilityIdentifier("symbol-reference-empty")
            }
        } else {
            Section {
                ForEach(model.filtered) { entry in
                    NavigationLink(value: entry) {
                        SymbolReferenceRow(entry: entry)
                    }
                    .accessibilityIdentifier("symbol-reference-row-\(entry.text)")
                }
            } footer: {
                Text("Derived from the bundled layouts. Search by name "
                    + "(“nasal”), by pasting a symbol, or by code point "
                    + "(“U+0261”). Tap a symbol for its exact code points "
                    + "and where it appears.")
            }
        }
    }
}

/// One row: the glyph, its spoken name, and its exact code points.
private struct SymbolReferenceRow: View {
    let entry: SymbolEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.displayLabel)
                .font(.title2)
                .frame(minWidth: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.spokenName ?? "No spoken name")
                    .font(.body)
                    .foregroundStyle(entry.spokenName == nil ? .secondary : .primary)
                Text(entry.codePointNotation)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.spokenName ?? entry.displayLabel)
    }
}

/// Detail for one symbol: large glyph, spoken name, exact per-scalar code
/// points (with Unicode character names), copy / add-to-scratchpad actions,
/// and every layout/panel the symbol appears in.
struct SymbolDetailView: View {
    let entry: SymbolEntry
    let model: SymbolReferenceModel

    /// Sticky "Copied" feedback — deliberately not auto-reverting, so the
    /// state stays deterministic for UI tests and screen readers.
    @State private var copied = false

    var body: some View {
        List {
            glyphSection
            codePointsSection
            actionsSection
            occurrencesSection
        }
        .navigationTitle(entry.spokenName ?? entry.displayLabel)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var glyphSection: some View {
        Section {
            VStack(spacing: 8) {
                Text(entry.displayLabel)
                    .font(.system(size: 64))
                    .accessibilityIdentifier("symbol-detail-glyph")
                    .accessibilityLabel(entry.spokenName ?? entry.displayLabel)
                if let spokenName = entry.spokenName {
                    Text(spokenName)
                        .font(.headline)
                        .accessibilityIdentifier("symbol-detail-spoken-name")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var codePointsSection: some View {
        Section("Code Points") {
            ForEach(entry.codePoints) { codePoint in
                HStack(alignment: .firstTextBaseline) {
                    Text(codePoint.notation)
                        .font(.body.monospaced())
                        .accessibilityIdentifier("symbol-detail-codepoint-\(codePoint.ordinal)")
                    if let unicodeName = codePoint.unicodeName {
                        Text(unicodeName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                UIPasteboard.general.string = entry.text
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy Symbol",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .accessibilityIdentifier("symbol-detail-copy")
            Button {
                model.addToScratchpad(entry)
            } label: {
                Label("Add to Scratchpad", systemImage: "plus.square")
            }
            .accessibilityIdentifier("symbol-detail-add-scratch")
        } footer: {
            Text("Copying uses the symbol's exact text (\(entry.codePointNotation)). "
                + "The scratchpad collects symbols on the reference's main screen.")
        }
    }

    private var occurrencesSection: some View {
        Section("Found In") {
            ForEach(entry.occurrences, id: \.self) { occurrence in
                VStack(alignment: .leading, spacing: 2) {
                    Text(occurrence.layoutName)
                    Text(occurrence.panelName
                        + (occurrence.isAlternate ? " — long-press alternate" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Reference") {
    SymbolReferenceView()
}

#Preview("Detail") {
    let entries = SymbolInventory.build(from: LayoutStore().bundledLayouts())
    let entry = entries.first ?? SymbolEntry(
        text: "\u{0261}",
        spokenName: "voiced velar plosive",
        occurrences: [SymbolOccurrence(layoutName: "Sample", panelName: "IPA", isAlternate: false)])
    return NavigationStack {
        SymbolDetailView(entry: entry, model: SymbolReferenceModel())
    }
}
#endif
