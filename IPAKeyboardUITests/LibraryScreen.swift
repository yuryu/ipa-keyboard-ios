//
//  LibraryScreen.swift
//  IPAKeyboardUITests
//
//  Page objects for the layout-library root screen (LayoutListView) and the
//  layout-detail screen (LayoutDetailView).
//  Construct after app.launch() has returned.
//
//  Conventions
//  -----------
//  - Elements located by accessibilityIdentifier first, label second,
//    type-query last — never by index or coordinate.
//  - Synchronisation via waitForExistence, not sleep.
//  - @MainActor struct keeps all element access on the main actor.
//

import XCTest

/// Blocks until `element` exists, scrolling `scrollView` between checks.
/// Both `LayoutListView` and `LayoutDetailView` are plain SwiftUI `List`s
/// (`UICollectionView`-backed) tall enough that rows/sections below the
/// visible viewport are not yet composed — confirmed via the runtime
/// accessibility snapshot — so a bare `waitForExistence` can time out on
/// content that would render once scrolled into range. Shared by both page
/// objects below rather than duplicated per screen.
///
/// Hardened against the flake modes of the original swipe loop:
/// - Scroll steps are stationary press-drags between two in-list
///   coordinates, ending with zero deceleration — gesture geometry on a
///   located element (the documented exception AlternatesPopupUITests also
///   uses), not element location by coordinate. An inertial `swipeUp`
///   leaves the list decelerating, and a tap issued into that residual
///   motion is swallowed as a scroll-stop touch instead of activating.
/// - Never scrolls until the list exists and has composed at least one
///   cell (a generic `cells` query — the Section identifier-bleed breaks
///   identifier-prefix matches, see `row(labelContains:)`), so an empty or
///   mid-composition screen is never flung past the target.
/// - Spends the scroll budget on fast `exists` checks decoupled from
///   wall-clock, so inflated CI existence polls (issue #96) can't eat the
///   budget; `timeout` stays as the runaway backstop.
/// - Terminates on progress, not guesswork: the bottom-most composed cell
///   (identifier + frame) must be unchanged for two consecutive steps
///   before the downward scan counts as exhausted, then the same bounded
///   budget scans back toward the top and the loop keeps polling in place
///   until the deadline. `false` therefore always means the whole list was
///   scanned without a match — absence probes hold despite lazy
///   composition — and a near-top row overshot mid-composition is
///   recovered on the way back.
/// - Once any scroll step was issued, success additionally requires the
///   element to be hittable with an identical frame across two consecutive
///   snapshots, so a caller's immediate tap can't land on a still-settling
///   row. Found without scrolling returns immediately, unchanged from the
///   original happy path.
/// `maxSwipes` bounds each directional scan; `timeout` bounds how long the
/// whole reveal may take, so a generous caller deadline (`.postNavigation`,
/// issue #96) is never truncated by the scroll cap.
@MainActor
@discardableResult
func waitForRevealed(
    _ element: XCUIElement, scrollingIn scrollView: XCUIElement,
    timeout: TimeInterval, maxSwipes: Int = 6
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    var scrolled = false

    // Post-scroll settle gate: hittable, and a stable frame across two
    // consecutive snapshots (a short poll slice apart). Zero scroll steps
    // means the screen was never disturbed — success as-is.
    func settled() -> Bool {
        guard scrolled else { return true }
        var previousFrame: CGRect?
        while Date() < deadline {
            if element.exists, element.isHittable {
                let frame = element.frame
                if let previousFrame, frame == previousFrame { return true }
                previousFrame = frame
            } else {
                previousFrame = nil
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.exists
    }

    // One bounded directional scan. Each step is a deceleration-free
    // stationary press-drag; between steps only fast `exists` checks run,
    // so all `maxSwipes` steps execute even under issue-#96-scale poll
    // inflation. A two-strike stall counter on the edge-most composed cell
    // (nil samples never count) detects the end of the list.
    func scan(towardTop: Bool) -> Bool {
        var steps = 0
        var strikes = 0
        var previousEdge: (identifier: String, frame: CGRect)?
        while steps < maxSwipes, strikes < 2, Date() < deadline {
            scrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.25 : 0.75)
            ).press(
                forDuration: 0.05,
                thenDragTo: scrollView.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.75 : 0.25)))
            scrolled = true
            steps += 1
            if element.exists { return true }
            let cells = scrollView.cells.allElementsBoundByIndex
            if let edge = towardTop ? cells.first : cells.last {
                let sample = (identifier: edge.identifier, frame: edge.frame)
                if let previousEdge, previousEdge == sample {
                    strikes += 1
                } else {
                    strikes = 0
                }
                previousEdge = sample
            }
        }
        return element.exists
    }

    // Happy path first: one ~1s existence poll (capped by the remaining
    // budget) before any gesture — already-composed content returns here
    // at zero added cost over the original loop.
    if element.waitForExistence(timeout: min(1, max(0, deadline.timeIntervalSinceNow))) {
        return true
    }
    // Composition gate: never scroll an empty or still-composing list.
    while Date() < deadline, !(scrollView.exists && scrollView.cells.firstMatch.exists) {
        if element.exists { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    if element.exists { return true }

    // Scan down; on exhaustion without a match, recover back toward the top.
    if scan(towardTop: false) { return settled() }
    if scan(towardTop: true) { return settled() }

    // Both scans exhausted: the whole list has been traversed. Keep polling
    // in place until the deadline in case the element composes in late.
    while Date() < deadline {
        if element.waitForExistence(timeout: min(1, max(0, deadline.timeIntervalSinceNow))) {
            return settled()
        }
    }
    return element.exists
}

/// Which of the two candidate elements passed to `waitForEither` actually
/// appeared.
enum EitherOutcome {
    case first
    case second
}

/// Waits until `first` or `second` exists — whichever happens first —
/// polling both under one shared `timeout` deadline, for branch decisions
/// between two possible outcomes (e.g. "degraded-state alert" vs. "success").
/// A one-sided `waitForExistence` probe on a fixed window used to make this
/// call: on an overloaded runner the *other* branch's condition can still be
/// on its way when the probe's window expires, so the test falls into the
/// wrong branch instead of waiting for whichever outcome actually happened
/// (issue #99). Pass `.postNavigation` as `timeout` when this follows a
/// navigation event (cold launch, push, sheet/alert presentation). If
/// `second` lives in a lazily-composed scroll view (see `waitForRevealed`),
/// pass `scrollingSecondIn:` so it can be swiped into range while polling —
/// `first` (typically a system alert) is assumed reachable without
/// scrolling. Returns `nil` if neither appeared by the deadline.
@MainActor
func waitForEither(
    _ first: XCUIElement, _ second: XCUIElement,
    scrollingSecondIn scrollView: XCUIElement? = nil,
    timeout: TimeInterval, maxSwipes: Int = 6
) -> EitherOutcome? {
    let deadline = Date().addingTimeInterval(timeout)
    var swipes = 0
    while true {
        if first.exists { return .first }
        if second.exists { return .second }
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 { return nil }
        // Only swipe once the scroll view is actually there and interactable:
        // this helper can run right after launch (import flow) while the list
        // is still composing, and XCUITest gestures on a non-existent element
        // hard-fail rather than no-op. `isHittable` is false for a missing
        // element, so it covers both. Deferring the swipe never truncates the
        // deadline — the loop keeps polling both conditions in place.
        if let scrollView, swipes < maxSwipes, scrollView.isHittable {
            scrollView.swipeUp()
            swipes += 1
        }
        // Poll in short slices so neither condition can appear and sit
        // unnoticed until the next swipe.
        RunLoop.current.run(until: Date().addingTimeInterval(min(0.5, remaining)))
    }
}

// MARK: - LibraryScreen

/// Page object wrapping all XCUIElement queries for the root `LayoutListView`.
///
/// Accessibility identifiers sourced from `LayoutListView.swift`:
///   `layout-list`                   — the `List`
///   `layout-list-builtin-section`   — "Built-in" section header
///   `layout-list-user-section`      — "My Layouts" section header
///   `layout-row-<UUID>`             — each row (a Button inside the cell)
///   `layout-list-help-button`       — toolbar button reopening onboarding
///                                     guidance (see OnboardingScreen.swift)
///   `layout-list-active-preview`    — Active section's live keyboard preview
///   `layout-list-scratch`           — scratchpad text field (issue #103)
///   `layout-list-scratch-clear`     — clears the scratchpad (issue #103)
@MainActor
struct LibraryScreen {
    let app: XCUIApplication

    // MARK: Launch arguments (sourced from LayoutLibrary.swift)

    /// Clears every user layout and per-layout hidden-symbol/active-selection
    /// preference at launch, so fork/persistence tests start from a clean
    /// slate instead of self-healing via swipe-to-delete (issue #27).
    /// Matches `LayoutLibrary.resetLayoutsArgument`. When the App Group
    /// container is unavailable (every unsigned build today) only the layout
    /// deletion is skipped; the preferences reset still clears the app's
    /// fallback process-local defaults.
    static let resetLayoutsArgument = "--uitest-reset-layouts"

    // MARK: Navigation

    /// The "Layouts" navigation bar. First-class sentinel that the screen is
    /// presented — SwiftUI NavigationStack sets this from `.navigationTitle`.
    var navigationBar: XCUIElement {
        app.navigationBars["Layouts"]
    }

    // MARK: List

    /// The layout list. SwiftUI `List` renders as `UICollectionView` on iOS 16+,
    /// surfaced as `.collectionViews` in XCUITest.
    var layoutList: XCUIElement {
        app.collectionViews["layout-list"]
    }

    // MARK: Toolbar

    /// Toolbar button that (re)opens the "Enable the Keyboard" onboarding
    /// sheet on demand. Always present, regardless of first-run state.
    var helpButton: XCUIElement {
        app.buttons["layout-list-help-button"]
    }

    // MARK: Active section (preview + scratchpad, issues #103/#115)

    /// The Active section's live `KeyboardView` preview: one accessibility
    /// container element (`.accessibilityElement(children: .contain)` + the
    /// identifier, issue #25 — same pattern as `LayoutDetailScreen.preview`).
    /// Verified against the runtime accessibility snapshot (2026-07-04):
    /// exactly one `Other` element carries the identifier — the Section
    /// identifier-bleed described at `row(labelContains:)` doesn't reach it,
    /// because `LayoutListView` puts section identifiers on the header
    /// `Text`, never on the `Section`.
    var activePreview: XCUIElement {
        app.otherElements["layout-list-active-preview"]
    }

    /// The active-preview key that inserts `text`, by the kit's stable
    /// per-key scheme `key-insert-<text>` (exact IPA code points) — same
    /// contract as `LayoutDetailScreen.previewKey(inserting:)`. Scoped to
    /// the preview container, so a match also proves the key rendered
    /// *inside* the Active section's preview.
    func activePreviewKey(inserting text: String) -> XCUIElement {
        activePreview.descendants(matching: .any)["key-insert-\(text)"].firstMatch
    }

    /// The scratchpad under the active preview (issue #103). Surfaces as a
    /// `TextField` despite its `axis: .vertical` (confirmed via the runtime
    /// accessibility snapshot, 2026-07-04); its `value` is the typed text,
    /// or the placeholder while empty.
    var scratchField: XCUIElement {
        app.textFields["layout-list-scratch"]
    }

    /// Clears the scratchpad. Only rendered while the scratchpad has text —
    /// its existence doubles as the sync point that a typed key press has
    /// landed in the buffer.
    var scratchClearButton: XCUIElement {
        app.buttons["layout-list-scratch-clear"]
    }

    // MARK: Built-in row (stable identifier)

    /// Stable UUID for the English (US) General American built-in layout.
    /// Pinned in `en-US.json`; `UUID.uuidString` is always uppercase.
    static let englishUSLayoutID = "7E5A1C00-0000-4000-8000-00656E2D5553"

    /// The built-in English (US) row, located by its stable accessibility
    /// identifier (`layout-row-7E5A1C00-0000-4000-8000-00656E2D5553`).
    /// On the iOS 26 SDK a SwiftUI `NavigationLink` row surfaces as a
    /// `Button` inside the `Cell` — the identifier lands on the Button, so
    /// query `buttons`, not `cells`.
    var englishUSRow: XCUIElement {
        app.buttons["layout-row-\(LibraryScreen.englishUSLayoutID)"]
    }

    /// Waits for `englishUSRow` to exist *and* be hittable, then taps it.
    /// The row sits above the fold in portrait (Active section + first
    /// built-in), so no reveal scroll is needed — deliberately
    /// self-sufficient rather than depending on `waitForRevealed`. Both
    /// conditions are polled under the one shared deadline (an
    /// instantaneous hittability snapshot right after existence could catch
    /// the row mid-composition and fail a healthy screen). Returns `false`
    /// when the row never becomes tappable, so callers assert with their
    /// own message.
    ///
    /// After the tap, probes the detail screen's preview and re-taps once on
    /// a miss — the same silent-tap guard as `revealTapAndSettle`, which
    /// this helper predates. A hittable row's tap can still be swallowed
    /// with no scroll gesture ever issued (CI sighting 2026-07-05, PR #132:
    /// the tap landed, the push never happened, and the tearDown screenshot
    /// showed the library list untouched — most plausibly the tall Active
    /// section preview/scratchpad still composing and re-laying the list out
    /// under the touch). The caller's own `.postNavigation` first-wait on
    /// the destination supplies the full settling window.
    @discardableResult
    func openEnglishUS(timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !(englishUSRow.exists && englishUSRow.isHittable) {
            if Date() >= deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        englishUSRow.tap()
        // Push sentinel: `layout-detail-preview` exists only on the pushed
        // detail screen (the library's own preview is
        // `layout-list-active-preview`), so its appearance proves the
        // navigation happened. Only re-tap while the row is still there to
        // receive it: a vanished or covered row means the push is already
        // underway.
        let pushSentinel = app.otherElements["layout-detail-preview"]
        if pushSentinel.waitForExistence(timeout: 3) { return true }
        if englishUSRow.exists, englishUSRow.isHittable {
            englishUSRow.tap()
        }
        return true
    }

    // MARK: Convenience lookup

    /// Returns the first static text element whose label exactly matches `name`.
    /// Use alongside `englishUSRow` when you need a human-readable cross-check,
    /// or when the layout ID is not known in advance.
    func row(named name: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@", name)
        return app.staticTexts.matching(predicate).firstMatch
    }

    /// Taps a layout row (built-in or user) by a substring of its merged
    /// accessible label, working around a confirmed identifier regression:
    /// `.accessibilityIdentifier` applied to a `Section` in `LayoutListView`
    /// (`layout-list-builtin-section`, `layout-list-user-section`,
    /// `layout-list-active-section`) overrides the `identifier` of every
    /// descendant inside it — including each row's own `layout-row-<UUID>` —
    /// so `app.cells["layout-row-<UUID>"]` never matches. The row's `label`
    /// is unaffected: SwiftUI merges each `NavigationLink` row into a single
    /// `Button` accessibility element whose label concatenates its visible
    /// text, e.g. `"IPA — Full (QWERTY), und, Built-in, read-only"` or, once
    /// forked, `"IPA — Full (QWERTY) (Custom), und"`. Prefer a `name` that
    /// only one row's label could contain (e.g. the full layout name) — note
    /// the row for whichever layout is *active* also gets an `"Active, "`
    /// prefix, and its name additionally appears a second time (as plain
    /// text, not a `Button`) in the "Active" section preview above.
    func row(labelContains name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
    }

    /// Like `row(labelContains:)`, but requires the label to contain every
    /// string in `substrings`. Useful to disambiguate a built-in row (whose
    /// label always ends "..., Built-in, read-only") from a same-named fork
    /// of it (which drops that suffix) when both may be present — e.g. a
    /// leftover fork from a previous, non-hermetic test run.
    func row(labelContainsAll substrings: [String]) -> XCUIElement {
        let format = substrings.map { _ in "label CONTAINS[c] %@" }.joined(separator: " AND ")
        return app.buttons.matching(NSPredicate(format: format, argumentArray: substrings)).firstMatch
    }

    // MARK: Synchronised wait

    /// Blocks until the "Layouts" navigation bar is present, or `timeout`
    /// expires. Returns `true` when the screen is ready.
    @discardableResult
    func waitForContent(timeout: TimeInterval = 10) -> Bool {
        navigationBar.waitForExistence(timeout: timeout)
    }

    /// Returns the row located by `row(labelContains:)`, scrolling
    /// `layoutList` up first if needed (see `waitForRevealed`) — in
    /// particular, "My Layouts" entries can start below the visible
    /// viewport once the "Active" and "Built-in" sections have content.
    @discardableResult
    func waitForRow(labelContains name: String, timeout: TimeInterval = 10) -> XCUIElement {
        let element = row(labelContains: name)
        waitForRevealed(element, scrollingIn: layoutList, timeout: timeout)
        return element
    }

    /// Returns the row located by `row(labelContainsAll:)`, scrolling
    /// `layoutList` up first if needed (see `waitForRevealed`).
    @discardableResult
    func waitForRow(labelContainsAll substrings: [String], timeout: TimeInterval = 10) -> XCUIElement {
        let element = row(labelContainsAll: substrings)
        waitForRevealed(element, scrollingIn: layoutList, timeout: timeout)
        return element
    }

    // MARK: Open a row (reveal + tap + settle probe)

    /// Reveals the row matched by `row(labelContains:)`, taps it, and
    /// re-taps once if `pushSentinel` — an element that only exists on the
    /// destination screen — hasn't shown up after a short probe (see
    /// `revealTapAndSettle`). Returns `false` only when the row itself
    /// never revealed; the caller's own `.postNavigation` first-wait on the
    /// destination supplies the full navigation window.
    @discardableResult
    func openRow(
        labelContains name: String, pushSentinel: XCUIElement,
        timeout: TimeInterval = 10
    ) -> Bool {
        revealTapAndSettle(
            row(labelContains: name), scrollingIn: layoutList,
            pushSentinel: pushSentinel, timeout: timeout)
    }

    /// Like `openRow(labelContains:pushSentinel:timeout:)`, for rows
    /// located by `row(labelContainsAll:)`.
    @discardableResult
    func openRow(
        labelContainsAll substrings: [String], pushSentinel: XCUIElement,
        timeout: TimeInterval = 10
    ) -> Bool {
        revealTapAndSettle(
            row(labelContainsAll: substrings), scrollingIn: layoutList,
            pushSentinel: pushSentinel, timeout: timeout)
    }
}

// MARK: - Reveal + tap + settle probe

/// Reveals `element` in `scrollView` (see `waitForRevealed`), taps it, then
/// probes `pushSentinel` — an element that only exists on the destination
/// screen — for a few seconds and re-taps once on a miss. The single retry
/// covers the two ways a correctly-located tap can silently do nothing: it
/// was swallowed as a scroll-stop touch by residual list motion, or it was
/// invalidated by a system interruption. Deliberately does NOT wait out the
/// caller's full navigation deadline here: it returns as soon as the tap
/// has been (re)issued, and the caller's own `.postNavigation` first-wait
/// on the destination supplies the full settling window. Returns `false`
/// only when `element` itself never revealed.
@MainActor
@discardableResult
func revealTapAndSettle(
    _ element: XCUIElement, scrollingIn scrollView: XCUIElement,
    pushSentinel: XCUIElement, timeout: TimeInterval
) -> Bool {
    guard waitForRevealed(element, scrollingIn: scrollView, timeout: timeout) else {
        return false
    }
    element.tap()
    if pushSentinel.waitForExistence(timeout: 3) { return true }
    // The sentinel may legitimately still be composing (or sit below the
    // destination's fold — e.g. LayoutDetailScreen's action buttons), so
    // only re-tap while the tapped element is still there to receive it: a
    // vanished element means the push is already underway.
    if element.exists, element.isHittable {
        element.tap()
    }
    return true
}

// MARK: - LayoutDetailScreen

/// Page object wrapping XCUIElement queries for `LayoutDetailView`.
///
/// Accessibility identifiers sourced from `LayoutDetailView.swift`:
///   `layout-detail-preview`          — the live `KeyboardView` preview (one
///                                      accessibility container element,
///                                      issue #25)
///   `layout-detail-duplicate-button` — "Duplicate to Edit" (built-ins only)
///   `layout-detail-edit-keys-button` — "Edit Keys" (user layouts only, issue #6)
///   `layout-detail-delete-button`    — "Delete" (user layouts only)
@MainActor
struct LayoutDetailScreen {
    let app: XCUIApplication

    // MARK: Elements

    /// The live `KeyboardView` preview: exactly one accessibility container
    /// element (`.accessibilityElement(children: .contain)` + the identifier,
    /// issue #25). The keys inside remain individually accessible descendants
    /// — look them up with `previewKey(inserting:)`.
    var preview: XCUIElement {
        app.otherElements["layout-detail-preview"]
    }

    /// The preview key that inserts `text`, located by `KeyboardView`'s
    /// stable per-key identifier scheme — `key-insert-<text>`, where `<text>`
    /// is the exact inserted string (precise IPA code points; see the scheme
    /// doc on `Key.accessibilityIdentifier` in the kit's KeyboardView.swift).
    /// Scoped to the preview container, so a match also proves the key
    /// rendered *inside* the preview. Keyed by inserted text rather than
    /// spoken name so tests can assert what a key types; cross-check the
    /// spoken name via the returned element's `label`. The lookup is
    /// type-agnostic (`.any`) because keycaps with `.isKeyboardKey` aren't
    /// guaranteed to surface as `StaticText` across iOS versions.
    func previewKey(inserting text: String) -> XCUIElement {
        preview.descendants(matching: .any)["key-insert-\(text)"].firstMatch
    }

    /// "Duplicate to Edit" button, present for built-in layouts only.
    var duplicateButton: XCUIElement {
        app.buttons["layout-detail-duplicate-button"]
    }

    /// "Edit Keys" button, present for user layouts only (issue #6).
    var editKeysButton: XCUIElement {
        app.buttons["layout-detail-edit-keys-button"]
    }

    /// "Delete" button, present for user layouts only.
    var deleteButton: XCUIElement {
        app.buttons["layout-detail-delete-button"]
    }

    /// Back button that returns to the library.
    /// Label matches the parent NavigationStack title ("Layouts").
    var backButton: XCUIElement {
        app.navigationBars.buttons["Layouts"]
    }

    /// `LayoutDetailView`'s root `List` (no accessibilityIdentifier of its
    /// own — there is only ever one List on this screen, so a type query is
    /// the documented last-resort per project convention). Used to scroll
    /// the action section (Duplicate to Edit / Edit Keys / Delete) into view.
    private var list: XCUIElement {
        app.collectionViews.firstMatch
    }

    // MARK: Scrolling

    /// Reveals `element` by scrolling the detail List (see `waitForRevealed`
    /// — deceleration-free steps, settle gate, full-scan guarantee). Needed
    /// because SwiftUI lists are lazy: the action section ("Duplicate to
    /// Edit" / "Edit Keys" / "Delete") sits below the fold on iPhone-sized
    /// screens and is absent from the accessibility hierarchy until scrolled
    /// into view. Scrolls the List element itself, never the whole app — a
    /// whole-app swipe can land on the navigation bar and go nowhere.
    @discardableResult
    func scrollTo(_ element: XCUIElement, timeout: TimeInterval = 10, maxSwipes: Int = 4) -> Bool {
        waitForRevealed(element, scrollingIn: list, timeout: timeout, maxSwipes: maxSwipes)
    }

    // MARK: Synchronised wait

    /// Blocks until the "Duplicate to Edit" button appears (the sentinel for
    /// a built-in layout detail screen), scrolling the List up first if
    /// needed (see `waitForRevealed`) — `LayoutDetailView`'s List (metadata +
    /// a live keyboard preview + "Use this Layout" + "Customize symbols" all
    /// ahead of the action section) can be taller than one screen, confirmed
    /// via the runtime accessibility snapshot for "IPA — Full (QWERTY)"
    /// (whose preview has more rows than English (US)'s): the action section
    /// simply doesn't exist yet in the lazily-composed List until scrolled
    /// into the loaded range. Because the action section is the last section,
    /// success also implies the preview rendered; callers that only need the
    /// preview can wait on `preview` directly.
    @discardableResult
    func waitForContent(timeout: TimeInterval = 10) -> Bool {
        waitForRevealed(duplicateButton, scrollingIn: list, timeout: timeout)
    }

    /// Blocks until the "Edit Keys" button appears (the sentinel for a user
    /// layout detail screen, which has no "Duplicate to Edit"), scrolling if
    /// needed, or `timeout` expires.
    @discardableResult
    func waitForUserLayoutContent(timeout: TimeInterval = 10) -> Bool {
        waitForRevealed(editKeysButton, scrollingIn: list, timeout: timeout)
    }
}
