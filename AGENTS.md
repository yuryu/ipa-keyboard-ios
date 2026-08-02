# IPAKeyboard — agent notes

IPAKeyboard is a universal iOS/iPadOS app providing a customizable
International Phonetic Alphabet keyboard: a host container app plus a
system keyboard extension (`.appex`), sharing code and data through the
`IPAKeyboardKit` framework and an App Group. Keyboard layouts are
versioned `Codable` JSON documents (data, not code); bundled defaults are
read-only and users fork them copy-on-write. Swift 6.0 on all targets,
deployment target iOS 17.0 built with the iOS 26 SDK, no third-party
dependencies. Deeper structure notes live in `CLAUDE.md`.

## Review guidelines

Focus on correctness issues in these project-specific areas — they are
where mistakes are easy to make and expensive to ship:

- **Unicode exactness.** IPA layouts and character data use precise code
  points. Flag ASCII or lookalike substitutions anywhere in layout JSON or
  IPA data: `g` U+0067 vs `ɡ` U+0261, `:` U+003A vs `ː` U+02D0, `'` vs
  `ʼ` U+02BC, precomposed vs combining-diacritic forms. When a symbol
  changes, check the actual code point, not the glyph's appearance.
- **Grapheme-cluster awareness.** All text editing against the document
  proxy must treat user-perceived characters (base + combining
  diacritics) as single units — especially backspace/deletion. Flag any
  string manipulation that indexes by `UTF16`/scalar counts where a
  `Character` (grapheme) boundary is intended.
- **API availability.** Deployment target is iOS 17.0 on the iOS 26 SDK.
  Any API introduced after iOS 17 needs an `@available` guard. Don't
  suggest raising the deployment target.
- **Extension-safe API only.** `IPAKeyboardKit` builds with
  `APPLICATION_EXTENSION_API_ONLY = YES` and is linked into the keyboard
  extension. Flag use of extension-unavailable API (e.g.
  `UIApplication.shared`) in the framework or extension targets.
- **Never mutate built-in layouts.** Bundled layouts are read-only; user
  edits go through `KeyboardLayout.makeEditableCopy(named:)` (new `id`,
  `isBuiltIn = false`). Symbol curation is non-destructive
  (`applyingHiddenSymbols(_:)` returns a filtered copy; hidden sets live
  in `KeyboardPreferences`, never in the layout document).
- **Graceful degradation without the App Group.** `AppGroup.containerURL`
  is still nil wherever the App Group entitlement isn't embedded — the
  unhosted kit-test runner, and any build made with
  `CODE_SIGNING_ALLOWED=NO`. (CI's app-scheme lanes now sign ad-hoc and do
  have a container; the kit scheme still doesn't.) So this stays a
  permanent requirement, not a provisioning stopgap: storage and
  preferences code must fall back (bundled defaults, `.standard`
  UserDefaults) rather than crash or silently lose data.
- **Keyboard-extension constraints.** Tight memory budget (~48–66 MB), no
  network, no full access assumed; the globe key must respect
  `needsInputModeSwitchKey`.
- **Schema versioning.** Layout JSON carries a schema version
  (`currentSchemaVersion = 2`); older versions migrate on decode,
  newer-than-supported versions are rejected, never downgraded. Flag
  schema-shape changes that skip the migration/version bump.
- **Tests.** Unit targets (`IPAKeyboardKitTests`, `IPAKeyboardTests`) use
  Swift Testing (`#expect`), the UI target (`IPAKeyboardUITests`) uses
  XCUITest. Behavior changes should come with matching test updates.
