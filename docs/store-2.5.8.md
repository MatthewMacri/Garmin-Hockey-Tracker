# Connect IQ Store — version 2.5.8, ready to paste

> **The live listing is 2.5.7 (internal 8), approved 2026-11-11.** Type
> `2.5.8` in the App Version box — nothing in the repo carries the store
> version, it is typed at upload.

Engineering notes: [release-2.5.8.md](release-2.5.8.md).

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

Produces `IndoorHockey.iq` for all 126 manifest products, from a staging copy
at a neutral path so the per-device `debug.xml` carries no home directory. It
aborts if `$HOME` appears in the unpacked archive.

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

**The Description has now missed six consecutive uploads.** It was rewritten
for 2.5.6, carried unchanged through 2.5.7, and the live listing still shows
the 2.5.5 text (3,864 characters against this repo's 3,888). `store-status.py`
reports it every time and it has been skipped every time. It is the second box
on the form; it does not paste itself.

## Step 4 — check the internal version ordinal

`tools/replay_detector.py` now carries `APPVER_V258 = 9`, the store internal
version it expects 2.5.8 to land on, and it uses that to decide which dwell
constants to replay a recorded game against. 2.5.7 is internal 8, so 9 is the
expectation — but two uploads in this app's history never became store
versions at all, so **read the ordinal off the dashboard after approval** and
correct the constant if it is anything other than 9. Getting it wrong replays
every future game against a floor the watch is no longer running, silently.

---

## What's New

905 characters (911 if the form counts CRLF line endings). Paste verbatim.

```
Fixed: short shifts were being reported as 20 seconds when they were shorter. The detector had a 20-second minimum that quietly rounded them up - in one recorded game that was 6 shifts out of 26. The minimum for a shift is now 12 seconds, so shift lengths and the Splits chart show what actually happened. Ice time barely moves.

Fixed: heart rate drift was labelled bpm/min when the number is a total in bpm. A reading of 19 means 19 bpm of drift across the whole game, not 19 every minute.

Changed: stride rate, estimated distance and estimated speed are now withheld unless enough of the game was actually measured, rather than being published off a handful of seconds.

If your watch buzzes at every line change, that is the watch's own lap alert and no Connect IQ app can silence it. Turn off "Lap per shift" in this app's settings to stop it - your shift times and ice time are recorded either way.
```

**The order is deliberate.** The shift-length fix leads because it changes
numbers people have already looked at — anyone who read a 20-second shift in
the Splits tab was reading the floor, not their shift. The lap-alert paragraph
is last but is the one that answers the most-repeated complaint about this
app, and it is the only one of the four that no release can fix in code.

---

## Description

Unchanged since 2.5.6, byte for byte, and **still never published**.
3888 characters (3978 with CRLF), against a 4,000 cap.

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

### What changed, and why

See [store-2.5.6.md](store-2.5.6.md), which rewrote it. Nothing has changed
since. It went over the cap twice while being written — 4,434 then 4,012 — so
if the form rejects it, trim rather than retyping from an older copy.

---

## Unchanged fields

Only re-enter these if the form has emptied them: name, category, preview
video, screenshots, support contact. The preview video is from the 2.0.0 build
and nothing it shows has changed.

## Still outstanding on the listing

- **Six device part numbers remain dropped** — see Step 2. This has now been
  true across several uploads.
- **Untested on the devices that had the 2.5.7 lock bug.** Nobody here owns
  one of the 34 products without a LIGHT key.
