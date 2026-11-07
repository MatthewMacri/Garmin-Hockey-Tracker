# Feedback from players, and what was done about it

Every question and complaint worth acting on, with its status checked against
the code rather than remembered. What shipped in answer to them is in
[release-2.1.0.md](release-2.1.0.md); the store text that announces it is in
[store-2.5.0.md](store-2.5.0.md). Two sources: the r/hockeyplayers thread about
RinkPulse (a rival app, but the same players asking about the same sport, so
the complaints transfer) and replies to this app's own post.

Status means:

- **In the app** - verified present, with the evidence that proves it.
- **Added** - was missing, now built, with the commit.
- **Unverified** - should work by design, never actually tested. These are the
  dangerous ones: answering a player "yes" from a design argument is how a
  wrong answer gets published.
- **Not doing** - a deliberate decision, with the reason.

## Asked about this app

| Question | Status |
|---|---|
| "Sense when the game is over so I don't forget about it for 4 hours" | **Added** - `b51d493`, [#1](../../issues/1). 25 min idle, buzzes, saves itself. |
| "Does it still give an overall HR zone chart?" | **In the app.** Verified by decoding a recording: four `time_in_zone` messages (one session, three laps) plus `zones_target`. The watch writes them, not the app. |
| "Does it work with an HRM 600 chest strap?" | **Unverified.** See [#2](../../issues/2). |
| "Does it still log vigorous minutes to health metrics?" | **Unverified.** See [#3](../../issues/3). |

## Raised on the RinkPulse thread

These are complaints about a different app. They are listed because the same
player would hit the same thing here, and most of them this app already answers.

| Complaint | Status here |
|---|---|
| Shift buzz "driving me crazy… thought I was getting tons of calls" | **In the app.** `shiftAlerts` turns it off entirely; `shiftSeconds` moves it. |
| "I can't figure out how to start/stop" | **In the app.** START twice reaches the stop menu, hold UP reaches the same, and both exits confirm. |
| "Text from screens is cut off on some corners" | **In the app.** Everything goes through `drawFitted`, which walks a font ladder down to `FONT_XTINY` rather than clipping. Not proof it never clips on 202 variants, but it is designed against. |
| "HR zones show 1 at the top and 5 at the bottom, backwards" | **Not applicable.** No zone list is drawn on the watch. Zones come from Garmin Connect, in Connect's own order. |
| "Swiping through screens seems inverted" | **Not applicable.** One screen, no paging, and swipes are ignored while a game is live. |
| Shift count wrong - 16 vs 13, 28 vs 16 against hand counts | **Partly.** The lap key corrects a boundary in the moment, and the raw motion and learned threshold are written per second so a miscount can be charted afterwards. But this app's detector has been tuned against one game, so it has no right to claim it does better. |
| "Reported speeds seem low" / indoor speed | **Not doing.** No speed, no distance. GPS does not fix indoors and an accelerometer alone cannot produce a skating speed worth printing. |
| "Does it work for goalies?" | **Not doing yet.** See [#4](../../issues/4). |
| Scorekeeping - goals, assists, plus/minus | **Not doing yet.** See [#5](../../issues/5). |
| Per-shift HR zones | **Added** - `tools/fit/shift-zones.py` reads them out of a saved game, plus the ice-versus-bench zone split Connect cannot draw. See [#6](../../issues/6). |
| "I wear a chest strap and put the watch in a sports vest" | **Will not work, now documented.** Detection is wrist motion, so the watch has to be on the wrist. The docs implied this and never said it. |
| Not compatible with vivoactive 3 / FR245 / 645 / 945 / fenix 5X | **In the app.** All present in `manifest.xml`; `minApiLevel` is 3.1.0. 126 products covering 202 device variants. |
| Ports to Apple / Samsung / Pixel | **Not doing.** See `comparison.md`. On Apple the metrics have nowhere to live - HealthKit's types are a closed set - so the port loses the thing that makes this app worth using. |
| Beer counter, shock collar | Noted. |

## The pattern worth remembering

Three of the four questions asked about this app resolve to "probably fine,
never tested": chest straps, zone charts, intensity minutes. Only the zone
chart could be settled from a file already on disk. The other two need one real
game and ten minutes in Garmin Connect afterwards, which is worth more than any
amount of reasoning from the SDK documentation.

## A claim of ours went stale in under a day

The launch drafts both carried the line *"no goalie mode, no scorekeeping, no
per-shift heart rate zones."* It was true when it was written and false about
four hours later, when `tools/fit/shift-zones.py` shipped in v2.1.0. Nothing
flagged it. It was caught only because the line was read back to us.

The speed and distance half of that section is still exactly right and stays
as written - that one is a deliberate choice, not a todo, and it will not
change. The zone half was a todo that got done.

Worth remembering in both directions: a "what it doesn't do" list ages faster
than a feature list, because the whole point of writing one is to name the
things you intend to fix. Anything in `docs/` that tells a player what this app
cannot do needs re-reading against the code before it goes anywhere public,
and this file is where that check gets recorded.

The zone question turned out to be worth more than an answer. Looking for
evidence that the overall chart worked turned up a per-lap breakdown nobody had
noticed, already recorded on every game ever played with this app - so the
feature a player asked for had existed for months with nothing reading it. The
cost of answering from memory is not only a wrong answer; it is never finding
out what is already in the file.
