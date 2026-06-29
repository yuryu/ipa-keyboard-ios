# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

IPAKeyboard is a universal iOS/iPadOS app (bundle id `net.yuryu.IPAKeyboard`) that provides a customizable International Phonetic Alphabet keyboard. The product is a system custom keyboard: a host container app plus a keyboard extension, sharing code and data through a framework and an App Group.

The defining requirement is **customizability**: the app ships read-only default layouts per language-dialect (e.g. `en-US`), and users can add new layouts and fork/edit existing ones. Layouts are **data, not code** (see Architecture).

- Language: Swift 6.0 on all three targets (app, extension, framework)
- Deployment target: iOS 26.5, universal (`TARGETED_DEVICE_FAMILY = "1,2"`, iPhone + iPad)
- No third-party dependencies, no Swift Package Manager manifest
- Two test targets (`IPAKeyboardKitTests`, `IPAKeyboardUITests`) — currently stock template tests only
- CI on GitHub Actions (`.github/workflows/ci.yml`); Dependabot keeps Actions current
- Licensed under the MIT License (`LICENSE`)

## Workflow

This is an early-stage prototype. Commit directly to `main`; don't create feature branches or PRs unless I ask. (Still commit or push only when I ask — this just removes the auto-branch step.)

## Working style: verify, don't trust memory

Don't rely on recalled memory or assumptions for things that are cheap to check. Before referencing or recommending any of the following, verify it against the actual source (read the file, grep, or check the entitlement/build setting) rather than citing it from memory:

- File paths, type/function/symbol names, and public API of `IPAKeyboardKit`.
- Build settings and flags (`APPLICATION_EXTENSION_API_ONLY`, `BUILD_LIBRARY_FOR_DISTRIBUTION`, `TARGETED_DEVICE_FAMILY`, signing flags).
- The App Group identifier — confirm `AppGroup.identifier` in code matches both `.entitlements` files.
- Exact Unicode code points in layouts and IPA data (see the Unicode note in Architecture).

When you state a fact about the codebase, make clear whether you verified it or are assuming it. A recalled memory that names a file, function, or flag is a starting point to check, not a fact to repeat.

## Targets

Three targets in `IPAKeyboard.xcodeproj` (build the project directly — there is no `xcworkspace`):

1. **IPAKeyboard** (app) — host/container app and the settings/editor UI for managing layouts. Currently still the stock template (`IPAKeyboardApp` → `ContentView`). Embeds the extension and the framework.
2. **KeyboardExtension** (`.appex`, `UIInputViewController`) — the actual keyboard. `KeyboardExtension/KeyboardViewController.swift` is still the stock template (globe/Next-Keyboard button only); it has yet to be wired to render a `KeyboardLayout`. Links the framework as **Do Not Embed**.
3. **IPAKeyboardKit** (framework) — shared model + data store, linked by both of the above. Holds the layout schema, the `LayoutStore`, and the bundled default layouts.

Both app and extension carry the App Group entitlement `group.net.yuryu.IPAKeyboard` (`IPAKeyboard/IPAKeyboard.entitlements`, `KeyboardExtension/KeyboardExtension.entitlements`), which must match `AppGroup.identifier` in code.

## Commands

```sh
# Build the framework only, no signing (works today; validates the kit + bundled JSON)
xcodebuild -project IPAKeyboard.xcodeproj -scheme IPAKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -target IPAKeyboardKit CODE_SIGNING_ALLOWED=NO build

# Full build for the simulator (app + extension; requires signing/provisioning)
xcodebuild -project IPAKeyboard.xcodeproj -scheme IPAKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run the IPAKeyboardKit unit tests (no signing needed)
xcodebuild -project IPAKeyboard.xcodeproj -scheme IPAKeyboardKit \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO test

# Open in Xcode (preferred for running on simulator/device and SwiftUI previews)
open IPAKeyboard.xcodeproj
```

Run a single test with `-only-testing:<Target>/<Class>/<method>`. The test bundles (`IPAKeyboardKitTests` uses Swift Testing; `IPAKeyboardUITests` uses XCUITest) currently hold only the stock template tests — real coverage is still to be written. CI (`.github/workflows/ci.yml`, `macos-26`) does `build-for-testing` for all three targets plus the UI-test bundle with signing disabled, then runs the kit unit tests; it does not yet run the UI tests or any signed/device/archive build.

> **Signing is deferred.** The Apple developer account is mid-relocation, so the App Group is configured in the project but not yet provisioned with Apple. A full app/extension build fails at code-signing until that is resolved; the framework builds standalone without signing.

## Architecture: layouts as data

The core design decision is that keyboard layouts are versioned `Codable` JSON documents, not Swift code. This is what makes the keyboard user-customizable.

- **Schema** (`IPAKeyboardKit/Model/`):
  - `KeyAction` — discriminated-union of what a key does, encoded as clean hand-editable JSON (`{ "type": "insert", "text": "ə" }`, `{ "type": "backspace" }`, also `space`, `return`, `nextKeyboard`).
  - `Key` — `action` plus optional `label`, `accessibilityLabel`, `alternates` (long-press keys), `widthFactor`. All fields except `action` are optional in JSON so defaults stay terse; `id` is generated on decode when omitted.
  - `KeyboardLayout` / `KeyRow` — the document: `schemaVersion`, `id`, `name`, `locale` (BCP-47), `isBuiltIn`, `derivedFrom`, `rows`. `KeyboardLayout.currentSchemaVersion` gates migrations.
- **Copy-on-write forking**: built-ins are read-only. `KeyboardLayout.makeEditableCopy(named:)` produces a user-owned copy (new `id`, `isBuiltIn = false`, `derivedFrom = source.id`). **Never mutate a bundled layout in place.**
- **Storage** (`IPAKeyboardKit/Store/`):
  - `LayoutStore` reads built-in defaults from the framework bundle (auto-discovering every `*.json`, so adding a locale needs no code change), reads/writes user layouts in the App Group container, and **degrades gracefully to bundled defaults when the container is nil** (i.e. before provisioning).
  - `AppGroup` exposes the shared `containerURL`; the host app writes layouts, the extension reads them.
- **Default layouts** (`IPAKeyboardKit/Resources/`): one JSON per locale. `en-US.json` is General American (full vowel/consonant inventory + suprasegmentals + function keys). It uses precise code points — `ɡ` U+0261 (not ASCII `g`), `ː` U+02D0 (not colon), `ɹ` U+0279 as the primary rhotic with `r` as an alternate. Preserve exact Unicode when editing.

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
