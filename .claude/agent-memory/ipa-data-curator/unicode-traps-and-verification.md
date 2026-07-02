---
name: unicode-traps-and-verification
description: Verified IPA/Unicode lookalike traps (clicks, ʡ) and the tier-1 verification workflow that works without Bash
metadata:
  type: project
---

Verified traps and how to re-verify code points in this project.

**Click letters — Unicode names contradict IPA values (verified 2026-07, Unicode 17.0 names list):**
- U+01C2 ǂ is *named* "LATIN LETTER ALVEOLAR CLICK" but its IPA value is the **palatoalveolar** click.
- U+01C3 ǃ is *named* "LATIN LETTER RETROFLEX CLICK" but its IPA value is the **(post)alveolar** click.
- Always label by IPA value, never by Unicode name. Also: ǀ U+01C0 ≠ | U+007C, ǁ U+01C1 ≠ ‖ U+2016, ǃ U+01C3 ≠ ! U+0021. The bundled-layout lookalike test forbids inserting "!", "|" (plus "g", ":", "?", "'").

**ʡ discrepancy:** Unicode's names-list comment for U+02A1 says "voiced epiglottal stop"; the IPA chart says just "epiglottal plosive". We follow the IPA wording (IPA is the authority for phonetic values; Unicode annotations are informative).

**Why:** a wrong code point or name ships as a silent data bug; these are the exact spots where memory fails.

**How to apply / re-verify without Bash:**
- Batch name checks: `https://util.unicode.org/UnicodeJsps/list-unicodeset.jsp?a=%5B%5CuXXXX...%5D` (official Unicode infra, returns U+XXXX + name table).
- Per-char names-list annotations (IPA value comments): `https://util.unicode.org/UnicodeJsps/character.jsp?a=XXXX`.
- The IPA's chart page (internationalphoneticassociation.org/content/full-ipa-chart) is images/PDF only; the WebFetch summarizer refuses to transcribe the chart PDF (copyright caution, though it is CC-BY-SA) — use character.jsp annotations instead for values.
- Byte-verify authored JSON with ripgrep `\x{XXXX}` patterns (positive presence + negative `"text": "[g:?'!|]"` checks). Related: [[layout-authoring-decisions]].
