#!/bin/bash
# Driver for handling GitHub Copilot auto-review feedback on pull requests.
# Every subcommand shells out to `gh` (uses gh's embedded jq; no system jq needed).
# Run from anywhere inside the repo checkout.
set -euo pipefail

BOT="copilot-pull-request-reviewer"   # GraphQL login of the Copilot reviewer
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
OWNER=${REPO%/*}
NAME=${REPO#*/}

usage() {
  cat <<'EOF'
Usage: copilot.sh <subcommand> [args]

  prs                      Open PRs: unresolved Copilot threads, check rollup, pending re-review
  summary <pr>             Latest Copilot review summary body for a PR
  threads <pr> [--all]     Copilot review threads as JSON (default: unresolved only)
  reply <pr> <comment-id> <body>
                           Reply to an inline review comment (comment-id = databaseId)
  resolve <thread-id>      Resolve a review thread (GraphQL id, PRRT_…)
  unresolve <thread-id>    Unresolve a review thread
  rerequest <pr>           Re-request a Copilot review (do this after pushing fixes)
  runs <pr>                Workflow runs on the PR's head branch
  rerun <run-id> [--failed]
                           Re-run a workflow run (--failed: only its failed jobs)
  wait <pr> [timeout-sec]  Poll until checks green + no pending Copilot re-review +
                           all Copilot threads resolved. Exit 0 ready, 2 checks failed,
                           3 timeout, 4 Copilot left unresolved comments (triage them).
                           Interval via COPILOT_POLL_INTERVAL (default 60s).
EOF
  exit 1
}

# One GraphQL round-trip: rollup state, requested reviewers, Copilot threads.
pr_state() { # $1 = pr number
  gh api graphql -f query='
    query($owner: String!, $name: String!, $pr: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $pr) {
          reviewRequests(first: 20) { nodes { requestedReviewer { ... on Bot { login } ... on User { login } } } }
          commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
          reviewThreads(first: 100) {
            pageInfo { hasNextPage }
            nodes {
              id isResolved isOutdated path line
              comments(first: 50) { nodes { databaseId author { login } body } }
            }
          }
        }
      }
    }' -F owner="$OWNER" -F name="$NAME" -F pr="$1"
}

case "${1:-}" in
  prs)
    gh api graphql -f query='
      query($owner: String!, $name: String!) {
        repository(owner: $owner, name: $name) {
          pullRequests(states: OPEN, first: 50, orderBy: {field: CREATED_AT, direction: DESC}) {
            nodes {
              number title
              reviewRequests(first: 20) { nodes { requestedReviewer { ... on Bot { login } ... on User { login } } } }
              commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
              reviewThreads(first: 100) { pageInfo { hasNextPage } nodes { isResolved comments(first: 1) { nodes { author { login } } } } }
            }
          }
        }
      }' -F owner="$OWNER" -F name="$NAME" --jq '
        .data.repository.pullRequests.nodes[] | {
          number, title,
          checks: (.commits.nodes[0].commit.statusCheckRollup.state // "NONE"),
          copilotReviewPending: ([.reviewRequests.nodes[].requestedReviewer.login] | contains(["'"$BOT"'"])),
          unresolvedCopilotThreads: ([.reviewThreads.nodes[] | select((.comments.nodes[0].author.login == "'"$BOT"'") and (.isResolved | not))] | length),
          threadsTruncated: .reviewThreads.pageInfo.hasNextPage
        }'
    ;;

  summary)
    [ $# -eq 2 ] || usage
    gh pr view "$2" --json reviews \
      --jq '[.reviews[] | select(.author.login == "'"$BOT"'")]
            | if length == 0 then "no Copilot review on this PR yet"
              else (last | "── Copilot review (\(.submittedAt), \(.state)) ──\n\(.body)") end' -R "$REPO"
    ;;

  threads)
    [ $# -ge 2 ] || usage
    pr_state "$2" | /usr/bin/env python3 -c '
import json, sys
rt = json.load(sys.stdin)["data"]["repository"]["pullRequest"]["reviewThreads"]
if rt["pageInfo"]["hasNextPage"]:
    sys.exit("error: PR has more than 100 review threads; refusing to report a truncated list")
data = rt["nodes"]
bot = "'"$BOT"'"
show_all = "'"${3:-}"'" == "--all"
out = []
for t in data:
    cs = t["comments"]["nodes"]
    # author can be null for deleted/ghosted accounts
    if not cs or ((cs[0].get("author") or {}).get("login")) != bot:
        continue
    if t["isResolved"] and not show_all:
        continue
    out.append({
        "threadId": t["id"], "isResolved": t["isResolved"], "isOutdated": t["isOutdated"],
        "path": t["path"], "line": t["line"],
        "comments": [{"commentId": c["databaseId"], "author": (c.get("author") or {}).get("login"), "body": c["body"]} for c in cs],
    })
print(json.dumps(out, indent=2, ensure_ascii=False))
'
    ;;

  reply)
    [ $# -eq 4 ] || usage
    gh api "repos/$REPO/pulls/$2/comments/$3/replies" -f body="$4" \
      --jq '{replied: .id, in_reply_to: .in_reply_to_id, url: .html_url}'
    ;;

  resolve)
    [ $# -eq 2 ] || usage
    gh api graphql -f query='mutation($t: ID!) { resolveReviewThread(input: {threadId: $t}) { thread { id isResolved } } }' \
      -F t="$2" --jq '.data.resolveReviewThread.thread'
    ;;

  unresolve)
    [ $# -eq 2 ] || usage
    gh api graphql -f query='mutation($t: ID!) { unresolveReviewThread(input: {threadId: $t}) { thread { id isResolved } } }' \
      -F t="$2" --jq '.data.unresolveReviewThread.thread'
    ;;

  rerequest)
    [ $# -eq 2 ] || usage
    # The [bot] suffix is required — the bare login is rejected with HTTP 422.
    gh api "repos/$REPO/pulls/$2/requested_reviewers" -f 'reviewers[]=copilot-pull-request-reviewer[bot]' \
      --jq '{requested: [.requested_reviewers[].login]}'
    ;;

  runs)
    [ $# -eq 2 ] || usage
    branch=$(gh pr view "$2" --json headRefName --jq .headRefName -R "$REPO")
    gh run list --branch "$branch" --limit 15 -R "$REPO" \
      --json databaseId,workflowName,event,status,conclusion,headSha \
      --jq '.[] | [.databaseId, .workflowName, .event, .status, (.conclusion // "-"), (.headSha[0:7])] | @tsv'
    ;;

  rerun)
    [ $# -ge 2 ] || usage
    if [ "${3:-}" = "--failed" ]; then
      gh run rerun "$2" --failed -R "$REPO"
    else
      gh run rerun "$2" -R "$REPO"
    fi
    echo "rerun requested for run $2"
    ;;

  wait)
    [ $# -ge 2 ] || usage
    pr=$2
    timeout=${3:-1800}
    interval=${COPILOT_POLL_INTERVAL:-60}
    deadline=$(( $(date +%s) + timeout ))
    while :; do
      state=$(pr_state "$pr" | /usr/bin/env python3 -c '
import json, sys
pr = json.load(sys.stdin)["data"]["repository"]["pullRequest"]
if pr["reviewThreads"]["pageInfo"]["hasNextPage"]:
    sys.exit("error: PR has more than 100 review threads; wait cannot judge readiness on a truncated list")
bot = "'"$BOT"'"
rollup = (pr["commits"]["nodes"][0]["commit"]["statusCheckRollup"] or {}).get("state", "NONE")
pending = any((n["requestedReviewer"] or {}).get("login") == bot for n in pr["reviewRequests"]["nodes"])
unresolved = sum(1 for t in pr["reviewThreads"]["nodes"]
                 if t["comments"]["nodes"]
                 and ((t["comments"]["nodes"][0].get("author") or {}).get("login")) == bot
                 and not t["isResolved"])
print(f"{rollup} {str(pending).lower()} {unresolved}")
')
      read -r rollup pending unresolved <<< "$state"
      echo "$(date '+%H:%M:%S') PR #$pr — checks: $rollup, copilot re-review pending: $pending, unresolved copilot threads: $unresolved"
      case "$rollup" in
        FAILURE|ERROR)
          echo "checks failed — inspect with: copilot.sh runs $pr" >&2
          exit 2
          ;;
      esac
      # No re-review in flight but threads are unresolved: Copilot's review
      # produced actionable comments. Hand control back to the agent instead
      # of polling until timeout.
      if [ "$pending" = "false" ] && [ "$unresolved" != "0" ]; then
        echo "Copilot left $unresolved unresolved thread(s) — triage with: copilot.sh threads $pr" >&2
        exit 4
      fi
      case "$rollup" in
        SUCCESS|NONE)
          if [ "$pending" = "false" ] && [ "$unresolved" = "0" ]; then
            echo "PR #$pr is ready for final human review."
            exit 0
          fi
          ;;
      esac
      if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "timed out after ${timeout}s" >&2
        exit 3
      fi
      sleep "$interval"
    done
    ;;

  *)
    usage
    ;;
esac
