//
//  ActiveLayoutResolverTests.swift
//  IPAKeyboardKitTests
//
//  The resolver is the exact code the extension runs to pick a layout, so it
//  must be total and never-blank: any inputs resolve to a renderable layout.
//

import Foundation
import Testing
@testable import IPAKeyboardKit

struct ActiveLayoutResolverTests {

    private func layout(_ name: String, locale: String) -> KeyboardLayout {
        KeyboardLayout(name: name, locale: locale,
                       rows: [KeyRow(keys: [Key(action: .insert("p"))])])
    }

    private func insertKeys(_ layout: KeyboardLayout) -> [Key] {
        layout.arrangements.flatMap(\.panels).flatMap(\.rows).flatMap(\.keys)
    }

    @Test func matchesActiveID() {
        let a = layout("A", locale: "en-US")
        let b = layout("B", locale: "fr-FR")
        #expect(ActiveLayoutResolver.resolve(activeID: b.id, in: [a, b]).id == b.id)
    }

    @Test func nilIDFallsBackToEnUS() {
        let other = layout("Other", locale: "fr-FR")
        let enUS = layout("English", locale: "en-US")
        #expect(ActiveLayoutResolver.resolve(activeID: nil, in: [other, enUS]).locale == "en-US")
    }

    @Test func unknownIDFallsBackToEnUS() {
        let other = layout("Other", locale: "fr-FR")
        let enUS = layout("English", locale: "en-US")
        #expect(ActiveLayoutResolver.resolve(activeID: UUID(), in: [other, enUS]).locale == "en-US")
    }

    @Test func withoutEnUSFallsBackToFirst() {
        let a = layout("A", locale: "fr-FR")
        let b = layout("B", locale: "de-DE")
        #expect(ActiveLayoutResolver.resolve(activeID: UUID(), in: [a, b]).id == a.id)
    }

    @Test func emptyListReturnsNonBlankFallback() {
        let resolved = ActiveLayoutResolver.resolve(activeID: UUID(), in: [])
        #expect(!insertKeys(resolved).isEmpty)
    }

    @Test func fallbackIsNeverBlank() {
        let hasInsert = insertKeys(ActiveLayoutResolver.fallback).contains {
            if case .insert = $0.action { return true } else { return false }
        }
        #expect(hasInsert)
    }
}
