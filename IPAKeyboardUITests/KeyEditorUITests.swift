//
//  KeyEditorUITests.swift
//  IPAKeyboardUITests
//
//  Coverage of the key-level layout editor (issue #6): open the library ->
//  open a built-in layout -> "Duplicate to Edit" -> "Edit Keys" -> edit one
//  key's inserted text and spoken (VoiceOver) name -> Save -> assert the
//  change is visible back on the layout-detail screen's live preview.
//
//  REQUIRES A LIVE APP GROUP CONTAINER. `LayoutStore.save`/`delete` need
//  `AppGroup.containerURL` to be non-nil, which needs the App Group
//  *entitlement* embedded in the running process — i.e. a code-signed build.
//  Every lane that runs this suite now signs the app: local runs sign
//  automatically under the project's team, and CI signs ad-hoc
//  (`CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-`, which needs no
//  certificate or account on a simulator destination — issue #210). Verified
//  empirically: `simctl get_app_container <udid> net.yuryu.IPAKeyboard
//  groups` reports a live container for an ad-hoc-signed build and reports
//  nothing for a `CODE_SIGNING_ALLOWED=NO` one.
//
//  So the fork *must* persist here, and `duplicateBuiltInLayout(from:
//  library:)` below fails the test if it doesn't. These tests used to
//  `XCTSkip` on the degraded path, which meant a signing regression read as
//  a green run — the skip-is-a-pass false green the testing-and-ci skill
//  warns about. The degraded path itself keeps its coverage where it can be
//  driven deterministically: `IPAKeyboardTests/LayoutLibraryTests.swift`
//  injects `LayoutStore(containerURL: nil)` and asserts the friendly
//  shared-storage message.
//
//  Conventions
//  -----------
//  - Test names: test_<flow>_<expectation>
//  - Elements located by accessibilityIdentifier first, label second,
//    type-query last — never by index or coordinate.
//  - Synchronisation via waitForExistence, not sleep.
//  - continueAfterFailure = false so failures are reported at their root cause.
//  - Failure screenshots are attached automatically in tearDown.
//
//  Layout choice: this flow forks "IPA — Full (QWERTY)" (`ipa-full.json`,
//  locale `und`) rather than "English (US) — General American". English (US)
//  is the `ActiveLayoutResolver` default, so on a fresh launch its name is
//  rendered *twice* (once as plain text in the "Active" section preview,
//  once as the tappable built-in row) — an ambiguous target for
//  `LibraryScreen.row(labelContains:)`. "IPA — Full (QWERTY)" is never the
//  default active layout, so its row label is unique (once any leftover
//  fork has been reset — see "Hermeticity" below).
//
//  Hermeticity: `LayoutStore` persists forked user layouts to the container
//  across `app.launch()` calls within the same test session — and, now that
//  every lane has a container, across other suites in the same run too.
//  "Duplicate to Edit" always names the fork "<source> (Custom)" with no way
//  to vary it from the UI, so a leftover fork from a previous run would
//  collide with a fresh one and make the row(labelContains:) lookups
//  ambiguous. `setUp` passes
//  `LibraryScreen.resetLayoutsArgument` (`--uitest-reset-layouts`,
//  `LayoutLibrary`'s UI-test reset hook, issue #27), which clears every user
//  layout and per-layout preference before the library ever renders — a safe
//  no-op when the container is unavailable (nothing persisted to clear).
//  This replaces the previous swipe-to-delete self-healing helper.
//

import XCTest

final class KeyEditorUITests: XCTestCase {

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
        // Onboarding (#34) appears on a fresh install and covers the library
        // list; skip it like every other non-onboarding suite does.
        // Reset persisted user layouts/prefs (issue #27) so this suite's
        // fork-dependent tests are hermetic without swipe-to-delete
        // self-healing — see the file-level comment.
        app.launchArguments += [
            OnboardingScreen.forceSkipArgument,
            LibraryScreen.resetLayoutsArgument,
        ]
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

    /// The built-in layout this flow forks. Never the default active layout
    /// (see the file-level comment), so its library row label is unique once
    /// any leftover fork has been reset (see the "Hermeticity" note above).
    private static let sourceLayoutName = "IPA — Full (QWERTY)"

    /// Name `KeyboardLayout.makeEditableCopy(named:)` gives the fork when
    /// called with the default `newName: nil` — `"\(name) (Custom)"`.
    private static let forkedLayoutName = "\(sourceLayoutName) (Custom)"

    /// Taps "Duplicate to Edit" on `builtInDetail` and asserts the fork
    /// persisted: a new row appears under "My Layouts", leaving the library
    /// as the current screen.
    ///
    /// Still polls the "Something went wrong" alert alongside the forked row
    /// rather than waiting on the row alone — not because the alert is an
    /// acceptable outcome (it isn't; see the file-level comment), but so the
    /// failure message names *which* way it went. A run that lost its App
    /// Group container reports the shared-storage alert by name instead of an
    /// anonymous "row never appeared" timeout.
    @MainActor
    private func duplicateBuiltInLayout(from builtInDetail: LayoutDetailScreen, library: LibraryScreen) {
        builtInDetail.duplicateButton.tap()

        // Both conditions polled under one shared deadline: a one-sided
        // fixed-window probe could pick the wrong branch on a slow runner
        // (issue #99). The success condition must be the forked row, not the
        // library reappearing: `LayoutDetailView` pops back unconditionally
        // after `fork`, so the library's navigation bar shows up on the
        // failure path too — often before the root-presented alert — and only
        // the row is exclusive to a persisted fork.
        let errorAlert = app.alerts["Something went wrong"]
        let forkedRow = library.row(labelContains: Self.forkedLayoutName)
        switch waitForEither(
            errorAlert, forkedRow, scrollingSecondIn: library.layoutList, timeout: .postNavigation
        ) {
        case .first:
            XCTFail(
                "'Duplicate to Edit' surfaced the 'Something went wrong' alert instead of "
                    + "persisting a fork. This suite requires a live App Group container, so "
                    + "the app must be signed — locally automatic, in CI ad-hoc via "
                    + "CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- (issue #210).")
        case .second:
            break
        case nil:
            XCTFail(
                "Neither the save-failure alert nor the forked row appeared within "
                    + "\(TimeInterval.postNavigation)s of tapping 'Duplicate to Edit'")
        }
    }

    /// Opens the built-in "IPA — Full (QWERTY)" layout's detail screen from
    /// a freshly-loaded library. `setUp`'s `LibraryScreen.resetLayoutsArgument`
    /// guarantees no leftover fork from a previous run is present (issue #27).
    @MainActor
    private func openSourceLayoutDetail() -> LayoutDetailScreen {
        let library = LibraryScreen(app: app)
        XCTAssertTrue(library.waitForContent(timeout: .postNavigation), "Library did not appear")
        let detail = LayoutDetailScreen(app: app)
        // Reveal + tap with a settle probe on the detail preview (the first
        // element unique to the pushed screen) — see `revealTapAndSettle`.
        XCTAssertTrue(
            library.openRow(
                labelContainsAll: [Self.sourceLayoutName, "Built-in, read-only"],
                pushSentinel: detail.preview, timeout: .postNavigation),
            "Built-in '\(Self.sourceLayoutName)' row not found")

        XCTAssertTrue(
            detail.waitForContent(timeout: .postNavigation),
            "'Duplicate to Edit' button did not appear on built-in detail screen")
        return detail
    }

    // MARK: - Container-independent coverage (always runs)

    /// A built-in layout's detail screen offers "Duplicate to Edit" but never
    /// "Edit Keys" — key-level editing is user-layouts-only (issue #6 scope:
    /// "built-ins stay read-only"). Deterministic: doesn't touch the App
    /// Group container.
    @MainActor
    func test_builtInDetail_doesNotOfferEditKeys() throws {
        app.launch()
        let detail = openSourceLayoutDetail()

        XCTAssertTrue(detail.duplicateButton.exists, "Built-in detail should offer 'Duplicate to Edit'")
        XCTAssertFalse(detail.editKeysButton.exists, "Built-in detail should not offer 'Edit Keys'")
    }

    /// "Duplicate to Edit" persists a fork of the built-in layout: a new row
    /// appears under "My Layouts" and the library stays usable. Real coverage
    /// of `LayoutLibrary.fork`'s success path, which no lane could reach while
    /// CI ran unsigned (issue #210); the nil-container error path is covered
    /// deterministically by `LayoutLibraryTests`' injected-seam tests.
    @MainActor
    func test_duplicateBuiltIn_persistsForkedLayout() throws {
        app.launch()
        let detail = openSourceLayoutDetail()
        let library = LibraryScreen(app: app)

        duplicateBuiltInLayout(from: detail, library: library)

        let forkedRow = library.waitForRow(labelContains: Self.forkedLayoutName, timeout: 5)
        XCTAssertTrue(forkedRow.exists, "Forked row not found under My Layouts after a successful fork")
        XCTAssertTrue(library.layoutList.exists, "Layout list not usable after duplicating")
    }

    // MARK: - Full editor flow

    @MainActor
    func test_editorFlow_editedKeyPersistsToDetailPreview() throws {
        app.launch()
        let builtInDetail = openSourceLayoutDetail()
        let library = LibraryScreen(app: app)

        duplicateBuiltInLayout(from: builtInDetail, library: library)

        // Open the forked user layout's detail screen — reveal + tap with a
        // settle probe on "Edit Keys", the sentinel unique to a *user*
        // layout's detail screen (see `revealTapAndSettle`).
        let userDetail = LayoutDetailScreen(app: app)
        XCTAssertTrue(
            library.openRow(
                labelContains: Self.forkedLayoutName,
                pushSentinel: userDetail.editKeysButton, timeout: 5),
            "Forked '\(Self.forkedLayoutName)' row not found under My Layouts")

        XCTAssertTrue(
            userDetail.waitForUserLayoutContent(timeout: .postNavigation),
            "'Edit Keys' button did not appear on the forked layout's detail screen")

        // Sanity: the unedited key renders in the preview before we change
        // anything — located by its inserted text ("q" → key-insert-q) and
        // cross-checked by its spoken name — so the post-save assertions
        // below are a genuine before/after comparison rather than queries
        // that would have matched regardless.
        let uneditedKey = userDetail.previewKey(inserting: "q")
        XCTAssertTrue(
            uneditedKey.waitForExistence(timeout: 5),
            "Expected the unedited 'q' key (key-insert-q) in the preview before editing")
        XCTAssertEqual(
            uneditedKey.label, "voiceless uvular plosive",
            "Unedited 'q' key does not speak its VoiceOver name in the preview")

        // "Edit Keys" -> key editor root -> row 0 -> key 0 ('q', the QWERTY
        // panel's first key in ipa-full.json).
        userDetail.editKeysButton.tap()

        let keyEditor = LayoutKeyEditorScreen(app: app)
        XCTAssertTrue(keyEditor.waitForContent(timeout: .postNavigation), "Key editor sheet did not appear")

        let firstRow = keyEditor.waitForRow(at: 0, timeout: 5)
        XCTAssertTrue(firstRow.exists, "key-editor-row-0 not found")
        firstRow.tap()

        let rowEditor = KeyRowEditorScreen(app: app)
        XCTAssertTrue(
            rowEditor.waitForContent(rowNumber: 1, timeout: .postNavigation),
            "Row editor for row 1 did not appear")

        let firstKey = rowEditor.waitForKey(at: 0, timeout: 5)
        XCTAssertTrue(firstKey.exists, "row-editor-key-0 not found")
        firstKey.tap()

        // Edit the key's inserted text ("q" -> "qʰ", a real aspirated
        // voiceless uvular plosive) and its spoken name, then commit.
        let form = KeyEditorFormScreen(app: app)
        XCTAssertTrue(form.insertTextField.waitForExistence(timeout: .postNavigation), "Key form did not appear")

        let editedText = "q\u{02B0}" // "qʰ": U+0071 LATIN SMALL LETTER Q, U+02B0 MODIFIER LETTER SMALL H
        form.replaceText(in: form.insertTextField, with: editedText)
        XCTAssertEqual(
            form.insertTextField.value as? String, editedText,
            "Inserted-text field lost or altered the typed Unicode text")
        XCTAssertTrue(
            form.unicodeReadout.waitForExistence(timeout: 5),
            "Code-point readout did not appear for non-empty inserted text")
        XCTAssertEqual(
            form.unicodeReadout.label, "Code points: U+0071 U+02B0",
            "Code-point readout did not report the exact edited Unicode scalars")

        let editedSpokenName = "voiceless uvular plosive (edited)"
        form.replaceText(in: form.accessibilityLabelField, with: editedSpokenName)
        XCTAssertEqual(
            form.accessibilityLabelField.value as? String, editedSpokenName,
            "Spoken-name field lost or altered the typed text")

        XCTAssertTrue(form.doneButton.isEnabled, "'Done' should be enabled — inserted text is non-empty")
        form.doneButton.tap()

        // Back in the row editor: the committed edit is reflected
        // immediately (draft, not yet saved).
        XCTAssertTrue(
            rowEditor.waitForContent(rowNumber: 1, timeout: .postNavigation),
            "Did not return to the row editor after committing the key form")
        XCTAssertTrue(
            app.staticTexts[editedText].waitForExistence(timeout: 5),
            "Row editor does not show the edited glyph '\(editedText)'")
        XCTAssertTrue(
            app.staticTexts[editedSpokenName].waitForExistence(timeout: 5),
            "Row editor does not show the edited spoken name")

        // Back to the key-editor root and Save.
        app.navigationBars.buttons["Edit Keys"].tap()
        XCTAssertTrue(keyEditor.waitForContent(timeout: .postNavigation), "Did not return to the key editor root")
        XCTAssertTrue(
            keyEditor.saveButton.isEnabled,
            "Save should be enabled once the draft has unsaved changes")
        keyEditor.saveButton.tap()

        // Sheet dismisses back to the (still forked) layout's detail screen,
        // whose preview now reflects the saved edit.
        XCTAssertTrue(
            userDetail.waitForUserLayoutContent(timeout: .postNavigation),
            "Did not return to the layout-detail screen after saving")
        // Per-key identifiers (issue #25) let this assert the *inserted text*
        // changed — "key-insert-qʰ" replacing "key-insert-q" — not just the
        // spoken name, which the label cross-check still covers.
        let editedKey = userDetail.previewKey(inserting: editedText)
        XCTAssertTrue(
            editedKey.waitForExistence(timeout: 10),
            "Detail preview does not show a key inserting '\(editedText)' "
                + "after Save — the edit did not persist")
        XCTAssertEqual(
            editedKey.label, editedSpokenName,
            "Edited key's spoken name did not update in the detail preview")
        XCTAssertFalse(
            userDetail.previewKey(inserting: "q").exists,
            "Detail preview still shows the pre-edit 'q' key after Save")
    }

    /// Cancel-without-saving must leave the layout unchanged: reopening "Edit
    /// Keys" shows the original content, not a discarded draft. Exercises the
    /// discard-confirmation path, which (unlike Save) never touches the App
    /// Group container — but still needs one to *open* via a real fork, so it
    /// shares the happy-path test's container requirement.
    @MainActor
    func test_editorFlow_cancelWithChangesDiscardsDraft() throws {
        app.launch()
        let builtInDetail = openSourceLayoutDetail()
        let library = LibraryScreen(app: app)

        duplicateBuiltInLayout(from: builtInDetail, library: library)

        let userDetail = LayoutDetailScreen(app: app)
        XCTAssertTrue(
            library.openRow(
                labelContains: Self.forkedLayoutName,
                pushSentinel: userDetail.editKeysButton, timeout: 5),
            "Forked '\(Self.forkedLayoutName)' row not found under My Layouts")

        XCTAssertTrue(userDetail.waitForUserLayoutContent(timeout: .postNavigation))
        userDetail.editKeysButton.tap()

        let keyEditor = LayoutKeyEditorScreen(app: app)
        XCTAssertTrue(keyEditor.waitForContent(timeout: .postNavigation))
        XCTAssertFalse(
            keyEditor.saveButton.isEnabled,
            "Save should start disabled — the draft has no changes yet")

        // Make an unsaved change: append an empty row. "Add Row" sits below
        // the rows section, so reveal it first (lazy List composition).
        XCTAssertTrue(
            keyEditor.waitForAddRowButton(timeout: 10).exists,
            "'Add Row' button not found in the key editor")
        keyEditor.addRowButton.tap()
        XCTAssertTrue(
            keyEditor.saveButton.isEnabled,
            "Save should become enabled once the draft has an unsaved change")
        // Validate the persistence probe used after reopening below: the
        // appended row is the only one whose summary reads "No keys yet"
        // (every bundled row ships with keys), so it must be findable in the
        // dirty draft — otherwise the final absence assertion would pass
        // vacuously with a broken query.
        XCTAssertTrue(
            keyEditor.waitForEmptyRow(timeout: 10).exists,
            "Appended empty row ('No keys yet') not found in the dirty draft")

        // Cancel -> confirms discard -> dismisses without saving.
        keyEditor.cancelButton.tap()
        XCTAssertTrue(
            keyEditor.discardConfirmButton.waitForExistence(timeout: .postNavigation),
            "Discard-changes confirmation did not appear for a dirty draft")
        keyEditor.discardConfirmButton.tap()

        XCTAssertTrue(
            userDetail.waitForUserLayoutContent(timeout: .postNavigation),
            "Did not return to the layout-detail screen after discarding")

        // Reopening the editor must show the original (unmodified) content —
        // the added empty row must not have persisted. Probe by *content*,
        // not by the Save button alone: if the discard path had wrongly
        // persisted the draft, a fresh LayoutDraft would compare equal to
        // the (corrupted) saved document and Save would be disabled anyway,
        // so that check cannot detect the failure by itself.
        // `waitForEmptyRow` swipes through the whole rows list before giving
        // up, so lazy List composition can't hide a persisted row from the
        // absence assertion.
        userDetail.editKeysButton.tap()
        XCTAssertTrue(keyEditor.waitForContent(timeout: .postNavigation))
        XCTAssertFalse(
            keyEditor.waitForEmptyRow(timeout: 5).exists,
            "Reopened editor still shows the appended 'No keys yet' row — "
                + "the discarded draft persisted")
        XCTAssertFalse(
            keyEditor.saveButton.isEnabled,
            "Save should be disabled on a freshly reopened, unchanged draft")
    }
}
