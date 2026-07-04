---
name: layout-authoring-decisions
description: Data decisions behind bundled layouts - normalization convention, ipa-chart compaction rules, shared budgets, QWERTY shared-grid geometry, UUID tag pattern
metadata:
  type: project
---

Decisions that live only in the data (not enforced by the schema), made while authoring `ipa-chart.json` (issue #4, 2026-07).

**Normalization convention:** base letters are stored precomposed NFC (ç U+00E7, ø U+00F8, æ U+00E6, œ U+0153, ð U+00F0); diacritic keys insert the **bare combining mark** (e.g. ̃ U+0303, ̥ U+0325) with a `label` composed as U+25CC ◌ + mark ("◌̃"). No normalization happens on decode — author files in this shape.

**ipa-chart.json compaction rules (document any change against these):**
- Pulmonic paired cells: voiceless symbol is the primary key, voiced counterpart is its first long-press alternate (p→b, t→d … ɬ→ɮ). Exception, following ipa-full precedent: w is primary with ʍ as alternate (frequency trumps the voiceless-primary rule there).
- Vowels get their own keys; only the two rarest (ɶ, ɒ) ride as alternates of a/ɑ in the crowded open row. Near-close ɪ ʏ ʊ are inline in the close row (lateral position ≈ centrality; spacers mark front/central/back).
- Secondary stress ˌ is a long-press alternate of ˈ; secondary articulations ʲ ʷ ˠ ˤ hang off ʰ; ˑ and ◌̆ hang off ː; ◌̺ ◌̻ hang off ◌̪; ◌̯ off ◌̩; ‿ off ".".
- Chart-pure: no ɚ/ɝ keys (rhoticity is the ˞ diacritic).
- Tones (issue #29): 5th "Tones" panel (cycle Stops→Fricatives→Vowels→More→Tones→Stops, 2 rows). Level bars ˥˦˧˨˩ are primaries with the combining tone marks (U+030B/0301/0304/0300/030F) as alternates; only rising ˩˥ and falling ˥˩ ship as contour sequences (alts ◌̌ U+030C / ◌̂ U+0302). ipa-full instead compacts everything into 2 keys in its suprasegmentals row: ˥ (alts ˦˧˨˩) and ꜜ (alts ꜛ ↗ ↘).

**Shared budgets (mirror of ipa-full, enforced by BundledLayoutTests):** max 3 symbol rows per panel (totalRowCount ≤ 4), ≤ 10 interactive keys per row, width-factor sum ≤ 12.0 per row; panels form a single switch-key cycle (chart cycle test locks panels.count == 5 since #29).

**System-QWERTY grid convention (ipa-full, issue #101):** the QWERTY panel's three rows sit on a shared 10-unit grid — row 1 ten plain keys; row 2 flanked by 0.5-unit spacers (system half-key indent); row 3 flanked by 1.5-unit spacers (shift/backspace footprints left empty as placeholders). Rule: any row containing a spacer should total exactly the panel's gridReferenceFactor (densest row incl. bottom bar) so spacers sit at their minimum and geometry is deterministic. Known residual: the renderer subtracts keySpacing×(elements−1) per row before dividing, so rows with different element counts differ by ~0.6pt/gap in key width — exact cross-row equality is impossible data-only; don't chase it with spacer tricks, it needs a renderer change. Guarded by `genericFullQwertyPanelMatchesSystemKeyboardGeometry`.

**Bundled-layout UUID house pattern:** `7E5A1C00-0000-4000-8000-` + 12 hex digits whose bytes spell an ASCII tag (`006368617274` = "chart", `00656E2D5553` = "en-US"). Tests select bundled layouts **by name** ("IPA — Full (QWERTY)", "IPA — Chart"), not by locale — several layouts share locale `und`. Related: [[unicode-traps-and-verification]].
