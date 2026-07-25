//
//  LayoutStoreTests.swift
//  IPAKeyboardKitTests
//
//  Tests LayoutStore behaviour visible without a provisioned App Group:
//  AppGroup.identifier, bundledLayouts auto-discovery, sort order, graceful
//  degradation when the shared container is unavailable, and the allLayouts
//  aggregate. Full save/userLayouts/delete I/O is exercised hermetically via
//  LayoutStore's `containerURL` injection seam (issue #59), which points the
//  store at a throwaway temp directory instead of the real (unprovisioned in
//  this test environment) App Group container.
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
    //
    // These exercise LayoutStore()'s *default* containerURL argument, which
    // resolves to the real AppGroup.containerURL — so they only run where
    // that container is nil, via .enabled(if:), and report a visible skip
    // (never a silent pass) in a provisioned environment (issue #188). The
    // `containerURL: nil`-injected tests further down assert the identical
    // behaviour unconditionally, regardless of the environment's real
    // provisioning state.

    @Test(.enabled(if: AppGroup.containerURL == nil,
                   "App Group provisioned; userLayoutsReturnsEmptyArrayWhenContainerIsNil covers this via nil injection"))
    func userLayoutsReturnsEmptyArrayWhenContainerUnavailable() {
        // The runner carries no App Group entitlement, so containerURL is
        // nil; userLayouts() must return [] rather than crash.
        let store = LayoutStore()
        #expect(store.userLayouts().isEmpty)
    }

    @Test(.enabled(if: AppGroup.containerURL == nil,
                   "App Group provisioned; saveThrowsWhenContainerIsNil covers this via nil injection"))
    func saveThrowsWhenContainerUnavailable() {
        let layout = KeyboardLayout(
            name: "Test", locale: "en-US",
            rows: [KeyRow(keys: [Key(action: .insert("p"))])]
        )
        // StoreError has one case, so type-matching is equivalent to value-matching.
        #expect(throws: LayoutStore.StoreError.self) {
            try LayoutStore().save(layout)
        }
    }

    @Test(.enabled(if: AppGroup.containerURL == nil,
                   "App Group provisioned; deleteThrowsWhenContainerIsNil covers this via nil injection"))
    func deleteThrowsWhenContainerUnavailable() {
        #expect(throws: LayoutStore.StoreError.self) {
            try LayoutStore().delete(id: UUID())
        }
    }

    @Test(.enabled(if: AppGroup.containerURL == nil,
                   "App Group provisioned; deleteAllUserLayoutsThrowsWhenContainerIsNil covers this via nil injection"))
    func deleteAllUserLayoutsThrowsWhenContainerUnavailable() {
        // Same store contract as save/delete: a missing container throws
        // rather than silently no-ops, so callers decide how to react
        // (the reset hook treats it as the expected pre-provisioning case).
        #expect(throws: LayoutStore.StoreError.self) {
            try LayoutStore().deleteAllUserLayouts()
        }
    }

    // MARK: Graceful degradation (explicit `containerURL: nil` injection)
    //
    // Deterministic counterparts to the guarded tests above: injecting `nil`
    // directly exercises the degraded path regardless of whether this
    // environment's real App Group happens to be provisioned.

    @Test func userLayoutsReturnsEmptyArrayWhenContainerIsNil() {
        #expect(LayoutStore(containerURL: nil).userLayouts().isEmpty)
    }

    @Test func saveThrowsWhenContainerIsNil() {
        let layout = KeyboardLayout(
            name: "Test", locale: "en-US",
            rows: [KeyRow(keys: [Key(action: .insert("p"))])]
        )
        #expect(throws: LayoutStore.StoreError.self) {
            try LayoutStore(containerURL: nil).save(layout)
        }
    }

    @Test func deleteThrowsWhenContainerIsNil() {
        #expect(throws: LayoutStore.StoreError.self) {
            try LayoutStore(containerURL: nil).delete(id: UUID())
        }
    }

    @Test func deleteAllUserLayoutsThrowsWhenContainerIsNil() {
        #expect(throws: LayoutStore.StoreError.self) {
            try LayoutStore(containerURL: nil).deleteAllUserLayouts()
        }
    }

    @Test func allLayoutsIsBundledOnlyWhenContainerIsNil() {
        let store = LayoutStore(containerURL: nil)
        #expect(store.allLayouts().map(\.id) == store.bundledLayouts().map(\.id))
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
}

/// Hermetic exercise of LayoutStore's persisting half (issue #59): each test
/// injects a throwaway temp directory as the store's `containerURL`, so the
/// real save/userLayouts/delete/import I/O path runs without App Group
/// provisioning and without touching any other test's state.
struct LayoutStoreHermeticContainerTests {

    /// A directory unique to this test, standing in for the App Group
    /// container root (LayoutStore appends its own "Layouts" subdirectory
    /// inside it). Not created up front — `save` is responsible for that,
    /// matching real container behavior. Removed via the caller's `defer`.
    private func makeTempContainerURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LayoutStoreHermeticContainerTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeLayout(name: String = "Hermetic ɡː", id: UUID = UUID()) -> KeyboardLayout {
        KeyboardLayout(
            id: id, name: name, locale: "en-US",
            rows: [KeyRow(keys: [Key(action: .insert("\u{0261}"))])])
    }

    // MARK: save / userLayouts / delete

    @Test func saveUserLayoutsDeleteRoundTrips() throws {
        let container = makeTempContainerURL()
        defer { try? FileManager.default.removeItem(at: container) }
        let store = LayoutStore(containerURL: container)

        #expect(store.userLayouts().isEmpty)

        let layout = makeLayout()
        try store.save(layout)

        let saved = store.userLayouts()
        #expect(saved.count == 1)
        #expect(saved.first == layout)

        try store.delete(id: layout.id)
        #expect(store.userLayouts().isEmpty)
    }

    @Test func saveWritesTheExpectedFileUnderALayoutsSubdirectory() throws {
        let container = makeTempContainerURL()
        defer { try? FileManager.default.removeItem(at: container) }
        let store = LayoutStore(containerURL: container)
        let layout = makeLayout()
        try store.save(layout)

        let expectedURL = container
            .appendingPathComponent("Layouts", isDirectory: true)
            .appendingPathComponent("\(layout.id.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: expectedURL.path))
    }

    @Test func savingTwiceWithTheSameIDOverwritesRatherThanDuplicates() throws {
        let container = makeTempContainerURL()
        defer { try? FileManager.default.removeItem(at: container) }
        let store = LayoutStore(containerURL: container)
        let id = UUID()

        try store.save(makeLayout(name: "Original", id: id))
        try store.save(makeLayout(name: "Renamed", id: id))

        let saved = store.userLayouts()
        #expect(saved.count == 1)
        #expect(saved.first?.name == "Renamed")
    }

    @Test func deletingAnUnknownIDInAHermeticContainerIsANoOp() throws {
        let container = makeTempContainerURL()
        defer { try? FileManager.default.removeItem(at: container) }
        let store = LayoutStore(containerURL: container)
        try store.save(makeLayout())

        try store.delete(id: UUID()) // does not throw, does not remove the saved layout
        #expect(store.userLayouts().count == 1)
    }

    // MARK: deleteAllUserLayouts (the UI-test reset hook, issue #27)

    @Test func deleteAllUserLayoutsRemovesEverySavedLayout() throws {
        let container = makeTempContainerURL()
        defer { try? FileManager.default.removeItem(at: container) }
        let store = LayoutStore(containerURL: container)
        try store.save(makeLayout(name: "First"))
        try store.save(makeLayout(name: "Second"))

        try store.deleteAllUserLayouts()
        #expect(store.userLayouts().isEmpty)
        // Bundled layouts are untouched — only the user half is reset.
        #expect(store.allLayouts().map(\.id) == store.bundledLayouts().map(\.id))
    }

    @Test func deleteAllUserLayoutsIsANoOpBeforeTheLayoutsDirectoryExists() throws {
        let container = makeTempContainerURL()
        defer { try? FileManager.default.removeItem(at: container) }
        // No save has run, so the "Layouts" subdirectory was never created —
        // the documented nothing-to-reset case must not throw.
        try LayoutStore(containerURL: container).deleteAllUserLayouts()
        #expect(LayoutStore(containerURL: container).userLayouts().isEmpty)
    }

    @Test func allLayoutsCombinesBundledAndHermeticallySavedUserLayouts() throws {
        let container = makeTempContainerURL()
        defer { try? FileManager.default.removeItem(at: container) }
        let store = LayoutStore(containerURL: container)
        let layout = makeLayout()
        try store.save(layout)

        let all = store.allLayouts()
        #expect(all.count == store.bundledLayouts().count + 1)
        #expect(all.contains { $0.id == layout.id })
    }

    // MARK: importLayout(from:) save path

    @Test func importLayoutPersistsHermeticallyAndAppearsInUserLayouts() throws {
        let container = makeTempContainerURL()
        defer { try? FileManager.default.removeItem(at: container) }
        let store = LayoutStore(containerURL: container)

        let original = makeLayout(name: "Imported ɡː")
        let data = try LayoutTransfer.exportData(for: original)

        let imported = try store.importLayout(from: data)
        #expect(imported.id == original.id)
        #expect(imported.isBuiltIn == false)

        let userLayouts = store.userLayouts()
        #expect(userLayouts.count == 1)
        #expect(userLayouts.first?.id == original.id)
        #expect(userLayouts.first?.arrangements == original.arrangements)
    }

    @Test func importLayoutMintsFreshIDWhenItCollidesWithAnAlreadySavedUserLayout() throws {
        let container = makeTempContainerURL()
        defer { try? FileManager.default.removeItem(at: container) }
        let store = LayoutStore(containerURL: container)

        let existing = makeLayout(name: "Existing")
        try store.save(existing)

        let data = try LayoutTransfer.exportData(for: existing)
        let imported = try store.importLayout(from: data)

        #expect(imported.id != existing.id)
        #expect(store.userLayouts().count == 2)
    }

    // MARK: userLayouts() skip-and-continue over undecodable files (issue #164)

    @Test func userLayoutsSkipsUndecodableFilesButStillReturnsValidSiblings() throws {
        let container = makeTempContainerURL()
        defer { try? FileManager.default.removeItem(at: container) }
        let store = LayoutStore(containerURL: container)

        // One valid layout, saved through the real path (which also creates
        // the "Layouts" subdirectory the bad files are planted into).
        let valid = makeLayout(name: "Survivor ɡː")
        try store.save(valid)

        // Two undecodable siblings, each named <uuid>.json so the directory
        // listing's pathExtension filter picks them up: raw non-JSON bytes
        // (a user hand-edit gone wrong) and a well-formed document whose
        // schemaVersion is newer than supported (rejected by KeyboardLayout's
        // decoder — see SchemaV2Tests.newerSchemaVersionIsRejected…).
        let layoutsDir = container.appendingPathComponent("Layouts", isDirectory: true)
        try Data("{ not json".utf8).write(
            to: layoutsDir.appendingPathComponent("\(UUID().uuidString).json"))
        let futureDoc = """
        {
          "schemaVersion": 99,
          "name": "From the future",
          "locale": "en-US",
          "arrangements": []
        }
        """
        try Data(futureDoc.utf8).write(
            to: layoutsDir.appendingPathComponent("\(UUID().uuidString).json"))

        // Skip: neither bad file appears in the listing. Keep going: the
        // valid sibling still loads — one corrupt file must never throw and
        // wipe the entire user-layout listing.
        let loaded = store.userLayouts()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == valid.id)
    }
}
