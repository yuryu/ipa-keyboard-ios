---
name: testing-and-ci
description: Test-coverage inventory across the three test targets and the CI lane details (unsigned simulator test jobs plus a signed device-archive job on GitHub Actions). Use when writing or planning tests, changing .github/workflows/**, or debugging CI failures.
---

# Test coverage and CI lanes

Existing coverage spans kit Codable round-trips, `LayoutStore` I/O (via the injectable `containerURL` seam), schema v2 + migration, grapheme deletion, arrangement/bundled-layout checks, app view models (`LayoutDraft`, `OnboardingState`), and host library-UI flows.

CI (`macos-26`) runs two unsigned-simulator test jobs plus a signed archive job:

- `build-and-test` — build-for-testing all three targets + the app-hosted unit-test and UI-test bundles, then kit unit tests and `-only-testing:IPAKeyboardTests`, sequential.
- `ui-test` — build app scheme for testing; fully boot the simulator with `simctl bootstatus -b` — launching the XCUITest runner mid-boot fails with "Busy"; run `IPAKeyboardUITests` sequentially, `-parallel-testing-enabled NO`, via `test-without-building`.
- `signed-archive` — `xcodebuild archive` for `generic/platform=iOS` with automatic signing + `-allowProvisioningUpdates`, authenticated by an App Store Connect API key (repo secrets `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`, `ASC_API_KEY_P8`; the key needs the Admin role for cloud-managed certificates). Proves signing + App Group provisioning for app **and** extension. Runs only on pushes to `main` and `workflow_dispatch` — Dependabot PRs can't read the secrets, so a per-PR run would fail spuriously. Test with `gh workflow run ci.yml --ref <branch>`.

The simulator test jobs stay unsigned (`CODE_SIGNING_ALLOWED=NO`) — signing adds nothing on a simulator.
