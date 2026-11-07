# Connect IQ Store listing

Field-by-field answers for the upload form at
<https://apps.garmin.com/en-US/developer/upload>. The dashboard for an app
already up is <https://apps-developer.garmin.com>.

**Step 1** — attach `IndoorHockey/dist/IndoorHockey.iq`, built by
`IndoorHockey/package.sh`.

Build it with that script and nothing else. It stages the source to a neutral
path first, because a plain `-e` build writes the absolute path of every source
file into a debug record for all 202 device variants - about 180,000 copies of
the builder's home directory, shipped inside the package.

Step 1 also asks for **App Version**, a free text box. Type the version there -
`2.2.0`, then `2.3.0`, and so on.

**Nothing in the build carries the version.** `manifest.xml` has no version
attribute and never has; the packaged `.iq` has none either, only `apiVersion`,
`connectIqVersion` and `minFirmwareVersion`, which are SDK and device
compatibility. The store tells releases apart by that typed string alone, so
bumping a version is an act of typing and nothing in the repo will prompt it.

The hint under the box reads *(Latest app version: X)* - that is Garmin reading
back the last string submitted, and it is the quickest way to confirm an upload
landed. The public listing keeps showing the previous version, and its
`Internal:` counter, until review passes the new one, so neither of those tells
you anything while a release is queued.

**Step 2** — the fields below.

| Form field | What to put |
|---|---|
| Title | `Ice Hockey Shifts` (17 of 50 chars) |
| Description | The block under *Description* below (2,825 of 4,000 chars) |
| What's New | See below. This is an **update**: the dashboard shows *Ice Hockey Shifts* live at 2.1.0 (Internal: 3) since 2026-11-04. A 404 on the manifest's application id means nothing — the store assigns a listing its own UUID |
| Hero Image (optional) | `store/images/hero-1440x720.jpg` (1440x720, 75 KB of 2048 KB) |
| Category | Health & Fitness — then the closest subcategory to hockey or winter sports |
| Does your app collect user data? | **No** — it sends nothing anywhere |
| Does your app decode/encode ANT+ profiles? | **No** |
| Does your app have regional limits? | **No** |
| Cover Image (500x500) | `store/images/cover-500x500.png` (46 KB of 300 KB) |
| Add icons for app store on device? | **No** — optional, and the launcher icon already covers every device |
| Screen Images | The six PNGs in `docs/screenshots/`, in filename order (390x390, ~47 KB each, limit 150 KB) |
| Preview Video | `https://youtu.be/LM8cZ_diB8s` |
| Email Address | Shown publicly, so use an address you are happy to publish rather than your personal one |
| Source Code URL | `https://github.com/MatthewMacri/Garmin-Hockey-Tracker` |
| Review Notification | **Yes** |
| App Migration | **Yes** — lets the store add new watches as Garmin releases them, which is the point of building for every product |
| Monetization | **No** |
| iOS / Android companion app | Leave blank |
| Additional hardware | Leave blank |

### On "Signature check failed"

The panel showing `Status: Verified` alongside `Signature check failed` on a
first upload is a known report against Garmin's own checker. The usual cause of
a genuine failure is a key mismatch between versions of an app that is already
published, which cannot apply to a first upload. The key here is a 4096-bit RSA
private key in PKCS#8 DER, which is what Connect IQ requires.

**Back up `~/.Garmin/ConnectIQ/keys/developer_key.der` somewhere safe.** Every
future version of this app has to be signed with that exact key. Lose it and
the app can never be updated again - only replaced by a new listing, with the
install count back at zero.

---

## App name

Ice Hockey Shifts

## Type

Watch App · Health & Fitness

## Short description

Tracks a hockey game from your wrist without being touched. Works out every
shift and every spell on the bench by itself.

## Description

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

## Category

Health & Fitness

## Keywords

hockey, ice hockey, shifts, shift timer, line change, on-ice heart rate,
bench, shifts, rink, skating

## What's New (version 2.2.0)

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

If the form's counter accepts more than the ~1,000 characters above,
append this; `docs/store-2.5.0.md` carries both with exact counts.

```
One thing that costs nothing: start the game at the opening faceoff rather
than in the warm-up. A warm-up skate produces the same wrist motion and the
same heart rate as a shift does, so a game started early collects shifts
nobody played.
```

## Screenshots

In order, from `docs/screenshots/` (390x390 PNG):

1. `01-ready.png` — ready to start
2. `02-on-ice.png` — on the ice, shift clock green
3. `03-bench.png` — on the bench
4. `04-press-again.png` — the first of the two presses needed to pause
5. `05-menu.png` — the stop menu
6. `06-summary.png` — the post-game summary

## Support

Source and issues: https://github.com/MatthewMacri/Garmin-Hockey-Tracker

## Privacy

The app sends nothing anywhere. Everything it records goes into the activity
file on the watch, which syncs to Garmin Connect the way any activity does.

---

## Preview Video

Uploaded, unlisted: **https://youtu.be/LM8cZ_diB8s**

Recorded from the 2.0.0 build. It replaces `youtu.be/b-NZduxCrtI`, which showed
the period clock (`P1/3`) this version removes - that clip advertised the exact
behaviour that cut a game short, so it must not go back in the form.

The form accepts YouTube and Vimeo links only, so a file hosted anywhere else
cannot go in that field. The source files are kept here for re-uploading.

| File | Use |
|---|---|
| `store/video/demo-1080p.mp4` | 1920x1080, for YouTube and the store's Preview Video field |
| `store/video/demo-square-780.mp4` | 780x780, the watch screen alone, for the web |
| `store/video/poster-1080p.jpg` | Thumbnail |

Re-record all four, including the README GIF, with `tools/record-demo.sh`. It
needs the simulator already running on the current build and sitting on READY.

A real recording of the app in the Connect IQ simulator, with the waiting sped
up: the game starting, ice and bench alternating, the two presses that pause,
the stop menu, the confirmation, and the saved summary. Everything with a
button press in it runs at 2x so it stays readable; play runs at 4x.

Two things about the simulator, neither of which is a fault in the app:

Heart rate reads a constant 162 because the simulator has no heart rate sensor.

The shifts are driven by the lap key rather than detected. The app reads raw
accelerometer samples and the simulator delivers a flat zero, so there is no
wrist motion to detect; left alone the detector correctly decides the player is
sitting down and backdates every shift away, and the summary reads Ice 0:00.
The lap key is a real feature - it is how a player corrects a boundary the
detector got wrong - so the recording uses it to produce the shift boundaries
the simulator cannot. No number on screen is invented; the clocks, totals and
summary are all the app's own arithmetic.
