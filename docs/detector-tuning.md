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
python3 tools/replay_detector.py <game.fit>            # threshold rule only
python3 tools/replay_detector.py <game.fit> --shifts   # the whole state machine
python3 tools/replay_detector.py <game.fit> --sweep 8,10,12
```

No virtualenv and no pip: it reads the file with this repo's own decoder in
`tools/fit/`. The harness is the thing that says whether a detector change is
safe, so it should not be the one file in the project that cannot run without
a dependency.

The harness is only worth anything if it agrees with the watch, so it checks,
and `--shifts` prints the check before anything else. It replays each file
**with the constants that shipped in the release the file was recorded
against**, recovered from the band the watch wrote into the file. Running
today's constants against a 2.1.0 recording and calling the disagreement an
error is how a harness gets "fixed" until it reproduces the wrong thing.

| Game | Reproduces |
|---|---|
| 2026-11-03 | **100.0%** of the watch's on-ice seconds |
| 2026-11-05 | **98.4%** |

The percentage hides the part that matters more: on 11-05 the replay now
produces **48 shifts against the watch's 48**, where it previously made 92
transitions against the watch's 94. A second-agreement figure can look healthy
while the shift *structure* is still wrong, so both are worth quoting.

Three things had to be right before those numbers were:

- **Stale seconds still tick.** When no accelerometer sample arrives, the
  watch returns from `tick()` before `learn()` — but `_secondsInState` has
  already been incremented, and `observe()` ran before `tick()` was called at
  all. The harness used to drop those rows entirely, so every minimum-dwell
  guard fired earlier in the replay than it did on the wrist. The 2026-11-03
  game has **489 of them, 13.6%** of the file. (That figure replaces an
  earlier 501 / 13.9%, which was `mark_stale()` over-flagging and then being
  cited as if it were an independent count. The heuristic has since been
  fixed.)
- **Transitions are dated back.** `transition()` sets `_backtrackMs` to the
  length of the window that confirmed the change. Without that the harness
  charges every confirmation window to the player as lost ice time, and a
  sweep over window lengths measures mostly its own omission.
- **Two traces, not one.** The `on_ice` developer field is written as the
  watch goes and never revised, so it is the trace to validate against. The
  session's `ice_time` uses the backdated boundaries, so it is the one to
  quote an ice share from. On 2026-11-05 they differ by nearly three points —
  26.3% against 23.5% — because the build that recorded it dated a bench spell
  back ten seconds and a shift only six. (Those are that file's era
  constants, not today's; quoting today's `CONFIRM_BENCH` here was an
  anachronism.)

## The entry window: a negative result

**A ten-second entry window was built, measured, written up as a 2.5.0 feature
and then withdrawn before release.** `CONFIRM_ICE` stays at six. This section
is kept at length, with the numbers that killed it, so nobody reaches for the
same idea and re-derives the same wrong answer.

### What was proposed

Moving a wrist on the bench collects shifts nobody played. That is an
**entry-edge** problem and it cannot be fixed by raising the motion threshold:
the spurious shifts carry *higher* wrist motion than a defenceman gliding at
the point does, so no amplitude cut separates them. The proposed separator was
duration — a fidget is a burst, a shift is not — so `CONFIRM_ICE` was to go
from six seconds to ten.

That diagnosis still looks right. The fix does not follow from it.

### Why it was withdrawn

**1. The window is unreachable by motion alone.** On 2026-11-03, with the
heart-rate fast path disabled, **0 of 232** off-ice motion bursts ever reach a
ten-second ice streak. Not one shift in that game would have opened on motion
alone at either six or ten, so changing the number changes nothing about the
behaviour it is named for.

**2. The sweep that chose it was decided by three entries.** With heart rate
present, `corroboratesIce()` is true on roughly half of all judgeable seconds,
so about nine entries in ten take `CONFIRM_ICE_FAST` and never consult
`CONFIRM_ICE` at all:

| | fast-path entries | slow-path entries |
|---|---|---|
| 2026-11-05 | 29 | **3** |
| 2026-11-03 | 16 | **0** |

The sweep table this section used to carry — 6, 8, 10, 12 and 15 seconds
against shift counts and below-baseline counts — was therefore a measurement
of three slow-path entries on one game and none on the other. Every cell of it
reproduced exactly on re-run, which is the uncomfortable part: the arithmetic
was never the problem. It was a correct measurement of almost nothing,
presented as a measurement of the detector.

**3. It fails hard when heart rate is absent.** Everything quoted in favour of
the change was measured with heart rate present, and that premise was never
written down. It is also not this player's ordinary case: wrist optical only,
no chest strap, and not one position fix ever recorded at his rink. Replayed
with `hr` blanked on every row:

| | entry 6 s | entry 10 s |
|---|---|---|
| 11-05 at the shipped band 0.18 | 21 shifts, 52.1% ice, longest bench 297 s | 13 shifts, 26.3%, **longest bench 1221 s** |
| 11-03 at the shipped band 0.18 | 15 shifts, 46.3% ice, longest bench 387 s | 8 shifts, 17.2%, longest bench 808 s |
| 11-03 at its own recorded band 0.45 | 9 shifts, 14.5% ice, longest bench 1435 s | 1 shift, 3.2%, **longest bench 3491 s** |

The 11-03 ice percentages are there only to show the direction and size of the
collapse within one file. They are not quotable as ice shares — that game was
paused four times — so the shift counts and the bench lengths are the figures
that carry the argument, and they do not depend on a denominator.

A twenty-minute bench block in the middle of a game at the shipped band, and
at worst a whole game recorded as one shift and a 58-minute bench. Nothing on
the watch warns, because `isHealthy()` watches the accelerometer and says
nothing about heart rate. Nothing in the detector compensates either: with no
heart rate, `hrOffset()` and `hrSlope()` both return 0.0 behind their
eight-sample guard, so the fast paths die **and** `HR_VETO` never fires.
Losing heart rate does not degrade this detector, it substitutes a different
one, silently.

### Two claims that were published and are false

Both fail for the same reason, and the reason is the premise above.

- **"It costs no recorded ice time."** Measured: six to ten seconds costs
  **1.4 points of recorded ice on 11-03 and 2.3 points on 11-05** at the
  shipped band. The backdate returns the confirmation window; it cannot
  return a shift that never opened. This one is false by measurement, not by
  interpretation.
- **"Not one shift the heart rate supports is lost on either game."** True
  only where there is a heart rate to support one.

### The proxy was partly a warm-up detector

The metric the sweep was scored on was "shifts whose own mean heart rate sits
below the game's median". That is not a sound target for an entry window, and
it took the no-heart-rate replay to make it obvious.

On 2026-11-05 the below-median shifts run **112–134 bpm against a 136 bpm
median**, and they are not clustered where the write-up put them. They start
at 0, 126, 452, 774, 810, 988, 1759, 1901, 2110, 3804 and 5116 seconds: five
inside the first thirteen minutes, one after the last heart-rate-supported
shift, and the rest spread through the game. A player whose rate has not come
up yet looks identical to a player sitting down. So the proxy measures "early
in the session" at least as much as it measures "not a shift", and an entry
window tuned to remove those is partly a warm-up detector with a confirmation
window for a dial.

The proxy is still the only substitute for ground truth a FIT file supplies
without somebody writing down line changes at the rink, and it is adequate for
asking whether a *band* is wildly wrong. It is not adequate for choosing a
confirmation window to the second.

### What remains true

The complaint is real and unaddressed. The one thing measured to reduce it
needs no constant at all: start the game at the opening faceoff rather than in
the warm-up. A game started seventeen minutes early collects shifts no
detector constant can refuse, because warm-up skating *is* skating — and on
this evidence that is the larger effect by some margin.

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
- **489 of 3605 seconds in the 2026-11-03 game - 13.6% - were stale.** The
  detector holds state and learns nothing across them. That is a separate
  problem from tuning and is not fixed here.
- **That repeat test has a false-positive rate, and it fooled this document.**
  At low motion a settled threshold repeats on its own, so a fresh second can
  look stale. The decisive test is whether including a row *improves* the
  replay: feed every row of 11-05 to the learner and the recorded threshold
  reproduces to **0 mg**, better than the 1 mg you get by dropping the rows it
  flags. Feed every row of 11-03 and the error blows out to **72 mg**. So
  11-03's flagged rows are real dropouts and **11-05's are not: that game lost
  nothing.** With the heuristic fixed, 11-05 flags **2** rows rather than 74,
  which is what that test said all along.

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
| Median learned threshold | 241 mg - the **83rd percentile** of the player's own motion |
| Seconds that could clear it | **16.8%** |

So at most about 17% of any game could be recorded as ice time, whatever
happened on it. It is also a feedback loop: skating hard raises `work`, which raises the
boundary, until skating stops counting. The threshold climbed 206 - 311 mg
across that game.

**The shift count was not the problem.** The detector found 25 shifts; heart
rate on its own shows 22 cycles by the peak-counting parameters used at the
time. It found the shifts and **clipped** them -
only the intense middle of each cleared the boundary, so getting on, the glide
and the change were all recorded as bench. Median shift: 20 seconds as the
watch recorded it, 15 s replayed at its own era.

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
recording than the first - **2 stale rows, against 13.6% of the file on
11-03** - so there is very little to argue about in the input.

It is worth saying plainly what that is *not*. It was tempting to credit a
tighter strap, and that is wrong. **Heart rate never drops out in either
game** - no missing samples in 3605 or 5122 seconds - so the watch kept
optical contact throughout both, and a strap does not come loose for one game
and not the next while the heart rate sensor notices nothing. A 452-second
recording made the same evening as 11-03, on the same build, dropped
**nothing**. What 11-03 actually shows is a cadence: 492 of its 496 stale runs
are single seconds, spaced 5 or 6 apart, starting abruptly at second 181 and
then holding flat for the remaining 57 minutes. That is one batch per 1.171 s
against a 1.000 s tick - the accelerometer delivering about 21.4 Hz where 25
was asked for. Connect IQ clocks delivery by *samples taken*, not by
wall-clock seconds, so pairing one batch to one tick is an assumption the API
never makes.

Its measured cost is smaller than the fuss: injecting 11-03's cadence into
11-05 moves ice time down about 3.4 points and leaves the shift count
unchanged.

At the shipped 0.27 it came back wrong in three ways at once:

| | 11-03 (the fit) | 11-05 (the holdout) |
|---|---|---|
| Ice time | *not quotable* | **27.6%** against a known 40% |
| Shifts | 23, heart rate says 22 | **44**, heart rate says 31 |

The heart-rate cycle count for 11-03 is quoted as 22 above and as 24 below,
and both are this document's own figures. They come from different runs of the
same idea: smooth the rate, count peaks, discard any whose rise from the
preceding trough is too small. The count moves by one or two with the
smoothing width and the minimum rise, which is worth knowing before leaning on
it - it is the reference the whole fit is scored against. The later figures
use a 15-second window, a 50-second minimum separation and a 4 bpm minimum
rise. Neither value changes which band wins.
| Median shift | 49 s | **19.5 s** |
| Shift cycle | 151 s | **93 s** |

Two separate defects, and the per-shift zone data separates them cleanly.
Grading every detected shift by the peak heart rate inside it:

```
11-05   15 of 44 shifts never left zone 2   (280 s)
11-03    0 of 23 shifts never left zone 2
```

One of those fifteen ran 53 seconds with a peak of 119 bpm. **No band fixes
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
0.14 reads 47.4% and overshoots a number we have.

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
| Ice time | **42.9% against a known 40%** | *not quotable* — see below |
| Zone-2 shifts | 7 of 32 | 0 of 22 |

**The 11-03 column's *durations* were wrong until an audit caught it, and the
reason is worth keeping.** That game records at **0.87 Hz, not 1 Hz** - 3605
records across 4149 wall-clock seconds. The replay walks records and the
analysis counted each one as a second, so every 11-03 duration came out about
15% short: 76 s and 145 s were record-index numbers wearing wall-clock units,
and rescaling gives the 93 s and 186 s above. 11-05 records at exactly
1.00 Hz, so none of its figures move. Any future game has to be checked for
its record rate before any *duration* is measured from it.

**The ice share, though, should never have been quoted from this file at all,
and two audits were needed to get there.** The first correction rescaled it
along with the durations, which is wrong twice over: a share is a ratio of
seconds to seconds, so the record rate cancels and it cannot be "5 points
low". That is where the 52.9% came from - an artefact of rescaling a quantity
that does not rescale - and it is why it never agreed with the 47.5% quoted
further down.

The real problem is larger. **The 11-03 record stream has four breaks
totalling 544 seconds: the game was paused.** The detector does not tick while
paused, so replaying the rows as contiguous is right, but no denominator
recovers an ice *share* from it - the session's own `ice_time` banked paused
wall-clock into whichever segment was open. The harness now refuses to print a
share for this file, and this table follows it. Every 11-03 ice percentage
that has ever appeared in this document - 47.5%, 49.0%, 52.9%, 34.2% - was
unsound, and the shift counts, medians and cycles are the figures to use.

## The harness no longer has to be told the band

The band a recording was made with is a property of the file, and getting it
wrong invalidates the replay completely: it compares against a threshold no
watch ever computed and reports a disagreement that is really a settings
difference. That went wrong once already, with 0.45 hardcoded after 0.27 had
shipped, and three shipped values would have made it worse.

So the harness recovers it instead. Exactly one band reproduces the threshold
the watch wrote, and `replay_detector.py` now searches for it by default:

```
$ python3 tools/replay_detector.py \
      data/2026-11-05-game/2026-11-05-20-06-45.fit
samples: 5120   band recovered from the file: 0.270
replayed threshold vs recorded: max abs difference = 1 mg
VERDICT: replay matches the watch

$ python3 tools/replay_detector.py \
      data/2026-11-03-game/2026-11-03-22-11-07.fit
samples: 3116   band recovered from the file: 0.450
replayed threshold vs recorded: max abs difference = 1 mg
VERDICT: replay matches the watch
```

Two files, two different shipped builds, each recovered to the exact value
without being told. `--band` still overrides, for asking what a different band
would have done.

## Two other apps' detectors, which this section called ground truth

A sweep of all 40 files pulled off the watch found two games from before this
app existed, whose laps alternate shift and bench. They were read as the
player's own lap presses - "no accelerometer, no band, no threshold, his own
thumb" - and used as the independent measurement the 0.27 fit had lacked.

**They are not his thumb. They are two other apps' shift detectors.** The
developer field descriptions in the files name them:

| file | developer fields | app |
|---|---|---|
| `2026-11-01-22-05-22` | `on_ice`, `shift_time`, `shots`, `workload`, `ice_ratio`, `distance_est`, `avg_speed`, `max_speed` | **Ice Hockey Tracker**, by RegoCom - Garmin Connect credits it by name on the activity |
| `2026-10-08-20-15-22` | `On Ice`, `Shifts`, `Ice Time`, `Avg Shift`, `Est Speed`, `Speed Source` | a second third-party app |

Every lap in both carries that app's own `on_ice` flag and its own computed
shift duration. That is a detector writing its verdict onto a lap, not a watch
recording a press. `lap_trigger` reads `manual` throughout, but it reads
`manual` for this app's 95 laps on 11-05 as well - `Session.addLap()` produces
a manual-triggered lap - so it separates nothing. The decisive argument is the
player's own standing instruction: he does not touch the watch during a game.

What those two apps read, over the first 46.5 minutes of 11-01, before two
spells at the end that look like a state nobody corrected:

| measured by | ice share | median shift |
|---|---|---|
| Ice Hockey Tracker's own shift durations | **36.9%** | 83 s |
| the lap boundaries around them | **44.0%** | |

and about 42% from the second app, more weakly, because its laps have to be
sorted into shifts by alternation.

**37-44% is still worth having**, but it is a different thing from what this
section claimed. Two independent implementations, neither of them ours, land
either side of the 40% that five defencemen imply on 11-05 - where 0.27 reads
35.6% and 0.45 reads 21.4%. That is corroboration from strangers' code, not a
measurement from the player. The band is pinned by the five-defenceman game,
which is a fact he supplied and no software's opinion.

Those two games cannot test a band - they carry no motion trace, so there is
nothing to replay. **The replayable set is still exactly two games.** Of 40
files only five carry `motion` and `motion_threshold` at all, and four of
those are one evening in November, one of which starts 98 seconds after the
game file ends. The archive adds ground truth, not holdouts.

It also adds a population, and this part is unaffected by whose app recorded
what: it is heart rate only. Fourteen full-length sessions give a heart-rate
cycle each, with motion never consulted: **median 156 s, range 107-189 s**.
That corroborates the ~160 s this player was already known to run, and it
places both tuning games at the extremes - 11-05 at 125 s is his shortest
cycle, 11-03 at 186 s nearly his longest. The tuning sits on two outliers,
which is an argument for a third game rather than for a different band.

One more thing the sweep established: **11-03 is the worst recording in the
set.** A quarter of its wall-clock seconds delivered no usable sample - 489
stale rows plus 544 seconds across four pauses with no record written at all -
against 2 stale rows on 11-05. Its heart-rate reference is correspondingly unstable, moving between 17
and 26 cycles depending on how peaks are picked, where 11-05 moves only 31 to
43. The two games currently carry equal weight in the fit. They should not.

## Self-calibration was tried and rejected

The obvious next move is to stop using a fixed constant at all. The band has
been wrong twice, each refit needed a human to supply a fact no sensor
records, and heart rate gives a shift count the watch has live - so why not
let the detector close the loop on itself during a game? Three schemes were
built and tested offline. All three are worse than the fixed band, and two are
worse *by construction*.

**A closed loop on the heart-rate cycle rate cannot be stabilised, because
shift count is not monotone in the band.** On 11-05 the count climbs from 21
to 36 as the band goes 0.06 to 0.22, then falls back to 29 by 0.36 - so the
heart-rate target of 31 is crossed on *both sides of a maximum*. Raising the
band fragments long shifts (count up) and also drops short ones (count down).
The loop gain changes sign, and worse, the maximum sits near 0.22 on one game
and 0.14 on the other, so the locally-correct sign differs between games at
the same band. Every configuration tried ran to a rail.

**A percentile boundary is circular, and this one nearly caught me.** Setting
the boundary at a fixed percentile of the player's own motion looked
attractive because the threshold percentile was noticeably more stable between
the two games than the band was - that stability reads like a signal. It is
not. It is the symptom. A boundary defined as "the point 30% of this player's
seconds sit above" pins the very output being measured: fed a game of nothing
but his real skating seconds it reports 66% ice, fed nothing but his real
bench seconds it reports 27%.

That test is worth keeping as a tool. Build games with a *known* ice share by
interleaving this player's own real ice seconds and real bench seconds in
controlled blocks, then measure how much of a true change the detector
actually reports - a slope, where 1.00 is perfect:

| boundary rule | slope | robustness to a +-35% motion rescale |
|---|---|---|
| quantile, p78 | 0.13 | 2 pts |
| heart-rate phase | 0.26 | - |
| closed loop | 0.32 | - |
| **fixed band 0.18 (shipped)** | **0.49** | **2 pts** |
| `rest` x 2.2, no `work` term | 0.60 | 5 pts |
| flat 160 mg | 0.70 | 24 pts |

**The shipped detector reports about half of any real change in ice share.**
That is the most useful single number to come out of this and it is not
flattering. It also exposes the real trade-off, which no amount of adaptation
resolves: scale-invariant boundaries survive a different wrist or a tighter
strap but measure ice share poorly, and absolute boundaries measure it well
but move 20-24 points when the motion scale changes. Adapting to the scale of
the player's own motion normalises away part of the signal. More adaptation is
the wrong direction.

One non-adaptive simplification did come out of it: dropping the `work` term
entirely and setting the boundary at `rest` x 2.2. `work` is the term
collisions corrupt - the 2450 mg peaks against a 75 mg median that caused the
0.45 failure in the first place - and deleting it is near drop-in on both
games (same shift counts, same cycles, 43.1% against 42.9% ice) while
improving the slope from 0.49 to 0.60. It is still a fixed constant fitted to
two games, which is exactly where 0.27 was standing when it was wrong, so it
is recorded here rather than shipped.

### Two claims from that work that did not survive checking

Both are recorded because the corrections are more interesting than the
original claims.

**"Losing heart rate costs more than the whole refit."** Reported as ice time
falling 42.9% to 26.5% when heart rate is blanked for the middle third of a
game. Re-running it moves ice time the *other way*, 42.9% to 46.5%. The
difference is what "a dropout" means in code: if the heart-rate window is
cleared, every `CONFIRM_*_FAST` path dies and the detector turns conservative;
if the last reading is simply held - which is what the watch actually does,
because `observe()` ignores a null sample - the stale value keeps corroborating
and the detector turns *permissive*. The real finding is not the number but
that **the detector's response to losing heart rate is several points of ice
time in a direction nobody has established.** That is worth settling, and it
matters more on 11-03, where a quarter of the seconds delivered nothing.

**"The warm-up is phantom ice."** Reported as 45% ice across the first 13
minutes. Split by what was actually happening:

| | ice reported | mean HR |
|---|---|---|
| minutes 0-4, warm-up skate | 87.0% | 138 |
| minutes 5-12, standing around | 18.8% | 115 |
| minutes 13+, the game | 43.0% | 143 |

The detector called a warm-up skate "on the ice" because he was skating on the
ice, and called standing around "bench" because he was. Neither is a detection
error. The 45% average conflates them. What this really is is a **session
boundary** problem - the warm-up should not be inside the game at all - and
that is not something the band, the confirmation window or any adaptive scheme
can address.

## The proposed fix for the false positives, and the test that sized it

Nine zone-2 shifts survive the veto on 11-05. Tracing them: **six of the nine
are moments the player was not in the game, and three are not.** Five fall
before the first genuine shift and one in the 2.4 minutes after the last one;
the remaining three sit inside the run of real play, at 1901, 2110 and 3800
seconds.

An earlier version of this paragraph said five, three and one - eight of the
nine outside the game - and that was wrong in a way that mattered, because
"all nine are moments the player was not in the game" was the sentence the
whole proposed rule below was argued from. Three of them are mid-game, and a
rule that refuses them refuses real play.

(Nine over the whole file; seven over the warm-up-excluded window the ice-share
table above uses, because two of the five sit inside the first thirteen
minutes. An earlier draft of this section said seven and then listed nine,
having taken each number from a different replay. Re-measured: the full file
gives 36 detected shifts at 43.2% ice, nine of them peaking below 144; the
excluded window gives 32 and seven. What is *not* the same either way is the
structural claim - the earlier "eight of these are outside the run of real
shifts" does not survive, as above.) Their motion is not weak - median 85-514 mg against
7-254 mg for real shifts, because a real defenceman's shift is mostly glide.
Two have a walking signature: 200-290 mg every second for 45 s, rhythmic, no
impacts. **No absolute motion statistic separates the classes**, in either
direction, which is why no band and no floor fixes them.

The proposed rule: **make an ice entry provisional until heart rate
corroborates it, then backdate it when it commits.** When the motion streak
completes, mark the entry provisional rather than flipping. Commit when heart
rate reaches zone 3, or rises 6 bpm within 20 s of the provisional start, and
date the shift back to that start. Abandon it when the bench streak would have
ended the shift anyway. A shift that motion never sustains and the body never
confirms never happened.

It is live-computable - only waiting, which `CONFIRM_ICE` already does - and
where it commits it costs no ice time, because the backdate returns every
second the wait consumed. The player sees "bench" for a while into a real
shift; the recorded start and length are unaffected.

**But "costs no ice time" is exactly the claim that the withdrawn entry window
got wrong, and this rule inherits the whole of that error.** A backdate returns
the wait; it cannot return a shift that never commits. This rule commits on
heart rate, so with no heart rate it never commits at all - and with no strap
and no indoor fix, that is this player's ordinary case. Before any of this is
built, it has to be measured with `hr` blanked, the way the entry window should
have been.

**But it was scored on the metric that defines it.** "Peak heart rate never
left zone 2" is the class being removed, and the rule commits on heart rate
reaching zone 3, so removing 9 of 9 is arithmetic, not evidence.

The independent test is `2026-11-01-22-05-22`, which carries 11 shifts that
no band, no motion threshold and no heart-rate rule of ours produced. They are
**another app's detector's shifts**, not the player's lap presses - see the
section above, which got that wrong - so this is agreement with a stranger's
implementation rather than with the truth. Ask the gate whether it would have
accepted each one:

| | peak HR | verdict at zone 3 = 144 |
|---|---|---|
| 9 of the 11 shifts | 148-181 | accept, comfortably |
| 1 shift (65 s) | 161 | accept |
| **1 shift (66 s, marked 48 s)** | **141** | **REFUSED** |

**One in eleven.** A shift another detector was sure of, 3 bpm under the line,
with no 6 bpm rise to rescue it. It is a weaker number than it first looked -
agreement with Ice Hockey Tracker, not with the player - but it is still the
number to argue about rather than 9 of 9, because it is the only one not
computed from the metric the rule is defined on.

It also locates the right operating point. The lowest-peaking real shift on
11-03 reaches exactly 145, and this one reaches 141, so the line belongs at
**140**, not at the 144 the file's zone table gives: 140 accepts all 11
hand-marked shifts and the 11-03 shift, with 1 and 5 bpm of margin, and still
removes 8 of the 9 false positives at no ice-time cost. Note that 144 is what
`UserProfile.getHeartRateZones()` returns while the watch holds a maximum of
205, whereas this player's own recorded maximum is 199 - which would put zone
3 at about 140 by itself. The margin is thin either way and the rule must not
go above about 148.

**Not implemented.** It needs a third detector state and a backdate of
arbitrary length - up to 68 s on this data - which `switchSegment()`'s overlap
guard has never been asked to handle. That is a larger change than anything
shipped tonight, resting on the same two games, and tonight has already shown
what happens when several things change at once.

The cheaper half of the same finding needs no code at all: eight of the nine
false positives exist because the 11-05 activity ran for 16 minutes while
nothing was happening. 11-03 has almost none of them because its timer was
paused at every break. **Starting at the first shift instead of in the warm-up
removes more of this problem than any constant can**, and it is the only thing
that touches the 261 seconds of warm-up skate the zone-2 test cannot even see,
because during a warm-up the heart rate genuinely does reach zone 3. (It does
here: the two warm-up segments peak at 161.)

That half is done - it is written up in the README under *Start it at the
faceoff, not in the warm-up*, and in the store listing's notes, which is where
a player will actually meet it. It is advice rather than code because there is
no signal to act on: the detector sees a warm-up as a game it is doing well at.

### The opposite error, which is the same size

Bench spells that reach zone 4 total 303 s on 11-05 and 447 s on 11-03, but
most is legitimate post-shift lag. Allowing 25 s of lag, the bench time that
elapses before the heart rate even turns over is **79 s on 11-05 and 65 s on
11-03** - roughly 1.5 points of ice each. One case on 11-05 is a 77-second
"bench" spell with heart rate climbing 132 to 171 throughout, almost certainly
one 117-second shift split by a 14-second lull.

So premature shift *ends* cost about as much real ice as the false positives
add. The rule above touches only the entry edge, so it neither helps nor harms
this. It is the better argument for `CONFIRM_BENCH` 14 than the one that
change actually shipped with - and `CONFIRM_BENCH` 14 stands. It is the *entry*
change that was withdrawn; the bench side was measured on the exit edge, where
the fast path is not taking nine entries in ten.

## What this is not

**Two games, and only one of them with a verified ice-time target.** 11-05 had
five defencemen, which is known. The bench on 11-03 was never recorded and
cannot be recovered from the file, and neither can the ice share that was used
to guess at it: that game was paused four times for 544 seconds in total, so
no share off it is sound. The old "47.5% is consistent with two pairs" argument
is therefore withdrawn, not merely corrected. **11-05 is the only game that
constrains the band by ice share at all.**

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
