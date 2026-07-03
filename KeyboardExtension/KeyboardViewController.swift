//
//  KeyboardViewController.swift
//  KeyboardExtension
//
//  Created by Emma Haruka Iwao on 6/28/26.
//
//  Renders a bundled `KeyboardLayout` with the shared SwiftUI `KeyboardView`
//  and applies each emitted `KeyAction` to the document via the text proxy.
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

    override func viewDidLoad() {
        super.viewDidLoad()

        metrics = .metrics(forCompactHeight: traitCollection.verticalSizeClass == .compact)
        returnKeyType = textDocumentProxy.returnKeyType ?? .default
        applyProxyAppearance()

        let layout = displayLayout(loadLayout())
        renderedLayout = layout
        installKeyboard(for: layout)
        // Size to the tallest panel plus the shared bottom bar so switching
        // panels doesn't resize us. Derived from the fully-filtered layout, so
        // hiding symbols (which can drop rows) doesn't reserve blank height.
        applyHeight(forRowCount: layout.primaryArrangement?.totalRowCount ?? 0)

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
            rowCount: renderedLayout?.primaryArrangement?.totalRowCount ?? 0)
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
        return resolved.applyingHiddenSymbols(prefs.hiddenSymbols(for: resolved.id))
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
            nextKeyboardOverlay: globeOverlay
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
