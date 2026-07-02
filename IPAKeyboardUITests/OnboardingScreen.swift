//
//  OnboardingScreen.swift
//  IPAKeyboardUITests
//
//  Page object for the "Enable the Keyboard" onboarding sheet
//  (`OnboardingView.swift`), presented modally over `LayoutListView`.
//  Construct after app.launch() has returned.
//
//  Conventions
//  -----------
//  - Elements located by accessibilityIdentifier first, label second,
//    type-query last — never by index or coordinate.
//  - Synchronisation via waitForExistence / NSPredicate expectations, not sleep.
//  - @MainActor struct keeps all element access on the main actor.
//

import XCTest

/// Page object wrapping XCUIElement queries for the onboarding sheet
/// (`OnboardingView.swift`) and the launch arguments that drive its
/// auto-presentation (`OnboardingState.swift`).
///
/// Accessibility identifiers sourced from `OnboardingView.swift`:
///   `onboarding-view`                 — the sheet's root scroll view
///   `onboarding-full-access-note`     — "Full Access not required" callout
///   `onboarding-open-settings-button` — the Settings deep-link button
///   `onboarding-settings-open-failed` — inline fallback when the deep link fails
///   `onboarding-done-button`          — the Done toolbar button
@MainActor
struct OnboardingScreen {
    let app: XCUIApplication

    // MARK: Launch arguments (sourced from OnboardingState.swift)

    /// Forces the sheet to auto-present on launch, regardless of the stored
    /// "seen" flag. Matches `OnboardingState.forceShowArgument`.
    static let forceShowArgument = "--uitest-show-onboarding"
    /// Suppresses auto-presentation on launch (the help button still opens
    /// the sheet manually). Wins over `forceShowArgument` if both are passed.
    /// Matches `OnboardingState.forceSkipArgument`.
    static let forceSkipArgument = "--uitest-skip-onboarding"

    // MARK: Navigation

    /// The "Enable the Keyboard" navigation bar. First-class sentinel that the
    /// sheet is presented — SwiftUI sets this from `OnboardingView`'s
    /// `.navigationTitle`.
    var navigationBar: XCUIElement {
        app.navigationBars["Enable the Keyboard"]
    }

    // MARK: Elements

    /// The sheet's root scroll view.
    var rootView: XCUIElement {
        app.scrollViews["onboarding-view"]
    }

    /// The "Full Access is not required" callout. Rendered as a single merged
    /// accessibility element (`.accessibilityElement(children: .combine)`), so
    /// it is looked up by identifier across any element type rather than a
    /// specific query (`.otherElements` / `.staticTexts`), which SwiftUI does
    /// not guarantee for merged elements.
    var fullAccessNote: XCUIElement {
        element(identifier: "onboarding-full-access-note")
    }

    /// The "Open Settings" deep-link button. Assert existence only in tests —
    /// tapping it backgrounds the app into the Settings app.
    var openSettingsButton: XCUIElement {
        app.buttons["onboarding-open-settings-button"]
    }

    /// Inline fallback message shown only after a failed Settings deep link.
    var settingsOpenFailedNote: XCUIElement {
        element(identifier: "onboarding-settings-open-failed")
    }

    /// The "Done" toolbar button that dismisses the sheet.
    var doneButton: XCUIElement {
        app.buttons["onboarding-done-button"]
    }

    // MARK: Generic identifier lookup

    /// Matches any element type by accessibility identifier. Needed for merged
    /// (`.accessibilityElement(children: .combine)`) elements whose resulting
    /// `XCUIElement.ElementType` SwiftUI does not guarantee.
    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
    }

    // MARK: Synchronised wait

    /// Blocks until the "Enable the Keyboard" navigation bar is present, or
    /// `timeout` expires. Returns `true` when the sheet is ready.
    @discardableResult
    func waitForContent(timeout: TimeInterval = 10) -> Bool {
        navigationBar.waitForExistence(timeout: timeout)
    }

    /// Blocks until the "Enable the Keyboard" navigation bar is gone, or
    /// `timeout` expires. Returns `true` once the sheet has dismissed.
    @discardableResult
    func waitForDismissal(timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: navigationBar)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
