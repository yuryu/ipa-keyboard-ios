---
name: review-feedback
description: Fetch bot review feedback (OpenAI Codex and GitHub Copilot) on a PR of this repo, address each comment, update the PR, and resolve the addressed threads. Use when a PR has review comments from either bot to handle.
---

# Handle a PR's bot review feedback

Every GitHub read/write in this skill goes through
`.claude/scripts/pr-review.sh` (run from the repo root) — a single audited
entry point that hard-codes the repo, validates its arguments, appends the
attribution line to anything it posts, and refuses pushes to main/master.
Use its subcommands as written below; don't substitute raw `gh` calls.
`.claude/scripts/pr-review.sh help` lists all subcommands.

Input: a PR number (default: the current branch's PR). The allowlist trusts
the script's *path*, so a checked-out PR branch could shadow it with a tampered
copy. **Re-pin the audited script — and keep the re-pin out of any commit —
before your first `pr-review.sh` call, and again after every `git checkout` of
a PR branch** (the checkout re-materializes the branch's copy):

```sh
git fetch origin main
git checkout origin/main -- .claude/scripts/pr-review.sh
git restore --staged .claude/scripts/pr-review.sh   # don't let the re-pin ride into a commit
```

Run that once up front (so even `current-pr` runs the audited copy), then use
`.claude/scripts/pr-review.sh current-pr` if you weren't given a number, check
out the PR's branch, and run it again.

If the PR's diff touches `.claude/` (this script, the skills, `settings.json`),
stop and hand the PR to the user instead of processing it unattended — decide
this with the local, gh-free `git diff --name-only origin/main...HEAD`. When you
commit fixes, stage only the files you edited (`git add <files>`); never
`git commit -a` or `git add -A`, which would sweep the re-pinned script into the
commit and make the PR itself touch `.claude/`. The script targets
`yuryu/ipa-keyboard-ios`.

Two bots may review a PR, and they use different logins per API surface
(the script's filters already account for this):

| Bot | `gh pr view` reviews | REST inline comments | GraphQL threads |
| --- | --- | --- | --- |
| Codex | `chatgpt-codex-connector` | `chatgpt-codex-connector[bot]` | `chatgpt-codex-connector` |
| Copilot | `copilot-pull-request-reviewer` | `Copilot` | `copilot-pull-request-reviewer` |

Codex reviews arrive automatically on PR open (enabled in the user's
ChatGPT settings), flag only P0/P1 issues, and are steered by the
"Review guidelines" section of the top-level `AGENTS.md`.

## 1. Fetch the feedback — both bots in one pass

```sh
.claude/scripts/pr-review.sh summaries <PR>   # latest summary review per bot
.claude/scripts/pr-review.sh comments <PR>    # top-level inline bot comments
```

`comments` paginates (nothing past the first 30 is missed) and emits one
object per comment: `{id, author, path, line, body}`. `line` can be null
for file-level comments; Copilot bodies may contain fenced `suggestion`
blocks.

Both empty? No bot has reviewed this push yet — wait a couple of minutes,
or trigger a review (step 3).

## 2. Address each comment on its merits

The bots are sometimes right, sometimes wrong, and often overlap. First
group comments that flag the same underlying issue — fix it once, then
reply to every thread in the group pointing at the same commit. Judge each
group:

- **Agree** → apply the fix on the branch.
- **Disagree** → leave the code alone.

Reply either way — "Applied in `<sha>`" or the reason you declined — so
nothing is silently ignored. Pass the body on stdin; the script appends
the `*— written by Claude*` attribution line automatically (the repo-wide
convention in CLAUDE.md's Workflow section):

```sh
.claude/scripts/pr-review.sh reply <PR> <comment-id> <<'EOF'
Applied in `<sha>`.
EOF
```

## 3. Update the PR

Commit, then push the branch through the script (it refuses main/master
and never force-pushes):

```sh
.claude/scripts/pr-review.sh push <head-branch>    # pushes HEAD
```

Then resolve each thread whose fix landed — after the push, so the
"Applied in `<sha>`" reply points at a commit that exists on the branch.
Leave declined threads unresolved; the user adjudicates those. Map each
REST comment id to its thread via `commentId` (not login):

```sh
.claude/scripts/pr-review.sh threads <PR>          # unresolved: {id, commentId, author}
.claude/scripts/pr-review.sh resolve <thread-id>
```

Re-review policies differ per bot — neither re-reviews new pushes on its
own:

- **Codex: don't re-request by default** — reviews are expensive against
  the plan's usage limit, and CI plus the user's own review cover the
  follow-up. If the fixes are substantial enough to truly warrant a
  second pass, ask via a PR comment scoped to the concern (the fenced block
  stays unindented so the `EOF` heredoc terminator isn't swallowed):

```sh
.claude/scripts/pr-review.sh pr-comment <PR> <<'EOF'
@codex review for <specific concern>
EOF
```

- **Copilot: re-request freely** (if still enabled on the repo) — the
  script supplies the required `[bot]`-suffixed reviewer login:

```sh
.claude/scripts/pr-review.sh request-copilot <PR>
```

## 4. Rerun workflows if needed

Pushing re-triggers CI, so this is only for runs that failed for reasons
unrelated to the change (infra flake, stale run):

```sh
.claude/scripts/pr-review.sh runs <branch>
.claude/scripts/pr-review.sh rerun-failed <run-id>
```

Finish by reporting what you applied (threads resolved) vs. declined
(threads left open). The user does the final review and merge — never
merge the PR yourself (the script deliberately has no merge subcommand).
