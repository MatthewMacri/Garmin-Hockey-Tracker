# Connect IQ Store listing

Copy-paste source for the submission form at
<https://apps.garmin.com/en-US/developer/upload>. The dashboard for an app that
is already up is <https://apps-developer.garmin.com>.

Upload `IndoorHockey/bin/IndoorHockey.iq`, built by `IndoorHockey/export.sh`.

---

## App name

Ice Hockey Shifts

## Type

Watch App · Health & Fitness

## Short description

Tracks a hockey game from your wrist without being touched. Works out every
shift and every spell on the bench by itself.

## Description

One press at the opening faceoff. After that the app runs the periods, runs the
intermissions, and works out when you are on the ice and when you are on the
bench on its own. You never touch the watch during a game.

WHAT IT DOES

• Automatic shift detection — no button per line change. The app decides when
  you are skating and when you are resting, and splits the activity to match.
• Period clock — 3 x 20 minutes by default. Ends itself at zero, runs a
  one-minute intermission, and starts the next period without being asked.
• Shift clock — green, then amber, then red as the shift runs long, with a
  long buzz at your target length so it is felt through a glove.
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

START/STOP starts the game and stops into the stop menu. BACK is the lap key,
and a lap here is a line change. Hold UP for the menu. Nothing is needed during
normal play.

SETTINGS

Periods per game, period length, intermission length, shift alert target, shift
sensitivity, lap per shift, count period up or down, GPS on or off, and whether
the activity is filed as ice hockey or as ice skating.

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
bench, periods, rink, skating

## Screenshots

In order, from `docs/screenshots/` (390x390 PNG):

1. `01-ready.png` — ready to start
2. `02-on-ice.png` — on the ice, shift clock green
3. `03-bench.png` — on the bench
4. `04-intermission.png` — intermission counting down
5. `05-menu.png` — the stop menu
6. `06-summary.png` — the post-game summary

## Support

Source and issues: https://github.com/MatthewMacri/Garmin-Hockey-Tracker

## Privacy

The app sends nothing anywhere. Everything it records goes into the activity
file on the watch, which syncs to Garmin Connect the way any activity does.
