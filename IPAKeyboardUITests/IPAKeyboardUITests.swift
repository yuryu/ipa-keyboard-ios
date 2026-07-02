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
        app = XCUIApplication()
        // Launch arguments / environment can be appended here as the app grows:
        //   app.launchArguments += ["--uitesting"]
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

    // MARK: - Launch

    /// Verifies the app starts and exposes at least one window within a
    /// reasonable timeout.  This is the most fundamental smoke test — if it
    /// fails, every other test is meaningless.
    @MainActor
    func test_launch_mainWindowExists() throws {
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(
            window.waitForExistence(timeout: 10),
            "Expected the app's main window to appear within 10 s"
        )
    }

    // MARK: - Layout library

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

    /// Verifies that tapping the English (US) built-in row pushes the detail
    /// screen and renders the keyboard preview and "Duplicate to Edit" button.
    @MainActor
    func test_library_openDetail_showsPreview() throws {
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
    }

    /// Verifies that tapping the back button on the detail screen returns to
    /// the library list.  Does NOT assert that a new user layout was persisted,
    /// because saving requires the App Group container which may be unavailable
    /// on an unprovisioned simulator.
    @MainActor
    func test_library_detail_backNavigatesToList() throws {
        app.launch()
        let library = LibraryScreen(app: app)
        XCTAssertTrue(library.waitForContent(timeout: 10))

        library.englishUSRow.tap()

        let detail = LayoutDetailScreen(app: app)
        XCTAssertTrue(detail.waitForContent(timeout: 10))

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
    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
