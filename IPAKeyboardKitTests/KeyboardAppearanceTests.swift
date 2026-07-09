//
//  KeyboardAppearanceTests.swift
//  IPAKeyboardKitTests
//
//  Appearance parity with the system keyboard (issue #13): return-key
//  relabeling per `UIReturnKeyType`, the light/dark keycap palette, the
//  compact-height metrics for iPhone landscape, and the bundled layouts'
//  return key.
//

import Testing
import UIKit
@testable import IPAKeyboardKit

struct KeyboardAppearanceTests {

    // MARK: Return-key label

    @Test func returnKeyLabelMatchesTheFieldType() {
        #expect(ReturnKeyLabel.text(for: .default) == "return")
        #expect(ReturnKeyLabel.text(for: .go) == "go")
        #expect(ReturnKeyLabel.text(for: .join) == "join")
        #expect(ReturnKeyLabel.text(for: .next) == "next")
        #expect(ReturnKeyLabel.text(for: .route) == "route")
        #expect(ReturnKeyLabel.text(for: .search) == "search")
        #expect(ReturnKeyLabel.text(for: .send) == "send")
        #expect(ReturnKeyLabel.text(for: .done) == "done")
        #expect(ReturnKeyLabel.text(for: .emergencyCall) == "emergency call")
        #expect(ReturnKeyLabel.text(for: .continue) == "continue")
    }

    // MARK: Key styling

    @Test func symbolAndSpaceKeysUseTheCharacterTier() {
        #expect(KeyStyle(key: .insert("ə"), returnKeyType: .default) == .character)
        #expect(KeyStyle(key: Key(action: .space), returnKeyType: .default) == .character)
    }

    @Test func globeBackspaceAndPanelSwitchUseTheFunctionTier() {
        // Unaffected by the field's return-key type ("globe/backspace/space
        // unaffected" per the issue).
        for type in [UIReturnKeyType.default, .search] {
            #expect(KeyStyle(key: Key(action: .backspace), returnKeyType: type) == .function)
            #expect(KeyStyle(key: Key(action: .nextKeyboard), returnKeyType: type) == .function)
            #expect(KeyStyle(key: Key(action: .switchPanel("More")), returnKeyType: type) == .function)
        }
    }

    @Test func returnKeyIsProminentOnlyForSpecialTypes() {
        #expect(KeyStyle(key: Key(action: .return), returnKeyType: .default) == .function)
        #expect(KeyStyle(key: Key(action: .return), returnKeyType: .search) == .prominentReturn)
        #expect(KeyStyle(key: Key(action: .return), returnKeyType: .go) == .prominentReturn)
    }

    @Test func prominentReturnUsesWhiteText() {
        #expect(KeyStyle.prominentReturn.textColor == .white)
        #expect(KeyStyle.character.textColor == .label)
        #expect(KeyStyle.function.textColor == .label)
    }

    @Test func paletteResolvesDifferentlyInLightAndDark() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let dynamicColors: [UIColor] = [
            KeyPalette.characterKey,
            KeyPalette.functionKey,
            KeyboardChrome.background,
        ]
        for color in dynamicColors {
            #expect(color.resolvedColor(with: light) != color.resolvedColor(with: dark))
        }
    }

    @Test func alternateHighlightStandsOutAndStaysLegible() {
        // The popup's selected cell must be visibly distinct from unselected
        // cells (which use the character-key fill), with legible text, in
        // both schemes (issue #114).
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let highlight = KeyPalette.alternateHighlight.resolvedColor(with: traits)
            #expect(highlight != KeyPalette.characterKey.resolvedColor(with: traits))
            #expect(highlight != KeyPalette.alternateHighlightText.resolvedColor(with: traits))
        }
    }

    @Test func alternateHighlightSharesTheKeyboardAccent() {
        // One accent tier: the popup highlight and the prominent return key
        // must retint together under any future custom theme.
        #expect(KeyPalette.alternateHighlight == KeyPalette.prominentReturn)
    }

    @Test func textOnAccentFillsResolvesThroughOneSlot() {
        // Both the prominent return key's label and the highlighted alternates
        // cell's symbol must come from the SAME palette slot, so a future retint
        // of `accentText` moves them together (issue #114/#143). Reference
        // identity — not mere value equality — pins single-source-of-truth:
        // re-splitting either consumer into its own `UIColor.white` would still
        // compare equal but would break `===`.
        #expect(KeyStyle.prominentReturn.textColor === KeyPalette.accentText)
        #expect(KeyPalette.alternateHighlightText === KeyPalette.accentText)
        // And they render identically in both schemes.
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let accent = KeyPalette.accentText.resolvedColor(with: traits)
            #expect(KeyStyle.prominentReturn.textColor.resolvedColor(with: traits) == accent)
            #expect(KeyPalette.alternateHighlightText.resolvedColor(with: traits) == accent)
        }
    }

    @Test func pressedFillsDifferFromRestingFills() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        for style in [KeyStyle.character, .function, .prominentReturn] {
            let resting = style.fill(isPressed: false).resolvedColor(with: light)
            let pressed = style.fill(isPressed: true).resolvedColor(with: light)
            #expect(resting != pressed)
        }
    }

    // MARK: Compact-height metrics (iPhone landscape)

    @Test func compactMetricsAreShorterThanRegular() {
        let regular = KeyboardMetrics()
        let compact = KeyboardMetrics.compactHeight
        #expect(compact.totalHeight(rowCount: 5) < regular.totalHeight(rowCount: 5))
        // The tallest bundled layouts (5 total rows) must stay near the
        // system keyboard's landscape height, not fill the landscape screen.
        #expect(compact.totalHeight(rowCount: 5) <= 210)
    }

    @Test func metricsSelectionFollowsTheSizeClass() {
        #expect(KeyboardMetrics.metrics(forCompactHeight: true) == .compactHeight)
        #expect(KeyboardMetrics.metrics(forCompactHeight: false) == KeyboardMetrics())
    }

    // MARK: Bundled layouts

    @Test func everyBundledFunctionRowCarriesAReturnKey() throws {
        let layouts = LayoutStore().bundledLayouts()
        #expect(!layouts.isEmpty)
        for layout in layouts {
            let functionRow = try #require(
                layout.primaryArrangement?.functionRow,
                "\(layout.name) should have a shared function row")
            #expect(functionRow.keys.contains { $0.action == .return },
                    "\(layout.name) should offer a return key")
        }
    }
}
