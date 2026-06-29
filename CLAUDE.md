# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

IPAKeyboard is a universal iOS/iPadOS app (bundle id `net.yuryu.IPAKeyboard`) that provides a customizable International Phonetic Alphabet keyboard. The product is a system custom keyboard: a host container app plus a keyboard extension, sharing code and data through a framework and an App Group.

The defining requirement is **customizability**: the app ships read-only default layouts per language-dialect (e.g. `en-US`), and users can add new layouts and fork/edit existing ones. Layouts are **data, not code** (see Architecture).

- Language: Swift 6.0 on all three targets (app, extension, framework)
- Deployment target: iOS 26.5, universal (`TARGETED_DEVICE_FAMILY = "1,2"`, iPhone + iPad)
- No third-party dependencies, no Swift Package Manager manifest, no test target yet
- Licensed under the MIT License (`LICENSE`)

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

# Open in Xcode (preferred for running on simulator/device and SwiftUI previews)
open IPAKeyboard.xcodeproj
```

There are no tests yet. If a test target is added, run with `xcodebuild ... test` and a single test via `-only-testing:<Target>/<Class>/<method>`.

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

Two project subagents exist under `.claude/agents/`:
- `keyboard-extension-builder` — extension/host/App Group wiring and the two-target plumbing.
- `ipa-data-curator` — IPA character data, layout schema, per-locale defaults, Unicode correctness.
