# IPA Keyboard Privacy Policy

**Effective date:** _TBD — set on first App Store submission_

IPA Keyboard is an iOS/iPadOS app that provides a customizable
International Phonetic Alphabet keyboard: a host app for managing
keyboard layouts, plus a system keyboard extension that does the typing.
This policy describes what the app does — and deliberately does not do —
with your data.

## The short version

**We collect nothing.** IPA Keyboard has no analytics, no advertising,
no accounts, no tracking, and no network code. Everything you type and
every layout you create stays on your device.

## What the keyboard extension does

- **It does not send anything anywhere.** The keyboard extension
  contains no networking code at all. It cannot transmit what you type,
  and it never does.
- **It does not request "Allow Full Access."** The keyboard declares
  `RequestsOpenAccess = false` and is fully functional without Full
  Access. You will never be asked to grant it.
- **It does not log or store keystrokes.** Characters you tap are
  inserted directly into the app you are typing in, and nowhere else.
  To make backspace delete a full character (for example, a base letter
  together with a combining diacritic such as a tone or length mark),
  the keyboard briefly reads a small amount of text immediately before
  the cursor through the standard iOS text-input interface. That text is
  used only to compute how much to delete, is never stored, and never
  leaves the keyboard process.
- **It shows no ads and launches no other apps.**

## What the host app stores, and where

- **Keyboard layouts you create or edit** are saved as JSON files in the
  app's App Group container (`group.net.yuryu.IPAKeyboard`) on your
  device, so the keyboard extension can read the layouts you manage in
  the app.
- **Preferences** — which layout is active and which symbols you have
  hidden per layout — are stored in the same App Group's user-defaults
  store on your device.

The App Group is private to this app and its keyboard extension. No
other app can read it, and nothing in it is uploaded, synced, or backed
up by us (standard iOS device backups may include it, under your own
Apple account and control).

## Data collection summary (App Privacy questionnaire)

For the App Store "App Privacy" section, the accurate answer is
**"Data Not Collected"**: the app and its keyboard extension collect no
data, link nothing to your identity, and do not track you.

The app's privacy manifests (`PrivacyInfo.xcprivacy` in the app and in
the shared framework, the bundle whose code performs the access)
declare the only required-reason API in use — user defaults
(`NSPrivacyAccessedAPICategoryUserDefaults`), with reasons `1C8F.1`
(defaults shared only within the app's own App Group) and `CA92.1`
(defaults accessible to the app itself) — and declare no tracking, no
tracking domains, and no collected data types.

## Third parties

There are none. The app uses no third-party SDKs, libraries, or
services.

## Changes to this policy

If the app's behavior ever changes in a way that affects this policy
(it would have to start doing something it currently does not), the
policy will be updated here with a new effective date before the change
ships.

## Contact

Questions or concerns: open an issue at
<https://github.com/yuryu/ipa-keyboard-ios/issues>.
