# Connect IQ Store — version 2.5.6, ready to paste

> **Upload 2.5.6.** The live listing is 2.5.5 (internal 7), approved, 100
> downloads, 5.0 from one review. Rebuild with `./IndoorHockey/package.sh` and
> type `2.5.6` in the App Version box — nothing in the repo carries the store
> version, it is typed at upload.

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

---

## What's New

898 characters (914 if the form counts CRLF line endings). Paste verbatim.

```
Changed: the watch is far quieter during a game. The buzz when a shift passes
your target length is now OFF by default - at a 60-second target most defence
shifts cross it, so it was alerting you to something completely normal. Turn
it back on with "Shift alerts" if you are deliberately holding shifts to a
length.

If your watch still sounds at every line change, that is the watch's own lap
tone, not this app, and no Connect IQ app can silence it. Turn off Alert Tones
and keep Vibration in your watch's sound settings: you keep the per-shift
Splits chart and lose the noise.

New: four numbers the app was already recording now actually appear in Garmin
Connect - bench heart rate recovery, shift fade, heart rate drift and stride
consistency. They were being written into every activity correctly and shown
nowhere.

Fixed: heart rate drift is now labelled bpm/min, which is what it measures.
```

**The order is deliberate.** The noise change comes first because it is the
complaint that arrived three times, and because the second paragraph is the
part no app can fix — a player who does not read it will think the app is
still beeping at them after the update. The four new fields come second: they
are a real gain, but nobody noticed they were missing.

---

## Description

3888 characters of 4,000 (3978 if the form counts CRLF line endings — it
fits either way, with 22 characters to spare on the CRLF count). Paste verbatim.

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

1. **The target-length buzz is described as opt-in**, because it now is. The
   old text promised "a long buzz at your target length" unconditionally.
2. **The four fields that now render are listed** — bench heart rate
   recovery, shift fade, heart rate drift, stride consistency. They were
   written into every activity from 2.5.6's code and declared nowhere, so
   Garmin Connect had nothing to render them from.
3. **The chest-strap sentence is no longer a withdrawal.** It now states what
   the code does: `GameModel.mc:2710` reads
   `Activity.getActivityInfo().currentHeartRate`, and the only sensor the app
   registers for is the accelerometer, so heart rate is whatever source the
   watch is using. That is a statement about the code, deliberately not a
   claim about measured accuracy with a strap — no game has been recorded
   with one yet.
4. **The watch's own lap tone is explained**, because it is the commonest
   complaint and it is not the app's doing. Every shift is a lap, the firmware
   sounds at every lap, and `Session.addLap()` takes no arguments and has no
   suppression API.

**This description went over the cap twice.** 4,434 against 4,000 once, and
again while this file was being written: carrying 2.5.5's text forward with
the four edits above came to 4,351 on the CRLF count. It was cut back by
trimming the detection and stride paragraphs, which also removed the listing's
most over-claimed passage — stride rate accepted 6 of 1,995 on-ice seconds in
the 2026-11-09 game, so a whole section describing it was not earned. Every
count in this file is produced by script and re-counted after any edit.

---

## Unchanged fields

Only re-enter these if the form has emptied them: name, category, preview
video, screenshots, support contact. The preview video is from the 2.0.0 build
and is still accurate — nothing it shows has changed.

## Still outstanding on the listing

- **The internal version ordinal is 7 while this is external 2.5.6.** 2.3.0
  was internal 4, so one of four uploads never became a store version. Worth a
  look at the dashboard's version list to see which.
- A store-installed build stamps the internal ordinal into every FIT file as
  `developer_data_id.application_version`, which is how `replay_detector.py`
  picks the right constants to replay a game at. After this upload, the next
  game will carry 8, so `APPVER_NEW` in that tool stays correct (it tests
  `>= 7`).
