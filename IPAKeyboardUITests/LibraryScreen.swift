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

// MARK: - LibraryScreen

/// Page object wrapping all XCUIElement queries for the root `LayoutListView`.
///
/// Accessibility identifiers sourced from `LayoutListView.swift`:
///   `layout-list`                   — the `List`
///   `layout-list-builtin-section`   — "Built-in" section header
///   `layout-list-user-section`      — "My Layouts" section header
///   `layout-row-<UUID>`             — each row (a Button inside the cell)
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
    /// On the iOS 26 SDK a SwiftUI `NavigationLink` row surfaces as a
    /// `Button` inside the `Cell` — the identifier lands on the Button, so
    /// query `buttons`, not `cells`.
    var englishUSRow: XCUIElement {
        app.buttons["layout-row-\(LibraryScreen.englishUSLayoutID)"]
    }

    // MARK: Convenience lookup

    /// Returns the first static text element whose label exactly matches `name`.
    /// Use alongside `englishUSRow` when you need a human-readable cross-check,
    /// or when the layout ID is not known in advance.
    func row(named name: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@", name)
        return app.staticTexts.matching(predicate).firstMatch
    }

    // MARK: Synchronised wait

    /// Blocks until the "Layouts" navigation bar is present, or `timeout`
    /// expires. Returns `true` when the screen is ready.
    @discardableResult
    func waitForContent(timeout: TimeInterval = 10) -> Bool {
        navigationBar.waitForExistence(timeout: timeout)
    }
}

// MARK: - LayoutDetailScreen

/// Page object wrapping XCUIElement queries for `LayoutDetailView`.
///
/// Accessibility identifiers sourced from `LayoutDetailView.swift`:
///   `layout-detail-preview`          — the live `KeyboardView` container
///   `layout-detail-duplicate-button` — "Duplicate to Edit" (built-ins only)
///   `layout-detail-delete-button`    — "Delete" (user layouts only)
@MainActor
struct LayoutDetailScreen {
    let app: XCUIApplication

    // MARK: Elements

    /// The live `KeyboardView` preview. On the iOS 26 SDK the SwiftUI
    /// container is not itself an accessibility element — the identifier
    /// propagates to the key elements inside it — so match any element type
    /// and take the first hit.
    var preview: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "layout-detail-preview")
            .firstMatch
    }

    /// "Duplicate to Edit" button, present for built-in layouts only.
    var duplicateButton: XCUIElement {
        app.buttons["layout-detail-duplicate-button"]
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

    // MARK: Scrolling

    /// Scrolls the detail list until `element` exists, swiping up at most
    /// `maxSwipes` times. Needed because SwiftUI lists are lazy: the action
    /// section ("Duplicate to Edit" / "Delete") sits below the fold on
    /// iPhone-sized screens and is absent from the accessibility hierarchy
    /// until scrolled into view.
    @discardableResult
    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 4) -> Bool {
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.waitForExistence(timeout: 2)
    }

    // MARK: Synchronised wait

    /// Blocks until the keyboard preview appears (the sentinel that the
    /// detail screen is presented), or `timeout` expires. The action buttons
    /// are below the fold — use `scrollTo(_:)` before asserting on them.
    @discardableResult
    func waitForContent(timeout: TimeInterval = 10) -> Bool {
        preview.waitForExistence(timeout: timeout)
    }
}
