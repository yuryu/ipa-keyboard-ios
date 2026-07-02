---
name: unicode-verification-workflow
description: Which tier-1 Unicode sources actually work through WebFetch in this environment, and which fail (chart PDFs, UCL phonetics)
metadata:
  type: reference
---

Working tier-1 verification paths for code points (used for issue #15, 2026-07-01):

- `https://util.unicode.org/UnicodeJsps/character.jsp?a=XXXX` — official Unicode Utilities; returns name, block, general category, combining class per code point. Reliable via WebFetch.
- `https://www.unicode.org/Public/UCD/latest/ucd/NamesList.txt` — plain text; WebFetch can answer per-code-point queries including the IPA usage annotations ("IPA: nasalization", "IPA: unreleased stop", ...). Best single source for "is this the IPA diacritic I think it is".

Dead ends in this environment:

- unicode.org chart PDFs (e.g. U0300.pdf) — WebFetch can't parse the PDF, and local Read of the saved PDF fails (`pdftoppm`/poppler not installed on this machine).
- .edu PDFs (UAlberta/SFU handouts) — same PDF-parsing failure; rely on WebSearch result excerpts + cite the URL.
- `phon.ucl.ac.uk` (John Wells's IPA–Unicode page) — connection refused (ECONNREFUSED) as of 2026-07-01.
- internationalphoneticassociation.org serves its chart/diacritics sections as images — no extractable text; cross-verify IPA values via the UCD NamesList annotations instead.

**How to apply:** verify every code point via character.jsp, and its IPA meaning via NamesList.txt; after editing JSON, byte-verify with Grep hex escapes (`\x{0303}`, `\x{25CC}\x{0303}`) so lookalikes/normalization drift can't hide. Related: [[en-us-diacritics-sources]].
