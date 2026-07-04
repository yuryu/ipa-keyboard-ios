#!/bin/bash
# pr-review.sh — single audited entry point for the GitHub operations used by
# the review-feedback and review-sweep skills, so the Bash allowlist can cover
# one script instead of open-ended `gh api` invocations.
#
# Safety properties (written for unattended / auto-mode runs):
#   - The repo is hard-coded; no caller-supplied owner/repo ever reaches gh.
#   - Every argument is validated against a strict pattern before use.
#   - Comment/reply bodies are read from stdin and the "*— written by Claude*"
#     attribution line is appended automatically (never forgotten, never doubled).
#   - `push` refuses main/master, requires the commit to exist locally, and
#     never force-pushes (a non-fast-forward is rejected by the server).
#   - There is deliberately no merge, close, branch-delete, or force subcommand.
#
# Usage: .claude/scripts/pr-review.sh <subcommand> [args]   (run from repo root)
set -euo pipefail

REPO_OWNER='yuryu'
REPO_NAME='ipa-keyboard-ios'
REPO="$REPO_OWNER/$REPO_NAME"
ATTRIBUTION='*— written by Claude*'

# Bot logins differ per API surface:
#   gh pr view reviews / GraphQL threads: chatgpt-codex-connector, copilot-pull-request-reviewer
#   REST inline comments:                 chatgpt-codex-connector[bot], Copilot
BOTS_REVIEWS='chatgpt-codex-connector|copilot-pull-request-reviewer'
BOTS_REST='^Copilot$|^chatgpt-codex-connector'
BOTS_THREADS='copilot-pull-request-reviewer|chatgpt-codex-connector'

usage() {
  cat <<'EOF'
Usage: .claude/scripts/pr-review.sh <subcommand> [args]

Read-only:
  current-pr                     PR number of the current branch
  candidates                     open PRs that have unresolved bot review threads
  summaries <pr>                 latest summary review per bot
  comments <pr>                  top-level inline bot comments (paginated)
  threads <pr> [--bots]          unresolved review threads (--bots: bot-opened only)
  runs <branch>                  recent workflow runs for a branch

Writes (each one guarded):
  reply <pr> <comment-id>        reply to an inline comment; body on stdin
  pr-comment <pr>                comment on the PR; body on stdin
  resolve <thread-id>            resolve one review thread
  request-copilot <pr>           re-request a Copilot review
  push <branch> [<sha>]          push sha (default HEAD) to origin/<branch>;
                                 refuses main/master, never force-pushes
  rerun-failed <run-id>          rerun the failed jobs of a workflow run

Bodies passed on stdin get the attribution line appended automatically.
EOF
}

die() { echo "pr-review.sh: $*" >&2; exit 1; }

require_pr() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || die "expected a numeric PR number, got '${1:-}'"
}

# Read a comment body from stdin, reject empty input, append attribution.
read_body() {
  local body
  body=$(cat)
  [[ -n "${body//[[:space:]]/}" ]] || die 'empty body on stdin'
  if [[ "$body" == *"$ATTRIBUTION"* ]]; then
    printf '%s\n' "$body"
  else
    printf '%s\n\n%s\n' "$body" "$ATTRIBUTION"
  fi
}

# Stream of {id, commentId, author} for every unresolved review thread of a PR.
unresolved_threads() {
  gh api graphql -f owner="$REPO_OWNER" -f repo="$REPO_NAME" -F pr="$1" -f query='
    query($owner:String!,$repo:String!,$pr:Int!){
      repository(owner:$owner,name:$repo){ pullRequest(number:$pr){
        reviewThreads(first:100){ nodes{
          id isResolved comments(first:1){ nodes{ databaseId author{login} } } } } } } }' \
    --jq '.data.repository.pullRequest.reviewThreads.nodes[]
          | select(.isResolved | not)
          | {id, commentId: .comments.nodes[0].databaseId,
             author: .comments.nodes[0].author.login}'
}

cmd_current_pr() {
  gh pr view --json number --jq .number
}

cmd_candidates() {
  local num branch title count
  gh pr list --repo "$REPO" --state open \
      --json number,headRefName,title \
      --jq '.[] | [.number, .headRefName, .title] | @tsv' |
  while IFS=$'\t' read -r num branch title; do
    count=$(unresolved_threads "$num" \
      | jq -s --arg bots "$BOTS_THREADS" '[.[] | select(.author | test($bots))] | length')
    if (( count > 0 )); then
      jq -n --argjson number "$num" --arg headBranch "$branch" --arg title "$title" \
            --argjson unresolvedBotThreads "$count" \
            '{number: $number, headBranch: $headBranch, title: $title,
              unresolvedBotThreads: $unresolvedBotThreads}'
    fi
  done
}

cmd_summaries() {
  require_pr "$1"
  gh pr view "$1" --repo "$REPO" --json reviews \
    --jq "[.reviews[] | select(.author.login | test(\"$BOTS_REVIEWS\"))]
          | group_by(.author.login) | map(last | {author: .author.login, body})"
}

cmd_comments() {
  require_pr "$1"
  # --paginate, or comments past the first 30 are silently missed; the jq
  # filter runs per page, so output is one object per comment.
  gh api --paginate "repos/$REPO/pulls/$1/comments" \
    --jq ".[] | select((.user.login | test(\"$BOTS_REST\"))
                       and .in_reply_to_id == null)
          | {id, author: .user.login, path, line, body}"
}

cmd_threads() {
  require_pr "$1"
  case "${2:-}" in
    --bots) unresolved_threads "$1" | jq --arg bots "$BOTS_THREADS" 'select(.author | test($bots))' ;;
    '')     unresolved_threads "$1" ;;
    *)      die "unknown flag '${2}' (only --bots is supported)" ;;
  esac
}

cmd_reply() {
  require_pr "$1"
  [[ "${2:-}" =~ ^[0-9]+$ ]] || die "expected a numeric comment id, got '${2:-}'"
  local body
  body=$(read_body)  # separate assignment so a read_body failure aborts (set -e)
  gh api "repos/$REPO/pulls/$1/comments/$2/replies" -f body="$body"
}

cmd_pr_comment() {
  require_pr "$1"
  local body
  body=$(read_body)
  gh pr comment "$1" --repo "$REPO" --body "$body"
}

cmd_resolve() {
  [[ "${1:-}" =~ ^[A-Za-z0-9_=+/-]+$ ]] || die "malformed thread id '${1:-}'"
  gh api graphql -f id="$1" -f query='
    mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ isResolved } } }'
}

cmd_request_copilot() {
  require_pr "$1"
  # The [bot] suffix is required; the bare login is rejected with HTTP 422.
  gh api "repos/$REPO/pulls/$1/requested_reviewers" \
    -f 'reviewers[]=copilot-pull-request-reviewer[bot]'
}

cmd_push() {
  local branch="${1:-}" sha="${2:-HEAD}"
  [[ "$branch" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || die "malformed branch name '$branch'"
  case "$branch" in
    main|master) die "refusing to push to $branch" ;;
  esac
  [[ "$sha" == 'HEAD' || "$sha" =~ ^[0-9a-fA-F]{7,40}$ ]] || die "expected HEAD or a commit sha, got '$sha'"
  git rev-parse --verify --quiet "$sha^{commit}" >/dev/null || die "commit '$sha' not found locally"
  # Plain push: the server rejects a non-fast-forward, which means the branch
  # moved underneath us — re-fetch and redo the work, never force-push.
  git push origin "$sha:refs/heads/$branch"
}

cmd_runs() {
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || die "malformed branch name '${1:-}'"
  gh run list --repo "$REPO" --branch "$1" --limit 5
}

cmd_rerun_failed() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || die "expected a numeric run id, got '${1:-}'"
  gh run rerun "$1" --repo "$REPO" --failed
}

cmd="${1:-}"
shift || true
case "$cmd" in
  current-pr)      cmd_current_pr "$@" ;;
  candidates)      cmd_candidates "$@" ;;
  summaries)       cmd_summaries "$@" ;;
  comments)        cmd_comments "$@" ;;
  threads)         cmd_threads "$@" ;;
  runs)            cmd_runs "$@" ;;
  reply)           cmd_reply "$@" ;;
  pr-comment)      cmd_pr_comment "$@" ;;
  resolve)         cmd_resolve "$@" ;;
  request-copilot) cmd_request_copilot "$@" ;;
  push)            cmd_push "$@" ;;
  rerun-failed)    cmd_rerun_failed "$@" ;;
  -h|--help|help|'') usage; [[ "$cmd" =~ ^(-h|--help|help)$ ]] || exit 1 ;;
  *) usage >&2; die "unknown subcommand '$cmd'" ;;
esac
