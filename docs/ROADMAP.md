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

### 1. Two render arrangements per dialect

A single dialect (e.g. `en-US`) can offer **multiple arrangements** of largely
the same symbol inventory. Two to support first:

- **Split (consonants ↔ vowels)** — phonetically organized, vowels on one side,
  consonants on the other.
- **QWERTY-style full mode** — symbols placed to mirror familiar physical-
  keyboard positions.

These are *arrangements within one dialect*, not separate dialects: the user
picks an arrangement, and the symbol set is shared. (Schema implication: a
layout document for a dialect holds more than one arrangement, each with its
own rows. See "Schema evolution" below.)

### 2. Multi-symbol keys (allophones & variations)

Each key can surface more than one symbol — like a normal/flick keyboard — so
related sounds are reachable without a separate key: `pʰ` from `p`, `ɝ` from
`ɜ`, length/aspiration variants, etc. The schema already supports this via
`Key.alternates` (long-press); `en-US.json` uses it today. Rendering it (the
long-press popup) is the open part.

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

In the host app's setup/settings screen the user chooses which arrangements and
symbols they want enabled, so the keyboard shows their curated set rather than
forcing them to cycle through many layouts.

## Schema evolution

**Arrangements + panels — delivered (schema v2).** The document is now
`KeyboardLayout.arrangements` → `Arrangement` → `Panel`:

- **Arrangements**: a dialect's layout holds one or more named arrangements
  (e.g. "Split"; QWERTY-style still to author), each sharing the symbol
  inventory. Index 0 is shown by default until arrangement selection lands.
- **Panels**: each `Arrangement` has a primary panel plus optional secondary
  panels and a shared `functionRow` (the pinned bottom bar). A per-`Panel`
  `switchKey` (a `KeyAction.switchPanel(target)`) moves between panels.
- `currentSchemaVersion` is `2`; v1 (flat `rows`) files migrate on decode by
  wrapping their rows in one default arrangement/panel, and a file claiming a
  *newer* version than supported is rejected rather than silently downgraded.

Still deferred:

- **Enabled set**: user selection of arrangements/symbols, stored with the
  user's layouts in the App Group container.

## Suggested build order

1. ~~**Render spine** (extension): wire `KeyboardViewController` to
   `LayoutStore`, render a one-screen grid (size from `widthFactor`, no
   horizontal scroll), handle tap→insert (grapheme-cluster-aware),
   backspace/space/return/nextKeyboard, and long-press→`alternates`.~~ **Done.**
2. ~~**Schema: arrangements + panels**, with migration and updated defaults.~~
   **Done** (v2: arrangements → panels, shared bottom bar, `switchPanel`,
   flexible `spacer`; `en-US` migrated).
3. **Host-app setup screen**: browse/select arrangements and symbols; fork/edit.
4. **More dialect defaults** once the format has settled.
