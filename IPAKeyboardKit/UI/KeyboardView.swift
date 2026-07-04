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
//  stay silent); backspace acts on key-down and autorepeats while held,
//  timed by the unit-tested `KeyRepeatCadence`. Keys with alternates use
//  the system keyboard's hold-slide-release interaction: the popup opens
//  after a 0.3 s hold, tracks the sliding finger (hit-testing in the
//  unit-tested `AlternatesSelection`), and always closes on release. The
//  extension can overlay the globe keycap with a UIKit control
//  (`nextKeyboardOverlay`) so the system drives keyboard switching,
//  including the long-press picker.
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
    private let onAction: (KeyAction) -> Void

    /// Name of the panel currently shown within the primary arrangement.
    /// `nil` falls back to the primary panel. Panel-switch keys update this
    /// in place; the action never escapes to the host document.
    @State private var activePanelName: String?

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
    public init(
        layout: KeyboardLayout,
        metrics: KeyboardMetrics = KeyboardMetrics(),
        returnKeyType: UIReturnKeyType = .default,
        nextKeyboardOverlay: AnyView? = nil,
        onAction: @escaping (KeyAction) -> Void
    ) {
        self.layout = layout
        self.metrics = metrics
        self.returnKeyType = returnKeyType
        self.nextKeyboardOverlay = nextKeyboardOverlay
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
                ForEach(Array(symbolRows.enumerated()), id: \.element.id) { index, row in
                    // The top row has no room above it within the keyboard's own
                    // bounds, so its long-press popup opens downward instead.
                    KeyRowView(
                        row: row,
                        metrics: metrics,
                        gridReferenceFactor: reference,
                        popupEdge: index == 0 ? .bottom : .top,
                        returnKeyType: returnKeyType,
                        nextKeyboardOverlay: nextKeyboardOverlay,
                        onAction: handle)
                }
            }
            if let bottomBar {
                Spacer(minLength: metrics.rowSpacing)
                KeyRowView(
                    row: bottomBar,
                    metrics: metrics,
                    gridReferenceFactor: reference,
                    popupEdge: .top,
                    returnKeyType: returnKeyType,
                    nextKeyboardOverlay: nextKeyboardOverlay,
                    onAction: handle)
            }
        }
        .padding(metrics.outerPadding)
        // Reserve the arrangement's tallest-panel + bottom-bar height so
        // switching panels doesn't change the keyboard's size. Matches the
        // controller's height constraint (both via `metrics.totalHeight`).
        .frame(maxWidth: .infinity, minHeight: metrics.totalHeight(for: arrangement), alignment: .top)
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
    let popupEdge: VerticalEdge
    let returnKeyType: UIReturnKeyType
    let nextKeyboardOverlay: AnyView?
    let onAction: (KeyAction) -> Void

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
                            popupEdge: popupEdge,
                            returnKeyType: returnKeyType,
                            nextKeyboardOverlay: nextKeyboardOverlay,
                            onAction: onAction)
                            .frame(width: max(unit * key.widthFactor, 0))
                    }
                }
            }
        }
        .frame(height: metrics.rowHeight)
    }
}

/// A single key cap. Tap emits the key's action on release, like the system
/// keyboard's character keys; press feedback is a highlighted cap plus the
/// standard input click on key-down. Keys with `alternates` open a popup of
/// the alternate glyphs after a 0.3 s hold: slide to highlight one and
/// release to commit it, release on the key cap to type the base symbol, or
/// release anywhere else to cancel — the popup always closes when the finger
/// lifts. Backspace instead acts on key-down and autorepeats while held —
/// one `.backspace` per tick, which the extension applies
/// grapheme-cluster-aware.
@MainActor
private struct KeyButton: View {
    let key: Key
    let popupEdge: VerticalEdge
    let returnKeyType: UIReturnKeyType
    let nextKeyboardOverlay: AnyView?
    let onAction: (KeyAction) -> Void

    @State private var isPressed = false
    /// Set when the key-down handler already emitted the action (backspace),
    /// so the tap that fires on release doesn't emit it a second time.
    @State private var pressDidFireAction = false
    @State private var repeatTask: Task<Void, Never>?

    /// Whether the alternates popup is visible. Driven by the UIKit
    /// long-press recognizer in `AlternatesPressTracker`, whose `.ended`,
    /// `.cancelled`, and `.failed` states cover every teardown path — the
    /// physical finger-up, a scrolling host list stealing the touch, the
    /// app resigning active — so the popup always closes when the finger
    /// lifts and can never be stranded on screen (issue #104).
    @State private var showingAlternates = false
    /// The finger's last reported position in the key's coordinate space,
    /// while the popup is open.
    @State private var alternatesFingerLocation: CGPoint?
    /// The key cap's rendered size, so a release can be classified as on or
    /// off the cap (release-on-cap types the base symbol).
    @State private var keyCapSize: CGSize = .zero
    /// The popup's cell frames in the key's coordinate space, reported by
    /// `AlternatesPopup` as it lays out and consumed by the hit-testing in
    /// `AlternatesSelection`.
    @State private var alternateCellFrames: [Int: CGRect] = [:]

    private var hasAlternates: Bool { !key.alternates.isEmpty }

    /// Whether the cap draws its pressed fill; an open popup keeps the cap
    /// highlighted like the system keyboard does.
    private var showsPressedFill: Bool {
        isPressed || showingAlternates
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
            .overlay {
                if key.action == .nextKeyboard, let nextKeyboardOverlay {
                    // The extension's UIKit globe control sits on top and
                    // captures all touches on this key, so the system provides
                    // tap-to-switch and the long-press input-mode list.
                    nextKeyboardOverlay
                }
            }
            .overlay(alignment: popupEdge == .top ? .top : .bottom) {
                if showingAlternates {
                    AlternatesPopup(
                        alternates: key.alternates,
                        edge: popupEdge,
                        highlightedIndex: highlightedAlternateIndex,
                        cellSpaceName: Self.coordinateSpaceName,
                        onCellFrameChange: { alternateCellFrames[$0] = $1 })
                        // Purely visual — selection is by sliding the finger
                        // that opened it, so it must never swallow touches.
                        .allowsHitTesting(false)
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
                if hasAlternates {
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
    }

    /// The key cap with its press handling attached. Keys without alternates
    /// keep the SwiftUI tap plus the plain long-press purely as a press
    /// tracker — its `onPressingChanged` is the key-down/key-up signal for
    /// highlight, click, and backspace autorepeat, and `maximumDistance` is
    /// generous so a rolling fingertip doesn't cancel a held backspace.
    ///
    /// Keys *with* alternates are instead driven by a UIKit touch tracker
    /// (`AlternatesPressTracker`) overlaid on the cap, the same pattern as
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
    @ViewBuilder private var pressableKeyCap: some View {
        if hasAlternates {
            keyCap
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { size in
                    keyCapSize = size
                }
                .overlay {
                    AlternatesPressTracker(
                        holdDuration: Self.alternatesHoldDuration,
                        onPressChanged: { pressing in
                            isPressed = pressing
                            if pressing { UIDevice.current.playInputClick() }
                        },
                        onBegan: { location in
                            showingAlternates = true
                            alternatesFingerLocation = location
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
            keyCapBounds: CGRect(origin: .zero, size: keyCapSize))
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

/// The UIKit touch tracker behind a key's alternates interaction — hold to
/// open the popup, slide to highlight, release to commit (issue #104). It
/// overlays the key cap (like the extension's globe-key overlay) and owns
/// all of the key's touch handling; see `KeyButton.pressableKeyCap` for why
/// SwiftUI's own gestures can't express this.
///
/// Three cooperating pieces, all reporting in the tracker view's own
/// coordinate space (identical to the key's, since the overlay fills the
/// cap):
///
/// - raw `touchesBegan`/`touchesEnded`/`touchesCancelled` overrides are the
///   key-down/key-up signal (highlight + input click);
/// - a `UILongPressGestureRecognizer` drives the popup: `.began` opens it
///   after the stationary hold, `.changed` streams the sliding finger,
///   `.ended` is the real finger-up (commit), and `.cancelled`/`.failed`
///   fire on every other teardown (an enclosing scroll view stealing the
///   touch, the app resigning active) so the popup always closes;
/// - a `UITapGestureRecognizer` that `require(toFail:)`s the long-press
///   inserts the base symbol on a quick tap. The failure requirement makes
///   double-emission impossible by construction: once the hold begins, the
///   tap can never fire, and vice versa.
private struct AlternatesPressTracker: UIViewRepresentable {
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
        var parent: AlternatesPressTracker

        init(parent: AlternatesPressTracker) {
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

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            onPressChanged?(true)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            onPressChanged?(false)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            onPressChanged?(false)
        }
    }
}

/// A floating row of alternate glyphs shown above a long-pressed key.
/// Purely visual: selection is driven by the owning key's continuous press
/// (`AlternatesPressTracker` — slide to highlight, release to commit), so
/// the cells carry no tap handlers of their own — they report their frames
/// up for hit-testing instead — while keeping their accessibility labels
/// and identifiers.
private struct AlternatesPopup: View {
    let alternates: [Key]
    /// Which side of the key the popup floats toward. Top rows open downward
    /// so the popup stays inside the keyboard's bounds instead of being clipped.
    let edge: VerticalEdge
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
        // Float fully clear of the key cap rather than overlapping it,
        // upward for normal rows and downward for the top row.
        .offset(y: edge == .top ? -56 : 56)
        .zIndex(1)
    }

    private func cell(for alt: Key, isHighlighted: Bool) -> some View {
        Text(alt.displayLabel)
            .font(.title3)
            .foregroundStyle(isHighlighted ? Color.white : Color(uiColor: .label))
            .frame(minWidth: 36, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHighlighted
                        ? Color(uiColor: .systemBlue)
                        : Color(uiColor: KeyPalette.characterKey))
            )
            .accessibilityLabel(alt.accessibilityLabel ?? alt.displayLabel)
            .accessibilityIdentifier(alt.accessibilityIdentifier)
            .accessibilityAddTraits(.isKeyboardKey)
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
