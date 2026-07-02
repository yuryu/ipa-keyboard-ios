//
//  KeyEditorUITests.swift
//  IPAKeyboardUITests
//
//  Coverage of the key-level layout editor (issue #6): open the library ->
//  open a built-in layout -> "Duplicate to Edit" -> "Edit Keys" -> edit one
//  key's inserted text and spoken (VoiceOver) name -> Save -> assert the
//  change is visible back on the layout-detail screen's live preview.
//
//  ENVIRONMENT LIMITATION (confirmed via the runtime accessibility snapshot,
//  not assumed): `LayoutStore.save`/`delete` require `AppGroup.containerURL`
//  to be non-nil, which requires the App Group *entitlement* to actually be
//  embedded in the running process — i.e. a code-signed build. Every build
//  this suite can currently exercise uses `CODE_SIGNING_ALLOWED=NO` (signing
//  is deferred per CLAUDE.md — the Apple developer account is mid-
//  relocation), so the entitlement is never embedded and
//  `AppGroup.containerURL` is *always* nil here. Concretely: tapping
//  "Duplicate to Edit" always fails with `LayoutStore.StoreError
//  .sharedContainerUnavailable`, surfaced by `LayoutListView`'s "Something
//  went wrong" / "Couldn't save your copy..." alert — confirmed by capturing
//  the actual alert in the accessibility snapshot on this build. Since
//  forking is the *only* way to get a user layout to open "Edit Keys" on,
//  the full persistence round-trip cannot be driven end-to-end in this
//  environment; it is expected to work once the App Group is signed and
//  provisioned. `duplicateBuiltInLayout(from:library:)` below handles both
//  outcomes, and the persistence-dependent tests `XCTSkip` (not fail) when
//  the container is unavailable, so this suite stays green in the current
//  environment while still exercising the full flow automatically once
//  provisioning lands. The two `test_builtInDetail_*`/
//  `test_duplicateBuiltIn_*` tests below are container-independent and
//  always run.
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
//  fork is cleaned up — see below).
//
//  Hermeticity: when the App Group *is* available (e.g. a future signed run),
//  `LayoutStore` persists forked user layouts to the container across
//  `app.launch()` calls within the same test session — there is no
//  launch-argument to reset it (none exists in the app yet; see the report).
//  "Duplicate to Edit" always names the fork "<source> (Custom)" with no way
//  to vary it from the UI, so a leftover fork from a previous run would
//  collide with a fresh one and make the row(labelContains:) lookups
//  ambiguous. Every test calls `cleanUpForkedSourceLayout()` first, deleting
//  any pre-existing fork via the library row's own swipe-to-delete action
//  (no confirmation dialog on that path, so it stays idiom-agnostic on both
//  iPhone and iPad) — this makes each test self-healing regardless of what a
//  prior run left behind, without depending on tearDown running.
//

import XCTest

final class KeyEditorUITests: XCTestCase {

    @MainActor private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // Onboarding (#34) appears on a fresh install and covers the library
        // list; skip it like every other non-onboarding suite does.
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

    /// The built-in layout this flow forks. Never the default active layout
    /// (see the file-level comment), so its library row label is unique once
    /// any leftover fork has been cleaned up.
    private static let sourceLayoutName = "IPA — Full (QWERTY)"

    /// Name `KeyboardLayout.makeEditableCopy(named:)` gives the fork when
    /// called with the default `newName: nil` — `"\(name) (Custom)"`.
    private static let forkedLayoutName = "\(sourceLayoutName) (Custom)"

    /// The exact message `LayoutLibrary.fork` sets when `LayoutStore.save`
    /// throws `.sharedContainerUnavailable` (see `LayoutLibrary.perform`).
    private static let sharedStorageUnavailableMessage =
        "Couldn’t save your copy. Saving layouts needs the keyboard’s shared storage, "
        + "which isn’t set up yet."

    /// Deletes any leftover fork of `sourceLayoutName` from a previous test
    /// run via the library row's swipe-to-delete action (`LayoutListView`'s
    /// `.swipeActions`, which — unlike the layout-detail screen's Delete —
    /// calls `library.delete(layout)` directly with no confirmation dialog,
    /// so this works the same on iPhone and iPad without a popover/action-
    /// sheet idiom difference to handle). Call at the *start* of every test
    /// in this file so each run is self-healing regardless of what an
    /// earlier run left behind. Bounded to a handful of iterations so a
    /// genuine failure here surfaces as a hung/failed precondition rather
    /// than an infinite loop. A no-op when the App Group container is
    /// unavailable (nothing can have persisted — see the file-level comment).
    @MainActor
    private func cleanUpForkedSourceLayout() {
        let library = LibraryScreen(app: app)
        XCTAssertTrue(library.waitForContent(timeout: 10), "Library did not appear")
        for _ in 0..<5 {
            let row = library.waitForRow(labelContains: Self.forkedLayoutName, timeout: 3)
            guard row.exists else { return }
            row.swipeLeft()
            let deleteAction = app.buttons["Delete"]
            guard deleteAction.waitForExistence(timeout: 5) else {
                XCTFail("Swipe-to-delete action did not reveal a 'Delete' button")
                return
            }
            deleteAction.tap()
        }
    }

    /// Taps "Duplicate to Edit" on `builtInDetail` and handles both possible
    /// outcomes of `LayoutLibrary.fork` (see the file-level comment):
    /// - App Group available: a new row appears under "My Layouts" and this
    ///   returns `true`, leaving the library as the current screen.
    /// - App Group unavailable: the "Something went wrong" alert appears
    ///   with the expected message; this dismisses it and returns `false`,
    ///   leaving the library in its original, working state either way.
    @MainActor
    @discardableResult
    private func duplicateBuiltInLayout(from builtInDetail: LayoutDetailScreen, library: LibraryScreen) -> Bool {
        builtInDetail.duplicateButton.tap()

        let errorAlert = app.alerts["Something went wrong"]
        if errorAlert.waitForExistence(timeout: 5) {
            XCTAssertTrue(
                errorAlert.staticTexts[Self.sharedStorageUnavailableMessage].exists,
                "Unexpected error-alert message when the shared container is unavailable")
            errorAlert.buttons["OK"].tap()
            XCTAssertTrue(
                library.waitForContent(timeout: 10),
                "Library did not remain usable after dismissing the save-failure alert")
            return false
        }

        XCTAssertTrue(
            library.waitForContent(timeout: 10),
            "Did not return to the library after duplicating")
        return true
    }

    /// Opens the built-in "IPA — Full (QWERTY)" layout's detail screen from
    /// a freshly-loaded, cleaned-up library.
    @MainActor
    private func openSourceLayoutDetail() -> LayoutDetailScreen {
        cleanUpForkedSourceLayout()
        let library = LibraryScreen(app: app)
        let builtInRow = library.waitForRow(
            labelContainsAll: [Self.sourceLayoutName, "Built-in, read-only"], timeout: 5)
        XCTAssertTrue(builtInRow.exists, "Built-in '\(Self.sourceLayoutName)' row not found")
        builtInRow.tap()

        let detail = LayoutDetailScreen(app: app)
        XCTAssertTrue(
            detail.waitForContent(timeout: 10),
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

    /// "Duplicate to Edit" must never crash or strand the app regardless of
    /// whether the App Group container is available: either a new user-layout
    /// row appears, or a friendly error alert appears and can be dismissed
    /// back to a working library. Passes in both environments (see the
    /// file-level comment on why only the latter is exercised today), so this
    /// is real, deterministic, always-green coverage of `LayoutLibrary.fork`'s
    /// error-handling path.
    @MainActor
    func test_duplicateBuiltIn_succeedsOrDegradesGracefully() throws {
        app.launch()
        let detail = openSourceLayoutDetail()
        let library = LibraryScreen(app: app)

        let forkPersisted = duplicateBuiltInLayout(from: detail, library: library)

        if forkPersisted {
            let forkedRow = library.waitForRow(labelContains: Self.forkedLayoutName, timeout: 5)
            XCTAssertTrue(forkedRow.exists, "Forked row not found under My Layouts after a successful fork")
        } else {
            XCTAssertTrue(
                library.waitForRow(labelContains: Self.forkedLayoutName, timeout: 2).exists == false,
                "No forked row should exist when the fork failed to persist")
        }
        // Either way, the library must still be fully usable afterward.
        XCTAssertTrue(library.layoutList.exists, "Layout list not usable after duplicating")
    }

    // MARK: - Full editor flow (skips when the App Group container is unavailable)

    @MainActor
    func test_editorFlow_editedKeyPersistsToDetailPreview() throws {
        app.launch()
        let builtInDetail = openSourceLayoutDetail()
        let library = LibraryScreen(app: app)

        guard duplicateBuiltInLayout(from: builtInDetail, library: library) else {
            throw XCTSkip(
                "App Group container unavailable in this build (CODE_SIGNING_ALLOWED=NO — "
                    + "signing/provisioning is deferred per CLAUDE.md), so 'Duplicate to Edit' "
                    + "cannot persist a user layout here. This flow is expected to work once "
                    + "provisioning lands.")
        }

        // Open the forked user layout's detail screen.
        let forkedRow = library.waitForRow(labelContains: Self.forkedLayoutName, timeout: 5)
        XCTAssertTrue(
            forkedRow.exists,
            "Forked '\(Self.forkedLayoutName)' row not found under My Layouts")
        forkedRow.tap()

        let userDetail = LayoutDetailScreen(app: app)
        XCTAssertTrue(
            userDetail.waitForUserLayoutContent(timeout: 10),
            "'Edit Keys' button did not appear on the forked layout's detail screen")

        // Sanity: the unedited key's spoken name renders in the preview
        // before we change anything, so the post-save assertion below is a
        // genuine before/after comparison rather than a query that would
        // have matched regardless.
        XCTAssertTrue(
            userDetail.previewElements(withLabel: "voiceless uvular plosive").firstMatch
                .waitForExistence(timeout: 5),
            "Expected the unedited 'q' key's spoken name in the preview before editing")

        // "Edit Keys" -> key editor root -> row 0 -> key 0 ('q', the QWERTY
        // panel's first key in ipa-full.json).
        userDetail.editKeysButton.tap()

        let keyEditor = LayoutKeyEditorScreen(app: app)
        XCTAssertTrue(keyEditor.waitForContent(timeout: 10), "Key editor sheet did not appear")

        let firstRow = keyEditor.waitForRow(at: 0, timeout: 5)
        XCTAssertTrue(firstRow.exists, "key-editor-row-0 not found")
        firstRow.tap()

        let rowEditor = KeyRowEditorScreen(app: app)
        XCTAssertTrue(
            rowEditor.waitForContent(rowNumber: 1, timeout: 10),
            "Row editor for row 1 did not appear")

        let firstKey = rowEditor.waitForKey(at: 0, timeout: 5)
        XCTAssertTrue(firstKey.exists, "row-editor-key-0 not found")
        firstKey.tap()

        // Edit the key's inserted text ("q" -> "qʰ", a real aspirated
        // voiceless uvular plosive) and its spoken name, then commit.
        let form = KeyEditorFormScreen(app: app)
        XCTAssertTrue(form.insertTextField.waitForExistence(timeout: 10), "Key form did not appear")

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
            rowEditor.waitForContent(rowNumber: 1, timeout: 10),
            "Did not return to the row editor after committing the key form")
        XCTAssertTrue(
            app.staticTexts[editedText].waitForExistence(timeout: 5),
            "Row editor does not show the edited glyph '\(editedText)'")
        XCTAssertTrue(
            app.staticTexts[editedSpokenName].waitForExistence(timeout: 5),
            "Row editor does not show the edited spoken name")

        // Back to the key-editor root and Save.
        app.navigationBars.buttons["Edit Keys"].tap()
        XCTAssertTrue(keyEditor.waitForContent(timeout: 10), "Did not return to the key editor root")
        XCTAssertTrue(
            keyEditor.saveButton.isEnabled,
            "Save should be enabled once the draft has unsaved changes")
        keyEditor.saveButton.tap()

        // Sheet dismisses back to the (still forked) layout's detail screen,
        // whose preview now reflects the saved edit.
        XCTAssertTrue(
            userDetail.waitForUserLayoutContent(timeout: 10),
            "Did not return to the layout-detail screen after saving")
        XCTAssertTrue(
            userDetail.previewElements(withLabel: editedSpokenName).firstMatch
                .waitForExistence(timeout: 10),
            "Detail preview does not show the edited key's new spoken name "
                + "after Save — the edit did not persist")
        XCTAssertFalse(
            userDetail.previewElements(withLabel: "voiceless uvular plosive").firstMatch.exists,
            "Detail preview still shows the pre-edit spoken name after Save")
    }

    /// Cancel-without-saving must leave the layout unchanged: reopening "Edit
    /// Keys" shows the original content, not a discarded draft. Exercises the
    /// discard-confirmation path, which (unlike Save) never touches the App
    /// Group container — but still needs one to *open* via a real fork, so
    /// this shares the same skip guard as the happy-path test above.
    @MainActor
    func test_editorFlow_cancelWithChangesDiscardsDraft() throws {
        app.launch()
        let builtInDetail = openSourceLayoutDetail()
        let library = LibraryScreen(app: app)

        guard duplicateBuiltInLayout(from: builtInDetail, library: library) else {
            throw XCTSkip(
                "App Group container unavailable in this build (CODE_SIGNING_ALLOWED=NO — "
                    + "signing/provisioning is deferred per CLAUDE.md), so 'Duplicate to Edit' "
                    + "cannot persist a user layout here. This flow is expected to work once "
                    + "provisioning lands.")
        }

        let forkedRow = library.waitForRow(labelContains: Self.forkedLayoutName, timeout: 5)
        XCTAssertTrue(forkedRow.exists)
        forkedRow.tap()

        let userDetail = LayoutDetailScreen(app: app)
        XCTAssertTrue(userDetail.waitForUserLayoutContent(timeout: 10))
        userDetail.editKeysButton.tap()

        let keyEditor = LayoutKeyEditorScreen(app: app)
        XCTAssertTrue(keyEditor.waitForContent(timeout: 10))
        XCTAssertFalse(
            keyEditor.saveButton.isEnabled,
            "Save should start disabled — the draft has no changes yet")

        // Make an unsaved change: append an empty row.
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
            keyEditor.discardConfirmButton.waitForExistence(timeout: 5),
            "Discard-changes confirmation did not appear for a dirty draft")
        keyEditor.discardConfirmButton.tap()

        XCTAssertTrue(
            userDetail.waitForUserLayoutContent(timeout: 10),
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
        XCTAssertTrue(keyEditor.waitForContent(timeout: 10))
        XCTAssertFalse(
            keyEditor.waitForEmptyRow(timeout: 5).exists,
            "Reopened editor still shows the appended 'No keys yet' row — "
                + "the discarded draft persisted")
        XCTAssertFalse(
            keyEditor.saveButton.isEnabled,
            "Save should be disabled on a freshly reopened, unchanged draft")
    }
}
