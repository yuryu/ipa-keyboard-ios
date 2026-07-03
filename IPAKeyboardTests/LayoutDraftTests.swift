//
//  LayoutDraftTests.swift
//  IPAKeyboardTests
//
//  LayoutDraft (issue #6) owns the key editor's working copy: edits mutate
//  only the copy (the saved original is untouched), `hasChanges` is value
//  equality against that original, Save commits the whole document through
//  LayoutLibrary.update → LayoutStore, and reset-to-default re-adopts the
//  source built-in's content while keeping the fork's identity.
//
//  Each test builds an isolated world: a LayoutStore over a temporary
//  container directory (or nil, for the unprovisioned degraded path — the
//  containerURL seam added for issue #59 / PR #76) and a fresh UserDefaults suite, so
//  nothing touches real shared storage.
//

import Foundation
import Testing
import IPAKeyboardKit
@testable import IPAKeyboard

@MainActor
struct LayoutDraftTests {

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
        let suiteName = "LayoutDraftTests-\(UUID().uuidString)"
        let containerURL: URL? = containerAvailable
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent(suiteName, isDirectory: true)
            : nil
        let library = LayoutLibrary(
            store: LayoutStore(containerURL: containerURL),
            preferences: KeyboardPreferences(defaults: UserDefaults(suiteName: suiteName)!),
            environment: [:]) // no UI-test launch import
        return World(
            library: library,
            containerURL: containerURL,
            defaults: UserDefaults(suiteName: suiteName)!,
            suiteName: suiteName)
    }

    /// A user-owned layout the draft can legally edit and save.
    private func makeUserLayout(derivedFrom: UUID? = nil) -> KeyboardLayout {
        KeyboardLayout(
            name: "Draft Fixture",
            locale: "en-US",
            isBuiltIn: false,
            derivedFrom: derivedFrom,
            rows: [
                KeyRow(keys: [Key(action: .insert("ə")), Key(action: .insert("ɡ"))]),
                KeyRow(keys: [Key(action: .backspace)]),
            ])
    }

    // MARK: Working-copy semantics

    @Test func freshDraftIsCleanAndMirrorsTheOriginal() {
        let world = makeWorld()
        defer { world.cleanUp() }
        let layout = makeUserLayout()
        let draft = LayoutDraft(layout: layout, library: world.library)

        #expect(draft.workingCopy == layout)
        #expect(draft.original == layout)
        #expect(!draft.hasChanges)
        #expect(draft.saveErrorMessage == nil)
    }

    @Test func editsMutateOnlyTheWorkingCopy() {
        let world = makeWorld()
        defer { world.cleanUp() }
        let layout = makeUserLayout()
        let draft = LayoutDraft(layout: layout, library: world.library)

        draft.addRow()
        draft.appendKey(Key(action: .insert("ʃ")), toRowAt: 1)

        #expect(draft.rows.count == 3)
        #expect(draft.keys(inRowAt: 1).count == 2)
        // The saved original is untouched — Cancel can always discard.
        #expect(draft.original == layout)
        #expect(draft.workingCopy != layout)
    }

    // MARK: Dirty tracking

    @Test func editingMarksDirty() {
        let world = makeWorld()
        defer { world.cleanUp() }
        let draft = LayoutDraft(layout: makeUserLayout(), library: world.library)

        draft.addRow()
        #expect(draft.hasChanges)
    }

    @Test func editsThatRestoreTheOriginalClearDirty() {
        let world = makeWorld()
        defer { world.cleanUp() }
        let draft = LayoutDraft(layout: makeUserLayout(), library: world.library)

        // Dirty tracking is value equality, not an edit counter: an edit that
        // is later undone by an inverse edit leaves the draft clean.
        draft.appendKey(Key(action: .insert("θ")), toRowAt: 1)
        #expect(draft.hasChanges)
        draft.removeKeys(atOffsets: IndexSet(integer: 1), inRowAt: 1)
        #expect(!draft.hasChanges)
    }

    // MARK: Panel addressing

    @Test func outOfRangePanelIndexIsClampedNotCrashing() {
        let world = makeWorld()
        defer { world.cleanUp() }
        let draft = LayoutDraft(layout: makeUserLayout(), library: world.library)
        let panelRows = draft.rows

        draft.panelIndex = 99 // clamped down to the last panel
        #expect(draft.rows == panelRows)

        draft.panelIndex = -3 // clamped up to the first panel
        #expect(draft.rows == panelRows)
    }

    // MARK: Save

    @Test func saveCommitsTheWorkingCopyThroughTheLibrary() {
        let world = makeWorld()
        defer { world.cleanUp() }
        let layout = makeUserLayout()
        let draft = LayoutDraft(layout: layout, library: world.library)
        draft.addRow()

        #expect(draft.save())
        #expect(draft.saveErrorMessage == nil)

        // The whole document landed in the store (library reloads on update).
        let saved = world.library.userLayouts.first { $0.id == layout.id }
        #expect(saved == draft.workingCopy)
        #expect(saved?.primaryArrangement?.panels.first?.rows.count == 3)
    }

    @Test func saveRefusesBuiltInsAndSurfacesAnError() {
        let world = makeWorld()
        defer { world.cleanUp() }
        var layout = makeUserLayout()
        layout.isBuiltIn = true // copy-on-write: built-ins never reach the store
        let draft = LayoutDraft(layout: layout, library: world.library)
        draft.addRow()

        #expect(!draft.save())
        #expect(draft.saveErrorMessage?.hasPrefix("Couldn’t save your changes.") == true)
        // Nothing was persisted.
        #expect(world.library.userLayouts.isEmpty)
    }

    @Test func saveWithoutSharedStorageExplainsTheDegradedState() {
        let world = makeWorld(containerAvailable: false)
        defer { world.cleanUp() }
        let draft = LayoutDraft(layout: makeUserLayout(), library: world.library)
        draft.addRow()

        #expect(!draft.save())
        // The friendly no-shared-storage message, not the raw error.
        #expect(draft.saveErrorMessage?.contains("shared storage") == true)
        // The library reflects the degraded state for the rest of the UI.
        #expect(!world.library.containerAvailable)
    }

    // MARK: Reset to default

    @Test func resetToDefaultReadoptsTheSourceContentKeepingIdentity() throws {
        let world = makeWorld()
        defer { world.cleanUp() }
        let source = try #require(world.library.builtInLayouts.first)
        let fork = source.makeEditableCopy(named: "My Fork")
        let draft = LayoutDraft(layout: fork, library: world.library)

        #expect(draft.builtInSource == source)
        #expect(draft.canResetToDefault)

        draft.addRow()
        draft.panelIndex = 1
        draft.resetToDefault()

        // Content matches the built-in again; identity/metadata stay the fork's.
        #expect(draft.workingCopy.arrangements == source.arrangements)
        #expect(draft.workingCopy.id == fork.id)
        #expect(draft.workingCopy.name == "My Fork")
        #expect(draft.workingCopy.derivedFrom == source.id)
        // A reset can change the panel count, so the selection rewinds.
        #expect(draft.panelIndex == 0)
        // Nothing persisted: reset is a draft operation like any other.
        #expect(world.library.userLayouts.isEmpty)
    }

    @Test func resetIsUnavailableWithoutASourceBuiltIn() {
        let world = makeWorld()
        defer { world.cleanUp() }

        // Never forked: no derivedFrom.
        let standalone = LayoutDraft(layout: makeUserLayout(), library: world.library)
        #expect(standalone.builtInSource == nil)
        #expect(!standalone.canResetToDefault)

        // Forked from a built-in that no longer exists: dangling derivedFrom.
        let dangling = LayoutDraft(
            layout: makeUserLayout(derivedFrom: UUID()), library: world.library)
        #expect(dangling.builtInSource == nil)
        #expect(!dangling.canResetToDefault)

        // Calling reset anyway is a safe no-op.
        let before = dangling.workingCopy
        dangling.resetToDefault()
        #expect(dangling.workingCopy == before)
    }
}
