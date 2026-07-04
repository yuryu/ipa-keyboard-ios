---
name: review-feedback
description: Fetch bot review feedback (OpenAI Codex and GitHub Copilot) on a PR of this repo, address each comment, update the PR, and resolve the addressed threads. Use when a PR has review comments from either bot to handle.
---

# Handle a PR's bot review feedback

Input: a PR number (default: the current branch's PR, `gh pr view --json number --jq .number`).
Check out the PR's branch; all commands run inside the repo, against
`yuryu/ipa-keyboard-ios`.

Two bots may review a PR, and they use different logins per API surface:

| Bot | `gh pr view` reviews | REST inline comments | GraphQL threads |
| --- | --- | --- | --- |
| Codex | `chatgpt-codex-connector` | `chatgpt-codex-connector[bot]` | `chatgpt-codex-connector` |
| Copilot | `copilot-pull-request-reviewer` | `Copilot` | `copilot-pull-request-reviewer` |

Codex reviews arrive automatically on PR open (enabled in the user's
ChatGPT settings), flag only P0/P1 issues, and are steered by the
"Review guidelines" section of the top-level `AGENTS.md`.

## 1. Fetch the feedback — both bots in one pass

The summary reviews — one per round per bot; the last per bot is current:

```sh
gh pr view <PR> --json reviews \
  --jq '[.reviews[] | select(.author.login
          | test("chatgpt-codex-connector|copilot-pull-request-reviewer"))]
        | group_by(.author.login) | map(last | {author: .author.login, body})'
```

The inline comments — top-level comments have `in_reply_to_id == null`;
`line` can be null for file-level comments; Copilot bodies may contain
fenced `suggestion` blocks:

```sh
gh api --paginate repos/yuryu/ipa-keyboard-ios/pulls/<PR>/comments \
  --jq '.[] | select((.user.login | test("^Copilot$|^chatgpt-codex-connector"))
                     and .in_reply_to_id == null)
        | {id, author: .user.login, path, line, body}'
```

(`--paginate`, or comments past the first 30 are silently missed; it emits
one object per comment because the jq filter runs per page.)

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
nothing is silently ignored. Replies post under the user's account, so every
reply must end with the attribution line `*— written by Claude*` (the
repo-wide convention in CLAUDE.md's Workflow section):

```sh
gh api repos/yuryu/ipa-keyboard-ios/pulls/<PR>/comments/<id>/replies \
  -f body='Applied in `<sha>`.

*— written by Claude*'
```

## 3. Update the PR

Commit and push to the PR branch. Then resolve each thread whose fix landed —
after the push, so the "Applied in `<sha>`" reply points at a commit that
exists on the branch. Leave declined threads unresolved; the user adjudicates
those. Resolving is GraphQL-only, so first map each REST comment id to its
thread (match on `commentId`, not login — GraphQL uses the thread logins
from the table above):

```sh
gh api graphql -f owner=yuryu -f repo=ipa-keyboard-ios -F pr=<PR> -f query='
  query($owner:String!,$repo:String!,$pr:Int!){
    repository(owner:$owner,name:$repo){ pullRequest(number:$pr){
      reviewThreads(first:100){ nodes{
        id isResolved comments(first:1){ nodes{ databaseId } } } } } } }' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved | not)
        | {id, commentId: .comments.nodes[0].databaseId}'
```

```sh
gh api graphql -f id=<thread-id> -f query='
  mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ isResolved } } }'
```

Re-review policies differ per bot — neither re-reviews new pushes on its
own:

- **Codex: don't re-request by default** — reviews are expensive against
  the plan's usage limit, and CI plus the user's own review cover the
  follow-up. If the fixes are substantial enough to truly warrant a
  second pass, ask via a PR comment scoped to the concern:

  ```sh
  gh pr comment <PR> --body '@codex review for <specific concern>

  *— written by Claude*'
  ```

- **Copilot: re-request freely** (if still enabled on the repo) — it's a
  reviewer request, and the `[bot]` suffix is required (the bare login is
  rejected with HTTP 422):

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

Finish by reporting what you applied (threads resolved) vs. declined (threads
left open). The user does the final review and merge — never merge the PR
yourself.
