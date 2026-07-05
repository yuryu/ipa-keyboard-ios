//
//  KeyboardView.swift
//  IPAKeyboardKit
//
//  The SwiftUI rendering of a `KeyboardLayout`. This view is intentionally
//  decoupled from the keyboard extension runtime: it emits `KeyAction`
//  values through `onAction` rather than touching `UITextDocumentProxy`, so
//  the same view renders inside the extension today and inside the host
//  app's editor/preview later.
//
//  Layout rule (roadmap): one screen, no horizontal scrolling. Each row
//  independently fills the available width, with per-key widths derived
//  from `Key.widthFactor`.
//
//  Key feedback: keycaps highlight while pressed and play the system input
//  click on key-down (`UIDevice.playInputClick()` is a no-op unless the
//  active input view adopts `UIInputViewAudioFeedback`, so host previews
//  stay silent); on iPhone, pressed insert keys also show a magnified
//  preview balloon (`KeyPreviewBalloon`, placed by the unit-tested
//  `KeyPreviewPlacement`) that stays inside the keyboard's bounds.
//  Backspace acts on key-down and autorepeats while held, timed by the
//  unit-tested `KeyRepeatCadence`. Keys with alternates use the system
//  keyboard's hold-slide-release interaction: the popup opens after a
//  0.3 s hold, floats above the pressed key on every row (placed by the
//  unit-tested `AlternatesPopupPlacement`, clamped in-frame like the
//  balloon and raised in z-order over neighboring keys and rows), tracks
//  the sliding finger (hit-testing in the unit-tested
//  `AlternatesSelection`), and always closes on release. The space bar
//  doubles as a trackpad (issue #70): the same hold enters cursor mode and
//  a horizontal drag emits `CursorMoveEvent`s through `onCursorMove` —
//  `began` on the completed hold, `moved(steps:)` per crossed grid cell
//  (quantized by the unit-tested `CursorDragStepper`), `ended` on release;
//  the extension turns the session into grapheme-aware `adjustTextPosition`
//  offsets, while the host previews
//  leave the callback a no-op. The extension can
//  overlay the globe keycap with a UIKit control (`nextKeyboardOverlay`)
//  so the system drives keyboard switching, including the long-press
//  picker.
//

import SwiftUI
import UIKit

/// Sizing constants for the rendered keyboard, shared so the hosting
/// controller can compute the keyboard's overall height from the same
/// numbers the view lays out with.
public struct KeyboardMetrics: Sendable {
    public var rowHeight: CGFloat
    public var rowSpacing: CGFloat
    public var keySpacing: CGFloat
    public var outerPadding: CGFloat

    public init(
        rowHeight: CGFloat = 50,
        rowSpacing: CGFloat = 8,
        keySpacing: CGFloat = 6,
        outerPadding: CGFloat = 4
    ) {
        self.rowHeight = rowHeight
        self.rowSpacing = rowSpacing
        self.keySpacing = keySpacing
        self.outerPadding = outerPadding
    }

    /// Height of just the rows area for `rowCount` rows — inter-row spacing
    /// included, outer padding excluded. The single formula the view and the
    /// hosting controller both build their heights from.
    public func contentHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * rowHeight
            + CGFloat(rowCount - 1) * rowSpacing
    }

    /// Total height the keyboard wants for `rowCount` rows, including
    /// inter-row spacing and outer padding.
    public func totalHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return contentHeight(rowCount: rowCount) + outerPadding * 2
    }

    /// Height for a whole arrangement: sized to its tallest panel plus the
    /// shared bottom bar, so switching panels keeps the keyboard a constant
    /// height (like the system `123`/`#+=`).
    public func totalHeight(for arrangement: Arrangement?) -> CGFloat {
        totalHeight(rowCount: arrangement?.totalRowCount ?? 0)
    }
}

extension KeyboardMetrics: Equatable {}

public extension KeyboardMetrics {
    /// Shorter rows for compact-height environments (iPhone landscape),
    /// mirroring the system keyboard, which drops to roughly two-thirds of
    /// its portrait height there. A 5-row bundled layout renders ~196 pt —
    /// close to the system landscape keyboard — instead of 290 pt.
    static let compactHeight = KeyboardMetrics(
        rowHeight: 34, rowSpacing: 5, keySpacing: 6, outerPadding: 3)

    /// The metrics for an environment: the default set, or the shorter
    /// `compactHeight` set when the vertical size class is compact. The
    /// extension (UIKit traits) and the host previews (SwiftUI environment)
    /// both key off this so their heights always agree.
    static func metrics(forCompactHeight isCompact: Bool) -> KeyboardMetrics {
        isCompact ? .compactHeight : KeyboardMetrics()
    }
}

extension Key {
    /// Stable accessibility identifier for this key, for XCUITest lookups.
    /// Derived from the key's *action* — not its `id`, which is regenerated
    /// whenever a layout document omits it — so it is stable across symbol
    /// curation, panel switches, and re-decoding. Naming scheme:
    ///
    ///     insert        → "key-insert-<text>"        e.g. "key-insert-ə"
    ///     backspace     → "key-backspace"
    ///     space         → "key-space"
    ///     return        → "key-return"
    ///     nextKeyboard  → "key-nextKeyboard"
    ///     switchPanel   → "key-switchPanel-<target>" e.g. "key-switchPanel-More"
    ///
    /// `<text>` is the exact inserted string (precise IPA code points, e.g.
    /// `ɡ` U+0261), not the display label — so tests can assert what a key
    /// *types*, not just its spoken name. Duplicate identifiers can coexist
    /// (only one panel renders at a time, and the long-press alternates popup
    /// reuses the same scheme for its keys); `.spacer` never renders an
    /// accessibility element, so its value is defined only for totality.
    var accessibilityIdentifier: String {
        switch action {
        case .insert(let text): return "key-insert-\(text)"
        case .backspace: return "key-backspace"
        case .space: return "key-space"
        case .return: return "key-return"
        case .nextKeyboard: return "key-nextKeyboard"
        case .switchPanel(let target): return "key-switchPanel-\(target)"
        case .spacer: return "key-spacer"
        }
    }
}

public struct KeyboardView: View {
    private let layout: KeyboardLayout
    private let metrics: KeyboardMetrics
    private let returnKeyType: UIReturnKeyType
    private let nextKeyboardOverlay: AnyView?
    private let onCursorMove: (CursorMoveEvent) -> Void
    private let onAction: (KeyAction) -> Void

    /// Name of the panel currently shown within the primary arrangement.
    /// `nil` falls back to the primary panel. Panel-switch keys update this
    /// in place; the action never escapes to the host document.
    @State private var activePanelName: String?

    /// Row containing the currently open alternates popup, raised above its
    /// sibling rows (`zIndex`) so a popup clamped into another row's area —
    /// the top row's, which has no headroom above and overlaps downward —
    /// draws in front of that row's keys instead of behind them (issue #122).
    @State private var popupRowID: UUID?

    /// The keyboard's rendered size — the bounds the alternates popup's
    /// placement clamps against.
    @State private var keyboardSize: CGSize = .zero

    /// Name of the coordinate space covering the whole keyboard (declared on
    /// the same frame the key-preview overlay measures against), so pressed
    /// keys can resolve their cap frames in keyboard coordinates for the
    /// alternates popup's placement.
    fileprivate static let keyboardSpaceName = "IPAKeyboardBounds"
    fileprivate static var keyboardSpace: NamedCoordinateSpace {
        .named(keyboardSpaceName)
    }

    /// - Parameter returnKeyType: the host field's return-key type; `.return`
    ///   keys are relabeled to match (Go/Search/Done…) and tinted for the
    ///   non-default types, like the system keyboard. The extension passes
    ///   `textDocumentProxy.returnKeyType`; the host previews keep the
    ///   default, which renders a plain "return".
    /// - Parameter nextKeyboardOverlay: an optional UIKit control the
    ///   keyboard extension lays over every `.nextKeyboard` keycap so the
    ///   system handles switching (tap advances; long-press shows the
    ///   input-mode list). nil — the host app and previews — leaves the plain
    ///   SwiftUI key, whose tap emits `KeyAction.nextKeyboard`.
    /// - Parameter onCursorMove: receives the space bar's trackpad-style
    ///   cursor session — `began` when the hold completes, `moved(steps:)`
    ///   (positive right, negative left) while it is dragged, `ended` on
    ///   release. A renderer-level event like panel switching — deliberately
    ///   not a `KeyAction`, which is the persisted layout schema. The
    ///   extension snapshots the document context at `began` and maps steps
    ///   to `adjustTextPosition` offsets via `CursorMovement.Context`; the
    ///   default no-op keeps host previews inert while rendering the
    ///   identical interaction.
    public init(
        layout: KeyboardLayout,
        metrics: KeyboardMetrics = KeyboardMetrics(),
        returnKeyType: UIReturnKeyType = .default,
        nextKeyboardOverlay: AnyView? = nil,
        onCursorMove: @escaping (CursorMoveEvent) -> Void = { _ in },
        onAction: @escaping (KeyAction) -> Void
    ) {
        self.layout = layout
        self.metrics = metrics
        self.returnKeyType = returnKeyType
        self.nextKeyboardOverlay = nextKeyboardOverlay
        self.onCursorMove = onCursorMove
        self.onAction = onAction
    }

    private var arrangement: Arrangement? { layout.primaryArrangement }
    private var activePanel: Panel? { arrangement?.panel(named: activePanelName) }
    private var symbolRows: [KeyRow] { activePanel?.rows ?? [] }

    /// The pinned bottom bar: the active panel's switch key (if any) followed by
    /// the arrangement's shared function row. nil when neither is present.
    private var bottomBar: KeyRow? {
        let keys = (activePanel?.switchKey.map { [$0] } ?? []) + (arrangement?.functionRow?.keys ?? [])
        return keys.isEmpty ? nil : KeyRow(keys: keys)
    }

    /// Shared grid basis for rows that contain a `spacer`: the largest total
    /// `widthFactor` (spacers counted, default 1.0 each) across all rendered
    /// rows. Grouped keys are sized off this so they match the densest row, and
    /// because the spacer's own factor is included, a full grouped row still
    /// reserves a gap rather than collapsing it.
    private var gridReferenceFactor: Double {
        (symbolRows + (bottomBar.map { [$0] } ?? []))
            .map { row in row.keys.reduce(0.0) { $0 + $1.widthFactor } }
            .max() ?? 0
    }

    public var body: some View {
        let reference = gridReferenceFactor
        // Outer stack has no spacing of its own; the gap between the symbol rows
        // and the pinned bottom bar is an explicit Spacer whose minimum equals a
        // normal row gap. That keeps the natural height exactly
        // `contentHeight(totalRowCount)` for the tallest panel (one extra row for
        // the bar) and lets the Spacer grow — pinning the bar to the bottom —
        // for shorter panels.
        VStack(spacing: 0) {
            VStack(spacing: metrics.rowSpacing) {
                ForEach(symbolRows) { row in
                    KeyRowView(
                        row: row,
                        metrics: metrics,
                        gridReferenceFactor: reference,
                        keyboardSize: keyboardSize,
                        returnKeyType: returnKeyType,
                        nextKeyboardOverlay: nextKeyboardOverlay,
                        onCursorMove: onCursorMove,
                        onAction: handle,
                        onPopupChange: { popupChanged(rowID: row.id, isOpen: $0) })
                        // The row with the open popup draws above its
                        // siblings: a top-row popup — clamped down into the
                        // next row's area — must cover that row's keys, not
                        // hide behind them (issue #122).
                        .zIndex(row.id == popupRowID ? 1 : 0)
                }
            }
            if let bottomBar {
                Spacer(minLength: metrics.rowSpacing)
                KeyRowView(
                    row: bottomBar,
                    metrics: metrics,
                    gridReferenceFactor: reference,
                    keyboardSize: keyboardSize,
                    returnKeyType: returnKeyType,
                    nextKeyboardOverlay: nextKeyboardOverlay,
                    onCursorMove: onCursorMove,
                    onAction: handle,
                    // A later sibling of the symbol rows' stack, so its
                    // popup — floating up over the last symbol row — already
                    // draws in front; no z-order bookkeeping needed.
                    onPopupChange: { _ in })
            }
        }
        .padding(metrics.outerPadding)
        // Reserve the arrangement's tallest-panel + bottom-bar height so
        // switching panels doesn't change the keyboard's size. Matches the
        // controller's height constraint (both via `metrics.totalHeight`).
        .frame(maxWidth: .infinity, minHeight: metrics.totalHeight(for: arrangement), alignment: .top)
        // Name the keyboard's full bounds and record their rendered size:
        // pressed keys measure their cap frames in this space and clamp
        // their alternates popups against the size (`AlternatesPopupPlacement`).
        .coordinateSpace(Self.keyboardSpace)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            keyboardSize = size
        }
        // The key-press preview balloon renders here at the keyboard level —
        // not inside the pressed key like the alternates popup — so it can
        // never be underdrawn by a neighboring key or a later row, and so
        // there is one place that knows the keyboard's full bounds to clamp
        // against (`KeyPreviewPlacement`): a custom keyboard cannot draw
        // outside its own view, so unlike the system keyboard the balloon
        // must stay in-frame, overlapping the row above, with top-row and
        // edge keys shifting it inward. Pressed keys report their glyph and
        // cap bounds up through `KeyPreviewPreferenceKey`.
        .overlayPreferenceValue(KeyPreviewPreferenceKey.self) { requests in
            GeometryReader { proxy in
                ForEach(requests) { request in
                    let frame = KeyPreviewPlacement.balloonFrame(
                        keyFrame: proxy[request.anchor],
                        keyboardBounds: CGRect(origin: .zero, size: proxy.size))
                    KeyPreviewBalloon(text: request.text)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
            // Purely visual feedback for the finger already on the key; it
            // must never intercept the next touch.
            .allowsHitTesting(false)
        }
        // A reused view identity (host editor/preview) must drop a stale panel
        // selection when the layout changes.
        .onChange(of: layout.id) { _, _ in activePanelName = nil }
    }

    /// Intercept panel switches; forward every other action to the host.
    private func handle(_ action: KeyAction) {
        if case .switchPanel(let target) = action {
            activePanelName = target
        } else {
            onAction(action)
        }
    }

    /// Tracks which row owns the open alternates popup, for the row-level
    /// z-order raise. Closes are keyed to the opener so a stale dismissal
    /// can't clear a popup another row just opened.
    private func popupChanged(rowID: UUID, isOpen: Bool) {
        if isOpen {
            popupRowID = rowID
        } else if popupRowID == rowID {
            popupRowID = nil
        }
    }
}

/// One row of keys, sized to fill the available width. Key widths are
/// proportional to `Key.widthFactor`, so a `widthFactor` of 3.0 (space)
/// renders three times as wide as a standard 1.0 key.
private struct KeyRowView: View {
    let row: KeyRow
    let metrics: KeyboardMetrics
    /// Shared key-unit basis for rows containing a `spacer` (see
    /// `KeyboardView.gridReferenceFactor`). Ignored by plain rows, which keep
    /// stretching to fill the width.
    let gridReferenceFactor: Double
    /// The keyboard's rendered size, forwarded to each key for its
    /// alternates popup's placement.
    let keyboardSize: CGSize
    let returnKeyType: UIReturnKeyType
    let nextKeyboardOverlay: AnyView?
    let onCursorMove: (CursorMoveEvent) -> Void
    let onAction: (KeyAction) -> Void
    /// Reports popup open/close for any key in this row, so `KeyboardView`
    /// can raise the row above its siblings.
    let onPopupChange: (Bool) -> Void

    /// Key currently showing its alternates popup, raised above its row
    /// neighbors: a top-row popup is clamped down over its own row, where
    /// later siblings would otherwise draw over it (issue #122).
    @State private var popupKeyID: UUID?

    var body: some View {
        GeometryReader { geo in
            let keys = row.keys
            let hasSpacer = keys.contains(where: \.isSpacer)
            let totalFactor = keys.reduce(0.0) { $0 + $1.widthFactor }
            let spacing = metrics.keySpacing * CGFloat(max(keys.count - 1, 0))
            // Grouped rows lay out on the shared grid so keys keep a constant
            // size and the spacer takes the slack; plain rows fill the width
            // proportionally (the spacer-free case is unchanged).
            let referenceFactor = hasSpacer ? gridReferenceFactor : totalFactor
            let unit = referenceFactor > 0 ? (geo.size.width - spacing) / CGFloat(referenceFactor) : 0
            HStack(spacing: metrics.keySpacing) {
                ForEach(keys) { key in
                    if key.isSpacer {
                        // At least its grid share, growing to right-align the
                        // keys that follow when the row is short.
                        Spacer(minLength: max(unit * key.widthFactor, 0))
                    } else {
                        KeyButton(
                            key: key,
                            keyboardSize: keyboardSize,
                            returnKeyType: returnKeyType,
                            nextKeyboardOverlay: nextKeyboardOverlay,
                            onCursorMove: onCursorMove,
                            onAction: onAction,
                            onPopupChange: { popupChanged(keyID: key.id, isOpen: $0) })
                            .frame(width: max(unit * key.widthFactor, 0))
                            .zIndex(key.id == popupKeyID ? 1 : 0)
                    }
                }
            }
        }
        .frame(height: metrics.rowHeight)
    }

    /// Tracks which key owns the open alternates popup (for the key-level
    /// z-order raise) and forwards the change to `KeyboardView` (for the
    /// row-level one). Closes are keyed to the opener so a stale dismissal
    /// can't clear a popup another key just opened.
    private func popupChanged(keyID: UUID, isOpen: Bool) {
        if isOpen {
            popupKeyID = keyID
            onPopupChange(true)
        } else if popupKeyID == keyID {
            popupKeyID = nil
            onPopupChange(false)
        }
    }
}

/// A single key cap. Tap emits the key's action on release, like the system
/// keyboard's character keys; press feedback is a highlighted cap plus the
/// standard input click on key-down — and, for insert keys on iPhone, the
/// magnified preview balloon (see `showsPreviewBalloon`). Keys with
/// `alternates` open a popup of the alternate glyphs after a 0.3 s hold:
/// slide to highlight one and
/// release to commit it, release on the key cap to type the base symbol, or
/// release anywhere else to cancel — the popup always closes when the finger
/// lifts. Under VoiceOver, where that slide isn't operable, the alternates
/// are also exposed as accessibility custom actions on the key
/// (`AlternatesAccessibility`). Backspace instead acts on key-down and
/// autorepeats while held — one `.backspace` per tick, which the extension
/// applies grapheme-cluster-aware. Space keys hold-to-enter trackpad-style
/// cursor mode (see `isCursorControlKey`): a horizontal drag emits steps
/// through `onCursorMove`, and releasing after the hold types nothing, like
/// the system space bar.
@MainActor
private struct KeyButton: View {
    let key: Key
    /// The keyboard's rendered size — the bounds the alternates popup's
    /// placement clamps against.
    let keyboardSize: CGSize
    let returnKeyType: UIReturnKeyType
    let nextKeyboardOverlay: AnyView?
    let onCursorMove: (CursorMoveEvent) -> Void
    let onAction: (KeyAction) -> Void
    /// Reports the alternates popup opening/closing, so the enclosing row
    /// and keyboard can raise this key's subtree in z-order while the popup
    /// overlaps its neighbors.
    let onPopupChange: (Bool) -> Void

    @State private var isPressed = false
    /// Set when the key-down handler already emitted the action (backspace),
    /// so the tap that fires on release doesn't emit it a second time.
    @State private var pressDidFireAction = false
    @State private var repeatTask: Task<Void, Never>?

    /// Whether the alternates popup is visible. Driven by the UIKit
    /// long-press recognizer in `KeyPressTracker`, whose `.ended`,
    /// `.cancelled`, and `.failed` states cover every teardown path — the
    /// physical finger-up, a scrolling host list stealing the touch, the
    /// app resigning active — so the popup always closes when the finger
    /// lifts and can never be stranded on screen (issue #104).
    @State private var showingAlternates = false
    /// The finger's last reported position in the key's coordinate space,
    /// while the popup is open.
    @State private var alternatesFingerLocation: CGPoint?
    /// The key cap's frame in the keyboard's coordinate space
    /// (`KeyboardView.keyboardSpace`): its size classifies a release as on
    /// or off the cap (release-on-cap types the base symbol), and its
    /// position feeds the popup placement.
    @State private var keyCapFrame: CGRect = .null
    /// The popup's measured natural size (it self-sizes to its cells),
    /// captured while it is still mounted invisibly during the hold — the
    /// other input the placement math needs.
    @State private var popupSize: CGSize = .zero
    /// The popup's cell frames in the key's coordinate space, reported by
    /// `AlternatesPopup` as it lays out and consumed by the hit-testing in
    /// `AlternatesSelection`.
    @State private var alternateCellFrames: [Int: CGRect] = [:]

    /// Quantizes the cursor-mode drag into whole steps (kit logic,
    /// unit-tested). Re-anchored each time the hold begins.
    @State private var cursorStepper = CursorDragStepper()

    private var hasAlternates: Bool { !key.alternates.isEmpty }

    /// Whether this key drives trackpad-style cursor movement on long-press
    /// (issue #70): space keys, in every context — host previews render the
    /// identical interaction and simply receive a no-op `onCursorMove`, so
    /// the preview can never disagree with the extension. Cursor mode takes
    /// precedence over `alternates` on a space key: hold-to-move-cursor on
    /// the space bar is a platform-wide expectation, so a user layout that
    /// adds alternates to space keeps tap-to-insert but gets no popup (and
    /// no alternates dot — see `rendersAlternates`).
    private var isCursorControlKey: Bool { key.action == .space }

    /// Whether the alternates machinery (dot, popup, hold-slide-release
    /// tracker) applies to this key. False for space keys even when the
    /// layout declares alternates, per the precedence above.
    private var rendersAlternates: Bool { hasAlternates && !isCursorControlKey }

    /// Whether the cap draws its pressed fill; an open popup keeps the cap
    /// highlighted like the system keyboard does.
    private var showsPressedFill: Bool {
        isPressed || showingAlternates
    }

    /// Whether this key currently requests the key-press preview balloon
    /// (issue #71). Insert keys only — function keys (space, return,
    /// backspace, globe, panel switch) show no balloon, matching the system
    /// keyboard — and **iPhone only**: system iPad keyboards do not show
    /// key balloons, so per platform convention the preview is disabled on
    /// iPad. The balloon tracks the press (key-down shows it; release or
    /// cancellation clears `isPressed` through the existing press tracking,
    /// which hides it) and yields as soon as the alternates popup opens so
    /// the two overlays never fight.
    private var showsPreviewBalloon: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              case .insert = key.action
        else { return false }
        return isPressed && !showingAlternates
    }

    /// Reported cell frames in popup order (`.null` until measured) — the
    /// hit-testing input.
    private var orderedCellFrames: [CGRect] {
        key.alternates.indices.map { alternateCellFrames[$0] ?? .null }
    }

    private var highlightedAlternateIndex: Int? {
        alternatesFingerLocation.flatMap {
            AlternatesSelection.highlightedIndex(at: $0, cellFrames: orderedCellFrames)
        }
    }

    /// Offset from the popup's natural overlay position (top-aligned and
    /// centered over the key cap) to its placed frame — floating above the
    /// cap on every row, clamped inside the keyboard so the top row's popup
    /// shifts down over its own cap instead of rendering below the key
    /// (issue #122). Zero until the pre-open measurements land, while the
    /// popup is still invisible.
    private var popupOffset: CGSize {
        guard popupSize != .zero, !keyCapFrame.isNull, keyboardSize != .zero
        else { return .zero }
        let frame = AlternatesPopupPlacement.popupFrame(
            popupSize: popupSize,
            keyFrame: keyCapFrame,
            keyboardBounds: CGRect(origin: .zero, size: keyboardSize))
        return CGSize(
            width: frame.midX - keyCapFrame.midX,
            height: frame.minY - keyCapFrame.minY)
    }

    /// Palette tier for this key (character / function / tinted return),
    /// resolved against the trait environment so it follows the extension's
    /// `keyboardAppearance` override and the host app's color scheme alike.
    private var style: KeyStyle { KeyStyle(key: key, returnKeyType: returnKeyType) }

    /// The rendered glyph. Return keys always mirror the host field's
    /// `returnKeyType` (Go/Search/Done…), overriding any static layout label,
    /// exactly like the system keyboard. Every other key keeps its own label.
    private var displayText: String {
        key.action == .return ? ReturnKeyLabel.text(for: returnKeyType) : key.displayLabel
    }

    /// Spoken label; for return keys the mapped word ("search", not a stale
    /// "return") so VoiceOver matches what is displayed.
    private var spokenLabel: String {
        key.action == .return
            ? ReturnKeyLabel.text(for: returnKeyType)
            : (key.accessibilityLabel ?? key.displayLabel)
    }

    /// Autorepeat timing for a held backspace (pure kit policy, unit-tested;
    /// the actual clock lives here in the view).
    private static let backspaceCadence = KeyRepeatCadence.backspace

    /// `minimumDuration` used for keys without alternates: long enough that
    /// the long-press never completes, so the gesture serves purely as the
    /// press tracker (`onPressingChanged`) and `isPressed` survives an
    /// arbitrarily long hold (a completed long-press ends press tracking).
    private static let pressTrackingOnlyDuration: TimeInterval = 86_400

    /// How long a key with alternates must be held before its popup opens.
    private static let alternatesHoldDuration: TimeInterval = 0.3

    /// How long the space bar must be held before trackpad-style cursor
    /// mode engages. Matches the alternates hold so every hold interaction
    /// on the keyboard shares one rhythm.
    private static let cursorModeHoldDuration: TimeInterval = alternatesHoldDuration

    /// Name of the coordinate space covering the key cap and its popup
    /// overlay, so drag locations and popup cell frames are directly
    /// comparable. Lookup resolves to the nearest ancestor declaring the
    /// name, so every key can share one name without colliding with its
    /// siblings.
    private static let coordinateSpaceName = "IPAKeyButton"
    private static var keySpace: NamedCoordinateSpace {
        .named(coordinateSpaceName)
    }

    var body: some View {
        pressableKeyCap
            // While pressed, report this key's glyph and cap bounds up to
            // `KeyboardView`, which renders the preview balloon in its own
            // keyboard-level overlay (see the comment there for why the
            // balloon doesn't render here like the alternates popup does).
            .anchorPreference(key: KeyPreviewPreferenceKey.self, value: .bounds) { anchor in
                showsPreviewBalloon
                    ? [KeyPreviewRequest(id: key.id, text: displayText, anchor: anchor)]
                    : []
            }
            .overlay {
                if key.action == .nextKeyboard, let nextKeyboardOverlay {
                    // The extension's UIKit globe control sits on top and
                    // captures all touches on this key, so the system provides
                    // tap-to-switch and the long-press input-mode list.
                    nextKeyboardOverlay
                }
            }
            .overlay(alignment: .top) {
                // Mounted (invisibly) from the first touch, not from popup-
                // open, so the cells are laid out and their frames reported
                // during the 0.3 s hold — before the release can possibly
                // need them. Revealing on open is then a pure opacity flip
                // with no layout. If the popup instead mounted at open, the
                // commit would depend on a render pass landing between the
                // long-press's `.began` and `.ended`: on a starved main
                // thread (slow CI runner) the queued finger-up can be
                // processed first, and the release — with every cell frame
                // still unmeasured — would classify as `.dismiss` and type
                // nothing (the CI-only slide-to-select regression on #71).
                if rendersAlternates && (isPressed || showingAlternates) {
                    AlternatesPopup(
                        alternates: key.alternates,
                        highlightedIndex: highlightedAlternateIndex,
                        cellSpaceName: Self.coordinateSpaceName,
                        onCellFrameChange: { alternateCellFrames[$0] = $1 })
                        // Its natural size feeds the placement math; the
                        // pre-open mount above makes it ready before reveal.
                        .onGeometryChange(for: CGSize.self) { proxy in
                            proxy.size
                        } action: { size in
                            popupSize = size
                        }
                        .opacity(showingAlternates ? 1 : 0)
                        // Out of the accessibility tree until it is really
                        // shown, so a plain tap never surfaces phantom cells.
                        .accessibilityHidden(!showingAlternates)
                        // Purely visual — selection is by sliding the finger
                        // that opened it, so it must never swallow touches.
                        .allowsHitTesting(false)
                        // Applied outside the cell-frame reporting, so the
                        // frames used for hit-testing include the placement.
                        .offset(popupOffset)
                        .onDisappear { alternateCellFrames = [:] }
                }
            }
            .coordinateSpace(Self.keySpace)
            .onDisappear {
                stopRepeat()
                dismissAlternates()
            }
    }

    private var keyCap: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(uiColor: style.fill(isPressed: showsPressedFill)))
            // The system keyboard's 1-pt keycap drop shadow; applied before
            // the overlays so the label doesn't cast one.
            .shadow(color: Color(uiColor: KeyPalette.keycapShadow), radius: 0, y: 1)
            .overlay(
                Text(displayText)
                    .font(.title3)
                    .foregroundStyle(Color(uiColor: style.textColor))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            )
            .overlay(alignment: .topTrailing) {
                if rendersAlternates {
                    Circle()
                        .fill(Color(uiColor: .label).opacity(0.4))
                        .frame(width: 4, height: 4)
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
            // On the cap itself — not the composite with the popup overlay —
            // so an open popup's cells keep their own labels and identifiers
            // (`Key.accessibilityIdentifier` documents that the popup reuses
            // the per-key scheme) instead of inheriting this key's.
            .accessibilityLabel(spokenLabel)
            .accessibilityIdentifier(key.accessibilityIdentifier)
            .accessibilityAddTraits(.isKeyboardKey)
            // VoiceOver's non-drag path to the alternates (issue #114):
            // hold-slide-release is not operable under VoiceOver, so each
            // alternate is also a custom action on the base key (swipe
            // up/down to choose, double-tap to commit), emitting the same
            // action a slide-and-release on its popup cell would. Adds
            // nothing for keys without alternates.
            .accessibilityActions {
                ForEach(AlternatesAccessibility.customActions(for: key)) { custom in
                    Button(custom.name) { onAction(custom.action) }
                }
            }
    }

    /// The key cap with its press handling attached. Keys without alternates
    /// keep the SwiftUI tap plus the plain long-press purely as a press
    /// tracker — its `onPressingChanged` is the key-down/key-up signal for
    /// highlight, click, and backspace autorepeat, and `maximumDistance` is
    /// generous so a rolling fingertip doesn't cancel a held backspace.
    ///
    /// Keys *with* alternates are instead driven by a UIKit touch tracker
    /// (`KeyPressTracker`) overlaid on the cap, the same pattern as
    /// the extension's globe-key overlay. SwiftUI's own gestures can't
    /// express this interaction correctly: a completed long-press modifier
    /// delivers no callback at the physical finger-up (which is what used to
    /// strand the popup on screen, issue #104), and composing a raw
    /// `LongPressGesture` with a `DragGesture` to obtain the release claims
    /// touch arbitration so aggressively — even via `simultaneousGesture` —
    /// that an enclosing `List` can no longer scroll across the host app's
    /// keyboard previews. `UILongPressGestureRecognizer` is the system's
    /// cooperative primitive: a scroll that starts early defeats it, while a
    /// 0.3 s stationary hold begins it, streams finger locations, and
    /// reports the real release or cancellation.
    ///
    /// Space keys use the same tracker for cursor mode (issue #70): the
    /// hold's `.began` anchors the drag and opens the cursor session
    /// (`CursorMoveEvent.began` — the extension snapshots the document
    /// context here, while it is guaranteed settled), `.changed` samples
    /// feed the stepper (whose quantized steps go out as `.moved(steps:)`),
    /// and the release or cancellation closes the session (`.ended`) while
    /// deliberately typing nothing — tap-to-insert
    /// still comes from the tap recognizer, which the completed hold has
    /// already defeated. No per-step feedback: haptics need Full Access in
    /// an extension, and replaying the input click per step would be noise.
    @ViewBuilder private var pressableKeyCap: some View {
        if isCursorControlKey {
            keyCap
                .overlay {
                    KeyPressTracker(
                        holdDuration: Self.cursorModeHoldDuration,
                        onPressChanged: { pressing in
                            isPressed = pressing
                            if pressing { UIDevice.current.playInputClick() }
                        },
                        onBegan: { location in
                            // Fresh stepper per hold; the first sample only
                            // anchors, so entering cursor mode never jumps.
                            var stepper = CursorDragStepper()
                            _ = stepper.steps(movingTo: location.x)
                            cursorStepper = stepper
                            onCursorMove(.began)
                        },
                        onMoved: { location in
                            var stepper = cursorStepper
                            let steps = stepper.steps(movingTo: location.x)
                            cursorStepper = stepper
                            if steps != 0 { onCursorMove(.moved(steps: steps)) }
                        },
                        onEnded: { _ in onCursorMove(.ended) },
                        onCancelled: { onCursorMove(.ended) },
                        onTap: { tapped() })
                }
        } else if hasAlternates {
            keyCap
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: KeyboardView.keyboardSpace)
                } action: { frame in
                    keyCapFrame = frame
                }
                .overlay {
                    KeyPressTracker(
                        holdDuration: Self.alternatesHoldDuration,
                        onPressChanged: { pressing in
                            isPressed = pressing
                            if pressing { UIDevice.current.playInputClick() }
                        },
                        onBegan: { location in
                            showingAlternates = true
                            alternatesFingerLocation = location
                            onPopupChange(true)
                        },
                        onMoved: { location in
                            alternatesFingerLocation = location
                        },
                        onEnded: { location in
                            commit(release: location)
                            dismissAlternates()
                        },
                        onCancelled: { dismissAlternates() },
                        onTap: { tapped() })
                }
        } else {
            keyCap
                .onTapGesture { tapped() }
                .onLongPressGesture(
                    minimumDuration: Self.pressTrackingOnlyDuration,
                    maximumDistance: 40,
                    perform: {},
                    onPressingChanged: { pressingChanged($0) }
                )
        }
    }

    // MARK: Press handling

    /// Applies a finger release at `location`: the highlighted alternate
    /// wins, a release still on the key cap types the base symbol, and
    /// anything else cancels.
    private func commit(release location: CGPoint) {
        let target = AlternatesSelection.releaseTarget(
            at: location,
            cellFrames: orderedCellFrames,
            keyCapBounds: CGRect(origin: .zero, size: keyCapFrame.size))
        switch target {
        case .alternate(let index):
            onAction(key.alternates[index].action)
        case .baseKey:
            onAction(key.action)
        case .dismiss:
            break
        }
    }

    private func dismissAlternates() {
        showingAlternates = false
        alternatesFingerLocation = nil
        onPopupChange(false)
    }

    private func tapped() {
        if pressDidFireAction {
            pressDidFireAction = false
            return
        }
        onAction(key.action)
    }

    /// Key-down / key-up. Down: highlight, input click, and — for backspace —
    /// emit immediately and start the autorepeat. Up (or cancellation, e.g. a
    /// scrolling host preview list): clear the highlight and stop repeating,
    /// emitting nothing.
    private func pressingChanged(_ pressing: Bool) {
        isPressed = pressing
        if pressing {
            pressDidFireAction = false
            UIDevice.current.playInputClick()
            if key.action == .backspace {
                onAction(.backspace)
                pressDidFireAction = true
                startRepeat()
            }
        } else {
            stopRepeat()
        }
    }

    /// Emit `.backspace` on the kit cadence until cancelled. Each tick is one
    /// action, so held deletion removes exactly one user-perceived character
    /// per tick through the extension's grapheme-cluster-aware path.
    private func startRepeat() {
        repeatTask?.cancel()
        repeatTask = Task {
            var tick = 0
            while !Task.isCancelled {
                let wait = Self.backspaceCadence.interval(beforeTick: tick)
                do {
                    try await Task.sleep(for: .seconds(wait))
                } catch {
                    return // cancelled mid-wait
                }
                UIDevice.current.playInputClick()
                onAction(.backspace)
                tick += 1
            }
        }
    }

    private func stopRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

/// The UIKit touch tracker behind a key's hold interactions — the
/// alternates popup (hold to open, slide to highlight, release to commit;
/// issue #104) and the space bar's trackpad-style cursor mode (hold, then
/// drag; issue #70). It
/// overlays the key cap (like the extension's globe-key overlay) and owns
/// all of the key's touch handling; see `KeyButton.pressableKeyCap` for why
/// SwiftUI's own gestures can't express this.
///
/// Three cooperating pieces, all reporting in the tracker view's own
/// coordinate space (identical to the key's, since the overlay fills the
/// cap):
///
/// - raw `touchesBegan`/`touchesEnded`/`touchesCancelled` overrides are the
///   key-down/key-up signal (highlight + input click); `touchesMoved` also
///   ends the press when the hold recognizer has silently `.failed` (a drag
///   past `allowableMovement` — no action message accompanies that
///   transition), so a drag-cancelled key doesn't stay highlighted with its
///   preview balloon stuck until finger-up;
/// - a `UILongPressGestureRecognizer` drives the hold phase: `.began` fires
///   after the stationary hold (popup opens / cursor mode engages),
///   `.changed` streams the sliding finger,
///   `.ended` is the real finger-up (commit), and `.cancelled` fires on
///   every other teardown (an enclosing scroll view stealing the touch, the
///   app resigning active) so the popup always closes;
/// - a `UITapGestureRecognizer` that `require(toFail:)`s the long-press
///   inserts the base symbol on a quick tap. The failure requirement makes
///   double-emission impossible by construction: once the hold begins, the
///   tap can never fire, and vice versa.
private struct KeyPressTracker: UIViewRepresentable {
    let holdDuration: TimeInterval
    var onPressChanged: (Bool) -> Void
    var onBegan: (CGPoint) -> Void
    var onMoved: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void
    var onCancelled: () -> Void
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> TouchObservingView {
        let view = TouchObservingView()
        view.backgroundColor = .clear
        view.onPressChanged = { [coordinator = context.coordinator] pressing in
            coordinator.parent.onPressChanged(pressing)
        }

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = holdDuration
        // Matches the SwiftUI press tracker's `maximumDistance`: a rolling
        // fingertip shouldn't cancel the hold before the popup opens. Only
        // constrains the pre-recognition phase; sliding afterward is free.
        longPress.allowableMovement = 40
        // Keep the raw-touch key-up signal flowing to the view even once
        // the recognizer has claimed the gesture.
        longPress.cancelsTouchesInView = false
        view.addGestureRecognizer(longPress)
        view.holdRecognizer = longPress

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.require(toFail: longPress)
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ view: TouchObservingView, context: Context) {
        // Rebind so the callbacks capture the current view state.
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: KeyPressTracker

        init(parent: KeyPressTracker) {
            self.parent = parent
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            switch recognizer.state {
            case .began:
                parent.onBegan(location)
            case .changed:
                parent.onMoved(location)
            case .ended:
                parent.onEnded(location)
            case .cancelled, .failed:
                parent.onCancelled()
            default:
                break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            if recognizer.state == .ended {
                parent.onTap()
            }
        }
    }

    /// A clear view whose raw touch overrides provide the key-down/key-up
    /// press signal (recognizers only report from the 0.3 s mark onward).
    final class TouchObservingView: UIView {
        var onPressChanged: ((Bool) -> Void)?
        /// The hold recognizer, consulted from `touchesMoved`: a drag past
        /// `allowableMovement` before the hold completes moves it to
        /// `.failed`, and UIKit sends no action message for that transition —
        /// so without polling it here the key would stay pressed (highlight
        /// and preview balloon frozen on the key) until finger-up.
        weak var holdRecognizer: UIGestureRecognizer?
        /// Whether a key-down has been reported without its matching key-up,
        /// so a drag-cancelled press isn't ended twice.
        private var isReportingPress = false

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            isReportingPress = true
            onPressChanged?(true)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event)
            if holdRecognizer?.state == .failed {
                endPress()
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            endPress()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            endPress()
        }

        private func endPress() {
            guard isReportingPress else { return }
            isReportingPress = false
            onPressChanged?(false)
        }
    }
}

/// A floating row of alternate glyphs shown above a long-pressed key —
/// above on every row, like the system keyboard: the owning `KeyButton`
/// positions it via the unit-tested `AlternatesPopupPlacement`, which
/// clamps it inside the keyboard's bounds (a custom keyboard cannot draw
/// outside its own view), shifting top-row popups down over their own cap.
/// Purely visual: selection is driven by the owning key's continuous press
/// (`KeyPressTracker` — slide to highlight, release to commit), so
/// the cells carry no tap handlers of their own — they report their frames
/// up for hit-testing instead — while keeping their accessibility labels
/// and identifiers.
private struct AlternatesPopup: View {
    let alternates: [Key]
    /// Index of the cell currently under the finger, tinted like the system
    /// keyboard's selection; releasing commits it.
    let highlightedIndex: Int?
    /// The owning key's coordinate space name; cell frames are reported in
    /// it so they are directly comparable with the drag gesture's locations.
    let cellSpaceName: String
    let onCellFrameChange: (Int, CGRect) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(alternates.enumerated()), id: \.element.id) { index, alt in
                cell(for: alt, isHighlighted: index == highlightedIndex)
                    .onGeometryChange(for: CGRect.self) { [cellSpaceName] proxy in
                        proxy.frame(in: NamedCoordinateSpace.named(cellSpaceName))
                    } action: { frame in
                        onCellFrameChange(index, frame)
                    }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: KeyPalette.functionKey))
                .shadow(radius: 4, y: 2)
        )
        .fixedSize()
    }

    private func cell(for alt: Key, isHighlighted: Bool) -> some View {
        Text(alt.displayLabel)
            .font(.title3)
            .foregroundStyle(Color(uiColor: isHighlighted
                ? KeyPalette.alternateHighlightText
                : .label))
            .frame(minWidth: 36, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(uiColor: isHighlighted
                        ? KeyPalette.alternateHighlight
                        : KeyPalette.characterKey))
            )
            .accessibilityLabel(alt.accessibilityLabel ?? alt.displayLabel)
            .accessibilityIdentifier(alt.accessibilityIdentifier)
            .accessibilityAddTraits(.isKeyboardKey)
    }
}

// MARK: Key-press preview balloon

/// A pressed key's request for the preview balloon: the glyph to magnify
/// and where the key cap sits, resolved against the keyboard's bounds by
/// the keyboard-level overlay in `KeyboardView`. `Equatable`
/// (`Anchor: Equatable` since iOS 15) so the preference system can skip
/// re-evaluating that overlay when a key re-render republishes an unchanged
/// value — a pressed key re-renders on every slide sample while its
/// alternates popup is open, and that dead work competes with the gesture's
/// own event handling on slow machines.
private struct KeyPreviewRequest: Identifiable, Equatable {
    /// The pressed key's `id` — unique per rendered key, so simultaneous
    /// presses on different keys each get their own balloon.
    let id: UUID
    let text: String
    let anchor: Anchor<CGRect>
}

private struct KeyPreviewPreferenceKey: PreferenceKey {
    static var defaultValue: [KeyPreviewRequest] { [] }
    static func reduce(value: inout [KeyPreviewRequest], nextValue: () -> [KeyPreviewRequest]) {
        value.append(contentsOf: nextValue())
    }
}

/// The magnified key-press preview balloon shown while an insert key is
/// held (issue #71). IPA keycaps are small and many glyphs are
/// near-identical at keycap size (ɘ ə ɵ; ɜ ɞ; ˑ ː), so the balloon echoes
/// the pressed glyph large enough to confirm the right key was hit before
/// lifting the finger. iPhone only, following platform convention — system
/// iPad keyboards show no key balloons (`KeyButton.showsPreviewBalloon`
/// gates this). Purely visual: it never takes touches, and it surfaces as a
/// single *unlabeled* accessibility element (identifier
/// `key-preview-balloon`, issue #120) so UI tests can assert its
/// press-scoped lifecycle without VoiceOver gaining a second spoken copy of
/// the glyph — the key cap underneath already carries the spoken label and
/// identifier.
private struct KeyPreviewBalloon: View {
    /// Stable accessibility identifier for the balloon (issue #120). One
    /// balloon per pressed key, so simultaneous multi-touch presses surface
    /// one element each under this same identifier.
    static let accessibilityIdentifier = "key-preview-balloon"

    let text: String

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: KeyPalette.characterKey))
            .shadow(radius: 4, y: 2)
            .overlay(
                Text(text)
                    .font(.largeTitle)
                    .foregroundStyle(Color(uiColor: .label))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            )
            // `children: .ignore` keeps the magnified glyph out of the
            // accessibility tree (VoiceOver must not announce it a second
            // time), while the identifier on the collapsed element lets UI
            // tests observe when the balloon is on screen — shown while an
            // insert key is held, gone on release and while the alternates
            // popup is open. Deliberately no label or traits, so VoiceOver
            // has nothing to speak here.
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(Self.accessibilityIdentifier)
    }
}

#if DEBUG
#Preview {
    let layout = LayoutStore().bundledLayouts().first ?? KeyboardLayout(
        name: "Sample",
        locale: "en-US",
        rows: [KeyRow(keys: [.insert("ə"), .insert("i"), .insert("u")])]
    )
    return KeyboardView(layout: layout, returnKeyType: .search) { action in
        print("action: \(action)")
    }
    .frame(height: KeyboardMetrics().totalHeight(for: layout.primaryArrangement))
    .background(Color(uiColor: KeyboardChrome.background))
}
#endif
