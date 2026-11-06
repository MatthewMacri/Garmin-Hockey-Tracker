# v2.3.0 — stride rate, and why the activity page has been blank

Released 2026-11-06.
<https://github.com/MatthewMacri/Garmin-Hockey-Tracker/releases/tag/v2.3.0>

The release notes as published, kept here so the repo carries its own history
rather than only GitHub's.

---

## Stride rate, measured without GPS

The watch can tell how fast your legs are turning over, and it does not need a
fix to do it. Skating is periodic; the arm counterbalances the legs; the rhythm
is already in the accelerometer the shift detector reads.

New `StrideMeter.mc` finds it by **autocorrelation** — six seconds of
acceleration magnitude, mean removed, compared against delayed copies of
itself. The best lag is the stride period. The search covers lags of 7 to 27
samples, which at the ~21 Hz the sensor actually delivers is **47 to 184 pushes
per minute**.

Reported three ways:

| Field | Scope | |
|---|---|---|
| Stride Rate | record | Pushes per minute, second by second, charted |
| Avg Stride Rate | session | Mean over the seconds that produced one |
| Stride Coverage | session | What share of judged on-ice seconds produced one |

**Coverage is the field that makes the average worth reading.** A stride rate
averaged over 80% of your ice time is a different claim from one averaged over
12%, and no other hockey app tells you which you are looking at.

Two gates decide whether a second counts. A **confidence gate** at 0.45 of
zero-lag energy, which real skating clears at 0.7–0.95. And a **prominence
gate** at 0.60 above the mean of the lag curve, which exists because a single
hard impact in an otherwise quiet window scores 0.91 on confidence alone and
reports a stride that was never skated. Across synthetic cases real strides
score 0.76–1.09 on prominence and a lone impact scores 0.47; with the gate in,
every false-positive case drops to zero accepted windows.

Tested against a line-for-line Python port of the shipped code:

| case | true | reported | coverage |
|---|---|---|---|
| cruise 1.0 Hz, legs equal | 60 | 58 | 100% |
| cruise 1.4 Hz, legs equal | 84 | 82 | 100% |
| cruise 1.0 Hz, legs 50% apart | 60 | 58 | 100% |
| slow 0.8 Hz | 48 | 46 | 100% |
| hard 1.8 Hz | 108 | 105 | 100% |
| standing still | — | 0 windows | 0% |
| random noise | — | 0 windows | 0% |
| one impact, no rhythm | — | 0 windows | 0% |

The meter also measures its own sample rate rather than assuming one. The FR570
advertises a 100 Hz accelerometer and delivers about 21.4 Hz to a watch app; a
hard-coded 25 would have reported every stride 17% fast.

**What is not verified:** the gates were sized against synthetic signals, not
against a recording of real skating, and no published study has measured wrist
accelerometry during skating to check against. Stride Confidence and Stride Lag
are written to every record for that reason — the first real game recorded with
this build is what settles the thresholds.

## Distance and speed, only if you supply the missing number

Distance would be pushes times stride length, and there is no stride length to
use. The walking coefficients a phone seeds from your height are a category
error for a 2.6–3.6 m skating push; GPS cannot calibrate one indoors, which is
the entire reason this app exists; and counting pushes systematically misses
glide, where you cover ground without pushing.

So the app asks instead of guessing. A new **Stride length** setting defaults to
**0, meaning off** — and at 0 the distance and speed fields are not created at
all, so the FIT carries no distance rather than a fabricated one. Set it and
both appear. The speed field is called **Speed While Striding** because its
denominator is the measured seconds, not your ice time: dividing by ice time
would quietly claim a speed for every second the app could not read.

## Why the activity page has been blank, traced

Every FIT file carries a `developer_data_id` message whose `application_id` is
the app's store UUID. Garmin Connect joins its rendering metadata against
exactly that — its own web API returns `{"appID": …, "developerFieldNumber": …}`
alongside each value.

Decoding this app's own recordings shows **sixteen zero bytes** there, and
`application_version` 0, where a store-installed rival hockey app on the same
watch writes its real UUID and the store's internal version counter. (Confirmed
against the store API: that app's FIT says version 54 and its listing says
`latestInternalVersion` 54.)

Two consequences, and the second one is the unwelcome one:

- A sideloaded build writes every field correctly and Connect renders none of
  them, because there is no listing with an id of all zeros.
- **Games already recorded cannot be fixed by publishing later.** They carry an
  id that will never match a listing. Only games recorded after a store install
  will render. The numbers are not lost — they are in the files, and
  `tools/replay_detector.py` still reads them.

This is also why the stride fields ship now rather than in a later release:
Connect stores a listing's fit-contributions metadata at first upload, and
fields added afterwards are not reliably picked up.

`docs/store-2.3.0.md` carries the full trace, the sources, and a way to confirm
the diagnosis over USB in five minutes before spending a store submission.

## Also

- `tools/fit/fitread.py` decodes `developer_data_id` (global message 207) and
  reads application UUIDs as raw bytes. The ordinary decode path dropped `0xFF`
  as an invalid value, which is a legal UUID byte — it was shortening one app's
  UUID to 30 hex digits.
