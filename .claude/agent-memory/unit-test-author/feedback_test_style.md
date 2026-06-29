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
