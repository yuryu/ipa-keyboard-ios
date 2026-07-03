---
name: unicode-traps-and-verification
description: Verified IPA/Unicode lookalike traps (clicks, ʡ, tone/word-accent marks, group marks) and the tier-1 verification workflow that works without Bash
metadata:
  type: project
---

Verified traps and how to re-verify code points in this project.

**Click letters — Unicode names contradict IPA values (verified 2026-07, Unicode 17.0 names list):**
- U+01C2 ǂ is *named* "LATIN LETTER ALVEOLAR CLICK" but its IPA value is the **palatoalveolar** click.
- U+01C3 ǃ is *named* "LATIN LETTER RETROFLEX CLICK" but its IPA value is the **(post)alveolar** click.
- Always label by IPA value, never by Unicode name. Also: ǀ U+01C0 ≠ | U+007C, ǁ U+01C1 ≠ ‖ U+2016, ǃ U+01C3 ≠ ! U+0021. The bundled-layout lookalike test forbids inserting "!", "|" (plus "g", ":", "?", "'").

**ʡ discrepancy:** Unicode's names-list comment for U+02A1 says "voiced epiglottal stop"; the IPA chart says just "epiglottal plosive". We follow the IPA wording (IPA is the authority for phonetic values; Unicode annotations are informative).

**Tone/word-accent traps (verified 2026-07-02, issue #29):**
- Downstep/upstep are ꜜ U+A71C / ꜛ U+A71B (Modifier Tone Letters block, encoded for IPA per L2/06-259r) — NOT the full-height arrows ↓ U+2193 / ↑ U+2191, which are a legacy fallback some chart reproductions (e.g. ilg.usc.es/ipa-chart) still use. Global rise/fall are ↗ U+2197 / ↘ U+2198 (those full-size arrows ARE correct).
- The finer contour bar sequences are **contested across chart reproductions**: high rising ˦˥ (USC/IPA-faithful) vs ˧˥ (Wikipedia's IPA-chart article); low rising ˩˨ vs ˩˧; rising-falling ˧˦˧ vs others. The official chart is an image with ligated glyphs, so there's no textual ground truth. We ship only uncontested rising ˩˥ (U+02E9 U+02E5) and falling ˥˩ (U+02E5 U+02E9); finer contours are composed from level bars. Also skipped: combining contour marks U+1DC4–1DC9 (mapping equally contested, poor font support).
- Group marks: major group is ‖ U+2016 DOUBLE VERTICAL LINE (≠ click ǁ U+01C1, spoken label "major intonation group break" keeps them apart). Minor group's only standard mapping is ASCII | U+007C, which the lookalike test forbids — deliberately not shipped, no non-ASCII alternative exists.
- Tone bars are spacing letters (Lm): "˩˥" is two grapheme clusters, backspace peels one bar per press; combining tone marks (U+0300 etc.) delete with their base.

**Why:** a wrong code point or name ships as a silent data bug; these are the exact spots where memory fails.

**How to apply / re-verify without Bash:**
- Batch name checks: `https://util.unicode.org/UnicodeJsps/list-unicodeset.jsp?a=%5B%5CuXXXX...%5D` (official Unicode infra, returns U+XXXX + name table).
- Per-char names-list annotations (IPA value comments): `https://util.unicode.org/UnicodeJsps/character.jsp?a=XXXX`.
- The IPA's chart page (internationalphoneticassociation.org/content/full-ipa-chart) is images/PDF only; the WebFetch summarizer refuses to transcribe the chart PDF (copyright caution, though it is CC-BY-SA) — use character.jsp annotations instead for values.
- Byte-verify authored JSON with ripgrep `\x{XXXX}` patterns (positive presence + negative `"text": "[g:?'!|]"` checks). Strongest closing check: a negated whitelist class `[^\x{0000}-\x{007F}\x{0261}\x{02D0}…]` listing every intended non-ASCII scalar — zero matches proves the file contains *only* accounted-for code points (used to clear en-GB, 2026-07-02). Related: [[layout-authoring-decisions]].
