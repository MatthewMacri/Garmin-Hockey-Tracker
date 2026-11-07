# v2.5.0 — a self-calibrating stride length, and skating intensity

Released 2026-11-07.
<https://github.com/MatthewMacri/Garmin-Hockey-Tracker/releases/tag/v2.5.0>

The release notes as published, kept here so the repo carries its own history
rather than only GitHub's.

**This is the upload that carries 2.4.0 as well.** 2.4.0 was tagged and never
went to the store, so the listing jumps from 2.3.0 to 2.5.0 and the store's
What's New covers both. Nothing is lost: no user ever saw 2.4.0.

---

## Withdrawn before release: the ten-second entry window

This release was going to open a shift only after **ten** seconds of wrist
motion rather than six, as a fix for the complaint that moving a wrist on the
bench collected shifts nobody played. **It has been withdrawn.** `CONFIRM_ICE`
stays at six, and nothing about shift detection changes in 2.5.0.

It was not refined or softened. It was wrong, and re-measuring it without
heart rate present took it apart three separate ways.

**The window is unreachable by motion alone.** On 2026-11-03, with the
heart-rate fast path disabled, **0 of 232** off-ice motion bursts ever reach a
ten-second ice streak. No shift in that game would have opened on motion alone
at either value, so the setting does not do the thing its name describes.

**The sweep that chose it was decided by three entries.** With heart rate
present, `corroboratesIce()` is true on roughly half of all judgeable seconds,
so about nine entries in ten take the three-second fast path and never consult
`CONFIRM_ICE` at all — 29 fast against 3 slow on 11-05, and 16 fast against 0
slow on 11-03. The entry sweep this section used to carry was therefore a
result about three slow-path entries on one game and none on the other, quoted
as though it were a result about the detector.

**It fails hard when heart rate is absent**, which is this player's ordinary
case: wrist optical only, no chest strap, and not one position fix ever
recorded at his rink. Replayed with heart rate blanked on every row:

| | entry 6 s | entry 10 s |
|---|---|---|
| 11-05, shipped band | 21 shifts, 52.1% ice, longest bench 297 s | 13 shifts, 26.3%, **longest bench 1221 s** |
| 11-03, shipped band | 15 shifts, 46.3% ice, longest bench 387 s | 8 shifts, 17.2%, longest bench 808 s |
| 11-03, its own recorded band | 9 shifts, 14.5% ice, longest bench 1435 s | 1 shift, 3.2%, longest bench 3491 s |

The 11-03 percentages show the size of the collapse within one file rather
than a true ice share — that game was paused four times — so it is the shift
counts and the bench lengths that carry the point.

That is a twenty-minute bench block mid-game at the shipped band, and in the
worst case an entire game recorded as one shift followed by a 58-minute bench.
Nothing on the watch would have said so: `isHealthy()` watches the
accelerometer and reports nothing at all about heart rate.

**Two claims made for the change were false, and both rested on the same
unstated premise.** That it "costs no recorded ice time" — measured, six to ten
seconds costs **1.4 points of recorded ice on 11-03 and 2.3 on 11-05** at the
shipped band, so that one is false by measurement rather than by
interpretation. And that "not one shift the heart rate supports is lost on
either game" — true only where there is a heart rate to support one. Every figure quoted in favour of the change was
measured with heart rate present. That premise was never written down, so it
was never tested.

The negative result is kept in
[detector-tuning.md](detector-tuning.md#the-entry-window-a-negative-result) so
nobody re-runs it. The complaint it was aimed at is real and still open, and
the thing that measurably reduces it needs no detector constant at all:
starting the game at the opening faceoff rather than in the warm-up.

## The replay harness, which had to be fixed first

None of the measurement above was possible until the harness was honest — and
once it was honest, it is what exposed the entry window as unreachable. Three
things were wrong, and all three flattered the result in different directions.

- **Stale seconds were dropped.** When no accelerometer sample arrives the
  watch returns from `tick()` before `learn()` — but `_secondsInState` has
  already advanced, and `observe()` ran before `tick()` was called at all. The
  harness skipped those rows entirely, so every minimum-dwell guard fired
  earlier in the replay than on the wrist. The 2026-11-03 file has **489 of
  them, 13.6%**. (An earlier figure of 501 / 13.9% was `mark_stale()`
  over-flagging and then being cited as an independent count; the heuristic
  has since been fixed. On 11-05 it now flags 2 rows rather than 74.)
- **Transitions were not dated back.** A sweep over confirmation windows was
  therefore measuring mostly the harness's own omission.
- **Two traces were treated as one.** The `on_ice` developer field is written
  as the watch goes and never revised; the session's `ice_time` uses the
  backdated boundaries. On 2026-11-05 they differ by nearly three points —
  26.3% against 23.5% — because the build that recorded it dated a bench
  spell back ten seconds and a shift only six.

It now replays each file with **the constants of the release it was recorded
against**, recovered from the band the watch wrote into the file. Running
today's constants against a 2.1.0 recording and calling the disagreement an
error is how a harness gets "fixed" until it reproduces the wrong thing.

| Game | Reproduces the watch's on-ice seconds |
|---|---|
| 2026-11-03 | **100.0%** |
| 2026-11-05 | **98.4%** |

And the structure, not just the seconds: on 11-05 the replay now produces **48
shifts against the watch's 48**, where it used to make 92 transitions against
94.

Against 84% before. The band default was also two releases stale at 0.27.

And `fitdecode` is gone — it reads files with this repo's own `tools/fit/`
decoder now. The one file in the project that decides whether a detector
change is safe should not be the one that cannot run without pip.

## A stride length nobody has to measure

Distance is pushes times stride length; speed is rate times length. Stride
length is the one term a wrist cannot measure, and the obvious answer — skate
a measured length and press a button at each end — is a tax most players will
not pay.

The way out is that **stride length is close to a constant for a given
skater.** Marino found skating velocity rises with stride *rate* while stride
length barely moves across speeds within one person. What separates a fast
skater from a slow one is length, but that difference is between people, not
between one person's shifts. So it is a calibration constant, needed once.

So the app takes it from GPS on the days it can get it. Where there is a fix
**and** the stride meter has a rhythm in the same second, length is simply
speed divided by rate — `speed × 6000 ÷ pushes-per-minute` centimetres.

Guards, because a wrong constant is worse than none:

- Seconds under 1.5 m/s are ignored; nobody is skating.
- Lengths outside 100–600 cm are discarded as impossible.
- A game contributes nothing unless at least thirty seconds agreed, so a
  stray fix by the arena door cannot overwrite a calibration built outdoors.
- The player's own **Stride length** setting always outranks it. They measured
  it; the app only inferred.

What it learns is stored and reused for every later game, indoors included,
and lands in the file as **Stride Length Used** so a distance always carries
the number it was built from.

**It may never fire for this player.** His rink has produced 0 position fixes
in any game recorded there — 5,122 records in the 2026-11-05 game alone, and
not one of them with a fix. It costs nothing on the days it does not, and it fires at an outdoor
rink, on a pond, or in an arena with enough glass.

Verified end to end in the simulator, with one injection: the GPS side ran on
real simulated speed and reached the calibration with `onIce` true, but the
simulator produces no skating rhythm at all, so the rate had to be supplied as
120 ppm. At 8.4 m/s that stored **418 cm against 420 expected** — and the next
game read it back out of storage and created the distance and speed fields
from it.

What the app will **not** do is seed a stride length from height. A phone
pedometer's walking coefficient is about 0.4 × height; a skating push is
2.6–3.6 m. That would produce a confident number wrong by a quarter, which is
worse than a blank field.

## Skating intensity

Mean on-ice wrist motion multiplied by mean stride rate. Amplitude times
cadence — the shape of a mechanical power term, which is exactly why it is
left **unitless**. Nothing here is calibrated in watts, and dressing it up as
though it were would be the same mistake as inventing a stride length.

It is the one speed-like number that is always available: no GPS, no setting,
no calibration skate. Comparable with your own past games and with nobody
else's.

The two terms are averaged separately rather than multiplied second by second.
Multiplying first would send the index to zero on every second with no
readable rhythm, which would make it a measure of stride coverage wearing a
different name — and coverage is already reported on its own.

## New FIT fields

| Field | Scope | Type | |
|---|---|---|---|
| Stride Length Used | session | UINT16 | cm, from whichever source supplied it |
| Skating Intensity | session | FLOAT | Unitless |

## Size

**35,290 B** of the 98,304 B available on the tightest supported device
(instinct2 and its siblings) — 35.9%, static. 26,647 B of code and 8,643 B of
data. The FR570 has 786,432 B.

Measured with `monkeyc -d instinct2 --build-stats 0`, which is the only figure
here worth quoting: the earlier notes said 27.2 kB for 2.4.0 and 29.0 kB for
2.5.0, and neither reproduces. The same command against the commit that 2.5.0
was cut from gives 34,081 B, so the 29.0 kB was already wrong before the QA
fixes, which added 1,209 B between them.
