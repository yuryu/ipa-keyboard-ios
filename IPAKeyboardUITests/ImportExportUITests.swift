//
//  ImportExportUITests.swift
//  IPAKeyboardUITests
//
//  Coverage of layout import/export (issue #8).
//
//  WHAT IS AND ISN'T DRIVABLE HERE
//  -------------------------------
//  - The system document picker (`.fileImporter`) is remote system UI that
//    XCUITest cannot reliably drive, so the *file-picking* step is not
//    exercised end-to-end. Instead the app exposes a UI-test hook
//    (`LayoutLibrary.uiTestImportEnvironmentKey`, launch environment
//    `UITEST_IMPORT_JSON`): its value is fed through the exact same import
//    pipeline a picked file uses (kit validation → store save → alert on
//    failure), skipping only the picker and the security-scoped URL read.
//    The decode/identity rules themselves are unit-tested in
//    IPAKeyboardKitTests/LayoutTransferTests.swift.
//  - Export: tapping the "Export Layout" ShareLink and asserting the system
//    share sheet appears IS drivable and covered below. What the share sheet
//    does after that is system-owned.
//  - Persistence: on unsigned builds (CODE_SIGNING_ALLOWED=NO — signing is
//    deferred per CLAUDE.md) `AppGroup.containerURL` is nil, so a *valid*
//    import cannot persist; it must instead surface the friendly
//    shared-storage alert. `test_importValid_succeedsOrDegradesGracefully`
//    passes in both environments, exercising whichever path the build allows
//    (same pattern as KeyEditorUITests.duplicateBuiltInLayout).
//
//  Conventions
//  -----------
//  - Test names: test_<flow>_<expectation>
//  - Elements located by accessibilityIdentifier first, label second,
//    type-query last — never by index or coordinate.
//  - Synchronisation via waitForExistence, not sleep.
//  - continueAfterFailure = false; failure screenshots attached in tearDown.
//  - Every launch passes --uitest-skip-onboarding so the onboarding sheet
//    (auto-presented on first launch of a fresh install) can't cover the
//    library or block the import-error alert, and
//    LibraryScreen.resetLayoutsArgument (`LayoutLibrary`'s UI-test reset
//    hook, issue #27) so a leftover imported row from a previous (future,
//    provisioned) run can never collide with this run's fixed
//    `importedLayoutName` — the reset runs before the view (and hence any
//    injected import for that same launch) ever renders, so it can't clobber
//    an import injected in the same launch. Replaces the previous
//    swipe-to-delete self-healing helper.
//

import XCTest

final class ImportExportUITests: XCTestCase {

    @MainActor private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        // Portrait, always, for the same hermeticity reason as
        // IPAKeyboardUITests: IPAKeyboardUITestsLaunchTests runs per UI
        // configuration and leaves the simulator in landscape, where the
        // active-layout preview card fills the viewport and built-in rows
        // fall below the fold — SwiftUI's lazy list keeps off-screen cells
        // out of the accessibility tree, so row queries fail (CI flake:
        // "Built-in 'IPA — Full (QWERTY)' row not found").
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
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

    // MARK: - Constants (must mirror the app code they test)

    /// Launch-environment key checked by `LayoutLibrary` (see its
    /// `uiTestImportEnvironmentKey`).
    private static let importEnvironmentKey = "UITEST_IMPORT_JSON"

    /// The failure summary `LayoutLibrary.importLayout` prefixes to every
    /// import error (curly apostrophe — U+2019).
    private static let importFailurePrefix = "Couldn’t import this layout."

    /// `LayoutImportError.malformedDocument.errorDescription`.
    private static let malformedMessageFragment = "isn’t a valid keyboard layout"

    /// Stable fragment of `LayoutImportError.unsupportedSchemaVersion`'s
    /// description (the exact version numbers are asserted in unit tests).
    private static let newerFormatMessageFragment = "newer format"

    /// The message `LayoutLibrary.perform` uses when `LayoutStore` reports
    /// the shared container unavailable (unsigned builds).
    private static let sharedStorageMessageFragment =
        "Saving layouts needs the keyboard’s shared storage"

    /// A built-in that is never the resolver's default active layout, so its
    /// library row label is unique (see KeyEditorUITests' layout-choice note).
    private static let builtInLayoutName = "IPA — Full (QWERTY)"

    /// Name carried by the valid injected document below. Unique to this
    /// suite so leftover-row cleanup can never collide with other tests'
    /// forks ("… (Custom)").
    private static let importedLayoutName = "Imported Layout (UITest)"

    /// A well-formed schema-v2 document for the happy(ish) path. `ə` is
    /// U+0259, exactly as the keyboard inserts it.
    private static let validLayoutJSON = """
    {
      "schemaVersion": 2,
      "name": "\(importedLayoutName)",
      "locale": "en-US",
      "arrangements": [
        {
          "name": "Default",
          "panels": [
            {
              "name": "Main",
              "rows": [
                { "keys": [ { "action": { "type": "insert", "text": "ə" } } ] }
              ]
            }
          ]
        }
      ]
    }
    """

    /// Valid JSON that is not a supportable layout: a future schema version.
    private static let newerSchemaJSON = """
    { "schemaVersion": 99, "name": "Future", "locale": "und", "arrangements": [] }
    """

    // MARK: - Helpers

    /// Launches the app with onboarding suppressed and persisted user
    /// layouts/prefs reset (issue #27 — see the file-level comment),
    /// optionally injecting a layout document into the UI-test import hook.
    @MainActor
    private func launch(importJSON: String? = nil) {
        app.launchArguments += [
            "--uitest-skip-onboarding",
            LibraryScreen.resetLayoutsArgument,
        ]
        if let importJSON {
            app.launchEnvironment[Self.importEnvironmentKey] = importJSON
        }
        app.launch()
    }

    /// Waits for the root error alert, asserts its message contains both the
    /// import-failure prefix and `fragment`, dismisses it, and asserts the
    /// library is still usable afterward.
    @MainActor
    private func assertImportErrorAlert(messageContains fragment: String) {
        let alert = app.alerts["Something went wrong"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: .postNavigation),
            "Import-error alert did not appear")

        let message = alert.staticTexts.matching(
            NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@",
                Self.importFailurePrefix, fragment)
        ).firstMatch
        XCTAssertTrue(
            message.waitForExistence(timeout: 5),
            "Alert message does not contain '\(Self.importFailurePrefix)' and '\(fragment)'")

        alert.buttons["OK"].tap()
        let library = LibraryScreen(app: app)
        XCTAssertTrue(
            library.waitForContent(timeout: .postNavigation),
            "Library not usable after dismissing the import-error alert")
    }

    /// True once any recognizable share-sheet element exists. The share
    /// sheet is system UI whose internals vary by OS release, so several
    /// signatures are polled rather than relying on a single identifier.
    @MainActor
    private func waitForShareSheet(timeout: TimeInterval) -> Bool {
        let candidates: [XCUIElement] = [
            app.otherElements["ActivityListView"],
            app.navigationBars["UIActivityContentView"],
            app.otherElements["ShareSheet.RemoteContainerView"],
            app.buttons["Close"],
        ]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if candidates.contains(where: { $0.exists }) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        return false
    }

    // MARK: - Export

    /// Detail screen → "Export Layout" → the system share sheet appears.
    /// Container-independent: exporting only reads the bundled layout.
    @MainActor
    func test_exportBuiltIn_presentsShareSheet() throws {
        launch()

        let library = LibraryScreen(app: app)
        XCTAssertTrue(library.waitForContent(timeout: .postNavigation), "Library did not appear")
        let builtInRow = library.waitForRow(
            labelContainsAll: [Self.builtInLayoutName, "Built-in, read-only"], timeout: 10)
        XCTAssertTrue(builtInRow.exists, "Built-in '\(Self.builtInLayoutName)' row not found")
        builtInRow.tap()

        let detail = LayoutDetailScreen(app: app)
        // waitForContent scrolls to the action section, which sits below the
        // export section — so success guarantees the export button is loaded.
        XCTAssertTrue(detail.waitForContent(timeout: .postNavigation), "Detail screen did not appear")

        let exportButton = app.buttons["layout-detail-export-button"]
        XCTAssertTrue(
            detail.scrollTo(exportButton),
            "'Export Layout' button not found on the detail screen")
        exportButton.tap()

        XCTAssertTrue(
            waitForShareSheet(timeout: .postNavigation),
            "Share sheet did not appear after tapping 'Export Layout'")
    }

    // MARK: - Import (error paths, via the launch-environment hook)

    /// Malformed bytes → the user-visible error alert, app stays usable.
    @MainActor
    func test_importMalformedFile_showsErrorAlert() throws {
        launch(importJSON: "{ this is not JSON")
        assertImportErrorAlert(messageContains: Self.malformedMessageFragment)
    }

    /// A document declaring a newer schema version → the specific
    /// newer-format error, not a generic decode failure.
    @MainActor
    func test_importNewerSchemaVersion_showsVersionErrorAlert() throws {
        launch(importJSON: Self.newerSchemaJSON)
        assertImportErrorAlert(messageContains: Self.newerFormatMessageFragment)
    }

    /// The import affordance is present on the library toolbar. Tapping it
    /// opens the system document picker, which XCUITest cannot reliably
    /// dismiss, so this asserts presence/hittability only (see the
    /// file-level comment for where the rest of the pipeline is covered).
    @MainActor
    func test_importButton_isPresentOnLibraryToolbar() throws {
        launch()
        let importButton = app.buttons["layout-list-import-button"]
        XCTAssertTrue(importButton.waitForExistence(timeout: .postNavigation), "Import button not found")
        XCTAssertTrue(importButton.isHittable, "Import button not hittable")
    }

    // MARK: - Import (valid document)

    /// A valid document must either persist (row under "My Layouts") or —
    /// on unsigned builds where the App Group container is nil — surface the
    /// friendly shared-storage alert and leave the library usable. Never a
    /// crash, never a silent drop. Green in both environments.
    @MainActor
    func test_importValid_succeedsOrDegradesGracefully() throws {
        // `launch`'s LibraryScreen.resetLayoutsArgument clears any persisted
        // leftover from a previous (future, provisioned) run before this
        // launch's injected import runs, so the row assertion below can't
        // match stale data (issue #27 — see the file-level comment).
        launch(importJSON: Self.validLayoutJSON)

        let library = LibraryScreen(app: app)
        let alert = app.alerts["Something went wrong"]
        let importedRow = library.row(labelContains: Self.importedLayoutName)

        // Whichever condition actually materialises: the degraded-state
        // alert, or the imported row. A one-sided fixed-window probe here
        // could pick the wrong branch on a slow runner (issue #99), so both
        // are polled under one shared deadline and the branch below follows
        // whichever one actually appeared.
        switch waitForEither(
            alert, importedRow, scrollingSecondIn: library.layoutList, timeout: .postNavigation
        ) {
        case .first:
            let message = alert.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@ AND label CONTAINS %@",
                    Self.importFailurePrefix, Self.sharedStorageMessageFragment)
            ).firstMatch
            XCTAssertTrue(
                message.exists,
                "Valid-import failure alert should carry the shared-storage message")
            alert.buttons["OK"].tap()
            // The library's nav bar stays in the hierarchy *beneath* the
            // alert, so waitForContent alone would pass vacuously if the OK
            // tap silently failed — pin dismissal itself first.
            XCTAssertTrue(
                alert.waitForNonExistence(timeout: .postNavigation),
                "Shared-storage alert did not dismiss")
            XCTAssertTrue(
                library.waitForContent(timeout: .postNavigation),
                "Library not usable after dismissing the shared-storage alert")
            XCTAssertFalse(
                library.waitForRow(labelContains: Self.importedLayoutName, timeout: 2).exists,
                "No imported row should exist when persistence was unavailable")
        case .second:
            XCTAssertTrue(library.waitForContent(timeout: .postNavigation), "Library did not appear")
            XCTAssertTrue(
                importedRow.exists,
                "Imported layout row not found under 'My Layouts' after a successful import")
            // Hermeticity: no manual cleanup needed — the next launch (this
            // suite or any other) resets user layouts before rendering.
        case nil:
            XCTFail(
                "Neither the shared-storage alert nor the imported row appeared within "
                    + "\(TimeInterval.postNavigation)s of a valid import")
        }

        XCTAssertTrue(library.layoutList.exists, "Layout list not usable after importing")
    }
}
