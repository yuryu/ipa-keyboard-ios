//
//  SymbolReferenceScreen.swift
//  IPAKeyboardUITests
//
//  Page object for the symbol reference sheet (issue #17): the searchable
//  inventory list opened from the layout library's toolbar, and the
//  per-symbol detail screen. Construct after app.launch() has returned.
//
//  Accessibility identifiers sourced from `SymbolReferenceView.swift`:
//    layout-list-symbol-reference-button — toolbar entry point (library)
//    symbol-reference-list           — the root List
//    symbol-reference-row-<text>     — each symbol row (exact inserted string)
//    symbol-reference-empty          — the no-search-results placeholder
//    symbol-reference-done           — toolbar Done button
//    symbol-reference-scratch        — the scratchpad text
//    symbol-detail-codepoint-<n>     — the n-th (0-based) "U+XXXX" readout
//    symbol-detail-copy              — copy button (label flips to "Copied")
//    symbol-detail-add-scratch       — add-to-scratchpad button
//
//  The search field has no custom identifier (SwiftUI `.searchable` doesn't
//  take one); it is matched as `app.searchFields.firstMatch` — the sheet is
//  the only searchable screen in the app. The field uses
//  `.navigationBarDrawer(displayMode: .always)`, so it is hittable without a
//  reveal swipe.
//
//  Conventions
//  -----------
//  - Elements located by accessibilityIdentifier first, label second,
//    type-query last — never by index or coordinate.
//  - Synchronisation via waitForExistence, not sleep.
//  - @MainActor struct keeps all element access on the main actor.
//  - Self-contained: no helpers shared with other page-object files, so
//    in-flight rewrites of those files cannot break this suite.
//

import XCTest

@MainActor
struct SymbolReferenceScreen {
    let app: XCUIApplication

    // MARK: Entry point (on the library screen)

    /// Toolbar button on `LayoutListView` that presents the reference sheet.
    var openButton: XCUIElement {
        app.buttons["layout-list-symbol-reference-button"]
    }

    // MARK: Reference list

    /// The root List. SwiftUI `List` renders as `UICollectionView` on
    /// iOS 16+, surfaced as `.collectionViews` in XCUITest.
    var list: XCUIElement {
        app.collectionViews["symbol-reference-list"]
    }

    /// The `.searchable` field (see the header comment on why a type query).
    var searchField: XCUIElement {
        app.searchFields.firstMatch
    }

    /// Toolbar Done button that dismisses the sheet.
    var doneButton: XCUIElement {
        app.buttons["symbol-reference-done"]
    }

    /// The placeholder shown when a search matches nothing. Identifier bleed
    /// on iOS 26 (see LibraryScreen's Section note) means the identifier may
    /// land on a descendant rather than one container, so match any type.
    var emptyState: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "symbol-reference-empty").firstMatch
    }

    /// A symbol's row, keyed by its exact inserted string (e.g. "ɡ" U+0261 —
    /// the identifier is built from the precise text, so look-alike glyphs
    /// have distinct rows). SwiftUI `NavigationLink` rows surface as
    /// `Button`s inside cells on the iOS 26 SDK — query `buttons`.
    func row(forSymbol text: String) -> XCUIElement {
        app.buttons["symbol-reference-row-\(text)"]
    }

    /// The scratchpad text on the reference's main screen (appears once a
    /// symbol has been added from a detail screen).
    var scratchpadText: XCUIElement {
        app.staticTexts["symbol-reference-scratch"]
    }

    // MARK: Detail screen

    /// The n-th (0-based) "U+XXXX" code-point readout on the detail screen.
    func codePointText(at ordinal: Int) -> XCUIElement {
        app.staticTexts["symbol-detail-codepoint-\(ordinal)"]
    }

    /// Copy button; its label flips from "Copy Symbol" to "Copied" (sticky —
    /// it does not auto-revert, so this is race-free to assert on).
    var copyButton: XCUIElement {
        app.buttons["symbol-detail-copy"]
    }

    /// Appends the symbol's exact text to the scratchpad.
    var addToScratchpadButton: XCUIElement {
        app.buttons["symbol-detail-add-scratch"]
    }

    /// Back button from the detail screen. UIKit labels it with the parent
    /// screen's title ("Symbol Reference") when it fits, or the generic
    /// "Back" when it doesn't — accept either rather than guessing which.
    /// The library's own toolbar entry is *also* labelled "Symbol Reference"
    /// and stays in the accessibility hierarchy under the sheet, so a bare
    /// label query is ambiguous — exclude it by its custom identifier.
    var backButton: XCUIElement {
        let byTitle = app.navigationBars.buttons.matching(
            NSPredicate(
                format: "label == %@ AND identifier != %@",
                "Symbol Reference", "layout-list-symbol-reference-button")
        ).firstMatch
        return byTitle.exists ? byTitle : app.navigationBars.buttons["Back"]
    }

    // MARK: Flows

    /// Opens the reference sheet from the library toolbar and waits for its
    /// list and search field. Returns false if any step doesn't appear.
    @discardableResult
    func open(timeout: TimeInterval = 10) -> Bool {
        guard openButton.waitForExistence(timeout: timeout) else { return false }
        openButton.tap()
        return list.waitForExistence(timeout: timeout)
            && searchField.waitForExistence(timeout: timeout)
    }

    /// Types `query` into the search field. Filtering is live — no submit
    /// keystroke needed. ASCII-only queries are used in tests because
    /// XCUITest's typeText cannot synthesize characters that have no
    /// hardware-keyboard equivalent (glyph *matching* itself is covered by
    /// the kit unit tests in SymbolInventoryTests).
    func search(_ query: String) {
        searchField.tap()
        searchField.typeText(query)
    }

    /// Waits for `element`, swiping the reference list up between checks —
    /// SwiftUI lists compose rows lazily, so a row below the fold does not
    /// exist until scrolled into range. Termination is progress-based, not
    /// wall-clock: the loop stops when a swipe reveals no new bottom row
    /// (the whole list has been traversed), so the reach scales with the
    /// inventory instead of failing when new bundled layouts grow it. The
    /// swipe cap is only a runaway backstop, sized well past the row count
    /// a full traversal of today's inventory needs.
    @discardableResult
    func waitForRevealed(_ element: XCUIElement, maxSwipes: Int = 40) -> Bool {
        var swipes = 0
        var previousBottomRow: String?
        while !element.waitForExistence(timeout: 1) {
            let bottomRow = lastVisibleRowIdentifier
            let stalled = bottomRow != nil && bottomRow == previousBottomRow
            if stalled || swipes >= maxSwipes { return element.exists }
            previousBottomRow = bottomRow
            list.swipeUp()
            swipes += 1
        }
        return true
    }

    /// Identifier of the bottom-most composed symbol row, used by
    /// `waitForRevealed` to detect that swiping stopped making progress.
    private var lastVisibleRowIdentifier: String? {
        list.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "symbol-reference-row-")
        ).allElementsBoundByIndex.last?.identifier
    }
}
