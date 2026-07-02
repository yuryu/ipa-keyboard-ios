//
//  LayoutDetailView.swift
//  IPAKeyboard
//
//  Detail/preview screen for a single layout (roadmap step 3a). Shows the
//  layout's metadata and a live `KeyboardView` preview, and offers the two
//  whole-layout actions for this increment: "Duplicate to Edit" (fork a
//  built-in) and "Delete" (remove a user layout). Per-key editing is out of
//  scope here.
//
//  Accessibility identifier scheme (for ui-test-author):
//    layout-detail-preview         — the live keyboard preview container
//    layout-detail-duplicate-button — "Duplicate to Edit" (built-ins only)
//    layout-detail-delete-button    — "Delete" (user layouts only)
//

import SwiftUI
import IPAKeyboardKit

struct LayoutDetailView: View {
    let layout: KeyboardLayout
    let library: LayoutLibrary

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false

    private let metrics = KeyboardMetrics()

    var body: some View {
        List {
            metadataSection
            previewSection
            useSection
            customizeSection
            actionSection
        }
        .navigationTitle(layout.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var metadataSection: some View {
        Section("Details") {
            LabeledContent("Name", value: layout.name)
            LabeledContent("Locale", value: layout.locale)
            LabeledContent("Type", value: layout.isBuiltIn ? "Built-in" : "Custom")
            LabeledContent("Arrangements", value: "\(layout.arrangements.count)")
            if let primary = layout.primaryArrangement {
                LabeledContent("Primary arrangement", value: primary.name)
            }
            if layout.derivedFrom != nil {
                LabeledContent("Origin", value: "Forked from a built-in")
            }
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            // Live render via the shared kit view. There is no host document
            // here, so actions are intentionally dropped; panel-switch keys are
            // handled inside KeyboardView and never reach this closure.
            KeyboardView(layout: layout) { _ in }
                .frame(height: metrics.totalHeight(for: layout.primaryArrangement))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("layout-detail-preview")
                .listRowInsets(EdgeInsets())
                .background(Color(uiColor: .systemBackground))
        }
    }

    @ViewBuilder
    private var useSection: some View {
        Section {
            if layout.id == library.resolvedActiveLayoutID {
                Label("Active layout", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("layout-detail-active-label")
            } else {
                Button {
                    library.setActive(layout)
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
            NavigationLink {
                LayoutEditorView(layout: layout, library: library)
            } label: {
                Label("Customize symbols", systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("layout-detail-customize-link")
        } footer: {
            Text("Hide symbols you don’t use. This is a personal overlay — the "
                + "layout’s data isn’t changed.")
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            if layout.isBuiltIn {
                Button {
                    library.fork(layout)
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
            if layout.isBuiltIn {
                Text("Built-in layouts are read-only. Duplicating makes an "
                    + "editable copy under “My Layouts.”")
            }
        }
        .confirmationDialog(
            "Delete “\(layout.name)”?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                library.delete(layout)
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
