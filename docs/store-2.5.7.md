# Connect IQ Store — version 2.5.7, ready to paste

> **Upload 2.5.7, not 2.5.6.** 2.5.6 was built and tagged but never uploaded,
> so this supersedes it and the What's New below carries both releases. The
> live listing is still 2.5.5 (internal 7). Type `2.5.7` in the App Version
> box — nothing in the repo carries the store version, it is typed at upload.

**Why this one is urgent.** 2.5.5 is live and it pauses the game when a player
locks the watch, on all 34 products that have no LIGHT key. That is the app's
only 1-star review and it is a fair one. See
[release-2.5.7.md](release-2.5.7.md).

Verify the live state before and after with:

```
python3 tools/store-status.py
```

It reads the listing's own JSON with no login, diffs the Compatible Devices
list against the manifest, and diffs both text boxes against this file.

---

## Step 1 — the package

```
./IndoorHockey/package.sh
```

Produces `IndoorHockey.iq` for all 126 manifest products. The script builds
from a staging copy at a neutral path so the per-device `debug.xml` inside the
`.iq` carries no home directory, and it aborts if `$HOME` appears in the
unpacked archive.

## Step 2 — tick the six device part numbers Garmin dropped

**This is the one step that is easy to miss and costs real users.** The live
listing carries 202 part numbers; the package declares 208. The six missing
ones are devices your users cannot install on:

| part number | device |
|---|---|
| 006-B3324-00 | D2 Delta PX |
| 006-B3393-00 | Approach S62 |
| 006-B3700-00 | Approach S62 |
| 006-B3446-00 | vívoactive 3 |
| 006-B3473-00 | vívoactive 3 Music |
| 006-B3477-00 | vívoactive 3 Music |

So four products across six part numbers. Garmin's App Migration has silently
dropped devices from this listing before, which is why `store-status.py`
checks it on every release rather than trusting the form.

## Step 3 — paste BOTH boxes

Every release from 2.4.0 to 2.5.5 updated What's New and left the Description
alone, so the listing advertised none of stride rate, heart rate recovery or
skating load for five releases and kept a chest-strap claim 2.4.0 had
withdrawn. `store-status.py` now fails the build on that drift. **Paste both,
every time.**

## Step 4 — reply to the 1-star review

The dashboard lets you reply to a review, and the reply shows publicly under
it. Worth doing: he reported a real bug precisely, and the fix is in this
upload.

**Post it once 2.5.7 is approved and live**, not before — the reply says the
fix is out, and store approval takes a day or so.

```
You were right, and this was our bug rather than your watch.

On watches with no separate light button - Venu, Venu Sq, vivoactive,
Approach - holding the top button is how Garmin's own lock works, and this app
had made that same hold its pause. So locking the watch paused the recording,
which is exactly what you saw. Fixed in 2.5.7: pausing now only takes effect
when you let the button go, so the lock can't touch the game.

Sorry for the lost session, and thank you for the detail. "13 seconds" told us
exactly where to look. If you're on a Forerunner or a fenix, though, then this
was something else and we'd like to know which watch.
```

The last line is there because **the review never says which watch he has.**
The device class was inferred from the symptom, and the inference is strong,
but it is an inference. On a Forerunner or fenix the lock is a hold of LIGHT,
so this diagnosis would not apply and something else would be wrong.

---

## What's New

971 characters (977 if the form counts CRLF line endings). Paste verbatim.

```
Fixed: the app could pause itself when you locked your watch. On every Venu, Venu Sq, Venu X1, vivoactive, Approach and D2 Air, holding the top button is how Garmin's own lock works - and it was also how this app paused, so locking the watch stopped the recording. Pausing now takes effect when you LET GO of the button, and the screen tells you when you have held it long enough.

Changed: the watch is much quieter during a game. The buzz when a shift passes your target length is now off by default - at a 60-second target most defence shifts cross it. Turn it back on with "Shift alerts".

If your watch still sounds at every line change, that is the watch's own lap tone, not this app, and no Connect IQ app can silence it. Turn off Alert Tones and keep Vibration in your watch's sound settings: you keep the per-shift Splits chart and lose the noise.

New: bench heart rate recovery, shift fade, heart rate drift and stride consistency now appear in Garmin Connect.
```

**The order is deliberate.** The lock fix leads because it is the live bug and
the only 1-star the app has. The lap-tone paragraph stays in third place
because it is the one thing no app can fix, and a player who skips it will
think the update failed to quieten anything.

---

## Description

Unchanged from 2.5.6, byte for byte — 2.5.6 never shipped, so this text has
still never been published. 3888 characters (3978 with CRLF), against a 4,000 cap.

```
One press at the opening faceoff. After that the app works out when you are on
the ice and when you are on the bench. You never touch the watch again.

WHAT IT DOES

• Automatic shift detection — no button per line change. The app decides when
  you are skating and when you are resting, and splits the activity to match.
• One screen, everything at a glance, no paging mid-game.
• Shift clock — green, then amber, then red, and a buzz at your target length
  if you switch it on.
• Ends itself if you forget — after 25 minutes with no skating it saves
  rather than discards.
• Total ice time on screen all game.
• On-ice heart rate as its own number, not blended with the bench: in elite
  match play it averages 84% of maximum, a figure a game average hides.

HOW THE DETECTION WORKS

Wrist motion decides, because it is the only signal fast enough to open and
close a shift; GPS and heart rate only agree with it. One exception: while
heart rate sits well below its baseline, no amount of arm movement opens a
shift. That is a player sitting down. Thresholds are learned during the game,
and a change is believed only once it persists, then dated back to when it
happened, so a shift keeps its opening seconds.

It will get some boundaries wrong. The LAP button flips the state by hand.

WHAT LANDS IN GARMIN CONNECT

Shifts, ice time, bench time, average and longest shift, rest-per-work ratio,
on-ice average heart rate, time above 85% of maximum HR, average stride rate
with its coverage, heart rate recovery, skating load, skating intensity, bench
heart rate recovery, shift fade, heart rate drift and stride consistency. One
lap per shift and per bench spell, each with its own average and maximum heart
rate, so the Splits tab reads as a shift chart. Plus the on-ice state second
by second.

FITNESS, NOT JUST EFFORT

Heart rate recovery is the one number here that should improve over a season —
HRR60: your rate when a shift ends minus your rate sixty seconds later,
averaged over the game.

Skating load is the accumulated acceleration of your skating, on the ice
only.

Skating intensity is wrist motion times stride rate, needs no GPS and no
setting, and is unitless on purpose: compare it with your own past games.

STRIDE RATE

Skating rhythm in pushes per minute, with a coverage figure saying how much of
your ice time the game average rests on.

Distance and speed need a stride length, which nothing on a wrist can measure.
Set it yourself, or let the app work it out where GPS and your rhythm land in
the same second. Until it has one, those fields are left out, not invented.

BUTTONS

START begins the game. Hold it for a second to stop; a short press during a
game does nothing, and nor do screen taps.
BACK is the lap key: a lap here is a line change. Hold UP for the menu.

SETTINGS

Shift alert target, sensitivity and alerts on or off; lap per shift; GPS on or
off; how long with no skating before the game saves itself; stride length for
distance; your true maximum heart rate; and whether the activity is filed as
ice hockey or ice skating.

NOTES

Start the game at the opening faceoff, not during the warm-up. A warm-up skate
produces the same wrist motion and heart rate as a shift, so a game started
early collects shifts nobody played.

Wear the watch on your wrist: shifts and stride rate both come from wrist
motion, so a watch in a vest or a bag has nothing to detect. Heart rate is
whichever source the watch itself is using, so a paired chest strap just
works.

Your watch plays its own lap tone at each line change, because every shift is
a lap. No Connect IQ app can suppress that. Turn off Alert Tones and
keep Vibration to silence it without losing the Splits chart.

GPS is on by default; expect no fix inside most arenas. The app records
normally without one.

Strava has no ice hockey type: set Activity Type to Ice Skate if you sync
there.
```

### What changed from the 2.5.5 Description, and why

See [store-2.5.6.md](store-2.5.6.md), which rewrote it. Nothing has changed
since. **That description went over the cap twice while it was being written**
— 4,434 against 4,000, then 4,012 — so if the form rejects it, trim rather
than retyping from an older copy.

---

## Unchanged fields

Only re-enter these if the form has emptied them: name, category, preview
video, screenshots, support contact. The preview video is from the 2.0.0 build
and is still accurate — nothing it shows has changed.

## Still outstanding on the listing

- **The internal version ordinal is 7 while this is external 2.5.7.** 2.3.0
  was internal 4, so one of four uploads never became a store version. Worth a
  look at the dashboard's version list to see which.
- A store-installed build stamps the internal ordinal into every FIT file as
  `developer_data_id.application_version`, which is how `replay_detector.py`
  picks the right constants to replay a game at. After this upload the next
  game will carry 8, so `APPVER_NEW` in that tool stays correct (it tests
  `>= 7`).
- **Untested on the hardware that had the bug.** The fix is verified in the
  simulator on a Forerunner 570, which is not in the affected class. Whether
  hold-to-pause still works on a Venu depends on whether Garmin's
  hold-for-controls threshold is longer than 1,000 ms, and that cannot be
  measured without one of those watches.
