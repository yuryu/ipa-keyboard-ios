//
//  SystemKeyboardSmokeUITests.swift
//  IPAKeyboardUITests
//
//  Empirical end-to-end verification of the keyboard *extension* — the only
//  tests in this target that exercise the real `.appex` process and the
//  system text-input stack, rather than the host app's preview
//  `KeyboardView`. They type into the layout list's scratchpad (a real text
//  field, issue #103) with the actual IPA keyboard and verify the space
//  bar's trackpad-style cursor mode (issue #70):
//
//  1. `adjustTextPosition(byCharacterOffset:)` counts **UTF-16 code units**
//     (`CursorMovement`'s foundational assumption): one cursor step from
//     after "ə̃" must be sent as -2 and land exactly between "t" and "ə̃" —
//     if the API counted user-perceived characters instead, the same -2
//     would overshoot to before the "t".
//  2. A sustained drag never splits a base + combining-mark sequence: a
//     marker typed after dragging must sit at a grapheme boundary — a
//     marker that recombines with a stranded combining tilde ("ĩ") means a
//     step parked the cursor inside a cluster (the stale-context defect
//     `CursorMovement.Context` exists to prevent).
//
//  These tests SKIP unless the IPA keyboard is enabled on the simulator.
//  One-time setup (no signing needed — the unsigned extension runs fine on
//  a simulator): install the app, then in the Settings app: General →
//  Keyboard → Keyboards → Add New Keyboard… → IPAKeyboard. Writing the
//  `AppleKeyboards` array into com.apple.Preferences via
//  `simctl spawn … defaults write` does *not* reach the live text-input
//  system (verified 2026-07-04, iOS 26.5 simulator) — enable through the
//  Settings UI. CI simulators have no third-party keyboard enabled, so CI
//  skips these.
//
//  Conventions
//  -----------
//  - The host preview and the extension render identical identifiers
//    (`key-space`, `key-insert-ə`, …). The extension's keys are told apart
//    by geometry: its keyboard window lays out *below* the scratch field,
//    while the layout list's preview sits above it (`extensionKey(_:)`).
//  - Custom keyboards expose no `Keyboard`-type accessibility element
//    (`app.keyboards` matches nothing while the IPA keyboard is up), so
//    element queries run app-wide.
//  - Synchronisation via waitForExistence/polling deadlines, not fixed
//    sleeps.
//

import XCTest

final class SystemKeyboardSmokeUITests: XCTestCase {

    @MainActor private var app: XCUIApplication!

    /// One nasalized schwa: ə U+0259 + combining tilde U+0303 — one
    /// user-perceived character, two UTF-16 code units.
    private let nasalizedSchwa = "\u{0259}\u{0303}"

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments += [OnboardingScreen.forceSkipArgument]
    }

    @MainActor
    override func tearDown() async throws {
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

    // MARK: - Tests

    /// Pins the counting unit of `adjustTextPosition(byCharacterOffset:)`
    /// and single-step grapheme traversal, end-to-end. With "tə̃" typed and
    /// the cursor at the end, one cursor step left is sent as -2 (the
    /// UTF-16 length of "ə̃"); typing a marker must then yield "tiə̃".
    /// "itə̃" would mean the API counts user-perceived characters and the
    /// kit's offset math double-moves; anything else means the step split
    /// the cluster or the gesture misfired.
    @MainActor
    func test_extension_cursorStepCountsUTF16CodeUnitsAndWholeClusters() throws {
        try focusScratchpadOnIPAKeyboard()

        tapExtensionKey("key-insert-t")
        typeNasalizedSchwa()
        XCTAssertEqual(
            scratchText, "t\(nasalizedSchwa)",
            "seed text did not arrive intact through the extension")

        // 12 pt of leftward drag on the 8 pt/step grid: exactly one step.
        holdSpaceAndDragLeft(points: 12, velocity: 40)

        tapExtensionKey("key-insert-i")
        let result = scratchText
        XCTAssertNotEqual(
            result, "it\(nasalizedSchwa)",
            "one step moved two user-perceived characters — "
                + "adjustTextPosition(byCharacterOffset:) does not count UTF-16 "
                + "code units, so CursorMovement's offsets over-step")
        XCTAssertEqual(
            result, "ti\(nasalizedSchwa)",
            "one cursor step from after 'ə̃' must land between 't' and 'ə̃'")
    }

    /// A sustained drag (many touch samples, one step each) across
    /// combining-mark text: wherever it ends, the cursor must sit at a
    /// grapheme boundary. The marker "i" recombining with a stranded
    /// combining tilde ("ĩ") is the fingerprint of a split cluster —
    /// the stale-context defect the per-drag context mirror prevents.
    @MainActor
    func test_extension_sustainedDragNeverSplitsCombiningSequences() throws {
        try focusScratchpadOnIPAKeyboard()

        tapExtensionKey("key-insert-t")
        typeNasalizedSchwa()
        tapExtensionKey("key-insert-t")
        typeNasalizedSchwa()
        let seed = "t\(nasalizedSchwa)t\(nasalizedSchwa)"
        XCTAssertEqual(
            scratchText, seed,
            "seed text did not arrive intact through the extension")

        // 36 pt left at a gentle velocity: several samples per grid cell,
        // nominally 4 steps — enough to walk the whole seed.
        holdSpaceAndDragLeft(points: 36, velocity: 50)

        tapExtensionKey("key-insert-i")
        let result = scratchText
        XCTAssertFalse(
            result.contains("i\u{0303}"),
            "the marker recombined with a stranded combining tilde — a cursor "
                + "step parked the insertion point inside a grapheme cluster: \(result)")
        let boundaries: Set<String> = [
            "t\(nasalizedSchwa)ti\(nasalizedSchwa)",
            "t\(nasalizedSchwa)it\(nasalizedSchwa)",
            "ti\(nasalizedSchwa)t\(nasalizedSchwa)",
            "it\(nasalizedSchwa)t\(nasalizedSchwa)",
        ]
        XCTAssertNotEqual(
            result, "\(seed)i",
            "the drag produced no cursor movement at all")
        XCTAssertTrue(
            boundaries.contains(result),
            "the marker must sit between whole user-perceived characters; got: \(result)")
    }

    // MARK: - Reaching the extension's keyboard

    @MainActor private var scratchField: XCUIElement {
        app.textFields["layout-list-scratch"]
    }

    /// The scratch field's current text ("" while it shows its placeholder).
    @MainActor private var scratchText: String {
        let value = scratchField.value as? String ?? ""
        return value == scratchField.placeholderValue ? "" : value
    }

    /// Launches the app, focuses the scratchpad, and makes the IPA keyboard
    /// the active input mode — switching to it through the globe's
    /// input-mode picker when a system keyboard comes up first. Skips the
    /// test when the extension is not enabled on this device.
    @MainActor
    private func focusScratchpadOnIPAKeyboard() throws {
        app.launch()
        XCTAssertTrue(scratchField.waitForExistence(timeout: .postNavigation))
        scratchField.tap()

        if waitForExtensionKey("key-space", timeout: 5) != nil { return }

        // A system keyboard (or none) is up. The system globe's long-press
        // opens the input-mode picker, which lists the extension by its
        // display name.
        let globe = app.buttons["Next keyboard"]
        if globe.waitForExistence(timeout: 3) {
            globe.press(forDuration: 1.2)
            let ipaEntry = app.cells.matching(
                NSPredicate(format: "label BEGINSWITH %@", "KeyboardExtension")).firstMatch
            if ipaEntry.waitForExistence(timeout: 5) {
                ipaEntry.tap()
                if waitForExtensionKey("key-space", timeout: 10) != nil { return }
            }
        }
        throw XCTSkip(
            "IPA keyboard extension is not enabled on this simulator — "
                + "see the file header for the one-time Settings setup")
    }

    /// The *extension's* rendering of the key with `identifier`, told apart
    /// from the host preview's identically-identified key by geometry: the
    /// keyboard window lays out below the scratch field. Returns nil when no
    /// such element is currently on screen.
    @MainActor
    private func extensionKey(_ identifier: String) -> XCUIElement? {
        guard scratchField.exists else { return nil }
        let fieldBottom = scratchField.frame.maxY
        let matches = app.descendants(matching: .any).matching(identifier: identifier)
        for index in 0..<matches.count {
            let element = matches.element(boundBy: index)
            if element.frame.minY > fieldBottom { return element }
        }
        return nil
    }

    /// Polls for the extension's key with `identifier` until `timeout`
    /// expires (frame-filtered queries have no waitForExistence).
    @MainActor
    @discardableResult
    private func waitForExtensionKey(
        _ identifier: String, timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if let key = extensionKey(identifier) { return key }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        } while Date() < deadline
        return nil
    }

    // MARK: - Typing through the extension

    @MainActor
    private func tapExtensionKey(_ identifier: String, timeout: TimeInterval = 10) {
        guard let key = waitForExtensionKey(identifier, timeout: timeout) else {
            XCTFail("extension key not found: \(identifier)")
            return
        }
        key.tap()
    }

    /// Types one nasalized schwa (ə + combining tilde): the tilde lives on
    /// the en-US "More" panel, so this round-trips the panel switch.
    @MainActor
    private func typeNasalizedSchwa() {
        tapExtensionKey("key-insert-ə")
        tapExtensionKey("key-switchPanel-More")
        tapExtensionKey("key-insert-\u{0303}")
        tapExtensionKey("key-switchPanel-IPA")
    }

    /// Holds the extension's space bar past the 0.3 s cursor-mode threshold,
    /// then drags left by `points` at `velocity` (pt/s) and holds briefly
    /// before lifting. The hold-then-release path types nothing by design.
    @MainActor
    private func holdSpaceAndDragLeft(points: CGFloat, velocity: CGFloat) {
        guard let space = waitForExtensionKey("key-space", timeout: 10) else {
            XCTFail("extension space bar not found")
            return
        }
        // Start right-of-center so the leftward travel stays over the
        // keyboard (the touch may leave the key cap once cursor mode owns
        // the gesture — only the pre-recognition phase is anchored).
        let start = space.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
        let end = start.withOffset(CGVector(dx: -points, dy: 0))
        start.press(
            forDuration: 0.6,
            thenDragTo: end,
            withVelocity: XCUIGestureVelocity(rawValue: velocity),
            thenHoldForDuration: 0.3)
    }
}
