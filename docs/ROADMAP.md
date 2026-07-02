# Roadmap & product direction

This file captures *what we're building and why* — the durable product intent.
CLAUDE.md covers how the code is structured; **actionable work is tracked as
[GitHub issues](https://github.com/yuryu/ipa-keyboard-ios/issues)**. When a
direction below becomes current work it graduates to an issue; this file stays
at the level of intent so the two don't drift. Don't add task lists or
per-item status tracking here — file an issue instead. The one narrative
status snapshot is "Where we are" below; other docs link to it rather than
restating it.

## The core idea

A system custom keyboard for typing the International Phonetic Alphabet, whose
defining trait is **customizability**: ship good read-only defaults per
language-dialect, and let users compose and edit what they actually use instead
of toggling through dozens of fixed layouts.

## Product pillars

### Two kinds of layouts: dialect + generic

Keyboards come in two flavors, each a self-contained layout document the user
selects from the library:

- **Dialect layouts** — curated per language-dialect, organized phonetically.
  The `en-US` default (General American) is a *split* arrangement: consonants
  grouped left, vowels right. More dialects to come ([#5](https://github.com/yuryu/ipa-keyboard-ios/issues/5)).
- **Generic layouts** — dialect-independent and comprehensive, covering *most*
  of the IPA inventory. **"IPA — Full (QWERTY)"** (locale `und`) ships today,
  its symbols mirroring familiar physical-keyboard positions; an IPA
  chart/table layout is the likely next one ([#4](https://github.com/yuryu/ipa-keyboard-ios/issues/4)).
  There can be several generic layouts.

Both render on the same engine (panels + a pinned bottom bar), so a generic
layout is just another bundled JSON — **no schema change**. Because "most of
IPA" can't fit one screen with no horizontal scroll, generic layouts lean on
the secondary-panel mechanism.

> **Deferred by design:** *multiple arrangements within a single dialect*
> (e.g. giving `en-US` both a split and a QWERTY arrangement). The schema
> keeps `arrangements[]`, but alternatives ship as generic layouts instead.
> Tracked in [#10](https://github.com/yuryu/ipa-keyboard-ios/issues/10).

### Customization, in increasing depth

The user journey the host app builds toward:

1. **Select** the active layout (which keyboard the extension shows).
2. **Curate** per-layout which symbols are enabled, as a reversible overlay
   that never touches the layout document.
3. **Fork** a built-in into a user-owned copy ("Duplicate to Edit").
4. **Edit** a forked layout's actual keys — rows, labels, alternates, widths
   ([#6](https://github.com/yuryu/ipa-keyboard-ios/issues/6)).
5. **Share**: export/import a layout as a file ([#8](https://github.com/yuryu/ipa-keyboard-ios/issues/8)).

### Interaction principles

- **Multi-symbol keys** — allophones/variants reachable from one key
  (`pʰ` from `p`, `ɚ`/`ɝ` from schwa) via long-press `alternates`.
- **Everything on one screen, no horizontal scrolling** — widths from
  `widthFactor`; a flexible `spacer` groups keys within a row (consonants
  left, vowels right).
- **A secondary symbols panel** — less-common symbols live in a separate
  panel reached like iOS's `123`/`#+=`, with the bottom bar pinned.

## Where we are

Delivered: the render spine (extension renders layouts, grapheme-cluster-aware
editing), schema v2 (arrangements → panels, v1 migration), the host layout
library (browse/fork/delete/preview), active-layout selection shared across
targets, the first generic layout ("IPA — Full (QWERTY)"), and per-layout
symbol curation with an in-app scratchpad.

The big external blocker is **signing/App Group provisioning**
([#3](https://github.com/yuryu/ipa-keyboard-ios/issues/3)) — until it lands,
nothing reaches the on-device keyboard and the payoff of new work is host-side
(live preview and scratchpad).

For everything else, see the
[open issues](https://github.com/yuryu/ipa-keyboard-ios/issues).
