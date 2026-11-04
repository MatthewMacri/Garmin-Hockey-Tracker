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

**Step 2** — the fields below.

| Form field | What to put |
|---|---|
| Title | `Ice Hockey Shifts` (17 of 50 chars) |
| Description | The block under *Description* below (2,825 of 4,000 chars) |
| What's New | See below — this is an update, not the first release |
| Hero Image (optional) | `store/images/hero-1440x720.jpg` (1440x720, 75 KB of 2048 KB) |
| Category | Health & Fitness — then the closest subcategory to hockey or winter sports |
| Does your app collect user data? | **No** — it sends nothing anywhere |
| Does your app decode/encode ANT+ profiles? | **No** |
| Does your app have regional limits? | **No** |
| Cover Image (500x500) | `store/images/cover-500x500.png` (46 KB of 300 KB) |
| Add icons for app store on device? | **No** — optional, and the launcher icon already covers every device |
| Screen Images | The six PNGs in `docs/screenshots/`, in filename order (390x390, ~47 KB each, limit 150 KB) |
| Preview Video | `https://youtu.be/b-NZduxCrtI` |
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
  so the recording stops when you stop it and not before.
• Shift clock — green, then amber, then red as the shift runs long, with a
  long buzz at your target length so it is felt through a glove. The ring
  around the screen fills as the shift goes on, readable without reading it.
• Total ice time on screen all game, not just in the summary afterwards.
• On-ice heart rate, reported separately from bench heart rate.
• One screen. Everything at a glance, no paging mid-game.

WHY ON-ICE HEART RATE MATTERS

Measured on the same players in the same game, average heart rate came out at
76% of maximum over the whole game, and 84% counting only the seconds actually
on the ice — a 21-point difference produced by nothing but the averaging
window. A game average is diluted by every minute spent on the bench. This app
knows when you were on the ice, so it reports both.

HOW THE DETECTION WORKS

Wrist motion is the only signal fast enough to open and close a shift, so it
decides; heart rate and GPS only corroborate. Thresholds are learned during the
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
GPS on or off, and whether the activity is filed as ice hockey or as ice
skating.

NOTES

GPS is on by default, but expect no fix inside most arenas. The app degrades
quietly to motion-only detection and records the game normally.

Strava has no ice hockey activity type, so a hockey-typed game syncs there as a
plain workout. Set Activity Type to Ice Skate if you sync to Strava and would
rather it arrived typed.

## Category

Health & Fitness

## Keywords

hockey, ice hockey, shifts, shift timer, line change, on-ice heart rate,
bench, shifts, rink, skating

## What's New (version 2.0.0)

```
A game is now one continuous recording. The period and intermission clock
is gone, along with the settings for it - the activity runs until you stop
it, however long that takes. The previous version ended a game by itself at
the end of the third period, which cut a recording short mid-play.

Pausing now takes two presses, and the touchscreen is ignored while a game
is running: a tap arrived as the same button behaviour as START, so a glove
on the glass could stop the recording. Ending a game asks for confirmation.

A pause no longer counts toward the shift and bench clocks, which could
record a whole intermission as a single enormous shift.

The shift detector has been retuned against a recorded game, and the shift
ring on the watch face now tracks the current shift against the target.
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

Uploaded: **https://youtu.be/b-NZduxCrtI**

The form accepts YouTube and Vimeo links only, so a file hosted anywhere else
cannot go in that field. The source files are kept here for re-uploading.

| File | Use |
|---|---|
| `store/video/demo-1080p.mp4` | 1920x1080, for YouTube and the store's Preview Video field |
| `store/video/demo-square-780.mp4` | 780x780, the watch screen alone, for the web |
| `store/video/poster-1080p.jpg` | Thumbnail |

Both are a real recording of the app in the Connect IQ simulator, sped up 2x:
the game starting, the shift clock running, the state flipping between ice and
bench, the stop menu, and the saved summary. Heart rate reads `--` because the
simulator has no heart rate sensor.

One thing was changed for the recording and changed back afterwards: the red
`NO MOTION DATA` warning was suppressed. The simulator has no accelerometer,
so that warning is on screen permanently there and never appears on a watch
that works. Nothing else was altered and no number was invented.
