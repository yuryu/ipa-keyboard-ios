---
name: keyboardextension-folder-syncs-to-kit
description: KeyboardExtension/ folder now syncs to the KeyboardExtension target (Info.plist excepted) — the old kit-membership quirk is gone
metadata:
  type: project
---

The `KeyboardExtension/` file-system-synchronized folder is now a member of the **KeyboardExtension target** itself: the only `PBXFileSystemSynchronizedBuildFileExceptionSet` for it excepts `Info.plist`. New `.swift` files dropped in `KeyboardExtension/` compile into the extension target directly (e.g. `NextKeyboardKeyOverlay.swift`, `InputClickFeedback.swift` live there today). Re-verified 2026-07-04 in `project.pbxproj`.

**History:** an earlier project layout had this folder synced into the IPAKeyboardKit target with per-file exceptions, which once made two new extension-side files silently compile into the kit. That wiring no longer exists — do not work around it.

**How to apply:** extension-runtime code can be added as new files under `KeyboardExtension/` without touching project.pbxproj. Kit code still goes under `IPAKeyboardKit/`. `IPAKeyboardUITests/`, `IPAKeyboardKitTests/`, `IPAKeyboardTests/`, and `IPAKeyboard/` are likewise plain synchronized root groups — new files join their target automatically.
