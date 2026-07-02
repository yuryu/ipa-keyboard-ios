//
//  KeyEditorForm.swift
//  IPAKeyboard
//
//  Bottom level of the key editor: one key's fields — inserted text, display
//  label, spoken (VoiceOver) name, width factor, and long-press alternates.
//  Edits a local copy and hands the finished key back through `onCommit`, so
//  Cancel here discards just this key's edits.
//
//  Unicode exactness: all text fields disable autocorrection and
//  autocapitalization and pass the typed/pasted string through untouched —
//  no trimming, no normalization — so ɡ (U+0261) never degrades to ASCII g,
//  ː (U+02D0) never becomes a colon, and combining marks survive. The
//  code-point readout under the symbol field makes this verifiable.
//
//  Accessibility identifier scheme (for ui-test-author):
//    key-form-text                — inserted-text field (insert keys only)
//    key-form-unicode             — code-point readout for the text field
//    key-form-label               — display-label field
//    key-form-accessibility-label — spoken-name (VoiceOver) field
//    key-form-width-stepper       — width stepper (0.25–5.0, step 0.25)
//    key-form-alternate-text-<i>  — alternate i's symbol field (0-based)
//    key-form-alternate-a11y-<i>  — alternate i's spoken-name field
//    key-form-add-alternate       — appends an alternate
//    key-form-done                — commit ("Add" for a new key)
//    key-form-cancel              — discard
//

import SwiftUI
import IPAKeyboardKit

struct KeyEditorForm: View {
    let isNew: Bool
    let onCommit: (Key) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var key: Key

    init(key: Key, isNew: Bool, onCommit: @escaping (Key) -> Void) {
        self.isNew = isNew
        self.onCommit = onCommit
        _key = State(initialValue: key)
    }

    var body: some View {
        NavigationStack {
            Form {
                actionSection
                if !key.isSpacer {
                    appearanceSection
                }
                widthSection
                if !key.isSpacer {
                    alternatesSection
                }
            }
            .navigationTitle(isNew ? "New Key" : "Edit Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("key-form-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Done") {
                        onCommit(committedKey)
                        dismiss()
                    }
                    .disabled(!canCommit)
                    .accessibilityIdentifier("key-form-done")
                }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var actionSection: some View {
        if key.action.insertText != nil {
            Section {
                TextField("Symbol", text: insertText)
                    .font(.title2)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("key-form-text")
            } header: {
                Text("Inserted Text")
            } footer: {
                if let text = key.action.insertText, !text.isEmpty {
                    Text("Code points: \(codePoints(of: text))")
                        .accessibilityIdentifier("key-form-unicode")
                } else {
                    Text("The exact text this key types — a symbol, a digraph "
                        + "like “tʃ”, or a base plus combining mark.")
                }
            }
        } else {
            // Function keys (space, backspace, globe, panel switch, spacer):
            // the action itself isn't editable here, only its presentation.
            Section {
                LabeledContent("Action", value: key.action.editorName)
            }
        }
    }

    private var appearanceSection: some View {
        Section {
            TextField("Display label", text: displayLabel)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("key-form-label")
            TextField("Spoken name (VoiceOver)", text: spokenName)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("key-form-accessibility-label")
        } header: {
            Text("Appearance & VoiceOver")
        } footer: {
            Text("The display label falls back to the inserted text. The "
                + "spoken name is what VoiceOver says — “schwa”, not “ə”.")
        }
    }

    private var widthSection: some View {
        Section("Width") {
            Stepper(value: $key.widthFactor, in: 0.25...5.0, step: 0.25) {
                Text("\(key.widthFactor.formatted()) × standard key")
            }
            .accessibilityIdentifier("key-form-width-stepper")
        }
    }

    private var alternatesSection: some View {
        Section {
            ForEach(Array(key.alternates.enumerated()), id: \.element.id) { index, alternate in
                alternateRow(alternate, index: index)
            }
            .onDelete { key.alternates.remove(atOffsets: $0) }
            .onMove { key.alternates.move(fromOffsets: $0, toOffset: $1) }

            Button {
                key.alternates.append(Key(action: .insert("")))
            } label: {
                Label("Add Alternate", systemImage: "plus")
            }
            .accessibilityIdentifier("key-form-add-alternate")
        } header: {
            HStack {
                Text("Long-press Alternates")
                Spacer()
                if key.alternates.count > 1 {
                    EditButton().textCase(nil)
                }
            }
        } footer: {
            Text("Symbols offered when the key is held down (pʰ from p). "
                + "Alternates left empty are removed when you finish.")
        }
    }

    @ViewBuilder
    private func alternateRow(_ alternate: Key, index: Int) -> some View {
        if alternate.action.insertText != nil {
            HStack(spacing: 12) {
                TextField("Symbol", text: alternateText(id: alternate.id))
                    .font(.title3)
                    .frame(width: 72)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("key-form-alternate-text-\(index)")
                Divider()
                TextField("Spoken name", text: alternateSpokenName(id: alternate.id))
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("key-form-alternate-a11y-\(index)")
            }
        } else {
            // Hand-edited JSON can hold non-insert alternates; show them
            // rather than losing them, but don't offer text editing.
            LabeledContent("Alternate", value: alternate.action.editorName)
        }
    }

    // MARK: Bindings

    private var insertText: Binding<String> {
        Binding(
            get: { key.action.insertText ?? "" },
            set: { key.action = .insert($0) } // field only shown for insert keys
        )
    }

    private var displayLabel: Binding<String> {
        Binding(
            get: { key.label ?? "" },
            set: { key.label = $0.isEmpty ? nil : $0 }
        )
    }

    private var spokenName: Binding<String> {
        Binding(
            get: { key.accessibilityLabel ?? "" },
            set: { key.accessibilityLabel = $0.isEmpty ? nil : $0 }
        )
    }

    /// Bindings for an alternate's fields, keyed by the alternate's id (not
    /// its offset) so they stay correct across reorder/delete.
    private func alternateText(id: UUID) -> Binding<String> {
        Binding(
            get: { key.alternates.first { $0.id == id }?.action.insertText ?? "" },
            set: { newValue in
                guard let index = key.alternates.firstIndex(where: { $0.id == id }) else { return }
                key.alternates[index].action = .insert(newValue)
            }
        )
    }

    private func alternateSpokenName(id: UUID) -> Binding<String> {
        Binding(
            get: { key.alternates.first { $0.id == id }?.accessibilityLabel ?? "" },
            set: { newValue in
                guard let index = key.alternates.firstIndex(where: { $0.id == id }) else { return }
                key.alternates[index].accessibilityLabel = newValue.isEmpty ? nil : newValue
            }
        )
    }

    // MARK: Commit

    /// The key as edited, with alternates whose inserted text is exactly
    /// empty dropped (they'd be blank popup keys). Nothing is trimmed —
    /// whitespace and combining marks are meaningful and pass through intact.
    private var committedKey: Key {
        var result = key
        result.alternates = result.alternates.filter { alternate in
            guard let text = alternate.action.insertText else { return true }
            return !text.isEmpty
        }
        return result
    }

    /// An insert key with no text would render blank and type nothing.
    private var canCommit: Bool {
        guard let text = key.action.insertText else { return true }
        return !text.isEmpty
    }

    private func codePoints(of text: String) -> String {
        text.unicodeScalars
            .map { String(format: "U+%04X", $0.value) }
            .joined(separator: " ")
    }
}

#if DEBUG
#Preview {
    KeyEditorForm(
        key: .insert("ə", accessibilityLabel: "schwa", alternates: [.insert("ɚ"), .insert("ɝ")]),
        isNew: false
    ) { _ in }
}
#endif
