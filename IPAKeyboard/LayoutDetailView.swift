//
//  LayoutDetailView.swift
//  IPAKeyboard
//
//  Detail/preview screen for a single layout (roadmap step 3a). Shows the
//  layout's metadata and a live `KeyboardView` preview, and offers the
//  whole-layout actions: "Duplicate to Edit" (fork a built-in), "Edit Keys"
//  (key-level editing of a user layout, issue #6), and "Delete" (remove a
//  user layout).
//
//  Accessibility identifier scheme (for ui-test-author):
//    layout-detail-preview          — the live keyboard preview: one
//                                     accessibility container element; the
//                                     keys inside expose stable per-key
//                                     identifiers ("key-insert-<text>", …) —
//                                     see the scheme doc on
//                                     Key.accessibilityIdentifier in
//                                     IPAKeyboardKit's KeyboardView.swift
//    layout-detail-active-label     — "Active layout" indicator (when this is
//                                     the active layout)
//    layout-detail-use-button       — "Use this Layout" (when not the active
//                                     layout)
//    layout-detail-duplicate-button — "Duplicate to Edit" (built-ins only)
//    layout-detail-edit-keys-button — "Edit Keys" (user layouts only)
//    layout-detail-customize-link   — "Customize symbols" (all layouts)
//    layout-detail-export-button    — "Export Layout" ShareLink (all layouts,
//                                     issue #8; see LayoutExportItem.swift)
//    layout-detail-delete-button    — "Delete" (user layouts only)
//

import SwiftUI
import IPAKeyboardKit

struct LayoutDetailView: View {
    let layout: KeyboardLayout
    let library: LayoutLibrary

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showingDeleteConfirmation = false
    @State private var showingKeyEditor = false

    /// Same size selection as the extension (compact rows in iPhone
    /// landscape), so the preview mirrors what the keyboard will render.
    private var metrics: KeyboardMetrics {
        .metrics(forCompactHeight: verticalSizeClass == .compact)
    }

    /// The up-to-date copy of this layout. The navigation value we were
    /// pushed with is a snapshot; after the key editor saves, the library
    /// reloads and this lookup picks up the new content so the metadata and
    /// preview refresh. Falls back to the snapshot when the layout no longer
    /// exists (mid-dismiss after a delete).
    private var current: KeyboardLayout {
        (library.userLayouts + library.builtInLayouts).first { $0.id == layout.id } ?? layout
    }

    var body: some View {
        List {
            metadataSection
            previewSection
            useSection
            customizeSection
            exportSection
            actionSection
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingKeyEditor) {
            LayoutKeyEditorView(layout: current, library: library)
        }
    }

    private var metadataSection: some View {
        Section("Details") {
            LabeledContent("Name", value: current.name)
            LabeledContent("Locale", value: current.locale)
            LabeledContent("Type", value: current.isBuiltIn ? "Built-in" : "Custom")
            LabeledContent("Arrangements", value: "\(current.arrangements.count)")
            if let primary = current.primaryArrangement {
                LabeledContent("Primary arrangement", value: primary.name)
            }
            if current.derivedFrom != nil {
                LabeledContent("Origin", value: "Forked from a built-in")
            }
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            // Live render via the shared kit view. There is no host document
            // here, so actions are intentionally dropped; panel-switch keys are
            // handled inside KeyboardView and never reach this closure.
            KeyboardView(layout: current, metrics: metrics) { _ in }
                .frame(height: metrics.totalHeight(for: current.primaryArrangement))
                .frame(maxWidth: .infinity)
                // One accessibility *container* element carrying the
                // identifier (issue #25): without `children: .contain` an
                // identifier on this non-element view bleeds onto every key
                // inside, clobbering their per-key identifiers, and no single
                // "layout-detail-preview" element exists. Keys stay
                // individually navigable for VoiceOver.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("layout-detail-preview")
                // Inset the keys clear of the list card's rounded-corner
                // mask (issue #100); the chrome color below still bleeds to
                // the card edge.
                .padding(PreviewChrome.padding)
                .listRowInsets(EdgeInsets())
                // The keyboard-chrome color (adapts light/dark) instead of the
                // plain background, so white keycaps stay visible in light mode.
                .background(Color(uiColor: KeyboardChrome.background))
        }
    }

    @ViewBuilder
    private var useSection: some View {
        Section {
            if current.id == library.resolvedActiveLayoutID {
                Label("Active layout", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("layout-detail-active-label")
            } else {
                Button {
                    library.setActive(current)
                } label: {
                    Label("Use this Layout", systemImage: "keyboard")
                }
                .accessibilityIdentifier("layout-detail-use-button")
            }
        } footer: {
            if !library.selectionReachesKeyboard {
                Text("Selecting a layout won’t reach the keyboard on your device "
                    + "until the extension’s shared storage is set up.")
            }
        }
    }

    private var customizeSection: some View {
        Section {
            if !current.isBuiltIn {
                Button {
                    showingKeyEditor = true
                } label: {
                    Label("Edit Keys", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("layout-detail-edit-keys-button")
            }
            NavigationLink {
                LayoutEditorView(layout: current, library: library)
            } label: {
                Label("Customize symbols", systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("layout-detail-customize-link")
        } footer: {
            if current.isBuiltIn {
                Text("Hide symbols you don’t use. This is a personal overlay — "
                    + "the layout’s data isn’t changed.")
            } else {
                Text("Edit Keys changes this layout’s rows and keys. Customize "
                    + "symbols is a reversible overlay that doesn’t change the "
                    + "layout’s data.")
            }
        }
    }

    private var exportSection: some View {
        Section {
            // Exports the document exactly as the store persists it (kit's
            // LayoutTransfer via LayoutExportItem), for any layout — sharing
            // a built-in is fine; only *importing* strips built-in identity.
            ShareLink(
                item: LayoutExportItem(layout: current),
                preview: SharePreview(current.name)
            ) {
                Label("Export Layout", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("layout-detail-export-button")
        } footer: {
            Text("Shares this layout as a JSON file. Import it from the "
                + "Layouts screen on any device.")
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            if current.isBuiltIn {
                Button {
                    library.fork(current)
                    dismiss()
                } label: {
                    Label("Duplicate to Edit", systemImage: "plus.square.on.square")
                }
                .accessibilityIdentifier("layout-detail-duplicate-button")
            } else {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityIdentifier("layout-detail-delete-button")
            }
        } footer: {
            if current.isBuiltIn {
                Text("Built-in layouts are read-only. Duplicating makes an "
                    + "editable copy under “My Layouts.”")
            }
        }
        .confirmationDialog(
            "Delete “\(current.name)”?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                library.delete(current)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the layout permanently.")
        }
    }
}

#if DEBUG
#Preview {
    let layout = LayoutStore().bundledLayouts().first ?? KeyboardLayout(
        name: "Sample",
        locale: "en-US",
        rows: [KeyRow(keys: [.insert("ə"), .insert("i"), .insert("u")])]
    )
    return NavigationStack {
        LayoutDetailView(layout: layout, library: LayoutLibrary())
    }
}
#endif
