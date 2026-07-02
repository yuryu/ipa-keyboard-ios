# IPAKeyboard

[![CI](https://github.com/yuryu/ipa-keyboard-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/yuryu/ipa-keyboard-ios/actions/workflows/ci.yml)

A customizable International Phonetic Alphabet keyboard for iOS and iPadOS.
IPAKeyboard is a system custom keyboard — a host container app plus a keyboard
extension — that ships good default IPA layouts per language-dialect and lets
you compose and edit the symbol set you actually use.

> **Status: early-stage prototype.** The keyboard extension and the host app's
> layout-management UI exist; key-level layout *editing* is next. Code signing
> is deferred (the Apple developer account is mid-relocation), so the framework
> builds standalone but a full signed app/extension build does not yet run.
> For what's delivered and what's planned, see
> ["Where we are"](docs/ROADMAP.md#where-we-are) and
> [GitHub Issues](https://github.com/yuryu/ipa-keyboard-ios/issues).

## What makes it different

- **Customizable layouts as data.** Keyboard layouts are versioned, hand-
  editable JSON documents, not code — so you can add and fork them.
- **Multi-symbol keys.** A key can surface related sounds (allophones and
  variants like `pʰ` from `p`) without a separate key.
- **Dialect and generic layouts**: curated per-dialect layouts (e.g. `en-US`,
  a phonetic split of consonants and vowels) alongside generic,
  dialect-independent layouts covering most of the IPA inventory (the
  QWERTY-positioned "IPA — Full" layout ships today; more to come) — each
  selectable from the library, with a secondary panel for less-common symbols
  and per-layout curation of which symbols are enabled.

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the full product direction and
[`CLAUDE.md`](CLAUDE.md) for architecture, build/test commands, and constraints.

## Building

Requires Xcode with the iOS 26.5 SDK. Build the project directly (there is no
`.xcworkspace`):

```sh
# Framework only, no signing (validates the kit + bundled JSON)
xcodebuild -project IPAKeyboard.xcodeproj -scheme IPAKeyboardKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO build

# IPAKeyboardKit unit tests
xcodebuild -project IPAKeyboard.xcodeproj -scheme IPAKeyboardKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO test
```

## License

[MIT](LICENSE)
