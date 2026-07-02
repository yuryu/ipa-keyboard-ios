//
//  LayoutKeyEditorView.swift
//  IPAKeyboard
//
//  Key-level editor for a user layout (issue #6): add/remove/reorder rows,
//  drill into a row to edit its keys, live-preview the draft, and reset the
//  content back to the built-in the layout was forked from. Presented as a
//  sheet with its own NavigationStack so Save/Cancel bracket the whole edit:
//  every mutation hits a `LayoutDraft` working copy, Cancel discards it, and
//  only Save persists (through `LayoutLibrary.update` → `LayoutStore`). User
//  layouts only — built-ins keep "Duplicate to Edit" as their entry point.
//
//  Accessibility identifier scheme (for ui-test-author):
//    key-editor                 — the root List
//    key-editor-cancel          — Cancel (confirms discard when dirty)
//    key-editor-save            — Save (disabled until there are changes)
//    key-editor-preview         — live draft preview
//    key-editor-panel-picker    — panel picker (only when >1 panel)
//    key-editor-row-<index>     — row link (0-based, within the shown panel)
//    key-editor-add-row         — appends an empty row
//    key-editor-reset           — reset content to the built-in source
//    key-editor-reset-confirm   — confirm button in the reset dialog
//    key-editor-discard-confirm — confirm button in the discard dialog
//

import SwiftUI
import IPAKeyboardKit

/// Navigation value for drilling into one row of the shown panel.
private struct EditedRowIndex: Hashable {
    let index: Int
}

struct LayoutKeyEditorView: View {
    @State private var draft: LayoutDraft
    @Environment(\.dismiss) private var dismiss

    @State private var showingDiscardConfirmation = false
    @State private var showingResetConfirmation = false

    private let metrics = KeyboardMetrics()

    init(layout: KeyboardLayout, library: LayoutLibrary) {
        _draft = State(initialValue: LayoutDraft(layout: layout, library: library))
    }

    var body: some View {
        NavigationStack {
            List {
                previewSection
                panelSection
                rowsSection
                resetSection
            }
            .accessibilityIdentifier("key-editor")
            .navigationTitle("Edit Keys")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: EditedRowIndex.self) { destination in
                KeyRowEditorView(draft: draft, rowIndex: destination.index)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if draft.hasChanges {
                            showingDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("key-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if draft.save() { dismiss() }
                    }
                    .disabled(!draft.hasChanges)
                    .accessibilityIdentifier("key-editor-save")
                }
            }
            .confirmationDialog(
                "Discard changes?",
                isPresented: $showingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                    .accessibilityIdentifier("key-editor-discard-confirm")
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your edits haven’t been saved.")
            }
            .alert(
                "Couldn’t Save",
                isPresented: Binding(
                    get: { draft.saveErrorMessage != nil },
                    set: { if !$0 { draft.saveErrorMessage = nil } }
                ),
                actions: { Button("OK", role: .cancel) { draft.saveErrorMessage = nil } },
                message: { Text(draft.saveErrorMessage ?? "") }
            )
        }
        .interactiveDismissDisabled(draft.hasChanges)
    }

    // MARK: Sections

    private var previewSection: some View {
        Section("Preview") {
            // Live render of the working copy; actions are dropped (panel
            // switches are handled inside KeyboardView), same as the other
            // host previews.
            KeyboardView(layout: draft.workingCopy) { _ in }
                .frame(height: metrics.totalHeight(for: draft.workingCopy.primaryArrangement))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("key-editor-preview")
                .listRowInsets(EdgeInsets())
                .background(Color(uiColor: .systemBackground))
        }
    }

    @ViewBuilder
    private var panelSection: some View {
        if draft.panels.count > 1 {
            @Bindable var draft = draft
            Section {
                Picker("Panel", selection: $draft.panelIndex) {
                    ForEach(Array(draft.panels.enumerated()), id: \.element.id) { index, panel in
                        Text(panel.name).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("key-editor-panel-picker")
            } footer: {
                Text("The rows below belong to the selected panel.")
            }
        }
    }

    private var rowsSection: some View {
        Section {
            ForEach(Array(draft.rows.enumerated()), id: \.element.id) { index, row in
                NavigationLink(value: EditedRowIndex(index: index)) {
                    rowSummary(row, number: index + 1)
                }
                .accessibilityIdentifier("key-editor-row-\(index)")
            }
            .onDelete { draft.removeRows(atOffsets: $0) }
            .onMove { draft.moveRows(fromOffsets: $0, toOffset: $1) }

            Button {
                draft.addRow()
            } label: {
                Label("Add Row", systemImage: "plus")
            }
            .accessibilityIdentifier("key-editor-add-row")
        } header: {
            HStack {
                Text("Rows")
                Spacer()
                EditButton().textCase(nil)
            }
        } footer: {
            Text("Tap a row to edit its keys. Swipe to delete a row; use Edit "
                + "to reorder.")
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        if let source = draft.builtInSource {
            Section {
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset Keys to Default", systemImage: "arrow.counterclockwise")
                }
                .accessibilityIdentifier("key-editor-reset")
            } footer: {
                Text("Replaces every panel, row, and key with “\(source.name)”’s. "
                    + "Nothing changes until you tap Save.")
            }
            .confirmationDialog(
                "Reset to “\(source.name)”?",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Keys", role: .destructive) { draft.resetToDefault() }
                    .accessibilityIdentifier("key-editor-reset-confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces the draft’s rows and keys. You can still "
                    + "Cancel the editor to keep the saved version.")
            }
        }
    }

    private func rowSummary(_ row: KeyRow, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Row \(number)")
            Text(row.keys.isEmpty
                ? "No keys yet"
                : row.keys.map(\.editorGlyph).joined(separator: "  "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

#if DEBUG
#Preview {
    let source = LayoutStore().bundledLayouts().first ?? KeyboardLayout(
        name: "Sample", locale: "en-US",
        rows: [KeyRow(keys: [.insert("ə"), .insert("i"), .insert("u")])])
    return LayoutKeyEditorView(layout: source.makeEditableCopy(), library: LayoutLibrary())
}
#endif
