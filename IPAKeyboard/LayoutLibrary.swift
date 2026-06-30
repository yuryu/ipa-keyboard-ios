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

    /// Best-effort signal for whether writing user layouts will work. Starts
    /// true and flips false the first time the store reports the shared
    /// container is unavailable. We can't probe the container without a write,
    /// so this reflects the most recent attempt rather than live state.
    private(set) var containerAvailable = true

    /// User-facing message for the most recent failed operation, or nil.
    var errorMessage: String?

    private let store: LayoutStore

    init(store: LayoutStore = LayoutStore()) {
        self.store = store
        reload()
    }

    /// Repopulate both layout arrays from the store.
    func reload() {
        builtInLayouts = store.bundledLayouts()
        userLayouts = store.userLayouts()
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
