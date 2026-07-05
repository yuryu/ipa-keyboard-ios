//
//  AlternatesPopupUITests.swift
//  IPAKeyboardUITests
//
//  Press-interaction regression tests for the shared `KeyboardView`, driven
//  on the host app's live previews (the layout-detail preview and the
//  symbol editor render the same view the extension does):
//
//  - Issue #104: after long-pressing a key with alternates, the popup must
//    close when the finger is released — it used to stay stranded on screen
//    because a completed SwiftUI long-press ends press tracking, so the
//    physical finger-up delivered no callback at all. Release *on the key
//    cap* must type the base symbol (system-keyboard parity, PR #107;
//    previously typed nothing).
//  - Issue #71 (coverage added for issue #120): the key-press preview
//    balloon must track the press — shown while an insert key is held on
//    iPhone, gone on release — and must yield while the alternates popup is
//    open, so the two overlays never fight.
//
//  Exercised on the en-US layout: the `ɹ` key's long-press popup offers the
//  `r` alternate; `l` is its plain (no-alternates) same-row neighbor.
//

import UIKit
import XCTest
import os

final class AlternatesPopupUITests: XCTestCase {

    @MainActor private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        // Portrait, always — see the note in IPAKeyboardUITests.setUp: in
        // landscape the built-in layout row falls out of the lazy List's
        // accessibility tree.
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // Onboarding is exercised elsewhere; force-skip so a fresh simulator
        // doesn't auto-present the sheet over the layout list.
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

    // MARK: - Alternates popup lifecycle (issue #104)

    /// Long-press a key with alternates past the 0.3 s popup threshold,
    /// slide off it, and release — the repro from issue #104. The slide
    /// matters: a perfectly stationary synthesized press still ended in a
    /// successful tap (SwiftUI taps fail on movement, not duration), which
    /// happened to dismiss the popup even before the fix; real fingers
    /// micro-move, fail the tap, and stranded it. Dragging to a same-row
    /// neighbor reproduces that reliably. The popup must be gone once the
    /// finger lifts (the release lands off both popup and key cap, so it
    /// also types nothing — but the detail preview discards actions, so the
    /// assertion is popup dismissal).
    @MainActor
    func test_detailPreview_longPressSlideOffAndRelease_closesAlternatesPopup() throws {
        app.launch()
        let library = LibraryScreen(app: app)
        XCTAssertTrue(library.waitForContent(timeout: .postNavigation))

        XCTAssertTrue(
            library.openEnglishUS(timeout: .postNavigation),
            "English (US) built-in row not found or not hittable")

        let detail = LayoutDetailScreen(app: app)
        let rhotic = detail.previewKey(inserting: "ɹ")
        XCTAssertTrue(
            rhotic.waitForExistence(timeout: .postNavigation),
            "Preview does not expose the 'ɹ' key via 'key-insert-ɹ'"
        )
        // ɹ's same-row left-hand neighbor on the en-US main panel — same
        // row so the drag is horizontal and cannot scroll the List.
        let neighbor = detail.previewKey(inserting: "l")
        XCTAssertTrue(
            neighbor.waitForExistence(timeout: 10),
            "Preview does not expose the 'l' key via 'key-insert-l'"
        )

        rhotic.press(forDuration: 0.8, thenDragTo: neighbor)

        // The popup's alternate cell (`key-insert-r`, the alveolar trill)
        // must not remain in the tree after release. The popup legitimately
        // existed mid-gesture and is dismissing now — assert the eventual
        // state (nonexistence), not a fixed-window snapshot that races the
        // dismissal animation.
        let alternateCell = detail.previewKey(inserting: "r")
        XCTAssertTrue(
            alternateCell.waitForNonExistence(timeout: .postNavigation),
            "Alternates popup stayed on screen after the key was released (issue #104)"
        )
        // Belt and braces: a stranded popup can also surface as a *second*
        // element carrying the base key's identifier (accessibility
        // modifiers applied over the popup overlay used to stamp the cells
        // with the key's own identifier), so also pin the element count.
        XCTAssertEqual(
            detail.preview.descendants(matching: .any)
                .matching(identifier: "key-insert-ɹ").count,
            1,
            "Expected exactly one 'key-insert-ɹ' element after release — "
                + "more means the alternates popup is still on screen (issue #104)"
        )
    }

    /// The positive half of the interaction: hold `ɹ`, slide up into the
    /// popup, release — the alternate (`r`) must be committed, exactly once,
    /// and observable in the symbol editor's scratchpad (the only preview
    /// surface that records emitted actions). The drag destination is a
    /// coordinate offset from the located key — an exception to the
    /// "identifiers, never coordinates" convention that is unavoidable here:
    /// the popup cell only exists mid-gesture, when no element query can
    /// run. The offset is derived from the popup's fixed geometry (floats 56
    /// pt above the cap, 40-pt-tall cells), well within the hit-testing
    /// slop; tests run in portrait, where key caps are the default 50 pt.
    @MainActor
    func test_editorPreview_longPressSlideToPopup_commitsAlternateOnce() throws {
        app.launch()
        let rhotic = try openEditorPreviewRhotic()

        // The editor screen was just pushed: wait for ɹ's frame to stop
        // moving before deriving gesture coordinates from it — a start point
        // resolved from a still-settling frame puts the whole fixed-offset
        // drag in the wrong place (CI sightings 2026-07-03/-04 on two
        // unrelated branches: the slide committed nothing and the scratchpad
        // kept its placeholder).
        waitForStableFrame(of: rhotic)

        let start = rhotic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let inPopup = start.withOffset(CGVector(dx: 0, dy: -55))
        // Hold briefly inside the popup before releasing: the release
        // commits whatever cell the last *processed* drag position selected,
        // and on a slow runner a release issued in the same frame as the
        // final move can land before SwiftUI has observed the drag entering
        // the popup at all.
        start.press(
            forDuration: 0.8, thenDragTo: inPopup,
            withVelocity: .default, thenHoldForDuration: 0.3)

        let scratch = app.staticTexts["layout-editor-scratch"]
        XCTAssertTrue(scratch.waitForExistence(timeout: 5), "Editor scratchpad missing")
        XCTAssertEqual(
            scratch.label, "r",
            "Slide-to-select should commit the alternate exactly once"
        )
    }

    // MARK: - Cap-release commit (PR #107, coverage for issue #120)

    /// Hold a key with alternates past the 0.3 s popup threshold, then
    /// release without moving — the touch stays on the key cap, so the
    /// release must type the *base* symbol, exactly once (system-keyboard
    /// parity, PR #107; before it, releasing on the cap typed nothing). The
    /// `.baseKey` release classification is covered at kit level by
    /// AlternatesSelectionTests; this drives it end-to-end against the
    /// symbol editor's scratchpad, the only preview surface that records
    /// emitted actions. The press targets the located element itself (no
    /// coordinates needed — the release point is wherever the touch went
    /// down, the cap's center).
    @MainActor
    func test_editorPreview_longPressReleaseOnCap_typesBaseSymbolOnce() throws {
        app.launch()
        let rhotic = try openEditorPreviewRhotic()
        // The editor screen was just pushed: let ɹ's frame settle so the
        // key can't slide out from under the stationary 0.8 s touch while
        // the push animation finishes (a moved-away cap would classify the
        // release as `.dismiss` and type nothing).
        waitForStableFrame(of: rhotic)

        rhotic.press(forDuration: 0.8)

        let scratch = app.staticTexts["layout-editor-scratch"]
        XCTAssertTrue(scratch.waitForExistence(timeout: 5), "Editor scratchpad missing")
        // Event-driven wait for the commit to land in the scratchpad (the
        // press returns before SwiftUI has re-rendered the label), then pin
        // the exact grapheme: precisely one `ɹ` (U+0279) — a double
        // emission would read "ɹɹ", and the popup's alternate would read
        // "r".
        let committed = app.staticTexts.matching(identifier: "layout-editor-scratch")
            .matching(NSPredicate(format: "label == %@", "ɹ")).firstMatch
        XCTAssertTrue(
            committed.waitForExistence(timeout: 10),
            "Cap-release should type the base symbol 'ɹ' (U+0279) exactly once — "
                + "scratchpad reads '\(scratch.label)' (PR #107)"
        )
    }

    // MARK: - Key-preview balloon (issue #71, coverage for issue #120)

    /// Key-down on an insert key must show the magnified preview balloon,
    /// and key-up must remove it. Exercised on `l` — an insert key with no
    /// alternates, so no popup can interfere and the balloon owns the whole
    /// hold. The balloon only exists while the touch is down and the
    /// press blocks the test thread for the entire synthesis, so the
    /// existence check runs concurrently from a background observer — see
    /// `observe(whilePerforming:poll:)`.
    @MainActor
    func test_detailPreview_pressShowsBalloonAndReleaseHidesIt() throws {
        try skipUnlessPhoneIdiom()
        app.launch()
        let library = LibraryScreen(app: app)
        XCTAssertTrue(library.waitForContent(timeout: .postNavigation))

        XCTAssertTrue(
            library.openEnglishUS(timeout: .postNavigation),
            "English (US) built-in row not found or not hittable")

        let detail = LayoutDetailScreen(app: app)
        let lateral = detail.previewKey(inserting: "l")
        XCTAssertTrue(
            lateral.waitForExistence(timeout: .postNavigation),
            "Preview does not expose the 'l' key via 'key-insert-l'"
        )
        // Let the pushed screen settle so the key can't slide out from
        // under the long stationary touch.
        waitForStableFrame(of: lateral)

        // With no finger down there must be no balloon; this negative probe
        // runs before the press so its snapshot can't race the balloon's
        // legitimate appearance.
        XCTAssertFalse(balloon.exists, "Preview balloon present before any key was pressed")

        let appRef: XCUIApplication = app
        let balloonAppeared = observe(
            whilePerforming: { lateral.press(forDuration: Self.pressHoldDuration) },
            poll: {
                !Self.presentIdentifiers(in: appRef, among: [Self.balloonID]).isEmpty
            })

        XCTAssertTrue(
            balloonAppeared,
            "Preview balloon never appeared while the 'l' key was held (issue #71)"
        )
        // The balloon legitimately existed during the hold and is going away
        // now — assert the eventual state, not a snapshot racing the
        // key-up's render pass.
        XCTAssertTrue(
            balloon.waitForNonExistence(timeout: .postNavigation),
            "Preview balloon stayed on screen after the key was released (issue #71)"
        )
    }

    /// While the alternates popup is open the balloon must be hidden — the
    /// two overlays must never fight (the balloon/slide-to-select
    /// interference regression on PR #108's first CI run). A stationary
    /// hold on `ɹ` opens its popup after 0.3 s; once the popup's `r` cell
    /// is in the accessibility tree the balloon must leave it too — both
    /// flip on the same `showingAlternates` state change, though each
    /// element's accessibility exposure trails the render independently,
    /// so one overlapping sample is tolerated (see the observer comment in
    /// the body). The balloon legitimately shows during the pre-popup
    /// 0.3 s, so it is only sampled while the popup cell is present (a
    /// background observer samples mid-press; see
    /// `observe(whilePerforming:poll:)`). The release lands on the cap and
    /// types the base symbol, which the detail preview discards.
    @MainActor
    func test_detailPreview_balloonHiddenWhileAlternatesPopupOpen() throws {
        try skipUnlessPhoneIdiom()
        app.launch()
        let library = LibraryScreen(app: app)
        XCTAssertTrue(library.waitForContent(timeout: .postNavigation))

        XCTAssertTrue(
            library.openEnglishUS(timeout: .postNavigation),
            "English (US) built-in row not found or not hittable")

        let detail = LayoutDetailScreen(app: app)
        let rhotic = detail.previewKey(inserting: "ɹ")
        XCTAssertTrue(
            rhotic.waitForExistence(timeout: .postNavigation),
            "Preview does not expose the 'ɹ' key via 'key-insert-ɹ'"
        )
        waitForStableFrame(of: rhotic)

        // The observer records two facts per sample while the finger is
        // down: whether the popup's `r` cell was in the tree, and — sampled
        // only in that case — whether the balloon coexisted with it. Both
        // come from the same snapshot, so a sample can't straddle a state
        // change. The popup and the balloon flip on the same
        // `showingAlternates` state change, but each element's *exposure in
        // the accessibility tree* propagates on its own schedule, ~0.1–0.3 s
        // behind the render (measured by sampling this very hold at ~0.2 s
        // spacing: the balloon routinely misses the AX tree for its whole
        // 0.3 s pre-popup showing, and one popup-open sample can still carry
        // the removed balloon). So a single overlapping sample is
        // propagation skew, not the bug: the regression this test pins
        // (issue #71's overlays fighting) keeps the balloon up for the whole
        // remaining hold — many consecutive overlapping samples. The
        // observer therefore counts consecutive overlap samples from
        // popup-open (it stops at the first clean one) and the test rejects
        // only a persisting overlap.
        let alternateCell = detail.previewKey(inserting: "r")
        let alternateCellID = "key-insert-r"
        let appRef: XCUIApplication = app
        let record = OSAllocatedUnfairLock(
            initialState: (popupSeen: false, balloonWhilePopupOpenSamples: 0))
        _ = observe(
            whilePerforming: { rhotic.press(forDuration: Self.pressHoldDuration) },
            poll: {
                let present = Self.presentIdentifiers(
                    in: appRef, among: [alternateCellID, Self.balloonID])
                guard present.contains(alternateCellID) else { return false }
                let balloonNow = present.contains(Self.balloonID)
                record.withLock {
                    $0.popupSeen = true
                    if balloonNow { $0.balloonWhilePopupOpenSamples += 1 }
                }
                // Keep sampling until the popup is open balloon-free, so a
                // persisting violation can't hide behind a later clean sample.
                return !balloonNow
            })
        let observed = record.withLock { $0 }

        XCTAssertTrue(
            observed.popupSeen,
            "Alternates popup never opened during the stationary hold on 'ɹ'"
        )
        XCTAssertLessThanOrEqual(
            observed.balloonWhilePopupOpenSamples, 1,
            "Preview balloon stayed on screen while the alternates popup was "
                + "open (issue #71) — more than one consecutive overlap sample "
                + "is a stuck balloon, not accessibility-tree propagation skew"
        )
        // And the release must close the popup (issue #104's invariant,
        // cheap to re-pin here since the gesture already happened).
        XCTAssertTrue(
            alternateCell.waitForNonExistence(timeout: .postNavigation),
            "Alternates popup stayed on screen after the key was released (issue #104)"
        )
    }

    // MARK: - Helpers

    /// The key-press preview balloon's accessibility identifier, stamped by
    /// `KeyPreviewBalloon` in the kit's KeyboardView.swift (issue #120).
    private static let balloonID = "key-preview-balloon"

    /// The key-press preview balloon: a single unlabeled element carrying
    /// the kit-side identifier (`KeyPreviewBalloon` in the kit's
    /// KeyboardView.swift, issue #120), present exactly while an insert key
    /// is pressed on iPhone. Type-agnostic lookup for the same reason as
    /// `LayoutDetailScreen.previewKey(inserting:)`.
    @MainActor
    private var balloon: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: Self.balloonID).firstMatch
    }

    /// The balloon is iPhone-only by design (`KeyButton.showsPreviewBalloon`
    /// — system iPad keyboards show no key balloons), so balloon tests skip
    /// on other idioms instead of encoding platform-divergent expectations.
    @MainActor
    private func skipUnlessPhoneIdiom() throws {
        if UIDevice.current.userInterfaceIdiom != .phone {
            throw XCTSkip("Key-preview balloon is iPhone-only by design; nothing to assert on this idiom.")
        }
    }

    /// How long a stationary hold keeps the finger down when a background
    /// observer needs to sample the press-scoped UI. Generous on purpose:
    /// the observer's existence polls must land inside the press window
    /// even under issue-#96-scale poll inflation (~7 s per poll on an
    /// overloaded runner). The observer starts sampling before the touch
    /// even lands, so the headroom is pure margin, and the balloon tests
    /// pay it exactly once each.
    private static let pressHoldDuration: TimeInterval = 10

    /// Returns which of `identifiers` are present in `app`'s accessibility
    /// hierarchy right now, resolved from one raw snapshot — the only way
    /// `observe(whilePerforming:poll:)` closures may look at the UI.
    ///
    /// Poll closures must not touch `XCUIElement`/`XCUIElementQuery` (not
    /// even via KVC): query resolution logs an XCTest auto-activity
    /// ("Checking existence of …"), and a bare background thread has no
    /// XCTContext of its own (`XCTContext.runActivity` asserts "Current
    /// context must not be nil" there — verified on this toolchain), so
    /// that activity attaches to the *test thread's* current activity
    /// record. During `observe` that record is the gesture's own transient
    /// activity, and a poll straddling its completion trips
    /// `XCActivityRecord _ensureValid` — "Activity cannot be used after its
    /// scope has completed", aborting the test mid-run
    /// (NSInternalInconsistencyException, CI run 28731666930 on this PR's
    /// first push). `snapshotWithError:` (the ObjC spelling of public
    /// `XCUIElementSnapshotProviding.snapshot()`, reached by selector so
    /// the Swift interface's `@MainActor` annotation doesn't apply — at
    /// runtime only event *synthesis* enforces the main thread) bypasses
    /// the query-and-activity machinery entirely, and one snapshot answers
    /// every identifier atomically.
    private nonisolated static func presentIdentifiers(
        in app: XCUIApplication, among identifiers: Set<String>
    ) -> Set<String> {
        guard
            let root = app.perform(NSSelectorFromString("snapshotWithError:"), with: nil)?
                .takeUnretainedValue() as? XCUIElementSnapshot
        else { return [] }
        var found: Set<String> = []
        var stack: [any XCUIElementSnapshot] = [root]
        while let node = stack.popLast(), found != identifiers {
            if identifiers.contains(node.identifier) { found.insert(node.identifier) }
            stack.append(contentsOf: node.children)
        }
        return found
    }

    /// Runs `gesture` — a blocking, main-thread-only event synthesis:
    /// XCUIAutomation on this SDK raises `NSInternalInconsistencyException`
    /// ("Must be called on the main thread") when synthesis is attempted
    /// from any other thread — while a background thread repeatedly
    /// evaluates `poll`, and reports whether `poll` ever returned `true`
    /// before the gesture finished. That is what makes mid-gesture
    /// observation of transient, press-scoped UI (the preview balloon, the
    /// alternates popup) possible at all: the test thread is otherwise
    /// blocked for the whole synthesis. Poll closures must read the UI
    /// exclusively through `presentIdentifiers(in:among:)` — element
    /// queries are activity-logging and race the gesture's own activity
    /// records; see that helper's doc for the crash this prevents.
    ///
    /// The observer stops at the first `true` (or when the gesture ends),
    /// and this call always joins it before returning, so no orphaned
    /// background polls survive into the next gesture, an assertion
    /// failure, or teardown. Do all asserting on the returned value and
    /// on state the poll closure recorded itself.
    @MainActor
    private func observe(
        whilePerforming gesture: () -> Void,
        poll: @escaping @Sendable () -> Bool
    ) -> Bool {
        let state = OSAllocatedUnfairLock(initialState: (stop: false, seen: false))
        let done = expectation(description: "background observer finished")
        Thread.detachNewThread {
            while !state.withLock({ $0.stop }) {
                if poll() {
                    state.withLock { $0.seen = true }
                    break
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            done.fulfill()
        }
        gesture()
        state.withLock { $0.stop = true }
        // A single in-flight poll can outlive the gesture; give it the same
        // inflated-poll headroom the observation window itself gets.
        wait(for: [done], timeout: 30)
        return state.withLock { $0.seen }
    }

    /// Blocks until `element`'s frame is unchanged across two consecutive
    /// samples (0.2 s apart), or `timeout` expires. Gates gestures on a
    /// freshly pushed screen: a press located from a still-settling frame
    /// starts (or strands) the touch in the wrong place.
    @MainActor
    private func waitForStableFrame(of element: XCUIElement, timeout: TimeInterval = 10) {
        var previousFrame = CGRect.null
        let deadline = Date().addingTimeInterval(timeout)
        while element.frame != previousFrame, Date() < deadline {
            previousFrame = element.frame
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    /// Navigates launch → English (US) detail → symbol editor and returns
    /// the editor preview's `ɹ` key, existence-checked. Shared arrange
    /// phase of both editor-scratchpad tests; call after `app.launch()`.
    @MainActor
    private func openEditorPreviewRhotic() throws -> XCUIElement {
        let library = LibraryScreen(app: app)
        XCTAssertTrue(library.waitForContent(timeout: .postNavigation))

        XCTAssertTrue(
            library.openEnglishUS(timeout: .postNavigation),
            "English (US) built-in row not found or not hittable")

        let detail = LayoutDetailScreen(app: app)
        XCTAssertTrue(
            detail.waitForContent(timeout: .postNavigation),
            "Detail action section did not appear"
        )
        let customize = app.descendants(matching: .any)["layout-detail-customize-link"].firstMatch
        XCTAssertTrue(customize.waitForExistence(timeout: 5), "Customize symbols link missing")
        customize.tap()

        let editorPreview = app.otherElements["layout-editor-preview"]
        XCTAssertTrue(editorPreview.waitForExistence(timeout: .postNavigation), "Editor preview missing")
        let rhotic = editorPreview.descendants(matching: .any)["key-insert-ɹ"].firstMatch
        XCTAssertTrue(rhotic.waitForExistence(timeout: 10), "ɹ key missing from editor preview")
        return rhotic
    }
}
