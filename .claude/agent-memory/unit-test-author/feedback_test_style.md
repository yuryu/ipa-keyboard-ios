---
name: feedback_test_style
description: Style conventions confirmed for IPAKeyboardKitTests — no @Suite on top-level structs, no allSatisfy with key-path shorthand inside #expect
metadata:
  type: feedback
---

Top-level Swift Testing suites in IPAKeyboardKitTests use plain `struct Foo { }` without `@Suite` — auto-discovery picks them up. Pre-existing files (BundledLayoutTests, GraphemeTextTests, SchemaV2Tests, IPAKeyboardKitTests) all use this form; new files should match.

**Why:** `@Suite` on top-level types is optional and the team hasn't used it; adding it inconsistently creates visual noise.

**How to apply:** Omit `@Suite` on any new top-level test struct. `@Suite` is still required for *nested* test types.

---

Key-path shorthand passed to `allSatisfy` inside `#expect` fails to compile under Swift 6.0:

```swift
// BROKEN under Swift 6.0 — #expect macro expansion treats key path as throwing
#expect(layouts.allSatisfy(\.isBuiltIn))

// CORRECT — use explicit closure
#expect(layouts.allSatisfy { $0.isBuiltIn })
```

**Why:** The `#expect` macro re-evaluates its argument expression; the implicit key-path-to-function conversion is treated as `rethrows` and the macro expansion triggers a "call can throw but not marked try" error.

**How to apply:** Always use explicit closures `{ $0.property }` inside `#expect` when calling `allSatisfy`, `contains`, `first(where:)`, etc.

---

Calling a `mutating func` (e.g. `KeyboardLayout.insertRow`, `.removeKeys`, `.replaceKey` from `LayoutEditing.swift`) directly as the argument to `#expect(...)` fails to compile under Swift 6.0/Swift Testing, with an error buried in a synthesized macro-expansion file, not the test file itself:

```
@__swiftmacro_...expectfMf_.swift:2:6: error: cannot use mutating member on immutable value: '$0' is immutable
  $0.replaceKey(at: $1,inRowAt: $2,inPanelAt: $3,with: $4)
```

```swift
// BROKEN — #expect's macro expansion captures `layout` immutably
var layout = ...
#expect(layout.insertRow(at: 0, inPanelAt: .primary))
#expect(!layout.removeRows(atOffsets: IndexSet([99]), inPanelAt: .primary))

// CORRECT — capture the Bool result in a `let` first
let ok = layout.insertRow(at: 0, inPanelAt: .primary)
#expect(ok)
let ok2 = layout.removeRows(atOffsets: IndexSet([99]), inPanelAt: .primary)
#expect(!ok2)
// or, when the result isn't asserted on: `_ = layout.insertRow(...)`
```

**Why:** `#expect`'s macro expansion rewrites the expression to capture intermediate subexpression values for its failure diagnostics, and does so with an immutable `$0` binding — so any mutating method call inside the expression fails to compile. This hit ~36 call sites at once in `LayoutEditingTests.swift` (issue #6) because every mutating editing-API test originally inlined the call. `xcodebuild test`'s default output truncates/interleaves errors across files when piped through `tail`; redirect to a log file and `grep -c "error:"` on the *saved file* to get an accurate count before assuming a build is close to green.

**How to apply:** Whenever a test asserts on the return value of a `mutating func`, or checks that a mutating call succeeded/failed, always bind the call's result to a `let` on its own line first, then `#expect` the `let`. If the return value isn't needed, discard with `_ = layout.mutatingCall(...)` rather than inlining it in `#expect`.
