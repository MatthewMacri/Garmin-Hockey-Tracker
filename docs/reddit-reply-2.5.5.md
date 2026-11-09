# Reply to the 2026-11-09 field report

Ready to paste. The report it answers is in [feedback.md](feedback.md);
what shipped is in [release-2.5.4.md](release-2.5.4.md) and
[release-2.5.5.md](release-2.5.5.md).

It concedes two things rather than explaining them away, because both are
true: the two-press pause was meant to prevent exactly what happened to him
and didn't, and the setting that was supposed to silence the line-change
buzz never gated it. It makes no claim about shift-count accuracy, which is
still the one thing this app cannot prove.

347 words.

```
This is the most useful feedback I've had, and you were right on all three.
All of it is fixed and submitted to the store as 2.5.5 - Garmin review is
taking days to weeks at the moment, so it won't appear instantly.

The button one was a real bug and the worst kind, because it loses data.
Pausing took two presses within a window, which was meant to stop exactly
what happened to you - and it doesn't, because a glove rubbing a button
produces the second press on its own. So pausing is now a HOLD of about a
second, and a short press during a game does nothing at all. A glove can
brush a button; it can't hold one down.

The part where it ended AND discarded was two more failures stacked on that.
Discard was sitting on the stop menu, which is exactly where an accidental
press chain lands, so it's off that menu entirely now - it's only behind
holding UP. And the confirmation couldn't pre-select "no": the watch API I
was using takes a prompt and nothing else, so it was up to the firmware, and
the firmware doesn't. It's a proper menu now with "No, keep playing" selected
first.

The bench vibration had no off switch at all. I thought it did - there's a
"shift alerts" setting, but it only controlled the long-shift buzz, not the
line-change one. There's now a separate setting for it and it's OFF by
default, because you're right that it's telling you something you can already
see.

On the detection itself: it could legally flip between on-ice and bench every
8 seconds, which is your ten-second oscillation. That minimum is now 20
seconds, and I also removed a heart-rate rule that was firing on 42% of bench
seconds and doing almost nothing useful.

No pressure to come back to it - the native activity is a perfectly good
answer. But if you ever do, the shift count is the thing I'd want to hear
about, because that's the part I still can't prove.
```
