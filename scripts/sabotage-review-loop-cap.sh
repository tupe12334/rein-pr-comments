#!/bin/sh
# Invert the round 6 guard in a copy of round.rein, so a point of round 6 is
# fixed instead of tracked. Then check that a walk fails. A walk that still
# passes does not guard the review loop cap.
cd "$(dirname "$0")/.." || exit 1
root=$(pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
cp -R "$root/." "$tmp/" || exit 1
target=judge/route/round.rein
sed 's/if (round.round_6_plus) {/if (!round.round_6_plus) {/' \
  "$root/$target" > "$tmp/$target" || exit 1
if cmp -s "$root/$target" "$tmp/$target"; then
  echo "sabotage did not apply: the round 6 guard is not in $target"
  exit 1
fi
if (cd "$tmp" && sh scripts/test-flow-rules.sh) |
  grep -q '^FAIL round 6 with a Medium is tracked'; then
  echo "sabotage fails as expected: the walk catches the inverted round 6 guard"
  exit 0
fi
echo "sabotage passed: the walks do not guard the review loop cap"
exit 1
