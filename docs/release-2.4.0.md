# v2.4.0 — how fit you are, not just how hard it was

Released 2026-11-07.
<https://github.com/MatthewMacri/Garmin-Hockey-Tracker/releases/tag/v2.4.0>

The release notes as published, kept here so the repo carries its own history
rather than only GitHub's.

---

## Heart rate recovery

Every number this app has produced so far measures how hard a game was. This
one measures how fit you are, and it is the only one that should improve over
a season.

It is the standard **HRR60**: heart rate at the moment a shift ends, minus
heart rate sixty seconds later, averaged across the game. Hockey hands it over
for free. A game is thirty-odd repeats of exactly the protocol a lab uses — a
hard effort, then a seated minute — and the app already knows the instant each
one starts, because finding that instant is what it was built to do. Nothing
new is asked of the player and nothing new is sensed.

A bench spell shorter than the window reports nothing rather than guessing at
a partial drop.

**A negative result is kept.** A heart rate still climbing a minute after a
shift is a real reading about a player who is not recovering, and averaging it
in is what makes this a measurement rather than a highlight reel. The field is
a signed byte for that reason.

### The accuracy work, which was most of it

The first implementation was short and two things about it were wrong.

**The clock only advanced on seconds the sensor reported.** Wrist optical
heart rate drops out, and a ten-second dropout silently turned HRR60 into
HRR70 — a bigger drop, for a reason that has nothing to do with fitness. The
clock now advances on every tick that passes, and takes whatever sample is
available inside the window.

**Both ends were single samples.** HRR60 is a difference between two numbers,
so the several beats of jitter a 1 Hz optical sensor carries land in the
answer at full size. Each end is now a five-second mean: the far end collected
across seconds 58 to 62, the near end taken from a five-deep ring, since the
rate as a shift ends has to be known at the instant it ends and cannot be
collected forwards. A ring that has gone stale through a long dropout is
refused rather than used, so a recovery is never started from a rate the
player no longer had.

Verified in the simulator: fires at second 62 with five samples in the far
window, timeout unused.

## Skating load

Catapult's PlayerLoad, computed on the accelerometer already on your wrist:
the running sum of `sqrt(dx² + dy² + dz²)` across consecutive samples, in g,
over 100. It accumulates only while the app judges you to be on the ice, so a
game spent mostly on the bench does not quietly inflate it.

Two honest limits, both stated in the README rather than buried:

- **A wrist is not a torso.** The professional units sit between the shoulder
  blades and never see stick work. The number is comparable with your own past
  games and with nobody else's.
- **A difference measured across a paused timer is not a difference.** The
  running sample is dropped whenever the accelerometer buffer breaks, so a
  gap cannot be read as a lurch.

## Per-shift heart rate in the Splits tab

Average and maximum heart rate on every lap — every shift *and* every bench
spell. A 48-second shift means one thing at 150 and another at 188, and until
now the table could not tell you which.

The bench rows are not padding. A bench spell's average heart rate is how hard
the shift before it was still costing you, which is what makes the shift's own
average mean something.

## Max heart rate, as a setting

*Time above 85 %* is only as good as the maximum it is 85 % of, and the number
on a Garmin profile is usually 220-minus-age that nobody ever checked.

The error was asymmetric, which is why this needed fixing rather than
documenting. The app raises its ceiling whenever a game beats it, so a profile
set too **low** corrects itself inside a shift. A profile set too **high**
never corrects at all, and under-reports every hard minute, for good. On this
developer's own watch the profile says 205 against a measured 199 — the line
sitting at 174 where it belongs at 169.

The ceiling is now the higher of two things kept separately: a seed, which is
the player's setting if they gave one and the profile otherwise, and the
highest beat recorded in this game. So a setting can lower the seed while a
real beat still wins.

A value between 1 and 99 is read as a slip of the numeric picker and treated
as unset, rather than clamped up to 100 — which would put the line at 85 and
call an entire game hard.

A/B in the simulator, the same 41-second game at a constant 162 bpm:

| Max HR | Threshold | `hard_time` |
|---|---|---|
| 240 | 204 | 0 |
| 180 | 153 | 41 |

## Withdrawn: the chest strap claim

The live store description said a paired chest strap "is fine and is used for
heart rate as normal." The app has never called
`Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE])`, nobody has skated with
a strap, and [#2](https://github.com/MatthewMacri/Garmin-Hockey-Tracker/issues/2)
has had it down as unverified the whole time. The listing now says so instead
of claiming it.

## New FIT fields

| Field | Scope | Type | |
|---|---|---|---|
| HR Recovery (1 min) | session | SINT8 | Signed, so a rate still climbing is reportable |
| Skating Load | session | FLOAT | PlayerLoad, on-ice only |
| Avg HR | lap | UINT8 | Per shift and per bench spell |
| Max HR | lap | UINT8 | Per shift and per bench spell |

Verified end to end in the simulator: all four `field_description` messages
present with the right base types and units, lap values written on both shift
and bench laps, `ice_load` accumulating.

## Also corrected

The README and the 2.3.0 notes both said the FR570 "advertises a 100 Hz
accelerometer and delivers about 21.4 Hz", which reads as the watch losing
four samples in five. It does not. The app asks for 25 Hz, which is what
`pickSampleRate()` caps it at, and receives full 25-sample batches every
1.171 s. 25/1.171 = 21.35 and 32768/1536 = 21.33: the gap is the timer the
batches are clocked against, not a sensor falling short. The conclusion is
unchanged — a hard-coded 25 still reports every stride 17 % fast — but the
reason given for it was wrong.

## Size

27.2 kB of the 98,304 B available on the tightest supported device
(instinct2 and its siblings), static. The FR570 has 786,432 B.

## Not in this release

- **The bench-fidget retune.** It was diagnosed as an entry-edge problem; the
  detector change itself has not been made. Starting the game at the opening
  faceoff rather than in the warm-up removes most of it at zero cost, and that
  note is in the listing.

  *Still true as of 2.5.0.* A ten-second entry window was built for 2.5.0 and
  withdrawn before release — unreachable by motion alone, and it can record a
  whole game as one shift when heart rate is absent. The entry-edge diagnosis
  survives; the duration fix does not. See `docs/detector-tuning.md`.
- **Distance and speed without a stride length.** Still off by default. There
  is no way to measure a skating stride length from a wrist, and the open
  question is now whether to anchor one from GPS on the days a fix exists.
  [#7](https://github.com/MatthewMacri/Garmin-Hockey-Tracker/issues/7).
