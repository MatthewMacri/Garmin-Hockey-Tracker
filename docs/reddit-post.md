# r/hockeyplayers post

Ready to paste. The store link below is the real one. Note the store's ID is
not the manifest App ID - the manifest's `d979409c-...` 404s on the store. The
real one came off the watch: `GARMIN/GarminDevice.xml` carries a `<StoreId>` per
store-installed app, which for this app is `4b5a5a43-...`.

Claims here stay inside what `comparison.md` can source. In particular it does
not say this is the only app that detects shifts automatically, or that Garmin
cannot track hockey, because neither is true. It also does not run down any
rival app: the trade-offs section does that work better.

**Title:** Made a free Garmin hockey app. Looking for people to break it, not
download it.

---

Garmin has an Ice Hockey activity profile, which gives you a duration and a
heart rate curve. What it doesn't give you is the shape of the game — when you
were on the ice, when you were on the bench, how long your shifts actually ran.
So I built a Connect IQ app for that. It's called Ice Hockey Shifts and it's
free.

One press at the opening faceoff. After that you don't touch the watch. It works
out when you're skating and when you're resting on its own and keeps recording
until you stop it — no periods to set up and nothing that ends the activity
partway through a game that ran long.

**The data goes into Garmin Connect.** No companion app, no account, no cloud.
It writes into the FIT file, so shifts, ice time, bench time, average and
longest shift, rest-per-work ratio, on-ice average heart rate and time above 85%
of max all show up in Garmin Connect alongside any other activity. One lap per
shift and one per bench spell, so the Splits tab reads as a shift chart. Works
the same on iPhone and Android because there's no app in the middle.

**On-ice heart rate is why I started.** A game average blends skating with
sitting, and the weighting is your rest rather than your effort — two guys who
skated identically post different averages because one got a shorter bench. So
it reports both separately.

**It will get shifts wrong, and that's the part I actually want to talk about.**
Every automatic shift tracker miscounts sometimes. So this one writes the raw
wrist motion and the threshold it learned during the game into the activity, one
value per second, next to the on-ice flag. When it gets a boundary wrong you can
chart exactly what it saw and why it decided wrong, instead of just knowing that
it did. The lap button flips the state by hand in the moment. And it's open
source, so the detection rule is something you can read rather than trust:
github.com/MatthewMacri/Garmin-Hockey-Tracker

**What it doesn't do**, because I'd rather you know before you install it:

- No GPS speed or distance indoors, and nothing invented to replace it. There
  is a unitless skating-intensity number, and a distance and speed if you give
  it a stride length or it picks one up from GPS outdoors - otherwise those
  fields are left out rather than guessed. If a distance on every indoor game
  is your main thing, this isn't your app.
- No goalie mode, no scorekeeping.
- It's new. The detection is tuned against one recorded game, mine. That's the
  single biggest weakness and it's the reason I'm posting.

**One thing I had listed here as missing, and it turned out not to be.**
Somebody asked about per-shift heart rate zones. The watch doesn't show them
and neither does Garmin Connect, so I said no — and then went and looked.
Every shift in this app is a lap, and Garmin's own firmware writes a zone
breakdown for every lap. Fifty laps and fifty-one of those records in the game
I checked. It had been recording the thing I'd just said it couldn't do, on
every game ever played with it. There's a script in the repo that reads them
out of a saved activity now, including zone time on the ice against zone time
on the bench, which Connect can't show you because it doesn't know which laps
were shifts.

Shift alerts buzz at your target length and can be switched off entirely.
Pausing takes two presses of start, because the screen is a touchscreen and one
press was too easy to make through a glove, and ending a game asks for
confirmation.

It detects from wrist motion, so the watch has to be on your wrist -
watch-in-a-vest gives it nothing to detect. Heart rate comes from the watch; a
paired chest strap is untested, and I'd rather say so than guess.

https://apps.garmin.com/apps/4b5a5a43-135d-456e-91a0-c1dbca4ada2d

**Full disclosure: this is my app and it's free.** I'd rather have five people
tell me it misread their shifts than fifty installs from people who never open
it. The useful feedback is your watch model, how many shifts it reported against
how many you actually took, and anything on screen that was cut off or
confusing.

---

## Alternative titles

- Free Garmin app for beer league: shifts, ice time and on-ice HR, and it all
  lands in Garmin Connect
- I built a Garmin shift tracker that shows its own working, because every
  shift tracker miscounts sometimes

The chosen title leads with the ask, which this sub responds to better than a
feature list. The second alternative is the most honest hook and the most likely
to start an actual conversation.
