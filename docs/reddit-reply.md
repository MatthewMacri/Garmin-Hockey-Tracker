# Reply for the r/hockeyplayers RinkPulse thread

Ready to paste. Replace `[STORE LINK]` first - the store's app ID is not the
manifest App ID, so copy the URL from the listing page itself.

That thread is about six months old and RinkPulse has had several releases
since, so this does not reference any of the bug reports in it as if they were
current, and it does not run the app down. See `comparison.md`.

---

Late to this thread, but there's one difference worth mentioning for anyone
still looking, and it's narrow enough to be worth stating precisely.

I wrote a Connect IQ app called Ice Hockey Shifts. Same premise: one press at
the opening faceoff, automatic shift detection, no mashing lap every line
change.

The difference is where the breakdown ends up. There's no companion app, no
account and no sign-in, because everything is written into the FIT file itself.
Shifts, ice time, bench time, average and longest shift, rest-per-work and
on-ice average heart rate all land in Garmin Connect like any other activity,
and it writes one lap per shift and one per bench spell so the Splits tab reads
as a shift chart. Same on iPhone and Android, because there's nothing in the
middle.

It also writes the raw wrist motion and the threshold it learned during the game
into the activity as per-second fields. That sounds like a nerd detail, but
several people in here reported shift counts that didn't match what they
actually took, and this is the thing that lets you chart why rather than just
report that it was wrong. It's open source too, so the detection rule is
readable instead of taken on trust:
github.com/MatthewMacri/Garmin-Hockey-Tracker

Being straight about the trade-offs:

- No GPS speed or distance indoors. There's a unitless skating-intensity
  number, and a distance and speed if you supply a stride length or it learns
  one from GPS outdoors; otherwise those fields are left out. I'd rather
  report nothing than a number I don't trust.
- No goalie mode, no scorekeeping.
- Per-shift HR zones aren't on the watch — but it turns out the watch has been
  recording them all along, because every shift here is a lap and Garmin writes
  a zone breakdown per lap. There's a script in the repo that pulls them out of
  a saved game, including on-ice zone time against bench zone time, which
  Connect can't show because it doesn't know which laps were shifts.
- It's brand new. Shift detection is tuned against one recorded game, so it
  will get boundaries wrong. The lap button flips the state by hand when it
  does.

It detects from wrist motion, so the watch has to be on your wrist —
watch-in-a-vest gives it nothing to work with. That came up a few times above.
Heart rate comes from the watch; a paired chest strap is untested.

[STORE LINK]

Full disclosure, it's my app and it's free.
