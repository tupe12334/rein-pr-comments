#!/bin/sh
# Invert the round guard in a copy of round.rein, so a Low point is noted
# in rounds 1 to 3 and fixed from round 4. Then check that a walk fails. A walk
# that still passes does not guard the Low rule.
cd "$(dirname "$0")/.." || exit 1
root=$(pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
cp -R "$root/." "$tmp/" || exit 1
target=judge/route/round.rein
sed 's/if (round.round_4_plus && low_points) {/if (!round.round_4_plus \&\& low_points) {/' \
  "$root/$target" > "$tmp/$target" || exit 1
if cmp -s "$root/$target" "$tmp/$target"; then
  echo "sabotage did not apply: the round guard is not in $target"
  exit 1
fi
if (cd "$tmp" && sh scripts/test-flow-rules.sh) |
  grep -q '^FAIL round 4 with only Lows moves forward'; then
  echo "sabotage fails as expected: the walk catches the inverted round guard"
  exit 0
fi
echo "sabotage passed: the walks do not guard the round rule"
exit 1
