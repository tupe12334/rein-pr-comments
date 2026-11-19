# pr-comments

A [Rein](https://github.com/tupe12334/rein) program. It judges the open review comments on a pull request, then acts on them.

It fixes each point the agent agrees with, as commits on the pull request's own branch. It replies to the points it disagrees with. It resolves the threads that are fixed. It tracks the Low points and the points after the review loop cap.

This program was extracted from [rein-pr-handling](https://github.com/tupe12334/rein-pr-handling), where it lived in the `comments/address` folder.

## Install

```sh
rein install -g github:tupe12334/rein-pr-comments#v0.2.0
```

## Use

A caller imports the program by name and awaits it with the link of the pull request. The `const` needs a doc comment above it:

```text
import { main } from "pr-comments";

/** Judge the open review comments on a pull request, then act on them. */
const answer: string = await main(pr=<pull request link>);
```

- `pr`: the link of the pull request with the review comments.

## Flow

1. `main.rein` checks whether any review point is open: an unresolved thread of any author, or a review body that failed verify.
2. `judge.rein` judges each open comment. It answers agree or disagree, and whether each agreed point is critical or Low.
3. `judge/route.rein` and `judge/route/round.rein` route the judgment by review round. Rounds 1 to 3 fix every point. From round 4 a Low point is tracked. From round 6 the loop is capped.
4. `act.rein` and `act/push_fixes.rein` fix the agreed points on the branch. `edit_pr_text.rein` fixes a point about the title or body first.
5. `follow_up.rein` and `follow_up/resolve_threads.rein` resolve the fixed threads, then ask for a new review.

The round count is read by `scripts/review-round.sh`, from the installed package.

## Develop

Set the hooks path once with `git config core.hooksPath .githooks`. Pushes then run `rein check .` and `scripts/test-flow-rules.sh`. The walks answer each step with fixed answers and check where each walk ends.

The sabotage scripts invert one guard in a copy and check that a walk fails:

- `scripts/sabotage-failed-body.sh`: an open failed-verify review body is ignored.
- `scripts/sabotage-low-round.sh`: a Low point is fixed in rounds 1 to 3.
- `scripts/sabotage-review-loop-cap.sh`: a round 6 point is fixed, not tracked.

## License

MIT
