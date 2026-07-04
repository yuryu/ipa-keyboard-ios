---
name: codex-review
description: Fetch OpenAI Codex review comments on a PR of this repo, address each one, update the PR, resolve the addressed threads, and re-request review. Use when a PR has Codex review feedback to handle.
---

# Handle a PR's Codex review

Input: a PR number (default: the current branch's PR, `gh pr view --json number --jq .number`).
Check out the PR's branch; all commands run inside the repo, against
`yuryu/ipa-keyboard-ios`.

Codex reviews arrive automatically on PR open (enabled in the user's
ChatGPT Codex settings) and only flag P0/P1 issues, so expect fewer,
higher-severity comments than Copilot. Review behavior is steered by the
"Review guidelines" section of the top-level `AGENTS.md`.

## 1. Fetch the feedback

Codex posts as a GitHub App; the expected login is
`chatgpt-codex-connector[bot]` (**unverified until the first review lands
here** — confirm with the discovery command below and correct this file if
it differs, dropping this parenthetical).

Discover the actual reviewer login if unsure:

```sh
gh pr view <PR> --json reviews --jq '[.reviews[].author.login] | unique'
```

The summary review — one per round; the last is the current one:

```sh
gh pr view <PR> --json reviews \
  --jq '[.reviews[] | select(.author.login == "chatgpt-codex-connector")] | last | .body'
```

(`gh pr view` reports App logins without the `[bot]` suffix; the REST API
below includes it. Check both forms if a filter comes back empty.)

The inline comments — top-level comments have `in_reply_to_id == null`;
`line` can be null for file-level comments:

```sh
gh api --paginate repos/yuryu/ipa-keyboard-ios/pulls/<PR>/comments \
  --jq '.[] | select((.user.login | startswith("chatgpt-codex-connector")) and .in_reply_to_id == null)
        | {id, path, line, body}'
```

(`--paginate`, or comments past the first 30 are silently missed; it emits
one object per comment because the jq filter runs per page.)

Both empty? Codex hasn't reviewed this push yet — wait a couple of
minutes, or trigger it explicitly (step 3).

## 2. Address each comment on its merits

Codex is sometimes right, sometimes wrong. Judge each comment:

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
thread (match on `commentId`, not login):

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

Re-request review after the push — Codex does not re-review new pushes on
its own. Unlike Copilot, this is a PR comment, not a reviewer request
(scope it when useful, e.g. `@codex review for Unicode regressions`):

```sh
gh pr comment <PR> --body '@codex review

*— written by Claude*'
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
