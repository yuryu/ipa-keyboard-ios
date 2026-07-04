//
//  AlternatesPopupUITests.swift
//  IPAKeyboardUITests
//
//  Regression test for issue #104: after long-pressing a key with
//  alternates, the popup must close when the finger is released — it used
//  to stay stranded on screen because a completed SwiftUI long-press ends
//  press tracking, so the physical finger-up delivered no callback at all.
//
//  Exercised on the layout-detail preview (the same shared `KeyboardView`
//  the extension renders), on the en-US `ɹ` key whose long-press popup
//  offers the `r` alternate.
//

import XCTest

final class AlternatesPopupUITests: XCTestCase {

    @MainActor private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        // Portrait, always — see the note in IPAKeyboardUITests.setUp: in
        // landscape the built-in layout row falls out of the lazy List's
        // accessibility tree.
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // Onboarding is exercised elsewhere; force-skip so a fresh simulator
        // doesn't auto-present the sheet over the layout list.
        app.launchArguments += [OnboardingScreen.forceSkipArgument]
    }

    @MainActor
    override func tearDown() async throws {
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

    /// Long-press a key with alternates past the 0.3 s popup threshold,
    /// slide off it, and release — the repro from issue #104. The slide
    /// matters: a perfectly stationary synthesized press still ended in a
    /// successful tap (SwiftUI taps fail on movement, not duration), which
    /// happened to dismiss the popup even before the fix; real fingers
    /// micro-move, fail the tap, and stranded it. Dragging to a same-row
    /// neighbor reproduces that reliably. The popup must be gone once the
    /// finger lifts (the release lands off both popup and key cap, so it
    /// also types nothing — but the detail preview discards actions, so the
    /// assertion is popup dismissal).
    @MainActor
    func test_detailPreview_longPressSlideOffAndRelease_closesAlternatesPopup() throws {
        app.launch()
        let library = LibraryScreen(app: app)
        XCTAssertTrue(library.waitForContent(timeout: 10))

        library.englishUSRow.tap()

        let detail = LayoutDetailScreen(app: app)
        let rhotic = detail.previewKey(inserting: "ɹ")
        XCTAssertTrue(
            rhotic.waitForExistence(timeout: 10),
            "Preview does not expose the 'ɹ' key via 'key-insert-ɹ'"
        )
        // ɹ's same-row left-hand neighbor on the en-US main panel — same
        // row so the drag is horizontal and cannot scroll the List.
        let neighbor = detail.previewKey(inserting: "l")
        XCTAssertTrue(
            neighbor.waitForExistence(timeout: 10),
            "Preview does not expose the 'l' key via 'key-insert-l'"
        )

        rhotic.press(forDuration: 0.8, thenDragTo: neighbor)

        // The popup's alternate cell (`key-insert-r`, the alveolar trill)
        // must not remain in the tree after release. Inverted wait: give a
        // stranded popup a moment to prove it is stuck before failing.
        let alternateCell = detail.previewKey(inserting: "r")
        XCTAssertFalse(
            alternateCell.waitForExistence(timeout: 2),
            "Alternates popup stayed on screen after the key was released (issue #104)"
        )
        // Belt and braces: a stranded popup can also surface as a *second*
        // element carrying the base key's identifier (accessibility
        // modifiers applied over the popup overlay used to stamp the cells
        // with the key's own identifier), so also pin the element count.
        XCTAssertEqual(
            detail.preview.descendants(matching: .any)
                .matching(identifier: "key-insert-ɹ").count,
            1,
            "Expected exactly one 'key-insert-ɹ' element after release — "
                + "more means the alternates popup is still on screen (issue #104)"
        )
    }

    /// The positive half of the interaction: hold `ɹ`, slide up into the
    /// popup, release — the alternate (`r`) must be committed, exactly once,
    /// and observable in the symbol editor's scratchpad (the only preview
    /// surface that records emitted actions). The drag destination is a
    /// coordinate offset from the located key — an exception to the
    /// "identifiers, never coordinates" convention that is unavoidable here:
    /// the popup cell only exists mid-gesture, when no element query can
    /// run. The offset is derived from the popup's fixed geometry (floats 56
    /// pt above the cap, 40-pt-tall cells), well within the hit-testing
    /// slop; tests run in portrait, where key caps are the default 50 pt.
    @MainActor
    func test_editorPreview_longPressSlideToPopup_commitsAlternateOnce() throws {
        app.launch()
        let library = LibraryScreen(app: app)
        XCTAssertTrue(library.waitForContent(timeout: 10))

        library.englishUSRow.tap()

        let detail = LayoutDetailScreen(app: app)
        XCTAssertTrue(
            detail.waitForContent(timeout: 10),
            "Detail action section did not appear"
        )
        let customize = app.descendants(matching: .any)["layout-detail-customize-link"].firstMatch
        XCTAssertTrue(customize.waitForExistence(timeout: 5), "Customize symbols link missing")
        customize.tap()

        let editorPreview = app.otherElements["layout-editor-preview"]
        XCTAssertTrue(editorPreview.waitForExistence(timeout: 10), "Editor preview missing")
        let rhotic = editorPreview.descendants(matching: .any)["key-insert-ɹ"].firstMatch
        XCTAssertTrue(rhotic.waitForExistence(timeout: 10), "ɹ key missing from editor preview")

        let start = rhotic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let inPopup = start.withOffset(CGVector(dx: 0, dy: -55))
        start.press(forDuration: 0.8, thenDragTo: inPopup)

        let scratch = app.staticTexts["layout-editor-scratch"]
        XCTAssertTrue(scratch.waitForExistence(timeout: 5), "Editor scratchpad missing")
        XCTAssertEqual(
            scratch.label, "r",
            "Slide-to-select should commit the alternate exactly once"
        )
    }
}
