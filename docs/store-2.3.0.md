# Connect IQ Store — version 2.3.0, ready to paste

Everything the upload form at <https://apps.garmin.com/en-US/developer/upload>
asks for that has changed since the live listing, in the order the form asks
for it. The full field-by-field reference lives in `store/listing.md`; this
file exists so the text can be copied without reading around it.

**Nothing appears to be live on the store**, and the only way to be certain is
the dashboard. Garmin Connect renders none of this app's developer fields on a
recorded game while rendering another store app's fields on the same watch,
which is the behaviour of an app the store does not know, and the app's own
recordings carry an `application_id` of sixteen zero bytes where a
store-installed app carries a real one. Whatever became of the 2.0.0 upload —
the one that showed `Status: Verified` beside `Signature check failed` — it
does not look like it ended in a listing. **Check the dashboard before
assuming this is an update rather than a first publish**, because the form
differs.

An earlier draft of this file argued from a 404 on
<https://apps.garmin.com/en-US/apps/d979409c-45c9-41b6-a1ec-092f51bd6006>, the
manifest's application id. **That argument was wrong and is withdrawn.** The
store assigns its own UUID to a listing, and it is not the manifest id.
RinkPulse proves it on this very watch: `GarminDevice.xml` lists it with
`StoreId` `036b4e61-…` and `AppId` `c46ee819-…`, and only `036b4e61-…` returns
200 from the store API — `c46ee819-…` 404s exactly as ours does. So a 404 on a
manifest id is the normal state of affairs, published or not, and it proves
nothing either way.

2.1.0 and 2.2.0 were tagged and released on GitHub and never uploaded either,
so this upload carries everything since 2.0.0 and the What's New below covers
all three releases. The version is 2.3.0 rather than 2.2.0 because `v2.2.0` is
already a published GitHub tag pointing at the code *before* stride rate
existed; reusing the number would have put a different app behind it on the
store than the one behind it on GitHub, which is the mistake 2.1.0 made.

**Paste the description as well as What's New.** The live listing still carries
the heart rate claim that was corrected in `537d491`, has no wrist note and no
warm-up note, and describes a detector that no longer behaves that way.

---

## Why nothing renders today, and what publishing can and cannot fix

**Developer fields only render in Garmin Connect for an app the store knows
about.** A sideloaded build writes every field correctly and Connect displays
none of them — which is exactly what the 2026-11-05 activity shows: no Connect
IQ section at all, while a game recorded on the same watch with a
store-published hockey app shows its own fields with names and units.

The mechanism is now traced rather than guessed. Every FIT file carries a
`developer_data_id` message whose `application_id` is, in Garmin's own words,
a *"16-byte identifier for the developer"* used to *"uniquely identify
developer data field sources"* ([FIT Protocol](https://developer.garmin.com/fit/protocol/),
Table 9). Connect's web backend joins on exactly that: its splits API returns
`"connectIQMeasurement": [{"appID": "…", "developerFieldNumber": 0, …}]` per
value. Decoding our own recordings — and the simulator's — shows
`application_id` written as **sixteen zero bytes**, with `application_version`
0, where a store-installed app writes its real UUID and the store's internal
version counter. (Checked against the store API: Ice Hockey Tracker's FIT says
version 54 and its listing says `latestInternalVersion` 54.)

Two consequences, and the first one is the unwelcome one:

- **The games already in Connect cannot be made to render by publishing.**
  They carry an app id of all zeros. There is no listing with that id and
  never will be. The numbers are not lost — they are intact in the FIT files
  and `tools/replay_detector.py` still reads them — but the activity pages for
  the games recorded so far will stay bare. Only games recorded after a store
  install will render.
- **The fields have to be complete before the first upload.** Connect stores
  the listing's fit-contributions metadata when the app is first uploaded;
  fields added to the XML afterwards are not reliably picked up. This is the
  reason the stride fields (ids 14–20) went in now rather than in a later
  release.

### Confirm the diagnosis for free, before spending a submission

Plug the FR570 in over USB and read `GARMIN/GARMINDEVICE.XML`. The device keeps
one `<App>` entry per store-installed app, each with an `<AppId>` UUID and an
integer `<Version>` — the same two values that land in `developer_data_id`.
Sideloaded PRGs get no entry at all. Expect to find entries for Ice Hockey
Tracker and RinkPulse, and **no entry for
`D979409C-45C9-41B6-A1EC-092F51BD6006`**. That confirms the whole chain in five
minutes.

One caveat on the above: no Garmin document or staff post states in writing
that a sideload writes a zero `application_id`. The decode is ours, the FIT
spec and the Connect API shape are official, and a developer who re-uploaded
the identical sideloaded app as a Beta reported the fields appearing
immediately afterwards ([thread 299371](https://forums.garmin.com/developer/connect-iq/f/discussion/299371/sideloaded-datafield-app-doesn-t-seem-to-save-fit-contributor-fields-to-fit-file)).
Everything converges; the single sentence does not exist in Garmin's docs.

### A Beta proves rendering, but its games are throwaway

A Beta upload does get fields rendering and skips public review, so it is the
cheap way to prove the pipeline end to end. The catch is in Garmin's own
[Beta Apps](https://developer.garmin.com/connect-iq/core-topics/beta-apps)
instructions: a Beta requires **an alternate app id in the manifest**, created
with a UUID generator. So a Beta can never share an id with the real listing,
and every game recorded against it carries the throwaway id — those activities
will not render once the Beta is gone, any more than the sideloaded ones do.

So use a Beta to answer "does it render and does Rest per Work read `3.2`
rather than `324`", and not for a game worth keeping:

1. Copy the manifest to a scratch branch, replace the application id with a
   fresh UUID, and build the `.iq` from that. Do not commit it.
2. Upload it as a Beta.
3. **Delete the sideloaded copy from the watch first** — `GARMIN/Apps/IndoorHockey.prg`
   over USB. A sideload and a store install share the manifest ID, and having
   both is a known source of confusion about which one is running.
4. Install the Beta from <https://apps.garmin.com> in a desktop browser while
   signed in. Beta apps do not appear in the Connect IQ mobile app's search;
   the website, or Garmin Express, is how they reach the watch.
5. Record anything — two minutes of waving an arm around is enough — and sync.
   Then decode the file: `developer_data_id` should carry a real UUID and a
   non-zero version, which is the proof the install path is right.
6. The activity should carry a Connect IQ section reading Shifts, Ice Time,
   Bench Time, Avg Shift, Longest Shift, Rest per Work, On-Ice Avg HR, Time
   above 85% HR, Avg Stride Rate and Stride Coverage.
7. Then publish publicly under the real manifest id, uninstall the Beta, and
   record the games you actually want to keep against the published app. Note
   that the id landing in those FIT files will be the UUID the **store**
   assigns the listing, not `d979409c-…`; read it out of the first file, or
   out of `GarminDevice.xml`, rather than assuming it.

If the Beta renders nothing, the problem is the listing's fit contributions,
not the app: the labels and units Connect draws come from
`IndoorHockey/resources/fitfields.xml` as packaged into each device's
`-fit_contributions.json` inside the `.iq`, not from the FIT file.

---

## Step 1 — the package

Attach `IndoorHockey/dist/IndoorHockey.iq`, built by `IndoorHockey/package.sh`.
All 202 device variants, signed, with no build paths in the 812 packaged files.

**App Version:** type `2.3.0`

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

998 characters (1013 if the form counts CRLF line endings). Paste verbatim.

```
New: stride rate. The app now reads your skating rhythm off the wrist, in
pushes per minute, second by second and as a game average - with a coverage
figure saying how much of your ice time it rests on. Distance and speed
stay off until you set a stride length yourself: nothing on a wrist can
measure one, and the alternative is inventing it.

Shift detection has been retuned, and you will see it in your numbers.
The old settings were fitted against a forward's share of the ice, and a
defenceman gliding at the point kept dropping under the bar and losing the
rest of the shift to the bench. A shift is now harder to leave than to
enter, and your heart rate can refuse one outright: while it sits well below
its baseline for the game, no amount of arm movement will open a shift.

A game left running no longer runs all night. After 25 minutes with no
skating the watch buzzes and counts down; any press calls it off, and left
alone the game is saved, not discarded. Set it to 0 to turn it off.
```

No character limit for this field is documented anywhere I could find, and the
form's own counter is the authority. This is written to land just under 1,000
in case that is the cap. **If the form accepts more**, append this — the
warm-up note is the only part of the release that asks anything of the player:

```
One thing that costs nothing: start the game at the opening faceoff rather
than in the warm-up. A warm-up skate produces the same wrist motion and the
same heart rate as a shift does, so a game started early collects shifts
nobody played.

Also fixed: Rest per Work reads as a ratio, 3.2, rather than as the number
317; and a watch delivering accelerometer samples in very small batches could
read as having no accelerometer at all, disabling shift detection for a whole
game.
```

With the tail it is 1476 characters (1500 with CRLF).

---

## Description

3893 characters of 4,000 (3976 if the form counts CRLF line endings — it fits
either way). Paste verbatim.

```
One press at the opening faceoff. After that the app works out when you are on
the ice and when you are on the bench on its own. You never touch the watch
during a game.

WHAT IT DOES

• Automatic shift detection — no button per line change. The app decides when
  you are skating and when you are resting, and splits the activity to match.
• One continuous game clock — no periods to set up and nothing that ends your
  activity on a schedule. Recording stops when you stop it.
• Shift clock — green, then amber, then red as the shift runs long, with a
  long buzz at your target length so it is felt through a glove.
• Ends itself if you forget — after 25 minutes with no skating the watch
  counts down and saves rather than discards. Any press cancels it.
• Total ice time on screen all game, not just in the summary.
• On-ice heart rate, reported separately from bench heart rate.
• One screen. Everything at a glance, no paging mid-game.

WHY ON-ICE HEART RATE MATTERS

In simulated elite match play, average heart rate on the ice was 84% of
maximum. A game average blends skating with sitting, so two players who skated
identically post different averages when one rested more. This app knows when
you were on the ice, so it reports both.

HOW THE DETECTION WORKS

Wrist motion is the only signal fast enough to open and close a shift, so it
decides and GPS only agrees with it. Heart rate mostly agrees too, with one
exception: while it sits well below its own baseline for the game, no amount of
arm movement will open a shift. That is a player sitting down, not a player
skating. Thresholds are learned during the game, because they depend on the
player and on how the watch is worn, and a change is believed only once it
persists, then dated back to when it happened.

It will get some boundaries wrong. The LAP button flips the state by hand.

WHAT LANDS IN GARMIN CONNECT

Shifts, ice time, bench time, average and longest shift, rest-per-work ratio,
on-ice average heart rate, time above 85% of maximum HR, and average stride
rate with its coverage. One lap per shift and one per bench spell, so the
Splits tab reads as a shift chart, and the on-ice state second by second.

STRIDE RATE

The app measures your skating rhythm from the wrist, in pushes per minute,
second by second and as a game average — with stride coverage beside it, the
share of your on-ice seconds that produced a readable rhythm, so you can see
how much of the game the average rests on.

Distance and speed stay off unless you ask. There is no published stride
length for skating, nothing on a wrist can measure one, and GPS cannot
calibrate it indoors. Set Stride Length yourself and the app estimates both;
leave it at 0 and it reports rhythm alone rather than inventing a distance.

BUTTONS

START begins the game. Pressing it twice stops into the stop menu — twice,
because one press was too easy to make inside a glove on a touchscreen. Screen
taps do nothing while a game is running.
BACK is the lap key: a lap here is a line change. Hold UP for the menu.

SETTINGS

Shift alert target, sensitivity and alerts on or off; lap per shift; GPS on or
off; how long with no skating before the game saves itself; stride length for
distance; and whether the activity is filed as ice hockey or ice skating.

NOTES

Start the game at the opening faceoff, not during the warm-up. A warm-up skate
produces the same wrist motion and heart rate as a shift, so a game started
early collects shifts nobody played.

Wear the watch on your wrist. Shifts and stride rate both come from wrist
motion, so a watch in a vest or a bag has nothing to detect. A paired chest
strap is fine and is used for heart rate as normal.

GPS is on by default, but expect no fix inside most arenas; the app falls back
to motion alone and records normally.

Strava has no ice hockey type: set Activity Type to Ice Skate if you sync
there.
```

It was over the limit before this release: 4,434 characters once the warm-up
note went in, against a cap of 4,000, and the file claimed 3,864. The claim
had gone stale — text was added twice without re-counting. It is counted here
by script rather than by eye, and the margin is 24 characters on the CRLF
count. Adding the stride section cost 462 characters and paid for them by
tightening six paragraphs that were saying the same thing twice.

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
