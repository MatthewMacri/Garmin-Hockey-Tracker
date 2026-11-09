# v2.5.3 — the bench fidget, measured instead of argued

Released 2026-11-07. Like 2.5.0, 2.5.1 and 2.5.2 before it, this corrects a
version that never reached the store, so no user ever ran the code it changes.

**This is no longer the version to upload** - see [2.5.4](release-2.5.4.md).
[2.5.0](release-2.5.0.md), [2.5.1](release-2.5.1.md) and
[2.5.2](release-2.5.2.md) should not be installed either.

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

Replayed through `tools/replay_detector.py` at the shipped band, with
`HR_OFFSET_ARM` as the only difference between the two rows. The harness
reproduces 98.4% of the watch's own seconds on the 2026-11-05 file when run at
that file's era, which is what makes the counterfactual worth reading.

| game | | shifts | ice share | median shift | below-baseline HR |
|---|---|---|---|---|---|
| 2026-11-03 22:11 | 2.5.2 | 22 | 46.5% | 80 s | 8/22 |
| | **2.5.3** | **20** | **43.7%** | **80 s** | **8/20** |
| 2026-11-05 20:06 | 2.5.2 | 35 | 40.9% | 39 s | 10/35 |
| | **2.5.3** | **28** | **38.4%** | **55 s** | **8/28** |

Nine shifts removed across the two full games, and the ice share falls by 2.8
and 2.5 points.

The most telling number is the median shift on 2026-11-05, which rises from
**39 s to 55 s**. A real hockey shift is 40–60 s. A detector reporting a median
of 39 s is reporting something that is not shifts; one reporting 55 s is in the
right range. That is the shape of the change — it removes short spurious
entries rather than trimming real ones, which is why the median goes up while
the count goes down.

What it does **not** do is change the proportion of shifts that never lift the
rate off its baseline: 8/22 → 8/20 and 10/35 → 8/28, flat either way. Removing
the offset arm removes short shifts, not specifically low-intensity ones.

**Expect a smaller ice share**, by roughly two and a half points. That is the
intended direction, and it is not confirmed against ground truth; see
*Still open*.

### A correction

An earlier draft of this file reported 23 → 16 and 34 → 27 shifts, and claimed
the low-HR shifts halved from 4 to 2. Those came from a throwaway replay
written for this analysis which used the shipped band against files recorded at
a different one, and today's confirmation windows against files recorded with
2.1.0's. The project already had `tools/replay_detector.py`, which keys the
constants to the band each file was recorded at precisely so this cannot
happen, and which warns in its own comments that doing otherwise is "how a
harness gets fixed until it reproduces the wrong thing". The table above is
from that harness. The likelihood ratios below are unaffected — they are
computed from recorded heart rate against the recorded verdict, with no replay
involved.

## `hrOffset()` is not gone

It remains the instrument for `HR_VETO`, which reads a level rather than a
derivative and scores a likelihood ratio of 3.06 at −12.0 — because a rate
sitting twelve beats under its own drifting baseline is asking a far deeper
question than four. Only the shallow four-beat use is gone. `HR_VETO` was swept
in the same pass (−8 → 2.10, −12 → 3.06, −20 → 4.85, −25 → 14.88) and
deliberately **not** changed: the deeper thresholds score better but fire on
far less of the bench, and catching bench fidget is the whole point of the
veto.

## The harness

`tools/replay_detector.py` gained two things:

- `HR_OFFSET_ARM`, so both configurations can be replayed from the same file
  and a future change to corroboration can be scored the same way.
- `--no-offset-arm` / `--offset-arm`. 2.5.3 changed corroboration without
  changing `HYSTERESIS`, so the band no longer identifies the era: a 2.5.3
  recording and a 2.4.0 recording are both band 0.18 and `era_for()` returns
  the older constants for either. The flag says which build wrote the file.

It also had `CONFIRM_ICE` sitting at **10** as the class default — the entry
window from the experiment that was raised and reverted on 2026-11-07. Any
replay not routed through an era dict was being scored at a window the app has
never shipped. It is back to 6.

```
python3 tools/replay_detector.py <game.fit> --band auto --shifts
python3 tools/replay_detector.py <game.fit> --band auto --no-offset-arm
```

Nothing about shipping this change is irreversible: `motion`,
`motion_threshold` and `on_ice` are recorded every second, so either
configuration can be reconstructed from any game either one produced.

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

---

## This release should not be installed

2.5.3 shipped the same day a player lost a game to an accidental press chain
reaching Discard, and to a bench-change buzz with no off switch. See
[2.5.4](release-2.5.4.md), which is the version to upload.
