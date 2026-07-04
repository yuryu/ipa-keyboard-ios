//
//  PreviewChrome.swift
//  IPAKeyboard
//
//  Shared metrics for the full-bleed keyboard previews (LayoutDetailView,
//  LayoutEditorView, LayoutKeyEditorView). Those previews zero out the list
//  row insets so the keyboard-chrome color bleeds to the section card's
//  edges — but the card's rounded-corner mask then clips whatever reaches
//  the corners (issue #100). One shared inset keeps the keys clear of that
//  mask on every screen, without a clip: the editor previews are interactive
//  and their long-press alternates popup floats past the keyboard's bounds,
//  so clipping is never an option here (see LayoutListView's "shaped
//  background, not a clip" note for the same rationale).
//

import SwiftUI

enum PreviewChrome {
    /// Padding between the keyboard preview and the edges of its list card.
    ///
    /// Inset the keys clear of the list card's rounded-corner mask; the
    /// chrome color still bleeds to the card edge. 12pt on top of
    /// `KeyboardMetrics.outerPadding` (4pt regular / 3pt compact) keeps the
    /// 6pt-radius corner keycaps inside the card's corner circle on both the
    /// iOS 17 (~10pt) and iOS 26 (larger) card radii.
    static let padding: CGFloat = 12
}
