---
name: pr-workflow
description: How work lands in this repo — when an issue is required, branch creation with gh issue develop, PR body rules, issue conventions and labels, and handling Codex/Copilot review feedback. Use before creating a branch, opening a PR, or filing an issue.
---

# Branch, issue, and PR conventions

Everything lands through PRs — code and docs alike. `main` is protected (PR + green CI, squash-merge only) and only moves by merging a PR.

## Per work item

1. **Substantial work starts from an issue** — feature work, behavior changes, anything needing context or acceptance criteria:
   `gh issue develop <n> --name <ascii-name> --checkout`.
   **Small self-contained changes need no issue** (docs tweaks, typo fixes, agent-memory updates, mechanical chores): `git checkout -b <short-name>`, and the PR body is the record.
2. **Commit and push freely on the branch** — PR review replaces ask-before-committing.
3. **Open the PR** with `gh pr create`, following `.github/pull_request_template.md`. Squash-merge discards branch commit messages (the squash commit takes the PR title + body), so the body must stand alone: summary, test evidence (which suites ran and their results), and `Fixes #<n>` when it closes an issue — in the **body**, not only in a commit message.
4. **The user reviews and merges — don't merge a PR unless asked.** On merge the branch auto-deletes and `Fixes #<n>` closes the issue.

Keep PRs small and short-lived: one work item = one branch = one PR; independent items proceed in parallel on separate branches.

`--name <ascii-name>` is not optional: issue titles routinely contain IPA characters and `gh issue develop` copies the title into the branch name. Don't plan on renaming later — pushing under a new name and deleting the old closes the open PR.

## Issue conventions (`yuryu/ipa-keyboard-ios`)

- Before feature work, check `gh issue list` and `gh issue view <n>` — issues are written so a fresh session can act on them (context, file pointers, acceptance criteria, owning subagent).
- Substantial work with no issue yet? File one first (`gh issue create`). File discovered work as new issues, not code TODOs or roadmap task lists.
- Labels map to areas (and to subagents): `layouts` (`ipa-data-curator`), `host-app` (`layout-editor-ui`), `keyboard-ext` (`keyboard-extension-builder`), `testing` (test authors), `infra` (CI/signing/provisioning), `deferred` (parked by design).

## Review feedback

OpenAI Codex auto-reviews each new PR (P0/P1 only, steered by "Review guidelines" in `AGENTS.md`). Handle bot feedback (Codex and Copilot) with the **user-level** `review-feedback` skill, or `review-sweep` for several PRs at once — both live in the user's `~/.claude/skills/`, not in this repo, so they are unavailable on a fresh clone elsewhere. The user may also run `/code-review ultra <PR#>` for a deeper review.
