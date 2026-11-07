# v2.5.0 — the bench fidget, and a stride length nobody has to measure

Released 2026-11-07.
<https://github.com/MatthewMacri/Garmin-Hockey-Tracker/releases/tag/v2.5.0>

The release notes as published, kept here so the repo carries its own history
rather than only GitHub's.

**This is the upload that carries 2.4.0 as well.** 2.4.0 was tagged and never
went to the store, so the listing jumps from 2.3.0 to 2.5.0 and the store's
What's New covers both. Nothing is lost: no user ever saw 2.4.0.

---

## Moving your wrist on the bench no longer collects shifts

This was the complaint, and it needed the right diagnosis before it could have
a fix. It is an **entry-edge** problem, and it cannot be solved by turning the
sensitivity down. The spurious shifts carry *higher* wrist motion than a
defenceman gliding at the point does, so no amplitude cut separates them.

What separates them is duration. A fidget is a burst; a shift is not.

**Opening a shift now takes ten seconds of motion rather than six**, when
nothing else agrees with it. When heart rate or GPS does agree, entry is still
three seconds, unchanged.

Replayed against both recorded games. The metric is shifts whose own mean
heart rate sits below the game's median — a player sitting down. It is a
proxy, not ground truth, but it is the only one a FIT file supplies without
somebody writing down line changes at the rink.

| Plain entry | 2026-11-05 | 2026-11-03 |
|---|---|---|
| 6 s (to 2.4.0) | 35 shifts, 11 below baseline | 18 shifts, 5 below |
| **10 s (shipped)** | **33, 9** | **17, 4** |
| 12 s | 32, 9 | 17, 4 |
| 15 s | 31, 8 | 17, 4 |

Every shift the change removes between six and ten seconds is one the heart
rate says was not a shift, and **not one shift the heart rate supports is lost
on either game**. At twelve it stops being selective: 11-05 loses a good shift
and gains nothing.

**It costs no recorded ice time.** `transition()` dates the boundary back by
the length of the window that confirmed it, so the extra four seconds come
back into the shift. What it costs is four seconds of the screen still saying
BENCH at the start of a shift heart rate has not yet agreed with.

### What this does not settle

Two games, one player, one rink, and a proxy for ground truth rather than
ground truth. It also does not touch the larger problem, which is the warm-up:
a game started seventeen minutes before the opening faceoff collects shifts no
detector constant can refuse, because warm-up skating *is* skating.

## The replay harness, which had to be fixed first

None of the table above could be measured until the harness was honest. Three
things were wrong, and all three flattered the result in different directions.

- **Stale seconds were dropped.** When no accelerometer sample arrives the
  watch returns from `tick()` before `learn()` — but `_secondsInState` has
  already advanced, and `observe()` ran before `tick()` was called at all. The
  harness skipped those rows entirely, so every minimum-dwell guard fired
  earlier in the replay than on the wrist. The 2026-11-03 file has 501 of
  them, 13.9%.
- **Transitions were not dated back.** A sweep over confirmation windows was
  therefore measuring mostly the harness's own omission.
- **Two traces were treated as one.** The `on_ice` developer field is written
  as the watch goes and never revised; the session's `ice_time` uses the
  backdated boundaries. On 2026-11-05 they differ by nearly three points —
  26.3% against 23.5% — because a bench spell is dated back fourteen seconds
  and a shift only six.

It now replays each file with **the constants of the release it was recorded
against**, recovered from the band the watch wrote into the file. Running
today's constants against a 2.1.0 recording and calling the disagreement an
error is how a harness gets "fixed" until it reproduces the wrong thing.

| Game | Reproduces the watch's on-ice seconds |
|---|---|
| 2026-11-03 | **100.0%** |
| 2026-11-05 | **97.4%** |

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

**It may never fire for this player.** His rink has produced 0 fixes in 5,011
records. It costs nothing on the days it does not, and it fires at an outdoor
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

29.0 kB of the 98,304 B available on the tightest supported device
(instinct2 and its siblings), static. The FR570 has 786,432 B.
