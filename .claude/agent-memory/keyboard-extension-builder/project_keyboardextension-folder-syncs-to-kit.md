---
name: keyboardextension-folder-syncs-to-kit
description: New files in KeyboardExtension/ compile into the IPAKeyboardKit target, NOT the extension — only KeyboardViewController.swift belongs to the appex target
metadata:
  type: project
---

The `KeyboardExtension/` file-system-synchronized folder is a member of the **IPAKeyboardKit** target's `fileSystemSynchronizedGroups`, not the KeyboardExtension target's. Membership exception sets in `project.pbxproj` carve out only `KeyboardViewController.swift` (extension target) and `Info.plist`+`KeyboardViewController.swift` (excluded from kit). Verified 2026-07-01 in `IPAKeyboard.xcodeproj/project.pbxproj` (PBXFileSystemSynchronizedBuildFileExceptionSet section, ~lines 88-104).

**Why:** discovered when two new extension-side files (`NextKeyboardKeyOverlay.swift`, `InputClickFeedback.swift`) silently compiled into the kit framework and were unresolvable from the controller; subagents are forbidden from editing project.pbxproj, so they cannot add new exception entries.

**How to apply:** any code that must live in the extension target either goes inside `KeyboardViewController.swift`, or the orchestrator/user must add a membership exception in Xcode (Target Membership checkbox on the new file). Conversely, a file dropped in `KeyboardExtension/` becomes kit code — it must satisfy `APPLICATION_EXTENSION_API_ONLY` and the `.swiftinterface` verification, and internal types there are invisible to the extension module.
