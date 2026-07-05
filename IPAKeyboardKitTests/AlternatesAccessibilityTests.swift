//
//  AlternatesAccessibilityTests.swift
//  IPAKeyboardKitTests
//
//  Verifies the VoiceOver-facing view of a key's alternates (issue #114):
//  one custom action per alternate, in popup order, named by the spoken
//  label where present, committing the same `KeyAction` a slide-and-release
//  on the popup cell would.
//

import Testing
@testable import IPAKeyboardKit

struct AlternatesAccessibilityTests {

    @Test func keysWithoutAlternatesExposeNoActions() {
        let insertActions = AlternatesAccessibility.customActions(for: .insert("ə"))
        let backspaceActions = AlternatesAccessibility.customActions(for: Key(action: .backspace))
        #expect(insertActions.isEmpty)
        #expect(backspaceActions.isEmpty)
    }

    @Test func oneActionPerAlternateInPopupOrderCommittingItsAction() {
        // ɹ U+0279 with its bundled-style alternates.
        let key = Key.insert("ɹ", alternates: [.insert("r"), .insert("ɾ")])
        let actions = AlternatesAccessibility.customActions(for: key).map(\.action)
        #expect(actions == [.insert("r"), .insert("ɾ")])
    }

    @Test func actionNamesPreferTheSpokenLabel() {
        let key = Key.insert("p", alternates: [
            .insert("pʰ", accessibilityLabel: "aspirated p"),
            .insert("p̚"),
        ])
        let names = AlternatesAccessibility.customActions(for: key).map(\.name)
        #expect(names == ["aspirated p", "p̚"])
    }

    @Test func nameFallbackHonorsACustomDisplayLabel() {
        let alternate = Key(action: .insert("ː"), label: "length")
        let key = Key.insert("ː", alternates: [alternate])
        let names = AlternatesAccessibility.customActions(for: key).map(\.name)
        #expect(names == ["length"])
    }

    @Test func actionIdentityFollowsTheAlternateKey() {
        let alternate = Key.insert("pʰ")
        let key = Key.insert("p", alternates: [alternate])
        let ids = AlternatesAccessibility.customActions(for: key).map(\.id)
        #expect(ids == [alternate.id])
    }

    /// Every alternate across the bundled layouts must yield a custom action
    /// with a non-empty spoken name — a silent action is unusable under
    /// VoiceOver.
    @Test func everyBundledAlternateSpeaksANonEmptyName() {
        let layouts = LayoutStore().bundledLayouts()
        #expect(!layouts.isEmpty)
        var keysWithAlternates = 0
        for layout in layouts {
            for arrangement in layout.arrangements {
                var rows = arrangement.panels.flatMap(\.rows)
                if let functionRow = arrangement.functionRow { rows.append(functionRow) }
                let keys = rows.flatMap(\.keys) + arrangement.panels.compactMap(\.switchKey)
                for key in keys where !key.alternates.isEmpty {
                    keysWithAlternates += 1
                    let actions = AlternatesAccessibility.customActions(for: key)
                    #expect(actions.count == key.alternates.count,
                            "\(layout.name): \(key.displayLabel) should expose every alternate")
                    for action in actions {
                        let isNameEmpty = action.name.isEmpty
                        #expect(!isNameEmpty,
                                "\(layout.name): an alternate of \(key.displayLabel) has no spoken name")
                    }
                }
            }
        }
        #expect(keysWithAlternates > 0, "bundled layouts should exercise the alternates path")
    }
}
