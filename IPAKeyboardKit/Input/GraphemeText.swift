//
//  GraphemeText.swift
//  IPAKeyboardKit
//
//  Grapheme-cluster-aware text helpers. The keyboard inserts and deletes
//  whole user-perceived characters, so a base glyph plus a combining
//  diacritic (e.g. a vowel + length/tone mark) behaves as one unit. The
//  logic lives here as pure functions so it is unit-testable without the
//  extension runtime (`UITextDocumentProxy`).
//

import Foundation

public enum GraphemeText {
    /// How many Unicode scalars the last grapheme cluster of `context`
    /// occupies. The keyboard extension calls `deleteBackward()` this many
    /// times so one backspace removes one user-perceived character even when
    /// it is composed of several scalars (combining diacritics, emoji, etc.).
    ///
    /// Returns 0 when `context` is empty (nothing to delete).
    public static func deletionScalarCount(before context: String) -> Int {
        guard let last = context.last else { return 0 }
        return last.unicodeScalars.count
    }
}
