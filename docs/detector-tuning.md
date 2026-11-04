# Tuning the shift detector

The detector decides, once a second, whether the player is on the ice. It gets
one number to do it with: **motion**, the mean absolute deviation of wrist
acceleration over that second, in milli-g.

It learns two levels as the game runs - `rest`, how still the player gets, and
`work`, how hard they move - and puts the decision boundary a fixed fraction
of the way between them. That fraction is `_band`, and it is the whole tuning.

## Why it can be tuned at all

The app writes `motion` and `motion_threshold` into the FIT file every second.
That is the entire point of those two developer fields: a real game can be
replayed through a candidate detector offline, as many times as needed,
without going back to a rink.

```
python3 -m venv .venv-fit
.venv-fit/bin/pip install -r tools/requirements.txt
.venv-fit/bin/python tools/replay_detector.py <game.fit>
```

The harness is only worth anything if it agrees with the watch, so it checks:
it replays the recorded motion through the same rule and compares against the
threshold the watch actually recorded. **Max disagreement is 3 mg over an hour**,
which is Monkey C's Float-to-Number truncation against Python's. The full state
machine - hysteresis, confirmation streaks, dwell guards, heart-rate
corroboration - reproduces **98.9%** of the watch's own on-ice decisions.

The validation replays at the band the recording was made with (`RECORDED_BAND`
in the harness), not at the band currently shipped. Those are no longer the
same number, and replaying at today's band would compare against a threshold
no watch ever computed - a disagreement that is really a settings difference.

One correction worth recording, because it is the kind of error a harness
invites: the harness originally computed the heart-rate slope by least squares
over the window, where the watch uses a crude two-point endpoint slope, and it
skipped the eight-sample guard the watch applies. Least squares is the better
statistic, which is exactly why it was wrong here - the harness answers "what
would the watch have done", so where the watch is crude it has to be crude
identically. Matching them moved agreement from 98.3% to 98.9%.

Two things had to be understood before it agreed at all, and both are
properties of the data rather than of the algorithm:

- A second where the accelerometer delivered nothing shows up in the FIT as a
  row whose motion **and** threshold both repeat the row before. `tick()`
  returns before `learn()` in that case. Replaying those rows feeds the same
  sample in twice and inflates `work`.
- **501 of 3605 seconds in the 2026-11-03 game - 13.9% - were stale.** The
  detector holds state and learns nothing across them. That is a separate
  problem from tuning and is not fixed here.

## What was wrong

`_band` was 0.45 on normal sensitivity. It had never been fitted to anything -
the heart-rate constants were fitted to twelve games, the motion side was a
guess.

The guess failed because **`work` is set by hits, not by skating**. The learner
chases a sample above `work` at 15% and decays at 1%, so a collision or board
contact hauls it up and it stays up for roughly a hundred seconds. The
2026-11-03 game peaked at 2450 mg against a median of 75.

A boundary 45% of the way up a band whose top is set by collisions lands a long
way above skating:

| | |
|---|---|
| Median motion, whole game | 75 mg |
| Median learned threshold | 241 mg - the **82nd percentile** of the player's own motion |
| Seconds that could clear it | ~18% |

So at most 18% of any game could be recorded as ice time, whatever happened on
it. It is also a feedback loop: skating hard raises `work`, which raises the
boundary, until skating stops counting. The threshold climbed 206 - 311 mg
across that game.

**The shift count was not the problem.** The detector found 25 shifts; heart
rate on its own shows 22 cycles. It found the shifts and **clipped** them -
only the intense middle of each cleared the boundary, so getting on, the glide
and the change were all recorded as bench. Median shift: 17 seconds.

## What it was changed to

`_band` 0.45 -> **0.27** on normal, with low and high sensitivity moved to 0.35
and 0.21 around it.

0.27 was not picked to hit one number. Four checks that do not depend on each
other agree on it at once:

| Check | Where the target comes from | Target | 0.27 gives |
|---|---|---|---|
| Ice time | a three-line bench | ~33% | **34.0%** |
| Shift count | heart-rate cycles, motion not involved | 22 | **23** |
| Median shift | the cycle length | 45-50 s | **45 s** |
| Shift cycle | 141 s from heart rate, ~160 s known for this player | 141-160 s | **147 s** |

Agreement with the heart-rate phase reference rises from 60.4% at 0.45 to
72.5% at 0.27, against a best-available 73.6% at 0.22 - and 0.22 overshoots
every other check (ice 39.6%, a 90-second cycle).

Spike-capping the `work` estimator was tried, since collisions are the root
cause. It overshoots: capping lowers `work`, which lowers the boundary, which
pushes ice time to 45-52%. Lowering the band alone reaches the target, so the
simpler change is the one that shipped.

## What this is not

**One game.** It is a first fit, not a final one. A single recording cannot
show whether 0.27 holds for a different rink, a different pair of gloves or a
tighter watch strap.

A 7.5-minute recording from the same night was tried as a holdout and is not
usable: three shifts and a 229-second bench, which is the tail after the game
ended rather than a game. On a mostly-idle recording a high boundary scores
well for the wrong reason - "bench" is the right answer almost all the time.

The way to settle it is more games. Every one of them carries the motion trace
and the threshold, so re-checking this costs a replay and no ice time.
