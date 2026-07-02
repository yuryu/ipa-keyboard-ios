---
name: copilot-review
description: Fetch GitHub Copilot auto-review comments on a PR of this repo, address each one, update the PR, and rerun workflows when needed. Use when a PR has Copilot review feedback to handle.
---

# Handle a PR's Copilot review

Input: a PR number (default: the current branch's PR, `gh pr view --json number`).
Check out the PR's branch; all commands run inside the repo, against
`yuryu/ipa-keyboard-ios`.

## 1. Fetch the feedback

The summary review — Copilot's login is `copilot-pull-request-reviewer` here.
There is one review per round; the last is the current one:

```sh
gh pr view <PR> --json reviews \
  --jq '[.reviews[] | select(.author.login == "copilot-pull-request-reviewer")] | last | .body'
```

The inline comments — Copilot's login is `Copilot` here (yes, different from
above). Top-level comments have `in_reply_to_id == null`; `line` can be null
for file-level comments; bodies may contain fenced `suggestion` blocks:

```sh
gh api repos/yuryu/ipa-keyboard-ios/pulls/<PR>/comments \
  --jq '[.[] | select(.user.login == "Copilot" and .in_reply_to_id == null)
        | {id, path, line, body}]'
```

Both empty? Copilot hasn't reviewed this push yet — wait a couple of minutes,
or re-request (step 3).

## 2. Address each comment on its merits

Copilot is sometimes right, sometimes wrong. Judge each comment:

- **Agree** → apply the fix on the branch.
- **Disagree** → leave the code alone.

Reply either way — "Applied in `<sha>`" or the reason you declined — so
nothing is silently ignored:

```sh
gh api repos/yuryu/ipa-keyboard-ios/pulls/<PR>/comments/<id>/replies -f body='...'
```

## 3. Update the PR

Commit and push to the PR branch, then re-request Copilot review — it does not
re-review new pushes on its own. The `[bot]` suffix is required; the bare
login is rejected with HTTP 422:

```sh
gh api repos/yuryu/ipa-keyboard-ios/pulls/<PR>/requested_reviewers \
  -f 'reviewers[]=copilot-pull-request-reviewer[bot]'
```

## 4. Rerun workflows if needed

Pushing re-triggers CI, so this is only for runs that failed for reasons
unrelated to the change (infra flake, stale run):

```sh
gh run list --branch <branch> --limit 5
gh run rerun <run-id> --failed
```

Finish by reporting what you applied vs. declined. The user does the final
review and merge — never merge the PR yourself.
