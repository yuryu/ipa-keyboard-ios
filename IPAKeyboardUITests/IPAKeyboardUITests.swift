//
//  IPAKeyboardUITests.swift
//  IPAKeyboardUITests
//
//  Functional UI tests for the IPAKeyboard host app.
//  Covers the layout-library root screen (LayoutListView) and the
//  layout-detail screen (LayoutDetailView).
//
//  Conventions
//  -----------
//  - Test names: test_<flow>_<expectation>
//  - Elements located by accessibilityIdentifier first, label second,
//    type-query last — never by index or coordinate.
//  - Synchronisation via waitForExistence / XCTNSPredicateExpectation, not sleep.
//  - The first wait after a navigation event (launch, push, sheet/alert,
//    dismissal) passes timeout: .postNavigation — slow CI runners can stretch
//    the transition past the 10s suite default (issue #96).
//  - continueAfterFailure = false so failures are reported at their root cause.
//  - Failure screenshots are attached automatically in tearDown.
//

import XCTest

final class IPAKeyboardUITests: XCTestCase {

    // @MainActor isolates the stored property so setUp/tearDown and test
    // methods (all @MainActor) can mutate it without concurrency warnings.
    @MainActor private var app: XCUIApplication!

    // Use the async variants so @MainActor isolation is permitted on the
    // override (Swift 6: synchronous overrides of nonisolated XCTestCase
    // methods cannot add actor isolation).

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        // Portrait, always: in landscape the active-layout preview card fills
        // the viewport and the built-in layout row falls below the fold —
        // SwiftUI's lazy list keeps off-screen cells out of the accessibility
        // tree entirely, so row queries fail. IPAKeyboardUITestsLaunchTests
        // (per-UI-configuration) leaves even CI simulators in landscape, and
        // a developer's simulator may be left there too — every functional
        // suite resets orientation in setUp.
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // None of these tests exercise onboarding (see OnboardingUITests.swift),
        // and on a fresh/first-run simulator the onboarding sheet would
        // auto-present and occlude the layout list these tests assert on.
        // Force-skip so this suite is hermetic and order-independent
        // regardless of prior runs' first-run state.
        app.launchArguments += [OnboardingScreen.forceSkipArgument]
    }

    @MainActor
    override func tearDown() async throws {
        // Attach a screenshot after every test run.  XCTest discards it on
        // success because the lifetime is .deleteOnSuccess.
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

    // MARK: - Layout library

    // A bare launch/window smoke test used to live here; it was subsumed by
    // IPAKeyboardUITestsLaunchTests.testLaunch (window + nav-bar assertions,
    // per UI configuration) and by every test below waiting on library
    // content. A built-in-row smoke test followed it out (issue #187): its
    // identifier-based existence + hittability assertions were already
    // re-exercised by openEnglishUS's hardened poll in the detail test
    // below, which now also carries its one unique assertion (the
    // human-readable name cross-check) — retiring the one-shot isHittable
    // snapshot flake (issue #166) with it. Each XCUITest costs a full cold
    // app launch in CI, so tests whose assertions are a subset of another's
    // are deleted, not kept.

    /// Verifies the round trip through the detail screen in one launch:
    /// the library shows the English (US) built-in row (human-readable
    /// cross-check; the identifier-based existence + hittability checks are
    /// `openEnglishUS`'s poll), tapping the row pushes the detail screen with
    /// the keyboard preview and "Duplicate to Edit" button, and the back
    /// button returns to the library list.  (Previously two tests whose
    /// launch → tap-row → wait-for-detail prefix was identical.)
    /// Does NOT assert that a new user layout was persisted, because saving
    /// requires the App Group container which may be unavailable on an
    /// unprovisioned simulator.
    @MainActor
    func test_library_openDetail_showsPreview_andBackNavigatesToList() throws {
        app.launch()
        let library = LibraryScreen(app: app)
        XCTAssertTrue(library.waitForContent(timeout: .postNavigation))

        // Cross-check: the human-readable name is also present on screen.
        // waitForExistence, not a bare `.exists` — the nav bar (waitForContent)
        // can precede the lazy list's row composition (issue #166's lesson).
        XCTAssertTrue(
            library.row(named: "English (US) — General American")
                .waitForExistence(timeout: 5),
            "Expected visible text 'English (US) — General American' in the list"
        )

        XCTAssertTrue(
            library.openEnglishUS(timeout: .postNavigation),
            "English (US) built-in row not found or not hittable")

        let detail = LayoutDetailScreen(app: app)
        // Preview assertions first: the preview section sits at the top of
        // the lazy List, and scrolling down to the action section can compose
        // it back out of the accessibility tree.
        XCTAssertTrue(
            detail.preview.waitForExistence(timeout: .postNavigation),
            "Keyboard preview (layout-detail-preview) did not appear on detail screen"
        )
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "layout-detail-preview").count, 1,
            "Expected exactly one 'layout-detail-preview' element — the "
                + "accessibility container; more means the identifier is "
                + "bleeding onto the keys again (issue #25)"
        )
        // One representative per-key identifier: the schwa key on the en-US
        // main panel, by inserted text — with its spoken name, not the raw
        // glyph, as the label.
        let schwaKey = detail.previewKey(inserting: "ə")
        XCTAssertTrue(
            schwaKey.waitForExistence(timeout: 10),
            "Preview does not expose the schwa key via its per-key identifier 'key-insert-ə'"
        )
        XCTAssertEqual(
            schwaKey.label, "schwa",
            "Schwa key's accessibility label should be its spoken name"
        )
        XCTAssertTrue(
            detail.waitForContent(timeout: 10),
            "'Duplicate to Edit' button missing on detail screen (after scrolling)"
        )

        detail.backButton.tap()

        XCTAssertTrue(
            library.waitForContent(timeout: .postNavigation),
            "Did not navigate back to the layout library"
        )
        XCTAssertTrue(
            library.layoutList.exists,
            "Layout list not visible after back navigation"
        )
    }

    // MARK: - Launch performance

    /// Measures cold-launch time.  Uses a local XCUIApplication instance so
    /// the measure loop is independent of the setUp-managed `app`.
    ///
    /// Local-only: the measure block performs five full app launches
    /// (minutes of wall-clock in CI) and no baseline is recorded, so on a
    /// shared runner it can never fail — it only produces noise.  CI sets
    /// TEST_RUNNER_CI=1 on the xcodebuild invocation (xcodebuild strips the
    /// TEST_RUNNER_ prefix and forwards CI=1 to the test-runner process).
    @MainActor
    func testLaunchPerformance() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["CI"] != nil,
            "Launch-performance measurement is local-only; see comment above"
        )
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let perfApp = XCUIApplication()
            // Keep the measured launch free of the first-run onboarding
            // sheet's extra view-hierarchy work, matching the rest of this
            // suite (see setUp).
            perfApp.launchArguments += [OnboardingScreen.forceSkipArgument]
            perfApp.launch()
        }
    }
}
