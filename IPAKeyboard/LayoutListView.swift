//
//  LayoutListView.swift
//  IPAKeyboard
//
//  Root screen of the host app (roadmap step 3a — layout library). Browses the
//  bundled defaults and the user's own layouts, pushes a detail/preview screen,
//  and offers swipe-to-delete for user layouts. All data comes from
//  `LayoutLibrary`, which reads/writes through `LayoutStore`.
//
//  Accessibility identifier scheme (for ui-test-author):
//    layout-list                    — the List
//    layout-list-builtin-section    — the "Built-in" section
//    layout-list-user-section       — the "My Layouts" section
//    layout-row-<layout.id>         — each row (stable UUID; name is mutable)
//    layout-list-container-unavailable — the saving-unavailable notice
//

import SwiftUI
import IPAKeyboardKit

struct LayoutListView: View {
    @State private var library = LayoutLibrary()
    private let metrics = KeyboardMetrics()

    var body: some View {
        NavigationStack {
            List {
                activeSection
                builtInSection
                userSection
            }
            .accessibilityIdentifier("layout-list")
            .navigationTitle("Layouts")
            .navigationDestination(for: KeyboardLayout.self) { layout in
                LayoutDetailView(layout: layout, library: library)
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) { library.errorMessage = nil } },
            message: { Text(library.errorMessage ?? "") }
        )
    }

    private var activeSection: some View {
        Section {
            let active = library.activeLayout
            VStack(alignment: .leading, spacing: 8) {
                Text(active.name)
                    .font(.headline)
                KeyboardView(layout: active) { _ in }
                    .frame(height: metrics.totalHeight(for: active.primaryArrangement))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("layout-list-active-preview")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        } header: {
            Text("Active")
        } footer: {
            if library.selectionReachesKeyboard {
                Text("The layout the keyboard shows. Open any layout and tap "
                    + "“Use this Layout” to change it.")
            } else {
                Text("The layout the keyboard will show. It won’t reach the "
                    + "keyboard on your device until the extension’s shared "
                    + "storage is set up.")
                    .accessibilityIdentifier("layout-list-selection-unavailable")
            }
        }
        .accessibilityIdentifier("layout-list-active-section")
    }

    private var builtInSection: some View {
        Section {
            ForEach(library.builtInLayouts) { layout in
                layoutRow(layout)
            }
        } header: {
            Text("Built-in")
        } footer: {
            if !library.containerAvailable {
                Text("Editing a built-in creates your own copy. Saving isn’t "
                    + "available yet — the keyboard’s shared storage is still "
                    + "being set up.")
                    .accessibilityIdentifier("layout-list-container-unavailable")
            } else {
                Text("Built-in layouts are read-only. Open one to preview it or "
                    + "duplicate it for editing.")
            }
        }
        .accessibilityIdentifier("layout-list-builtin-section")
    }

    private var userSection: some View {
        Section {
            if library.userLayouts.isEmpty {
                Text("You haven’t created any layouts yet. Open a built-in and "
                    + "tap “Duplicate to Edit” to start one.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(library.userLayouts) { layout in
                    layoutRow(layout)
                }
                .onDelete(perform: deleteUserLayouts)
            }
        } header: {
            Text("My Layouts")
        }
        .accessibilityIdentifier("layout-list-user-section")
    }

    private func layoutRow(_ layout: KeyboardLayout) -> some View {
        NavigationLink(value: layout) {
            LayoutRow(layout: layout, isActive: layout.id == library.resolvedActiveLayoutID)
        }
        .accessibilityIdentifier("layout-row-\(layout.id.uuidString)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !layout.isBuiltIn {
                Button(role: .destructive) {
                    library.delete(layout)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func deleteUserLayouts(at offsets: IndexSet) {
        // Snapshot before deleting: `library.delete` reloads and reassigns
        // `userLayouts`, so indexing it again mid-loop would go out of bounds
        // (or hit the wrong row) once `offsets` holds more than one index.
        let layoutsToDelete = offsets.map { library.userLayouts[$0] }
        for layout in layoutsToDelete {
            library.delete(layout)
        }
    }
}

/// One row in the layout list: an active checkmark, name, locale, and a lock
/// badge for built-ins.
private struct LayoutRow: View {
    let layout: KeyboardLayout
    let isActive: Bool

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
                .opacity(isActive ? 1 : 0)
                .accessibilityHidden(!isActive)
                .accessibilityLabel("Active")
            VStack(alignment: .leading, spacing: 2) {
                Text(layout.name)
                    .font(.body)
                Text(layout.locale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if layout.isBuiltIn {
                Label("Built-in", systemImage: "lock.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Built-in, read-only")
            }
        }
    }
}

#if DEBUG
#Preview {
    LayoutListView()
}
#endif
