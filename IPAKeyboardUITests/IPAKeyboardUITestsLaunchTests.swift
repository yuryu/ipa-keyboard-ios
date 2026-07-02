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

    // Use the async variant for Swift 6 @MainActor compatibility.
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
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
            app.windows.firstMatch.waitForExistence(timeout: 10),
            "Main window did not appear after launch"
        )

        // Assert the "Layouts" navigation bar is present so we know the
        // SwiftUI layout-library hierarchy rendered.
        let screen = LibraryScreen(app: app)
        XCTAssertTrue(
            screen.waitForContent(timeout: 10),
            "Expected 'Layouts' navigation bar (LayoutListView) after launch"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
