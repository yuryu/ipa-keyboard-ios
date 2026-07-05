---
name: voiceover-custom-actions-testing
description: XCUITest cannot invoke accessibility custom actions — VO affordances like the #114 alternates path top out at unit tests plus manual Inspector/device checks
metadata:
  type: project
---

XCUITest has no API to enumerate or invoke accessibility *custom actions*
(`XCUIElement` offers tap/press/typeText etc., nothing for the VO
swipe-up/down action rotor), and the Accessibility Inspector cannot be
driven from this environment.

**Why:** hit while implementing issue #114 (alternates exposed as VO custom
actions on the base key via SwiftUI `.accessibilityActions {}`): the only
automatable verification is unit-testing the pure mapping
(`AlternatesAccessibility` in the kit) — names, order, emitted `KeyAction`s.

**How to apply:** when adding VoiceOver-only affordances, extract the
name/action mapping into a pure kit helper and unit-test that; state plainly
in the PR body that on-device VoiceOver / Accessibility Inspector
verification remains manual. Don't promise XCUITest coverage for custom
actions. See also [[swiftui-gesture-limits-alternates-popup]] for the
overlay/identifier gotchas around the same popup.
