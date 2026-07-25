# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository. Area-specific guidance lives in `.claude/skills/` — **use the named skill before working in its area** (pointers below say which skill covers what); subagents without the Skill tool read the `SKILL.md` file directly.

## Overview

IPAKeyboard is a universal iOS/iPadOS app (bundle id `net.yuryu.IPAKeyboard`): a customizable International Phonetic Alphabet system keyboard — a host container app plus a keyboard extension, sharing code and data through a framework and an App Group. The defining requirement is **customizability**: read-only default layouts ship per language-dialect (e.g. `en-US`); users add, fork, and edit layouts. Layouts are **data, not code** (see Architecture).

Two standing constraints that the project files show only as today's state, not as policy:

- Deployment target is **iOS 17.0 on the iOS 26 SDK** — deliberate, for device reach. Guard post-17 API with `@available`; don't raise the target.
- **No third-party dependencies** and no SwiftPM manifest. Adding one is a project decision, not an implementation detail.

## Product direction

`docs/ROADMAP.md` is the single source for product intent and for the delivered-vs-remaining snapshot ("Where we are") — read it before planning feature work, and don't mirror it here. Actionable work is GitHub issues, never a roadmap task list.

## Workflow

Everything lands through PRs — code and docs alike. `main` is protected and only moves by merging a PR: **never commit or push to `main`, and don't merge a PR unless asked.**

**Branch names must be ASCII.** Issue titles routinely contain IPA characters and `gh issue develop` copies the title into the branch name — always pass `--name <ascii-name>`. Renaming later closes the open PR, so get it right the first time.

Merges are squash-only, so the **PR body is the permanent record**: follow `.github/pull_request_template.md` and put `Fixes #<n>` there, never only in a commit message. Substantial work starts from an issue; small self-contained changes (docs tweaks, chores) need none. Commit and push freely on the branch — PR review replaces ask-before-committing.

When an issue is required, `gh issue develop` usage, issue/label conventions, and Codex/Copilot review handling: the `pr-workflow` skill.

## Working style: verify, don't trust memory

Verify file paths, kit API names, build settings, and exact Unicode code points against the source (read, grep, or `show_build_settings`) before citing them — and say when a fact is assumed rather than verified.

## Targets

Three targets in `IPAKeyboard.xcodeproj` (no `.xcworkspace` — build the project directly), each with an owning skill:

- **IPAKeyboard** (host app + layout-management UI) → `host-app-ui`
- **KeyboardExtension** (`.appex`, `UIInputViewController`; links the kit **Do Not Embed**) → `keyboard-extension`
- **IPAKeyboardKit** (framework: schema, `LayoutStore`, bundled layouts) → `layout-schema`

App and extension both carry the App Group entitlement `group.net.yuryu.IPAKeyboard` (`IPAKeyboard/IPAKeyboard.entitlements`, `KeyboardExtension/KeyboardExtension.entitlements`), which must match `AppGroup.identifier` in code.

## Commands

Use the XcodeBuildMCP tools (`mcp__XcodeBuildMCP__*`, configured in `.mcp.json`) for builds, tests, and simulator work; README.md carries the equivalent raw `xcodebuild` invocations for when the server is unavailable.

Call `session_show_defaults` once per session before the first build (don't assume defaults are set); if unset, `session_set_defaults` with `projectPath` = `IPAKeyboard.xcodeproj`, simulator e.g. `iPhone 17`. **`build_sim`/`test_sim` take no `scheme` argument** — the scheme comes from the active defaults, so switch it with `session_set_defaults`; never pass `-scheme` in `extraArgs`, it collides with the one the tool injects.

- Kit build, no signing (validates kit + bundled JSON): scheme `IPAKeyboardKit`, `extraArgs: ["CODE_SIGNING_ALLOWED=NO"]`.
- App + extension: scheme `IPAKeyboard`; signs automatically under the team in the project and runs in the simulator with a live App Group container. Device builds additionally need the device registered with the team; CI stays unsigned.

**Per-suite run recipes, and the false-green traps that make a passing run meaningless, are in the `testing-and-ci` skill — read it before running or trusting tests.** All XCUITest work (new tests included) is bound by the `ui-testing` skill.

## Architecture: layouts as data

Keyboard layouts are versioned `Codable` JSON documents, not Swift code — this is what makes the keyboard user-customizable. Invariants that hold everywhere (full schema/storage detail: the `layout-schema` skill):

- The document holds `arrangements` (→ `Panel` → `KeyRow`), **not** a flat `rows`; `currentSchemaVersion` is `2`, v1 files migrate on decode, newer-than-supported versions are rejected.
- **Built-ins are read-only — never mutate a bundled layout in place.** Fork with `KeyboardLayout.makeEditableCopy(named:)`; symbol curation is non-destructive (`applyingHiddenSymbols(_:)` returns a filtered copy; hidden sets live in `KeyboardPreferences`, never in the layout document).
- A nil App Group container is a permanent supported state (unsigned CI, the unhosted kit-test runner), not a provisioning stopgap — but storage and preferences degrade *differently*: `LayoutStore` serves bundled layouts and throws `StoreError.sharedContainerUnavailable` on writes, while `KeyboardPreferences` stays writable on a suite that opens fine but is process-local rather than shared (`.standard` only if the suite won't open at all). Adding a bundled layout is JSON only — `LayoutStore` auto-discovers it.
- Bundled layouts use precise IPA code points — `ɡ` U+0261 (not ASCII `g`), `ː` U+02D0 (not colon). **Preserve exact Unicode when editing.**

## Subagents

Five project subagents in `.claude/agents/` — their frontmatter says what each owns. Use them proactively: dispatch matching specialists when a task spans areas, launch independent pieces concurrently in a single batch, and keep context-heavy subtasks on the specialist rather than doing them inline. Each runs with `isolation: worktree`.

Dispatch from the feature branch: agent worktrees branch off (and merge back into) the session's checked-out branch, and the session — never the agent — pushes and opens the PR. Several agents have no Bash/`gh`, so paste the issue number and body into the prompt and have them report the number back so the PR body can carry `Fixes #<n>`.
