# v2.5.3 — the bench fidget, measured instead of argued

Released 2026-11-07. Like 2.5.0, 2.5.1 and 2.5.2 before it, this corrects a
version that never reached the store, so no user ever ran the code it changes.

**This is the version to upload.** [2.5.0](release-2.5.0.md),
[2.5.1](release-2.5.1.md) and [2.5.2](release-2.5.2.md) are tagged and should
not be.

2.5.2 closed out a QA pass. This release does one thing, to the oldest open
complaint in the project: *moving your wrist on the bench collects shifts you
never played.*

---

## What was wrong

`corroboratesIce()` read:

```monkeyc
return hrSlope() >= HR_SLOPE || hrOffset() >= HR_OFFSET;   // 0.25, 4.0
```

The second arm came from a real observation — the peak-to-trough swing of one
shift-plus-bench cycle is 42–62 bpm, so the phase of the oscillation is legible
even when the derivative is buried in noise. The mistake was treating a
*within-cycle range* as the separation available in **any one second**.

Scored against the three recorded games — 9,179 seconds carrying both a heart
rate and a detector verdict:

| test | P(+ \| ice) | P(+ \| bench) | likelihood ratio |
|---|---|---|---|
| `slope >= 0.25 OR offset >= 4.0` (old) | 0.694 | 0.424 | **1.64** |
| `slope >= 0.25` alone (now) | 0.444 | 0.185 | **2.40** |
| `offset >= 4.0` alone | 0.567 | 0.369 | 1.54 |

Sweeping the offset threshold across its entire observed range moves the
likelihood ratio only between 1.0 and 1.7, with no peak to aim at — the mark of
a variable carrying almost no information. Slope has a peak, and 0.25 already
sits on it: the LR-optimal 0.29 scores 2.46 against 2.40, which is not worth
moving for.

OR-ing the two did what OR-ing a noisy test with a good one always does. It
more than doubled the false-positive rate, 0.185 → 0.424, to buy 0.25 of
true-positive rate.

## Why a corroboration signal mattered this much

Corroboration never opens or closes a shift by itself. It picks the
*confirmation window*:

```monkeyc
var needed = corroboratesIce() ? CONFIRM_ICE_FAST : CONFIRM_ICE;   // 3 : 6
```

At `P(+ | bench) = 0.424` the three-second fast path was effectively always
open, `CONFIRM_ICE` was very nearly dead code, and a bench fidget needed only
three seconds of motion to become a shift. The code comment above
`CONFIRM_ICE` had already noticed the symptom in the 2026-11-07 entry-window
experiment — *"corroboratesIce() is true on roughly half of all judgeable
seconds, so nearly every real entry takes CONFIRM_ICE_FAST: 29 fast against 3
slow on 2026-11-05, and 16 against 0 on 2026-11-03"* — and answered it by
raising `CONFIRM_ICE` to ten, which was reverted the same day. The symptom is
now fixed at its source instead, and the entry window is left alone.

## What it does to the recorded games

Replaying the recorded per-second motion through the detector:

| game | shifts (old → new) | ice time | never above 130 bpm |
|---|---|---|---|
| 2026-11-03 22:11 | 23 → **16** | 746 s → **634 s** | 0 → 0 |
| 2026-11-03 23:21 | 1 → **1** | 15 s → **17 s** | 0 → 0 |
| 2026-11-05 20:06 | 34 → **27** | 1642 s → **1387 s** | 4 → **2** |

Fourteen shifts removed across the two full games, and the shifts that never
lift the rate above 130 bpm — the bench-fidget signature — halve on 2026-11-05.

**Expect a smaller ice time.** On 2026-11-05 the published figure would fall
from 27:22 to 23:07. That is the intended direction, and it is not yet
confirmed against ground truth; see *Still open*.

## `hrOffset()` is not gone

It remains the instrument for `HR_VETO`, which reads a level rather than a
derivative and scores a likelihood ratio of 3.06 at −12.0 — because a rate
sitting twelve beats under its own drifting baseline is asking a far deeper
question than four. Only the shallow four-beat use is gone. `HR_VETO` was swept
in the same pass (−8 → 2.10, −12 → 3.06, −20 → 4.85, −25 → 14.88) and
deliberately **not** changed: the deeper thresholds score better but fire on
far less of the bench, and catching bench fidget is the whole point of the
veto.

## A new tool

`tools/fit/replay-detector.py` re-runs the detector offline over any FIT file
the app produced, because `motion`, `motion_threshold` and `on_ice` are
recorded every second. It scores a candidate configuration against the games
already on disk, and prints the likelihood-ratio table above with `--lr`.

```
tools/fit/replay-detector.py --lr data/2026-11-05-game/*.fit
```

This is what makes the next tuning change arguable from data rather than from
theory — and it works on *any* game, including ones recorded by the old
configuration, so nothing about shipping this change is irreversible.

## Size

Measured with `tools/size.sh`, against the tightest supported device limit of
98,304 B (a five-way tie: `descentg1`, `instinct2`, `instinct2s`,
`instinct2x`, `instinctcrossover`; the governing limit is watch-app, not
datafield).

```
ref               total       code       data of 98304
v2.5.2            31364      26436       4928    31.9%
v2.5.3            31942      26817       5125    32.5%
```

The growth is comment and tool, not logic.

## Verified

- `TYPECHECK=3` build clean for `fr57042mm`.
- Package build: 202 of 202 devices, no build paths in 812 packaged files.
- Simulator: game starts, clock advances, `Ice` / elapsed / `ON` agree, no
  exceptions in the run log.
- Secret scan of `dist/IndoorHockey.iq`: zero hits for the Tailscale address,
  the watch serial, the VNC password and any IPv4 literal.

## Still open

**The ice-time drop is not confirmed against ground truth.** The labels the
likelihood ratios are scored against are the detector's *own* `on_ice`, not a
human count of shifts. That circularity runs in the old configuration's favour
— it helped produce those labels — so the offset arm's measured 1.54 is, if
anything, flattering, and the conclusion survives. But "14 shifts removed"
means 14 shifts the *motion* detector claimed; how many were really fidget is
unknown until a game is counted by hand.

**The speed arm is unmeasured.** `corroboratesIce()` still returns true on
`speed >= 2.5 m/s`, untouched here. No game at this player's rink has ever
recorded a position fix — 0 in 5,122 records on 2026-11-05 — so that branch has
never run and could not be scored.

**Developer-field count.** This build asks for 27 fields against a firmware
limit reported as 16. A probe run in the simulator created **227** fields
without a throw, confirming the simulator enforces no limit at all and the
watch is the only place it can be observed. The tiering added in 2.5.2 means
tiers 1–3 come to exactly 14 fields — precisely the set this watch has already
recorded twice — so the worst case is losing the per-second diagnostics, not
the game.
