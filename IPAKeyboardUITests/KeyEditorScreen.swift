//
//  KeyEditorScreen.swift
//  IPAKeyboardUITests
//
//  Page objects for the key-level layout editor (issue #6): the editor root
//  sheet (`LayoutKeyEditorView`), the row-of-keys screen (`KeyRowEditorView`),
//  and the single-key form (`KeyEditorForm`). Construct after navigating to
//  a user layout's "Edit Keys" flow (see `LayoutDetailScreen.editKeysButton`).
//
//  Conventions
//  -----------
//  - Elements located by accessibilityIdentifier first, label second,
//    type-query last — never by index or coordinate.
//  - Synchronisation via waitForExistence, not sleep.
//  - @MainActor struct keeps all element access on the main actor.
//  - List rows whose identifier is applied to a `NavigationLink` or `Button`
//    (not to an enclosing `Section`) render as a single `Button` accessibility
//    element carrying that identifier directly — confirmed via the runtime
//    accessibility snapshot, unaffected by the `LayoutListView` Section-bleed
//    regression documented in `LibraryScreen.row(labelContains:)` — so plain
//    `app.buttons[identifier]` lookups are reliable here.
//

import XCTest

// MARK: - LayoutKeyEditorScreen

/// Page object for the editor root sheet (`LayoutKeyEditorView`).
///
/// Accessibility identifiers sourced from `LayoutKeyEditorView.swift`:
///   `key-editor`                 — the root List
///   `key-editor-cancel`          — Cancel (confirms discard when dirty)
///   `key-editor-save`            — Save (disabled until there are changes)
///   `key-editor-preview`         — live draft preview (same identifier-bleed
///                                  caveat as `LayoutDetailScreen.preview`)
///   `key-editor-panel-picker`    — panel picker (only when >1 panel)
///   `key-editor-row-<index>`     — row link (0-based, within the shown panel)
///   `key-editor-add-row`         — appends an empty row
///   `key-editor-reset`           — reset content to the built-in source
///   `key-editor-reset-confirm`   — confirm button in the reset dialog
///   `key-editor-discard-confirm` — confirm button in the discard dialog
@MainActor
struct LayoutKeyEditorScreen {
    let app: XCUIApplication

    /// The "Edit Keys" navigation bar — sentinel that the sheet is presented.
    var navigationBar: XCUIElement {
        app.navigationBars["Edit Keys"]
    }

    var cancelButton: XCUIElement {
        app.buttons["key-editor-cancel"]
    }

    var saveButton: XCUIElement {
        app.buttons["key-editor-save"]
    }

    var addRowButton: XCUIElement {
        app.buttons["key-editor-add-row"]
    }

    var resetButton: XCUIElement {
        app.buttons["key-editor-reset"]
    }

    var resetConfirmButton: XCUIElement {
        app.buttons["key-editor-reset-confirm"]
    }

    var discardConfirmButton: XCUIElement {
        app.buttons["key-editor-discard-confirm"]
    }

    /// The root `List` (no accessibilityIdentifier of its own on the `List`
    /// itself — `key-editor` is applied to it in source, but per the same
    /// bleed pattern as `LayoutDetailScreen.preview` that identifier only
    /// resurfaces on descendant leaves, not a single container element; a
    /// type query is the reliable way to reach the scrollable List here).
    private var list: XCUIElement {
        app.collectionViews.firstMatch
    }

    /// The row link at `index` (0-based) within the currently shown panel.
    func row(at index: Int) -> XCUIElement {
        app.buttons["key-editor-row-\(index)"]
    }

    /// Returns `row(at: index)`, scrolling the List up first if needed (see
    /// `waitForRevealed`) — the preview section above the rows list can push
    /// later rows below the visible viewport on layouts with more content
    /// (e.g. "IPA — Full (QWERTY)"'s QWERTY panel).
    @discardableResult
    func waitForRow(at index: Int, timeout: TimeInterval = 10) -> XCUIElement {
        let element = row(at: index)
        waitForRevealed(element, scrollingIn: list, timeout: timeout)
        return element
    }

    /// Any rows-list entry whose summary shows it has no keys. A freshly
    /// appended row's merged label is "Row <n>, No keys yet", and every row
    /// of the bundled layouts ships with keys, so tests use this element as
    /// a *content* probe for whether a draft-added empty row exists (or
    /// wrongly persisted) — independent of Save-button state, which a fresh
    /// draft over a wrongly-saved document would report as unchanged.
    var emptyRow: XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "key-editor-row-", "No keys yet")).firstMatch
    }

    /// Returns `emptyRow`, scrolling the List up first if needed (see
    /// `waitForRevealed`) — an appended row lands at the bottom of the rows
    /// section, usually below the visible viewport. On timeout the returned
    /// element's `exists` is `false` *after* the whole list was swiped
    /// through, so this also supports asserting absence despite the List's
    /// lazy composition.
    @discardableResult
    func waitForEmptyRow(timeout: TimeInterval = 10) -> XCUIElement {
        let element = emptyRow
        waitForRevealed(element, scrollingIn: list, timeout: timeout)
        return element
    }

    /// Blocks until the "Edit Keys" navigation bar appears, or `timeout`
    /// expires. Returns `true` when the sheet is ready.
    @discardableResult
    func waitForContent(timeout: TimeInterval = 10) -> Bool {
        navigationBar.waitForExistence(timeout: timeout)
    }
}

// MARK: - KeyRowEditorScreen

/// Page object for the row-of-keys screen (`KeyRowEditorView`).
///
/// Accessibility identifiers sourced from `KeyRowEditorView.swift`:
///   `row-editor`             — the List
///   `row-editor-key-<index>` — tap to edit that key (0-based)
///   `row-editor-add-key`     — opens the form for a new key
@MainActor
struct KeyRowEditorScreen {
    let app: XCUIApplication

    var addKeyButton: XCUIElement {
        app.buttons["row-editor-add-key"]
    }

    /// The `List` of keys (type query — no accessibilityIdentifier on the
    /// `List` container itself). Used to scroll a later key into view.
    private var list: XCUIElement {
        app.collectionViews.firstMatch
    }

    /// The key row at `index` (0-based); tapping opens `KeyEditorForm`.
    func key(at index: Int) -> XCUIElement {
        app.buttons["row-editor-key-\(index)"]
    }

    /// Returns `key(at: index)`, scrolling the List up first if needed (see
    /// `waitForRevealed`) — rows with many keys (e.g. ipa-full.json's QWERTY
    /// row) can need scrolling to reach a later index.
    @discardableResult
    func waitForKey(at index: Int, timeout: TimeInterval = 10) -> XCUIElement {
        let element = key(at: index)
        waitForRevealed(element, scrollingIn: list, timeout: timeout)
        return element
    }

    /// Blocks until the "Row `number`" navigation bar appears, or `timeout`
    /// expires. `number` is 1-based, matching `KeyRowEditorView`'s title.
    @discardableResult
    func waitForContent(rowNumber number: Int, timeout: TimeInterval = 10) -> Bool {
        app.navigationBars["Row \(number)"].waitForExistence(timeout: timeout)
    }
}

// MARK: - KeyEditorFormScreen

/// Page object for the single-key form (`KeyEditorForm`).
///
/// Accessibility identifiers sourced from `KeyEditorForm.swift`:
///   `key-form-text`                — inserted-text field (insert keys only)
///   `key-form-unicode`             — code-point readout for the text field
///   `key-form-label`               — display-label field
///   `key-form-accessibility-label` — spoken-name (VoiceOver) field
///   `key-form-width-stepper`       — width stepper (0.25–5.0, step 0.25)
///   `key-form-add-alternate`       — appends an alternate
///   `key-form-done`                — commit ("Add" for a new key)
///   `key-form-cancel`              — discard
@MainActor
struct KeyEditorFormScreen {
    let app: XCUIApplication

    var insertTextField: XCUIElement {
        app.textFields["key-form-text"]
    }

    /// Code-point readout footer, e.g. "Code points: U+0071 U+02B0" — asserts
    /// exact Unicode scalars per the project's IPA-exactness convention.
    var unicodeReadout: XCUIElement {
        app.staticTexts["key-form-unicode"]
    }

    var labelField: XCUIElement {
        app.textFields["key-form-label"]
    }

    var accessibilityLabelField: XCUIElement {
        app.textFields["key-form-accessibility-label"]
    }

    var doneButton: XCUIElement {
        app.buttons["key-form-done"]
    }

    var cancelButton: XCUIElement {
        app.buttons["key-form-cancel"]
    }

    /// Replaces `field`'s current text with `text` by deleting every existing
    /// character (one `XCUIKeyboardKey.delete` per Unicode scalar) then
    /// typing the replacement, rather than select-all — deterministic
    /// regardless of platform text-selection UI, and never trims/normalizes
    /// the typed string so combining marks and multi-scalar IPA text (e.g.
    /// `q` + `ʰ`) round-trip exactly.
    func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        if let current = field.value as? String, !current.isEmpty {
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
            field.typeText(deletes)
        }
        field.typeText(text)
    }
}
