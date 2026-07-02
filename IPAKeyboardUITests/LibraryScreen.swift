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

/// Blocks until `element` exists, swiping `scrollView` up between checks.
/// Both `LayoutListView` and `LayoutDetailView` are plain SwiftUI `List`s
/// (`UICollectionView`-backed) tall enough that rows/sections below the
/// visible viewport are not yet composed — confirmed via the runtime
/// accessibility snapshot — so a bare `waitForExistence` can time out on
/// content that would render once scrolled into range. Shared by both page
/// objects below rather than duplicated per screen.
@MainActor
@discardableResult
func waitForRevealed(
    _ element: XCUIElement, scrollingIn scrollView: XCUIElement,
    timeout: TimeInterval, maxSwipes: Int = 6
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    var swipes = 0
    while !element.waitForExistence(timeout: 1) {
        if Date() >= deadline || swipes >= maxSwipes { return element.exists }
        scrollView.swipeUp()
        swipes += 1
    }
    return true
}

// MARK: - LibraryScreen

/// Page object wrapping all XCUIElement queries for the root `LayoutListView`.
///
/// Accessibility identifiers sourced from `LayoutListView.swift`:
///   `layout-list`                   — the `List`
///   `layout-list-builtin-section`   — "Built-in" section
///   `layout-list-user-section`      — "My Layouts" section
///   `layout-row-<UUID>`             — each row cell
@MainActor
struct LibraryScreen {
    let app: XCUIApplication

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

    // MARK: Built-in row (stable identifier)

    /// Stable UUID for the English (US) General American built-in layout.
    /// Pinned in `en-US.json`; `UUID.uuidString` is always uppercase.
    static let englishUSLayoutID = "7E5A1C00-0000-4000-8000-00656E2D5553"

    /// The built-in English (US) row, located by its stable accessibility
    /// identifier (`layout-row-7E5A1C00-0000-4000-8000-00656E2D5553`).
    var englishUSRow: XCUIElement {
        app.cells["layout-row-\(LibraryScreen.englishUSLayoutID)"]
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
}

// MARK: - LayoutDetailScreen

/// Page object wrapping XCUIElement queries for `LayoutDetailView`.
///
/// Accessibility identifiers sourced from `LayoutDetailView.swift`:
///   `layout-detail-preview`          — the live `KeyboardView` container
///   `layout-detail-duplicate-button` — "Duplicate to Edit" (built-ins only)
///   `layout-detail-edit-keys-button` — "Edit Keys" (user layouts only, issue #6)
///   `layout-detail-delete-button`    — "Delete" (user layouts only)
@MainActor
struct LayoutDetailScreen {
    let app: XCUIApplication

    // MARK: Elements

    /// The live `KeyboardView` preview area. `.accessibilityIdentifier(
    /// "layout-detail-preview")` is applied to the `KeyboardView` container,
    /// but (confirmed via the runtime accessibility snapshot) it bleeds down
    /// the same way the `LayoutListView` Section identifiers do: there is no
    /// single element carrying that identifier — instead *every rendered
    /// key* becomes its own `StaticText` with `identifier ==
    /// "layout-detail-preview"` and `label` equal to that key's spoken name
    /// (`key.accessibilityLabel ?? key.displayLabel`). So this resolves to
    /// the *first* such element (any match proves the preview rendered);
    /// use `previewElements(withLabel:)` to find one specific key.
    var preview: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "layout-detail-preview").firstMatch
    }

    /// All preview key elements whose spoken name (or, if a key sets no
    /// `accessibilityLabel`, its display glyph) exactly matches `label`.
    /// Use to confirm an edited key's new content actually rendered.
    func previewElements(withLabel label: String) -> XCUIElementQuery {
        app.staticTexts.matching(
            NSPredicate(format: "identifier == %@ AND label == %@", "layout-detail-preview", label))
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

    // MARK: Synchronised wait

    /// Blocks until the "Duplicate to Edit" button appears (the sentinel for
    /// a built-in layout detail screen), scrolling the List up first if
    /// needed (see `waitForRevealed`) — `LayoutDetailView`'s List (metadata +
    /// a live keyboard preview + "Use this Layout" + "Customize symbols" all
    /// ahead of the action section) can be taller than one screen, confirmed
    /// via the runtime accessibility snapshot for "IPA — Full (QWERTY)"
    /// (whose preview has more rows than English (US)'s): the action section
    /// simply doesn't exist yet in the lazily-composed List until scrolled
    /// into the loaded range.
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
