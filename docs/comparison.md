# What else is out there

Researched 2026-11-05. Every claim here either cites a source or is marked
unverified. Rival feature lists come from the makers' own pages, which means
they are claims and not measurements - nothing below has been tested against a
rival app on real ice.

Prices and ratings move. Re-check before quoting any of this publicly.

## The short version

Garmin ships an Ice Hockey activity profile and it records a hockey-shaped
nothing: duration, heart rate, calories. No shift structure, because the watch
has no idea when you were on the ice.

Three Connect IQ apps fill that gap, and they have split along a clear line.
RinkPulse and Ice Hockey Tracker add metrics - shots, speed, distance, zones,
goalie stats, scorekeeping - and RinkPulse puts the history in its own
companion app. This one adds no metrics beyond the shift structure and puts
everything in Garmin Connect instead.

So the honest framing is not "better". It is: do you want more numbers, or do
you want the numbers in the place you already keep your training?

## Garmin, out of the box

**Ice Hockey** is a built-in activity profile, listed under Team Sports in the
[Forerunner 970 owner's
manual](https://www8.garmin.com/manuals/webhelp/GUID-025D75CF-3445-49E1-8D81-1AA74AB4E00F/EN-US/GUID-1AD90095-0C71-4E0C-A8F9-F24643235F14.html)
alongside Field Hockey, Lacrosse and Rugby. It exists on current watches; it is
not something Garmin ignores.

What it does not do is anything hockey-specific. Garmin's manual names the
activity and describes no shift, ice-time or bench metrics for it, and nothing
in Garmin's documentation suggests the stock profile detects shifts. You get an
activity of the right type with a heart rate curve, and the structure of the
game - when you were skating, when you were sitting - is gone.

Garmin's own forum carries a [three-year-old request for "a decent Ice Hockey
App"](https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-web/318571/ice-hockey-app)
with no staff reply, now locked. That is the gap every app below is filling.

## RinkPulse

[Store listing](https://apps.garmin.com/en-US/apps/036b4e61-03af-4946-bc52-89ec13ca7724)
· [rinkpulsehockey.com](https://rinkpulsehockey.com/) · free, no ads, a premium
tier described as not live.

The most developed of these by a distance, and the most actively supported. Its
own site claims:

- Auto shift detection from skating motion, with optional gyro confidence on
  supported watches
- Shift count and average, ice time, bench time, work/rest ratio
- Heart rate zones for the whole game *and per shift*
- Speed and distance on the watch
- Goalie mode - tap saves and goals against, save percentage at the buzzer
- Manual shift correction: hold DOWN about a second, or MARK ON ICE / MARK
  BENCH from the End menu
- Scorekeeping in the companion: goals, assists, plus/minus, score, notes
- 84 supported Garmin models

Companion apps on Android (Google Play open test) and iPhone (TestFlight); no
Apple Watch. The watch app works standalone - the companion is for history,
charts, edits and an optional cloud sync behind a sign-in.

**Where it is weaker than its feature list suggests.** Its site never mentions
Garmin Connect sync, and states it does not provide full Garmin account history
import. The history lives in the companion. On [the r/hockeyplayers
thread](https://www.reddit.com/r/hockeyplayers/) the developer said plainly
that Garmin Connect "doesn't really show the full RinkPulse breakdown like
shifts, shift duration, and the indoor estimated speed stuff in a clean way",
and that the detailed stats are on the watch summary and in the companion.

Testers in that thread reported shift counts of 16-vs-13 and 28-vs-16 against
hand counts, speeds reading low, confusion over how to end a workout, text
clipped on some watches, and shift-alert buzzing people wanted to switch off.
The developer acknowledged each and shipped fixes. **Those reports are around
six months old and the app has had several updates since** - do not quote them
as current behaviour.

Its own developer calls the indoor speed estimate weak: "The speed tracking is
estimated and is not that great."

## Ice Hockey Tracker (RegoCom)

[Store listing](https://apps.garmin.com/en-US/apps/8e916921-7fac-406f-864a-ff0baf3d9c63)
· free · rated 4.0 · 100+ downloads.

The closest in spirit to this app, and the one worth taking seriously. Per its
store listing it reads the accelerometer to detect stepping on and off the ice,
times the shift, and stops the clock on the bench. Claims ice time, bench time,
shots, heart rate and rink-zone time, settings for shot sensitivity and rink
length, and saving as Ice Hockey rather than skating or "other".

**It also creates a lap for every shift and every bench spell** - the same
trick this app uses, so that is not a point of difference.

Its store description could not be read directly (the Connect IQ store renders
descriptions in JavaScript); the feature list above comes from a search index
of that listing and should be treated as **unverified**.

**First-hand note:** this app was tried before building this one and judged not
good enough, which is part of why this one exists. What specifically failed was
not written down at the time - worth recording if it is tried again, because
"we tried it and it was bad" is not usable in public and a concrete fault is.
Note also that its feature list and this impression may be of different
versions.

## HockeyTracker (Apple Watch)

[App Store](https://apps.apple.com/us/app/hockeytracker/id1297971760) · Apple
Watch only, so not a competitor so much as the reason some people leave Garmin.
It is the app the locked Garmin forum thread was asking Garmin to match, and a
tester on the Reddit thread said he was "about to go drop my garmin for an
Apple Watch bc I missed HockeyTracker".

## Where this app actually differs

Two things, and they are both narrow.

**1. The data lands in Garmin Connect with nothing in between.** No companion
app, no account, no cloud, no sign-in. Session fields - shifts, ice time, bench
time, average and longest shift, rest-per-work, on-ice average heart rate, time
above 85% of max - plus one lap per shift and one per bench spell, all written
into the FIT file. Same on iPhone and Android because there is no app in the
middle. RinkPulse's richer history needs its companion by its own description;
this one has no history of its own to need.

**2. The detector shows its work.** The app writes the raw wrist motion and the
learned threshold into the activity as per-second fields, alongside the on-ice
flag. Charted against each other they show every decision the detector made and
why. No other app here claims to expose its detection signal, which means when
one of them miscounts your shifts - and the Reddit thread is full of miscounts -
there is no way to see why. Here you can chart it, and `tools/replay_detector.py`
can re-run a recorded game offline against a changed detector.

Open source is the third thing, and it is the same point: the detection rule is
readable rather than taken on trust.

## Where this app loses

Stated plainly, because a comparison that only flatters is worth nothing.

| Missing here | Who has it |
|---|---|
| Speed and distance | RinkPulse, Ice Hockey Tracker |
| Shot counting | Ice Hockey Tracker |
| Goalie mode, save percentage | RinkPulse |
| Scorekeeping - goals, assists, plus/minus | RinkPulse |
| Heart rate zones per shift | RinkPulse |
| A history and charts app of its own | RinkPulse |
| Field testing by anyone but the author | RinkPulse, Ice Hockey Tracker |

The last row is the one that matters. RinkPulse has been through a few hundred
hockey players finding its edges; Ice Hockey Tracker has 100+ downloads and a
4.0 rating. This app has shipped to nobody and its shift detection has been
tuned against a single recorded game. Everything above about auditability is a
reason to believe it can be *fixed* quickly, not a claim that it is right.

The speed and distance gap is a deliberate choice rather than a todo: GPS does
not fix indoors, and an accelerometer alone cannot produce a trustworthy skating
speed. RinkPulse's developer says as much about his own. Reporting nothing is
the honest option, but it is still a gap, and for anyone who wants a distance
number it is the wrong trade.

## Claims to avoid making

- **"The only app that detects shifts automatically."** False - all three do.
- **"The only one that writes laps per shift."** False - Ice Hockey Tracker
  does too.
- **"Garmin can't track hockey."** False, and checkable in a manual. Garmin has
  an Ice Hockey profile. It does not break the game into shifts.
- **"RinkPulse needs a phone app."** Its site says the watch works standalone.
  The accurate claim is narrower: its richer history lives in the companion, and
  it does not put the full breakdown into Garmin Connect.
- Anything sourced from the Reddit thread's bug reports as if it were current.
  Those are about six months and several releases old.
