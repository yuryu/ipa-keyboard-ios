//
//  LayoutLibrary.swift
//  IPAKeyboard
//
//  View model backing the layout-management UI (roadmap step 3a). Wraps a
//  `LayoutStore` and exposes the built-in and user layouts to SwiftUI, plus
//  the fork/delete operations that write user layouts back through the store.
//
//  Persistence always goes through `LayoutStore`: this type never touches the
//  App Group container or bundled JSON directly. Before signing/provisioning
//  lands the container can be nil, so `save`/`delete` throw
//  `StoreError.sharedContainerUnavailable`; we catch that, flip
//  `containerAvailable` to false, and surface a user-facing message instead of
//  crashing. Built-ins still load and preview in that state.
//

import Foundation
import Observation
import IPAKeyboardKit

@Observable
@MainActor
final class LayoutLibrary {
    /// Read-only bundled defaults, always available even before provisioning.
    private(set) var builtInLayouts: [KeyboardLayout] = []
    /// User-created/forked layouts from the App Group container; empty when the
    /// container is unavailable.
    private(set) var userLayouts: [KeyboardLayout] = []

    /// Id of the layout the keyboard will render (the user's active selection),
    /// or nil when none is chosen and the resolver falls back to a default.
    private(set) var activeLayoutID: UUID?

    /// Per-layout hidden-symbol sets, keyed by layout id and mirrored from
    /// `KeyboardPreferences` so SwiftUI observes curation changes (previews
    /// refresh when a symbol is toggled).
    private(set) var hiddenSymbolsByLayout: [UUID: Set<String>] = [:]

    /// Best-effort signal for whether writing user layouts will work. Starts
    /// true and flips false the first time the store reports the shared
    /// container is unavailable. We can't probe the container without a write,
    /// so this reflects the most recent attempt rather than live state.
    private(set) var containerAvailable = true

    /// User-facing message for the most recent failed operation, or nil.
    var errorMessage: String?

    private let store: LayoutStore
    private let preferences: KeyboardPreferences

    init(store: LayoutStore = LayoutStore(), preferences: KeyboardPreferences = KeyboardPreferences()) {
        self.store = store
        self.preferences = preferences
        reload()
    }

    /// Repopulate the layout arrays, the active selection, and the per-layout
    /// hidden-symbol sets from storage.
    func reload() {
        builtInLayouts = store.bundledLayouts()
        userLayouts = store.userLayouts()
        activeLayoutID = preferences.activeLayoutID
        hiddenSymbolsByLayout = (builtInLayouts + userLayouts).reduce(into: [:]) { mirror, layout in
            mirror[layout.id] = preferences.hiddenSymbols(for: layout.id)
        }
    }

    /// The layout the keyboard would actually render for the current selection —
    /// resolved exactly the way the extension resolves it, with the active
    /// layout's hidden symbols applied (never nil/blank) so the host preview
    /// matches the keyboard.
    var activeLayout: KeyboardLayout {
        let resolved = ActiveLayoutResolver.resolve(activeID: activeLayoutID, in: builtInLayouts + userLayouts)
        return resolved.applyingHiddenSymbols(hiddenSymbolsByLayout[resolved.id] ?? [])
    }

    /// Id of the layout the keyboard actually renders: the explicit selection
    /// when set, otherwise the resolver's default (e.g. `en-US`). The list's
    /// active checkmark and the detail's "Active" label key off this — rather
    /// than the raw, nil-until-chosen `activeLayoutID` — so those indicators
    /// agree with the previewed active layout even before an explicit pick.
    var resolvedActiveLayoutID: UUID {
        ActiveLayoutResolver.resolve(activeID: activeLayoutID, in: builtInLayouts + userLayouts).id
    }

    /// Whether the active-layout choice actually reaches the keyboard extension.
    /// False until the App Group is provisioned (the preference is process-local
    /// until then), so the UI can say so honestly.
    var selectionReachesKeyboard: Bool { AppGroup.sharedAvailable }

    /// Mark `layout` as the active layout the keyboard should render.
    func setActive(_ layout: KeyboardLayout) {
        preferences.activeLayoutID = layout.id
        activeLayoutID = layout.id
    }

    /// The symbols the user has hidden for `layout` (empty when none).
    func hiddenSymbols(for layout: KeyboardLayout) -> Set<String> {
        hiddenSymbolsByLayout[layout.id] ?? []
    }

    /// Replace `layout`'s hidden set, persisting it and updating the observed
    /// mirror so previews refresh.
    func setHiddenSymbols(_ symbols: Set<String>, for layout: KeyboardLayout) {
        preferences.setHiddenSymbols(symbols, for: layout.id)
        hiddenSymbolsByLayout[layout.id] = symbols
    }

    /// Copy-on-write fork: save an editable copy of `layout`, then reload so the
    /// new copy appears under "My Layouts". `layout` is expected to be a
    /// built-in, but forking a user layout is harmless.
    func fork(_ layout: KeyboardLayout) {
        perform("Couldn’t save your copy.") {
            try store.save(layout.makeEditableCopy())
        }
    }

    /// Delete a user layout. No-op against a built-in (the UI never offers it).
    func delete(_ layout: KeyboardLayout) {
        perform("Couldn’t delete this layout.") {
            try store.delete(id: layout.id)
            preferences.clearActiveLayout(ifEquals: layout.id)
            preferences.clearHiddenSymbols(for: layout.id)
        }
    }

    /// Errors from `update` beyond what the store itself throws.
    enum UpdateError: Error {
        /// Attempted to write a built-in layout; built-ins are read-only
        /// (copy-on-write is enforced here as well as in the UI).
        case builtInIsReadOnly
    }

    /// Persist edits to an existing user layout (the key editor's Save) and
    /// reload. Unlike `fork`/`delete` this throws instead of setting
    /// `errorMessage`: the editor runs in a sheet and presents its own error
    /// alert (the root list's alert can't present while the sheet is up).
    /// Still flips `containerAvailable` on a missing-container failure so the
    /// rest of the UI reflects the degraded state.
    func update(_ layout: KeyboardLayout) throws {
        guard !layout.isBuiltIn else { throw UpdateError.builtInIsReadOnly }
        do {
            try store.save(layout)
            reload()
        } catch {
            if case LayoutStore.StoreError.sharedContainerUnavailable = error {
                containerAvailable = false
            }
            throw error
        }
    }

    /// Run a store mutation, translating a missing-container failure into a
    /// graceful, user-readable state and reloading on success.
    private func perform(_ failureSummary: String, _ work: () throws -> Void) {
        do {
            try work()
            errorMessage = nil
            reload()
        } catch LayoutStore.StoreError.sharedContainerUnavailable {
            containerAvailable = false
            errorMessage = "\(failureSummary) Saving layouts needs the keyboard’s "
                + "shared storage, which isn’t set up yet."
        } catch {
            errorMessage = "\(failureSummary) \(error.localizedDescription)"
        }
    }
}
