//
//  KeyRowEditorView.swift
//  IPAKeyboard
//
//  Second level of the key editor: the keys of one row of the draft's shown
//  panel. Keys can be reordered, deleted, edited (tap → `KeyEditorForm`
//  sheet), and appended. All mutations go through the shared `LayoutDraft`,
//  so they stay cancelable from the editor root.
//
//  Accessibility identifier scheme (for ui-test-author):
//    row-editor               — the List
//    row-editor-key-<index>   — tap to edit that key (0-based)
//    row-editor-add-key       — opens the form for a new key
//

import SwiftUI
import IPAKeyboardKit

/// What the key form is editing: an existing key (`keyIndex` set) or a new
/// key to append (`keyIndex` nil).
private struct KeyFormContext: Identifiable {
    let id = UUID()
    let keyIndex: Int?
    let key: Key
}

struct KeyRowEditorView: View {
    let draft: LayoutDraft
    let rowIndex: Int

    @State private var formContext: KeyFormContext? = nil

    var body: some View {
        List {
            Section {
                ForEach(Array(keys.enumerated()), id: \.element.id) { index, key in
                    Button {
                        formContext = KeyFormContext(keyIndex: index, key: key)
                    } label: {
                        KeySummaryRow(key: key)
                    }
                    .accessibilityIdentifier("row-editor-key-\(index)")
                }
                .onDelete { draft.removeKeys(atOffsets: $0, inRowAt: rowIndex) }
                .onMove { draft.moveKeys(fromOffsets: $0, toOffset: $1, inRowAt: rowIndex) }

                Button {
                    formContext = KeyFormContext(keyIndex: nil, key: Key(action: .insert("")))
                } label: {
                    Label("Add Key", systemImage: "plus")
                }
                .accessibilityIdentifier("row-editor-add-key")
            } header: {
                HStack {
                    Text("Keys")
                    Spacer()
                    EditButton().textCase(nil)
                }
            } footer: {
                Text("Tap a key to edit it. Swipe to delete; use Edit to reorder.")
            }
        }
        .accessibilityIdentifier("row-editor")
        .navigationTitle("Row \(rowIndex + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $formContext) { context in
            KeyEditorForm(key: context.key, isNew: context.keyIndex == nil) { edited in
                if let keyIndex = context.keyIndex {
                    draft.replaceKey(at: keyIndex, inRowAt: rowIndex, with: edited)
                } else {
                    draft.appendKey(edited, toRowAt: rowIndex)
                }
            }
        }
    }

    private var keys: [Key] { draft.keys(inRowAt: rowIndex) }
}

/// One key in the list: glyph, action + width, spoken name, alternate count.
private struct KeySummaryRow: View {
    let key: Key

    var body: some View {
        HStack(spacing: 12) {
            Text(key.editorGlyph)
                .font(.title3)
                .foregroundStyle(Color.primary)
                .frame(minWidth: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(actionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(key.accessibilityLabel ?? "No spoken name")
                    .font(.caption)
                    .foregroundStyle(key.accessibilityLabel == nil ? .tertiary : .secondary)
            }
            Spacer()
            if !key.alternates.isEmpty {
                Label("\(key.alternates.count)", systemImage: "square.on.square")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(key.alternates.count) long-press alternates")
            }
        }
    }

    private var actionSummary: String {
        let width = key.widthFactor == 1.0 ? "" : " · \(key.widthFactor.formatted())× wide"
        return key.action.editorName + width
    }
}

#if DEBUG
#Preview {
    let source = LayoutStore().bundledLayouts().first ?? KeyboardLayout(
        name: "Sample", locale: "en-US",
        rows: [KeyRow(keys: [.insert("ə"), .insert("i"), .insert("u")])])
    let library = LayoutLibrary()
    return NavigationStack {
        KeyRowEditorView(
            draft: LayoutDraft(layout: source.makeEditableCopy(), library: library),
            rowIndex: 0)
    }
}
#endif
