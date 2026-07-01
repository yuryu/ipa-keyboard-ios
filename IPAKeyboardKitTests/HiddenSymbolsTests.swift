//
//  HiddenSymbolsTests.swift
//  IPAKeyboardKitTests
//
//  applyingHiddenSymbols is the per-layout curation the extension applies after
//  resolving the active layout. It must remove only .insert keys (never a
//  required affordance), prune matching long-press alternates, drop emptied
//  rows, and — composed with the globe filter — never blank the keyboard.
//

import Foundation
import Testing
@testable import IPAKeyboardKit

struct HiddenSymbolsTests {

    /// One arrangement: a panel (with a switchKey) of two symbol rows plus a
    /// shared globe/space/backspace bar. "p" carries an aspirated alternate.
    private func sample() -> KeyboardLayout {
        KeyboardLayout(
            name: "Test", locale: "en-US",
            arrangements: [
                Arrangement(
                    name: "Split",
                    panels: [
                        Panel(
                            name: "IPA",
                            switchKey: Key(action: .switchPanel("More")),
                            rows: [
                                KeyRow(keys: [
                                    Key(action: .insert("p"), alternates: [Key(action: .insert("pʰ"))]),
                                    Key(action: .insert("b")),
                                ]),
                                KeyRow(keys: [Key(action: .insert("t")), Key(action: .insert("d"))]),
                            ]
                        )
                    ],
                    functionRow: KeyRow(keys: [
                        Key(action: .nextKeyboard),
                        Key(action: .space, widthFactor: 3),
                        Key(action: .backspace),
                    ])
                )
            ]
        )
    }

    private func insertTexts(_ layout: KeyboardLayout) -> [String] {
        layout.arrangements.flatMap(\.panels).flatMap(\.rows).flatMap(\.keys).compactMap {
            if case .insert(let t) = $0.action { return t } else { return nil }
        }
    }

    @Test func emptyHiddenSetIsIdentity() {
        let layout = sample()
        #expect(layout.applyingHiddenSymbols([]) == layout)
    }

    @Test func removesExactlyTheMatchingInsertKeys() {
        // Hide "b" and "t"; the other main keys ("p", "d") survive.
        let filtered = sample().applyingHiddenSymbols(["b", "t"])
        #expect(insertTexts(filtered).sorted() == ["d", "p"])
    }

    @Test func prunesAMatchingAlternateButKeepsItsHostKey() {
        let filtered = sample().applyingHiddenSymbols(["pʰ"])
        let p = filtered.arrangements.flatMap(\.panels).flatMap(\.rows).flatMap(\.keys)
            .first { $0.action == .insert("p") }
        #expect(p != nil)
        #expect(p?.alternates.isEmpty == true)
    }

    @Test func neverRemovesRequiredAffordances() {
        // Only .insert keys are eligible, so even a hidden set naming the space
        // or globe glyphs leaves the bottom bar and the panel switch intact.
        let filtered = sample().applyingHiddenSymbols(["p", "b", "t", "d", " ", "🌐"])
        let fn = filtered.primaryArrangement?.functionRow
        #expect(fn?.keys.contains { $0.action == .nextKeyboard } == true)
        #expect(fn?.keys.contains { $0.action == .space } == true)
        #expect(fn?.keys.contains { $0.action == .backspace } == true)
        #expect(filtered.primaryArrangement?.primaryPanel?.switchKey?.action == .switchPanel("More"))
    }

    @Test func dropsRowsLeftWithNoInteractiveKey() {
        // Hiding both keys of the second row removes that row entirely.
        let filtered = sample().applyingHiddenSymbols(["t", "d"])
        #expect(filtered.primaryArrangement?.primaryPanel?.rows.count == 1)
        #expect(insertTexts(filtered).sorted() == ["b", "p"])
    }

    @Test func hidingEveryInsertLeavesAWorkingBottomBarNotABlankKeyboard() {
        let layout = sample()
        let allInserts = Set(
            layout.arrangements.flatMap(\.panels).flatMap(\.rows).flatMap(\.keys)
                .flatMap { [$0] + $0.alternates }
                .compactMap { key -> String? in
                    if case .insert(let t) = key.action { return t } else { return nil }
                }
        )
        let curated = layout.applyingHiddenSymbols(allInserts)
        #expect(curated.primaryArrangement?.primaryPanel?.rows.isEmpty == true)
        #expect(curated.primaryArrangement?.functionRow != nil)
        #expect((curated.primaryArrangement?.totalRowCount ?? 0) >= 1)
    }

    @Test func composedWithGlobeFilterKeepsRequiredKeys() {
        // The exact pipeline the extension runs: hide symbols, then drop the
        // globe key. Insertion affordances and the panel switch still work.
        let curated = sample().applyingHiddenSymbols(["p", "b", "t", "d", "pʰ"])
        let final = curated.filteringKeys { $0.action == .nextKeyboard }
        let fn = final.primaryArrangement?.functionRow
        #expect(fn?.keys.contains { $0.action == .nextKeyboard } == false)
        #expect(fn?.keys.contains { $0.action == .space } == true)
        #expect(fn?.keys.contains { $0.action == .backspace } == true)
        #expect(final.primaryArrangement?.primaryPanel?.switchKey != nil)
    }

    @Test func curatingTheBundledGenericLayoutNeverBlanksIt() {
        // End-to-end against real data: hide a handful from ipa-full and confirm
        // the bottom bar and panel switching survive.
        let layouts = LayoutStore().bundledLayouts()
        guard let full = layouts.first(where: { $0.locale == "und" }) else { return }
        let curated = full.applyingHiddenSymbols(["p", "t", "k", "i", "u"])
        #expect(curated.primaryArrangement?.functionRow?.keys.contains { $0.action == .nextKeyboard } == true)
        #expect(curated.primaryArrangement?.primaryPanel?.switchKey != nil)
        #expect((curated.primaryArrangement?.totalRowCount ?? 0) >= 1)
    }
}
