# v2.5.4 — the first field report

Released 2026-11-09. The first three releases this week corrected code that no
user had ever run. This one does not: a player installed the live store build,
used it for one game, lost that game, and went back to Garmin's native hockey
activity.

Everything he reported was right. Two of the three were already listed in
[feedback.md](feedback.md) as handled.

---

## He lost a game

> "The button press to start/stop the session is too sensitive. Every time the
> button got barely touched moving around in my glove it would pause the
> workout, and at one point it even pressed it enough times to end and discard
> the workout."

Two guards were supposed to prevent this, and both failed.

**Discard was on the stop menu.** That is the menu an accidental press chain
lands on — the source comment beside it said exactly that, in those words, and
offered Discard anyway. The two-press guard on STOP stops *one* stray press. It
does nothing about a button being rubbed, which produces two presses inside the
window every time. Discard is now reachable only from the menu raised by
**holding UP**, a gesture a glove against a button cannot make. Everything the
stop menu now offers either continues the game or saves it.

**The confirmation could not preselect "no".** `WatchUi.Confirmation` takes a
prompt and nothing else — SDK 9.3.0 has no `:defaultResponse` and no
`setDefaultResponse()` — so the app had to trust the firmware to highlight the
safe answer. In the simulator the prompt drew no highlight on either option and
a bare START press through it discarded the game. The source recorded this as
unresolved, pending a check on real hardware, and said that if the watch really
opens on yes then it "has to become a Menu2 with the safe item first".

This report is that check. It is now a `Menu2`, which opens on its first item
with the order under the app's control:

```
End game and save?
> No, keep playing          <- first, and highlighted
  Yes, end and save
```

Verified in the simulator: the highlight is on "No, keep playing", and
selecting it returns to the game with the clock and shift count intact.

**`PAUSE_ARM_MS` drops from 5000 ms to 2000 ms.** The old comment argued that a
wide window "costs very little in accidental pauses". This report falsifies
that: five seconds is a long time for a glove to be rubbing a button, and
anywhere inside it a second contact pauses the game.

## It thrashed on the bench

> "I was sitting on the bench and it was vibrating every ten seconds switching
> between on ice and bench while I was sitting there."

`MIN_SHIFT_SEC` and `MIN_BENCH_SEC` were both **8**, which makes a complete
on-ice → bench → on-ice cycle legal in sixteen seconds. His ten-second
oscillation was that budget being spent.

Both are now **20**. Swept through `tools/replay_detector.py` over the two full
recorded games:

| minimum | shifts (11-03 / 11-05) | ice share | median shift |
|---|---|---|---|
| 8 s | 20 / 28 | 43.7% / 38.4% | 80 s / 55 s |
| 20 s | 18 / 27 | 43.8% / 38.1% | 96 s / 49 s |
| 30 s | 18 / 25 | 44.9% / 37.9% | 96 s / 49 s |

The ice share moves by less than a point anywhere in that range, because real
shifts and real benches are far longer than any of these numbers. All these
constants bound is how fast the detector is allowed to change its mind, and
8 s was faster than hockey happens.

## The buzz had no off switch

> "The vibration when changing between bench and on ice is unnecessary and
> becomes an annoyance… I don't need to be alerted that I'm sitting on the
> bench. I already know I'm sitting down."

There was no setting for this. `shiftAlerts` gates the *long-shift* alert — the
buzz when one shift runs past `shiftSeconds` — and nothing at all gated the
on-ice/bench transition buzz. `feedback.md` claimed `shiftAlerts` "turns it off
entirely", which was never true; that row has been corrected.

New **`changeAlerts`** setting, **off by default**. Off is right for an app
whose whole claim is that you start it and forget it: the buzz reports
something the player can see by looking, and its only real use is noticing a
misdetection in time to correct it, which is a thing to opt into.

## Still open

**Accidental pausing is narrowed, not solved.** Any press-twice scheme is one a
rubbing button can satisfy; a shorter window only shortens the odds. The
guaranteed fix is hold-to-pause, which no stray contact can produce, at the
cost of the Garmin muscle memory the two-press binding was chosen for. That is
a product decision and has not been taken.

**The detector is still tuned against two games.** 2.5.3 removed the heart-rate
offset arm from corroboration on measured grounds, and this release bounds the
thrash rate, but neither has been checked against a hand count of real shifts.

## What this says about the process

Two of these three were listed as answered. One rested on a design argument —
`shiftAlerts` looked like it covered the buzz and nobody checked which alert it
gated. The other was marked in the source as unresolved pending a hardware
check that never happened.

That check arrived as somebody's lost game. `feedback.md` opens by warning that
an **Unverified** row is not a "yes"; this release is what it costs to forget
that.

## Verified

- `TYPECHECK=3` build clean for `fr57042mm`.
- Simulator: stop menu shows Resume and End & Save only, no Discard; the
  confirmation opens highlighted on "No, keep playing"; answering it returns
  to the paused game with the clock and shift count intact.
- `tools/replay_detector.py` still reproduces the watch's own seconds on both
  recorded games at each file's own era.
