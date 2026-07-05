//
//  ScratchInputTests.swift
//  IPAKeyboardTests
//
//  ScratchInput (issue #115) is the shared reducer both host scratchpads
//  (layout editor, layout list) run preview key presses through. It must
//  mirror the extension's document edits: inserts append exact code points,
//  and backspace removes one grapheme cluster, so combining diacritics
//  delete as a single user-perceived character.
//

import Testing
import IPAKeyboardKit
@testable import IPAKeyboard

@MainActor
struct ScratchInputTests {

    @Test func insertAppendsExactText() {
        var scratch = ""
        // ɡ U+0261 and ː U+02D0 — precise IPA code points, not their ASCII
        // look-alikes; the reducer must never normalize them.
        ScratchInput.apply(.insert("\u{0261}"), to: &scratch)
        ScratchInput.apply(.insert("\u{02D0}"), to: &scratch)
        #expect(scratch == "\u{0261}\u{02D0}")
    }

    @Test func spaceAndReturnAppendWhitespace() {
        var scratch = "ə"
        ScratchInput.apply(.space, to: &scratch)
        ScratchInput.apply(.return, to: &scratch)
        #expect(scratch == "ə \n")
    }

    @Test func backspaceRemovesOneGraphemeCluster() {
        // "e" + combining tilde U+0303 is one user-perceived character;
        // backspace must remove the whole cluster, not just the mark.
        var scratch = "ə" + "e\u{0303}"
        ScratchInput.apply(.backspace, to: &scratch)
        #expect(scratch == "ə")
    }

    @Test func backspaceOnEmptyIsNoOp() {
        var scratch = ""
        ScratchInput.apply(.backspace, to: &scratch)
        #expect(scratch.isEmpty)
    }

    @Test func nonTypingActionsAreIgnored() {
        var scratch = "ə"
        ScratchInput.apply(.nextKeyboard, to: &scratch)
        ScratchInput.apply(.switchPanel("More"), to: &scratch)
        ScratchInput.apply(.spacer, to: &scratch)
        #expect(scratch == "ə")
    }
}
