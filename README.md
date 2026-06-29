# IPAKeyboard

[![CI](https://github.com/yuryu/ipa-keyboard-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/yuryu/ipa-keyboard-ios/actions/workflows/ci.yml)

A customizable International Phonetic Alphabet keyboard for iOS and iPadOS.
IPAKeyboard is a system custom keyboard — a host container app plus a keyboard
extension — that ships good default IPA layouts per language-dialect and lets
you compose and edit the symbol set you actually use.

> **Status: early-stage prototype.** The data model, layout store, and a
> bundled `en-US` default exist; the keyboard extension and host UI are still
> being built, and code signing is deferred (the Apple developer account is
> mid-relocation), so the framework builds standalone but a full signed
> app/extension build does not yet run.

## What makes it different

- **Customizable layouts as data.** Keyboard layouts are versioned, hand-
  editable JSON documents, not code — so you can add and fork them.
- **Multi-symbol keys.** A key can surface related sounds (allophones and
  variants like `pʰ` from `p`) without a separate key.
- **Multiple arrangements per dialect** (planned): a split consonants/vowels
  layout and a QWERTY-style full layout, plus a secondary panel for less-common
  symbols — all selectable from the setup screen.

See [`docs/ROADMAP.md`](docs/ROADMAP.md) for the full product direction and
[`CLAUDE.md`](CLAUDE.md) for architecture, build/test commands, and constraints.

## Building

Requires Xcode with the iOS 26.5 SDK. Build the project directly (there is no
`.xcworkspace`):

```sh
# Framework only, no signing (validates the kit + bundled JSON)
xcodebuild -project IPAKeyboard.xcodeproj -scheme IPAKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -target IPAKeyboardKit CODE_SIGNING_ALLOWED=NO build

# IPAKeyboardKit unit tests
xcodebuild -project IPAKeyboard.xcodeproj -scheme IPAKeyboardKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO test
```

## License

[MIT](LICENSE)
