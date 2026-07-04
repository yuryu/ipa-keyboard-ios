//
//  IPAKeyboardUITestsLaunchTests.swift
//  IPAKeyboardUITests
//
//  Launch tests that run for every UI configuration (light/dark, dynamic-type
//  sizes, etc.) because runsForEachTargetApplicationUIConfiguration = true.
//  These complement the functional tests in IPAKeyboardUITests.swift: they
//  capture a screenshot for each configuration but also assert something
//  meaningful so a blank/crashed launch is caught in CI.
//

import XCTest

final class IPAKeyboardUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    // An instance property (matching every other suite), not a test-local:
    // tearDown can only clean up what it can reach, and with
    // continueAfterFailure = false a failed run stops at its first assert —
    // a test-local app would escape the cleanup below on exactly the runs
    // that need it most. @MainActor isolates the stored property so
    // setUp/tearDown and the test (all @MainActor) can mutate it.
    @MainActor private var app: XCUIApplication!

    // Use the async variants for Swift 6 @MainActor compatibility.
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    @MainActor
    override func tearDown() async throws {
        // Cause-removal for every functional suite's portrait reset: these
        // per-configuration runs are the only thing that leaves the
        // simulator in landscape, so restore portrait here and the other
        // suites' setUp one-liners become no-ops with nothing to race.
        XCUIDevice.shared.orientation = .portrait
        // Leave a confirmed-dead process behind: each of the 4
        // per-configuration runs — and the first test of whatever suite
        // follows — would otherwise race launch()'s implicit termination of
        // this one (issue #62's exact failure line). Event-driven bounded
        // wait; no asserts in tearDown. Guarded for a failed setUp, where
        // app is still nil.
        if let app {
            app.terminate()
            _ = app.wait(for: .notRunning, timeout: 10)
        }
        app = nil
        try await super.tearDown()
    }

    @MainActor
    func testLaunch() throws {
        // This test asserts on the 'Layouts' navigation bar, which the
        // first-run onboarding sheet would occlude on a fresh simulator.
        // Force-skip so the assertion is hermetic regardless of prior runs'
        // first-run state (see OnboardingUITests.swift for onboarding
        // coverage).
        app.launchArguments += [OnboardingScreen.forceSkipArgument]
        app.launch()

        // Assert the main window is present — catches silent crashes and black
        // screens that would otherwise only show up as a blank screenshot.
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: .postNavigation),
            "Main window did not appear after launch"
        )

        // Assert the "Layouts" navigation bar is present so we know the
        // SwiftUI layout-library hierarchy rendered.
        let screen = LibraryScreen(app: app)
        XCTAssertTrue(
            screen.waitForContent(timeout: .postNavigation),
            "Expected 'Layouts' navigation bar (LayoutListView) after launch"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
