# v2.5.7 — the pause and the lock were the same gesture

Released 2026-11-11. [2.5.5](release-2.5.5.md) made pausing a one-second hold
on `START`, because a press is what a glove makes. It closed the accidental
pause. It also, on a quarter of the devices this app ships to, bound the pause
to the button Garmin already uses for locking the watch.

A player found that out before we did.

---

## The review

The first 1-star the app has had, left on 2026-11-10 against 2.5.5:

> i started the recording, locked the watch, it simply stopped after 13
> seconds and did not resume. weird app.

Every word of that is accurate, and the fault is entirely ours.

## What actually happened

On **34 of this app's 126 products there is no `LIGHT` key.** Reading the key
sets straight out of each device's `simulator.json`:

| keys the device has | products | how you reach the controls menu |
|---|---:|---|
| `up` `down` `enter` `esc` `menu` | 92 | hold `LIGHT` |
| `enter` `esc` `menu` | 24 | **hold the top button** |
| `enter` `esc` | 6 | **hold the top button** |
| `enter` | 4 | **hold the top button** |

The 34 are every Venu, Venu Sq, Venu X1, vívoactive, Approach and D2 Air.
Garmin's own manual for them says it plainly: *"From any screen, hold [the top
button] to view the controls menu"*, and the lock lives in that menu. There is
no other way to lock those watches.

**The top button is `KEY_ENTER`.** So on those 34 products, from 2.5.5 onward,
locking the watch and pausing the game were the same gesture — and 2.5.5
paused at the *threshold*, a second in, while the button was still down. The
app paused itself, pushed the stop menu, and the controls menu the player was
actually opening covered it. They locked the watch and put it away. The
recording never moved again.

Thirteen seconds is how long it took him to reach for the lock.

## Why the simulator never caught it

Two reasons, and both are worth writing down because they will recur.

The simulator has no controls menu and no lock, so the gesture does not exist
there to be tested. And the development watch is a **Forerunner 570**, which
is in the 92 — it has a `LIGHT` key, so its lock is somewhere else entirely
and its `START` hold is free. Every test that mattered was run on the one
device class that cannot show the bug.

## The fix

**The pause now happens when the button comes back UP, not at the threshold.**

That is a straight reversal of 2.5.5, which put it at the threshold on the
grounds that "holding a button and having nothing happen until you let go
feels broken." That reasoning was about feel. It lost to a lost game.

The mechanism is the point. When the controls menu opens over the app, the key
release is delivered to the overlay and **never reaches `GameDelegate`**. So:

- pause at the threshold → the system steals the release → **the game pauses**
- pause on release → the system steals the release → **nothing happens**

Those are the only two failure modes available, and only one of them loses
somebody's game. On a watch its owner has just deliberately locked and put
away, "kept recording" is the only acceptable way for this to fail.

Three changes carry it:

1. The hold is timed in `GameModel` (`beginPauseHold` / `endPauseHold`)
   rather than by a `Timer` in `GameDelegate`. Nothing is scheduled, so
   nothing can fire unattended.
2. `GameDelegate.onKeyReleased` is now the only place a hold becomes a pause,
   and only for `KEY_ENTER`. Any other key coming up mid-hold drops it.
3. `GameView.onHide` calls `cancelPauseHold()`. Losing the screen mid-hold is
   the signature of the controls menu opening — belt and braces beside the
   release rule, so a stolen hold is dropped on the spot instead of sitting
   armed until some later, unrelated key comes up.

The hint gets a second stage so the gesture still reads as deliberate:
`KEEP HOLDING` until the threshold, then **`LET GO TO PAUSE`**. That is what
answers 2.5.5's objection — the screen now tells you the pause is ready and
that letting go is what takes it, so nothing about it feels broken.

## Verified

Every step by screenshot, in the simulator, on `fr57042mm`.

| action | 2.5.5 and 2.5.6 | 2.5.7 |
|---|---|---|
| hold `START` 1.6 s, **not released** | paused at 1.0 s | running, `LET GO TO PAUSE` |
| hold `START` 4.6 s, **not released** | stop menu, clock frozen | running, clock 0:07 → **0:10** |
| release after a full hold | — | paused, stop menu, `Resume` preselected |
| five rapid short presses | running | running |

The second row is the whole bug and the whole fix. The shipped build sits in
the stop menu with the button still held down; the new one is still counting.

The glove-safety property 2.5.5 was built for is intact: a short press during a
game does nothing, and a touchscreen tap still cannot reach the pause at all,
because the path is driven entirely by key events.

## What this does to the affected devices

Honestly: it depends on a threshold that cannot be measured from here.

If Garmin's hold-for-controls is **longer** than our 1,000 ms — which the
`LET GO TO PAUSE` hint now makes usable, since it tells you exactly when to
release — hold-to-pause keeps working on all 34 and the accidental pause is
gone. If it is **shorter or equal**, the system wins every time and those
players have no hold-to-pause at all.

In that case 24 of the 34 still have a complete fallback: they have a `menu`
key, so holding the bottom button opens the in-game menu, which carries both
**Pause** and **End Game**. The remaining 10 — `venu441mm`, `venu445mm`,
`venux1`, `vivoactive6`, `approachs7243mm`, `approachs7247mm` and the four
`vivoactive3` variants — have no menu key, and on those a running game may
have no user-reachable pause or stop at all. That is a pre-existing hole this
release does not close; it is filed, not fixed.

This is the thing to check on real hardware, and it needs one of those
watches. Nobody here has one.

## Size

```
ref               total       code       data of 98304
v2.5.5            32273      27059       5214    32.8%
v2.5.6            34513      29029       5484    35.1%
v2.5.7            34981      29414       5567    35.6%
```

468 bytes for the fix, against the 98,304 ceiling on `instinct2`.

## Also found, not fixed

`TYPECHECK=3 ./build.sh vivoactive3` fails on five sport constants —
`SPORT_ICE_SKATING`, `SPORT_HOCKEY`, `SPORT_TRAINING`, `SUB_SPORT_GENERIC`,
`SUB_SPORT_ICE` — that the device does not support. Confirmed pre-existing by
building the `v2.5.6` tag, which fails identically. It builds and ships fine
at the default typecheck level, so this is a strictness gap rather than a
broken binary, but a device that supports none of the app's sport types is
worth looking at on its own.

## Still open

Unchanged from [2.5.5](release-2.5.5.md), and still the largest unverified
claim in the project: **the detector is tuned against games nobody
hand-counted.** No recorded game has been checked against a human count of
shifts.

Newly open, and the lesson of this release: **126 products, one test device,
and a device class whose basic interaction model differs from it.** The key
sets are readable from the SDK — the table at the top of this file was
generated from them — so the next question to ask of any input change is which
of those four groups it was designed against.
