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

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Assert the main window is present — catches silent crashes and black
        // screens that would otherwise only show up as a blank screenshot.
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 10),
            "Main window did not appear after launch"
        )

        // Assert the primary placeholder content is present so we know the
        // SwiftUI hierarchy rendered.  Update this assertion when ContentView
        // is replaced by the real onboarding / settings UI.
        let helloLabel = app.staticTexts["content-view-hello-world-label"]
        XCTAssertTrue(
            helloLabel.waitForExistence(timeout: 5),
            "Expected 'Hello, world!' label (identifier: content-view-hello-world-label)"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
