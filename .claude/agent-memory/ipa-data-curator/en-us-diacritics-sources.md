---
name: en-us-diacritics-sources
description: The five combining diacritics chosen for en-US narrow transcription (issue #15), exact code points, and the sources that justify each
metadata:
  type: project
---

en-US.json "More" panel row 3 carries exactly five combining diacritics for General American narrow transcription (issue #15). Code points verified against the Unicode UCD (util.unicode.org character.jsp + NamesList.txt IPA annotations):

- U+0303 COMBINING TILDE — nasalized (vowels before syllable-final nasals: man [mæ̃n]; nasal tap ɾ̃)
- U+0325 COMBINING RING BELOW — voiceless (approximants devoiced after initial /p t k/: play [pl̥eɪ], tree [tɹ̥i])
- U+0329 COMBINING VERTICAL LINE BELOW — syllabic (button [ˈbʌʔn̩], bottle [ˈbɑɾl̩])
- U+032A COMBINING BRIDGE BELOW — dental (alveolars before /θ ð/: tenth [tɛn̪θ], width [wɪd̪θ])
- U+031A COMBINING LEFT ANGLE ABOVE — no audible release (apt [æp̚t], cat [kæt̚])

**Why:** these are the five GA allophonic processes named in Ladefoged & Johnson, *A Course in Phonetics* (English allophone rules), corroborated by UAlberta Ling 205 allophone summary (sites.ualberta.ca/~tnearey/Ling205/Week4/AllophoneSummary.pdf), SFU transcription guides, and Ball et al., "Advanced Phonetic Transcription" (ASHA, doi 10.1044/cicsd_36_F_103). Aspirated ʰ (U+02B0, a spacing modifier letter, not combining) was deliberately left out of en-US to keep the issue scoped to combining marks; it exists in ipa-full.json. Candidate follow-up if anyone asks for it.

**How to apply:** key pattern is text = bare combining mark, label = U+25CC dotted circle + mark, spoken accessibilityLabel matching ipa-full.json wording ("nasalized", "voiceless", "syllabic", "no audible release"; new: "dental"). No normalization applied — marks are stored as single raw scalars in NFC-irrelevant position (after a quote, nothing to compose with). See [[unicode-verification-workflow]].
