---
name: copilot-review
description: Respond to GitHub Copilot auto-review comments on a pull request — triage the suggestions, apply or decline each with a reply, resolve threads, re-request Copilot review, rerun workflows if safe, and wait until the PR is ready for the user's final review and merge.
---

# Handling Copilot auto-reviews

Copilot auto-reviews every PR on this repo (`copilot-pull-request-reviewer`): one summary review plus inline review threads, some with ` ```suggestion ` blocks. The driver is `.claude/skills/copilot-review/copilot.sh` (paths relative to repo root) — bash over `gh` + `python3`, both already on the machine; no setup. Run `copilot.sh` with no args for the subcommand list.

The end state you are working toward: **checks green, no Copilot re-review pending, every Copilot thread replied-to and resolved** — then tell the user the PR is ready for their final review. **Never merge; the user merges.**

## The loop (agent path)

```bash
SKILL=.claude/skills/copilot-review/copilot.sh

# 1. What needs attention? (all open PRs, or one)
$SKILL prs                # unresolved-thread counts + check rollup per open PR
$SKILL summary 47         # Copilot's review summary body
$SKILL threads 47         # unresolved Copilot threads as JSON: threadId, commentId, path, line, bodies
```

2. **Triage each thread on its merits.** Copilot is often right about small things and confidently wrong about intent — check its claim against the code and the PR/issue description before acting. Then, per thread:
   - **Accept** → make the fix on the PR branch, commit, push. Suggestion blocks cannot be applied via API — edit the file locally.
   - **Decline** → no code change; your reply carries the reasoning.

3. **Reply to every thread, then resolve it.** Never resolve silently — the reply is the audit trail (say what you changed + the commit SHA, or why you declined):

```bash
$SKILL reply 47 3514812939 'Accepted — restored in 8da42ef.'   # 3rd arg = the thread's FIRST (Copilot) commentId — not a reply's id
$SKILL resolve PRRT_kwDOTIIYJ86N-JVd                           # threadId from `threads`
```

4. **If you pushed fixes, re-request a Copilot review** so it validates the new code (it re-reviews in ~1–2 min; while pending, `prs`/`wait` show `copilotReviewPending: true`):

```bash
$SKILL rerequest 47
```

5. **Rerun workflows only when safe.** Safe = the failure is infra/flake (simulator boot, runner death) and no code changed since; or the run is stale after your push. Not safe = rerunning to "see if it passes" on a real failure, or touching runs on a branch another session owns.

```bash
$SKILL runs 47                     # runs on the PR's head branch
$SKILL rerun 28607278304           # whole run; add --failed for failed jobs only
```

6. **Wait for ready.** Run in background Bash; it polls (60 s default, `COPILOT_POLL_INTERVAL` to override) until checks are green **and** no Copilot re-review is pending **and** all Copilot threads are resolved. Exit 0 = ready → report to the user for final review/merge. Exit 2 = checks failed → investigate (`runs`, then fix or `rerun` per the safety rule) and wait again. Exit 3 = timeout (arg 2, default 1800 s) → look at what's stuck.

```bash
$SKILL wait 47 1800
```

Copilot's re-review may add new threads on your fixes — that's the loop restarting at step 2, not a failure.

## Gotchas

- **Copilot has three different names.** REST comment author: `Copilot`. GraphQL login: `copilot-pull-request-reviewer`. Requesting a review needs the third: `reviewers[]=copilot-pull-request-reviewer[bot]` — the bare login gets HTTP 422 "Reviews may only be requested from collaborators", and `gh pr edit --add-reviewer Copilot` fails with "Could not resolve user". The driver's `rerequest` handles this.
- **`claude.yml` runs on Copilot's review events** and lands as `skipped` or `action_required`. Neither attaches to the PR's check rollup, so they never block readiness — don't chase them, and don't `rerun` an `action_required` run (it awaits user-side approval, not a rerun).
- **Another session may be working the same PR** (observed live on this repo). Before acting on a thread, check its existing replies — a `yuryu` reply means someone already triaged it. The `prs` sweep + thread replies are your coordination surface.
- **Everything the driver does is reversible** except replies-once-seen: `unresolve <threadId>` undoes resolve; a reply can be deleted with `gh api -X DELETE repos/{owner}/{repo}/pulls/comments/<id>`.
- Thread `isOutdated: true` means the commented lines changed since — usually your push already addressed it; still reply + resolve.
- `wait` keys off the rollup *state* (`SUCCESS`/`PENDING`/`FAILURE`…). Individual checks with a `SKIPPED` conclusion roll up into `SUCCESS` (observed with the skipped `claude` checks), so they never block readiness; a PR with no checks at all counts as green.

## Troubleshooting

- `HTTP 422: Reviews may only be requested from collaborators` on rerequest → you used the bare login; it must be `copilot-pull-request-reviewer[bot]` (driver already does).
- `threads` returns `[]` but the PR shows comments → they're all resolved; use `threads <pr> --all`.
