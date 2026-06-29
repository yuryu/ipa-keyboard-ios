---
name: feedback_swift6_xcuitest
description: Swift 6 @MainActor isolation pattern for XCUITest setUp/tearDown — verified working in this project
metadata:
  type: feedback
---

Use async `setUp()` / `tearDown()` overrides (not `setUpWithError`/`tearDownWithError`) and annotate them `@MainActor`. This avoids Swift 6 warnings about calling main-actor-isolated APIs (`XCUIApplication()`, `.screenshot()`, stored `@MainActor` properties) from nonisolated synchronous overrides.

Also annotate stored XCUITest properties with `@MainActor` rather than the whole class, so the class itself stays nonisolated and the XCTestCase override signatures remain valid.

**Why:** Swift 6 strict concurrency: synchronous overrides of `XCTestCase`'s nonisolated `setUpWithError`/`tearDownWithError` cannot add `@MainActor` isolation. The async variants (`setUp() async throws`, `tearDown() async throws`) do allow it.

**How to apply:** Every new XCUITest class in this project — use `@MainActor override func setUp() async throws` and `@MainActor override func tearDown() async throws`, and mark per-class XCUIApplication properties `@MainActor`.
