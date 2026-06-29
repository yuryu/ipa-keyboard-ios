//
//  IPAKeyboardUITests.swift
//  IPAKeyboardUITests
//
//  Baseline UI tests for the IPAKeyboard host app.
//  These tests cover what actually renders today (the stock SwiftUI template)
//  and are written to grow alongside the real settings / onboarding /
//  layout-management UI.
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

    // MARK: - ContentView smoke tests

    /// Verifies the "Hello, world!" placeholder text is present and on-screen
    /// after launch.
    @MainActor
    func test_contentView_helloWorldLabelVisible() throws {
        app.launch()
        let screen = ContentScreen(app: app)
        XCTAssertTrue(
            screen.helloWorldLabel.waitForExistence(timeout: 5),
            "Expected 'Hello, world!' label (identifier: content-view-hello-world-label)"
        )
        XCTAssertTrue(
            screen.helloWorldLabel.isHittable,
            "'Hello, world!' label exists but is not hittable (possibly off-screen or occluded)"
        )
    }

    /// Verifies the globe SF Symbol image is present after launch.
    @MainActor
    func test_contentView_globeImageVisible() throws {
        app.launch()
        let screen = ContentScreen(app: app)
        XCTAssertTrue(
            screen.globeImage.waitForExistence(timeout: 5),
            "Expected globe image (identifier: content-view-globe-image)"
        )
    }

    /// Verifies both primary content elements are visible simultaneously —
    /// i.e. neither is hidden behind the other or off-screen.
    @MainActor
    func test_contentView_allPrimaryElementsVisible() throws {
        app.launch()
        let screen = ContentScreen(app: app)
        XCTAssertTrue(screen.waitForContent(timeout: 5), "ContentView primary content did not appear")
        XCTAssertTrue(screen.globeImage.exists, "Globe image missing after content loaded")
        XCTAssertTrue(screen.helloWorldLabel.exists, "'Hello, world!' label missing after content loaded")
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
