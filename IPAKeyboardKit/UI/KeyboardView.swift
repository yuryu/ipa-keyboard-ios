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

    /// Total height the keyboard wants for `rowCount` rows, including
    /// inter-row spacing and outer padding.
    public func totalHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * rowHeight
            + CGFloat(rowCount - 1) * rowSpacing
            + outerPadding * 2
    }
}

public struct KeyboardView: View {
    private let layout: KeyboardLayout
    private let metrics: KeyboardMetrics
    private let onAction: (KeyAction) -> Void

    public init(
        layout: KeyboardLayout,
        metrics: KeyboardMetrics = KeyboardMetrics(),
        onAction: @escaping (KeyAction) -> Void
    ) {
        self.layout = layout
        self.metrics = metrics
        self.onAction = onAction
    }

    public var body: some View {
        VStack(spacing: metrics.rowSpacing) {
            ForEach(Array(layout.rows.enumerated()), id: \.element.id) { index, row in
                // The top row has no room above it within the keyboard's own
                // bounds, so its long-press popup opens downward instead.
                KeyRowView(
                    row: row,
                    metrics: metrics,
                    popupEdge: index == 0 ? .bottom : .top,
                    onAction: onAction)
            }
        }
        .padding(metrics.outerPadding)
        .frame(maxWidth: .infinity)
    }
}

/// One row of keys, sized to fill the available width. Key widths are
/// proportional to `Key.widthFactor`, so a `widthFactor` of 3.0 (space)
/// renders three times as wide as a standard 1.0 key.
private struct KeyRowView: View {
    let row: KeyRow
    let metrics: KeyboardMetrics
    let popupEdge: VerticalEdge
    let onAction: (KeyAction) -> Void

    var body: some View {
        GeometryReader { geo in
            let keys = row.keys
            let totalFactor = keys.reduce(0.0) { $0 + $1.widthFactor }
            let spacing = metrics.keySpacing * CGFloat(max(keys.count - 1, 0))
            let unit = totalFactor > 0
                ? (geo.size.width - spacing) / totalFactor
                : 0
            HStack(spacing: metrics.keySpacing) {
                ForEach(keys) { key in
                    KeyButton(key: key, popupEdge: popupEdge, onAction: onAction)
                        .frame(width: max(unit * key.widthFactor, 0))
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
    .frame(height: KeyboardMetrics().totalHeight(rowCount: layout.rows.count))
    .background(Color(uiColor: .systemBackground))
}
#endif
