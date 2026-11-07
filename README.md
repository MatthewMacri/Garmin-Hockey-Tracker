# Garmin Hockey Tracker

A Connect IQ watch app that tracks an ice hockey game from your wrist **without
being touched**. One press at the opening faceoff; after that it works out
every shift and every spell on the bench by itself and keeps recording until
you stop it. It records a real hockey activity that syncs to Garmin Connect.

Built and tested on the **Forerunner 570**. The layout is resolution-independent,
so the same build runs across the Garmin watch range.

<p align="center">
  <img src="docs/demo.gif" width="300" alt="A game being tracked: the game clock runs unbroken, the shift clock opens and closes, and the summary lands at the end" />
</p>
<p align="center">
  <sub>A short game tracked end to end &middot;
  <a href="https://youtu.be/LM8cZ_diB8s">the same clip in 1080p</a></sub>
</p>

<p align="center">
  <img src="docs/screenshots/01-ready.png" width="32%" alt="Ready to start" />
  <img src="docs/screenshots/02-on-ice.png" width="32%" alt="On the ice, shift clock green" />
  <img src="docs/screenshots/03-bench.png" width="32%" alt="On the bench" />
</p>
<p align="center">
  <img src="docs/screenshots/04-press-again.png" width="32%" alt="Pausing asks for a second press" />
  <img src="docs/screenshots/05-menu.png" width="32%" alt="The stop menu" />
  <img src="docs/screenshots/06-summary.png" width="32%" alt="Post-game summary" />
</p>
<p align="center">
  <sub>Ready &middot; on the ice &middot; on the bench &middot; pausing asks twice &middot; the stop menu &middot; final summary</sub>
</p>

---

## What it does

- **Automatic shift detection** — no button per line change. The app decides
  when you are on the ice and when you are on the bench, and splits the
  activity accordingly.
- **One continuous game clock** — no periods to set up and nothing that ends
  the activity on a schedule. A real game runs longer than the sum of its
  periods, so the recording stops when you stop it and not before.
- **Shift clock** — green → amber → red as the shift runs long, with a long,
  full-strength buzz at your target length so it is felt through a glove. The
  ring around the screen fills with it, readable without reading a number.
- **Total ice time on screen all game**, not only in the summary afterwards.
- **On-ice heart rate, separated from bench heart rate** — the number this app
  exists to produce. See below.
- **Stride rate from the wrist**, in pushes per minute, with a coverage figure
  saying how much of your ice time the average actually rests on.
- **GPS on** — speed and distance are recorded when a fix is available.
- **One screen** — everything visible at a glance, no paging mid-game.

```
       Ice 14:06            total time on the ice so far
      ┌─────────────┐
         42:18              the game clock, counting up
       ON 0:42              green → amber → red; BENCH in blue
      148 bpm  9 sh         heart rate and shifts so far
      └─────────────┘
          the outer ring fills as the current shift runs toward its target
```

## How the shift detection works

Three signals are available and they are not equally good:

| Signal | Latency | What it is good for |
|---|---|---|
| **Wrist motion** | ~1 s | The only signal that responds fast enough, and the only one that separates skating from standing on the bench. Noisy. |
| **Heart rate** | 20–60 s | Reliable but far too slow to open or close a shift. HR keeps climbing after a shift ends and falls for a minute afterwards. It can, however, *refuse* one: a rate far below its own baseline is a player at rest. |
| **GPS speed** | instant, when it exists | Unambiguous — nobody reaches 3 m/s on a bench — but indoor rinks usually never get a fix. |

So motion decides, and the other two only agree with it — with the single
exception noted below, where heart rate overrules motion by refusing a shift:

- The measure is the **mean absolute deviation of the acceleration magnitude**
  over each second. Taking the magnitude removes the watch's orientation from
  the answer; taking the deviation about the mean removes gravity. What is left
  is how much the arm actually moved.
- Thresholds are **learned during the game**, not hard-coded, because the
  absolute numbers depend on the player, where the watch sits and how tight the
  strap is. The app tracks a slow estimate of your resting level and your
  working level and puts the boundary between them.
- A change is only believed once it **persists**: ten seconds to open a shift,
  fourteen to close one, with a dead band around the boundary so noise cannot
  make the state flap. Heart rate climbing, or GPS agreeing, shortens those to
  three and seven.
- **Entry takes ten seconds, not six, and that is the fix for extra shifts off
  the bench.** Moving a wrist while sitting down used to collect shifts nobody
  played, and it cannot be fixed by raising the motion threshold: those
  spurious shifts carry *higher* wrist motion than a defenceman gliding at the
  point does, so no amplitude cut separates them. Duration does. A fidget is a
  burst; a shift is not. Replayed against both recorded games, ten seconds
  removes two shifts on 2026-11-05 and one on 2026-11-03 — and **every one it
  removes is a shift whose own mean heart rate sits below the game baseline**,
  which is a player sitting down. Not one shift the heart rate supports is
  lost. Past ten it stops being selective. It costs no recorded ice time
  either, because the boundary is dated back by the length of the window that
  confirmed it; what it costs is four seconds of the screen still saying BENCH
  at the start of a shift heart rate has not yet agreed with.
- A shift is **refused outright** while heart rate sits 12 bpm or more below its
  own drifting baseline, whatever the motion says. This is the one place a
  signal other than motion overrules it, and it exists because a player sitting
  between periods and moving their arms is indistinguishable from a shift to an
  accelerometer alone.
- Because a boundary is confirmed late, it is **dated back** to when it actually
  happened. Without that, every shift would lose its first seconds to the bench
  and every bench spell its first seconds to the shift.

It will get some boundaries wrong. `BACK` — the lap key — flips the state by
hand when it does, and the menu offers the same correction in words.

The band the boundary sits in was fitted to a real game rather than guessed;
[docs/detector-tuning.md](docs/detector-tuning.md) records the method, the
numbers and what one game does not prove.

## Why on-ice heart rate is the point

In a simulated game of elite U20 players, average heart rate **on the ice** was
**84 ± 2 % of maximum**, peaking at **97 ± 2 %**.¹ Those are on-ice numbers: the
study reports no whole-game average, because once bench time is averaged in the
figure stops describing the skating and starts describing the proportion of the
night you spent sitting down.

That is the problem with a game average. It is a weighted blend of two states,
and the weighting is your bench time, not your effort. Two players who skated
identically can post different game averages purely because one got more rest.
A chest strap with no idea when you were on the ice cannot separate them.

This app knows when you were on the ice, so it reports both.

<sub>¹ Vigh-Larsen et al., "Muscle Metabolism and Fatigue during Simulated Ice
Hockey Match-Play in Elite Players", <i>Medicine & Science in Sports &
Exercise</i> 52(10):2162-2171, 2020. Thirty U20 national-team players, three
periods of eight one-minute shifts with two-minute recoveries - a fixed shift
structure, not a real game's ragged one.</sub>

## Stride rate

The watch can tell you how fast your legs are turning over, and it does not
need GPS to do it. Skating is periodic, and a periodic leg movement shows up in
the arm that counterbalances it, so the rhythm is in the accelerometer the
shift detector is already reading.

Finding it is an **autocorrelation**: take six seconds of acceleration
magnitude, subtract its mean, and compare the window against delayed copies of
itself. A lag where the signal lines up with its own past is a period, and the
best one is the stride. The search runs over lags of 7 to 27 samples, which at
the ~21 Hz the sensor actually delivers is 0.8 to 3.1 Hz, or **47 to 184 pushes
per minute** — wide enough for a glide and for a hard forecheck, narrow enough
that an arm swing at twice the rate cannot masquerade as one.

Three things keep it honest:

- **A band-pass first.** Two one-pole filters, fast minus slow, which is a
  cheap band-pass that removes gravity and the slow drift of a changing arm
  posture without an FIR's ring buffer of coefficients.
- **A confidence gate.** The peak has to reach 0.45 of the zero-lag energy. A
  real skating window scores 0.7 to 0.95; noise does not get near it.
- **A prominence gate.** The peak also has to stand 0.60 above the mean of the
  whole lag curve. This is the one that matters: a single hard impact in an
  otherwise quiet window scores 0.91 on confidence alone and reports a stride
  rate that was never skated. Measured across synthetic cases, real strides
  score 0.76 to 1.09 on prominence and a lone impact scores 0.47, so the gate
  sits between them and every false-positive case drops to zero accepted
  windows.

It also measures its own sample rate rather than assuming one. The app asks
the FR570 for 25 Hz and gets 25-sample batches every 1.171 s, which is 21.4 Hz
of wall clock — 32768/1536, a timer division, not a dropped-sample problem.
A hard-coded 25 would have reported every stride 17 % fast.

**Coverage is reported beside the average**, and it is the point. A stride rate
averaged over 80 % of your on-ice seconds is a different claim from one
averaged over 12 %, and no other hockey app tells you which you are looking at.
A second that fails either gate contributes nothing to the average and writes a
zero to the per-second trace — the app saying it looked and found no rhythm,
which is the truth during a glide, a faceoff or a scrum.

### Where the stride length comes from

Distance is pushes times stride length, and stride length is the one term a
wrist cannot measure. Speed is rate times length, so it has the same problem.

What makes this tractable is that **stride length is close to a constant for a
given skater.** Marino found skating velocity rises with stride *rate* while
stride length barely moves across speeds within one person; what separates a
fast skater from a slow one is length, but that difference is between people,
not between one person's shifts. So length is a calibration constant, needed
once, not a per-second measurement.

There are three ways to get it, and the app takes all three in this order:

1. **Your setting.** Set **Stride length** and that number wins. You measured
   it; the app only infers.
2. **GPS, on the days it can.** Whenever there is a fix *and* the stride meter
   has a rhythm in the same second, length is simply speed divided by rate —
   `speed × 6000 ÷ pushes-per-minute` centimetres. Seconds outside 100–600 cm
   are discarded as impossible, and a game contributes nothing unless at least
   thirty seconds agreed, so a stray fix by the arena door cannot overwrite a
   calibration built outdoors. What it learns is stored and reused for every
   later game, indoors included. Nothing is asked of you.
3. **Nothing.** Then the distance and speed fields are not created at all. The
   FIT carries no distance rather than a fabricated one.

This rink has never produced a fix — **0 of 5,011 records** — so for this
player route 2 may never fire. It costs nothing on the days it does not, and
it fires at an outdoor rink, on a pond, or in an arena with enough glass.

What the app will *not* do is seed a stride length from your height. A phone
pedometer's walking coefficient is about 0.4 × height; a skating push is
2.6–3.6 m. It would produce a confident number that is wrong by a quarter,
which is worse than the blank field.

A calibration always lands in the file as **Stride Length Used**, so a
distance in Connect carries the number it was built from.

The speed field is labelled **Speed While Striding** because its denominator
is the measured seconds and not your ice time: dividing by ice time would
quietly claim a speed for every second the app could not read.

### Skating intensity, which needs no calibration at all

`Skating Intensity` is mean on-ice wrist motion multiplied by mean stride
rate. Amplitude times cadence — the shape of a mechanical power term, which is
exactly why it is **left unitless**. Nothing here is calibrated in watts, and
dressing it up as though it were would be the same mistake as inventing a
stride length.

It is the one speed-like number that is always available: no GPS, no setting,
no calibration skate. Compare it with your own past games and with nobody
else's.

The two terms are averaged separately rather than multiplied second by second.
Multiplying first would send the whole index to zero on every second with no
readable rhythm, which would make it a measure of stride coverage wearing a
different name. Coverage is already reported on its own.

**What is not yet verified:** the gates were sized against synthetic signals
and a line-for-line Python port of the shipped code, not against a recording of
real skating. No published study has measured wrist accelerometry during
skating, so there is no reference to check against either. Stride Confidence
and Stride Lag are written to every record for exactly this reason — the first
real game recorded with it is what settles the thresholds.

## Heart rate recovery

Every other number this app produces measures how hard a game was. This one
measures how fit you are, which is not the same thing and is the only one that
should improve over a season.

It is the standard **HRR60**: heart rate at the moment a shift ends, minus
heart rate sixty seconds later, averaged over the game. Hockey gives it away
for free — a game is forty-odd repeats of exactly the protocol a lab uses, and
the app already knows the instant each one starts. A bench spell shorter than a
minute reports nothing rather than guessing at a partial drop.

Both ends are averaged over five seconds rather than read as single samples.
HRR60 is a difference between two numbers, so the several beats of jitter a
wrist optical sensor carries at 1 Hz land in the result at full size; five
samples cut that by better than half, and five seconds either side of the
minute mark is far shorter than the timescale the recovery curve itself moves
on. The clock that counts to sixty advances on every second that passes, not
only on the seconds the sensor managed to report — counting reported samples
would turn a ten-second dropout into a seventy-second "HRR60", a smaller
number for a reason that has nothing to do with fitness.

A negative result is kept, not floored at zero. A heart rate still climbing a
minute after a shift is a real reading about a player who is not recovering,
and averaging it in is what makes this a measurement rather than a highlight
reel. The field is a signed byte for that reason.

## Skating load

`Skating Load` is Catapult's PlayerLoad, computed on the accelerometer already
on your wrist: the running sum of `sqrt(dx² + dy² + dz²)` across consecutive
samples, in g, divided by 100. It accumulates only while the app judges you to
be on the ice, so a game spent mostly on the bench does not quietly inflate it.

Two honest limits. A wrist is not a torso — the professional units sit between
the shoulder blades, and a wrist sees stick work the trunk never does — so the
number is comparable with your own past games and with nobody else's. And a
difference measured across a paused timer is not a difference, so the running
sample is dropped whenever the accelerometer buffer breaks.

## Controls

Laid out the way Garmin's own activities are, so muscle memory from the stock
Run app transfers. Nothing here is needed during normal play.

| Button | Action |
|---|---|
| `START` / `STOP` | Start the game. **Press twice** to stop into the stop menu — resume, save, discard — exactly as stopping a run does. |
| `BACK` (`LAP`) | Line change. `BACK` is the lap key in every Garmin activity, and a lap here *is* a shift, so this is the button that corrects the detector when it has the state wrong. |
| `UP` / `DOWN` | Nothing. There is one data screen by design, so there is nothing to page through. |
| `MENU` (hold `UP`) | Correct the shift state, pause, end or discard the game. Only while a game is open. |

Two things follow from that, and both are deliberate departures from where this
app started:

- **`BACK` no longer ends the game.** On a Garmin watch `BACK` is never the exit
  during an activity, and a knock against the boards should not be able to end a
  game. Ending now goes through the stop menu: `START`, then *End & Save*.
- **`DOWN` does nothing.** It used to end the period, and a mis-press inside a
  glove could burn one. There are no periods now, so there is nothing to burn.
- **Pausing takes two presses.** The first buzzes twice and shows `PRESS AGAIN`
  without stopping anything, and lapses after five seconds if the second never
  comes.
- **The glass is ignored while a game is live.** This watch maps touch straight
  onto the same behaviours as the buttons — a tap arrives as `SELECT`, exactly
  like `START`, and a swipe right arrives as `BACK` — so a glove or a sleeve
  across the display used to stop the recording or fake a line change. A game on
  2026-11-03 lost seven minutes that way, in two pauses nobody meant to make.

  Touch is told apart from the buttons by what precedes it: a physical button
  raises a key event immediately before its behaviour, and the touchscreen
  raises none. While a game is running or paused, a behaviour that arrives
  without one is dropped. The menus are separate screens and still take touch
  normally, so this costs nothing once a menu is deliberately open.
- **Ending a game asks first.** *End & Save* is irreversible mid-game and the
  stop menu is where an accidental pause lands you, so it now confirms — as
  *Discard* always did.

## Wear it on your wrist

Shifts come from wrist motion, so the watch has to be on the arm. Carried in a
vest pocket or a bag it has nothing to detect: the detector never flips, and
the game records as one shift the length of the game. This comes up because
plenty of players wear a chest strap and stow the watch - the strap is fine and
is used for heart rate exactly as normal, but it cannot stand in for the one
signal the detection actually runs on.

## Start it at the faceoff, not in the warm-up

One press, at the opening faceoff. Starting it earlier and skating a warm-up
with the game already running is the largest single source of wrong shifts in
every game recorded so far, and it is the one fault here that costs nothing to
fix.

A warm-up looks like hockey to a wrist. Circling the zone, standing in a line
of shooters, leaning on a stick between reps - the motion sits in the same
range a defenceman's glide does, and the heart rate climbs into the same zone
a real shift does, so neither signal can rule it out afterwards. On 2026-11-05
the watch ran for seventeen minutes before the first shift of the game. Of the
nine detected shifts in that game whose heart rate never left zone 2 - the
ones the player's own body says were not shifts - **five fall in that opening
window and three more in the two minutes after the last real shift.** Eight of
the nine are time he was not in a game. The game on 2026-11-03, whose timer was
paused at every break, has almost none of them.

No setting fixes this. The detector can only compare a second against the
seconds around it, and a warm-up gives it nothing to object to. The press does
fix it.

## Settings

Editable in Garmin Connect; the defaults are a regulation game.

| Setting | Default | Range |
|---|---|---|
| Shift alert | 60 s | 15–600 |
| Shift sensitivity | Normal | Low / Normal / High |
| Shift alerts | on | |
| Lap per shift | on | |
| Use GPS | on | |
| End game when idle | 25 min | 0–180, 0 = never |
| Stride length | 0 cm (off) | 0–500 |
| Max heart rate | 0 (use profile) | 0, or 100–240 |
| Activity type | Ice Hockey | Ice Hockey / Ice Skate |

**Shift sensitivity** moves the decision boundary within the learned band. High
means less movement counts as being on the ice — raise it if shifts are being
missed, lower it if standing on the bench is being counted as a shift.

**Max heart rate** is what the *Time above 85 %* field is 85 % of. Left at 0 it
comes from your Garmin profile, which on most watches is 220-minus-age that
nobody has ever checked. That matters in one direction in particular: the app
raises its ceiling whenever a game beats it, so a profile that is too *low*
corrects itself within a shift — and a profile that is too *high* never
corrects at all, and quietly under-reports every hard minute you skate, for
good. Setting your real maximum is the only fix. A rate actually recorded
during a game still wins over both.

**End game when idle** saves a game nobody is playing any more. After this
many minutes with no skating detected the watch buzzes long-short-long and
shows a red *ENDING GAME* countdown; any button press cancels it and starts the
count again. Left alone for thirty seconds it **saves** the activity rather
than discarding it, because the premise of the app is that the watch is not
being touched, so silence has to mean keep the game.

Three things hold it back, and each is there because the alternative is ending
a game that is still being played:

- **A press has to be a press.** A swipe arrives as the same behaviour as a
  button on some devices, so cloth moving against the glass in a bag would
  otherwise reset the clock forever and the recording would run all night.
- **It stops while the accelerometer is unhealthy.** The detector holds its
  last state through a silent sensor rather than guessing, so reading that held
  state as stillness would turn a dead sensor into an ended game. No data is
  not the same as no movement.
- **It suspends while a menu is open**, because the countdown cannot be shown
  there and no press can reach it. Failing to end a game is recoverable;
  ending one silently is not.

This is not the period clock coming back. That ended a game on a *schedule*,
which knows nothing about whether play is still going, and it cut a recording
short mid-shift. This ends on *evidence that nothing is happening*. The
distinction is why the default is twenty-five minutes: an intermission is a
normal fifteen to eighteen minutes of sitting down, and the threshold has to
clear it comfortably or the old bug is back. Set 0 to turn it off.

**There is no period setting, and that is deliberate.** The app used to run
three twenty-minute periods and end the activity when the last one expired. It
did exactly that on 2026-11-03, at 3600.79 seconds of clock time — three
periods to the second — while the game was still being played, and the last
nine minutes of it were never recorded. The periods were a fiction regardless:
the app has no way to know the real game clock, which stops for whistles and
penalties and everything else the watch cannot see, so they drifted from the
game's within minutes. A game is now one continuous recording.

**Use GPS** is on because speed and distance are worth having when a fix exists.
Expect no fix inside most arenas; the app degrades quietly to motion-only
detection and records the game normally.

**Stride length** is the one number the app asks you for, and it is off by
default. See [Stride rate](#stride-rate) below for why there is no honest
default to fill in.

**Activity type** decides the FIT sport the finished game is filed under, and
it is a straight trade:

| | Garmin Connect | Strava |
|---|---|---|
| **Ice Hockey** (default) | Ice hockey | A plain *Workout* |
| **Ice Skate** | Ice skating | *Ice Skate* |

Strava has no ice hockey type and has said it has no plans to add one, so a
hockey-typed game arrives there untyped. Ice skating — FIT sport 33 — is the
closest thing Strava understands, and switching to it costs only the label in
Garmin Connect. Everything else, including every field below, is unaffected.
The setting is read when a game starts, so changing it never retypes an
activity that is already recording.

## What lands in Garmin Connect

The activity records as FIT sport `hockey`, sub-sport `ice`, with heart rate,
calories, time and — where there was a fix — GPS. On top of that:

| Field | Scope | Meaning |
|---|---|---|
| Shifts | session | Number of shifts |
| Ice Time | session | Total seconds on the ice |
| Bench Time | session | Total seconds on the bench |
| Avg Shift / Longest Shift | session | Shift lengths in seconds |
| Rest per Work | session | Bench seconds per ice second, to one decimal — `2.4` means nearly two and a half minutes of bench for every minute of ice |
| On-Ice Avg HR | session | Average heart rate over on-ice seconds only |
| Time above 85 % HR | session | Seconds above 85 % of max heart rate |
| HR Recovery (1 min) | session | How far the heart rate falls in the first minute on the bench, averaged over the game. The one number here that tracks conditioning rather than effort |
| Skating Load | session | Accumulated acceleration change while on the ice — the same construction the professional sides buy, on the accelerometer you already own |
| Shift Time / Bench Time | lap | One lap per shift and one per bench spell, so the Splits tab reads as a shift chart |
| Avg HR / Max HR | lap | The heart rate during each shift and each bench spell, beside its length. A 48-second shift means one thing at 150 and another at 188 |
| Avg Stride Rate | session | Mean skating rhythm over the seconds that produced one, in pushes per minute |
| Stride Coverage | session | What share of judged on-ice seconds produced a readable rhythm |
| Distance (estimated) | session | Only written once a stride length exists |
| Speed While Striding | session | Only written once a stride length exists |
| Stride Length Used | session | The number the distance was built from, so you can see which one it used |
| Skating Intensity | session | Mean wrist motion times mean stride rate. Unitless, and comparable only with your own past games |
| Stride Rate | record | The rhythm second by second; 0 means "looked, found none" |
| On Ice | record | 1 on the ice, 0 on the bench — a square wave against the heart rate trace |
| Shift Time (live) | record | The running shift clock |
| Wrist Motion | record | The raw signal the detector ran on, in milli-g |
| Detection Threshold | record | The learned boundary it was judged against |
| Stride Confidence / Stride Lag | record | Diagnostics: the autocorrelation peak and the lag that won it |

The motion and threshold rows are diagnostics, and deliberately **written but not charted**.
Garmin does not record wrist acceleration into a FIT file, so unless the app
writes it itself the signal the detector ran on is gone the moment the game
ends; plotted against each other they show every decision the app made and
why, which is what makes the thresholds tunable against real skating rather
than guesswork. But that is a use for the person tuning the detector, not for
the person who just played a game, and charting them put two unexplained
graphs labelled "mg" under every activity. They stay in the file, where
`tools/replay_detector.py` reads them; nobody has to scroll past them.

`Rest per Work` is a float. It was a UINT16 holding the ratio times 100 —
which is all an integer FIT field can carry — and Connect dutifully rendered a
3.2 ratio as the number `317`.

**Developer fields only render for games recorded by a build installed from
the store.** Not merely published — *installed*. The app has been live as
*Ice Hockey Shifts* since 4 November; the games that showed nothing were
recorded by a sideloaded `.prg`, which is a different thing entirely. Every FIT file carries a
`developer_data_id` message whose `application_id` is the UUID the **store**
assigned the listing — not the one in your manifest — and that is what Garmin
Connect joins its rendering metadata against; its own web API returns
`{"appID": …, "developerFieldNumber": …}` per value. A sideloaded build writes
sixteen zero bytes there instead, so Connect has nothing to match.

Confirmed end to end on the watch itself. `GARMIN/GarminDevice.xml` lists one
`<App>` per store-installed app with a `StoreId` and a `Version`; RinkPulse
appears as `036b4e61-…` version 39, and its recordings carry
`application_id 036b4e61-…`, `application_version 39` — with an October file
from before its last update carrying 38. This app has no entry in that file at
all, and every one of its recordings carries zeros and version 0.

Two consequences. A sideloaded game shows no Connect IQ section at all, which
is exactly what happens here while the rival app's fields render with names and
units on the same watch. And **games already recorded cannot be rescued** —
they carry an id that will never match a listing, whatever is published later.
The numbers are still in the files, and `tools/replay_detector.py` still reads
them.

`docs/store-2.4.0.md` has the full trace, including a way to confirm it over
USB in five minutes before spending a store submission.

### Heart rate zones per shift

There is one more thing in the file that neither the app nor Garmin Connect
shows you, and it was found by looking rather than by building: **the watch
writes a heart rate zone breakdown for every lap.** Every shift in this app is
a lap, so a per-shift zone split has been recorded on every game ever played
with it — fifty laps and fifty-one `time_in_zone` messages in the game this was
checked against, one per lap plus one for the session.

Connect records it and shows neither half: the Splits tab gives lap duration
and average heart rate, and the zone chart covers the whole activity.

```
tools/fit/shift-zones.py data/2026-11-03-game/2026-11-03-22-11-07.fit
tools/fit/shift-zones.py GAME.fit --all-laps --csv shifts.csv
```

It prints a zone table and a bar per shift, and then the number that exists
nowhere else — zone time **on the ice** against zone time **on the bench**:

```
            total        Z1      Z2      Z3      Z4      Z5
  Ice        9:46      1:10    0:51    2:46    4:16    0:43
  Bench     49:34      0:56   10:24   16:41   19:07    2:26
  Game      59:20      2:07   11:14   19:27   23:23    3:09
```

The Game row is Connect's zone chart. The two rows above it are the same
seconds split by where they were spent, which Connect cannot do because it does
not know which laps were shifts — this app wrote that onto every lap itself.

Two cautions, both printed by the tool. The ice row is a claim about the
detector as much as about the player: a missed line change moves seconds from
one row to the other and nothing in the file records that it happened. And the
per-lap breakdown is firmware behaviour, not something this app controls, so it
was confirmed on a Forerunner 570 and may differ elsewhere.

## Install

**From the Connect IQ Store** — the ordinary way, and the only way the developer
fields show up in Garmin Connect. Listed once Garmin's review completes.

**By sideloading** — every [release](../../releases) carries two files:

| File | What it is |
|---|---|
| `IndoorHockey.prg` | A single build for the Forerunner 570. Copy it to `GARMIN/APPS/` on the watch over USB and eject, or run `tools/watch.sh install IndoorHockey.prg`. |
| `IndoorHockey.iq` | The store package: the same app built for all 202 supported device variants. This is what gets uploaded to Garmin, not what gets copied to a watch. |

For any watch other than a Forerunner 570, build the `.prg` yourself —
`./build.sh <device>`, see [Build from source](#build-from-source). The `.iq` is
an archive, not something a watch can open.

The app then appears in the activity list. One thing to know before sideloading:
**developer fields only render in Garmin Connect for an app that came from the
store.** A sideloaded build writes shift and bench time into the FIT file
correctly, and Garmin Connect displays none of it. The on-watch summary and the
lap splits still work.

## Publishing

```bash
cd IndoorHockey
./package.sh               # builds dist/IndoorHockey.iq for every product
```

Upload that at <https://apps.garmin.com/en-US/developer/upload>; the dashboard
for an app already up is <https://apps-developer.garmin.com>. `store/listing.md`
holds the description, category and screenshot order to paste into the form,
and `docs/store-2.4.0.md` holds the current release's text with its character
counts, so it can be pasted without reading around it.

Launcher icons are generated, not hand-drawn, because the supported watches ask
for fifteen different sizes between 26x26 and 70x70:

```bash
python3 tools/make-launcher-icons.py   # after changing the device list
```

## Build from source

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) and
device files, which the Garmin SDK Manager downloads after you sign in with a
Garmin account.

```bash
cd IndoorHockey
./build.sh                 # Forerunner 570 42mm
./build.sh fenix847mm      # any installed device
./run-sim.sh               # build and run in the Connect IQ simulator
TYPECHECK=3 ./build.sh     # strict type checking
```

`./sync-products.sh` rewrites `<iq:products>` in `manifest.xml` to exactly the
devices installed locally that meet the app's `minApiLevel` — run it after
adding devices, before building a store package.

### Running the tooling on Ubuntu 24.04

The SDK Manager and the simulator both link `webkit2gtk-4.0` (libsoup2).
Ubuntu 24.04 ships only `webkit2gtk-4.1` (libsoup3), and loading both into one
process aborts with `libsoup2 symbols detected`. Symlinking 4.1 as 4.0 does not
work either.

`tools/sdkmanager-docker/` solves this with an Ubuntu 22.04 container that reads
and writes the real `~/.Garmin`, so downloaded device files land where `monkeyc`
expects them:

```bash
tools/sdkmanager-docker/run.sh             # SDK Manager GUI
tools/sdkmanager-docker/run-simulator.sh   # Connect IQ simulator
```

Both honour `$DISPLAY`, so they work over X11 forwarding or against a virtual
display on a headless box.

## Layout

```
IndoorHockey/
  manifest.xml         app id, device list, permissions
  monkey.jungle        build config
  build.sh             compile for one device
  package.sh           build the signed .iq for every supported device
  run-sim.sh           build + launch in the simulator
  sync-products.sh     regenerate the device list from what is installed
  source/
    IndoorHockeyApp.mc entry point, the 1 Hz game clock, settings reload
    GameModel.mc       clocks, shifts, heart rate stats, the FIT session
    ShiftDetector.mc   on-ice / on-bench detection
    StrideMeter.mc     skating rhythm by autocorrelation
    GameView.mc        the one screen, plus the post-game summary
    GameDelegate.mc    buttons
    GameMenu.mc        in-game menu
    Fmt.mc             time formatting
  resources/
    fitfields.xml      how the developer fields render in Garmin Connect
    strings/           every user-visible string
    settings/          properties and their Garmin Connect settings UI
    drawables/         launcher icon
tools/
  replay_detector.py   replay a recorded game through the detector offline
  sdkmanager-docker/   containerised SDK Manager + simulator
docs/
  screenshots/         simulator captures used above
  detector-tuning.md   how the detection band was fitted, and to what
```

### Design notes

All game state lives in `GameModel`; views read it and draw, holding none of
their own.

The 1 Hz game clock is owned by the **app**, not the view, so shift detection,
alerts and the per-second FIT fields keep running while a menu or a confirmation
is covering the screen.

The game clock is game time; **shift and bench time are wall time**. Recovery
happens during whistles too, so a bench spell that spans a stoppage really is
longer than the game clock says it is.

Clocks are "time already banked" plus "running since", measured with
`System.getTimer()`, so pausing and resuming cannot drift.

Text is never positioned in fixed pixels. Each line picks the largest font that
fits the **chord of the circle at that height** — on a round watch the usable
width near the top and bottom is far narrower than the diameter, which is what
makes naively-sized text spill off the edge.

Vibration patterns are deliberately long and at full strength. A short, gentle
buzz is perfectly clear on a bare wrist and completely undetectable under a
glove, an elbow pad and a jersey sleeve, which is where this app is.

## Licence

MIT — see [LICENSE](LICENSE).
