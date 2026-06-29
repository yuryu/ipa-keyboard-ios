//
//  LayoutStoreTests.swift
//  IPAKeyboardKitTests
//
//  Tests LayoutStore behaviour visible without a provisioned App Group:
//  AppGroup.identifier, bundledLayouts auto-discovery, sort order, graceful
//  degradation when the shared container is unavailable, and the allLayouts
//  aggregate. Full save/load I/O requires a containerURL injection seam that
//  does not yet exist in LayoutStore — flagged as a testability gap below.
//

import Foundation
import Testing
@testable import IPAKeyboardKit

struct AppGroupTests {

    @Test func identifierMatchesEntitlements() {
        // Must stay in sync with both .entitlements files and AppGroup.identifier.
        #expect(AppGroup.identifier == "group.net.yuryu.IPAKeyboard")
    }
}

struct LayoutStoreTests {

    // MARK: bundledLayouts

    @Test func bundledLayoutsIsNonEmpty() {
        // Verifies LayoutStore auto-discovers layouts from the framework bundle.
        // (BundledLayoutTests.bundledLayoutsDecode also guards this, from the
        // data-contract perspective; here we're testing the store's discovery.)
        #expect(!LayoutStore().bundledLayouts().isEmpty)
    }

    @Test func bundledLayoutsAreSortedAlphabeticallyByName() {
        let names = LayoutStore().bundledLayouts().map(\.name)
        #expect(names == names.sorted())
    }

    @Test func bundledLayoutsAllHaveCurrentSchemaVersion() {
        let expected = KeyboardLayout.currentSchemaVersion
        let layouts = LayoutStore().bundledLayouts()
        #expect(layouts.allSatisfy { $0.schemaVersion == expected })
    }

    @Test func bundledLayoutsEachHaveAtLeastOneArrangement() {
        let layouts = LayoutStore().bundledLayouts()
        #expect(layouts.allSatisfy { !$0.arrangements.isEmpty })
    }

    @Test func bundledLayoutsEachHaveNonEmptyName() {
        let layouts = LayoutStore().bundledLayouts()
        #expect(layouts.allSatisfy { !$0.name.isEmpty })
    }

    @Test func bundledLayoutsEachHaveNonEmptyLocale() {
        let layouts = LayoutStore().bundledLayouts()
        #expect(layouts.allSatisfy { !$0.locale.isEmpty })
    }

    // MARK: Graceful degradation (App Group not provisioned in test environment)

    @Test func userLayoutsReturnsEmptyArrayWhenContainerUnavailable() {
        // The test runner carries no App Group entitlement, so containerURL
        // is nil; userLayouts() must return [] rather than crash.
        let store = LayoutStore()
        #expect(store.userLayouts().isEmpty)
    }

    @Test func saveThrowsWhenContainerUnavailable() throws {
        guard AppGroup.containerURL == nil else {
            // App Group is unexpectedly provisioned in this environment.
            // A full save test requires injecting a containerURL; skip here
            // and note it as a testability gap.
            return
        }
        let layout = KeyboardLayout(
            name: "Test", locale: "en-US",
            rows: [KeyRow(keys: [Key(action: .insert("p"))])]
        )
        // StoreError has one case, so type-matching is equivalent to value-matching.
        #expect(throws: LayoutStore.StoreError.self) {
            try LayoutStore().save(layout)
        }
    }

    @Test func deleteThrowsWhenContainerUnavailable() throws {
        guard AppGroup.containerURL == nil else { return }
        #expect(throws: LayoutStore.StoreError.self) {
            try LayoutStore().delete(id: UUID())
        }
    }

    // MARK: allLayouts

    @Test func allLayoutsContainsEveryBundledLayout() {
        let store = LayoutStore()
        let bundledIDs = Set(store.bundledLayouts().map(\.id))
        let allIDs = Set(store.allLayouts().map(\.id))
        #expect(bundledIDs.isSubset(of: allIDs))
    }

    @Test func allLayoutsCountIsAtLeastBundledCount() {
        let store = LayoutStore()
        #expect(store.allLayouts().count >= store.bundledLayouts().count)
    }

    // MARK: Testability gap note
    //
    // LayoutStore.userLayoutsDirectory is computed from AppGroup.containerURL,
    // which calls FileManager.containerURL(forSecurityApplicationGroupIdentifier:)
    // directly. There is no injection seam for the container URL, so it is
    // impossible to write a hermetic save → userLayouts → delete round-trip in
    // a test process that lacks the App Group entitlement.
    //
    // Recommended fix: add an optional `containerURL: URL?` parameter to
    // LayoutStore.init (defaulting to AppGroup.containerURL) so tests can pass
    // a temporary directory and exercise the full I/O path without provisioning.
}
