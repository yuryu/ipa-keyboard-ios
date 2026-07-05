//
//  AlternatesPopupUITests.swift
//  IPAKeyboardUITests
//
//  Regression tests for the long-press alternates popup.
//
//  Issue #104: after long-pressing a key with alternates, the popup must
//  close when the finger is released — it used to stay stranded on screen
//  because a completed SwiftUI long-press ends press tracking, so the
//  physical finger-up delivered no callback at all.
//
//  Issue #122: a *top-row* key's popup must open above the pressed key
//  like every other row — it used to flip downward, rendering behind the
//  next row's keys and out of reach of the release.
//
//  Exercised on layout previews (the same shared `KeyboardView` the
//  extension renders): the en-US `ɹ` key (alternate `r`) for the mid-row
//  cases, and the ja-JP top-row `p` key (single alternate `pʲ`) for the
//  top-row case.
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
        XCTAssertTrue(library.waitForContent(timeout: .postNavigation))

        XCTAssertTrue(
            library.openEnglishUS(timeout: .postNavigation),
            "English (US) built-in row not found or not hittable")

        let detail = LayoutDetailScreen(app: app)
        let rhotic = detail.previewKey(inserting: "ɹ")
        XCTAssertTrue(
            rhotic.waitForExistence(timeout: .postNavigation),
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
        // must not remain in the tree after release. The popup legitimately
        // existed mid-gesture and is dismissing now — assert the eventual
        // state (nonexistence), not a fixed-window snapshot that races the
        // dismissal animation.
        let alternateCell = detail.previewKey(inserting: "r")
        XCTAssertTrue(
            alternateCell.waitForNonExistence(timeout: .postNavigation),
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
    /// run. The offset is derived from the popup's placed geometry
    /// (`AlternatesPopupPlacement`: bottom edge 4 pt above the cap,
    /// 40-pt-tall cells inside 6 pt of padding — cells span 10–50 pt above
    /// the cap for an unclamped mid-row key), well within the hit-testing
    /// slop; tests run in portrait, where key caps are the default 50 pt.
    @MainActor
    func test_editorPreview_longPressSlideToPopup_commitsAlternateOnce() throws {
        app.launch()
        let library = LibraryScreen(app: app)
        XCTAssertTrue(library.waitForContent(timeout: .postNavigation))

        XCTAssertTrue(
            library.openEnglishUS(timeout: .postNavigation),
            "English (US) built-in row not found or not hittable")

        let detail = LayoutDetailScreen(app: app)
        XCTAssertTrue(
            detail.waitForContent(timeout: .postNavigation),
            "Detail action section did not appear"
        )
        let customize = app.descendants(matching: .any)["layout-detail-customize-link"].firstMatch
        XCTAssertTrue(customize.waitForExistence(timeout: 5), "Customize symbols link missing")
        customize.tap()

        let editorPreview = app.otherElements["layout-editor-preview"]
        XCTAssertTrue(editorPreview.waitForExistence(timeout: .postNavigation), "Editor preview missing")
        let rhotic = editorPreview.descendants(matching: .any)["key-insert-ɹ"].firstMatch
        XCTAssertTrue(rhotic.waitForExistence(timeout: 10), "ɹ key missing from editor preview")

        // The editor screen was just pushed: wait for ɹ's frame to stop
        // moving before deriving gesture coordinates from it — a start point
        // resolved from a still-settling frame puts the whole fixed-offset
        // drag in the wrong place (CI sightings 2026-07-03/-04 on two
        // unrelated branches: the slide committed nothing and the scratchpad
        // kept its placeholder).
        var previousFrame = CGRect.null
        let frameDeadline = Date().addingTimeInterval(10)
        while rhotic.frame != previousFrame, Date() < frameDeadline {
            previousFrame = rhotic.frame
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        let start = rhotic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let inPopup = start.withOffset(CGVector(dx: 0, dy: -55))
        // Hold briefly inside the popup before releasing: the release
        // commits whatever cell the last *processed* drag position selected,
        // and on a slow runner a release issued in the same frame as the
        // final move can land before SwiftUI has observed the drag entering
        // the popup at all.
        start.press(
            forDuration: 0.8, thenDragTo: inPopup,
            withVelocity: .default, thenHoldForDuration: 0.3)

        let scratch = app.staticTexts["layout-editor-scratch"]
        XCTAssertTrue(scratch.waitForExistence(timeout: 5), "Editor scratchpad missing")
        XCTAssertEqual(
            scratch.label, "r",
            "Slide-to-select should commit the alternate exactly once"
        )
    }

    /// The issue #122 regression, end to end: a top-row key's popup used to
    /// flip downward — rendered behind the next row's keys and out of reach
    /// of the release. It now opens above the key like every other row,
    /// clamped inside the keyboard's bounds (`AlternatesPopupPlacement`):
    /// the top row has no headroom, so the clamp places the popup's cells
    /// over the pressed cap itself. A stationary hold-and-release therefore
    /// commits the cell under the finger — deterministic on the ja-JP
    /// top-row `p`, whose popup has exactly one cell (`pʲ`). Under the old
    /// downward placement the same release classified as on-cap and typed
    /// the base `p`, so the scratchpad assertion fails without the fix.
    @MainActor
    func test_editorPreview_topRowHoldAndRelease_commitsClampedAlternate() throws {
        // Hermetic hidden-symbol state: a stale per-layout curation from an
        // earlier non-hermetic run could filter the key out of the preview.
        app.launchArguments += [LibraryScreen.resetLayoutsArgument]
        app.launch()
        let library = LibraryScreen(app: app)
        XCTAssertTrue(library.waitForContent(timeout: .postNavigation))

        let detail = LayoutDetailScreen(app: app)
        XCTAssertTrue(
            library.openRow(labelContains: "Japanese", pushSentinel: detail.preview),
            "Japanese (Japan) built-in row not found or not hittable")
        XCTAssertTrue(
            detail.preview.waitForExistence(timeout: .postNavigation),
            "Detail preview did not appear")

        // The customize link sits below the tall preview in the lazy detail
        // List and doesn't exist in the accessibility tree until scrolled
        // into the loaded range — reveal it rather than just waiting.
        let customize = app.descendants(matching: .any)["layout-detail-customize-link"].firstMatch
        XCTAssertTrue(
            detail.scrollTo(customize, timeout: .postNavigation),
            "Customize symbols link missing")
        customize.tap()

        let editorPreview = app.otherElements["layout-editor-preview"]
        XCTAssertTrue(editorPreview.waitForExistence(timeout: .postNavigation), "Editor preview missing")
        let plosive = editorPreview.descendants(matching: .any)["key-insert-p"].firstMatch
        XCTAssertTrue(plosive.waitForExistence(timeout: 10), "p key missing from editor preview")

        // Wait for the just-pushed screen's layout to settle before pressing
        // — the same guard as the slide-to-select test above.
        var previousFrame = CGRect.null
        let frameDeadline = Date().addingTimeInterval(10)
        while plosive.frame != previousFrame, Date() < frameDeadline {
            previousFrame = plosive.frame
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        // Hold past the 0.3 s threshold and release in place. No slide is
        // needed (or wanted): the clamped popup is already under the finger,
        // and a stationary press cannot end in a tap because the tap
        // recognizer requires the already-begun long-press to fail.
        plosive.press(forDuration: 0.8)

        let scratch = app.staticTexts["layout-editor-scratch"]
        XCTAssertTrue(scratch.waitForExistence(timeout: 5), "Editor scratchpad missing")
        XCTAssertEqual(
            scratch.label, "pʲ",
            "Top-row hold-and-release should commit the popup cell clamped "
                + "over the cap, not the base key (issue #122)"
        )
    }
}
