---
name: project_layoutlibrary_testing
description: LayoutLibrary (app-hosted view model) test coverage state as of issue #82, and why readPickedDocument stays seam-free
metadata:
  type: project
---

`IPAKeyboardTests/LayoutLibraryTests.swift` (added for issue #82) covers `LayoutLibrary`'s
store-mutation pipeline hermetically, using the same `World` struct pattern as
`LayoutDraftTests.swift` (temp-directory `LayoutStore(containerURL:)` + isolated
`UserDefaults(suiteName:)`, `containerAvailable: Bool` toggle for the degraded path):
fork/delete/update/import (success + degraded-container branches), active-layout
resolver mirroring (`resolvedActiveLayoutID`/`activeLayout` vs
`ActiveLayoutResolver.resolve` called directly), and the per-layout hidden-symbols
mirror (`hiddenSymbolsByLayout`, persistence across a fresh `LayoutLibrary` instance
over the same storage).

**`LayoutLibrary.readPickedDocument(at:)`** (the `.fileImporter` completion's
security-scoped-URL read) deliberately has **no injection seam** — decided against
adding a stored-closure seam because the function is `@concurrent nonisolated static`
(forces the global executor per Swift 6.2 Approachable Concurrency, see the function's
own doc comment), and introducing a stored-closure default-parameter seam around it
risked disturbing that executor-hop for a branch only meaningfully exercisable against
a real sandboxed file URL. Recorded as an explicit deferral in a doc-comment addendum at
the call site rather than papering over it; `ImportExportUITests`' file header already
documents that XCUITest can't drive the system document picker either, so this read is
genuinely untested anywhere and needs a signed/provisioned UI test to close.

**Non-obvious, confirmed by compiling a throwaway snippet:** a plain Swift `enum Foo:
Error { case a, b }` with **no associated values and no explicit `: Equatable`**
auto-conforms to `Equatable` (and `Hashable`) — `Foo.a == Foo.a` compiles and works.
This matches [[project_test_api_facts]]'s note on `LayoutStore.StoreError`; codebase
convention still prefers `#expect(throws: SomeError.self)` (type-based) over
value-based `#expect(throws: SomeError.someCase)` for these no-payload error enums,
so match that style rather than relying on the auto-conformance.

**Issues can reference test gaps that already closed before you start**: issue #82
asked for kit-level tests of `LayoutStore.deleteAllUserLayouts()` and
`KeyboardPreferences.resetAll()`, but both were already fully covered (including the
real-deletion/real-clear branches, not just degraded/no-op ones) by PR #78, merged
before this session started. Always `git log --oneline -- <file>` / grep the existing
test file for the method name before assuming an issue's "no coverage" claim still
holds — the issue may be stale relative to `main`.

**How to apply:** When re-touching `LayoutLibrary.swift` or its tests, keep the
`readPickedDocument` deferral unless a signed/provisioned UI test lane exists to
validate a seam's concurrency behavior end-to-end. When picking up a testing issue,
verify current test-file coverage first rather than trusting the issue body's claim
about what's untested.
