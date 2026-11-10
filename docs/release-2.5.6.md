# v2.5.6 — the buzz we silenced was the wrong one

Released 2026-11-10. [2.5.5](release-2.5.5.md) changed pausing to a hold so a
glove could not end a game. This release answers a different field report from
the same player, delivered three times before it was properly diagnosed: *"it
was buzzing and beeping a lot at hockey"*, and then, decisively, *"i think it
was just beeping at us when i woukd br kff thr ice a lot."*

That second sentence was the evidence that broke it open, and it contradicted
the first diagnosis.

---

## Counting the noise instead of guessing at it

The 2026-11-09 game, measured:

| source | times | gated by | state in 2.5.5 |
|---|---|---|---|
| firmware lap tone and banner | **49** | `autoLap` → `addLap()` | ON |
| long-shift alert | 16 | `shiftAlerts` | ON |
| line-change alert | 0 | `changeAlerts` | OFF |
| start and stop | 2 | — | — |

**65 noises in one game.** The first diagnosis blamed the 16 long-shift
alerts, and that was wrong in a way the player's own words exposed: a
long-shift alert fires *on the ice*, by construction. The 49 lap tones fire on
the transition **to the bench**, which is exactly where he heard them.

## What was fixed, and the one thing that cannot be

**`shiftAlerts` now defaults off.** At a 60-second target most defence shifts
cross it, so the alert was reporting something normal. 16 of the 65 go away
for anyone installing fresh. Stored settings survive a default change, so
existing users must still turn it off once themselves — which is worth saying
out loud rather than discovering.

**The 49 cannot be fixed in this app.** `Session.addLap()` takes no arguments
in any API level, there is no suppression API, and the native lap banner even
calls `onHide()`. Removing the laps would work and is the wrong trade: every
shift being a lap is what makes the Splits tab a shift chart and what gives
the per-lap heart rate zones — 50 `time_in_zone` records in that one game,
recording something Garmin Connect cannot show because it does not know which
laps were shifts.

So the fix is the watch's own setting: **Alert Tones off, Vibration on.** That
silences all 65 and costs nothing.

**The discoverability bug was the real defect.** `autoLap` is the setting that
causes most of the noise, and its entire description was "Record a FIT lap for
every shift and every spell on the bench." Nothing told the player it was the
thing beeping, which is why the report came in three times. It now names the
tone, gives the count, says the app cannot suppress it, and points at the
free fix.

## Four fields that were being written into the void

`GameModel.mc` created developer fields 27–30 and `fitfields.xml` stopped at
26. The consequence is stated in that file's own header: Garmin Connect builds
its rendering from the **store listing's** declared fields, not from the FIT
file, so an undeclared field is written correctly into every activity and
displayed nowhere.

Four metrics were in that state: bench heart rate recovery, shift fade, heart
rate drift, stride prominence. Now declared — 31 created, 31 declared, no gaps
in either direction and unique sort orders.

`hr_drift` was also labelled `bpm` when it is a slope. It is `bpm/min`.

## What the alert comments claimed and the SDK denies

Two alerts relied on distinguishable vibration rhythms — the idle auto-end
warning was commented as having a rhythm that "has to be unmistakable against
the sensor warning." Local `Attention.html`, checked twice: **"Forerunner
devices do not support vibration patterns."** Multi-element `VibeProfile`
arrays collapse to a single flat buzz, so neither rhythm exists on the target
watch. The comments now record that rather than implying a safety property the
hardware does not provide.

## Tooling, from the same investigation

**The harness was scoring the newest game against constants it never ran.**
`ERAS` had no v2.5.4+ entry, and band 0.18 spans 2.4.0 through 2.5.5, so
`era_for()` returned the 2.5.3 constants for a 2.5.5 recording. Measured both
ways on the real file: the wrong era gives 93.7% agreement and 27 shifts, the
correct one **99.0% and 24** against the watch's 25. The 93.7% was a
lookup artefact, not detector disagreement. Era is now selected from the
file's own `application_version`, with `--era` as an explicit override.

**`session_ice_pct()` refused on any record-stream gap**, so a single dropped
sample killed the number for the 2026-11-09 game. The gap count was only a
proxy for the real hazard — a numerator that banked paused wall-clock — and
that is testable directly, because it reconciles against `total_elapsed_time`
instead of `total_timer_time`:

```
game        gaps        ice+bench   vs timer   vs elapsed
2026-11-03  4 (544 s)     4148 s       +547         -2    <- the pause bug
2026-11-05  0             5119 s         -2         -2
2026-11-09  1 (1 s)       4431 s        -10        -10
```

It now tests the numerator's own arithmetic. 11-03 is still refused; 11-09
reports 42.6% with a note saying why its break was harmless.

## A recommendation measured and refused

An accuracy review recommended raising `MIN_SHIFT_SEC` from 20 to 30 seconds,
described as having a measured gain. It was checked before being taken, and
the first check was itself wrong — it quoted shift lengths from a *replay*
trace rather than from the file, and described the floor as merging short runs
when `ShiftDetector.mc:711` gates the exit on `_secondsInState` and therefore
**extends** the run it is in.

Recounted on the watch's own recorded flag, which reproduces the file's 49 lap
durations exactly:

```
ice   (n=25):  14, 20, 27, 31, 33, 36, 47, 51, 56, 68, 75, 77, 78, 83,
               85, 93, 102, 104, 105, 112, 121, 135, 138, 150, 154
bench (n=24):  20, 20, 21, 26, 32, 33, 46, 79, 80, 81, 94, 106, 107,
               107, 108, 128, 143, 144, 149, 150, 164, 180, 186, 241
```

| floor | ice runs below | bench runs below |
|---|---|---|
| 20 s (shipped) | 1 of 25 | 0 of 24 |
| 25 s | 2 of 25 | 3 of 24 |
| 30 s | 3 of 25 | 4 of 24 |

Two bench spells sit at exactly 20 s — the current floor already binding. The
review withdrew its own recommendation on being shown this; both reviews now
land on 25 s as the ceiling. **Nothing was changed**, because there is no
ground truth to say whether the 27-second run is real, and 20 s is justified
by the user-facing argument rather than by a measured optimum. That is worth
stating plainly rather than presenting 20 as tuned.

## What this release does not claim

There is still **zero ground truth** in this project. The 99.0% above measures
the harness reproducing the watch, not whether the watch was right, and any
sweep scored against `dev:on_ice` will elect the band the file was recorded
at. The README and the store listing make no accuracy claim, which is correct
and is deliberately left that way. See `research-2026-11-10.md` §10 for the
full list of claims the evidence does not currently support.
