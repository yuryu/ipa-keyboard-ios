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
        // tree entirely, so row queries fail. CI simulators boot in portrait;
        // a developer's simulator may be left in landscape.
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
    // content. Each XCUITest costs a full cold app launch in CI, so tests
    // whose assertions are a subset of another's are deleted, not kept.

    /// Verifies the layout-library root screen shows the English (US) built-in
    /// row after launch.  Uses the stable accessibility identifier backed by the
    /// pinned UUID in `en-US.json` so this assertion is name-change-resilient.
    @MainActor
    func test_library_showsBuiltInLayout() throws {
        app.launch()
        let screen = LibraryScreen(app: app)
        XCTAssertTrue(
            screen.waitForContent(timeout: 10),
            "Layout library 'Layouts' navigation bar did not appear"
        )
        let row = screen.englishUSRow
        XCTAssertTrue(
            row.waitForExistence(timeout: 5),
            "Built-in English (US) row not found — expected identifier "
                + "'layout-row-\(LibraryScreen.englishUSLayoutID)'"
        )
        XCTAssertTrue(
            row.isHittable,
            "Built-in English (US) row exists but is not hittable "
                + "(possibly off-screen or occluded)"
        )
        // Cross-check: the human-readable name is also present on screen.
        XCTAssertTrue(
            screen.row(named: "English (US) — General American").exists,
            "Expected visible text 'English (US) — General American' in the list"
        )
    }

    /// Verifies the round trip through the detail screen in one launch:
    /// tapping the English (US) built-in row pushes the detail screen with
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
        XCTAssertTrue(library.waitForContent(timeout: 10))

        library.englishUSRow.tap()

        let detail = LayoutDetailScreen(app: app)
        XCTAssertTrue(
            detail.waitForContent(timeout: 10),
            "Keyboard preview (layout-detail-preview) did not appear on detail screen"
        )
        XCTAssertTrue(
            detail.scrollTo(detail.duplicateButton),
            "'Duplicate to Edit' button missing on detail screen (after scrolling)"
        )

        detail.backButton.tap()

        XCTAssertTrue(
            library.waitForContent(timeout: 10),
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
