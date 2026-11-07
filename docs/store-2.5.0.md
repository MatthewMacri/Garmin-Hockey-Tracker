# Connect IQ Store — version 2.5.0, ready to paste

Everything the upload form at <https://apps.garmin.com/en-US/developer/upload>
asks for that has changed since the live listing, in the order the form asks
for it. The full field-by-field reference lives in `store/listing.md`; this
file exists so the text can be copied without reading around it.

**This is an update, not a first publish.** *Ice Hockey Shifts* by KernelOPs
has been live since 4 November 2026, with 100+ downloads and one five-star
review — left against 2.0.0, so that upload reached the public despite showing
`Status: Verified` beside `Signature check failed`. 2.3.0 went up on
7 November as the fourth upload; this is the fifth.

**2.4.0 was tagged and never uploaded.** It exists on GitHub as a release and
nowhere else, so this upload carries both it and 2.5.0, and What's New below
covers the two together. Nothing is lost by skipping it on the store — the
store numbers releases by the string typed into the form, and no user ever saw
2.4.0.

Earlier drafts of this file said the opposite, at length, and were wrong on
every count: that nothing was live, that 2.0.0 never ended in a listing, and
that 2.1.0 was tagged on GitHub and never uploaded. The listing **is** live,
and it is live at 2.3.0. Two bad arguments got there. One was a 404 on
<https://apps.garmin.com/en-US/apps/d979409c-45c9-41b6-a1ec-092f51bd6006>, the
manifest's application id — but the store assigns a listing its own UUID, and
RinkPulse proves it on this watch: `GarminDevice.xml` gives it
`StoreId 036b4e61-…` and `AppId c46ee819-…`, and only `036b4e61-…` answers 200
from the store API while `c46ee819-…` 404s exactly as ours does. A 404 on a
manifest id is the normal state of affairs, published or not. The other was
the absent Connect IQ section on recorded games, which has a different cause
entirely, below.

So: **Upload New Version**, not the first-publish form.

## Read this before uploading: one thing 2.3.0 has to answer first

**Record one game on the installed 2.3.0 build and open its activity page
before uploading this release.** That game answers the question in *Does a later
upload update the rendering metadata?* below, and the answer decides whether
any of this release is worth typing.

- If Rest per Work reads as a decimal (e.g. `3.2`) and Avg Stride Rate is
  there, a later upload does update the metadata. Everything in 2.4.0 will
  render too. Upload it.
- If Rest per Work still reads as a three-digit integer and there are no
  stride fields, the
  listing is frozen on the metadata 2.0.0 set on 4 November. No upload fixes
  that, and the only route to rendering the new fields is a **new listing** —
  a decision worth making deliberately, since it abandons 100+ installs and
  the review.

Everything below assumes the first answer.

### The history, kept because it explains the mechanism

For three days the games showed nothing while the app was live, and the reason
was not the listing. The watch was not running the store build. It was running
a **sideload**, and a
sideload writes an `application_id` of sixteen zero bytes into every FIT file
where a store install writes the listing's UUID — which is the key Garmin
Connect joins its rendering metadata against. `GARMIN/GarminDevice.xml` lists
one `<App>` entry per store-installed app and has **no entry for this one**.

RinkPulse, on the same watch, is the control: registry `StoreId 036b4e61-…`
version 39, and its recordings carry `application_id 036b4e61-…`,
`application_version 39`, with an October file from before its last update
carrying 38. Every recording from this app carries zeros and version 0.

The fix was therefore not "publish" — that had already happened. It was to
delete the sideloaded `.prg` and install the app from the Connect IQ store.

One thing does not follow from it: **the games already in Connect cannot be
fixed.** Nov 1, 3 and 5 carry an id that matches no listing. The numbers are
intact in the FIT files and `tools/replay_detector.py` still reads them; the
activity pages stay bare.

**Paste the description as well as What's New**, every time.

---

## The mechanism, in full

Every FIT file carries a `developer_data_id` message whose `application_id` is,
in Garmin's own words, a *"16-byte identifier for the developer"* used to
*"uniquely identify developer data field sources"*
([FIT Protocol](https://developer.garmin.com/fit/protocol/), Table 9). Connect's
web backend joins on exactly that: its splits API returns
`"connectIQMeasurement": [{"appID": "…", "developerFieldNumber": 0, …}]` per
value. A sideloaded build writes **sixteen zero bytes** there and
`application_version` 0, so there is nothing to match and Connect draws no
Connect IQ section at all.

The watch confirms every link of it. `GARMIN/GarminDevice.xml` lists one
`<App>` entry per store-installed app, each with a `StoreId`, an `AppId` and an
integer `Version`:

| | registry | its FIT files |
|---|---|---|
| RinkPulse | `StoreId 036b4e61-…`, Version **39** | `application_id 036b4e61-…`, version **39** |
| …an October file, before its last update | | version **38** |
| Ice Hockey Tracker, since uninstalled | — | `8e916921-…`, version **54** |
| **This app** | **no entry at all** | **zeros, version 0** |

It is the `StoreId` that lands in the FIT, not the `AppId` and not the
manifest's application id. Checked against the store API, `036b4e61-…` returns
200 and `c46ee819-…` returns 404.

One caveat: no Garmin document or staff post states in writing that a sideload
writes a zero `application_id`. The decode is ours, the FIT spec and the
Connect API shape are official, and a developer who re-uploaded an identical
sideloaded app as a Beta reported the fields appearing immediately afterwards
([thread 299371](https://forums.garmin.com/developer/connect-iq/f/discussion/299371/sideloaded-datafield-app-doesn-t-seem-to-save-fit-contributor-fields-to-fit-file)).
Everything converges; that single sentence does not exist in Garmin's docs.

### Does a later upload update the rendering metadata?

Unknown, and it is the one open question that matters for this release. Forum
reports say Connect stores a listing's fit-contributions metadata at first
upload and that fields added later are not reliably picked up. This listing's
metadata was set on 4 November by 2.0.0, which had fields 0–13 only, `work_rest`
as an integer, and the two milli-g diagnostics charted.

If those reports are right, approving a later upload fixes nothing and the new
fields never appear. If they are wrong, everything in this release renders.
There is no way to tell from outside — which is why the check at the top of
this file comes before the upload, not after it. **If the stride fields do not
appear on a game recorded against the installed 2.3.0, that is the answer, not
a build problem**: the packaged `fit_contributions.json` has been verified to
carry every field with the right labels, units, precision and chart flags.

### A Beta, if you want the new fields before review clears

Not needed to prove rendering any more — installing the live 2.1.0 from the
store does that today, for free. A Beta is only worth it to see *this release's*
fields without waiting for review, and it is a dead end for real games: Garmin's
[Beta Apps](https://developer.garmin.com/connect-iq/core-topics/beta-apps)
instructions require **an alternate app id in the manifest**, created with a
UUID generator, so a Beta can never share an id with the listing and its games
stop rendering when it goes away.

1. Copy the manifest, replace the application id with a fresh UUID, and build
   the `.iq` from that. Do not commit it.
2. Upload it as a Beta, and delete the sideloaded `.prg` from the watch first.
3. Install it from <https://apps.garmin.com> in a desktop browser while signed
   in. Beta apps do not appear in the Connect IQ mobile app's search; the
   website, or Garmin Express, is how they reach the watch.
4. Record two minutes of waving an arm around, sync, and decode the file:
   `developer_data_id` should carry a real UUID and a non-zero version.
5. The activity should read Shifts, Ice Time, Bench Time, Avg Shift, Longest
   Shift, Rest per Work (as a decimal such as `3.2`, not a three-digit
   integer), On-Ice Avg HR, Time above 85%
   HR, Avg Stride Rate, Stride Coverage, HR Recovery (1 min), Skating Load and
   Skating Intensity, with Avg HR and Max HR beside each row in the Splits
   tab.

A Beta is also the only clean way to answer the caching question above without
risking the real listing, because it is a brand-new listing whose metadata has
never been set.

---

## Step 1 — the package

Attach `IndoorHockey/dist/IndoorHockey.iq`, built by `IndoorHockey/package.sh`.
All 126 products in `manifest.xml` — the 202 device variants they expand to —
signed, with no build paths in the packaged files; `package.sh` refuses to
produce a package that carries them.

**App Version:** type `2.5.0`

2.3.0 was the fourth upload and came back as Internal 4, so this is the fifth
and should read Internal 5 — the number that lands in every FIT file's
`application_version`, and a free way to tell a game recorded against this
release from one recorded against 2.3.0. Check the hint under the box reads
*(Latest app version: 2.3.0)* before typing, and *(2.4.0)* after.

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

969 characters (987 if the form counts CRLF line endings). Paste verbatim.

```
New: heart rate recovery - the one number here that measures how fit you are
rather than how hard the game was. HRR60: your rate when a shift ends, minus
your rate sixty seconds later, averaged over the game. Both ends are
five-second means, so a wrist sensor's jitter stays out of the answer.

New: skating load, the accumulated acceleration of your skating, counted on
the ice only so a game spent on the bench cannot inflate it. And skating
intensity - wrist motion times stride rate - which needs no GPS and no
setting at all.

New: the average and maximum heart rate of every shift and every bench spell
in the Splits tab, beside its length.

New: distance and speed can calibrate themselves. Where GPS has a fix and the
app has your rhythm in the same second, it works out your stride length and
keeps it for indoor games. Until it has one, both fields are left out rather
than invented.

New setting: Max Heart Rate, so Time above 85% is 85% of the right number.
```

**This covers 2.4.0 and 2.5.0.** The live listing is 2.3.0, so its users
already have stride rate, the retuned detector and the `work_rest` fix — the
whole of the current What's New text. Repeating any of it would say nothing.
2.4.0 is in here because it was tagged and never uploaded.

**The bench-fidget fix is deliberately not in this text.** It was the intended
headline of this upload — a ten-second entry window instead of six — and it was
withdrawn before release once it was measured without heart rate present. Do
not put it back. The reasons are in `docs/release-2.5.0.md` and at length in
`docs/detector-tuning.md`; the short version is that the window is unreachable
by motion alone, and that with no heart rate it can record a whole game as one
shift. Nothing about shift detection changed in 2.5.0.

No character limit for this field is documented anywhere I could find, and the
form's own counter is the authority. This lands under 1,000 in case that is the
cap. **If the form accepts more**, append this — it is the only part of the
release that asks anything of the player:

```
One thing that costs nothing: start the game at the opening faceoff rather
than in the warm-up. A warm-up skate produces the same wrist motion and the
same heart rate as a shift does, so a game started early collects shifts
nobody played - and nothing in the recording can tell them apart afterwards.
```

With the tail it is 1271 characters (1294 with CRLF).

---

## Description

3855 characters of 4,000 (3942 if the form counts CRLF line endings — it fits
either way, with 58 characters to spare on the CRLF count). Paste verbatim.

```
One press at the opening faceoff. After that the app works out when you are on
the ice and when you are on the bench. You never touch the watch again.

WHAT IT DOES

• Automatic shift detection — no button per line change. The app decides when
  you are skating and when you are resting, and splits the activity to match.
• One screen, everything at a glance, no paging mid-game.
• Shift clock — green, then amber, then red, with a long buzz at your target
  length.
• Ends itself if you forget — after 25 minutes with no skating it counts down
  and saves rather than discards.
• Total ice time on screen all game.
• On-ice heart rate as its own number, not blended with the bench: in elite
  match play it averages 84% of maximum, a figure a game average hides.

HOW THE DETECTION WORKS

Wrist motion is the only signal fast enough to open and close a shift, so it
decides and GPS only agrees with it. Heart rate mostly agrees too, with one
exception: while it sits well below its baseline, no amount of arm movement
will open a shift. That is a player sitting down. Thresholds are learned
during the game, and a change is believed only once it persists - six seconds
to open a shift - then dated back to when it happened, so a shift keeps its
opening seconds.

It will get some boundaries wrong. The LAP button flips the state by hand.

WHAT LANDS IN GARMIN CONNECT

Shifts, ice time, bench time, average and longest shift, rest-per-work ratio,
on-ice average heart rate, time above 85% of maximum HR, average stride rate
with its coverage, heart rate recovery, skating load and skating intensity.
One lap per shift and one per bench spell, each with its own average and
maximum heart rate, so the Splits tab reads as a shift chart. Plus the on-ice
state second by second.

FITNESS, NOT JUST EFFORT

Heart rate recovery is the one number here that should improve over a season.
The standard HRR60: your heart rate when a shift ends, minus your rate sixty
seconds later, averaged over every shift of the game.

Skating load is the accumulated acceleration of your skating, counted on the
ice only - what the professional sides measure, on the sensor you own.

Skating intensity is wrist motion times stride rate, and needs no GPS and no
setting at all. Unitless on purpose: compare it with your own past games.

STRIDE RATE

The app measures your skating rhythm from the wrist, in pushes per minute,
second by second and as a game average, with a coverage figure saying how much
of your ice time it rests on.

Distance and speed need a stride length, which nothing on a wrist can measure.
Set Stride Length yourself, or let the app find it: where GPS has a fix and
your rhythm in the same second, it works the length out and keeps it for
indoor games. Until it has one, those two fields are left out, not invented.

BUTTONS

START begins the game. Pressing it twice stops into the stop menu. Screen
taps do nothing during a game.
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
motion, so a watch in a vest or a bag has nothing to detect. Heart rate comes
from the watch; a paired chest strap is untested.

GPS is on by default; expect no fix inside most arenas. The app records
normally without one.

Strava has no ice hockey type: set Activity Type to Ice Skate if you sync
there.
```

This description went over the cap once before — 4,434 characters against
4,000, while the file claimed 3,864, because text was added twice without
re-counting. Every count in this file is now produced by script rather than by
eye, and re-counted after any edit. The 58 characters above is the real
margin; the previous revision of this file claimed 24 where the true figure
was 27, so the claim had started drifting again.

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
wrong. The six corrected PNGs are in `docs/screenshots/`, 390x390, 10 to 38 KB
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
