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

The validation replays at the band the recording was made with, not at the
band currently shipped. Those have not been the same number since v2.0.0, and
replaying at today's band would compare against a threshold no watch ever
computed - a disagreement that is really a settings difference. The harness
recovers the recorded band from the file rather than being told it; see below.

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
rate on its own shows 22 cycles by the peak-counting parameters used at the
time. It found the shifts and **clipped** them -
only the intense middle of each cleared the boundary, so getting on, the glide
and the change were all recorded as bench. Median shift: 17 seconds.

## The 0.27 fit, and why it was also wrong

`_band` went 0.45 -> 0.27 on normal, with low and high at 0.35 and 0.21.

0.27 was picked because four checks agreed on it at once. Three of them were
sound. The fourth was not this player's to hit:

| Check | Where the target came from | Target | 0.27 gave |
|---|---|---|---|
| Ice time | **a three-line bench** | ~33% | 34.0% |
| Shift count | heart-rate cycles, motion not involved | 22 | 23 |
| Median shift | the cycle length | 45-50 s | 45 s |
| Shift cycle | 141 s from heart rate, ~160 s known | 141-160 s | 147 s |

**A three-line bench is a forward's share. He plays defence.** A defenceman's
share is two spots divided by the number of defencemen dressed: 50% with two
pairs, 40% with five, 33% only with six. So the ice-time target was somewhere
between 7 and 17 points too low, and a detector scored against a target that
low gets a boundary correspondingly too high.

The damage was not limited to one row of the table. 0.22 was rejected at the
time *despite having the best agreement with the heart-rate phase reference of
anything tried* - 73.6% against 0.27's 72.5% - on the grounds that its 39.6%
ice time "overshoots every other check". It did not overshoot. For a
defenceman on anything thinner than a six-man rotation, 39.6% was still short.
The fit threw away the band that agreed best with its only
motion-independent reference, on the strength of the one target that was
wrong.

## The holdout that found it

The game of 2026-11-05 was the first independent test: 85.4 minutes, five
defencemen dressed, which is a known 40% share.

**Every 11-05 figure below is measured on game time only - the first 13
minutes are dropped.** The watch was started in the warm-up, and the
per-minute trace shows why that matters: a hard warm-up skate in minutes 0-4,
then eight minutes of standing around at 105-122 bpm before the cycling
starts. Leaving it in gives 36 shifts and 43.2% ice rather than 32 and 42.9%,
and the difference is not a detector result. Dropping it is a judgement about
where the game began, so it is stated rather than buried: an audit of this
document failed to reproduce these numbers for exactly this reason. It is also a much cleaner
recording than the first - **74 stale seconds out of 5122, 1.4%, against
13.9%** - so there is very little to argue about in the input.

At the shipped 0.27 it came back wrong in three ways at once:

| | 11-03 (the fit) | 11-05 (the holdout) |
|---|---|---|
| Ice time | 34.2% | **27.8%** against a known 40% |
| Shifts | 23, heart rate says 22 | **45**, heart rate says 31 |

The heart-rate cycle count for 11-03 is quoted as 22 above and as 24 below,
and both are this document's own figures. They come from different runs of the
same idea: smooth the rate, count peaks, discard any whose rise from the
preceding trough is too small. The count moves by one or two with the
smoothing width and the minimum rise, which is worth knowing before leaning on
it - it is the reference the whole fit is scored against. The later figures
use a 15-second window, a 50-second minimum separation and a 4 bpm minimum
rise. Neither value changes which band wins.
| Median shift | 51 s | **18 s** |
| Shift cycle | 151 s | **93 s** |

Two separate defects, and the per-shift zone data separates them cleanly.
Grading every detected shift by the peak heart rate inside it:

```
11-05   16 of 45 shifts never left zone 2   (288 s)
11-03    0 of 23 shifts never left zone 2
```

One of those sixteen ran 53 seconds with a peak of 119 bpm. **No band fixes
them** - they are present at every value from 0.18 to 0.35, and absent from the
other game at all of them. They are a player sitting between periods and
shifting around, which an accelerometer alone cannot tell from a shift.

## What it was changed to

Three changes, each aimed at one of the three failures.

**`_band` 0.27 -> 0.18** (low 0.24, high 0.14). Refitted against checks that
do not need to know the bench size, since that is precisely the quantity the
old fit got wrong and no FIT file records it. Shift count and cycle length both
come from the heart rate trace with motion never consulted:

| band | score | 11-05 shifts / cycle | 11-03 shifts / cycle |
|---|---|---|---|
| 0.14 | 0.26 | 29 / 131 s | 24 / 140 s |
| **0.18** | **0.35** | **32 / 125 s** | **22 / 146 s** |
| 0.22 | 0.78 | 36 / 107 s | 22 / 165 s |
| 0.27 | 1.12 | 31 / 113 s | 19 / 216 s |
| 0.45 | 1.47 | 26 / 135 s | 17 / 235 s |

Every row of that sweep is replayed with `CONFIRM_BENCH` at 14 and the veto in
place; only `_band` varies. That is why the 0.27 row here does not match the
0.27 column in the holdout table above, which shows the state machine as
version 2.1.0 actually shipped it.

Everything from 0.14 to 0.20 beats 0.27 by a wide margin without any
assumption about the bench at all. Within that window the one game whose bench
is actually known picks 0.18: it reads 42.9% ice against a known 40%, where
0.14 reads 46.3% and overshoots a number we have.

**That score is not a robust band selector, and an audit of this document is
why the sentence that used to be here is gone.** It claimed 0.18 was "a real
interior minimum". It is not. The heart-rate reference depends on how peaks
are picked, and the winner moves with it: at a 21-second smoothing window and
a 6 bpm minimum rise the same score picks 0.35, and at 11 seconds and 3 bpm it
picks 0.14. The band is only weakly constrained by heart rate alone.

What actually pins it is **ice share against games the player marked by
hand**, which no detector touched - see below. Those put him at 37-44%, which
0.18 and 0.20 both sit inside and which 0.27 (35.6%) and 0.45 (21.4%) fall
outside.

**`CONFIRM_BENCH` 10 -> 14 seconds** (fast path 5 -> 7). Ten seconds was not
enough for a defenceman: standing at the point, gliding, or waiting out a
stoppage drops below the boundary long enough to end the shift, and the
detector then opens a fresh one when he moves again. This is what put the
median shift at 18 seconds.

**A heart-rate veto, `HR_VETO` = 12 bpm.** Everything else in the detector uses
heart rate only to *agree* with motion, never to contradict it, because the
slope separation is too weak to trust alone. This is the one exception and it
is not a slope: a rate sitting a dozen beats under its own drifting baseline is
a player at rest, and no amount of wrist movement makes that a shift. It
removes six of them on 11-05 on its own, and costs nothing on 11-03, which had
none. This document previously credited the veto with nine, which was the
combined effect of all three changes - the sort of error that three
simultaneous changes invite, and the reason the figure is now attributed to
the veto alone with the others held fixed.

Replayed through the shipped state machine:

| | 11-05 holdout | 11-03 |
|---|---|---|
| Shifts | 32, heart rate says 31 | 22 |
| Shift cycle | 125 s, heart rate says 127 s | **186 s** |
| Median shift | 41 s | **93 s** |
| Ice time | **42.9% against a known 40%** | **52.9%**, bench unknown |
| Zone-2 shifts | 7 of 32 | 0 of 22 |

**The 11-03 column was wrong until an audit caught it, and the reason is worth
keeping.** That game records at **0.87 Hz, not 1 Hz** - 3605 records across
4149 wall-clock seconds. The replay walks records and the analysis counted
each one as a second, so every 11-03 duration came out about 15% short and the
ice share came out 5 points low: the published figures were 47.5%, 76 s and
145 s, which are record-index numbers wearing wall-clock units. 11-05 records
at exactly 1.00 Hz, so none of its figures move. Any future game has to be
checked for its record rate before anything is measured from it.

## The harness no longer has to be told the band

The band a recording was made with is a property of the file, and getting it
wrong invalidates the replay completely: it compares against a threshold no
watch ever computed and reports a disagreement that is really a settings
difference. That went wrong once already, with 0.45 hardcoded after 0.27 had
shipped, and three shipped values would have made it worse.

So the harness recovers it instead. Exactly one band reproduces the threshold
the watch wrote, and `replay_detector.py` now searches for it by default:

```
$ .venv-fit/bin/python tools/replay_detector.py \
      data/2026-11-05-game/2026-11-05-20-06-45.fit
samples: 5048   band recovered from the file: 0.270
replayed threshold vs recorded: max abs difference = 3 mg
VERDICT: replay matches the watch

$ .venv-fit/bin/python tools/replay_detector.py \
      data/2026-11-03-game/2026-11-03-22-11-07.fit
samples: 3104   band recovered from the file: 0.450
replayed threshold vs recorded: max abs difference = 3 mg
VERDICT: replay matches the watch
```

Two files, two different shipped builds, each recovered to the exact value
without being told. `--band` still overrides, for asking what a different band
would have done.

## Ground truth that no detector touched

A sweep of all 40 files pulled off the watch found two games from before this
app existed, recorded by a build where **the player marked every shift with a
button**. No accelerometer, no band, no threshold - his own thumb.

`2026-11-01-22-05-22` is the clean one. Its laps alternate bench and shift and
carry his own `on_ice` and `shift_time`. Over the first 46.5 minutes, before
two obviously forgotten presses at the end:

| measured by | ice share | median shift |
|---|---|---|
| his own marked shift durations | **36.9%** | 83 s |
| the lap boundaries around them | **44.0%** | |

So **37-44%**, and the true figure is inside it. `2026-10-08-20-15-22` gives a
second, weaker reading of about 42% - weaker because that build wrote no
`on_ice` field at all, so which laps were shifts has to be inferred from
alternation rather than read.

This is the first independent measurement of the quantity the 0.27 fit got
wrong, and it brackets the 40% that five defencemen imply on 11-05. It is also
what the band is really pinned by: 0.18 and 0.20 sit inside 37-44%, while 0.27
reads 35.6% and 0.45 reads 21.4%.

Those two games cannot test a band - they carry no motion trace, so there is
nothing to replay. **The replayable set is still exactly two games.** Of 40
files only five carry `motion` and `motion_threshold` at all, and four of
those are one evening in November, one of which starts 98 seconds after the
game file ends. The archive adds ground truth, not holdouts.

It also adds a population. Fourteen full-length sessions give a heart-rate
cycle each, with motion never consulted: **median 156 s, range 107-189 s**.
That corroborates the ~160 s this player was already known to run, and it
places both tuning games at the extremes - 11-05 at 125 s is his shortest
cycle, 11-03 at 186 s nearly his longest. The tuning sits on two outliers,
which is an argument for a third game rather than for a different band.

One more thing the sweep established: **11-03 is the worst recording in the
set.** A quarter of its wall-clock seconds delivered no usable sample - 501
stale rows plus 542 seconds with no record written at all - against 1.4% on
11-05. Its heart-rate reference is correspondingly unstable, moving between 17
and 26 cycles depending on how peaks are picked, where 11-05 moves only 31 to
43. The two games currently carry equal weight in the fit. They should not.

## What this is not

**Two games, and only one of them with a verified ice-time target.** 11-05 had
five defencemen, which is known. The bench on 11-03 was never recorded and
cannot be recovered from the file - 47.5% is consistent with two pairs and
flatly inconsistent with six defencemen, but that is an inference, not a
measurement.

So this fit is in the same epistemic position the last one was: anchored on a
single game. What changed is that the anchor is a number the player confirmed
rather than one assumed from the wrong position. **The thing worth writing down
next to every future game is how many were dressed at your position.** It costs
one sentence and it is the only input to this that no sensor can supply.

Seven of 32 shifts on 11-05 still never leave zone 2. The veto took the
clearest cases; the rest sit close enough to baseline that a stricter threshold
would start refusing real shifts.

The way to settle any of it is more games. Every one carries the motion trace
and the threshold, so re-checking costs a replay and no ice time.
