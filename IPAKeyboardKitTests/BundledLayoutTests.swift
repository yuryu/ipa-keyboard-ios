//
//  BundledLayoutTests.swift
//  IPAKeyboardKitTests
//
//  Guards the JSON↔model contract the renderer depends on: the bundled
//  defaults must decode, and every key must produce a glyph to render.
//

import Testing
@testable import IPAKeyboardKit

struct BundledLayoutTests {

    @Test func bundledLayoutsDecode() {
        let layouts = LayoutStore().bundledLayouts()
        #expect(!layouts.isEmpty)
        #expect(layouts.allSatisfy { $0.isBuiltIn })
    }

    @Test func enUSIsPresentWithRows() throws {
        let layouts = LayoutStore().bundledLayouts()
        let enUS = try #require(layouts.first { $0.locale == "en-US" })
        #expect(!enUS.rows.isEmpty)
    }

    @Test func everyCharacterKeyHasADisplayLabel() {
        for layout in LayoutStore().bundledLayouts() {
            for row in layout.rows {
                for key in row.keys {
                    if case .insert = key.action {
                        #expect(!key.displayLabel.isEmpty,
                                "insert key with empty label in \(layout.locale)")
                    }
                }
            }
        }
    }
}
