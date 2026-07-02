---
name: layout-authoring-decisions
description: Data decisions behind bundled layouts - normalization convention, ipa-chart compaction rules, shared budgets, UUID tag pattern
metadata:
  type: project
---

Decisions that live only in the data (not enforced by the schema), made while authoring `ipa-chart.json` (issue #4, 2026-07).

**Normalization convention:** base letters are stored precomposed NFC (ç U+00E7, ø U+00F8, æ U+00E6, œ U+0153, ð U+00F0); diacritic keys insert the **bare combining mark** (e.g. ̃ U+0303, ̥ U+0325) with a `label` composed as U+25CC ◌ + mark ("◌̃"). No normalization happens on decode — author files in this shape.

**ipa-chart.json compaction rules (document any change against these):**
- Pulmonic paired cells: voiceless symbol is the primary key, voiced counterpart is its first long-press alternate (p→b, t→d … ɬ→ɮ). Exception, following ipa-full precedent: w is primary with ʍ as alternate (frequency trumps the voiceless-primary rule there).
- Vowels get their own keys; only the two rarest (ɶ, ɒ) ride as alternates of a/ɑ in the crowded open row. Near-close ɪ ʏ ʊ are inline in the close row (lateral position ≈ centrality; spacers mark front/central/back).
- Secondary stress ˌ is a long-press alternate of ˈ; secondary articulations ʲ ʷ ˠ ˤ hang off ʰ; ˑ and ◌̆ hang off ː; ◌̺ ◌̻ hang off ◌̪; ◌̯ off ◌̩; ‿ off ".".
- Chart-pure: no ɚ/ɝ keys (rhoticity is the ˞ diacritic); tone/word-accent marks (U+02E5–02E9 etc.) are **not included** — known gap, same as ipa-full.

**Shared budgets (mirror of ipa-full, enforced by BundledLayoutTests):** max 3 symbol rows per panel (totalRowCount ≤ 4), ≤ 10 interactive keys per row, width-factor sum ≤ 12.0 per row; panels form a single switch-key cycle.

**Bundled-layout UUID house pattern:** `7E5A1C00-0000-4000-8000-` + 12 hex digits whose bytes spell an ASCII tag (`006368617274` = "chart", `00656E2D5553` = "en-US"). Tests select bundled layouts **by name** ("IPA — Full (QWERTY)", "IPA — Chart"), not by locale — several layouts share locale `und`. Related: [[unicode-traps-and-verification]].
