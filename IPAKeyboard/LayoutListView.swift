//
//  LayoutListView.swift
//  IPAKeyboard
//
//  Root screen of the host app (roadmap step 3a — layout library). Browses the
//  bundled defaults and the user's own layouts, pushes a detail/preview screen,
//  and offers swipe-to-delete for user layouts. The Active section also hosts a
//  small typing scratchpad (issue #103) so keyboard settings can be tried
//  in-app. All data comes from `LayoutLibrary`, which reads/writes through
//  `LayoutStore`.
//
//  Accessibility identifier scheme (for ui-test-author):
//    layout-list                    — the List
//    layout-list-active-section     — the "Active" section header
//    layout-list-active-preview     — live KeyboardView preview of the active
//                                     layout in the Active section; its keys
//                                     type into the scratchpad (issue #115)
//    layout-list-selection-unavailable — Active-section footer shown when the
//                                     active selection can't yet reach the
//                                     keyboard (shared storage not set up)
//    layout-list-builtin-section    — the "Built-in" section header
//    layout-list-user-section       — the "My Layouts" section header
//    layout-row-<layout.id>         — each row (stable UUID; name is mutable)
//    layout-list-container-unavailable — the saving-unavailable notice
//    layout-list-help-button        — toolbar button reopening the onboarding
//                                     guidance (see OnboardingView.swift)
//    layout-list-import-button      — toolbar button opening the file importer
//                                     (issue #8; import logic in LayoutLibrary)
//    layout-list-symbol-reference-button — toolbar button opening the symbol
//                                     reference (see SymbolReferenceView.swift)
//    layout-list-scratch            — scratchpad text field under the active
//                                     preview for trying the keyboard without
//                                     switching apps (issue #103)
//    layout-list-scratch-clear      — clears the scratchpad (only rendered
//                                     while it has text)
//
//  Section identifiers go on the header Text, never on the Section itself:
//  a modifier on Section is applied to every row, which would overwrite the
//  per-row `layout-row-<id>` identifiers (observed on the iOS 26 SDK).
//

import SwiftUI
import UniformTypeIdentifiers
import IPAKeyboardKit

struct LayoutListView: View {
    @State private var library = LayoutLibrary()
    @State private var onboarding = OnboardingState()
    @State private var showingImporter = false
    @State private var showingSymbolReference = false
    /// Scratchpad text (issue #103). Deliberately transient `@State`: it is a
    /// test surface, not a document, so it resets with the screen.
    @State private var scratch = ""
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Same size selection as the extension (compact rows in iPhone
    /// landscape), so the preview mirrors what the keyboard will render.
    private var metrics: KeyboardMetrics {
        .metrics(forCompactHeight: verticalSizeClass == .compact)
    }

    var body: some View {
        NavigationStack {
            List {
                activeSection
                builtInSection
                userSection
            }
            .accessibilityIdentifier("layout-list")
            // The scratchpad summons a keyboard with no other dismissal
            // affordance on this screen; dragging the list puts it away.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Layouts")
            .navigationDestination(for: KeyboardLayout.self) { layout in
                LayoutDetailView(layout: layout, library: library)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import Layout", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("layout-list-import-button")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSymbolReference = true
                    } label: {
                        Label("Symbol Reference", systemImage: "character.book.closed")
                    }
                    .accessibilityIdentifier("layout-list-symbol-reference-button")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onboarding.presentManually()
                    } label: {
                        Label("Keyboard Setup Help", systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("layout-list-help-button")
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json]
            ) { result in
                library.importLayout(from: result)
            }
        }
        .sheet(isPresented: $onboarding.isPresented, onDismiss: { onboarding.markSeen() }) {
            OnboardingView()
        }
        .sheet(isPresented: $showingSymbolReference) {
            SymbolReferenceView()
        }
        .onAppear {
            onboarding.presentIfFirstRun()
            library.performLaunchImportIfRequested()
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
                // Preview key presses feed the scratchpad below (issue #115,
                // same reducer as LayoutEditorView), so the active layout is
                // try-able right here even before the extension is enabled.
                KeyboardView(layout: active, metrics: metrics) { ScratchInput.apply($0, to: &scratch) }
                    .frame(height: metrics.totalHeight(for: active.primaryArrangement))
                    .frame(maxWidth: .infinity)
                    // Explicit accessibility container so the identifier
                    // names one element instead of bleeding onto every key
                    // (issue #25; same pattern as LayoutDetailView's preview).
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("layout-list-active-preview")
                    // Keyboard-chrome backdrop (adapts light/dark) so the
                    // white light-mode keycaps don't vanish into the row. A
                    // shaped background, not a clip: long-press popups may
                    // extend past the preview's bounds.
                    .background(
                        Color(uiColor: KeyboardChrome.background),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                // Scratchpad (issue #103): a real text field, so the user can
                // switch to the IPA keyboard right here and try the active
                // layout — settings changes are testable without leaving the
                // app. Autocorrection/capitalization are off so typed IPA
                // survives exactly as sent (no ɡ U+0261 → ASCII g "fixes").
                HStack(spacing: 8) {
                    TextField(
                        "Type here to try the keyboard…",
                        text: $scratch,
                        axis: .vertical
                    )
                    .font(.callout)
                    .lineLimit(1...4)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("layout-list-scratch")
                    if !scratch.isEmpty {
                        Button {
                            scratch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        // Borderless keeps the tap target on the icon instead
                        // of promoting the whole list row to a button.
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear scratchpad")
                        .accessibilityIdentifier("layout-list-scratch-clear")
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        } header: {
            Text("Active")
                .accessibilityIdentifier("layout-list-active-section")
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
    }

    private var builtInSection: some View {
        Section {
            ForEach(library.builtInLayouts) { layout in
                layoutRow(layout)
            }
        } header: {
            Text("Built-in")
                .accessibilityIdentifier("layout-list-builtin-section")
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
                .accessibilityIdentifier("layout-list-user-section")
        }
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
