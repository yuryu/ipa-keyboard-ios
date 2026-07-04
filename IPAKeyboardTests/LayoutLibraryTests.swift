//
//  LayoutLibraryTests.swift
//  IPAKeyboardTests
//
//  Hermetic coverage of LayoutLibrary's store-mutation pipeline (issue #82):
//  fork/delete/update/import all route through LayoutStore +
//  KeyboardPreferences, and the observed state (userLayouts, activeLayoutID,
//  hiddenSymbolsByLayout, containerAvailable, errorMessage) mirrors what
//  actually persisted. Each test builds an isolated world: a LayoutStore over
//  a temporary container directory (or nil, for the unprovisioned degraded
//  path) and a fresh UserDefaults suite — the same pattern as
//  LayoutDraftTests.
//
//  Not covered here: `LayoutLibrary.readPickedDocument(at:)`, the
//  `.fileImporter` completion's security-scoped-URL read. See its doc
//  comment in LayoutLibrary.swift for why that's deferred rather than given
//  an injection seam.
//

import Foundation
import Testing
import IPAKeyboardKit
@testable import IPAKeyboard

@MainActor
struct LayoutLibraryTests {

    // MARK: Fixtures

    /// One test's isolated storage world. `cleanUp()` removes what the test
    /// created; call it via `defer` right after `makeWorld`.
    private struct World {
        let library: LayoutLibrary
        let containerURL: URL?
        let defaults: UserDefaults
        let suiteName: String

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
            if let containerURL {
                try? FileManager.default.removeItem(at: containerURL)
            }
        }
    }

    /// A library over an injected temporary container (writable) or a nil
    /// container (the unprovisioned degraded state), plus isolated defaults.
    private func makeWorld(containerAvailable: Bool = true) -> World {
        let suiteName = "LayoutLibraryTests-\(UUID().uuidString)"
        let containerURL: URL? = containerAvailable
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent(suiteName, isDirectory: true)
            : nil
        let library = LayoutLibrary(
            store: LayoutStore(containerURL: containerURL),
            preferences: KeyboardPreferences(defaults: UserDefaults(suiteName: suiteName)!),
            environment: [:], // no UI-test launch import/reset hooks
            launchArguments: []) // isolate from the host runner's real arguments
        return World(
            library: library,
            containerURL: containerURL,
            defaults: UserDefaults(suiteName: suiteName)!,
            suiteName: suiteName)
    }

    /// A standalone user-owned layout the tests can import/save directly.
    private func makeUserLayout(name: String = "Fixture", derivedFrom: UUID? = nil) -> KeyboardLayout {
        KeyboardLayout(
            name: name,
            locale: "en-US",
            isBuiltIn: false,
            derivedFrom: derivedFrom,
            rows: [
                KeyRow(keys: [Key(action: .insert("ə")), Key(action: .insert("ɡ"))]),
                KeyRow(keys: [Key(action: .backspace)]),
            ])
    }

    /// Every `.insert` text reachable in `layout`'s primary arrangement.
    private func insertedTexts(in layout: KeyboardLayout) -> [String] {
        (layout.primaryArrangement?.panels ?? []).flatMap { panel in
            panel.rows.flatMap { row in
                row.keys.compactMap { key -> String? in
                    if case .insert(let text) = key.action { return text }
                    return nil
                }
            }
        }
    }

    // MARK: Initial load

    @Test func initialLoadPopulatesBuiltInsAndLeavesUserLayoutsEmpty() {
        let world = makeWorld()
        defer { world.cleanUp() }
        #expect(!world.library.builtInLayouts.isEmpty)
        #expect(world.library.userLayouts.isEmpty)
        #expect(world.library.activeLayoutID == nil)
        #expect(world.library.containerAvailable)
    }

    // MARK: fork

    @Test func forkSavesAnEditableCopyUnderUserLayouts() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        let source = try #require(world.library.builtInLayouts.first)

        world.library.fork(source)

        #expect(world.library.errorMessage == nil)
        let forked = try #require(world.library.userLayouts.first)
        #expect(forked.derivedFrom == source.id)
        #expect(forked.isBuiltIn == false)
        #expect(forked.name == "\(source.name) (Custom)")
        #expect(forked.id != source.id)
    }

    @Test func forkedLayoutGetsAHiddenSymbolsMirrorEntry() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        let source = try #require(world.library.builtInLayouts.first)

        world.library.fork(source)

        let forked = try #require(world.library.userLayouts.first)
        // reload() rebuilds the mirror over every current layout, so a
        // freshly forked layout has an (empty) entry immediately.
        #expect(world.library.hiddenSymbolsByLayout[forked.id] != nil)
        #expect(world.library.hiddenSymbols(for: forked).isEmpty)
    }

    @Test func forkWithoutSharedStorageExplainsTheDegradedStateAndPersistsNothing() throws {
        let world = makeWorld(containerAvailable: false)
        defer { world.cleanUp() }
        let source = try #require(world.library.builtInLayouts.first)

        world.library.fork(source)

        #expect(world.library.errorMessage?.contains("save your copy") == true)
        #expect(world.library.errorMessage?.contains("shared storage") == true)
        #expect(!world.library.containerAvailable)
        #expect(world.library.userLayouts.isEmpty)
    }

    // MARK: delete

    @Test func deleteRemovesAUserLayoutAndClearsItsActiveSelectionAndHiddenSymbols() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        let source = try #require(world.library.builtInLayouts.first)
        world.library.fork(source)
        let forked = try #require(world.library.userLayouts.first)

        world.library.setActive(forked)
        world.library.setHiddenSymbols(["ə"], for: forked)
        #expect(world.library.activeLayoutID == forked.id)
        #expect(world.library.hiddenSymbols(for: forked) == ["ə"])

        world.library.delete(forked)

        #expect(world.library.errorMessage == nil)
        #expect(world.library.userLayouts.isEmpty)
        #expect(world.library.activeLayoutID == nil)
        #expect(world.library.hiddenSymbolsByLayout[forked.id] == nil)
    }

    @Test func deletingALayoutLeavesAnUnrelatedActiveSelectionUntouched() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        let sourceA = try #require(world.library.builtInLayouts.first)
        let sourceB = try #require(world.library.builtInLayouts.dropFirst().first)
        world.library.fork(sourceA)
        world.library.fork(sourceB)
        let a = try #require(world.library.userLayouts.first { $0.derivedFrom == sourceA.id })
        let b = try #require(world.library.userLayouts.first { $0.derivedFrom == sourceB.id })

        world.library.setActive(a)
        world.library.delete(b)

        #expect(world.library.activeLayoutID == a.id)
        #expect(world.library.userLayouts.map(\.id) == [a.id])
    }

    @Test func deleteWithoutSharedStorageExplainsTheDegradedState() {
        let world = makeWorld(containerAvailable: false)
        defer { world.cleanUp() }

        world.library.delete(makeUserLayout())

        #expect(world.library.errorMessage?.contains("delete this layout") == true)
        #expect(!world.library.containerAvailable)
    }

    // MARK: update

    @Test func updatePersistsEditsToAnExistingUserLayoutAndReloads() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        let source = try #require(world.library.builtInLayouts.first)
        world.library.fork(source)
        var forked = try #require(world.library.userLayouts.first)
        forked.name = "Renamed Fork"

        try world.library.update(forked)

        let saved = try #require(world.library.userLayouts.first { $0.id == forked.id })
        #expect(saved.name == "Renamed Fork")
    }

    @Test func updateRefusesBuiltInLayouts() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        let builtIn = try #require(world.library.builtInLayouts.first)
        #expect(builtIn.isBuiltIn)

        #expect(throws: LayoutLibrary.UpdateError.self) {
            try world.library.update(builtIn)
        }
        // Copy-on-write is enforced here too: nothing was written.
        #expect(world.library.userLayouts.isEmpty)
    }

    @Test func updateWithoutSharedStorageThrowsAndFlipsContainerAvailable() {
        let world = makeWorld(containerAvailable: false)
        defer { world.cleanUp() }

        #expect(throws: LayoutStore.StoreError.self) {
            try world.library.update(makeUserLayout())
        }
        #expect(!world.library.containerAvailable)
    }

    // MARK: importLayout(data:)

    @Test func importLayoutPersistsAValidDocumentAndAppearsInUserLayouts() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        let original = makeUserLayout(name: "Imported Fixture")
        let data = try LayoutTransfer.exportData(for: original)

        world.library.importLayout(data: data)

        #expect(world.library.errorMessage == nil)
        let imported = try #require(world.library.userLayouts.first { $0.id == original.id })
        #expect(imported.name == "Imported Fixture")
        #expect(imported.isBuiltIn == false)
    }

    @Test func importLayoutSurfacesAMalformedDocumentError() {
        let world = makeWorld()
        defer { world.cleanUp() }

        world.library.importLayout(data: Data("{ this is not JSON".utf8))

        #expect(world.library.errorMessage?.contains("import this layout") == true)
        #expect(world.library.errorMessage?.contains("valid keyboard layout") == true)
        #expect(world.library.userLayouts.isEmpty)
    }

    @Test func importLayoutWithoutSharedStorageExplainsTheDegradedState() throws {
        let world = makeWorld(containerAvailable: false)
        defer { world.cleanUp() }
        let data = try LayoutTransfer.exportData(for: makeUserLayout())

        world.library.importLayout(data: data)

        #expect(world.library.errorMessage?.contains("shared storage") == true)
        #expect(!world.library.containerAvailable)
    }

    // MARK: Shared error-state reset

    @Test func errorMessageClearsAfterASubsequentSuccessfulOperation() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        world.library.importLayout(data: Data("{ bad".utf8))
        #expect(world.library.errorMessage != nil)

        let source = try #require(world.library.builtInLayouts.first)
        world.library.fork(source)

        #expect(world.library.errorMessage == nil)
    }

    // MARK: Resolver mirroring

    @Test func resolvedActiveLayoutIDDefaultsToEnUSWhenNoSelectionIsMade() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        let enUS = try #require(world.library.builtInLayouts.first { $0.locale == "en-US" })

        #expect(world.library.resolvedActiveLayoutID == enUS.id)
        #expect(world.library.activeLayout.id == enUS.id)
    }

    @Test func setActiveUpdatesTheResolvedSelectionAndTheActiveLayout() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        let target = try #require(world.library.builtInLayouts.first { $0.locale == "und" })

        world.library.setActive(target)

        #expect(world.library.activeLayoutID == target.id)
        #expect(world.library.resolvedActiveLayoutID == target.id)
        #expect(world.library.activeLayout.id == target.id)
    }

    @Test func resolvedActiveLayoutIDMatchesActiveLayoutResolverDirectly() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        let source = try #require(world.library.builtInLayouts.first)
        world.library.fork(source) // adds a user layout into the resolver's pool
        let target = try #require(world.library.builtInLayouts.first { $0.locale == "und" })
        world.library.setActive(target)

        let expected = ActiveLayoutResolver.resolve(
            activeID: world.library.activeLayoutID,
            in: world.library.builtInLayouts + world.library.userLayouts
        ).id
        #expect(world.library.resolvedActiveLayoutID == expected)
    }

    @Test func activeLayoutAppliesTheActiveLayoutsHiddenSymbols() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        let original = makeUserLayout(name: "Hideable Fixture")
        world.library.importLayout(data: try LayoutTransfer.exportData(for: original))
        let imported = try #require(world.library.userLayouts.first { $0.id == original.id })

        world.library.setActive(imported)
        world.library.setHiddenSymbols(["ə"], for: imported)

        let rendered = world.library.activeLayout
        #expect(rendered.id == imported.id)
        let texts = insertedTexts(in: rendered)
        #expect(!texts.contains("ə"))
        #expect(texts.contains("ɡ"))
        // The saved/observed layout itself is untouched — curation is
        // reversible and lives only in KeyboardPreferences.
        #expect(insertedTexts(in: imported).contains("ə"))
    }

    // MARK: Hidden-symbols mirror

    @Test func hiddenSymbolsMirrorRoundTripsAndPersistsAcrossLibraryInstances() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        let layout = try #require(world.library.builtInLayouts.first)

        world.library.setHiddenSymbols(["ə", "ɡ"], for: layout)
        #expect(world.library.hiddenSymbols(for: layout) == ["ə", "ɡ"])

        // A fresh library over the same storage (a relaunch) reads the same set.
        let relaunched = LayoutLibrary(
            store: LayoutStore(containerURL: world.containerURL),
            preferences: KeyboardPreferences(defaults: world.defaults),
            environment: [:],
            launchArguments: []) // isolate from the host runner's real arguments
        #expect(relaunched.hiddenSymbols(for: layout) == ["ə", "ɡ"])
    }

    @Test func clearingTheHiddenSymbolsMirrorAffectsOnlyThatLayout() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        let a = try #require(world.library.builtInLayouts.first)
        let b = try #require(world.library.builtInLayouts.dropFirst().first)

        world.library.setHiddenSymbols(["ə"], for: a)
        world.library.setHiddenSymbols(["t"], for: b)
        world.library.setHiddenSymbols([], for: a)

        #expect(world.library.hiddenSymbols(for: a).isEmpty)
        #expect(world.library.hiddenSymbols(for: b) == ["t"])
    }
}
