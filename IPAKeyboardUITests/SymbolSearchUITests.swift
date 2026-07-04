//
//  SymbolSearchUITests.swift
//  IPAKeyboardUITests
//
//  Coverage of the symbol reference and search flow (issue #17): open the
//  reference sheet from the library toolbar, search by spoken-name fragment
//  and by code point, verify the detail screen reports exact Unicode code
//  points (ɡ is U+0261, never conflated with ASCII g U+0067), and exercise
//  copy + scratchpad — including the per-row inline copy button (issue #69),
//  which must copy in place without pushing the detail screen.
//
//  Glyph-paste matching (searching by pasting "ɡ" itself) is covered by the
//  kit unit tests (SymbolInventoryTests.matchesExactGlyphNeverALookalike):
//  XCUITest's typeText cannot synthesize characters without a hardware-
//  keyboard equivalent, and driving the system paste menu (plus its
//  cross-app paste permission prompt) is not reliable in CI. The UI search
//  path is exercised here with ASCII queries ("nasal", "0261") through the
//  same `SymbolEntry.matches` code.
//
//  Environment: this screen reads only bundled layouts through `LayoutStore`
//  (no App Group container involved), so — unlike the key-editor suite —
//  every test here runs fully even before signing/provisioning lands.
//
//  Conventions
//  -----------
//  - Test names: test_<flow>_<expectation>
//  - Elements located by accessibilityIdentifier first, label second,
//    type-query last — never by index or coordinate.
//  - Synchronisation via waitForExistence, not sleep.
//  - continueAfterFailure = false so failures are reported at their root cause.
//  - Failure screenshots are attached automatically in tearDown.
//  - Launches with --uitest-skip-onboarding so the first-run onboarding
//    sheet never blocks the library toolbar (see OnboardingState.swift).
//

import XCTest

final class SymbolSearchUITests: XCTestCase {

    @MainActor private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        // Portrait, always, for the same hermeticity reason as
        // IPAKeyboardUITests: IPAKeyboardUITestsLaunchTests runs per UI
        // configuration and leaves the simulator in landscape, where lazy
        // lists drop off-screen rows from the accessibility tree.
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments += ["--uitest-skip-onboarding"]
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

    // MARK: Exact Unicode targets (never source-typed look-alikes)

    /// ɡ U+0261 LATIN SMALL LETTER SCRIPT G — the IPA voiced velar plosive.
    private static let scriptG = "\u{0261}"
    /// ŋ U+014B LATIN SMALL LETTER ENG — the velar nasal.
    private static let velarNasal = "\u{014B}"
    /// ə U+0259 LATIN SMALL LETTER SCHWA — a non-nasal control symbol.
    private static let schwa = "\u{0259}"

    /// Launches the app and opens the symbol reference sheet.
    @MainActor
    private func launchAndOpenReference() -> SymbolReferenceScreen {
        app.launch()
        let reference = SymbolReferenceScreen(app: app)
        XCTAssertTrue(
            reference.open(timeout: .postNavigation),
            "Symbol reference sheet did not open from the library toolbar")
        return reference
    }

    // MARK: - Tests

    @MainActor
    func test_symbolReference_opensAndDismissesFromLibraryToolbar() throws {
        let reference = launchAndOpenReference()

        // The inventory is non-empty out of the box: the bundled en-US schwa
        // key must surface as a row (scrolling if it composed below the fold).
        XCTAssertTrue(
            reference.waitForRevealed(reference.row(forSymbol: Self.schwa)),
            "Expected a row for the bundled schwa symbol in the unfiltered inventory")

        reference.doneButton.tap()
        // The library remains in the accessibility hierarchy *under* the
        // sheet, so asserting on its toolbar alone would pass vacuously —
        // wait for the sheet's own list to actually go away.
        XCTAssertTrue(
            reference.list.waitForNonExistence(timeout: .postNavigation),
            "Reference list still present after Done")
        XCTAssertTrue(
            reference.openButton.waitForExistence(timeout: .postNavigation),
            "Library toolbar did not come back after dismissing the reference sheet")
    }

    @MainActor
    func test_search_byNameFragment_findsVelarNasal() throws {
        let reference = launchAndOpenReference()

        reference.search("nasal")

        XCTAssertTrue(
            reference.waitForRevealed(reference.row(forSymbol: Self.velarNasal)),
            "Searching 'nasal' did not surface the ŋ (velar nasal) row")
        // waitForRevealed swiped through the filtered list, so this absence
        // check is not defeated by lazy row composition: schwa's spoken name
        // contains no 'nasal' fragment and must be filtered out.
        XCTAssertFalse(
            reference.row(forSymbol: Self.schwa).exists,
            "Searching 'nasal' should filter out schwa")
    }

    @MainActor
    func test_search_byCodePoint_showsExactScriptGDetail() throws {
        let reference = launchAndOpenReference()

        reference.search("0261")

        let gRow = reference.row(forSymbol: Self.scriptG)
        XCTAssertTrue(
            reference.waitForRevealed(gRow),
            "Searching '0261' did not surface the ɡ (U+0261) row")
        gRow.tap()

        // The detail must report the exact scalar — U+0261, and never the
        // ASCII look-alike g (U+0067) anywhere on the screen.
        let firstCodePoint = reference.codePointText(at: 0)
        XCTAssertTrue(
            firstCodePoint.waitForExistence(timeout: .postNavigation),
            "Code-point readout did not appear on the symbol detail screen")
        XCTAssertEqual(
            firstCodePoint.label, "U+0261",
            "Detail reports the wrong code point for ɡ")
        XCTAssertFalse(
            app.staticTexts["U+0067"].exists,
            "Detail screen must never show ASCII g's code point for ɡ")
    }

    @MainActor
    func test_search_noMatches_showsEmptyState() throws {
        let reference = launchAndOpenReference()

        reference.search("qqqq")

        XCTAssertTrue(
            reference.emptyState.waitForExistence(timeout: 10),
            "No-results placeholder did not appear for a match-less search")
        XCTAssertFalse(
            reference.row(forSymbol: Self.schwa).exists,
            "No symbol rows should remain for a match-less search")
    }

    @MainActor
    func test_rowCopyButton_copiesInPlace_withoutNavigating() throws {
        let reference = launchAndOpenReference()

        reference.search("0261")
        let gRow = reference.row(forSymbol: Self.scriptG)
        XCTAssertTrue(reference.waitForRevealed(gRow), "ɡ row not found for '0261'")

        // The row carries its own copy affordance — no detail visit needed.
        let rowCopy = reference.rowCopyButton(forSymbol: Self.scriptG)
        XCTAssertTrue(
            rowCopy.waitForExistence(timeout: 10),
            "Per-row copy button not found on the ɡ row")
        rowCopy.tap()

        // The label flips to "Copied" (sticky, race-free) — proof the tap
        // landed on the button. The flip is synchronous with the tap, so
        // the expectation fulfills on its first evaluation — it buys no
        // settle time for a (wrong) navigation push.
        let copied = NSPredicate(format: "label == %@", "Copied")
        expectation(for: copied, evaluatedWith: rowCopy)
        waitForExpectations(timeout: 10)

        // Copying must not navigate. The negative probe runs first: its 2s
        // window doubles as the settle time a wrongful push would need to
        // surface the detail screen's copy button, so the positive checks
        // below can't pass while a push is still animating in.
        XCTAssertFalse(
            reference.copyButton.waitForExistence(timeout: 2),
            "Detail screen appeared — the row copy button must not navigate")
        XCTAssertTrue(
            reference.list.exists,
            "Reference list left the screen after a row copy")
        XCTAssertTrue(gRow.exists, "ɡ row disappeared after a row copy")
    }

    @MainActor
    func test_symbolDetail_copyGivesFeedback_andScratchpadCollects() throws {
        let reference = launchAndOpenReference()

        reference.search("0261")
        let gRow = reference.row(forSymbol: Self.scriptG)
        XCTAssertTrue(reference.waitForRevealed(gRow), "ɡ row not found for '0261'")
        gRow.tap()

        // Copy: the button's label flips to "Copied" (sticky, race-free).
        XCTAssertTrue(
            reference.copyButton.waitForExistence(timeout: .postNavigation),
            "Copy button did not appear on the detail screen")
        reference.copyButton.tap()
        let copied = NSPredicate(format: "label == %@", "Copied")
        expectation(for: copied, evaluatedWith: reference.copyButton)
        waitForExpectations(timeout: 10)

        // Scratchpad: add the symbol, go back, and find its exact text
        // collected at the top of the reference list.
        XCTAssertTrue(reference.addToScratchpadButton.exists, "Add to Scratchpad not found")
        reference.addToScratchpadButton.tap()
        XCTAssertTrue(
            reference.backButton.waitForExistence(timeout: 10),
            "Back button not found on the symbol detail screen")
        reference.backButton.tap()

        XCTAssertTrue(
            reference.scratchpadText.waitForExistence(timeout: .postNavigation),
            "Scratchpad did not appear on the reference list after adding a symbol")
        XCTAssertEqual(
            reference.scratchpadText.label, Self.scriptG,
            "Scratchpad text is not the exact added symbol (ɡ U+0261)")
    }
}
