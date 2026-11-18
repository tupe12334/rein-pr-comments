#!/bin/sh
# Make the comment flow in a copy treat an open failed-verify review body as
# no open point, then check that a walk fails. A walk that still passes does
# not guard the fix-loop route for a failed verify.
cd "$(dirname "$0")/.." || exit 1
root=$(pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
cp -R "$root/." "$tmp/" || exit 1
target=main.rein
sed 's/if (!open_comments) {/if (open_comments) {/' \
  "$root/$target" > "$tmp/$target" || exit 1
if cmp -s "$root/$target" "$tmp/$target"; then
  echo "sabotage did not apply: the open_comments guard is not in $target"
  exit 1
fi
if (cd "$tmp" && sh scripts/test-flow-rules.sh) |
  grep -q '^FAIL a failed-verify review body leads to act'; then
  echo "sabotage fails as expected: the walk catches a skipped failed verify"
  exit 0
fi
echo "sabotage passed: the walks do not guard the failed-verify body"
exit 1
