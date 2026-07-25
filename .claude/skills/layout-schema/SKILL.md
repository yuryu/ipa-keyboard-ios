---
name: layout-schema
description: IPAKeyboardKit detail — the layout JSON schema (KeyboardLayout → Arrangement → Panel → KeyRow), copy-on-write forking, storage (LayoutStore, AppGroup, KeyboardPreferences, ActiveLayoutResolver), bundled default layouts, resource-bundle access, and framework build settings. Use when touching IPAKeyboardKit/** or reasoning about layout JSON documents.
---

# IPAKeyboardKit: layout schema, storage, and bundled layouts

Detail behind the "layouts as data" invariants in the root CLAUDE.md. Verify against `IPAKeyboardKit/Model/` and `Store/` before editing — don't trust this summary over the source.

## Schema (`IPAKeyboardKit/Model/`)

- `KeyAction` — discriminated union encoded as clean hand-editable JSON (`{ "type": "insert", "text": "ə" }`; also `backspace`, `space`, `return`, `nextKeyboard`), plus `switchPanel(target)` (renderer-handled panel switch, never reaches the host document) and `spacer` (non-interactive flexible gap that pushes following keys right).
- `Key` — `action` plus optional `label`, `accessibilityLabel` (spoken name, e.g. "schwa"), `alternates` (long-press keys), `widthFactor`; all fields except `action` are optional in JSON, and `id` is generated on decode when omitted.
- `KeyboardLayout` → `Arrangement` → `Panel` → `KeyRow` (`KeyboardLayout`/`KeyRow` in `Model/KeyboardLayout.swift`; `Arrangement`/`Panel` in `Model/Arrangement.swift`) — the document holds `arrangements`, **not** a flat `rows`. An `Arrangement` has `panels` plus an optional shared `functionRow` (the pinned bottom bar); a `Panel` has a `switchKey` (the affordance that leaves it) and its symbol `rows`. A convenience `init(...rows:)` wraps a flat grid in one default arrangement/panel (previews, extension fallback, v1→v2 migration). `currentSchemaVersion` is `2`: v1 (flat `rows`) files migrate on decode; newer-than-supported versions are rejected, not downgraded. `Arrangement.totalRowCount` (tallest panel + bottom bar) sizes the keyboard's constant height.
- Layout identity/metadata: stable UUID `id`, display `name`, a BCP-47 **locale** (`en-US` for dialect layouts, `und` for generic dialect-independent ones), `isBuiltIn`, and `derivedFrom` when forked from a default.
- Schema changes: bump `currentSchemaVersion`, add a structural on-decode migration for every older version, and keep the format diff-friendly and export/import-able. Don't generalize the schema before a real keyboard renders the new capability — new layouts are usually just new JSON.

## Copy-on-write forking

Built-ins are read-only — **never mutate a bundled layout in place**. `KeyboardLayout.makeEditableCopy(named:)` produces a user-owned copy (new `id`, `isBuiltIn = false`, `derivedFrom = source.id`). Symbol curation is likewise non-destructive: `applyingHiddenSymbols(_:)` (built on `filteringKeys`) returns a filtered copy; hidden sets live in `KeyboardPreferences`, never in the layout document.

## Storage (`IPAKeyboardKit/Store/`)

- `LayoutStore` — bundled defaults from the framework bundle (auto-discovers every `*.json`, so a new locale needs no code change); user layouts in the App Group container; **degrades gracefully to bundled defaults when the container is nil** (pre-provisioning).
- `AppGroup` — exposes the shared `containerURL`; the host app writes layouts, the extension reads them.
- `KeyboardPreferences` — cross-target preferences over the App Group `UserDefaults` suite (host writes, extension reads): `activeLayoutID`, per-layout hidden symbols. Injectable for tests; falls back to `.standard` (process-local) pre-provisioning.
- `ActiveLayoutResolver` — pure, total resolution of which layout to render (`activeID` match → bundled `en-US` → first available → minimal fallback), shared by host preview and extension so they never disagree or go blank.

## Default layouts (`IPAKeyboardKit/Resources/`, one JSON per layout)

`ls IPAKeyboardKit/Resources/` is the inventory — dialect layouts are named by BCP-47 tag (`en-US.json`, …) and generic ones by slug (`ipa-full.json`, `ipa-chart.json`, locale `und`). A new layout is JSON only: `LayoutStore` auto-discovers it, no code change.

`en-US.json` is the structural reference: General American, schema v2, one "Split" arrangement with an "IPA" main panel and a "More" panel, a shared globe/space/⌫ bottom bar, consonants left / vowels right via a `spacer`. It uses precise code points — `ɡ` U+0261 (not ASCII `g`), `ː` U+02D0 (not colon), `ɹ` U+0279 as primary rhotic with `r` as an alternate. **Preserve exact Unicode when editing.**

Each bundled layout has a matching test suite (`EnUSDiacriticsTests`, `EnGBLayoutTests`, `JaJPLayoutTests`, `DeDELayoutTests`) plus the all-layouts invariant sweep in `BundledLayoutTests` — add a suite when you add a locale, and expect the sweep to hold for it.

## Resource bundle access

Xcode framework targets get no SwiftPM `Bundle.module`; resources are located via `Bundle(for:)` against an anchor type — `IPAResources.bundle` in `IPAKeyboardKit/IPAKeyboardKit.swift`. **Do not name a public type the same as the module** (`IPAKeyboardKit`): with `BUILD_LIBRARY_FOR_DISTRIBUTION = YES` it shadows the module name and breaks `.swiftinterface` verification.

## Build settings that matter

- `APPLICATION_EXTENSION_API_ONLY = YES` on the framework (it links into an `.appex`) — don't call extension-unavailable APIs in the kit.
- `BUILD_LIBRARY_FOR_DISTRIBUTION = YES` on the framework generates the `.swiftinterface` (see the naming caveat above).
