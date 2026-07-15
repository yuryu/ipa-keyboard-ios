---
name: project-known-prefailing-uitests
description: Two UI tests fail deterministically on a signed fresh iOS 26.5 simulator (2026-07-12), independent of any in-flight branch — verified by stash/rerun
metadata:
  type: project
---

Found 2026-07-12 during issue #187 verification (full signed sequential UI run on a freshly created iPhone 17 / iOS 26.5 simulator). Both failures reproduce identically WITH and WITHOUT the #187 diff (proven via `git stash` + scoped rerun on the same simulator), so they are pre-existing on the `ci-signed-archive-lane` base (db0cb37):

1. `ImportExportUITests.test_importValid_succeedsOrDegradesGracefully` — fails "Neither the shared-storage alert nor the imported row appeared within 30.0s of a valid import". Notable: the build was SIGNED (App Group container should be available), yet neither the success branch (imported row) nor the degraded branch (shared-storage alert) materialised. Root cause not yet diagnosed — check the xcresult tearDown screenshot first.
2. `KeyEditorUITests.test_editorFlow_cancelWithChangesDiscardsDraft` — fails "Multiple matching elements found" tapping `key-editor-discard-confirm`: the confirmation dialog (rendered inside a Popover on this OS) exposes TWO nested `Button` elements both carrying that identifier, and the test taps a non-`firstMatch` query. Same nested-button identifier-duplication family as the [[project_uitest_baseline]] bleed bugs.

**Why:** Recorded so future suite runs don't attribute these to fresh changes and re-burn a stash/bisect cycle; orchestrator was asked (issue #187 report) to file both as issues.

**How to apply:** If these two fail in a full-suite run, they are expected until their fixes land; verify against the current code before assuming still-broken. Remove this memory once both are fixed.
