# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Overview

IPAKeyboard is a universal iOS/iPadOS app (bundle id `net.yuryu.IPAKeyboard`): a customizable International Phonetic Alphabet system keyboard — a host container app plus a keyboard extension, sharing code and data through a framework and an App Group. The defining requirement is **customizability**: read-only default layouts ship per language-dialect (e.g. `en-US`); users add, fork, and edit layouts. Layouts are **data, not code** (see Architecture).

- Swift 6.0 on all three targets; deployment target iOS 17.0 on the iOS 26 SDK (guard post-17 API with `@available`); universal (`TARGETED_DEVICE_FAMILY = "1,2"`).
- No third-party dependencies, no SwiftPM manifest. MIT licensed.
- Three test targets: `IPAKeyboardKitTests` and the app-hosted `IPAKeyboardTests` (Swift Testing), `IPAKeyboardUITests` (XCUITest) — real, if still partial, coverage. CI on GitHub Actions (`.github/workflows/ci.yml`); Dependabot keeps Actions current.

## Product direction

`docs/ROADMAP.md` holds product intent and the delivered-vs-remaining inventory ("Where we are") — read it before planning feature work; don't restate its inventory here. Actionable work is GitHub issues, never a roadmap task list. Headline goals:

- **Two kinds of layouts**: *dialect* layouts curated per language-dialect (e.g. `en-US`, a phonetic consonants/vowels split) and *generic* dialect-independent layouts covering most of the IPA inventory (two ship today, both locale `und`: "IPA — Full (QWERTY)" and "IPA — Chart"; several generics allowed). Multiple arrangements within one dialect is deferred — the schema keeps `arrangements[]` but no arrangement-picker is built.
- **Multi-symbol keys** for allophones/variants (`pʰ` from `p`) via `Key.alternates`; long-press popup rendered by `KeyboardView`.
- **One screen, no horizontal scrolling**; a **secondary symbols panel** (like iOS's `123`/`#+=`) for less-common symbols.
- **Setup-screen selection** of the active layout and per-layout enabled symbols (`KeyboardPreferences` + `ActiveLayoutResolver`; reversible hidden-symbols curation).

Don't generalize the schema before a real keyboard renders — generic layouts are just additional bundled JSON and need no schema change.

## Workflow

Everything lands through PRs — code and docs alike. `main` is protected (PR + green CI required, squash-merge only) and only moves by merging a PR; never commit to or push `main` directly. Per work item:

1. **Substantial work starts from an issue** (feature work, behavior changes, anything needing context or acceptance criteria): `gh issue develop <n> --name <ascii-name> --checkout`. **Small self-contained changes need no issue** (docs tweaks, typo fixes, agent-memory updates, mechanical chores): `git checkout -b <short-name>`; the PR body is the record.
2. **Commit and push freely on the branch** — PR review replaces ask-before-committing.
3. **Open the PR** (`gh pr create`) following `.github/pull_request_template.md`: standalone summary, test evidence (which suites ran and their results), and — when the PR closes an issue — `Fixes #<n>` in the **PR body** — squash-merge discards branch commit messages (the squash commit takes the PR title + body).
4. **The user reviews and merges — don't merge a PR unless asked.** OpenAI Codex auto-reviews each new PR (P0/P1 only, steered by "Review guidelines" in `AGENTS.md`); handle bot feedback (Codex and Copilot) with the `review-feedback` skill, or `review-sweep` for several PRs at once. The user may run `/code-review ultra <PR#>` for deeper review. On merge the branch auto-deletes and `Fixes #<n>` closes the issue, if there is one.

Keep PRs small and short-lived: one work item = one branch = one PR; independent items proceed in parallel on separate branches.

Issue conventions (repo `yuryu/ipa-keyboard-ios`):

- Before feature work, check `gh issue list` and `gh issue view <n>` — issues are written so a fresh session can act on them (context, file pointers, acceptance criteria, owning subagent).
- Substantial work with no issue yet? File one first (`gh issue create`). File discovered work as new issues, not code TODOs or roadmap task lists.
- **Attribute Claude's writing.** `gh` posts under the user's account, so end every Claude-written issue, comment, or review reply with a line like `*— written by Claude*`. PR bodies are covered by the `🤖 Generated with Claude Code` footer.
- Labels map to areas (and subagents): `layouts` (`ipa-data-curator`), `host-app` (`layout-editor-ui`), `keyboard-ext` (`keyboard-extension-builder`), `testing` (test authors), `infra` (CI/signing/provisioning), `deferred` (parked by design).
- **Branch names must be ASCII.** Issue titles often contain IPA characters and `gh issue develop` copies the title into the branch name — always pass `--name <ascii-name>`. Don't plan on renaming later: pushing under a new name and deleting the old closes the open PR.

## Working style: verify, don't trust memory

Before referencing or recommending any of the following, verify it against the actual source (read the file, grep, or check the build setting) rather than citing it from memory — and make clear whether a stated fact was verified or assumed:

- File paths, type/function/symbol names, and public API of `IPAKeyboardKit`.
- Build settings and flags (`APPLICATION_EXTENSION_API_ONLY`, `BUILD_LIBRARY_FOR_DISTRIBUTION`, `TARGETED_DEVICE_FAMILY`, signing flags).
- The App Group identifier — `AppGroup.identifier` in code must match both `.entitlements` files.
- Exact Unicode code points in layouts and IPA data (see the Unicode note in Architecture).

## Targets

Three targets in `IPAKeyboard.xcodeproj` (build the project directly — there is no `xcworkspace`):

1. **IPAKeyboard** (app) — host app + layout-management UI: `LayoutListView` (browse built-in + user layouts) → `LayoutDetailView` (metadata, live `KeyboardView` preview, set-active, "Duplicate to Edit" fork, delete) → `LayoutEditorView` (per-layout symbol curation with live preview + typing scratchpad), backed by the `LayoutLibrary` view model over `LayoutStore` + `KeyboardPreferences`. Key-level editing of user layouts ships as `LayoutKeyEditorView` (sheet from `LayoutDetailView`: add/remove/reorder rows, per-key edits via `KeyRowEditorView`/`KeyEditorForm`, live draft preview; user layouts only — built-ins go through "Duplicate to Edit"). Embeds the extension and the framework.
2. **KeyboardExtension** (`.appex`, `UIInputViewController`) — `KeyboardExtension/KeyboardViewController.swift` resolves the active layout (`ActiveLayoutResolver.resolve(activeID:in:)` over `KeyboardPreferences.activeLayoutID` + `LayoutStore().allLayouts()`, then applies that layout's hidden-symbols curation), renders the shared SwiftUI `KeyboardView`, and applies each emitted `KeyAction` to the document proxy (grapheme-cluster-aware backspace; globe key gated on `needsInputModeSwitchKey`). Links the framework as **Do Not Embed**.
3. **IPAKeyboardKit** (framework) — shared layout schema, `LayoutStore`, and bundled default layouts; linked by both.

App and extension both carry the App Group entitlement `group.net.yuryu.IPAKeyboard` (`IPAKeyboard/IPAKeyboard.entitlements`, `KeyboardExtension/KeyboardExtension.entitlements`), which must match `AppGroup.identifier` in code.

## Commands

**Use the XcodeBuildMCP tools (`mcp__XcodeBuildMCP__*`, configured in `.mcp.json`) for all builds, tests, and simulator work; fall back to raw `xcodebuild` only if the server is unavailable.**

Once per session call `session_show_defaults` (don't assume defaults are set); if unset, `session_set_defaults` with `projectPath` = `IPAKeyboard.xcodeproj`, simulator e.g. `iPhone 17`. **`build_sim`/`test_sim` take no `scheme` argument** — the scheme comes from the active defaults, so switch it with `session_set_defaults` (never pass `-scheme` in `extraArgs`; it collides with the one the tool injects). Then:

- **Kit build, no signing** (works today; validates kit + bundled JSON): scheme `IPAKeyboardKit`, `build_sim` with `extraArgs: ["CODE_SIGNING_ALLOWED=NO"]`.
- **Full simulator build** (app + extension; requires signing): scheme `IPAKeyboard`, `build_sim` (`build_run_sim` to build and launch).
- **Kit unit tests** (no signing): scheme `IPAKeyboardKit`, `test_sim` with `extraArgs: ["CODE_SIGNING_ALLOWED=NO"]`; scope with `-only-testing:<Target>/<Class>/<method>` in `extraArgs`.

`boot_sim` / `install_app_sim` / `launch_app_sim` / `screenshot` / `snapshot_ui` cover simulator driving; Xcode (`open IPAKeyboard.xcodeproj`) is preferred for SwiftUI previews. Raw fallback: `xcodebuild -project IPAKeyboard.xcodeproj -scheme <scheme> -destination 'platform=iOS Simulator,name=iPhone 17' [CODE_SIGNING_ALLOWED=NO] build|test`.

Existing coverage spans kit Codable round-trips, `LayoutStore` I/O (via the injectable `containerURL` seam), schema v2 + migration, grapheme deletion, arrangement/bundled-layout checks, app view models (`LayoutDraft`, `OnboardingState`), and host library-UI flows. CI (`macos-26`) runs two unsigned-simulator jobs: `build-and-test` (build-for-testing all three targets + the app-hosted unit-test and UI-test bundles, then kit unit tests and `-only-testing:IPAKeyboardTests`, sequential) and `ui-test` (build app scheme for testing; fully boot the simulator with `simctl bootstatus -b` — launching the XCUITest runner mid-boot fails with "Busy"; run `IPAKeyboardUITests` sequentially, `-parallel-testing-enabled NO`, via `test-without-building`). No signed/device/archive lane yet (deferred until provisioning).

> **Signing is deferred.** The Apple developer account is mid-relocation; the App Group is configured in the project but not yet provisioned. A full app/extension build fails at code-signing until then; the framework builds standalone without signing.

## Architecture: layouts as data

Keyboard layouts are versioned `Codable` JSON documents, not Swift code — this is what makes the keyboard user-customizable.

- **Schema** (`IPAKeyboardKit/Model/`):
  - `KeyAction` — discriminated union encoded as clean hand-editable JSON (`{ "type": "insert", "text": "ə" }`; also `backspace`, `space`, `return`, `nextKeyboard`), plus `switchPanel(target)` (renderer-handled panel switch, never reaches the host document) and `spacer` (non-interactive flexible gap that pushes following keys right).
  - `Key` — `action` plus optional `label`, `accessibilityLabel`, `alternates` (long-press keys), `widthFactor`; all fields except `action` are optional in JSON, and `id` is generated on decode when omitted.
  - `KeyboardLayout` → `Arrangement` → `Panel` → `KeyRow` (`KeyboardLayout`/`KeyRow` in `Model/KeyboardLayout.swift`; `Arrangement`/`Panel` in `Model/Arrangement.swift`) — the document holds `arrangements`, **not** a flat `rows`. An `Arrangement` has `panels` plus an optional shared `functionRow` (the pinned bottom bar); a `Panel` has a `switchKey` (the affordance that leaves it) and its symbol `rows`. A convenience `init(...rows:)` wraps a flat grid in one default arrangement/panel (previews, extension fallback, v1→v2 migration). `currentSchemaVersion` is `2`: v1 (flat `rows`) files migrate on decode; newer-than-supported versions are rejected, not downgraded. `Arrangement.totalRowCount` (tallest panel + bottom bar) sizes the keyboard's constant height.
- **Copy-on-write forking**: built-ins are read-only — **never mutate a bundled layout in place**. `KeyboardLayout.makeEditableCopy(named:)` produces a user-owned copy (new `id`, `isBuiltIn = false`, `derivedFrom = source.id`). Symbol curation is likewise non-destructive: `applyingHiddenSymbols(_:)` (built on `filteringKeys`) returns a filtered copy; hidden sets live in `KeyboardPreferences`, never in the layout document.
- **Storage** (`IPAKeyboardKit/Store/`):
  - `LayoutStore` — bundled defaults from the framework bundle (auto-discovers every `*.json`, so a new locale needs no code change); user layouts in the App Group container; **degrades gracefully to bundled defaults when the container is nil** (pre-provisioning).
  - `AppGroup` — exposes the shared `containerURL`; the host app writes layouts, the extension reads them.
  - `KeyboardPreferences` — cross-target preferences over the App Group `UserDefaults` suite (host writes, extension reads): `activeLayoutID`, per-layout hidden symbols. Injectable for tests; falls back to `.standard` (process-local) pre-provisioning.
  - `ActiveLayoutResolver` — pure, total resolution of which layout to render (`activeID` match → bundled `en-US` → first available → minimal fallback), shared by host preview and extension so they never disagree or go blank.
- **Default layouts** (`IPAKeyboardKit/Resources/`, one JSON per layout): `en-US.json` is General American, schema v2 — one "Split" arrangement with an "IPA" main panel and a "More" panel, a shared globe/space/⌫ bottom bar, consonants left / vowels right via a `spacer`. It uses precise code points — `ɡ` U+0261 (not ASCII `g`), `ː` U+02D0 (not colon), `ɹ` U+0279 as primary rhotic with `r` as an alternate. **Preserve exact Unicode when editing.** Generic layouts are just additional `*.json` here — auto-discovered, no code change; `ipa-full.json` and `ipa-chart.json` (both locale `und`) ship today.

### Resource bundle access

Xcode framework targets get no SwiftPM `Bundle.module`; resources are located via `Bundle(for:)` against an anchor type — `IPAResources.bundle` in `IPAKeyboardKit/IPAKeyboardKit.swift`. **Do not name a public type the same as the module** (`IPAKeyboardKit`): with `BUILD_LIBRARY_FOR_DISTRIBUTION = YES` it shadows the module name and breaks `.swiftinterface` verification.

### Build settings that matter

- `APPLICATION_EXTENSION_API_ONLY = YES` on the framework (it links into an `.appex`) — don't call extension-unavailable APIs in the kit.
- `BUILD_LIBRARY_FOR_DISTRIBUTION = YES` on the framework generates the `.swiftinterface` (see the naming caveat above).

## Keyboard extension constraints

For `KeyboardViewController` and anything that runs in the extension:

- Tight memory budget (~48–66 MB); no network by default.
- "Allow Full Access" (`RequestsOpenAccess`) is off by default — assume no full access.
- The globe/Next-Keyboard key is required; respect `needsInputModeSwitchKey`.
- Text edits must be grapheme-cluster-aware so combining diacritics insert/delete as single user-perceived characters.

## Subagents

Five project subagents in `.claude/agents/`: `keyboard-extension-builder` (extension/host/App Group wiring), `ipa-data-curator` (IPA data, layout schema, per-locale defaults, Unicode correctness), `layout-editor-ui` (host-app SwiftUI: settings, onboarding, layout management/editor), `unit-test-author` (kit Swift Testing tests), `ui-test-author` (XCUITest for the host app).

Use them proactively — don't wait to be asked. Dispatch matching specialists when a task spans areas, launch independent pieces concurrently in a single batch, and keep complex or context-heavy subtasks on the relevant specialist rather than doing everything inline. Each runs with `isolation: worktree` and merges back cleanly.

Subagents never push or open PRs — the orchestrating session owns the branch/PR lifecycle, and subagent worktrees branch off (and merge back to) the session's checked-out branch, so dispatch from the feature branch. Paste issue numbers + bodies into agent prompts (not every agent has Bash/`gh`), and have agents report the issue number back so the PR body can carry `Fixes #<n>`.
