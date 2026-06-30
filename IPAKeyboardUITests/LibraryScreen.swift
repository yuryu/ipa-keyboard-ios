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

    /// The live `KeyboardView` preview container.
    var preview: XCUIElement {
        app.otherElements["layout-detail-preview"]
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

    // MARK: Synchronised wait

    /// Blocks until the "Duplicate to Edit" button appears (the sentinel for
    /// a built-in layout detail screen), or `timeout` expires.
    @discardableResult
    func waitForContent(timeout: TimeInterval = 10) -> Bool {
        duplicateButton.waitForExistence(timeout: timeout)
    }
}
