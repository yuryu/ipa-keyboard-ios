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

### 4. A secondary symbols panel

Less-common symbols (extended diacritics, suprasegmentals, tone marks, rare
consonants) live in a **separate panel**, reached the way the standard iOS
keyboard switches to its `123` / `#+=` panels — not crammed into the main grid.

### 5. Setup-screen selection

In the host app's setup/settings screen the user chooses which arrangements and
symbols they want enabled, so the keyboard shows their curated set rather than
forcing them to cycle through many layouts.

## Schema evolution (deferred — do after the render spine works)

The current schema (`KeyboardLayout` → `rows`) describes a single flat grid. The
wishlist needs:

- **Arrangements**: a dialect's layout holds multiple named arrangements
  (split, qwerty), each with its own rows. Decision made: multiple arrangements
  *per dialect*, sharing a symbol inventory.
- **Panels**: each arrangement has a primary panel plus one or more secondary
  panels (the "additional symbols" panel), with a panel-switch affordance.
- **Enabled set**: user selection of arrangements/symbols, stored with the
  user's layouts in the App Group container.

Evolve this *after* the single-grid renderer exists, so the abstraction is
informed by a working keyboard rather than guessed up front. Bump
`KeyboardLayout.currentSchemaVersion` and add a migration when the format
changes.

## Suggested build order

1. **Render spine** (extension): wire `KeyboardViewController` to `LayoutStore`,
   render one arrangement's `rows` as a one-screen grid (size from
   `widthFactor`, no horizontal scroll), handle tap→insert (grapheme-cluster-
   aware), backspace/space/return/nextKeyboard, and long-press→`alternates`.
2. **Schema: arrangements + panels**, with migration and updated defaults.
3. **Host-app setup screen**: browse/select arrangements and symbols; fork/edit.
4. **More dialect defaults** once the format has settled.
