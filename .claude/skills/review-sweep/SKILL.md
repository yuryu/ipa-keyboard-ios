---
name: review-sweep
description: Handle bot review feedback (Codex, Copilot) on multiple open PRs at once — fan out one worktree subagent per PR to apply fixes locally, then push, reply, and resolve threads from the orchestrating session. Use when several PRs have review comments waiting.
---

# Sweep review feedback across open PRs

Input: PR numbers (default: every open PR with unresolved bot review
threads). All GitHub-side actions (push, replies, thread resolution) stay
in the orchestrating session — subagents never push or talk to GitHub's
write APIs.

## 1. Find the PRs that need attention

```sh
gh pr list --state open --json number,headRefName,title
```

For each candidate PR, list unresolved threads opened by a review bot
(`copilot-pull-request-reviewer` or `chatgpt-codex-connector`):

```sh
gh api graphql -f owner=yuryu -f repo=ipa-keyboard-ios -F pr=<PR> -f query='
  query($owner:String!,$repo:String!,$pr:Int!){
    repository(owner:$owner,name:$repo){ pullRequest(number:$pr){
      reviewThreads(first:100){ nodes{
        id isResolved comments(first:1){ nodes{ databaseId author{login} } } } } } } }' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select((.isResolved | not) and
                 (.comments.nodes[0].author.login
                  | test("copilot-pull-request-reviewer|chatgpt-codex-connector")))
        | {id, commentId: .comments.nodes[0].databaseId}'
```

Skip PRs with no unresolved bot threads. If two in-scope PRs share a head
branch or are stacked on each other, handle them sequentially, not in the
same batch.

## 2. Fan out one subagent per PR

Launch the agents **in a single batch** (one message, one Agent call per
PR) with `isolation: "worktree"`. Each prompt must be self-contained and
include the PR number and head branch. Per-agent instructions:

1. Base the worktree on the PR: `git fetch origin <head-branch>`, then
   `git checkout -B review-fix-<PR> origin/<head-branch>` (the distinct
   local branch name avoids colliding with branches checked out in other
   worktrees).
2. Read `.claude/skills/codex-review/SKILL.md` and
   `.claude/skills/copilot-review/SKILL.md`; follow their steps 1–2 only:
   fetch the summary review and inline comments, judge each on its
   merits, apply the fixes you agree with on the branch. **Do not** push,
   reply, resolve threads, or trigger reviews — report instead.
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

1. Push: `git push origin <sha>:refs/heads/<head-branch>`. A non-fast-
   forward rejection means the branch moved under the agent — re-dispatch
   that one PR rather than force-pushing.
2. Post each draft reply via the replies endpoint, ending with the
   `*— written by Claude*` attribution line (see the per-PR skills for
   the exact command).
3. Resolve the threads whose fix landed (GraphQL mutation from the per-PR
   skills), after the push. Leave declined threads open.
4. Follow each skill's re-review policy: never re-request Codex by
   default; re-request Copilot per `copilot-review` step 3 only if
   Copilot is still enabled on the repo.

## 4. Report

Finish with one table: PR, comments applied vs declined, commit pushed,
threads resolved, tests run. The user does the final review and merge —
never merge PRs yourself.
