# v2.5.1 — three things 2.5.0 said it had fixed

Released 2026-11-07, the same day as 2.5.0 and before it reached the store, so
no user ever ran the version this corrects.

2.5.0's own release notes are what found these. Writing down precisely what a
fix did, in the sentence that will be published, is a slower way to check it
than reading the diff — and it caught three claims the code did not support.

## The GPS cache aged in the wrong place

2.5.0 added a staleness counter to the shift detector: four seconds, after
which a speed reading stops being allowed a vote. That counter sits in
`ShiftDetector.observe()` and it resets whenever it is handed a non-null speed.

But the position callback only fires when the system has a fix to report.
`GameModel` keeps the last good one in `_speed` and feeds it to `observe()`
**every second, forever**. So the detector was handed a non-null speed every
second, reset its counter every second, and never aged anything out. A fix
picked up walking into the rink could have held `corroboratesBench()` true for
a whole game — which is the exact failure the counter was added to prevent.

A cache has to age where it is written, not where it is read. `GameModel` now
counts the seconds since `onPosition()` last supplied a usable fix and passes
`null` once it is older than four, and the stride calibration and `hasGpsFix()`
read through the same gate. The detector's counter stays: it catches a model
that stops supplying a speed, and this one catches a model that keeps supplying
the same one.

## Three fields still reported a dead accelerometer as zero

2.5.0's theme was not publishing numbers it had not measured, and it gated
everything derived from ice time on a shift having actually banked. One level
in, that was not enough.

`ice_load`, `stride_avg` and `stride_coverage` are built from **wrist motion**.
With the accelerometer delivering nothing, they are 0.0, 0 and 0% — read as
"this player did not move" and "no rhythm in any of those seconds", which are
measurements, reported by a sensor that was silent. The ready screen says `NO
MOTION DATA` in red and `isHealthy()` returns false; the file then contradicted
both with three zeroes.

They are now written only if some on-ice second actually delivered a
wrist-motion sample, as `skating_intensity` already was. The distance and speed
estimates follow them, since they are the same measurement multiplied by a
stride length.

`work_rest` joined them for a different reason: it returns 0.0 both for a game
played without ever leaving the ice and for a game with too little ice to
divide by, and only the first of those is a measurement. The watch already drew
`--` rather than a ratio; the file now agrees with it.

Verified by decoding the simulator's own output, where the accelerometer never
reports:

| | 2.5.0 | 2.5.1 |
|---|---|---|
| `ice_load` | `0.0` | *absent* |
| `stride_avg` | `0` | *absent* |
| `stride_coverage` | `0` | *absent* |
| `shifts` / `ice_time` / `avg_shift` | `1` / `33` / `33` | unchanged |

An absent developer field decodes as that type's invalid value — `nan` for a
float, `None` for an integer — which is how a FIT file says "not measured".

## The size figure was the wrong build

2.5.0's notes quoted **35,290 B** against the 98,304 B of the tightest
supported device. Two things were wrong with it: it was a *debug* build, and it
did not reproduce at the tag — it was measured mid-pass, 113 B short of what
was committed.

The package `package.sh` builds passes `-e -r`, and `-r` strips the debug data.
What actually installs on a watch at **this** tag is **30,831 B** (25,951 code,
4,880 data), 31.4% of the 98,304 B available on the tightest supported device.
Quoting a debug total against a device's memory overstates the app's cost by
about 16%.

The corrected figure for 2.5.0 is in [its own notes](release-2.5.0.md#size),
measured at that tag, with the command; 2.4.0's claim of 27.2 kB did not
reproduce either and is corrected there to the measured 27,983 B.

**A later correction to this very section.** The first version of it printed
30,647 B here — which is 2.5.0's size, not 2.5.1's. It was measured before the
2.5.1 commit was made rather than at the tag, which is the same mistake, one
release along, as the one the section is about. The release series, all
measured at their tags with the command above:

| Tag | Release build | Of 98,304 B |
|---|---|---|
| v2.4.0 | 27,983 B | 28.5% |
| v2.5.0 | 30,647 B | 31.2% |
| v2.5.1 | 30,831 B | 31.4% |

## Nothing else changed

No detector constants and no new FIT fields. `CONFIRM_ICE` is still 6, and the
bench fidget is still open and still waiting on line-change ground truth from a
real game. (2.5.1 does add one constant of its own, `SPEED_STALE_AFTER`, and it
does change behaviour — an earlier draft of this line claimed otherwise.)

## This release should not be installed

Six QA passes over 2.5.1 found a dozen further defects, including one in the
fix above: the model stops feeding a stale fix after four seconds, but the
detector then started its own four-second count from zero, so a fix voted for
about nine seconds while both constants said four. See
[2.5.2](release-2.5.2.md), which is the version to upload.
