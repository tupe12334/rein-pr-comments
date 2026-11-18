#!/bin/sh
# Print how many review submissions on a pull request opened review threads.
# A review opens a thread when one of its inline comments starts a thread.
# Usage: scripts/review-round.sh <pull request link or number>
set -eu
[ $# -eq 1 ] || { echo "usage: $0 <pull request>" >&2; exit 2; }
url=$(gh pr view "$1" --json url --jq .url)
pat='^https://github.com/([^/]*/[^/]*)/pull/([0-9]*)$'
api=$(printf '%s\n' "$url" | sed -En "s#$pat#repos/\1/pulls/\2#p")
[ -n "$api" ] || { echo "not a pull request: $url" >&2; exit 1; }
ids=$(gh api --paginate "$api/comments" \
  --jq '.[] | select(.in_reply_to_id | not) | .pull_request_review_id')
printf '%s\n' "$ids" | grep -v '^null$' | sort -u |
  awk 'NF { n++ } END { print n + 0 }'
