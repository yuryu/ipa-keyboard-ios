---
name: graceful-degradation
description: How the host UI detects and handles the App Group container being unavailable before provisioning
metadata:
  type: project
---

Signing/App Group provisioning is deferred, so on the current simulator
`LayoutStore.save`/`delete` may throw `StoreError.sharedContainerUnavailable`
(the only case in that enum). Built-ins (`bundledLayouts()`) and reading
`userLayouts()` still work — only writes fail.

The host UI detects this lazily, not up front: there is no kit API to probe the
container without a write, so `LayoutLibrary.containerAvailable` starts `true`
and flips `false` the first time a `save`/`delete` reports
`sharedContainerUnavailable`. The list shows a footer notice
(`layout-list-container-unavailable`) once that happens, and `errorMessage`
drives an alert.

**Why:** CLAUDE.md mandates degrading gracefully before provisioning — load and
preview built-ins, never crash or force-unwrap on the nil-container path.
**How to apply:** don't add eager container-availability checks or new kit API to
detect it; keep the lazy flip-on-failure approach until real provisioning lands.
