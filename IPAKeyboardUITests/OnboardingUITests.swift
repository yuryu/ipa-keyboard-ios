//
//  OnboardingUITests.swift
//  IPAKeyboardUITests
//
//  UI tests for the "Enable the Keyboard" onboarding flow (issue #7):
//  first-run auto-presentation, the persistent reopen affordance, the
//  Full-Access-not-required messaging, and the force-skip path.
//
//  Driven entirely through the launch-argument overrides described in
//  `OnboardingState.swift` (`OnboardingScreen.forceShowArgument` /
//  `forceSkipArgument`) rather than the real first-run UserDefaults flag, so
//  each test is hermetic and order-independent regardless of what a prior
//  test run left behind on the simulator.
//
//  End-to-end verification of the "Open Settings" deep link and the
//  post-install "Keyboards" toggle in the real Settings app is out of scope
//  here — it requires the extension to be installed and enabled, which is
//  blocked on signing/provisioning (#3). These tests assert the deep-link
//  button exists without tapping it, since tapping backgrounds the app.
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

final class OnboardingUITests: XCTestCase {

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
    }

    @MainActor
    override func tearDown() async throws {
        // Attach a screenshot after every test run. XCTest discards it on
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

    // MARK: - First-run auto-presentation + dismissal

    /// With `--uitest-show-onboarding`, the guidance sheet auto-presents on
    /// launch and Done dismisses it back to the layout library, regardless of
    /// whatever first-run state the simulator's UserDefaults already holds.
    @MainActor
    func test_onboarding_forceShow_appearsOnLaunch_andCanBeDismissed() throws {
        app.launchArguments += [OnboardingScreen.forceShowArgument]
        app.launch()

        let onboarding = OnboardingScreen(app: app)
        XCTAssertTrue(
            onboarding.waitForContent(timeout: 10),
            "Onboarding sheet ('Enable the Keyboard') did not auto-present "
                + "with \(OnboardingScreen.forceShowArgument)"
        )
        XCTAssertTrue(
            onboarding.rootView.exists,
            "Onboarding root view (onboarding-view) missing"
        )

        XCTAssertTrue(
            onboarding.doneButton.waitForExistence(timeout: 5),
            "Done button (onboarding-done-button) missing from the sheet"
        )
        onboarding.doneButton.tap()

        XCTAssertTrue(
            onboarding.waitForDismissal(timeout: 5),
            "Onboarding sheet did not dismiss after tapping Done"
        )

        let library = LibraryScreen(app: app)
        XCTAssertTrue(
            library.waitForContent(timeout: 5),
            "Layout library ('Layouts') did not reappear after dismissing "
                + "onboarding"
        )
    }

    // MARK: - Persistent affordance

    /// With the sheet skipped on launch, the toolbar help button on the
    /// layout library reopens the same onboarding guidance on demand.
    @MainActor
    func test_onboarding_helpButton_reopensGuidance() throws {
        app.launchArguments += [OnboardingScreen.forceSkipArgument]
        app.launch()

        let library = LibraryScreen(app: app)
        XCTAssertTrue(
            library.waitForContent(timeout: 10),
            "Layout library did not appear with "
                + "\(OnboardingScreen.forceSkipArgument)"
        )

        let onboarding = OnboardingScreen(app: app)
        XCTAssertFalse(
            onboarding.navigationBar.exists,
            "Onboarding sheet should not auto-present with "
                + "\(OnboardingScreen.forceSkipArgument)"
        )

        XCTAssertTrue(
            library.helpButton.waitForExistence(timeout: 5),
            "Help button (layout-list-help-button) missing from the "
                + "'Layouts' toolbar"
        )
        library.helpButton.tap()

        XCTAssertTrue(
            onboarding.waitForContent(timeout: 5),
            "Tapping the help button did not reopen the onboarding sheet"
        )
    }

    // MARK: - Full Access messaging

    /// The sheet states plainly that Full Access is NOT required for typing,
    /// and offers (without requiring a tap) the Settings deep link.
    @MainActor
    func test_onboarding_statesFullAccessNotRequired() throws {
        app.launchArguments += [OnboardingScreen.forceShowArgument]
        app.launch()

        let onboarding = OnboardingScreen(app: app)
        XCTAssertTrue(onboarding.waitForContent(timeout: 10))

        let note = onboarding.fullAccessNote
        XCTAssertTrue(
            note.waitForExistence(timeout: 5),
            "Full-Access-not-required callout (onboarding-full-access-note) "
                + "missing"
        )
        XCTAssertTrue(
            note.label.localizedCaseInsensitiveContains("Full Access")
                && note.label.localizedCaseInsensitiveContains("not required"),
            "Expected the callout to state Full Access is not required; "
                + "got label: \(note.label)"
        )

        // Existence-only: tapping this button backgrounds the app into
        // Settings, which would leave the test unable to synchronize back.
        XCTAssertTrue(
            onboarding.openSettingsButton.exists,
            "Open Settings button (onboarding-open-settings-button) missing"
        )
    }

    // MARK: - Force-skip path

    /// With `--uitest-skip-onboarding`, the layout library appears
    /// immediately and the onboarding sheet never auto-presents.
    @MainActor
    func test_onboarding_forceSkip_showsListImmediately() throws {
        app.launchArguments += [OnboardingScreen.forceSkipArgument]
        app.launch()

        let library = LibraryScreen(app: app)
        XCTAssertTrue(
            library.waitForContent(timeout: 10),
            "Layout library ('Layouts') did not appear immediately with "
                + "\(OnboardingScreen.forceSkipArgument)"
        )
        XCTAssertTrue(
            library.layoutList.exists,
            "Layout list not visible when onboarding is skipped"
        )

        let onboarding = OnboardingScreen(app: app)
        XCTAssertFalse(
            onboarding.navigationBar.exists,
            "Onboarding sheet ('Enable the Keyboard') should not be "
                + "presented when \(OnboardingScreen.forceSkipArgument) is "
                + "passed"
        )
    }
}
