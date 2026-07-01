# Roadmap & product direction

This file is the living wishlist for IPAKeyboard. It captures *what we're
building and why*; CLAUDE.md captures *how the code is structured*. Keep
product/UX intent here and link back from CLAUDE.md.

## The core idea

A system custom keyboard for typing the International Phonetic Alphabet, whose
defining trait is **customizability**: ship good read-only defaults per
language-dialect, and let users compose and edit what they actually use instead
of toggling through dozens of fixed layouts.

## Feature wishlist

### 1. Two kinds of layouts: dialect + generic

Keyboards come in two flavors, each a self-contained layout document the user
selects from the library:

- **Dialect layouts** — curated per language-dialect (e.g. `en-US`), organized
  phonetically. The `en-US` default is a *split* arrangement: consonants
  grouped left, vowels right.
- **Generic layouts** — dialect-independent and comprehensive, covering *most*
  of the IPA inventory. The first is **"IPA — Full (QWERTY)"** (locale `und`),
  its symbols placed to mirror familiar physical-keyboard positions; an IPA
  consonant/vowel *chart/table* layout is a likely future one. There can be
  several generic layouts.

Both render on the existing engine (panels + a pinned bottom bar), so a generic
layout is just another bundled JSON — **no schema change**. Because "most of
IPA" can't fit one screen with no horizontal scroll, generic layouts lean on
the secondary-panel mechanism (§4).

> **Deferred:** *multiple arrangements within a single dialect* (e.g. giving
> `en-US` both a split and a QWERTY arrangement). The schema still carries
> `arrangements[]`, but there's no arrangement-picker UI, and we may revisit
> this later. For now "QWERTY" is a **generic layout**, not an `en-US`
> arrangement.

### 2. Multi-symbol keys (allophones & variations)

Each key can surface more than one symbol — like a normal/flick keyboard — so
related sounds are reachable without a separate key: `pʰ` from `p`, `ɝ` from
`ɜ`, length/aspiration variants, etc. The schema supports this via
`Key.alternates` (long-press), `en-US.json` uses it today (e.g. `ɹ`→`r`,
schwa→`ɚ`/`ɝ`), and `KeyboardView` renders the long-press popup — **delivered**.

### 3. Everything on one screen — no horizontal scrolling

The active arrangement must fit the keyboard area without horizontal scroll.
Key widths come from `widthFactor`; the renderer sizes rows to fit.

**Within-row grouping** (done): a row may contain a flexible `spacer`
(`KeyAction.spacer`) that absorbs leftover width and pushes the following keys to
the right — e.g. consonants packed left, vowels packed right, with a gap between.
Rows with a spacer lay out on a shared key grid so grouped keys stay a consistent
size; plain rows still stretch to fill.

### 4. A secondary symbols panel — *delivered*

Less-common symbols (extended diacritics, suprasegmentals, tone marks, rare
consonants) live in a **separate panel**, reached the way the standard iOS
keyboard switches to its `123` / `#+=` panels — not crammed into the main grid.
Implemented in v2: an arrangement holds multiple panels plus a shared bottom bar;
a per-panel `switchKey` toggles between them while the bottom bar stays pinned.
`en-US` ships an "IPA" main panel and a "More" panel.

### 5. Setup-screen selection

In the host app the user picks the **active layout** (which keyboard the
extension shows) and, per layout, **which symbols are enabled**, so the keyboard
shows their curated set rather than forcing them to cycle through many layouts.
Not built yet — this is the next increment (see the build order).

## Schema evolution

**Arrangements + panels — delivered (schema v2).** The document is now
`KeyboardLayout.arrangements` → `Arrangement` → `Panel`:

- **Arrangements**: a layout holds one or more named arrangements (e.g. `en-US`
  ships a single "Split" arrangement), each sharing the symbol inventory. Index
  0 renders; per-dialect arrangement *selection* is deferred (see the wishlist).
- **Panels**: each `Arrangement` has a primary panel plus optional secondary
  panels and a shared `functionRow` (the pinned bottom bar). A per-`Panel`
  `switchKey` (a `KeyAction.switchPanel(target)`) moves between panels.
- `currentSchemaVersion` is `2`; v1 (flat `rows`) files migrate on decode by
  wrapping their rows in one default arrangement/panel, and a file claiming a
  *newer* version than supported is rejected rather than silently downgraded.

Still deferred:

- **Enabled set**: per-layout user selection of which symbols are enabled,
  stored alongside the user's layouts / preferences in the App Group.
- **Multiple arrangements within one dialect**: the schema keeps
  `arrangements[]`, but there's no arrangement-picker UI and we're not building
  one yet.

Note: **generic layouts need no schema work** — they're additional bundled
`KeyboardLayout` documents (a generic `locale`, e.g. `und`), auto-discovered by
`LayoutStore`.

## Suggested build order

1. ~~**Render spine** (extension): wire `KeyboardViewController` to
   `LayoutStore`, render a one-screen grid (size from `widthFactor`, no
   horizontal scroll), handle tap→insert (grapheme-cluster-aware),
   backspace/space/return/nextKeyboard, and long-press→`alternates`.~~ **Done.**
2. ~~**Schema: arrangements + panels**, with migration and updated defaults.~~
   **Done** (v2: arrangements → panels, shared bottom bar, `switchPanel`,
   flexible `spacer`; `en-US` migrated).
3. ~~**Layout library** (host): browse built-in + user layouts, fork
   ("Duplicate to Edit"), delete, live preview.~~ **Done.**
4. **Active-layout selection + a first generic layout.** A cross-target
   "active layout" preference plus a never-blank resolver the extension
   consumes; host UI to pick the active layout; and author the generic
   **"IPA — Full (QWERTY)"** layout, so selecting is a real choice (dialect
   Split vs. Full IPA). *Nothing reaches the on-device keyboard until the App
   Group is provisioned — the payoff is host-side (live preview) until signing
   lands.*
5. **Per-layout symbol curation.** A reversible "hide symbols" overlay stored
   per layout and applied via `KeyboardLayout.filteringKeys`, with an in-app
   scratchpad to type with the curated set.
6. **More layouts** once the format has settled — additional dialect defaults
   and generic layouts (e.g. an IPA chart/table layout).
