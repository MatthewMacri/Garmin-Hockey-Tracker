# v2.5.5 — pause on a hold, because a press is what a glove makes

Released 2026-11-09. [2.5.4](release-2.5.4.md) answered a player's lost game by
narrowing the window an accidental pause could land in, from five seconds to
two, and said plainly that this narrowed the odds without closing them. This
release closes them.

---

## The problem with pressing twice

Any press-twice scheme is one a button rubbing inside a glove can satisfy. That
is how the game was lost: the player did not press twice on purpose, his glove
did it for him, and it kept doing it until the presses walked through the stop
menu into Discard.

Shortening the window helps in proportion and no more. The gesture itself has
to change.

**Pausing is now a one-second hold on `START`, and a short press during a game
does nothing at all** — which is exactly the event a glove produces. A hold
needs contact to be *made and maintained*, which a glove brushing past does
not do, and which a screen tap cannot do at all: a tap arrives as a behaviour
with no key event, and this path is driven entirely by key events.

One second is Garmin's own hold — the same gesture that opens the menu on `UP`
— so it is one players already have.

## Why the hold could not go where the press was

Measured, not assumed. Instrumenting the delegate and driving the simulator:

```
short press   down t=169868535   onSelect t=169868536   up t=169868609
2 s hold      down t=169872720   onSelect t=169872720   up t=169874730
```

`onSelect` fires on the key going **down**, about a millisecond after
`onKeyPressed` and long before the button comes back up. A 74 ms tap and a
2,010 ms hold arrive at it identically. Nothing in `onSelect` can tell them
apart, so the pause had to leave it entirely.

The delegate's own header had already recorded that `START` "produces
`onKeyPressed(KEY_ENTER)` immediately before `onSelect`" — it just never drew
this conclusion from it.

## How it works

A one-shot `Timer` is armed in `onKeyPressed` when `START` goes down during a
game, and cancelled in `onKeyReleased`. It fires at the threshold rather than
on release: holding a button and having nothing happen until you let go feels
broken, and Garmin's own holds fire at the threshold.

While the hold runs, the header shows `KEEP HOLDING` in yellow.

Gone with the old scheme: `requestPause()`, `isPauseArmed()`,
`pauseArmRemainingMs()`, `PAUSE_ARM_MS`, `PAUSE_MIN_GAP_MS`, `_pauseArmedAt`
and the `PRESS AGAIN` string.

## Verified

Every step by screenshot, in the simulator:

| action | result |
|---|---|
| five rapid presses on `START` — the glove-rub case | game still running |
| 600 ms hold — below the threshold | game still running |
| full hold | paused, stop menu open |
| during a hold | `KEEP HOLDING` shown, clock still running |

`docs/screenshots/04-press-again.png` is replaced by `04-keep-holding.png`,
captured from that run rather than redrawn.

## Size

```
ref               total       code       data of 98304
v2.5.4            32397      27192       5205    33.0%
v2.5.5            32273      27059       5214    32.8%
```

Smaller than the release before it: the arming machinery that came out was
larger than the timer that went in.

## What this closes

Everything from the 2026-11-09 field report, which was the first time anybody
used this app in a real game and said what happened:

- the lost game — Discard left the stop menu in 2.5.4, and the confirmation
  became a menu with the safe answer preselected;
- the thrashing on the bench — the minimum dwell went from 8 s to 20 s;
- the buzz with no off switch — `changeAlerts`, default off;
- **the accidental pausing** — this release.

## Still open

**The detector is tuned against two games, neither hand-counted.** 2.5.3
removed the heart-rate offset arm on measured grounds and 2.5.4 bounded the
thrash rate, but no recorded game has been checked against a human count of
shifts. That remains the largest unverified claim in the project.
