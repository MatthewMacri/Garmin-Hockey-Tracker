# v2.1.0 — a forgotten game ends itself

Released 2026-11-05.
<https://github.com/MatthewMacri/Garmin-Hockey-Tracker/releases/tag/v2.1.0>

The release notes as published, kept here so the repo carries its own history
rather than only GitHub's.

---

A game left running no longer runs all night. This release is the answer to one
player's request — *"if it could sense when the game is over so I don't forget
about it for 4 hours that would be great"* — plus every defect found auditing
the code written to grant it.

## End game when idle

After **25 minutes with no skating detected**, the watch buzzes and shows a red
countdown. Any button press calls it off. Left alone it **saves** the game
rather than discarding it. Set `End game when idle` to 0 to turn it off.

It works on a paused game too, which is the likeliest way to forget one: pause
at the final whistle, put the gloves away, remember hours later.

**It cannot end a game still being played.** Four separate things guarantee it:

- A single second on the ice restarts the count.
- The default comfortably clears an intermission, and the setting now refuses
  anything shorter than twenty minutes — ten was accepted before, and ten
  minutes auto-saves during every intermission.
- If the accelerometer stops delivering, the count **stops with it**. A held
  detector state is an absence of evidence, not a player standing still —
  reading it as stillness would have saved a game mid-shift twenty-five
  minutes after a sensor died.
- Nothing happens while a menu covers the screen, because the countdown cannot
  be seen or cancelled from there.

## Fixed

**A watch could read as having no accelerometer at all.** Any sensor batch
under four samples was discarded, and discarded batches count as silence. A
device delivering samples in twos would have registered as a dead
accelerometer for an entire game: the sensor-failure buzz firing, shift
detection frozen in one state from the opening faceoff, and the whole game
recorded as a single enormous shift — on hardware that was working perfectly.
Short batches are now carried to the next callback and used.

**The pause question could survive a cancelled auto-end.** The red countdown
draws over `PRESS AGAIN`, so a player who armed a pause and then got the
warning could not see the pause was still live. The press that dismissed the
warning was swallowed, the header reverted to `PRESS AGAIN`, and the screen was
then asking for a press that would pause the game.

**The countdown could freeze at 30 and save anyway**, if the watch's
millisecond clock wrapped while the warning was up. The screen and the decision
now agree.

## New, off the watch

`tools/fit/shift-zones.py` reads **heart rate zones per shift** out of a saved
game. This was not built so much as found: every shift in this app is a lap,
and the watch firmware writes a zone breakdown for every lap — fifty laps and
fifty-one of those messages in the game it was checked against. That data has
been recorded on every game ever played with this app, and nothing read it.

It also prints the one number that exists nowhere else — zone time **on the
ice** against zone time **on the bench**. Garmin Connect cannot produce that,
because it does not know which laps were shifts.

```
            total        Z1      Z2      Z3      Z4      Z5
  Ice        9:46      1:10    0:51    2:46    4:16    0:43
  Bench     49:34      0:56   10:24   16:41   19:07    2:26
  Game      59:20      2:07   11:14   19:27   23:23    3:09
```

The Game row is Connect's zone chart. The two above it are the same seconds,
split by where they were spent.

## Also

`tools/sim-button.sh` had BACK and DOWN in the wrong place — far enough off to
land on bezel rather than on a button. They did nothing, silently, which means
every menu interaction ever "verified in the simulator" through those two
buttons was verified against a press that never happened.

## Install

`IndoorHockey.iq` is the store package, all 202 device variants. `IndoorHockey.prg`
is a Forerunner 570 build for sideloading — copy it to `GARMIN/Apps` on the
watch over USB. Developer fields only render in Garmin Connect for a store
install; a sideloaded build writes them correctly and displays them nowhere.

---

## What this release did not close

**A paused game with the stop menu still open does not auto-end.** Pausing with
START pushes the stop menu, and the countdown deliberately freezes while a menu
covers the screen — it cannot be seen or cancelled from there, and saving a game
out from under an open menu is worse than failing to save one.

So the covered paths are:

| Path | Covered |
|---|---|
| Game left **running** on the bench | Yes — the common case, and the one the request described |
| Paused, menu dismissed, on the game screen | Yes, as of this release |
| Paused with the stop menu left open | **No.** Bounded only by `saveIfRecording()` on app exit |

Closing it would mean either acting invisibly under a menu, which was rejected
for good reason, or popping the menu from the model to raise a visible
countdown, which risks popping a view the model knows nothing about. Neither is
worth doing speculatively. Tracked on
[#1](https://github.com/MatthewMacri/Garmin-Hockey-Tracker/issues/1).

## Open afterwards

| | |
|---|---|
| [#2](https://github.com/MatthewMacri/Garmin-Hockey-Tracker/issues/2) | Chest strap — the app never calls `Sensor.setEnabledSensors()`, and the only decoded recording was wrist HR |
| [#3](https://github.com/MatthewMacri/Garmin-Hockey-Tracker/issues/3) | Intensity minutes — no field to point at; needs one game and ten minutes in Connect |
| [#4](https://github.com/MatthewMacri/Garmin-Hockey-Tracker/issues/4) | Goalie mode — needs a goalie's raw accelerometer data before it can be designed |
| [#5](https://github.com/MatthewMacri/Garmin-Hockey-Tracker/issues/5) | Scorekeeping — conflicts with hands-free; post-game entry is the only part worth building |
| [#6](https://github.com/MatthewMacri/Garmin-Hockey-Tracker/issues/6) | Per-shift zones **on the watch** — the off-watch script shipped here |

Both #2 and #3 are answered by playing one game and looking at Garmin Connect
afterwards, which is worth more than any amount of reasoning from the SDK
documentation.
