# Connect IQ Store — version 2.1.0, ready to paste

Everything the upload form at <https://apps.garmin.com/en-US/developer/upload>
asks for that has changed since 2.0.0, in the order the form asks for it. The
full field-by-field reference lives in `store/listing.md`; this file exists so
the text can be copied without reading around it.

**Paste the description as well as What's New.** The live listing still carries
the heart rate claim that was corrected in `537d491` and has no wrist note, so
leaving the description alone ships a figure the cited paper never reported.

---

## Step 1 — the package

Attach `IndoorHockey/dist/IndoorHockey.iq`, built by `IndoorHockey/package.sh`.
All 202 device variants, signed, with no build paths in the 812 packaged files.

**App Version:** type `2.1.0`

Nothing in the build carries a version. `manifest.xml` has no version attribute
and the packaged `.iq` has none either — only `apiVersion`, `connectIqVersion`
and `minFirmwareVersion`, which are compatibility, not identity. The store
tells releases apart by that typed string alone, so bumping a version is an act
of typing and nothing in the repo will prompt it.

The hint under the box reads *(Latest app version: X)*. That is Garmin reading
back the last string submitted, and it is the quickest way to confirm an upload
landed. The public listing keeps showing the previous version until review
passes the new one.

---

## What's New

1,127 characters. Paste verbatim.

It was 931 before the two Connect-rendering fixes were added to the end.
No character limit for this field is documented anywhere I could find, so
the form's own counter is the authority: if it refuses this, drop the
closing paragraph about the two fixes first - it is the least important of
the three and the only one that is not about losing a game.

```
A game left running no longer runs all night. After 25 minutes with no
skating detected the watch buzzes and shows a countdown; any button press
calls it off, and left alone the game is saved rather than discarded. It
works on a paused game too, which is the likeliest way to forget one -
pause at the final whistle, put the gloves away, remember hours later.

It cannot end a game still being played. A single second on the ice
restarts the count, the default comfortably clears an intermission, and
the setting will not accept anything shorter than twenty minutes. If the
accelerometer stops delivering, the count stops with it rather than
reading a dead sensor as a player sitting still. Set it to 0 to turn the
whole thing off.

Also: a watch whose accelerometer delivered samples in very small batches
could read as having no accelerometer at all, which disabled shift
detection for the whole game. Those batches are now used.

Also in this version: Rest per Work reads as a ratio - 3.2 - instead of as
the number 317, and the detector's own motion diagnostics are still
recorded but no longer charted under your activity.
```

---

## Description

3864 characters of 4,000 (3,943 if the form counts CRLF line endings — it fits
either way). Paste verbatim.

```
One press at the opening faceoff. After that the app works out when you are on
the ice and when you are on the bench on its own, and keeps recording until you
stop it. You never touch the watch during a game.

WHAT IT DOES

• Automatic shift detection — no button per line change. The app decides when
  you are skating and when you are resting, and splits the activity to match.
• One continuous game clock — no periods to set up and nothing that ends your
  activity on a schedule. A real game runs longer than the sum of its periods,
  so the recording stops when you stop it and not before.
• Shift clock — green, then amber, then red as the shift runs long, with a
  long buzz at your target length so it is felt through a glove. The ring
  around the screen fills as the shift goes on, readable without reading it.
• Total ice time on screen all game, not just in the summary afterwards.
• On-ice heart rate, reported separately from bench heart rate.
• One screen. Everything at a glance, no paging mid-game.

WHY ON-ICE HEART RATE MATTERS

In a study of simulated elite match play, average heart rate on the ice was 84%
of maximum. A game average is a different number, because it blends skating
with sitting and the weighting is your bench time rather than your effort. Two
players who skated identically post different game averages when one got more
rest. This app knows when you were on the ice, so it reports both.

HOW THE DETECTION WORKS

Wrist motion is the only signal fast enough to open and close a shift, so it
decides, and GPS only agrees with it. Heart rate mostly only agrees too, with
one exception: while your heart rate is sitting well below its own baseline for
the game, no amount of arm movement will open a shift. That is a player sitting
down, not a player skating. Thresholds are learned during the
game rather than hard-coded, because the numbers depend on the player, where
the watch sits and how tight the strap is. A change is believed only once it
persists, and is then dated back to when it actually happened, so a shift does
not lose its first seconds to the bench.

It will get some boundaries wrong. The LAP button flips the state by hand when
it does.

WHAT LANDS IN GARMIN CONNECT

Shifts, ice time, bench time, average and longest shift, rest-per-work ratio,
on-ice average heart rate, and time above 85% of maximum heart rate. One lap
per shift and one per bench spell, so the Splits tab reads as a shift chart.
Per-second on-ice state, shift clock, wrist motion and the learned detection
threshold.

BUTTONS

START begins the game. Pressing it twice stops into the stop menu — twice,
because the screen is a touchscreen and one press was too easy to make by
accident inside a glove. The first press asks, the second does it. Screen taps
do nothing at all while a game is running. BACK is the lap key, and a lap here
is a line change. Hold UP for the menu. Nothing is needed during normal play.

SETTINGS

Shift alert target, shift sensitivity, shift alerts on or off, lap per shift,
GPS on or off, how long with no skating before the game saves itself, and
whether the activity is filed as ice hockey or as ice skating.

END GAME WHEN IDLE

A game left running does not run all night. After 25 minutes with no skating
detected the watch buzzes and shows a countdown; any button press cancels it,
and left alone it saves rather than discards. It cannot end a game still being
played: any second on the ice restarts the count, and the default clears a full
intermission. Set it to 0 to turn it off.

NOTES

Wear the watch on your wrist. Shifts come from wrist motion, so a watch in a
vest or a bag has nothing to detect and records one long shift. A paired chest
strap is fine and is used for heart rate as normal.

GPS is on by default, but expect no fix inside most arenas. The app degrades
quietly to motion-only detection and records the game normally.

Strava has no ice hockey activity type, so a hockey-typed game syncs there as a
plain workout. Set Activity Type to Ice Skate if you sync to Strava and would
rather it arrived typed.
```

---

## Unchanged fields

Only re-enter these if the form has emptied them.

| Field | Value |
|---|---|
| Title | `Ice Hockey Shifts` |
| Short description | See below |
| Category | Health & Fitness |
| Keywords | hockey, ice hockey, shifts, shift timer, line change, on-ice heart rate, bench, shifts, rink, skating |
| Preview Video | `https://youtu.be/LM8cZ_diB8s` |
| Source Code URL | `https://github.com/MatthewMacri/Garmin-Hockey-Tracker` |
| Collects user data / decodes ANT+ / regional limits | **No** to all three |
| App Migration | **Yes** |
| Monetization | **No** |

**Short description**

```
Tracks a hockey game from your wrist without being touched. Works out every
shift and every spell on the bench by itself.
```

---

## Still outstanding on the listing

**The screenshots.** The listing shows five images from the batch that was
wrong. The six corrected PNGs are in `docs/screenshots/`, 390x390, about 47 KB
each against a 150 KB limit. Upload them in filename order:

1. `01-ready.png` — ready to start
2. `02-on-ice.png` — on the ice, shift clock green
3. `03-bench.png` — on the bench
4. `04-press-again.png` — the first of the two presses needed to pause
5. `05-menu.png` — the stop menu
6. `06-summary.png` — the post-game summary

**Back up the signing key.** `~/.Garmin/ConnectIQ/keys/developer_key.der`.
Every future version has to be signed with that exact key. Lose it and the app
can never be updated again — only replaced by a new listing, with the install
count back at zero.
