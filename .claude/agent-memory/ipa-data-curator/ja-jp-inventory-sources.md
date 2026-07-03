---
name: ja-jp-inventory-sources
description: ja-JP (Tokyo) layout inventory decisions, code points, and the Okada 1999 / Vance / Labrune citations behind them (issue #75)
metadata:
  type: project
---

ja-JP.json (issue #75, 2026-07-02) inventory decisions and sources. UUID tag `006A612D4A50` ("ja-JP") per the house pattern in [[layout-authoring-decisions]].

**Canonical source access:** Okada (1999) "Japanese", IPA Handbook illustration, is readable as OCR text via archive.org item `rosettaproject_jpn_phon-2` — fetch `https://archive.org/download/rosettaproject_jpn_phon-2/rosettaproject_jpn_phon-2_djvu.txt` and follow the redirect WebFetch reports (a `*.eu.archive.org` host). The Cambridge/JIPA page serves only metadata. OCR is noisy (ɡ→"9", ɕ→"c", ɸ→"$", ç→"9") but quotes are recoverable.

**Decisions (all code points verified via util.unicode.org list-unicodeset, see [[unicode-verification-workflow]]):**
- **ɯ U+026F primary, u alternate.** Okada writes phonemic /u/ but: "resembling [ɯ] auditorily, has compressed lips, so that it is unrounded but without spreading; it could be transcribed narrowly as [ɯ̈]". Vance (2008), Labrune (2012) transcribe [ɯ]. The ◌̈ U+0308 "centralized" key exists for Okada's narrow [ɯ̈]. Contested claim that /u/ is really central/front [ʉ~ʏ] (2016 paper) NOT adopted.
- **Moraic nasal = ɴ U+0274** (Okada: uvular utterance-finally; nasalized vowel before vowels/approximants/fricatives → ◌̃ U+0303; homorganic [m n ŋ] elsewhere → own keys). Narrow [ɰ̃] not shipped (composable: ɰ alternate of w + ◌̃).
- **Sibilants:** ɕ U+0255, ʑ U+0291 own keys; affricates ts, tɕ own keys; **dz alternate of z, dʑ alternate of ʑ** (phonological pairing — Okada: "/z/ tends to be [dz] initially and after /ɴ/" — deviates from ipa-chart's voiceless→voiced alternate rule on purpose).
- **ɸ U+0278, ç U+00E7 (precomposed NFC)** — Okada: /h/ → [ç]/[ɸ] before /i/,/u/. No hʲ needed (hj → ç).
- **Tap ɾ U+027E** primary; alternates ɾʲ, ɺ U+027A (lateral flap, Vance/L&M), l, ɹ U+0279, r (Okada's phonemic chart symbol, IPA trill). **[l]/[ɹ] source caution:** Okada's sentence "A postalveolar [?] is not unusual in all positions" reads [ɹ] in the archive.org OCR but was quoted as [l] during authoring — the OCR garbles IPA inside brackets, so don't quote either reading exclusively without a print copy. Wikipedia's Japanese phonology (citing Okada 1999) attests [ɾ], [l], AND [ɹ], so shipping both l and ɹ as alternates is safe either way (review finding, 2026-07-02).
- **Palatalized series as alternates:** pʲ bʲ kʲ ɡʲ mʲ ɾʲ (ʲ U+02B2; Okada "/j/ affects the preceding consonant as /i/ does", [mʲaku]; Labrune: palatalized n is written [ɲ] U+0272 — own key, no nʲ alternate). No tʲ/dʲ/sʲ/zʲ (those surface as tɕ/dʑ/ɕ/ʑ).
- **Gemination = doubled letters** ([ɡakkoː] in Okada's passage), vowel length ː U+02D0 — **no sokuon key by design**.
- **Devoicing ◌̥ U+0325 primary, ◌̊ U+030A alternate** (official IPA chart licenses ring above for descender symbols, e.g. ŋ̊). Okada: "/i, u/ tend to be devoiced ... between voiceless consonants".
- **Pitch accent = combining acute ◌́ U+0301** ("A mora transcribed with an acute accent, á, is said to be accented and is high" — Okada), plus **ꜜ U+A71C downstep** as the accent-kernel notation of the wider literature (tier caveat: widespread but not in the Handbook illustration itself). No stress marks ˈ ˌ — Japanese has no stress.

**Why:** dialect inventories are exactly where memory fails; these placements deliberately deviate from generic-layout compaction rules and someone will "fix" them without the citations.

**How to apply:** when editing ja-JP.json or reviewing PRs against it, keep these placements unless a higher-tier source contradicts; JaJPLayoutTests.swift locks the scalars. Cross-layout spoken-name rule: the same inserted string must keep one accessibilityLabel across bundled layouts — U+0301 is "combining high tone" in both ipa-chart.json and ja-JP.json; don't introduce a divergent name like "pitch accent (high)" in a dialect layout.
