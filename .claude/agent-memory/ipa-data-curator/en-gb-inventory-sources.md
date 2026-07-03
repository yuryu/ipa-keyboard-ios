---
name: en-gb-inventory-sources
description: en-GB (SSB) layout decisions - dictionary-convention primary layer vs Lindsey alternates, sources, the ɜ/ɛ trap, and which contested SSB symbols were deliberately skipped
metadata:
  type: project
---

en-GB.json (issue #74, 2026-07-02) keys its **primary layer to the UK pronunciation-dictionary convention** (Wells LPD / CEPD, as documented on the OALD pronunciation key, and Roach 2004 JIPA "British English: Received Pronunciation"): DRESS **e**, LOT **ɒ** U+0252, BATH/PALM/START **ɑː** (Wells 1982 trap–bath split), GOAT **əʊ**, long iː uː ɔː ɜː, closing eɪ aɪ ɔɪ aʊ, centring ɪə eə ʊə, weak **i** (happY) / **u** as alternates of iː/uː, lettER = plain ə.

**Lindsey SSB alternates shipped** (Lindsey 2019 *English After RP*; englishspeechservices.com/blog/british-vowels): ɛ (DRESS), ɛː (SQUARE), ɪː (NEAR), a (TRAP). **Deliberately NOT shipped** (too divergent from the primary convention to mix): FLEECE ɪj, GOOSE ɵw/ʉw, LOT ɔ, THOUGHT oː, FOOT ɵ, CURE ɵː, FACE ɛj, PRICE ɑj, GOAT əw, MOUTH aw. **NURSE əː alternate skipped as unresolved**: the blog fetch reported Lindsey uses ɜː for NURSE, conflicting with my recollection that the book/CUBE use əː — don't add without checking the book.

**Marginal /x/ (loch) deliberately omitted** even though the OALD BrE pronunciation key lists it — Roach 2004's 24-consonant core excludes it (review finding, 2026-07-02; revisit only if a user asks for it).

Allophones ride as alternates + More-panel keys, not primary phoneme keys: **ʔ** U+0294 on t (Lindsey ch. 19: glottal stop for /t/ "entirely standard before consonants") and **ɫ** U+026B on l (clear before the nucleus, dark after — Cruttenden's *Gimson's Pronunciation of English*; UManitoba phonetics Dark L page).

**Why:** mixing transcription conventions in one primary layer would be incoherent (e.g. DRESS ɛ implies FACE ɛj); dictionaries are what UK learners/transcribers see, so that layer wins and Lindsey is the long-press layer.

**How to apply:** the layout-local lookalike trap is **ɜ U+025C (REVERSED OPEN E, NURSE) vs ɛ U+025B (OPEN E, DRESS alt)** — both present, visually similar. Non-rhotic negatives are locked by EnGBLayoutTests: no ɚ U+025A, ɝ U+025D, GA oʊ, or tap ɾ U+027E anywhere. UUID tag `00656E2D4742` = "en-GB" per the house pattern in [[layout-authoring-decisions]]. Code points verified per [[unicode-verification-workflow]].
