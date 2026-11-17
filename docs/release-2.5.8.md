# v2.5.8 — the detector was reporting shifts it had not measured

Cut 2026-11-13, re-cut 2026-11-17, not yet uploaded. The first release driven
by a chest strap, and by what two games with one exposed.

The strap gave the detector heart-rate corroboration good enough to flip
promptly, and two things that had been hiding behind a slower detector came
out at once. The shift floor stopped being a safety net and started being an
author. And the heart-rate veto — the single rule allowed to contradict
motion — began refusing shifts outright, for the specific reason that the
player's conditioning had improved.

---

## What the strap changed

2026-11-12 is the first game recorded with a Coospo H6. The app needed no
code to use it — `Activity.Info.currentHeartRate` is filled by the firmware
from whatever sensor the activity holds — but the detector behaved
differently, because this rink has no GPS and heart rate is therefore the
*only* corroboration `corroboratesIce()` has:

| | 2026-11-09 wrist | 2026-11-12 strap |
|---|---|---|
| median shift | 78 s | **53 s** |
| HR rise 15 s into a shift | +4 bpm | **+7 bpm** |
| shifts / transitions | 25 / 48 | 26 / 51 |

A median of 78 s is not a defenceman's shift. 53 s is. The rise at shift
onset — the quantity `hrSlope()` reads — nearly doubled, so the fast
confirmation path (`CONFIRM_ICE_FAST`, 3 s instead of 6) was actually
reachable for the first time.

And then the detector ran into its own floor.

## The finding

**Six of twenty-six shifts came back pinned at exactly 19–20 s** — 23% of the
game's shifts reported as a number the detector had chosen rather than
measured.

`MIN_SHIFT_SEC` was set to 20 in 2.5.4, and the sweep that chose it was not
wrong about what it measured: across 8/12/16/20/25/30 the ice share moves by
about a point and the shift count by at most two. But it only ever looked at
*totals*, and a dwell floor does not distort totals. It distorts the
**distribution**, by rewriting every short shift as the floor itself.

Replayed over all four recorded games, shift floor 20 against 12, bench floor
held at 20:

| game | shifts | median | ice % | pinned at floor |
|---|---|---|---|---|
| 2026-11-03 | 19 → 19 | 96 s → 96 s | 46.2% → 45.2% | 1 → **0** |
| 2026-11-05 | 33 → 34 | 44 s → 41 s | 42.0% → 40.1% | 7 → **4** |
| 2026-11-09 | 24 → 24 | 80 s → 80 s | 43.5% → 43.5% | 1 → **1** |
| 2026-11-12 | 26 → 26 | 52 s → 52 s | 37.4% → 37.2% | 6 → **2** |

Shift counts are stable, medians barely move, ice share moves at most 1.9
points and usually a fraction of one. Pinning falls everywhere.

## The floors are now split

**`MIN_SHIFT_SEC` drops to 12. `MIN_BENCH_SEC` stays at 20.**

They were equal only because 2.5.4 raised them together, and the same replay
says they should not be: in the 2026-11-12 game the shortest bench spell is
**24 s** and *nothing* is pinned at the bench floor. The bench floor is not
doing this damage and does not need to move.

Keeping it high also preserves what it was raised for. The 2026-11-09 report
was *"vibrating every ten seconds switching between on ice and bench"* — a
complete on-ice/bench/on-ice **cycle** in 16 s, which needs only one of the
two floors to stay high to remain impossible. At 12 + 20 the shortest legal
cycle is 32 s.

## Stride: two gates that disagreed with each other

`STRIDE_MIN_COVERAGE` rises from **5 to 20**.

Five percent is one accepted second in twenty, which is itself an anecdote.
Neither recorded game reaches even that — 0.3% on 2026-11-09 and 3% on
2026-11-12 — so this changes nothing that has been measured. It bounds the
first game in which the meter half-works, which is the case nobody has seen
and the one where a thin number would be believed.

The real defect was next to it. `distance_est` and `speed_est` were gated on
`measuredSeconds() > 0` — *any* accepted second — while `stride_avg`, the
number both are computed from, was correctly gated on coverage. So the app
would withhold the stride rate as unsupported and then publish a distance
derived from the very same seconds. Both now inherit the rate's bar.

## The heart-rate veto was throwing away real shifts

Found on 2026-11-16, the second game recorded with a chest strap, and the
reason the game read 44.7% ice against the 50% that four defencemen predict.

`ShiftDetector` has exactly one rule where heart rate may *contradict* motion
rather than agree with it:

```monkeyc
private const HR_VETO = 12.0;   // beats under the drifting baseline
return hrOffset() <= -HR_VETO;  // refuse the shift, "however convincing the motion looks"
```

At 57:42 the app recorded 3 m 43 s on the bench. He was skating. The veto
fired on **137 of those 223 seconds**, because his rate sat 19.6 beats under a
baseline his own hard first half had dragged up to 169.

**This is a fitness result turning into a bug.** The same game returned
`hr_drift` of **−17**: his rate came down 17 bpm for the same work. Skating at
146 against a 169 baseline is arithmetically identical to sitting at 131
against a 150 one, so the veto cannot separate them — and the better his
recovery gets, the more shifts it discards.

Motion separates them, and not narrowly. Inside the refused window against a
confirmed bench spell from the same game:

| | refused window | real bench |
|---|---|---|
| median motion | **110 mg** | 8 mg |
| seconds above threshold | **52%** | 10% |
| runs of ≥ 6 s | **7** | 0 |
| longest run | **14 s** | 3 s |

The refused window carries *more* motion evidence than a shift the detector
accepted that same game (78 mg median, 36% above threshold, longest run 9 s).

### The fix

```monkeyc
private const VETO_OVERRIDE_SEC = 14;

if (_iceStreak >= needed && _secondsInState >= MIN_BENCH_SEC
        && (_iceStreak >= VETO_OVERRIDE_SEC || !restingHeartRate())) {
```

Fourteen is the longest run in the window that motivated it, and more than
twice `CONFIRM_ICE`, so clearing it means considerably more than "confirmed".

### Replayed, all five games

Before and after, at 2.5.8 constants, band 0.18:

| game | shifts | median | ice share | max bench |
|---|---|---|---|---|
| 2026-11-03 | 18 → **18** | 88 → 88 s | 42.5% → **42.5%** | 197 → 197 |
| 2026-11-05 | 27 → **27** | 49 → 55 s | 37.5% → 37.8% | 335 → 335 |
| 2026-11-09 | 24 → 25 | 80 → 79 s | 43.5% → 42.9% | 244 → 244 |
| 2026-11-12 | 26 → **29** | 52 → 53 s | 37.2% → **40.6%** | 333 → **262** |
| 2026-11-16 | 28 → 29 | 57 → 57 s | 42.7% → 43.0% | 241 → 241 |

**2026-11-05 is the guard, and it holds.** That game is why the veto exists —
it removed six shifts of a player sitting between periods and shifting around.
Its shift count is unchanged at 27, and 2026-11-03 is unchanged to the
decimal. Those false shifts are wrist bursts; they never sustain fourteen
seconds. The veto keeps the case it was built for and loses only to motion
that does not stop.

**2026-11-12 is the strongest evidence**, being the file the harness
reproduces best at 99.7% second-by-second agreement. It gains three shifts, a
333-second "bench" collapses to 262, and its ice share moves to 40.6% against
the ~38.9% its 6-then-5 defencemen predict — shipped was 1.7 points under,
this is 1.7 over.

### What this does not settle

**2026-11-16 barely moves, and it is the game that prompted the change.** That
file is missing 268 of its seconds — 6.1%, scattered singles — so the replay
runs on a compressed timeline and reaches only 84% agreement where 2026-11-12
reaches 99.7%. Direct inspection of the file is unambiguous that 57:42 was
misclassified; the *replay* of that file is what cannot be trusted. Four
defencemen predict 50% and even the most aggressive override tested reached
45.2%, so this does not close the gap.

**The supported range is 12–16, not a sharp 14.** 16 lands 2026-11-12 closest
to expectation; 12 recovers most on 2026-11-16. Nothing in five games
separates them by more than two points. 14 is the midpoint, chosen on the
longest-run measurement rather than on the sweep.

## hr_drift is `bpm`, not `bpm/min`

Carried from the fix made on 2026-11-13 and included here because it has not
shipped. 2.5.6 relabelled this field reasoning that it "is a slope"; it is a
slope *multiplied by a time*:

```monkeyc
return (slope * minutes).toNumber();
```

so the per-minute cancels and the result is a total — how many bpm higher the
same effort cost by the end. The error surfaced the only way it could: on
2026-11-12, the first game in which the field ever rendered, it read **19
bpm/min**, which across 74 minutes is +1,400 bpm. Read as bpm the same 19 is
0.26 bpm/min of cardiac drift, which is ordinary. The value was never wrong.

## Tooling

`tools/replay_detector.py` gains a `_V258` era and `APPVER_V258 = 9`, since it
selects constants by the file's own `application_version` and would otherwise
replay every future game against a floor the watch is no longer running.
**That 9 is an expectation, not a reading** — 2.5.7 is internal 8, but two
uploads in this app's history never became store versions at all. Check the
dashboard after the upload and correct it if 2.5.8 landed elsewhere.

`_V258` also carries `VETO_OVERRIDE_SEC`, and `Detector` mirrors the watch's
gate rather than its `restingHeartRate()`, so the override is applied in the
one place the watch applies it. It defaults to `None` for every earlier era,
where the veto really was absolute.

`tools/fit/fitread.py` now decodes `device_info`, so a game can be asked which
sensor fed it rather than assumed. Two things were wrong in the first cut of
it, both found against real files:

- the heart-rate test keyed on ANT+ `device_type 120`, which a **Bluetooth**
  strap never sets — it would have reported "no strap" for precisely the
  setup it was written to check;
- `serial_number` was left unnamed rather than dropped, and unnamed is not
  redacted: it still decodes, as `f3`, and printed the watch serial that was
  purged from this repo once already. Field 29, a BLE MAC address, did the
  same thing. Both are now dropped in the decoder.

## Size

```
ref               total       code       data of 98304
v2.5.6            34513      29029       5484    35.1%
v2.5.7            34981      29414       5567    35.6%
v2.5.8            34999      29443       5556    35.6%
```

Seventeen bytes more than 2.5.7, for the floor split, the stride gates and the
veto override together.

## Verified

Five games replayed through `tools/replay_detector.py`, both tables above.
`TYPECHECK=3` builds clean on `fr57042mm`, `venu3` and `instinct2`.

One trap worth recording: `data/2026-11-03-game/` holds four `.fit` files, and
the alphabetically first is **not ours** — `2026-11-01-13-08-42.fit` carries
`application_version` 39 and six developer fields with none of this app's
names. The game is `2026-11-03-22-11-07.fit`. Globbing a directory and taking
the first match silently replays a foreign file; check `application_version`
and the field names, never the directory name.

**Not verified against ground truth, as ever.** Every number in that table is
the harness reproducing the watch. The strongest external check this project
has is still the one that arrived by conversation: with six defencemen for
half of the first period and five thereafter, expected ice share is about
38.9%, and 2026-11-12 measured **37.3%**. That validates the ice *share*. It
says nothing about whether the 26 shifts are the 26 shifts that happened.

2026-11-16 adds a second such check and it is the less flattering one: four
defencemen predict 50% and the watch recorded **44.7%**. The veto override
closes part of that, not all of it.

## Still open

- **Nobody has counted a game by hand.** Unchanged since 2.5.5 and still the
  largest unverified claim here.
- **The stride meter does not work.** 0.3% and 3% coverage. The H6 cannot help
  — it has no accelerometer — and the wrist is the wrong place for it.
- **Per-shift heart-rate zones require `autoLap`**, which is the lap alert a
  player has now asked to be rid of four times. Computing the zones in-app
  would let the laps be turned off without losing the data. Not done.
- **Ten products may have no reachable pause or stop**, from
  [2.5.7](release-2.5.7.md). Unchanged.
- **2026-11-16 still reads about five points under its predicted ice share**
  after the veto fix. Something else is losing ice, and the file's 6.1% of
  missing seconds means the harness cannot be the thing that finds it.
- **Three shifts in 2026-11-16 look false** — 7 s at the opening, and two more
  at 142–146 bpm against a 170 on-ice average, one of them running to the
  final buzzer. Warm-up and cool-down remain undetected as such.
- **Records are being dropped.** 268 seconds missing on 2026-11-16 and 544 on
  2026-11-03, against 0 and 13 on the two clean games. Unexplained, and it
  degrades every replay of those files.
