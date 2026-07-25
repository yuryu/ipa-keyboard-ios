---
name: testing-and-ci
description: How to run each of the three test suites (kit, app-hosted, UI) locally, what CI's two unsigned-simulator jobs do, and the false-green traps that make a passing run meaningless. Use when writing, running, or planning tests, changing .github/workflows/**, or debugging CI failures.
---

# Running tests, and the CI lanes

## Running a suite locally

Use the XcodeBuildMCP tools; raw `xcodebuild` only if the server is unavailable. Once per session call `session_show_defaults`; if unset, `session_set_defaults` with `projectPath` = `IPAKeyboard.xcodeproj`, simulator e.g. `iPhone 17`. **`build_sim`/`test_sim` take no `scheme` argument** — the scheme comes from the active defaults, so switch it with `session_set_defaults`; never pass `-scheme` in `extraArgs` (it collides with the one the tool injects).

| suite | scheme | `test_sim` extraArgs |
| --- | --- | --- |
| `IPAKeyboardKitTests` (kit, unsigned) | `IPAKeyboardKit` | `["CODE_SIGNING_ALLOWED=NO"]` |
| `IPAKeyboardTests` (app-hosted view models) | `IPAKeyboard` | `["-only-testing:IPAKeyboardTests"]` |
| `IPAKeyboardUITests` (XCUITest) | `IPAKeyboard` | `["-only-testing:IPAKeyboardUITests"]` — read the `ui-testing` skill first |

Scope to one test with `-only-testing:<Target>/<Class>/<method>`. App-scheme runs sign automatically under the team in the project; if signing blocks a run, surface it rather than reporting a skip as a pass. Raw fallback: `xcodebuild -project IPAKeyboard.xcodeproj -scheme <scheme> -destination 'platform=iOS Simulator,name=iPhone 17' [CODE_SIGNING_ALLOWED=NO] test`.

## A green run can be a false green

- **Swift Testing reports zero tests as success.** `xcodebuild` prints "Executed 0 tests … TEST SUCCEEDED" and exits 0 when a `-only-testing` filter matches nothing — and such a filter is exactly what goes stale after a target rename or test-plan drift. Before believing a pass, confirm the Swift Testing summary line `Test run with N tests` reports N > 0; prefer running the kit scheme unscoped. CI enforces this after both unit steps with `grep -Eq 'Test run with [1-9][0-9]* test'` (issue #188) — keep that guard on any new test step.
- **A UI suite that silently skips is the other false green.** The system-keyboard smoke tests depend on environment preconditions (hardware keyboard off, the keyboard enabled in Settings) that cannot be scripted; see the `ui-testing` skill.

## CI — `.github/workflows/ci.yml`

`macos-26`, two jobs, everything unsigned (`CODE_SIGNING_ALLOWED=NO`). No device or archive lane yet.

- **`build-and-test`** — `build-for-testing` the app scheme (app + extension + both app-hosted bundles) and the kit scheme, then `test-without-building` the kit tests, then `-only-testing:IPAKeyboardTests` with `-parallel-testing-enabled NO`.
- **`ui-test`** — same build, then `IPAKeyboardUITests` sequentially via `test-without-building`, with `TEST_RUNNER_CI: "1"`.

The flags carry reasons that aren't visible from the outcome:

- `build-for-testing` targets `generic/platform=iOS Simulator` to skip device resolution, which can transiently see zero devices while CoreSimulatorService restarts (#40). The *test* steps do need a concrete device, so both jobs boot one through the `.github/actions/boot-simulator` composite action (exact-name match, newest runtime, `simctl bootstatus -b`) and pass its UDID — launching the XCUITest runner mid-boot fails with "Busy (Application failed preflight checks)".
- `-parallel-testing-enabled NO`: with clone-based parallel testing `xcodebuild` also launches the runner on the original device, and that launch races the boot and fails the run even when every test passes on the clones.
- `TEST_RUNNER_CI`: `xcodebuild` strips the `TEST_RUNNER_` prefix and forwards `CI=1` into the runner process, where `testLaunchPerformance` skips itself. GitHub's own `CI=true` does not cross the xcodebuild → runner boundary, hence the explicit prefix.

## What is already covered

Read the test directories before adding a suite — one file per subject, named after it, so the file list *is* the coverage inventory: `IPAKeyboardKitTests/` (Codable round-trips, `LayoutStore` I/O through the injectable `containerURL` seam, schema v2 + migration, per-locale bundled-layout sweeps, grapheme/cursor input, alternates, transfer) and `IPAKeyboardTests/` (`LayoutDraft`, `LayoutLibrary`, `OnboardingState`, `ScratchInput`, `SymbolReferenceModel`). Don't duplicate an existing subject's coverage.
