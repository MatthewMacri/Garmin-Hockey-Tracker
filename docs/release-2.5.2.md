# v2.5.2 — what six QA passes over 2.5.1 found

Released 2026-11-07. Like 2.5.0 and 2.5.1 before it, this corrects a version
that never reached the store, so no user ever ran the code it fixes.

**This is the version to upload.** [2.5.0](release-2.5.0.md) and
[2.5.1](release-2.5.1.md) are tagged and should not be.

Seven agents went over 2.5.1 — four on the code and the documentation, three on
questions that bear on the upload. Fourteen defects, three of them in fixes
that 2.5.0 and 2.5.1 had announced as working.

---

## Three fixes that did not do what they said

**The heart-rate maximum guard was a no-op.** 2.5.0 added a rule that a new
maximum must be credible *and nearly repeated* before it raises the 85% line,
so that one optical spike could not silence `hard_time` for a game. The counter
was never cleared on promotion. It reaches its threshold of three on the third
second of any game with a heart rate and stays there, after which every new
high promotes on the single sample that raised it — the guard was exactly the
bare `if (heartRate > _hrObservedMax)` it replaced, plus a credibility ceiling.

The repetition test was wrong as well as the counter. It asked whether the beat
was *at least* the candidate minus one, which is true of every reading above
the candidate however far above, so a 229 bpm cadence-lock artefact read as
"the candidate, seen again" rather than as a new candidate. It now has to be
within one beat in **either** direction.

**Heart-rate recovery was moved off the mark it was already on.** 2.5.0's notes
said the far window "collected seconds 58 to 62 but fired as soon as five
samples had arrived, so it averaged out at 62 s", and moved it four seconds
earlier. The first half of that sentence is right and the second half
contradicts it: 58 to 62 averages **60**. The window was already centred. The
change produced seconds 56 to 60, a mean of 58, and 2.5.0 shipped HRR58 — a
*smaller* drop than the field it writes claims to be. Reverted, and the start
is now derived from the two constants (`HRR_AT - (HRR_WINDOW - 1) / 2`) so it
cannot drift again.

**The GPS staleness window was nine seconds, not four.** 2.5.1 fixed a real
latch — the model re-fed its last cached fix every second, so the detector's
own counter reset every second and never aged anything out — and said the new
constant was "matched to" the detector's. It is not matched to it; the two
**compose**. The model stopped feeding at second five, and only then did the
detector's own count start climbing from zero toward its own limit, so a fix
still voted at second nine while both constants and both comments said four.
The detector now drops a speed the moment it is handed a null, and one number
decides.

## Numbers that were still not measured

2.5.0 and 2.5.1 were both about not publishing numbers the app had not
measured. Four more were found.

- **`work_rest` published `0.0` for the dead-accelerometer game** — the exact
  case 2.5.1 added its gate for. With the accelerometer silent the detector
  never flips, the whole game banks as one shift with no bench, and the ratio
  is zero *because nothing ran*. It sat beside the absent `ice_load` and
  `stride_coverage` that had been withheld for that very reason, and the watch
  was drawing `--` on the same screen. The first attempt at this simply gave
  it their gate, and the simulator caught that going too far the other way: a
  bench spell entered **by hand** through the correction menu is a real
  boundary whatever the accelerometer is doing, and that run withheld the
  field while the watch drew `1:1.1` from the same two numbers. A zero ratio
  is only credible if the detector was running; a non-zero one stands on the
  bench time itself, and the gate now says so.
- **`hard_time` published `0`** whenever a maximum could be seeded from the
  Garmin profile, even on a game where the optical sensor reported nothing at
  all. "Zero seconds above 85% of maximum" is a statement about a player;
  without a pulse it is a statement about a sensor. It now needs a threshold
  *and* an observed heart rate.
- **`stride_avg`, `dist_est` and `speed_est` were gated on the wrong thing.**
  2.5.1 required a wrist-motion sample. That says the accelerometer delivered;
  it does not say a *stride* was ever measured, which is far narrower — the
  rhythm has to clear an autocorrelation gate, an octave guard and a prominence
  test. They now require a second that produced a rate. `stride_coverage`
  deliberately keeps the looser gate: 0% across forty examined seconds is a
  finding, and it is the number whose whole job is to say the rate beside it
  means nothing.
- **`hr_recovery` clamped to the FIT invalid value.** The field is `SINT8` and
  FIT's invalid value for `SINT8` is `0x7F` = **127**. The clamp was to 127 —
  so a value too large to represent was written as the exact sentinel meaning
  "not measured", in the one function working hardest to keep those apart. Now
  126. (`-128` is a valid `SINT8`, so the floor needed no change.)

## The guard that was only on one path

`switchSegment()` decrements `shifts` when a shift is dated back out of
existence, so that `shifts × avg_shift` cannot disagree with `ice_time`.
`endGame()` called the same function and **threw its answer away**, so a game
whose final segment was under a second counted a shift that `avg_shift` and
`max_shift` excluded — the precise disagreement the guard exists to prevent,
surviving on the one path that never got it.

`saveIfRecording()` had a related hole of its own. It writes the session fields
when the system kills the app mid-game, and it does not bank the open segment —
so `_iceMs` was zero while the published `ice_time` already counted the shift
in progress. A battery dying ten minutes into a first shift wrote `ice_time
600` and then withheld the on-ice heart rate, skating load and stride coverage
that had been measured for all ten of those minutes. The comment above that
gate had insisted it "tests the PUBLISHED value"; it tested `_iceMs`. Now it
tests what it publishes.

## Laps that described nothing

Two defects, both newly reachable because of 2.5.0's decrement:

- **A segment that banked nothing still wrote a lap.** Lap lengths round
  half-up where `bankShift()` takes a floor, so a 970 ms segment was *refused*
  as a shift — with `shifts` decremented for it — while its lap claimed
  `shift_time 1`. A fully backdated segment was worse, writing `shift_time 0`
  **and** `bench_lap 0` and breaking the rule this app states for itself: that
  every lap reads unambiguously as either a shift or a spell on the bench. Any
  shift the detector ends within about twelve seconds of opening it lands here,
  which is most of the false positives in a real game. No lap is written now;
  the sliver merges into the next one, which costs under a second of lap-timer
  time against a lap that was a wrong number.
- **`shifts` reaching zero suppressed the following bench lap.** The bench
  branch was guarded `shiftCount > 0`, written for a bench spell with no shift
  before it. That cannot happen — the game always opens on the ice — so the
  guard was dead code until the decrement brought it to life with the wrong
  meaning: a game whose only shift was dated away got no lap for the real bench
  spell that followed, leaving `bench_time` with nothing behind it.

## A pause re-opened the latch it was meant to close

2.5.0 taught the detector to age out heart rate and GPS speed. But
`onTick()` returns before `observe()` while the game is paused, so both ages
are **frozen for the whole intermission** and resume holding whatever they held
when play stopped. The first seconds of the second period were judged against a
fifteen-minute-old heart rate and a fifteen-minute-old position fix. `stop()`
now ages both out by hand and drops the rolling heart-rate window, which was
evidence about the same vanished seconds.

In the same family: heart-rate recovery required three samples at the far end
of its window and accepted **one** at the near end, which `pause()` made newly
reachable by clearing the ring. The argument for a minimum says nothing about
which end it applies to. Both ends now need three.

## The screen could contradict itself

Caught in the simulator: `Ice 1:42` beside `ON 1:43`. In a game with one
unfinished shift those are the same quantity — ice time is banked shifts plus
the one in progress, and nothing had banked — so Ice reading *smaller* than the
shift inside it is impossible from a single instant.

Every live number goes through one helper that read the system timer afresh on
each call, and a draw calls it several times. A draw that straddled a second
boundary mixed two different seconds. The model now pins one instant per frame.
The FIT file was never affected: `endGame()` stops both clocks and banks the
final segment before any field is written.

## Verified

In the simulator, which delivers no accelerometer data and no heart rate, with
the file decoded rather than the screen trusted:

| | before | after |
|---|---|---|
| `work_rest`, no bench spell | `0.0` | *absent* |
| `work_rest`, bench entered by hand | `1.176` | `1.176`, matching the watch's `1:1.1` |
| `hard_time` | `0` | *absent* |
| `ice_load`, `stride_avg`, `stride_coverage` | *absent* | *absent* |
| `shifts` / `ice_time` / `avg_shift` / `max_shift` | 1 / 17 / 17 / 17 | unchanged |
| laps | — | one shift lap of 17 s, one bench lap of 21 s, no 0/0 lap |

Eight consecutive frames were captured across a second boundary; the header,
the clock and the segment line moved from 0:24 to 0:25 together.

Also exercised end to end with screenshots: pause (clock frozen through twenty
seconds, resume not credited with them), the paused menu, the correction item
in both directions, discard-then-cancel (game continued, nothing written) and
discard-then-confirm (its own in-progress file removed, every previously saved
game untouched).

## Size

**31,342 B** of the 98,304 B available on the tightest supported device
(instinct2 and its siblings) — 31.9%, static. 26,414 B of code and 4,928 B of
data. The FR570 has 786,432 B.

That is the release build, which is what installs. Measured at this tag with

```
monkeyc -d instinct2 -f 'monkey.jungle;icons.jungle' \
        -y "$KEY" -r --build-stats 0
```

| Tag | Release build | Of 98,304 B |
|---|---|---|
| v2.4.0 | 27,983 B | 28.5% |
| v2.5.0 | 30,647 B | 31.2% |
| v2.5.1 | 30,831 B | 31.4% |
| v2.5.2 | 31,342 B | 31.9% |

Release builds only. **A debug build's size is not a property of the commit** —
its data segment carries the build directory's path and grows about 8 bytes per
character of it, so the same v2.4.0 commit measures 32,330 B built in this repo
and 32,842 B built from a temporary worktree 64 characters deeper. Two of this
repo's size claims were debug builds, and one of those compared two different
paths and called the difference a release's worth of code.

## Documentation

Ten errors, most of them introduced earlier the same day:

- The HRR explanation above, which had the before and after backwards.
- 2.5.1's size section printed **2.5.0's** figure — measured before the commit
  rather than at the tag, which is the same mistake the section is about.
- The 2.4.0 size correction led with a debug figure from a temporary worktree,
  and printed a reproduction command that omits `-f` and `-y` and simply fails.
- The README and a code comment said a dropout-inflated "HRR70" would be a
  *smaller* number. It is a bigger drop — the heart is still falling at second
  seventy. 2.4.0's notes had it right and were contradicted by both.
- "Overstates by 15%" was a truncation of 15.5%.
- An orphaned sentence fragment — "Against 84% before." — with no subject.
- The store guide told the reader to expect the version hint to read *(2.4.0)*
  after typing `2.5.1`, and elsewhere called the live listing 2.1.0 where the
  rest of the file says 2.3.0 four times.
- The stride calibration range is 100–500 cm, matched to the **Stride length**
  setting's own maximum; the README and 2.5.0's notes still said 600.
- And the claim corrected below, which was the only one with a consequence
  outside the repo.

## A store claim that was false, settled by measurement

The upload guide said the version string typed into the store form is "the
number that lands in every FIT file's `application_version`, and a free way to
tell a game recorded against this release from one recorded against 2.3.0."

It is not. `application_version` is a FIT **uint**, conventionally the version
times one hundred; a free-text string has no representation in it. The string
is typed after the binary is signed and never reaches it. Decoded from this
watch's own recordings — 2026-11-03, 2026-11-05, and the simulator's output —
`application_version` is **0** in every one.

The upload guide now records the correction, along with three things worth
knowing before the form is opened: the developer dashboard moved to
`apps-developer.garmin.com` in November 2025, auto-migrated devices are
silently dropped by the next upload unless they are added to `manifest.xml`,
and "Signature check failed" beside "Status: Verified" is a display artefact
that does not block — while "All app versions must be signed with the same key
pair" is the one that does.

## Still open

The bench fidget. `CONFIRM_ICE` is still 6, and nothing in this release
changes shift detection. The research done alongside this QA pass is in
[detector-tuning.md](detector-tuning.md#what-the-literature-says-and-what-it-does-not),
and its first recommendation costs nothing to act on: the heart-rate
corroboration threshold is **4.0 bpm against a measured on-ice/bench separation
of 1.1–3.8 bpm** — a threshold set above the difference it is meant to detect.
