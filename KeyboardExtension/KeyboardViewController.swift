//
//  KeyboardViewController.swift
//  KeyboardExtension
//
//  Created by Emma Haruka Iwao on 6/28/26.
//
//  Renders a bundled `KeyboardLayout` with the shared SwiftUI `KeyboardView`
//  and applies each emitted `KeyAction` to the document via the text proxy.
//
//  Also holds the extension-runtime feedback glue: the input view's
//  `UIInputViewAudioFeedback` opt-in (system keyboard click) and the UIKit
//  globe-key overlay that gives the system-standard tap-to-switch plus
//  long-press input-mode picker. These live in this file because it is the
//  only file the project assigns to the extension target — the rest of the
//  `KeyboardExtension/` folder is synchronized into IPAKeyboardKit.
//

import SwiftUI
import UIKit
import IPAKeyboardKit

class KeyboardViewController: UIInputViewController {

    private let metrics = KeyboardMetrics()
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        let layout = displayLayout(loadLayout())
        installKeyboard(for: layout)
        // Size to the tallest panel plus the shared bottom bar so switching
        // panels doesn't resize us. Derived from the fully-filtered layout, so
        // hiding symbols (which can drop rows) doesn't reserve blank height.
        applyHeight(forRowCount: layout.primaryArrangement?.totalRowCount ?? 0)
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
        // Lay a UIKit control wired to `handleInputModeList(from:with:)` over
        // the globe keycap so the system provides both tap-to-switch and the
        // long-press keyboard picker. Skipped when the key isn't shown at all
        // (see `displayLayout`).
        let globeOverlay: AnyView? = needsInputModeSwitchKey
            ? AnyView(NextKeyboardKeyOverlay(controller: self))
            : nil
        let root = KeyboardView(
            layout: layout,
            metrics: metrics,
            nextKeyboardOverlay: globeOverlay
        ) { [weak self] action in
            self?.handle(action)
        }

        let host = UIHostingController(rootView: root)
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

// MARK: - Input click feedback

/// Opts the keyboard's input view into the standard system keyboard click.
/// `UIDevice.current.playInputClick()` — called by the shared `KeyboardView`
/// on key-down — only produces sound when the visible input view adopts
/// `UIInputViewAudioFeedback`; this conformance is that opt-in.
/// `UIInputViewController`'s root view is a `UIInputView`, so conforming the
/// class covers this extension. The system still honors the user's keyboard
/// sound setting, and no Full Access is required. The host app never adopts
/// the protocol, so the same `KeyboardView` stays silent in its previews.
extension UIInputView: @retroactive UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }
}

// MARK: - Globe key overlay

/// A UIKit control laid over the shared SwiftUI globe keycap. Wiring every
/// touch event to `handleInputModeList(from:with:)` hands the interaction to
/// the system, which provides both behaviors Apple expects of the globe key:
/// a quick tap advances to the next keyboard and a long-press presents the
/// input-mode picker. A SwiftUI gesture can't call `handleInputModeList`
/// correctly because the system needs the real `UIEvent` to distinguish tap
/// from hold and to anchor the picker.
struct NextKeyboardKeyOverlay: UIViewRepresentable {
    /// The extension's input view controller; weak because the controller
    /// owns the view hierarchy this button lives in.
    weak var controller: UIInputViewController?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIButton {
        let button = HighlightingKeyButton(type: .custom)
        button.backgroundColor = .clear
        button.layer.cornerRadius = 6
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        // The SwiftUI keycap underneath keeps the accessibility label
        // ("next keyboard") and keyboard-key trait; VoiceOver activation
        // synthesizes a touch that lands on this button.
        button.isAccessibilityElement = false
        if let controller {
            button.addTarget(
                controller,
                action: #selector(UIInputViewController.handleInputModeList(from:with:)),
                for: .allTouchEvents)
        }
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.playClick),
            for: .touchDown)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}

    @MainActor
    final class Coordinator: NSObject {
        /// Match the shared keycaps' key-down click (audible because the
        /// input view adopts `UIInputViewAudioFeedback`; still subject to
        /// the user's keyboard sound setting).
        @objc func playClick() {
            UIDevice.current.playInputClick()
        }
    }
}

/// Mirrors the SwiftUI keycaps' pressed-state highlight, since the UIKit
/// globe control swallows the touches the SwiftUI key would otherwise track.
private final class HighlightingKeyButton: UIButton {
    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted
                ? UIColor.label.withAlphaComponent(0.12)
                : .clear
        }
    }
}
