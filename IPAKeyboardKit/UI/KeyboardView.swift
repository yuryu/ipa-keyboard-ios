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

import SwiftUI

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

public struct KeyboardView: View {
    private let layout: KeyboardLayout
    private let metrics: KeyboardMetrics
    private let onAction: (KeyAction) -> Void

    /// Name of the panel currently shown within the primary arrangement.
    /// `nil` falls back to the primary panel. Panel-switch keys update this
    /// in place; the action never escapes to the host document.
    @State private var activePanelName: String?

    public init(
        layout: KeyboardLayout,
        metrics: KeyboardMetrics = KeyboardMetrics(),
        onAction: @escaping (KeyAction) -> Void
    ) {
        self.layout = layout
        self.metrics = metrics
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
                        KeyButton(key: key, popupEdge: popupEdge, onAction: onAction)
                            .frame(width: max(unit * key.widthFactor, 0))
                    }
                }
            }
        }
        .frame(height: metrics.rowHeight)
    }
}

/// A single key cap. Tap inserts; long-press (when the key has
/// `alternates`) surfaces a popup of the alternate glyphs.
private struct KeyButton: View {
    let key: Key
    let popupEdge: VerticalEdge
    let onAction: (KeyAction) -> Void

    @State private var showingAlternates = false

    private var hasAlternates: Bool { !key.alternates.isEmpty }

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(uiColor: .systemGray4))
            .overlay(
                Text(key.displayLabel)
                    .font(.title3)
                    .foregroundStyle(Color(uiColor: .label))
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
            .onTapGesture {
                if showingAlternates {
                    showingAlternates = false
                } else {
                    onAction(key.action)
                }
            }
            .modifier(LongPressAlternates(enabled: hasAlternates) {
                showingAlternates = true
            })
            .overlay(alignment: popupEdge == .top ? .top : .bottom) {
                if showingAlternates {
                    AlternatesPopup(alternates: key.alternates, edge: popupEdge) { action in
                        onAction(action)
                        showingAlternates = false
                    }
                }
            }
            .accessibilityLabel(key.accessibilityLabel ?? key.displayLabel)
            .accessibilityAddTraits(.isKeyboardKey)
    }
}

/// Attaches a long-press gesture only when the key actually has alternates,
/// so plain keys keep their snappy tap behavior.
private struct LongPressAlternates: ViewModifier {
    let enabled: Bool
    let onTrigger: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onLongPressGesture(minimumDuration: 0.3, perform: onTrigger)
        } else {
            content
        }
    }
}

/// A floating row of alternate glyphs shown above a long-pressed key.
private struct AlternatesPopup: View {
    let alternates: [Key]
    /// Which side of the key the popup floats toward. Top rows open downward
    /// so the popup stays inside the keyboard's bounds instead of being clipped.
    let edge: VerticalEdge
    let onSelect: (KeyAction) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(alternates) { alt in
                Text(alt.displayLabel)
                    .font(.title3)
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(minWidth: 36, minHeight: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(uiColor: .systemGray6))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(alt.action) }
                    .accessibilityLabel(alt.accessibilityLabel ?? alt.displayLabel)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .systemGray3))
                .shadow(radius: 4, y: 2)
        )
        .fixedSize()
        // Float fully clear of the key cap rather than overlapping it,
        // upward for normal rows and downward for the top row.
        .offset(y: edge == .top ? -56 : 56)
        .zIndex(1)
    }
}

#if DEBUG
#Preview {
    let layout = LayoutStore().bundledLayouts().first ?? KeyboardLayout(
        name: "Sample",
        locale: "en-US",
        rows: [KeyRow(keys: [.insert("ə"), .insert("i"), .insert("u")])]
    )
    return KeyboardView(layout: layout) { action in
        print("action: \(action)")
    }
    .frame(height: KeyboardMetrics().totalHeight(for: layout.primaryArrangement))
    .background(Color(uiColor: .systemBackground))
}
#endif
