//
//  LayoutEditorView.swift
//  IPAKeyboard
//
//  Per-layout symbol curation (roadmap step 5). The user toggles which of a
//  layout's IPA symbols are enabled; hidden symbols are stored as a reversible
//  sidecar (see `KeyboardPreferences`) — the layout's JSON is never modified. A
//  live `KeyboardView` preview and an interactive scratchpad show, and let the
//  user type with, exactly the curated set, so curation is usable in-host even
//  before the App Group is provisioned.
//
//  Accessibility identifier scheme (for ui-test-author):
//    layout-editor-preview          — the live curated keyboard preview
//    layout-editor-scratch          — the typed-text scratchpad
//    layout-editor-clear            — clears the scratchpad
//    layout-editor-toggle-<symbol>  — per-symbol enable toggle
//

import SwiftUI
import IPAKeyboardKit

struct LayoutEditorView: View {
    let layout: KeyboardLayout
    let library: LayoutLibrary

    /// Local, snappy mirror of the hidden set; persisted through `library` on
    /// each change (which also updates the observed mirror the list preview
    /// reads). Loaded from storage in `onAppear`.
    @State private var hidden: Set<String> = []
    @State private var scratch = ""

    private let metrics = KeyboardMetrics()

    private var curated: KeyboardLayout { layout.applyingHiddenSymbols(hidden) }

    var body: some View {
        List {
            previewSection
            scratchSection
            symbolsSection
        }
        .navigationTitle("Symbols")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hidden = library.hiddenSymbols(for: layout) }
    }

    private var previewSection: some View {
        Section("Preview") {
            KeyboardView(layout: curated) { handleScratch($0) }
                .frame(height: metrics.totalHeight(for: curated.primaryArrangement))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("layout-editor-preview")
                .listRowInsets(EdgeInsets())
                .background(Color(uiColor: .systemBackground))
        }
    }

    private var scratchSection: some View {
        Section("Scratchpad") {
            Text(scratch.isEmpty ? "Type with the keyboard above…" : scratch)
                .foregroundStyle(scratch.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityIdentifier("layout-editor-scratch")
            if !scratch.isEmpty {
                Button("Clear", role: .destructive) { scratch = "" }
                    .accessibilityIdentifier("layout-editor-clear")
            }
        }
    }

    @ViewBuilder
    private var symbolsSection: some View {
        ForEach(curatablePanels, id: \.name) { panel in
            Section(panel.name) {
                ForEach(panel.symbols, id: \.self) { symbol in
                    Toggle(isOn: binding(for: symbol)) {
                        Text(symbol).font(.title3)
                    }
                    .accessibilityIdentifier("layout-editor-toggle-\(symbol)")
                }
            }
        }
    }

    // MARK: Symbol collection

    private struct PanelSymbols { let name: String; let symbols: [String] }

    /// Distinct inserted symbols grouped by panel (main keys then long-press
    /// alternates), first-seen order, de-duplicated across the whole layout so
    /// each toggle appears once.
    private var curatablePanels: [PanelSymbols] {
        var seen = Set<String>()
        var panels: [PanelSymbols] = []
        for panel in layout.arrangements.flatMap(\.panels) {
            var symbols: [String] = []
            for key in panel.rows.flatMap(\.keys) {
                for candidate in [key] + key.alternates {
                    if case .insert(let text) = candidate.action, seen.insert(text).inserted {
                        symbols.append(text)
                    }
                }
            }
            if !symbols.isEmpty { panels.append(PanelSymbols(name: panel.name, symbols: symbols)) }
        }
        return panels
    }

    private func binding(for symbol: String) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(symbol) },
            set: { enabled in
                if enabled { hidden.remove(symbol) } else { hidden.insert(symbol) }
                library.setHiddenSymbols(hidden, for: layout)
            }
        )
    }

    // MARK: Scratchpad input

    /// Apply a preview key press to the scratch buffer. Backspace removes one
    /// grapheme cluster (`String.removeLast()` is cluster-aware), matching the
    /// extension. Panel switches are handled inside `KeyboardView`; the globe and
    /// spacers have no meaning in the preview.
    private func handleScratch(_ action: KeyAction) {
        switch action {
        case .insert(let text): scratch += text
        case .space: scratch += " "
        case .return: scratch += "\n"
        case .backspace: if !scratch.isEmpty { scratch.removeLast() }
        case .nextKeyboard, .switchPanel, .spacer: break
        @unknown default: break
        }
    }
}

#if DEBUG
#Preview {
    let layout = LayoutStore().bundledLayouts().first ?? KeyboardLayout(
        name: "Sample", locale: "en-US",
        rows: [KeyRow(keys: [.insert("ə"), .insert("i"), .insert("u")])])
    return NavigationStack {
        LayoutEditorView(layout: layout, library: LayoutLibrary())
    }
}
#endif
