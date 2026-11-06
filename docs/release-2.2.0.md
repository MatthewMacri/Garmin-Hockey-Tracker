# v2.2.0 — the detector was tuned for the wrong position

Released 2026-11-06.
<https://github.com/MatthewMacri/Garmin-Hockey-Tracker/releases/tag/v2.2.0>

The release notes as published, kept here so the repo carries its own history
rather than only GitHub's.

This is the first build to reach the Connect IQ store since 2.0.0: 2.1.0 was
tagged and released here and never uploaded, so everything in that release
ships with this one.

---

## The detector was fitted against the wrong player

The sensitivity band was tuned until the recorded ice share matched about a
third of the game. That is a forward's share, on three rolling lines. **This
app's only user plays defence**, and a defenceman's share is two spots over
however many defencemen dressed — 50% with two pairs, 40% with five, 33% only
with six. The target was wrong by a fifth, the band was tightened to reach it,
and the cost was paid in shifts that ended while the player was still on the
ice: a defenceman standing at the point produces less wrist motion than a
forward backchecking, drops under the bar, and loses the rest of the shift to
the bench.

Refitted against checks that do not need to know the bench size, and then
pinned by one game whose bench *is* known — five defencemen, which had to be
asked, because no FIT file records it:

| | was | is |
|---|---|---|
| Sensitivity band, normal | 0.27 | **0.18** |
| Seconds to confirm the bench | 10 | **14** |
| …with heart rate falling | 5 | **7** |
| Heart rate veto | — | **12 bpm under baseline** |

The veto is the only one a player will notice as a rule rather than as a
tendency: **while your heart rate sits 12 bpm or more below its own baseline
for the game, no amount of arm movement will open a shift.** That is a player
sitting down, not a player skating. It is the first time heart rate decides
anything in this app rather than merely agreeing.

Expect your numbers to differ from previous games. Replayed against the game
it was fitted to — five defencemen dressed, so a 40% share to hit, and the
same recorded accelerometer stream fed to both builds:

| | 2.1.0 | 2.2.0 |
|---|---|---|
| Ice share | 28.1% | **43.4%** |
| Shifts | 45 | **32** |
| Median shift | 17 s | **43 s** |
| Longest shift | 90 s | **229 s** |

Forty-five shifts with a seventeen-second median is not a defence pair's game;
it is one game's shifts cut into pieces. This is a replay rather than a second
recording — the same seconds through two detectors — so it shows what changed,
not how close either one is to the truth.

## What lands in Garmin Connect

**Rest per Work read as `317`** where it meant a ratio of 3.2. It was a UINT16
carrying the ratio times a hundred, which is all an integer FIT field can
carry. It is a float now, shown to one decimal place — and the field's label
still said `(x100)` right up until the store package was unpacked and read.

**The two diagnostic charts are gone.** Wrist motion and the learned detection
threshold are still written, every second, and `tools/replay_detector.py`
still reads them. They are simply no longer drawn under the activity: they are
what you need to tune a detector, and two unexplained graphs labelled `mg` to
anyone who just played a game.

## Start it at the faceoff, not in the warm-up

Free, no setting, and worth more than any constant in the table above. On the
game this release was fitted against, the watch ran for seventeen minutes
before the first shift; of the nine detected shifts whose heart rate never
left zone 2 — the ones the player's own body says were not shifts — five fall
in that opening window and three more in the two minutes after the last real
shift. **Eight of nine are time he was not in a game.**

Nothing in the recording separates them afterwards. A warm-up skate produces
the same wrist motion as a shift and reaches the same heart rate zone, so no
threshold and no heart-rate rule can refuse it. The press is the fix.

## Also in this release, from 2.1.0

A game left running no longer runs all night: after 25 minutes with no skating
the watch buzzes and counts down, any press calls it off, and left alone it
saves rather than discards. A watch delivering accelerometer samples in very
small batches could read as having no accelerometer at all, disabling shift
detection for a whole game. `tools/fit/shift-zones.py` reads heart rate zones
per shift out of a saved game — including zone time on the ice against zone
time on the bench, which Garmin Connect cannot produce because it does not
know which laps were shifts. Full notes in
[`docs/release-2.1.0.md`](release-2.1.0.md).

## Install

`IndoorHockey.iq` is the store package, all 202 device variants.
`IndoorHockey.prg` is a Forerunner 570 build for sideloading — copy it to
`GARMIN/Apps` on the watch over USB. Developer fields only render in Garmin
Connect for a store install; a sideloaded build writes them correctly and
displays them nowhere.

---

## What this release did not close

**The false positives have a proposed fix that is not implemented.** Make an
ice entry provisional until heart rate corroborates it, then backdate it when
it commits. Scored against the game it came from it removes all nine, which is
circular — it commits on the metric that defines them. Scored against a game
recorded by a different hockey app, whose own detector called 11 shifts, it
accepts 10 and **refuses one**, a 66-second shift peaking 3 bpm under the
line. That one-in-eleven puts the operating point at 140 bpm rather than the
144 the watch's zone table gives. It is agreement with a stranger's
implementation rather than with the player — an earlier draft of this called
that game hand-marked, which it is not.
It needs a third detector state and a backdate of up to 68 seconds through an
overlap guard that has never been asked to handle one. Not done on two games'
worth of evidence.

**The replay harness no longer reproduces either recording.** It was updated
to mirror the shipped constants, which means it now models a state machine no
file on disk was recorded by: agreement against the watch's own decisions fell
from 97-99% to 66-76%. The fix is known and verified — recover the
confirmation windows and the veto from the file the way the band already is,
which independently returns the constants each build actually shipped — and
is not in this release.

**Everything here rests on two games**, one of which has a confirmed bench
size. That is better than the one game 2.1.0's detector rested on, and it is
not much better. `docs/detector-tuning.md` carries the whole argument,
including the six claims made during this work that did not survive checking.
