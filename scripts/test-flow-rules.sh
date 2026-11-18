#!/bin/sh
# Walk the flow with fixed answers and check where each walk ends.
cd "$(dirname "$0")/.." || exit 1
fail=0
# The review round: rounds 1 to 3 unless a walk says otherwise.
LR=judge/route/round.round
RND3='{"counted":true,"round_4_plus":false,"round_6_plus":false,"round":"3"}'

# walk_step <rein step arguments...>: every walk here enters the comment flow,
# so it answers rounds 1 to 3, unless it answers the round itself.
walk_step() {
  case "$*" in
    *"$LR="*) rein step --root . --json --input pr=PR "$@" ;;
    *) rein step --root . --json --input pr=PR --answer "$LR=$RND3" "$@" ;;
  esac
}

# expect <name> <text the output must hold> <rein step arguments...>
expect() {
  name=$1 want=$2
  shift 2
  out=$(walk_step "$@" | tr '\n' ' ')
  case $out in
    *"$want"*) echo "ok   $name" ;;
    *) echo "FAIL $name: want '$want' in: $out"; fail=1 ;;
  esac
}

# never <name> <text it must not hold> <text it must hold> <rein step args>
never() {
  name=$1 bad=$2 want=$3
  shift 3
  out=$(walk_step "$@" | tr '\n' ' ')
  case $out in
    *"$bad"*) echo "FAIL $name: holds '$bad': $out"; fail=1 ;;
    *"$want"*) echo "ok   $name" ;;
    *) echo "FAIL $name: want '$want' in: $out"; fail=1 ;;
  esac
}
# refuses <name> <regex the output must not match> <text it must hold>
# <rein step args>: the regex is checked on the output, with "\n" as spaces.
refuses() {
  name=$1 re=$2 want=$3
  shift 3
  out=$(walk_step "$@" | tr '\n' ' ')
  if printf '%s' "$out" | sed 's/\\n/ /g' | grep -Eqi "$re"; then
    echo "FAIL $name: matches /$re/ in: $out"; fail=1
    return
  fi
  case $out in
    *"$want"*) echo "ok   $name" ;;
    *) echo "FAIL $name: want '$want' in: $out"; fail=1 ;;
  esac
}
# both <name> <text 1> <text 2> <rein step args>: the output holds both.
both() {
  name=$1 one=$2 two=$3
  shift 3
  out=$(walk_step "$@" | tr '\n' ' ')
  case $out in
    *"$one"*"$two"* | *"$two"*"$one"*) echo "ok   $name" ;;
    *) echo "FAIL $name: want '$one' and '$two' in: $out"; fail=1 ;;
  esac
}

J=main
# Judgment answers, one JSON object each (fields: lines, fix_lines,
# pr_text_points, low_points, fix_points).
JCODE='{"lines":"L","fix_lines":"L","pr_text_points":false,'
JCODE="$JCODE"'"low_points":false,"fix_points":true,"critical_points":false,"critical_lines":"none"}'
JPR_TEXT='{"lines":"L","fix_lines":"L","pr_text_points":true,'
JPR_TEXT="$JPR_TEXT"'"low_points":false,"fix_points":true,"critical_points":false,"critical_lines":"none"}'
F="act.fix_points=true"
# The resolve step's typed answer: every thread done, none left open.
RES="follow_up/resolve_threads.resolution={\"resolved\":true,\"open\":\"none\"}"
never "a PR-text point goes to the edit, not an issue" 'open one' \
  'gh pr edit' --entry main --answer main.open_comments=true \
  --answer "judge.judgment=$JPR_TEXT"
expect "an edited PR text goes on to act" "\"key\":\"act.fix_points\"" \
  --entry main --answer main.open_comments=true \
  --answer "judge.judgment=$JPR_TEXT" \
  --answer edit_pr_text.edited=true
expect "a code point goes to act" "\"key\":\"act.fix_points\"" \
  --entry main --answer main.open_comments=true \
  --answer "judge.judgment=$JCODE"

# An agreed point is fixed as commits on the PR's own branch: no stacked PR.
# The act walk asks first whether any point needs a fix, then whether the
# author is this account, then fixes.
JL="judge.judgment=$JCODE"
P=act/push_fixes
expect "act asks first whether a point needs a fix" \
  "\"key\":\"act.fix_points\"" \
  --entry main --answer main.open_comments=true --answer "$JL"
expect "an agreed point checks the author" "\"key\":\"act.own\"" \
  --entry main --answer main.open_comments=true --answer "$JL" --answer "$F"
# A disagree-only judgment needs no push: it reaches the fresh review on a PR
# of any author, and the author is never asked.
expect "a disagree-only judgment reaches the fresh review, any author" \
  "\"key\":\"follow_up/disagree.agent_only\"" --entry main \
  --answer main.open_comments=true --answer "$JL" \
  --answer act.fix_points=false --answer act.own=false \
  --answer follow_up.disagree=true --answer "$RES"
both "the fix is a commit on the same branch, no new PR" \
  'commits on the head branch of PR itself' \
  'Open no new pull request and no issue' --entry main \
  --answer main.open_comments=true --answer "$JL" --answer "$F" \
  --answer act.own=true
ACT_VERB='(open|create|make|file|start)[[:space:]]+'
ACT_WHAT='(a|an|the|one|another|fix|separate|stacked|follow-up)'
ACT_OPENS="${ACT_VERB}${ACT_WHAT}[^.]*pull request|gh pr create"
refuses "the act prompt opens no pull request, in any words" "$ACT_OPENS" \
  'commits on the head branch of PR itself' --entry main \
  --answer main.open_comments=true --answer "$JL" --answer "$F" \
  --answer act.own=true
expect "the act task is a typed yes or no" "\"key\":\"$P.acted\"" \
  --entry main --answer main.open_comments=true --answer "$JL" --answer "$F" \
  --answer act.own=true
expect "a fix-free judgment never claims new commits" \
  'No commit was pushed to PR' --entry main \
  --answer main.open_comments=true --answer "$JL" \
  --answer act.fix_points=false --answer follow_up.disagree=false \
  --answer "$RES"
never "fixed in place waits for a new review, no stacked fix" 'stacked' \
  'fixed on its branch, waiting for the new review' --entry main \
  --answer main.open_comments=true --answer "$JL" --answer "$F" \
  --answer act.own=true \
  --answer $P.acted=true --answer follow_up.disagree=false \
  --answer "$RES"
# A PR by another author gets no push: the act prompt never runs.
never "a PR of another author pushes nothing" 'commits on the head branch' \
  'its author is another person' --entry main \
  --answer main.open_comments=true --answer "$JL" --answer "$F" \
  --answer act.own=false

# Every post of the program starts with 🤖: the owner shares its account,
# and the owner's answer is told apart by that prefix. One walk per post.
RULE='Start each post with 🤖'
expect "post rule: no open comment" "$RULE" --entry main \
  --answer main.open_comments=false
expect "post rule: disagree replies" "$RULE" --entry main \
  --answer main.open_comments=true
expect "post rule: PR text replies" "$RULE" --entry edit_pr_text \
  --input lines=L
expect "post rule: fix replies" "$RULE" --entry $P --input lines=L
expect "post rule: fresh review" "$RULE" --entry follow_up/disagree \
  --answer follow_up/disagree.agent_only=true
expect "post rule: re-review ask, no push" "$RULE" --entry main \
  --answer main.open_comments=true --answer "$JL" \
  --answer act.fix_points=false --answer follow_up.disagree=false \
  --answer "$RES"
expect "post rule: re-review ask, pushed" "$RULE" --entry main \
  --answer main.open_comments=true --answer "$JL" --answer "$F" \
  --answer act.own=true --answer $P.acted=true \
  --answer follow_up.disagree=false --answer "$RES"
# The resolve step runs after a fix and after a reply, and before a
# disagreement is answered. Every fixed thread is resolved, whoever started it.
R=follow_up/resolve_threads
expect "after a fix the resolve step runs" \
  "\"act/push_fixes\",\"follow_up\",\"$R\"" --entry main \
  --answer main.open_comments=true --answer "$JL" --answer "$F" \
  --answer act.own=true --answer act/push_fixes.acted=true \
  --answer follow_up.disagree=false --answer "$RES"
expect "after a reply the resolve step runs" \
  "\"act\",\"follow_up\",\"$R\"" --entry main \
  --answer main.open_comments=true --answer "$JL" \
  --answer act.fix_points=false --answer follow_up.disagree=false \
  --answer "$RES"
expect "a disagreement is answered after the resolve step" \
  "\"$R\",\"follow_up/disagree\"" --entry main \
  --answer main.open_comments=true --answer "$JL" \
  --answer act.fix_points=false --answer follow_up.disagree=true \
  --answer "$RES"
# The walks grep the request text for each rule: a fixed thread, whoever
# started it, is resolved; a thread a reply disagrees with stays open.
expect "a fixed human thread gets resolved" \
  'Resolve every fixed thread, whoever' --entry main \
  --answer main.open_comments=true --answer "$JL" \
  --answer act.fix_points=false --answer follow_up.disagree=false
expect "a fixed thread needs a 🤖 reply that names the fix sha" \
  'names a fix commit sha that is on the head branch' --entry main \
  --answer main.open_comments=true --answer "$JL" \
  --answer act.fix_points=false --answer follow_up.disagree=false
expect "a disagreed human thread stays open" \
  'its 🤖 reply disagrees' --entry main \
  --answer main.open_comments=true --answer "$JL" \
  --answer act.fix_points=false --answer follow_up.disagree=false
expect "a point already fixed on the branch needs no new commit" \
  'already names a fix commit' --entry act \
  --input lines=L
expect "a fix reply names the fix sha, so the thread can resolve" \
  'with the fix sha and its commit link' --entry act/push_fixes \
  --input lines=L
expect "the open-comment count keeps an unresolved thread open" \
  'an unresolved one stays open' --entry main
expect "the open-comment count reads threads of any author" \
  'Threads, any author' --entry main
# A failed verify review body counts as open points: act fixes them, never skips.
FV='judge.judgment={"lines":"- case 1 failed: RTDB trigger re-fired",'
FV="$FV"'"fix_lines":"- case 1 failed: RTDB trigger re-fired",'
FV="$FV"'"pr_text_points":false,"low_points":false,"fix_points":true,"critical_points":false,"critical_lines":"none"}'
expect "a failed-verify review body leads to act" \
  'act.fix_points' --entry main \
  --answer main.open_comments=true --answer "$FV"
never "a failed-verify review body never ends skipped" 'skipped' \
  'push_fixes' --entry main --answer main.open_comments=true \
  --answer "$FV" --answer act.fix_points=true \
  --answer act.own=true
# Review rounds: from round 4 a Low point needs no fix. Each Low thread gets
# one noted reply and is tracked; the others go on, or the flow moves on.
# Rounds 1 to 3 fix every point. The round is counted by the bundled script.
RND4='{"counted":true,"round_4_plus":true,"round_6_plus":false,"round":"4"}'
RND6='{"counted":true,"round_4_plus":true,"round_6_plus":true,"round":"6"}'
ONLY_LOW='{"lines":"L","fix_lines":"none",'
ONLY_LOW="$ONLY_LOW"'"pr_text_points":false,"low_points":true,"fix_points":false,"critical_points":false,"critical_lines":"none"}'
LOW_MED='{"lines":"L","fix_lines":"F","pr_text_points":false,'
LOW_MED="$LOW_MED"'"low_points":true,"fix_points":true,"critical_points":false,"critical_lines":"none"}'
MED_ONLY='{"lines":"L","fix_lines":"F","pr_text_points":false,'
MED_ONLY="$MED_ONLY"'"low_points":false,"fix_points":true,"critical_points":false,"critical_lines":"none"}'
expect "round 3 with a Low gets fixed" \
  '"key":"act.fix_points"' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$LOW_MED" \
  --answer "$LR=$RND3"
# No round answer here: the walk must ask for the round itself.
out=$(rein step --root . --json --input pr=PR --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$ONLY_LOW" |
  tr '\n' ' ')
case $out in
  *'scripts/review-round.sh'*) echo "ok   a Low point asks for the round count" ;;
  *) echo "FAIL a Low point asks for the round count: in: $out"; fail=1 ;;
esac
expect "round 4 with only Lows gives each Low thread the noted reply" \
  'Noted as a low follow-up (review round' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$ONLY_LOW" \
  --answer "$LR=$RND4" --answer low/track.tracker='{"jira_linked":false}'
never "round 4 with only Lows never reaches the fix loop" \
  '"key":"act.fix_points"' 'Start this program again' \
  --entry main --answer main.open_comments=true \
  --answer "judge.judgment=$ONLY_LOW" --answer "$LR=$RND4" \
  --answer low/track.tracker='{"jira_linked":false}' \
  --answer low/issue.tracked=true
expect "round 4 with only Lows moves forward to the task merge" \
  'Start this program again for PR with the task merge' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$ONLY_LOW" \
  --answer "$LR=$RND4" \
  --answer low/track.tracker='{"jira_linked":false}' \
  --answer low/issue.tracked=true
expect "round 4 with a Medium and a Low still gets fixed" \
  '"key":"act.fix_points"' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$LOW_MED" \
  --answer "$LR=$RND4" \
  --answer low/track.tracker='{"jira_linked":false}' \
  --answer low/issue.tracked=true
expect "round 4 with a Medium and no Low still gets fixed" \
  '"key":"act.fix_points"' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$MED_ONLY" \
  --answer "$LR=$RND4"
expect "a Low with a Jira key is tracked in Jira" \
  '"key":"low/jira.tracked"' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$ONLY_LOW" \
  --answer "$LR=$RND4" \
  --answer low/track.tracker='{"jira_linked":true}'
expect "a Low without a Jira key is tracked in a GitHub issue" \
  '"key":"low/issue.tracked"' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$ONLY_LOW" \
  --answer "$LR=$RND4" \
  --answer low/track.tracker='{"jira_linked":false}'
expect "a Low that cannot be tracked stops the run" \
  'could not be tracked' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$ONLY_LOW" \
  --answer "$LR=$RND4" \
  --answer low/track.tracker='{"jira_linked":false}' \
  --answer low/issue.tracked=false
# A noted Low thread is closed for every count, unless a comment came after
# its reply. The judgment skips it too.
NOTED='unless a comment came after that reply'
expect "the open-comment count closes a noted Low thread" "$NOTED" \
  --entry main
expect "the judgment does not judge a noted Low thread" \
  'whose only 🤖 reply starts' --entry main \
  --answer main.open_comments=true
expect "a Low point's replies and tracker start each post with 🤖" "$RULE" \
  --entry main --answer main.open_comments=true \
  --answer "judge.judgment=$ONLY_LOW" --answer "$LR=$RND4" \
  --answer low/track.tracker='{"jira_linked":false}'

# Review loop cap: from round 6 no fix is made for a review point. Each agreed
# point that is not Critical is tracked, and its thread gets the cap reply. A
# Critical point asks the owner, and nothing else runs.
CAP=judge/route/round/cap
CRIT='{"lines":"L","fix_lines":"F","critical_lines":"L",'
CRIT="$CRIT"'"pr_text_points":false,"low_points":false,"fix_points":true,'
CRIT="$CRIT"'"critical_points":true}'
JIRA_NO="$CAP.tracker={\"jira_linked\":false}"
JIRA_YES="$CAP.tracker={\"jira_linked\":true}"
expect "round 6 with a Medium is tracked and moves forward" \
  'Start this program again for PR with the task merge' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$MED_ONLY" \
  --answer "$LR=$RND6" --answer "$JIRA_NO" --answer "$CAP/issue.tracked=true"
expect "round 6 with a Medium gets the cap reply" \
  'Review loop cap reached (5 rounds); tracked as follow-up' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$MED_ONLY" \
  --answer "$LR=$RND6" --answer "$JIRA_NO"
expect "round 6 with a Low with a Jira key is tracked in Jira" \
  '"key":"judge/route/round/cap/jira.tracked"' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$ONLY_LOW" \
  --answer "$LR=$RND6" --answer "$JIRA_YES"
never "round 6 with a Medium never reaches the fix loop" \
  '"key":"act.' 'Review loop cap reached' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$MED_ONLY" \
  --answer "$LR=$RND6" --answer "$JIRA_NO"
expect "round 6 with a Critical asks the owner" 'Ask the user' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$CRIT" \
  --answer "$LR=$RND6"
never "round 6 with a Critical never tracks or fixes" \
  'Review loop cap reached' 'Ask the user' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$CRIT" \
  --answer "$LR=$RND6"

# A critical point asks the owner even when the judge says no fix point.
CRIT_NOFIX='{"lines":"L","fix_lines":"none","critical_lines":"L",'
CRIT_NOFIX="$CRIT_NOFIX"'"pr_text_points":false,"low_points":false,'
CRIT_NOFIX="$CRIT_NOFIX"'"fix_points":false,"critical_points":true}'
expect "round 6 with a critical and no fix point asks the owner" \
  'Ask the user' --entry main --answer main.open_comments=true \
  --answer "judge.judgment=$CRIT_NOFIX" --answer "$LR=$RND6"
# A title or body point is edited on the PR in round 6, never an issue.
TITLE6='{"lines":"L","fix_lines":"F","critical_lines":"none",'
TITLE6="$TITLE6"'"pr_text_points":true,"low_points":false,'
TITLE6="$TITLE6"'"fix_points":true,"critical_points":false}'
expect "round 6 with a title point edits the PR text" 'gh pr edit' \
  --entry main --answer main.open_comments=true \
  --answer "judge.judgment=$TITLE6" --answer "$LR=$RND6" \
  --answer "$JIRA_NO"
# A title or body point in rounds 4 and 5 gets its edit with no fix point.
TITLE4='{"lines":"L","fix_lines":"none","critical_lines":"none",'
TITLE4="$TITLE4"'"pr_text_points":true,"low_points":false,'
TITLE4="$TITLE4"'"fix_points":false,"critical_points":false}'
expect "round 4 with only a title point edits the PR text" 'gh pr edit' \
  --entry main --answer main.open_comments=true \
  --answer "judge.judgment=$TITLE4" --answer "$LR=$RND4"

# A round that cannot be counted stops the run; no point is dropped.
RND_UNCOUNTED='{"counted":false,"round_4_plus":false,"round_6_plus":false,"round":"0"}'
expect "an uncounted round stops the run" 'could not be counted' \
  --entry main --answer main.open_comments=true \
  --answer "judge.judgment=$MED_ONLY" --answer "$LR=$RND_UNCOUNTED"
# A point both Critical and Low is fixed in round 4, never noted as Low.
CRIT_LOW='{"lines":"L","fix_lines":"F","critical_lines":"L",'
CRIT_LOW="$CRIT_LOW"'"pr_text_points":false,"low_points":true,'
CRIT_LOW="$CRIT_LOW"'"fix_points":true,"critical_points":true}'
expect "round 4 with a point both critical and Low is noted" \
  'Noted as a low follow-up (review round' --entry main \
  --answer main.open_comments=true --answer "judge.judgment=$CRIT_LOW" \
  --answer "$LR=$RND4" --answer low/track.tracker='{"jira_linked":false}'

# A title or body reply in round 6 resolves its thread, so the loop closes.
expect "round 6 title point replies and resolves its thread" \
  'resolveReviewThread' --entry main --answer main.open_comments=true \
  --answer "judge.judgment=$TITLE6" --answer "$LR=$RND6" \
  --answer "$JIRA_NO"


exit $fail
