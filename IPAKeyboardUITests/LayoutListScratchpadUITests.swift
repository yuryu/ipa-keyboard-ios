//
//  LayoutListScratchpadUITests.swift
//  IPAKeyboardUITests
//
//  UI coverage for the layout-list scratchpad (issues #103/#115): keys
//  tapped on the Active section's `KeyboardView` preview type into the
//  scratchpad text field, and the clear button empties it. Also pins
//  space-bar tap-to-insert (issue #139 item 1) after the issue #70 / PR #133
//  migration moved the space key onto `KeyPressTracker`: a *short* tap must
//  still emit `.space` (only a >0.3 s hold enters trackpad-style cursor
//  mode, which types nothing), so a tap appends a literal U+0020.
//
//  Typing goes through the preview keys, not the system keyboard:
//  `typeText` needs the software keyboard on screen, whose presence depends
//  on the simulator's hardware-keyboard setting (a classic flake source; see
//  also issue #124), and the IPA keyboard extension itself can't be enabled
//  on an unsigned run. Preview taps are the designed in-app input path after
//  issue #115's wiring — this test covers that wiring directly.
//
//  Element types and identifiers below were verified against the runtime
//  accessibility snapshot (2026-07-04): `layout-list-scratch` survives on
//  exactly one TextField and `layout-list-scratch-clear` on one Button — the
//  in-section identifier bleed documented in LibraryScreen.swift does not
//  reach them.
//

import XCTest

final class LayoutListScratchpadUITests: XCTestCase {

    @MainActor private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        // Portrait, always — see the note in IPAKeyboardUITests.setUp: in
        // landscape the Active section's preview card fills the viewport and
        // lazy-List content falls out of the accessibility tree.
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // Onboarding is exercised elsewhere; force-skip so a fresh simulator
        // doesn't auto-present the sheet over the layout list.
        app.launchArguments += [OnboardingScreen.forceSkipArgument]
        // Hermetic active layout: a previous suite on this simulator may have
        // left another layout active (or curated symbols away) via the
        // process-local preference fallback. Resetting guarantees the
        // resolver falls back to bundled en-US, whose ə/i keys this test
        // taps.
        app.launchArguments += [LibraryScreen.resetLayoutsArgument]
    }

    @MainActor
    override func tearDown() async throws {
        // Attach a screenshot after every test run; XCTest discards it on
        // success (.deleteOnSuccess).
        if let runningApp = app {
            let screenshot = runningApp.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "tearDown – \(name)"
            attachment.lifetime = .deleteOnSuccess
            add(attachment)
        }
        app = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Waits until `element` exists *and* is hittable (both polled under one
    /// shared deadline, like `LibraryScreen.openEnglishUS` — an instantaneous
    /// hittability snapshot right after existence could catch the screen
    /// mid-composition and fail a healthy run). No scrolling: everything this
    /// test touches lives in the Active section, above the fold in portrait.
    @MainActor
    private func waitForTappable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !(element.exists && element.isHittable) {
            if Date() >= deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return true
    }

    /// Taps `element`, polls `confirmation` until it holds, and re-taps once
    /// on a miss — the single retry covers the two ways a correctly-located
    /// tap can silently do nothing (swallowed as a scroll-stop touch,
    /// invalidated by a system interruption; see `revealTapAndSettle`).
    /// Confirmation-gated so the retry can never double-apply: it is only
    /// issued after the first tap's observable effect failed to appear for
    /// the whole `timeout` — each poll takes a fresh accessibility snapshot,
    /// so a landed tap is observed well within that window. Returns whether
    /// `confirmation` finally held, so callers assert with their own message.
    @MainActor
    @discardableResult
    private func tap(
        _ element: XCUIElement,
        confirmedBy confirmation: () -> Bool,
        timeout: TimeInterval = 10
    ) -> Bool {
        func confirmed(within window: TimeInterval) -> Bool {
            let deadline = Date().addingTimeInterval(window)
            repeat {
                if confirmation() { return true }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            } while Date() < deadline
            return confirmation()
        }
        element.tap()
        if confirmed(within: timeout) { return true }
        if element.exists, element.isHittable {
            element.tap()
        }
        return confirmed(within: timeout)
    }

    /// Polls `predicate` until it holds or `timeout` elapses, taking a fresh
    /// accessibility snapshot each slice. For confirming a state assembled
    /// from several individually best-effort taps (e.g. an interior buffer
    /// run built by tapping space then a glyph), where no single retrying
    /// `tap(_:confirmedBy:)` call fits.
    @MainActor
    private func poll(_ predicate: () -> Bool, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if predicate() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return predicate()
    }

    /// The scratchpad's current text: the field's accessibility `value`.
    /// While the buffer is empty the field reports its placeholder instead,
    /// so emptiness is asserted via the clear button's nonexistence, never
    /// by comparing against placeholder copy.
    @MainActor
    private var scratchText: String {
        LibraryScreen(app: app).scratchField.value as? String ?? ""
    }

    // MARK: - Scratchpad

    /// Types "əi" into the scratchpad by tapping the Active-section preview's
    /// ə and i keys (exact code points; neither key has long-press
    /// alternates, so a plain tap can't open a popup), then clears it via the
    /// clear button and verifies the field is empty again.
    @MainActor
    func test_scratchpad_typesViaActivePreview_andClears() throws {
        app.launch()
        let library = LibraryScreen(app: app)
        XCTAssertTrue(
            library.waitForContent(timeout: .postNavigation),
            "Layout library 'Layouts' navigation bar did not appear"
        )

        // The scratchpad field is present, and its identifier names exactly
        // one element — more means the in-section identifier bleed
        // (LibraryScreen.row(labelContains:)) has spread to the Active
        // section's controls.
        XCTAssertTrue(
            library.scratchField.waitForExistence(timeout: .postNavigation),
            "Scratchpad text field (layout-list-scratch) not found on the main screen"
        )
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "layout-list-scratch").count, 1,
            "Expected exactly one 'layout-list-scratch' element — more means "
                + "an identifier is bleeding onto sibling elements again"
        )
        // Freshly launched (and layouts/preferences reset), the buffer is
        // empty, so the clear button — rendered only while there is text —
        // must not exist yet.
        XCTAssertFalse(
            library.scratchClearButton.exists,
            "Clear button rendered while the scratchpad is empty"
        )

        // Type ə then i through the preview (issue #115 wiring). The first
        // tap's confirmation doubles as the clear button's appearance check;
        // the second confirms the full buffer, keystroke order included.
        let schwa = library.activePreviewKey(inserting: "ə")
        XCTAssertTrue(
            waitForTappable(schwa, timeout: .postNavigation),
            "Active preview does not expose a tappable 'key-insert-ə' key"
        )
        XCTAssertTrue(
            tap(schwa, confirmedBy: { scratchText == "ə" && library.scratchClearButton.exists }),
            "Tapping the preview's ə key did not type 'ə' into the scratchpad"
        )

        let closeFrontI = library.activePreviewKey(inserting: "i")
        XCTAssertTrue(
            waitForTappable(closeFrontI, timeout: 10),
            "Active preview does not expose a tappable 'key-insert-i' key"
        )
        XCTAssertTrue(
            tap(closeFrontI, confirmedBy: { scratchText == "əi" }),
            "Tapping the preview's i key did not append — scratchpad should read 'əi'"
        )

        // Clear. Confirmation is the button's own disappearance (it only
        // renders while the buffer has text), so no comparison against
        // placeholder copy is needed.
        XCTAssertTrue(
            waitForTappable(library.scratchClearButton, timeout: 10),
            "Clear button (layout-list-scratch-clear) not tappable"
        )
        XCTAssertTrue(
            tap(library.scratchClearButton, confirmedBy: { !library.scratchClearButton.exists }),
            "Clear button did not empty the scratchpad"
        )
        XCTAssertFalse(
            scratchText.contains("ə"),
            "Scratchpad still shows typed text after clearing"
        )
    }

    // MARK: - Space-bar tap-to-insert (issue #139 item 1)

    /// Tapping the space key inserts a literal space into the scratchpad —
    /// pinning space-bar tap-to-insert after the issue #70 / PR #133 migration
    /// moved the space key from a SwiftUI tap gesture onto `KeyPressTracker`.
    /// The tracker routes a completed >0.3 s hold into trackpad-style cursor
    /// mode (which types nothing, so it can't stand in for a tap), and a short
    /// tap through its `onTap` path must still emit `.space` — which the
    /// active-preview wiring feeds to `ScratchInput.apply`, appending U+0020.
    ///
    /// Types i, then space, then u (all on the en-US function/primary rows,
    /// none with long-press alternates), so the inserted space sits *between*
    /// two non-space characters. The final assertion is positive and interior:
    /// the field's value must contain the exact "i u" run — a trailing space
    /// could be trimmed from a text field's reported value, but a space framed
    /// by glyphs cannot, so an observed "i u" proves the space was inserted.
    @MainActor
    func test_scratchpad_spaceKeyTap_insertsSpaceBetweenGlyphs() throws {
        app.launch()
        let library = LibraryScreen(app: app)
        XCTAssertTrue(
            library.waitForContent(timeout: .postNavigation),
            "Layout library 'Layouts' navigation bar did not appear"
        )
        XCTAssertTrue(
            library.scratchField.waitForExistence(timeout: .postNavigation),
            "Scratchpad text field (layout-list-scratch) not found on the main screen"
        )
        // Freshly launched (and layouts/preferences reset), the buffer is
        // empty, so the clear button — rendered only while there is text —
        // must not exist yet.
        XCTAssertFalse(
            library.scratchClearButton.exists,
            "Clear button rendered while the scratchpad is empty"
        )

        // First glyph: i (close front unrounded vowel) — a no-alternates key
        // on the en-US primary panel, so a plain tap types it directly. The
        // confirmation doubles as the clear button's appearance check.
        let closeFrontI = library.activePreviewKey(inserting: "i")
        XCTAssertTrue(
            waitForTappable(closeFrontI, timeout: .postNavigation),
            "Active preview does not expose a tappable 'key-insert-i' key"
        )
        XCTAssertTrue(
            tap(closeFrontI, confirmedBy: { scratchText == "i" && library.scratchClearButton.exists }),
            "Tapping the preview's i key did not type 'i' into the scratchpad"
        )

        // The migrated key (#70/PR #133): a short tap must still emit `.space`,
        // appending a literal space after the "i". The scratch buffer is
        // append-only, so that space is *transiently trailing* until the next
        // glyph lands — and a text field may report its accessibility value
        // with trailing whitespace trimmed, which is indistinguishable from the
        // space tap having been swallowed entirely (the scroll-stop-touch flake
        // this suite hardens against). So we never gate on the trailing space in
        // isolation: a bare "i" can't tell a trimmed-but-landed space from a
        // missed one, and accepting it would let a swallowed tap pass unretried.
        // Instead we tap space then u and gate on the *interior* "i u" run,
        // where the space sits between two glyphs and cannot be trimmed — an
        // unambiguous oracle that the space actually landed.
        let space = library.activePreviewSpaceKey
        XCTAssertTrue(
            waitForTappable(space, timeout: 10),
            "Active preview does not expose a tappable 'key-space' key"
        )
        // Second glyph: u (close back rounded vowel), same first row, also no
        // alternates. With a glyph on each side the space is interior and can't
        // be trimmed from the field's reported value.
        let closeBackU = library.activePreviewKey(inserting: "u")
        XCTAssertTrue(
            waitForTappable(closeBackU, timeout: 10),
            "Active preview does not expose a tappable 'key-insert-u' key"
        )

        space.tap()
        closeBackU.tap()
        if !poll({ scratchText == "i u" }) {
            // A tap was swallowed, leaving a partial buffer ("iu" if the space
            // was missed, "i " if u was). Re-tapping would only append to that
            // leftover — never yielding "i u" — so clear and rebuild the
            // i / space / u run from empty once, the same single-retry budget
            // `tap(_:confirmedBy:)` spends on the happy path.
            XCTAssertTrue(
                waitForTappable(library.scratchClearButton, timeout: 10),
                "Clear button not tappable while recovering a swallowed tap"
            )
            library.scratchClearButton.tap()
            XCTAssertTrue(
                poll({ !library.scratchClearButton.exists }),
                "Scratchpad did not clear before rebuilding the space run"
            )
            let closeFrontIAgain = library.activePreviewKey(inserting: "i")
            XCTAssertTrue(
                waitForTappable(closeFrontIAgain, timeout: 10),
                "Active preview does not re-expose a tappable 'key-insert-i' key"
            )
            closeFrontIAgain.tap()
            space.tap()
            closeBackU.tap()
            XCTAssertTrue(
                poll({ scratchText == "i u" }),
                "Rebuilt run never reached 'i u' — space-bar tap-to-insert did "
                    + "not survive the #70/PR #133 KeyPressTracker migration"
            )
        }

        // Positive assertion: the observed value contains the glyph-space-glyph
        // run — an actual U+0020 between two non-space characters — so the
        // inserted space is proven present, not merely inferred from absence.
        XCTAssertTrue(
            scratchText.contains("i u"),
            "Scratchpad should contain the space-delimited 'i u' — space-bar "
                + "tap-to-insert did not survive the #70/PR #133 KeyPressTracker migration"
        )
    }
}
