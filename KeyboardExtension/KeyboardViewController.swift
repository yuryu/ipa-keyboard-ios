//
//  KeyboardViewController.swift
//  KeyboardExtension
//
//  Created by Emma Haruka Iwao on 6/28/26.
//
//  Renders a bundled `KeyboardLayout` with the shared SwiftUI `KeyboardView`
//  and applies each emitted `KeyAction` to the document via the text proxy.
//

import SwiftUI
import UIKit
import IPAKeyboardKit

class KeyboardViewController: UIInputViewController {

    private let metrics = KeyboardMetrics()
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        let layout = loadLayout()
        installKeyboard(for: layout)
        // Size to the tallest panel plus the shared bottom bar so switching
        // panels doesn't resize us.
        applyHeight(forRowCount: layout.primaryArrangement?.totalRowCount ?? 0)
    }

    // MARK: Layout loading

    /// The layout to render. For the render-spine step we pin to the `en-US`
    /// bundled default (any bundled layout as a backstop); arrangement/
    /// selection comes later in the roadmap. Falls back to a minimal safe
    /// layout so the keyboard never renders blank.
    private func loadLayout() -> KeyboardLayout {
        let bundled = LayoutStore().bundledLayouts()
        if let layout = bundled.first(where: { $0.locale == "en-US" }) ?? bundled.first {
            return layout
        }
        return KeyboardLayout(
            name: "Fallback",
            locale: "en-US",
            rows: [KeyRow(keys: [
                .insert("ə"),
                Key(action: .space, label: "space", widthFactor: 3.0),
                Key(action: .backspace, label: "⌫", widthFactor: 1.5),
            ])]
        )
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
        let root = KeyboardView(layout: displayLayout(layout), metrics: metrics) { [weak self] action in
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
