# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository. Area-specific guidance lives in `.claude/skills/` — **use the named skill before working in its area** (pointers below say which skill covers what); subagents without the Skill tool read the `SKILL.md` file directly.

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

1. **IPAKeyboard** (app) — host app + layout-management UI; embeds the extension and the framework. Screen map, view models, and UI architecture rules: the `host-app-ui` skill.
2. **KeyboardExtension** (`.appex`, `UIInputViewController`) — resolves the active layout and renders the shared SwiftUI `KeyboardView`; links the framework as **Do Not Embed**. Runtime constraints and wiring: the `keyboard-extension` skill.
3. **IPAKeyboardKit** (framework) — shared layout schema, `LayoutStore`, and bundled default layouts; linked by both. Schema, storage, resource-bundle, and build-setting detail: the `layout-schema` skill.

App and extension both carry the App Group entitlement `group.net.yuryu.IPAKeyboard` (`IPAKeyboard/IPAKeyboard.entitlements`, `KeyboardExtension/KeyboardExtension.entitlements`), which must match `AppGroup.identifier` in code.

## Commands

**Use the XcodeBuildMCP tools (`mcp__XcodeBuildMCP__*`, configured in `.mcp.json`) for all builds, tests, and simulator work; fall back to raw `xcodebuild` only if the server is unavailable.**

Once per session call `session_show_defaults` (don't assume defaults are set); if unset, `session_set_defaults` with `projectPath` = `IPAKeyboard.xcodeproj`, simulator e.g. `iPhone 17`. **`build_sim`/`test_sim` take no `scheme` argument** — the scheme comes from the active defaults, so switch it with `session_set_defaults` (never pass `-scheme` in `extraArgs`; it collides with the one the tool injects). Then:

- **Kit build, no signing** (works today; validates kit + bundled JSON): scheme `IPAKeyboardKit`, `build_sim` with `extraArgs: ["CODE_SIGNING_ALLOWED=NO"]`.
- **Full simulator build** (app + extension; requires signing): scheme `IPAKeyboard`, `build_sim` (`build_run_sim` to build and launch).
- **Kit unit tests** (no signing): scheme `IPAKeyboardKit`, `test_sim` with `extraArgs: ["CODE_SIGNING_ALLOWED=NO"]`; scope with `-only-testing:<Target>/<Class>/<method>` in `extraArgs`.

`boot_sim` / `install_app_sim` / `launch_app_sim` / `screenshot` / `snapshot_ui` cover simulator driving; Xcode (`open IPAKeyboard.xcodeproj`) is preferred for SwiftUI previews. Raw fallback: `xcodebuild -project IPAKeyboard.xcodeproj -scheme <scheme> -destination 'platform=iOS Simulator,name=iPhone 17' [CODE_SIGNING_ALLOWED=NO] build|test`.

Test-coverage inventory and CI lane details: the `testing-and-ci` skill. Use the `ui-testing` skill when touching UI tests — its authoring standards and flake rules are binding on all XCUITest work, new tests included.

> **Signing.** All targets sign automatically under `DEVELOPMENT_TEAM = G3N78ZRFEH`; the full app + extension builds and runs signed in the simulator, and the App Group container works there. Device builds additionally need a device registered with the team (connect it to Xcode once and let automatic signing mint the profiles). CI test lanes stay unsigned (`CODE_SIGNING_ALLOWED=NO`); a separate `signed-archive` lane (pushes to `main` + manual dispatch) archives for device with an App Store Connect API key — details in the `testing-and-ci` skill.

## Architecture: layouts as data

Keyboard layouts are versioned `Codable` JSON documents, not Swift code — this is what makes the keyboard user-customizable. Invariants that hold everywhere (full schema/storage detail: the `layout-schema` skill):

- The document holds `arrangements` (→ `Panel` → `KeyRow`), **not** a flat `rows`; `currentSchemaVersion` is `2`, v1 files migrate on decode, newer-than-supported versions are rejected.
- **Built-ins are read-only — never mutate a bundled layout in place.** Fork with `KeyboardLayout.makeEditableCopy(named:)`; symbol curation is non-destructive (`applyingHiddenSymbols(_:)` returns a filtered copy; hidden sets live in `KeyboardPreferences`, never in the layout document).
- `LayoutStore` auto-discovers every bundled `*.json` (a new layout needs no code change) and degrades gracefully to bundled defaults when the App Group container is nil (pre-provisioning).
- Bundled layouts use precise IPA code points — `ɡ` U+0261 (not ASCII `g`), `ː` U+02D0 (not colon). **Preserve exact Unicode when editing.**

## Subagents

Five project subagents in `.claude/agents/`: `keyboard-extension-builder` (extension/host/App Group wiring), `ipa-data-curator` (IPA data, layout schema, per-locale defaults, Unicode correctness), `layout-editor-ui` (host-app SwiftUI: settings, onboarding, layout management/editor), `unit-test-author` (kit Swift Testing tests), `ui-test-author` (XCUITest for the host app).

Use them proactively — don't wait to be asked. Dispatch matching specialists when a task spans areas, launch independent pieces concurrently in a single batch, and keep complex or context-heavy subtasks on the relevant specialist rather than doing everything inline. Each runs with `isolation: worktree` and merges back cleanly.

Subagents never push or open PRs — the orchestrating session owns the branch/PR lifecycle, and subagent worktrees branch off (and merge back to) the session's checked-out branch, so dispatch from the feature branch. Paste issue numbers + bodies into agent prompts (not every agent has Bash/`gh`), and have agents report the issue number back so the PR body can carry `Fixes #<n>`.
