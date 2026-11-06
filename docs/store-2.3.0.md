# Connect IQ Store — version 2.3.0, ready to paste

Everything the upload form at <https://apps.garmin.com/en-US/developer/upload>
asks for that has changed since the live listing, in the order the form asks
for it. The full field-by-field reference lives in `store/listing.md`; this
file exists so the text can be copied without reading around it.

**This is an update, not a first publish.** The dashboard shows the listing
live: *Ice Hockey Shifts* by KernelOPs, **version 2.1.0 (Internal: 3)**,
initial release 4 November 2026, latest release 4 November 2026, 100+
downloads and one five-star review — left against 2.0.0, so that upload reached
the public despite showing `Status: Verified` beside `Signature check failed`.

Earlier drafts of this file said the opposite, at length, and were wrong on
every count: that nothing was live, that 2.0.0 never ended in a listing, and
that 2.1.0 was tagged on GitHub and never uploaded. 2.1.0 **is** the live
version. Two bad arguments got there. One was a 404 on
<https://apps.garmin.com/en-US/apps/d979409c-45c9-41b6-a1ec-092f51bd6006>, the
manifest's application id — but the store assigns a listing its own UUID, and
RinkPulse proves it on this watch: `GarminDevice.xml` gives it
`StoreId 036b4e61-…` and `AppId c46ee819-…`, and only `036b4e61-…` answers 200
from the store API while `c46ee819-…` 404s exactly as ours does. A 404 on a
manifest id is the normal state of affairs, published or not. The other was
the absent Connect IQ section on recorded games, which has a different cause
entirely, below.

So: **Upload New Version**, not the first-publish form.

## Why the games still show nothing, with the app live

The watch is not running the store build. It is running a **sideload**, and a
sideload writes an `application_id` of sixteen zero bytes into every FIT file
where a store install writes the listing's UUID — which is the key Garmin
Connect joins its rendering metadata against. `GARMIN/GarminDevice.xml` lists
one `<App>` entry per store-installed app and has **no entry for this one**.

RinkPulse, on the same watch, is the control: registry `StoreId 036b4e61-…`
version 39, and its recordings carry `application_id 036b4e61-…`,
`application_version 39`, with an October file from before its last update
carrying 38. Every recording from this app carries zeros and version 0.

The fix is therefore not "publish" — that already happened. It is **delete the
sideloaded `.prg` and install Ice Hockey Shifts from the Connect IQ store on
the phone**. The next game recorded that way will render the 2.1.0 field set
immediately, without waiting for this release to clear review.

Two things do not follow from that:

- **The games already in Connect cannot be fixed.** Nov 1, 3 and 5 carry an id
  that matches no listing. The numbers are intact in the FIT files and
  `tools/replay_detector.py` still reads them; the activity pages stay bare.
- **Rendering the 2.1.0 field set is not rendering this one.** The live listing
  carries the fit-contributions metadata from the first upload: `work_rest` as
  an integer, so Rest per Work will read `317` rather than `3.2`, the two
  milli-g diagnostics charted, and no stride fields at all. Those need this
  upload.

**Paste the description as well as What's New.** The live listing still carries
the heart rate claim that was corrected in `537d491`, has no wrist note and no
warm-up note, and describes a detector that no longer behaves that way.

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

If those reports are right, approving 2.3.0 fixes nothing and the stride fields
never appear. If they are wrong, everything in this release renders. There is
no way to tell from outside, and no second chance either — so upload it, record
a game, and read the activity page. **If the stride fields do not appear after
2.3.0 is live, that is the answer, not a build problem**: the packaged
`fit_contributions.json` has been verified to carry all 21 fields with the
right labels, units, precision and chart flags.

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
   Shift, Rest per Work (as `3.2`, not `317`), On-Ice Avg HR, Time above 85%
   HR, Avg Stride Rate and Stride Coverage.

A Beta is also the only clean way to answer the caching question above without
risking the real listing, because it is a brand-new listing whose metadata has
never been set.

---

## Step 1 — the package

Attach `IndoorHockey/dist/IndoorHockey.iq`, built by `IndoorHockey/package.sh`.
All 202 device variants, signed, with no build paths in the 812 packaged files.

**App Version:** type `2.3.0`

The live listing reads `2.1.0 (Internal: 3)`, so this is the fourth upload and
will come back as Internal 4 — which is the number that lands in every FIT
file's `application_version`, and a free way to tell a game recorded against
this release from one recorded against 2.1.0.

2.2.0 is skipped on purpose: `v2.2.0` is already a published GitHub tag
pointing at the code from before stride rate existed, and reusing the number
would put different code behind it on the store than on GitHub.

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

878 characters (892 if the form counts CRLF line endings). Paste verbatim.

```
New: stride rate. The app now reads your skating rhythm off the wrist, in
pushes per minute, second by second and as a game average - with a coverage
figure saying how much of your ice time it rests on. Distance and speed stay
off until you set a stride length yourself: nothing on a wrist can measure
one, and the alternative is inventing it.

Shift detection has been retuned, and you will see it in your own numbers.
The old settings were fitted against a forward's share of the ice, and a
defenceman gliding at the point kept dropping under the bar and losing the
rest of the shift to the bench. A shift is now harder to leave than it is to
enter, and your heart rate can refuse one outright: while it sits well below
its own baseline for the game, no amount of arm movement will open a shift.

Also fixed: Rest per Work reads as a ratio, 3.2, rather than as the number
317.
```

**This covers 2.2.0 and 2.3.0 only.** The live listing is 2.1.0, so its users
already have the idle-timeout feature and the small-batch accelerometer fix —
the whole of the current What's New text. Repeating either would tell them
nothing. An earlier draft of this file did repeat both, because it was written
while believing nothing was live.

No character limit for this field is documented anywhere I could find, and the
form's own counter is the authority. This lands just under 1,000 in case that
is the cap. **If the form accepts more**, append this — it is the only part of
the release that asks anything of the player:

```
One thing that costs nothing: start the game at the opening faceoff rather
than in the warm-up. A warm-up skate produces the same wrist motion and the
same heart rate as a shift does, so a game started early collects shifts
nobody played - and nothing in the recording can tell them apart afterwards.
```

With the tail it is 1180 characters (1198 with CRLF).

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
