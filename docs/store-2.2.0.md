# Connect IQ Store — version 2.2.0, ready to paste

Everything the upload form at <https://apps.garmin.com/en-US/developer/upload>
asks for that has changed since the live listing, in the order the form asks
for it. The full field-by-field reference lives in `store/listing.md`; this
file exists so the text can be copied without reading around it.

**Nothing is live on the store.** The public listing for this app's UUID,
<https://apps.garmin.com/en-US/apps/d979409c-45c9-41b6-a1ec-092f51bd6006>,
returns 404, where a published app's UUID returns its page; and Garmin Connect
renders none of this app's developer fields on a recorded game while rendering
another store app's fields on the same watch, which is the behaviour of an app
the store does not know. Whatever became of the 2.0.0 upload — the one that
showed `Status: Verified` beside `Signature check failed` — it did not end in
a listing. **Check the dashboard before assuming this is an update rather than
a first publish**, because the form differs.

2.1.0 was tagged and released on GitHub and never uploaded either, so this
upload carries everything since 2.0.0 and the What's New below covers both
releases. That is also why the version jumps: the package built
from this repo is two code commits ahead of the `v2.1.0` tag, and calling it
2.1.0 would have put a different app behind that number on the store than the
one behind it on GitHub.

**Paste the description as well as What's New.** The live listing still carries
the heart rate claim that was corrected in `537d491`, has no wrist note and no
warm-up note, and describes a detector that no longer behaves that way.

---

## Step 1 — the package

Attach `IndoorHockey/dist/IndoorHockey.iq`, built by `IndoorHockey/package.sh`.
All 202 device variants, signed, with no build paths in the 812 packaged files.

**App Version:** type `2.2.0`

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

996 characters (1013 if the form counts CRLF line endings). Paste verbatim.

```
Shift detection has been retuned, and you will see it in your own numbers.
The old settings were fitted against a forward's share of the ice, and a
defenceman gliding at the point kept dropping under the bar and losing the
rest of the shift to the bench. A shift is now harder to leave than it is
to enter, and your heart rate can refuse one outright: while it sits well
below its own baseline for the game, no amount of arm movement will open a
shift.

A game left running no longer runs all night. After 25 minutes with no
skating the watch buzzes and counts down; any press calls it off, and left
alone the game is saved rather than discarded. A second on the ice restarts
the count, so it cannot end a game still being played. Set it to 0 to turn
it off.

Also fixed: a watch delivering accelerometer samples in very small batches
could read as having no accelerometer at all, disabling shift detection for
a whole game. And Rest per Work reads as a ratio, 3.2, rather than as the
number 317.
```

No character limit for this field is documented anywhere I could find, and the
form's own counter is the authority. This is written to land just under 1,000
in case that is the cap. **If the form accepts more**, append this — it is the
most useful thing in the release and the only part that asks anything of the
player:

```
One thing that costs nothing: start the game at the opening faceoff rather
than in the warm-up. A warm-up skate produces the same wrist motion and the
same heart rate as a shift does, so a game started early collects shifts
nobody played.
```

With the tail it is 1236 characters (1258 with CRLF).

---

## Description

3840 characters of 4,000 (3920 if the form counts CRLF line endings — it fits
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
  so recording stops when you stop it.
• Shift clock — green, then amber, then red as the shift runs long, with a
  long buzz at your target length so it is felt through a glove. The ring
  around the screen fills as the shift goes on.
• Total ice time on screen all game, not just in the summary.
• On-ice heart rate, reported separately from bench heart rate.
• One screen. Everything at a glance, no paging mid-game.

WHY ON-ICE HEART RATE MATTERS

In simulated elite match play, average heart rate on the ice was 84% of
maximum. A game average is a different number: it blends skating with
sitting, so its weighting is your bench time rather than your effort, and two
players who skated identically post different averages when one rested more.
This app knows when you were on the ice, so it reports both.

HOW THE DETECTION WORKS

Wrist motion is the only signal fast enough to open and close a shift, so it
decides, and GPS only agrees with it. Heart rate mostly only agrees too, with
one exception: while your heart rate sits well below its own baseline for the
game, no amount of arm movement will open a shift. That is a player sitting
down, not a player skating. Thresholds are learned during the game, because
they depend on the player and on how the watch is worn. A change is believed only once it persists, and is then dated back to
when it happened, so a shift does not lose its opening seconds.

It will get some boundaries wrong. The LAP button flips the state by hand.

WHAT LANDS IN GARMIN CONNECT

Shifts, ice time, bench time, average and longest shift, rest-per-work ratio,
on-ice average heart rate, and time above 85% of maximum HR. One lap
per shift and one per bench spell, so the Splits tab reads as a shift chart,
and the on-ice state second by second.

BUTTONS

START begins the game. Pressing it twice stops into the stop menu; twice,
because this is a touchscreen and one press was too easy to make inside a
glove. Screen taps do nothing at all while a game is running.
BACK is the lap key: a lap here is a line change. Hold UP for the menu.

SETTINGS

Shift alert target, sensitivity and alerts on or off; lap per shift; GPS on or
off; how long with no skating before the game saves itself; and whether the
activity is filed as ice hockey or ice skating.

END GAME WHEN IDLE

A game left running does not run all night. After 25 minutes with no skating
the watch buzzes and counts down; any press cancels it, and left alone it saves
rather than discards. A second on the ice restarts the count, so it cannot end
a game being played. Set it to 0 to turn it off.

NOTES

Start the game at the opening faceoff, not during the warm-up. A warm-up skate
produces the same wrist motion and the same heart rate as a shift, so a game
started early collects shifts nobody played, and nothing in the recording can
tell them apart.

Wear the watch on your wrist. Shifts come from wrist motion, so a watch in a
vest or a bag has nothing to detect and records one long shift. A paired chest
strap is fine and is used for heart rate as normal.

GPS is on by default, but expect no fix inside most arenas; the app falls back
to motion-only detection and records normally.

Strava has no ice hockey type: set Activity Type to Ice Skate if you sync there
and would rather it arrived typed.
```

It was over the limit before this release: 4,434 characters once the warm-up
note went in, against a cap of 4,000, and the file claimed 3,864. The claim
had gone stale — text was added twice without re-counting. It is counted here
by script rather than by eye, and the margin is 80 characters.

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

**The preview video** is from the 2.0.0 build and still accurate: nothing it
shows has changed. Leave it.

**Back up the signing key.** `~/.Garmin/ConnectIQ/keys/developer_key.der`.
Every future version has to be signed with that exact key; lose it and this
listing can never be updated again, only replaced, with the install count back
at zero. It is the only thing in this whole process that cannot be redone.
