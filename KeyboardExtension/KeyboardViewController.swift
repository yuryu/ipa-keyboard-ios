//
//  KeyboardViewController.swift
//  KeyboardExtension
//
//  Created by Emma Haruka Iwao on 6/28/26.
//
//  Renders a bundled `KeyboardLayout` with the shared SwiftUI `KeyboardView`
//  and applies each emitted `KeyAction` to the document via the text proxy;
//  the space bar's trackpad-style cursor session arrives through the
//  separate `onCursorMove` callback and becomes grapheme-aware
//  `adjustTextPosition` offsets computed against a per-drag context mirror
//  (`CursorMovement.Context`).
//
//  The extension-runtime feedback glue lives alongside in this target:
//  `InputClickFeedback.swift` (the input view's `UIInputViewAudioFeedback`
//  opt-in for the system keyboard click) and `NextKeyboardKeyOverlay.swift`
//  (the UIKit globe-key overlay giving system-standard tap-to-switch plus
//  the long-press input-mode picker).
//

import SwiftUI
import UIKit
import IPAKeyboardKit

class KeyboardViewController: UIInputViewController {

    /// Sizing for the current environment: the regular set in portrait/iPad,
    /// the shorter compact set in iPhone landscape (kept in sync with the
    /// vertical size class via the trait-change registration below).
    private var metrics = KeyboardMetrics()
    private var heightConstraint: NSLayoutConstraint?
    /// The rendered (already filtered) layout, kept so the root view can be
    /// rebuilt when the metrics or return-key type change.
    private var renderedLayout: KeyboardLayout?
    private var hostingController: UIHostingController<KeyboardView>?
    /// The host field's return-key type as last rendered; `.return` keycaps
    /// are relabeled (Go/Search/Done…) to match, like the system keyboard.
    private var returnKeyType: UIReturnKeyType = .default
    /// Backs the recently-used-symbols strip (issue #16): the shared
    /// SwiftUI `KeyboardView` records every inserted symbol here and renders
    /// the strip from it. Persists through the App Group `UserDefaults` suite
    /// (no Full Access required), degrading to process-local storage before
    /// provisioning — the same story as `KeyboardPreferences`.
    private let recentSymbolsStore = RecentSymbolsStore()
    /// Symbols hidden for the active layout, captured when the layout is
    /// resolved so the recents strip can filter them out even though they are
    /// already gone from the rendered `renderedLayout`.
    private var hiddenSymbols: Set<String> = []

    override func viewDidLoad() {
        super.viewDidLoad()

        metrics = .metrics(forCompactHeight: traitCollection.verticalSizeClass == .compact)
        returnKeyType = textDocumentProxy.returnKeyType ?? .default
        applyProxyAppearance()

        let layout = displayLayout(loadLayout())
        renderedLayout = layout
        installKeyboard(for: layout)
        // Size to the tallest panel plus the shared bottom bar, plus the
        // always-present recents row, so neither switching panels nor recents
        // populating resizes us. Derived from the fully-filtered layout, so
        // hiding symbols (which can drop rows) doesn't reserve blank height.
        applyHeight(forRowCount: renderedRowCount(for: layout))

        // Rotation moves iPhones between regular and compact vertical size
        // classes; re-derive the metrics (and the height constraint) so the
        // landscape keyboard is shorter, like the system keyboard.
        registerForTraitChanges([UITraitVerticalSizeClass.self]) {
            (self: KeyboardViewController, _: UITraitCollection) in
            self.verticalSizeClassDidChange()
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Moving between fields (or apps) can change both the requested
        // appearance and the return-key type without relaunching us.
        applyProxyAppearance()
        let type = textDocumentProxy.returnKeyType ?? .default
        if type != returnKeyType {
            returnKeyType = type
            refreshRootView()
        }
    }

    // MARK: Appearance

    /// Match the host field's requested keyboard appearance: overriding the
    /// input view's interface style makes the `UIInputView` material and every
    /// dynamic color in the shared `KeyboardView` resolve dark or light, so a
    /// dark text field gets a dark keyboard even inside a light-mode app.
    /// `.default` defers to the ambient trait (system light/dark mode).
    private func applyProxyAppearance() {
        let style: UIUserInterfaceStyle
        switch textDocumentProxy.keyboardAppearance ?? .default {
        case .dark:
            style = .dark
        case .light:
            style = .light
        default:
            style = .unspecified
        }
        // textDidChange calls this per keystroke; skip the (rarely changing)
        // assignment when it's a no-op so we don't kick off trait propagation
        // through the whole hierarchy on every key press.
        guard view.overrideUserInterfaceStyle != style else { return }
        view.overrideUserInterfaceStyle = style
    }

    private func verticalSizeClassDidChange() {
        let updated = KeyboardMetrics.metrics(
            forCompactHeight: traitCollection.verticalSizeClass == .compact)
        guard updated != metrics else { return }
        metrics = updated
        refreshRootView()
        heightConstraint?.constant = metrics.totalHeight(
            rowCount: renderedLayout.map(renderedRowCount(for:)) ?? 0)
    }

    /// Total rendered rows for `layout`: its tallest panel plus bottom bar,
    /// plus the recents strip the shared `KeyboardView` always reserves
    /// (issue #16). The single place the extension adds the recents row to the
    /// height, kept in step with `KeyboardView.reservedRowCount`.
    private func renderedRowCount(for layout: KeyboardLayout) -> Int {
        (layout.primaryArrangement?.totalRowCount ?? 0) + KeyboardMetrics.recentsRowCount
    }

    // MARK: Layout loading

    /// The layout to render: the user's active selection (from the shared
    /// `KeyboardPreferences`) resolved against all available layouts, with that
    /// layout's hidden symbols applied. Falls back `en-US` → first → a minimal
    /// safe layout so it's never blank. Read once at `viewDidLoad`; the extension
    /// is relaunched fresh each time, so a selection or curation change takes
    /// effect on the next keyboard appearance. (Until the App Group is
    /// provisioned the preferences are process-local, so this resolves to the
    /// bundled default on device today.)
    private func loadLayout() -> KeyboardLayout {
        let prefs = KeyboardPreferences()
        let resolved = ActiveLayoutResolver.resolve(
            activeID: prefs.activeLayoutID, in: LayoutStore().allLayouts())
        // Kept so the recents strip can filter curated-away symbols out even
        // though they are already absent from the rendered layout.
        hiddenSymbols = prefs.hiddenSymbols(for: resolved.id)
        return resolved.applyingHiddenSymbols(hiddenSymbols)
    }

    /// Hide the globe key when the host doesn't need a keyboard-switch key
    /// (e.g. when this is the only keyboard installed). `needsInputModeSwitchKey`
    /// is read at install time; it's stable for the lifetime of the view.
    private func displayLayout(_ layout: KeyboardLayout) -> KeyboardLayout {
        guard !needsInputModeSwitchKey else { return layout }
        return layout.filteringKeys { $0.action == .nextKeyboard }
    }

    // MARK: View installation

    private func installKeyboard(for layout: KeyboardLayout) {
        let host = UIHostingController(rootView: makeRootView(for: layout))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    /// The shared SwiftUI keyboard for the current metrics and return-key
    /// type. Rebuilt (cheaply — it's a value) whenever either changes.
    private func makeRootView(for layout: KeyboardLayout) -> KeyboardView {
        // Lay a UIKit control wired to `handleInputModeList(from:with:)` over
        // the globe keycap so the system provides both tap-to-switch and the
        // long-press keyboard picker. Skipped when the key isn't shown at all
        // (see `displayLayout`).
        let globeOverlay: AnyView? = needsInputModeSwitchKey
            ? AnyView(NextKeyboardKeyOverlay(controller: self))
            : nil
        return KeyboardView(
            layout: layout,
            metrics: metrics,
            returnKeyType: returnKeyType,
            nextKeyboardOverlay: globeOverlay,
            recentSymbolsStore: recentSymbolsStore,
            hiddenSymbols: hiddenSymbols,
            onCursorMove: { [weak self] event in
                self?.handleCursorMove(event)
            }
        ) { [weak self] action in
            self?.handle(action)
        }
    }

    /// Re-render in place after a metrics or return-key-type change.
    private func refreshRootView() {
        guard let renderedLayout, let hostingController else { return }
        hostingController.rootView = makeRootView(for: renderedLayout)
    }

    private func applyHeight(forRowCount rowCount: Int) {
        let constraint = view.heightAnchor.constraint(
            equalToConstant: metrics.totalHeight(rowCount: rowCount))
        // Below required so the system can still resize during rotation/setup
        // instead of producing unsatisfiable-constraint warnings.
        constraint.priority = .defaultHigh
        constraint.isActive = true
        heightConstraint = constraint
    }

    // MARK: Action handling

    private func handle(_ action: KeyAction) {
        let proxy = textDocumentProxy
        switch action {
        case .insert(let text):
            proxy.insertText(text)
        case .space:
            proxy.insertText(" ")
        case .return:
            proxy.insertText("\n")
        case .backspace:
            deleteBackwardGraphemeAware(proxy)
        case .nextKeyboard:
            // Normally unreachable here: the globe keycap is covered by
            // `NextKeyboardKeyOverlay`, which routes touches to the system.
            // Kept as a safety net for a layout rendered without the overlay.
            advanceToNextInputMode()
        case .switchPanel, .spacer:
            // Never emitted to the host: KeyboardView consumes switchPanel
            // internally when flipping panels, and spacer keys are inert.
            break
        @unknown default:
            break
        }
    }

    /// Local mirror of the document context for the duration of one
    /// space-bar cursor drag; nil between drags. `adjustTextPosition` round-
    /// trips to the host and the proxy's context windows update
    /// asynchronously, so re-reading `documentContextBeforeInput`/
    /// `AfterInput` per step during a sustained drag (one step per touch
    /// sample, milliseconds apart) can compute step N+1 from pre-step-N
    /// context and park the cursor inside a combining sequence. The mirror
    /// is seeded once at `.began` — after the 0.3 s stationary hold, so the
    /// document has been quiet and the windows are settled — and advanced
    /// locally per step (see `CursorMovement.Context`).
    private var cursorContext: CursorMovement.Context?

    /// Apply the space bar's trackpad-style cursor session (issue #70):
    /// snapshot the settled context when cursor mode engages, then move the
    /// insertion point by whole user-perceived characters per step —
    /// `adjustTextPosition(byCharacterOffset:)` counts UTF-16 code units,
    /// not grapheme clusters, so each offset sums the code units of the
    /// clusters being traversed, mirroring grapheme-aware deletion.
    private func handleCursorMove(_ event: CursorMoveEvent) {
        switch event {
        case .began:
            cursorContext = CursorMovement.Context(
                contextBefore: textDocumentProxy.documentContextBeforeInput,
                contextAfter: textDocumentProxy.documentContextAfterInput)
        case .moved(let steps):
            // `.began` always precedes `.moved`; the fallback only covers a
            // hypothetical dropped event, accepting one possibly-unsettled
            // read rather than a dead drag.
            var context = cursorContext ?? CursorMovement.Context(
                contextBefore: textDocumentProxy.documentContextBeforeInput,
                contextAfter: textDocumentProxy.documentContextAfterInput)
            let offset = context.utf16Offset(steps: steps)
            cursorContext = context
            guard offset != 0 else { return }
            textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        case .ended:
            cursorContext = nil
        @unknown default:
            break
        }
    }

    /// Delete one user-perceived character. Combining diacritics and other
    /// multi-scalar clusters are removed as a unit so a length/tone mark
    /// vanishes with its base glyph in a single backspace.
    private func deleteBackwardGraphemeAware(_ proxy: UITextDocumentProxy) {
        guard let context = proxy.documentContextBeforeInput else {
            proxy.deleteBackward()
            return
        }
        let count = max(GraphemeText.deletionScalarCount(before: context), 1)
        for _ in 0..<count {
            proxy.deleteBackward()
        }
    }
}
