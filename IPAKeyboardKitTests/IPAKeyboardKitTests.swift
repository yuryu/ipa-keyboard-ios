//
//  IPAKeyboardKitTests.swift
//  IPAKeyboardKitTests
//
//  Smoke test: verify the current schema version constant and that the
//  framework bundle contains at least one decodable layout. Everything
//  deeper is covered by the domain-specific test files.
//

import Testing
@testable import IPAKeyboardKit

struct IPAKeyboardKitTests {

    @Test func currentSchemaVersionIsTwo() {
        #expect(KeyboardLayout.currentSchemaVersion == 2)
    }

    @Test func frameworkBundleContainsAtLeastOneLayout() {
        #expect(!LayoutStore().bundledLayouts().isEmpty)
    }
}
