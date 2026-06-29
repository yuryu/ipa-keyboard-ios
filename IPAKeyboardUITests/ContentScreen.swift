//
//  ContentScreen.swift
//  IPAKeyboardUITests
//
//  Page-object for the app's root ContentView.
//  Construct after app.launch() has returned.
//

import XCTest

/// Wraps all element queries for the root `ContentView` that ships with the
/// stock template.  Update or replace this object as the real settings /
/// onboarding / layout-management UI is built out.
@MainActor
struct ContentScreen {
    let app: XCUIApplication

    // MARK: - Element accessors

    /// The globe SF Symbol decorating the placeholder header.
    /// Backed by `.accessibilityIdentifier("content-view-globe-image")`.
    var globeImage: XCUIElement {
        app.images["content-view-globe-image"]
    }

    /// The "Hello, world!" placeholder label.
    /// Backed by `.accessibilityIdentifier("content-view-hello-world-label")`.
    var helloWorldLabel: XCUIElement {
        app.staticTexts["content-view-hello-world-label"]
    }

    // MARK: - Synchronised waits

    /// Blocks until the screen's primary content is present, or the timeout
    /// expires.  Returns `true` when ready.
    @discardableResult
    func waitForContent(timeout: TimeInterval = 5) -> Bool {
        helloWorldLabel.waitForExistence(timeout: timeout)
    }
}
