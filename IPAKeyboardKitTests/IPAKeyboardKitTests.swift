//
//  IPAKeyboardKitTests.swift
//  IPAKeyboardKitTests
//
//  Smoke test: verify the current schema version constant. Everything deeper
//  is covered by the domain-specific test files (bundled-layout discovery by
//  LayoutStoreTests.bundledLayoutsIsNonEmpty and
//  BundledLayoutTests.atLeastTwoBundledLayouts).
//

import Testing
@testable import IPAKeyboardKit

struct IPAKeyboardKitTests {

    @Test func currentSchemaVersionIsTwo() {
        #expect(KeyboardLayout.currentSchemaVersion == 2)
    }
}
