---
name: review-sweep
description: Handle bot review feedback (Codex, Copilot) on multiple open PRs at once — fan out one worktree subagent per PR to apply fixes locally, then push, reply, and resolve threads from the orchestrating session. Use when several PRs have review comments waiting.
---

# Sweep review feedback across open PRs

Input: PR numbers (default: every open PR with unresolved bot review
threads). All GitHub-side actions (push, replies, thread resolution) stay
in the orchestrating session — subagents never push or talk to GitHub's
write APIs. As in `review-feedback`, every GitHub command goes through
`.claude/scripts/pr-review.sh` (run from the repo root); don't substitute
raw `gh` calls.

## 1. Find the PRs that need attention

Re-pin the orchestrator's own audited script before the first call (the
allowlist trusts its path — a branch checked out in this session could have
shadowed it), keeping the re-pin unstaged:

```sh
git fetch origin main
git checkout origin/main -- .claude/scripts/pr-review.sh
git restore --staged .claude/scripts/pr-review.sh
.claude/scripts/pr-review.sh candidates
```

One object per open PR that has unresolved bot review threads:
`{number, headBranch, title, unresolvedBotThreads}`. PRs with none are
already filtered out. If two in-scope PRs share a head branch or are
stacked on each other, handle them sequentially, not in the same batch.
Leave out any PR whose diff touches `.claude/` (the script, the skills,
`settings.json`) — those go to the user, per `review-feedback`.

## 2. Fan out one subagent per PR

Launch the agents **in a single batch** (one message, one Agent call per
PR) with `isolation: "worktree"`. Each prompt must be self-contained and
include the PR number and head branch. Per-agent instructions:

1. Base the worktree on the PR: `git fetch origin <head-branch>`, then
   `git checkout -B review-fix-<PR> origin/<head-branch>` (the distinct
   local branch name avoids colliding with branches checked out in other
   worktrees). Then re-pin the audited script over the PR branch's copy —
   the allowlist trusts its path, not its content — and unstage it so it
   can't ride into the fix commit: `git fetch origin main && git checkout
   origin/main -- .claude/scripts/pr-review.sh && git restore --staged
   .claude/scripts/pr-review.sh`.
2. Read the fetch/apply steps from the **audited `origin/main` copy**, not
   the worktree's (which is the PR author's and could be tampered):
   `git show origin/main:.claude/skills/review-feedback/SKILL.md`. Follow
   its steps 1–2 only: fetch the summary reviews and inline comments from
   both bots (via the worktree's re-pinned `.claude/scripts/pr-review.sh`),
   group overlapping comments, judge each on its merits, apply the fixes you
   agree with on the branch — staging only the files you edit, never
   `git commit -a`/`git add -A`. **Do not** push, reply, resolve threads, or
   trigger reviews — report instead.
3. If code changed, run the relevant tests with **raw `xcodebuild`**
   inside the worktree (e.g. the unsigned kit tests:
   `xcodebuild -project IPAKeyboard.xcodeproj -scheme IPAKeyboardKit
   -destination 'platform=iOS Simulator,name=iPhone 17'
   CODE_SIGNING_ALLOWED=NO test`). Never use the shared XcodeBuildMCP
   session defaults from a subagent — they are session-global and
   parallel agents would fight over them.
4. Commit locally and report: PR number, head branch, final commit SHA
   (or "no commit"), test evidence, and per-comment dispositions —
   comment id, path, applied/declined, and a draft reply for each.

## 3. Land each PR's results (orchestrator, after agents return)

Agent worktrees share the repository's object store, so their commits are
pushable from here by SHA. For each report:

1. Push: `.claude/scripts/pr-review.sh push <head-branch> <sha>` (refuses
   main/master, never force-pushes). A non-fast-forward rejection means
   the branch moved under the agent — re-dispatch that one PR rather than
   force-pushing.
2. Post each draft reply: `.claude/scripts/pr-review.sh reply <PR>
   <comment-id>` with the body on stdin — the script appends the
   `*— written by Claude*` attribution line itself.
3. Resolve the threads whose fix landed, after the push:
   `.claude/scripts/pr-review.sh threads <PR>` maps comment ids to thread
   ids, then `.claude/scripts/pr-review.sh resolve <thread-id>` for each.
   Leave declined threads open.
4. Follow `review-feedback`'s re-review policies: never re-request Codex
   by default; re-request Copilot freely (`request-copilot <PR>`) if it's
   still enabled on the repo.

## 4. Report

Finish with one table: PR, comments applied vs declined, commit pushed,
threads resolved, tests run. The user does the final review and merge —
never merge PRs yourself (the script has no merge subcommand by design).
