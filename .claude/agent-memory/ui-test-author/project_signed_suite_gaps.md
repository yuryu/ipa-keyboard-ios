---
name: signed-suite-gaps
description: Two deterministic UI-test failures that only surface on SIGNED simulator runs (App-Group success branches), found 2026-07-12 during issue #185 verification — plus the two automation mechanics behind them
metadata:
  type: project
---

Running the FULL UI suite signed (App Group available) exercises success branches that unsigned CI never reaches, and two of them fail deterministically on an iOS 26.5 (23F77) iPhone 17 simulator. Both pre-date the #185 branch (files byte-identical to main); reported for the orchestrator to file as issues.

**Why:** CI runs unsigned, so `test_importValid_succeedsOrDegradesGracefully` always takes the alert branch and `test_editorFlow_cancelWithChangesDiscardsDraft` skips at its shared-storage guard. Signing (PR #184) made the row/persistence branches reachable for the first time; nobody had run the whole suite signed since.

**How to apply:** When authoring or verifying against the success branches of App-Group-dependent tests, expect these until fixed:

1. `ImportExportUITests.test_importValid_succeedsOrDegradesGracefully` — app-side: launching with BOTH `--uitest-reset-layouts` and `UITEST_IMPORT_JSON` ends with NO persisted layout file and NO error alert (verified via simctl launches watching the App Group `Layouts/` dir at 30 ms resolution; import alone persists fine, malformed-import alert fires fine). Likely cause: `LayoutListView`'s `@State private var library = LayoutLibrary()` initial-value expression runs on every struct re-init, and each throwaway `LayoutLibrary.init` re-runs the reset deletion.
2. Test-side compounding: `waitForEither(_:_:scrollingSecondIn:)`'s `scrollView.swipeUp()` starts at the layout list's CENTER, which on the library screen lands on the Active-preview `KeyboardView` keys — the key's UIKit press tracker consumes the gesture and the list NEVER scrolls (confirmed by the failure's screen recording: 30 s, zero scroll). Any below-the-fold second element is unreachable there. Press-drag from an off-preview coordinate (like [[LibraryScreen]].waitForRevealed's 0.75->0.25 drag) does not have this problem.
3. `KeyEditorUITests.test_editorFlow_cancelWithChangesDiscardsDraft` — on iOS 26.5 the `confirmationDialog` surfaces `key-editor-discard-confirm` as TWO nested Buttons (identifier bleed onto an inner button; hierarchy: Popover > Sheet 'Discard changes?' > ... > Button > Button, both with the identifier). `app.buttons["key-editor-discard-confirm"].tap()` then fails "Multiple matching elements found" at tap-time (waitForExistence passes — it tolerates multiplicity). `.firstMatch` on the subscript is the likely fix; same class as the two known Section/KeyboardView identifier-bleed bugs.
