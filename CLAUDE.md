# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

IPAKeyboard is a universal iOS/iPadOS app (bundle id `net.yuryu.IPAKeyboard`) that provides a customizable International Phonetic Alphabet keyboard. The product is a system custom keyboard: a host container app plus a keyboard extension, sharing code and data through a framework and an App Group.

The defining requirement is **customizability**: the app ships read-only default layouts per language-dialect (e.g. `en-US`), and users can add new layouts and fork/edit existing ones. Layouts are **data, not code** (see Architecture).

- Language: Swift 6.0 on all three targets (app, extension, framework)
- Deployment target: iOS 26.5, universal (`TARGETED_DEVICE_FAMILY = "1,2"`, iPhone + iPad)
- No third-party dependencies, no Swift Package Manager manifest
- Two test targets (`IPAKeyboardKitTests` — Swift Testing; `IPAKeyboardUITests` — XCUITest) with real, if still partial, coverage
- CI on GitHub Actions (`.github/workflows/ci.yml`); Dependabot keeps Actions current
- Licensed under the MIT License (`LICENSE`)

## Product direction

Durable product intent and UX direction live in `docs/ROADMAP.md` (this file
covers code structure; the roadmap covers what we're building and why —
actionable work is GitHub issues, never a roadmap task list). Read it before
planning feature work. The headline goals:

- **Two kinds of layouts** — *dialect* layouts curated per language-dialect
  (e.g. `en-US`, a phonetic split of consonants and vowels) and *generic*,
  dialect-independent layouts covering most of the IPA inventory ("IPA — Full
  (QWERTY)", locale `und`, ships today; an IPA chart/table layout is a likely
  next one). Each is its own bundled `KeyboardLayout` the user selects from
  the library, and there can be several generic ones. Multiple *arrangements
  within one dialect* is deferred (the schema keeps `arrangements[]`, but no
  arrangement-picker is built).
- **Multi-symbol keys** for allophones/variants (`pʰ` from `p`) — in the
  schema via `Key.alternates`; the long-press popup is rendered by `KeyboardView`.
- **One screen, no horizontal scrolling**; a **secondary symbols panel** (like
  iOS's `123`/`#+=`) for less-common symbols.
- **Setup-screen selection** of the active layout, and per layout which
  symbols are enabled (`KeyboardPreferences` + `ActiveLayoutResolver`;
  reversible hidden-symbols curation).

What's delivered versus what remains lives in one place — "Where we are" in
`docs/ROADMAP.md` — with the remainder tracked as GitHub issues (see
Workflow); don't restate that inventory here. The guiding rule still holds:
don't generalize the schema before a real keyboard renders — generic layouts
are just additional bundled JSON and need no schema change.

## Workflow

Everything lands through pull requests — code and docs alike. `main` is protected by a ruleset (PR + green CI required, squash-merge only, admin bypass for emergencies) and only moves by merging a PR. The loop, per work item:

1. **Start from an issue** (see the conventions below), and create its linked branch: `gh issue develop <n> --checkout`.
2. **Work on the branch.** Commit and push freely there without asking — PR review replaces the old ask-before-committing rule. Never commit to or push `main` directly.
3. **Open the PR** (`gh pr create`), following `.github/pull_request_template.md`: a standalone summary, test evidence (which suites ran and their results), and `Fixes #<n>` — closing keywords must be in the **PR body**, because squash-merge discards branch commit messages (the squash commit is configured to take the PR title + body).
4. **The user reviews and merges — don't merge a PR unless asked.** CI must be green; for deeper review the user may run `/code-review ultra <PR#>`. On merge the branch auto-deletes and `Fixes #<n>` closes the issue.

Keep PRs small and short-lived: one issue = one branch = one PR. Independent issues can proceed in parallel on separate branches.

Actionable work is tracked as **GitHub issues** on `yuryu/ipa-keyboard-ios`; `docs/ROADMAP.md` holds product direction only. Conventions:

- Before starting feature work, check `gh issue list` and read the relevant issue (`gh issue view <n>`) — issues are written so a fresh session can act on them (context, file pointers, acceptance criteria, owning subagent).
- Work with no issue yet? File one first (`gh issue create`) — it anchors the branch and the PR.
- File discovered work as new issues rather than leaving TODOs in code or adding task lists to the roadmap.
- Labels map to areas (and subagents): `layouts` (IPA data/schema/bundled JSON — `ipa-data-curator`), `host-app` (`layout-editor-ui`), `keyboard-ext` (`keyboard-extension-builder`), `testing` (the test authors), `infra` (CI/signing/provisioning), `deferred` (parked by design).

## Working style: verify, don't trust memory

Don't rely on recalled memory or assumptions for things that are cheap to check. Before referencing or recommending any of the following, verify it against the actual source (read the file, grep, or check the entitlement/build setting) rather than citing it from memory:

- File paths, type/function/symbol names, and public API of `IPAKeyboardKit`.
- Build settings and flags (`APPLICATION_EXTENSION_API_ONLY`, `BUILD_LIBRARY_FOR_DISTRIBUTION`, `TARGETED_DEVICE_FAMILY`, signing flags).
- The App Group identifier — confirm `AppGroup.identifier` in code matches both `.entitlements` files.
- Exact Unicode code points in layouts and IPA data (see the Unicode note in Architecture).

When you state a fact about the codebase, make clear whether you verified it or are assuming it. A recalled memory that names a file, function, or flag is a starting point to check, not a fact to repeat.

## Targets

Three targets in `IPAKeyboard.xcodeproj` (build the project directly — there is no `xcworkspace`):

1. **IPAKeyboard** (app) — host/container app and layout-management UI. `IPAKeyboardApp` shows `LayoutListView` (browse built-in + user layouts, swipe-to-delete) → `LayoutDetailView` (metadata, live `KeyboardView` preview, set-active, "Duplicate to Edit" fork, delete) → `LayoutEditorView` (per-layout symbol curation with live curated preview + typing scratchpad), backed by the `LayoutLibrary` view model over `LayoutStore` + `KeyboardPreferences`. Key-level editing of forked layouts is not built yet (tracked in issues). Embeds the extension and the framework.
2. **KeyboardExtension** (`.appex`, `UIInputViewController`) — the actual keyboard. `KeyboardExtension/KeyboardViewController.swift` resolves the active layout (`ActiveLayoutResolver.resolve(activeID:in:)` over `KeyboardPreferences.activeLayoutID` and `LayoutStore().allLayouts()`, then applies that layout's hidden-symbols curation), renders it with the shared SwiftUI `KeyboardView`, and applies each emitted `KeyAction` to the document proxy (grapheme-cluster-aware backspace; globe key gated on `needsInputModeSwitchKey`). Links the framework as **Do Not Embed**.
3. **IPAKeyboardKit** (framework) — shared model + data store, linked by both of the above. Holds the layout schema, the `LayoutStore`, and the bundled default layouts.

Both app and extension carry the App Group entitlement `group.net.yuryu.IPAKeyboard` (`IPAKeyboard/IPAKeyboard.entitlements`, `KeyboardExtension/KeyboardExtension.entitlements`), which must match `AppGroup.identifier` in code.

## Commands

**Use the XcodeBuildMCP tools (`mcp__XcodeBuildMCP__*`, configured in `.mcp.json`) for all builds, tests, and simulator work; fall back to raw `xcodebuild` only if the server is unavailable.**

Once per session, call `session_show_defaults` (don't assume defaults are set); if unset, `session_set_defaults` with `projectPath` = `IPAKeyboard.xcodeproj`, simulator e.g. `iPhone 17` (use `discover_projs` / `list_schemes` / `list_sims` to confirm names). **`build_sim`/`test_sim` take no `scheme` argument** — the scheme comes from the active defaults, so switch it with `session_set_defaults`, `scheme` = … (do not pass `-scheme` in `extraArgs`; it collides with the one the tool injects). Then:

- **Kit build, no signing** (works today; validates the kit + bundled JSON): set `scheme` = `IPAKeyboardKit`, then `build_sim` with `extraArgs: ["CODE_SIGNING_ALLOWED=NO"]`.
- **Full simulator build** (app + extension; requires signing/provisioning): set `scheme` = `IPAKeyboard`, then `build_sim` (`build_run_sim` to build and launch).
- **Kit unit tests** (no signing): set `scheme` = `IPAKeyboardKit`, then `test_sim` with `extraArgs: ["CODE_SIGNING_ALLOWED=NO"]`; scope with `-only-testing:<Target>/<Class>/<method>` in `extraArgs`.

`boot_sim` / `install_app_sim` / `launch_app_sim` / `screenshot` / `snapshot_ui` cover simulator driving; Xcode (`open IPAKeyboard.xcodeproj`) is still preferred for SwiftUI previews. The raw-`xcodebuild` fallback mirrors these: `-project IPAKeyboard.xcodeproj -scheme <scheme> -destination 'platform=iOS Simulator,name=iPhone 17' [CODE_SIGNING_ALLOWED=NO] build|test`.

The test bundles (`IPAKeyboardKitTests` uses Swift Testing; `IPAKeyboardUITests` uses XCUITest) hold real, if still partial, coverage — kit Codable round-trips, `LayoutStore`, schema v2 + migration, grapheme deletion, and arrangement/bundled-layout checks, plus host library-UI flows. CI (`.github/workflows/ci.yml`, `macos-26`) does `build-for-testing` for all three targets plus the UI-test bundle with signing disabled, then runs the kit unit tests; it does not yet run the UI tests or any signed/device/archive build.

> **Signing is deferred.** The Apple developer account is mid-relocation, so the App Group is configured in the project but not yet provisioned with Apple. A full app/extension build fails at code-signing until that is resolved; the framework builds standalone without signing.

## Architecture: layouts as data

The core design decision is that keyboard layouts are versioned `Codable` JSON documents, not Swift code. This is what makes the keyboard user-customizable.

- **Schema** (`IPAKeyboardKit/Model/`):
  - `KeyAction` — discriminated-union of what a key does, encoded as clean hand-editable JSON (`{ "type": "insert", "text": "ə" }`, `{ "type": "backspace" }`, also `space`, `return`, `nextKeyboard`). Plus `switchPanel(target)` (renderer-handled panel switch, never reaches the host document) and `spacer` (a non-interactive flexible gap that pushes following keys right, e.g. consonants left / vowels right).
  - `Key` — `action` plus optional `label`, `accessibilityLabel`, `alternates` (long-press keys), `widthFactor`. All fields except `action` are optional in JSON so defaults stay terse; `id` is generated on decode when omitted.
  - `KeyboardLayout` → `Arrangement` → `Panel` → `KeyRow` (`KeyboardLayout` and `KeyRow` in `IPAKeyboardKit/Model/KeyboardLayout.swift`; `Arrangement` and `Panel` in `IPAKeyboardKit/Model/Arrangement.swift`) — the document holds `arrangements`, **not** a flat `rows`. An `Arrangement` has `panels` plus an optional shared `functionRow` (the pinned bottom bar); a `Panel` has a `switchKey` (the affordance that leaves it) and its symbol `rows`. `KeyboardLayout` keeps a convenience `init(...rows:)` that wraps a flat grid in one default arrangement/panel (used by previews, the extension fallback, and the v1→v2 migration). `currentSchemaVersion` is `2`: v1 (flat `rows`) files migrate structurally on decode; a newer-than-supported version is rejected, not downgraded. `Arrangement.totalRowCount` (tallest panel + bottom bar) sizes the keyboard's constant height.
- **Copy-on-write forking**: built-ins are read-only. `KeyboardLayout.makeEditableCopy(named:)` produces a user-owned copy (new `id`, `isBuiltIn = false`, `derivedFrom = source.id`). **Never mutate a bundled layout in place.** Symbol curation is likewise non-destructive: `KeyboardLayout.applyingHiddenSymbols(_:)` (built on `filteringKeys`) returns a filtered copy; the hidden sets live in `KeyboardPreferences`, never in the layout document.
- **Storage** (`IPAKeyboardKit/Store/`):
  - `LayoutStore` reads built-in defaults from the framework bundle (auto-discovering every `*.json`, so adding a locale needs no code change), reads/writes user layouts in the App Group container, and **degrades gracefully to bundled defaults when the container is nil** (i.e. before provisioning).
  - `AppGroup` exposes the shared `containerURL`; the host app writes layouts, the extension reads them.
  - `KeyboardPreferences` — small cross-target preferences over the App Group `UserDefaults` suite (host writes, extension reads): `activeLayoutID` and per-layout hidden symbols. Injectable for tests; falls back to `.standard` (process-local) before provisioning.
  - `ActiveLayoutResolver` — pure, total resolution of which layout to render (`activeID` match → bundled `en-US` → first available → minimal fallback), shared by the host preview and the extension so they can never disagree or go blank.
- **Default layouts** (`IPAKeyboardKit/Resources/`): one JSON per locale. `en-US.json` is General American, schema v2: one "Split" arrangement with an "IPA" main panel and a "More" panel, a shared bottom bar (globe/space/⌫), and rows that group consonants left + vowels right via a `spacer`. It uses precise code points — `ɡ` U+0261 (not ASCII `g`), `ː` U+02D0 (not colon), `ɹ` U+0279 as the primary rhotic with `r` as an alternate. Preserve exact Unicode when editing. Generic, dialect-independent layouts are just additional `*.json` here — `LayoutStore` auto-discovers them, no code change; `ipa-full.json` ("IPA — Full (QWERTY)", locale `und`) is the first.

### Resource bundle access

Xcode framework targets do not get SwiftPM's `Bundle.module`. Resources are located via `Bundle(for:)` against an anchor type — `IPAResources.bundle` in `IPAKeyboardKit/IPAKeyboardKit.swift`. **Do not name a public type the same as the module** (`IPAKeyboardKit`): with `BUILD_LIBRARY_FOR_DISTRIBUTION = YES` it shadows the module name and breaks `.swiftinterface` verification.

### Build settings that matter

- `APPLICATION_EXTENSION_API_ONLY = YES` on the framework — required because it is linked into an `.appex`. Don't call extension-unavailable APIs in the kit.
- `BUILD_LIBRARY_FOR_DISTRIBUTION = YES` on the framework generates the `.swiftinterface` (see the naming caveat above).

## Keyboard extension constraints

When building out `KeyboardViewController` and any code that runs in the extension:

- Tight memory budget (~48–66 MB); no network by default.
- "Allow Full Access" (`RequestsOpenAccess`) is off by default — assume no full access.
- The globe/Next-Keyboard key is required; respect `needsInputModeSwitchKey`.
- Text edits must be grapheme-cluster-aware so combining diacritics insert/delete as single user-perceived characters.

## Subagents

Five project subagents exist under `.claude/agents/`:
- `keyboard-extension-builder` — extension/host/App Group wiring and the two-target plumbing.
- `ipa-data-curator` — IPA character data, layout schema, per-locale defaults, Unicode correctness.
- `layout-editor-ui` — SwiftUI for the host app: settings, onboarding, layout-management/editor screens.
- `unit-test-author` — Swift Testing unit tests for `IPAKeyboardKit` (Codable round-trips, `LayoutStore`/`AppGroup`, migration, forking).
- `ui-test-author` — XCUITest UI tests for the host app in `IPAKeyboardUITests`.

Use these subagents proactively to offload and parallelize work — don't wait to be asked. When a task spans multiple areas (e.g. schema change + tests, or a new host screen + UI tests), dispatch the matching specialists, and run independent pieces concurrently by launching multiple agents in a single batch. Each is configured with `isolation: worktree`, so they work on isolated git worktrees that merge back cleanly; lean on this for anything that doesn't have to run on the main tree. Keep complex, narrowly-scoped, or context-heavy subtasks on the relevant specialist rather than doing everything inline.

Subagents never push or open PRs — the orchestrating session owns the branch/PR lifecycle, and subagent worktrees branch off (and merge back to) whatever branch the session has checked out, so dispatch them from the feature branch. When dispatched work stems from a GitHub issue, paste the issue number and body into the agent's prompt (not every agent has Bash/`gh` to fetch it), and have the agent report the issue number back in its summary so the PR body can carry `Fixes #<n>`.
