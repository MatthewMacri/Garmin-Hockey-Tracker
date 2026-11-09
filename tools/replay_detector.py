#!/usr/bin/env python3
"""Replay the shift detector against a recorded game.

The app writes its motion index and its learned threshold into the FIT file
once a second, which means a real game can be run through a candidate detector
offline, as many times as needed, without going back to a rink. That is the
whole point of the motion/motion_threshold developer fields.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fit import fitread


_PARSED = {}


def parsed(path):
    """Decode a file once. Several of the checks below want the whole message
    set, and parsing an 85-minute game four times is pure latency."""
    if path not in _PARSED:
        _PARSED[path] = fitread.parse(path)
    return _PARSED[path]


def load(path):
    """Per-second motion, threshold, on_ice and heart rate from one game.

    Read with this repo's own decoder rather than fitdecode. The harness is
    the thing that says whether a detector change is safe, so it should not
    be the one file in the project that cannot run without pip.
    """
    out = []
    for m in parsed(path)['record']:
        if m.get('dev:motion') is None:
            continue
        out.append({
            'ts': m.get('timestamp'),
            'motion': m.get('dev:motion'),
            'threshold': m.get('dev:motion_threshold'),
            'on_ice': 1 if m.get('dev:on_ice') else 0,
            'hr': m.get('heart_rate'),
        })
    return out


def record_gaps(rows):
    """(index, missing seconds) for every break in the one-per-second stream.

    A gap is a pause: onTick() returns before detector.tick() while the game
    is not RUNNING, in both the 1.0.0 and the current GameModel, so the
    detector genuinely did not tick through it and replaying the rows as if
    they were contiguous is right for the STATE MACHINE. It is not right for
    anything that divides by a clock - see session_ice_pct().
    """
    out = []
    for i in range(1, len(rows)):
        a, b = rows[i - 1].get('ts'), rows[i].get('ts')
        if a is None or b is None:
            continue
        if b - a != 1:
            out.append((i, b - a - 1))
    return out


def mark_stale(rows):
    """Flag the seconds the accelerometer delivered nothing.

    The watch still ticks on those seconds - _secondsInState advances before
    tick() checks for a sample - so the harness has to tick on them too, or
    every minimum-dwell guard fires earlier in the replay than it did on the
    wrist.

    A dropped second is recognisable because tick() returns before learn():
    motion and threshold both hold whatever they last held. But that
    implication only runs ONE WAY, and the first version of this function read
    it as if it ran both ways. A second that really was delivered produces an
    identical pair whenever the integer motion repeats AND the threshold did
    not move - and the threshold cannot move at all while the learned boundary
    sits under MOTION_FLOOR, because learn() clamps it there. That is the whole
    bench: low, repetitive motion against a pinned threshold.

    So a row at the floor is no evidence of staleness and is not flagged.

    The difference is not cosmetic. On the game of 2026-11-05, 73 of the 74
    rows the old rule flagged sat at the floor with a median motion of 7 mg,
    and a motion-magnitude-matched null model predicted 77 such coincidences
    against the 74 observed - no enrichment at all, which is what a rule firing
    purely on chance looks like. Proof that those seconds were really
    delivered: suppress the repeat rule on that file entirely and the learner
    reproduces the watch's recorded threshold EXACTLY, 0 mg of maximum error
    over 5121 seconds. A threshold cannot reproduce exactly unless learn() ran
    on every one of those seconds.

    That is not an argument for suppressing the rule, though, because on the
    game of 2026-11-03 the dropped seconds are real: suppressing it there takes
    the threshold error to 84 mg and agreement from 100% to 83%. The floor-
    aware rule is what separates the two cases. It keeps 489 of 2026-11-03's
    501 flags and discards 72 of 2026-11-05's 74, and on both files it takes
    the threshold error to 1 mg - from 3 mg - while agreement goes 97.4% ->
    98.4% on 2026-11-05 and stays at 100.0% on 2026-11-03.

    The leading motion-0 row is a different case: the firmware writes one
    record at the instant the timer starts, before onTick() has run at all.
    """
    prev = None
    for r in rows:
        repeat = (prev is not None
                  and r['motion'] == prev['motion']
                  and r['threshold'] == prev['threshold'])
        r['stale'] = (not r['motion']) or (
            repeat and r['threshold'] != Learner.MOTION_FLOOR)
        prev = r
    return rows


class Learner:
    """The threshold rule as currently shipped in ShiftDetector.learn()."""
    MOTION_FLOOR = 85

    # 0.18 is what v2.2.0 and later ship as Normal. The default used to be
    # 0.27, which was two releases stale, and a stale default here is not a
    # cosmetic problem: it silently replays a detector nobody is running.
    def __init__(self, band=0.18, rest=40.0, work=400.0,
                 down_fast=0.15, up_slow=0.01, min_gap=60.0):
        self.rest, self.work, self.band = rest, work, band
        self.down_fast, self.up_slow, self.min_gap = down_fast, up_slow, min_gap
        self.threshold = self.MOTION_FLOOR

    def step(self, sample):
        v = float(sample)
        self.rest += (v - self.rest) * (self.down_fast if v < self.rest else self.up_slow)
        self.work += (v - self.work) * (self.down_fast if v > self.work else self.up_slow)
        if self.work < self.rest + self.min_gap:
            self.work = self.rest + self.min_gap
        b = self.rest + (self.work - self.rest) * self.band
        self.threshold = max(self.MOTION_FLOOR, int(b))
        return self.threshold


def live(rows):
    """Only the seconds the accelerometer actually delivered.

    Replaying a dropped second feeds the same sample to the learner twice and
    inflates its working estimate, which is what made the first versions of
    this harness disagree with the watch. Replaying a DELIVERED second as if it
    had been dropped starves the learner instead, and costs just as much - see
    mark_stale() for how the rule that tells them apart gets it wrong, and in
    which direction.
    """
    return [r for r in mark_stale(rows) if not r['stale']]


# Which band a recording was made with is a property OF THE FILE, and getting
# it wrong invalidates the whole VALIDATION: the harness would compare against
# a threshold no watch ever computed and report a disagreement that is really a
# settings difference. This went wrong once already, with 0.45 hardcoded while
# the watch had shipped 0.27, and it would have gone wrong again at 0.18.
#
# So stop asking the reader to remember. The recorded threshold is in the file,
# and exactly one band reproduces it, so the band can simply be recovered:
#
#   0.55 / 0.45 / 0.35   v1.0.0            low / normal / high
#   0.35 / 0.27 / 0.21   v2.0.0, v2.1.0    low / normal / high
#   0.24 / 0.18 / 0.14   v2.2.0 onward     low / normal / high
#
# 0.35 is ambiguous between v1.0.0-high and v2.0.0-low, which is harmless:
# those two releases ship identical detector constants, so the era lookup
# returns the same answer either way.
#
# The grid has to reach 0.55 or a v1.0.0 low-sensitivity recording silently
# recovers as 0.52 - the top of the old grid - and then fails the era lookup
# and gets replayed at a band no watch ever used.
#
# --band still overrides, for asking what a different band would have done.
BAND_GRID = [round(0.08 + 0.005 * i, 3) for i in range(0, 100)]

# The band the app ships as Normal today. This is NOT the band to validate at
# and it is the ONLY band to run a counterfactual at; see the note above
# sweep() for why conflating the two was a decision-changing mistake.
SHIPPED_BAND = 0.18


def fit_band(rows, grid=None):
    """Recover the band the watch was running, from the threshold it wrote."""
    best, best_err = None, None
    for band in (grid or BAND_GRID):
        lr = Learner(band=band)
        err = 0
        for r in rows:
            err = max(err, abs(lr.step(r['motion']) - r['threshold']))
        if best_err is None or err < best_err:
            best, best_err = band, err
    return best, best_err


# The detector constants each era shipped, keyed by the band that identifies
# it. A replay is only a test of the harness if it runs the constants the
# recording was made with; running today's constants against a 2.1.0 recording
# and calling the disagreement an error is how a harness gets "fixed" until it
# reproduces the wrong thing.
# v1.0.0 through v2.1.0. Checked line by line against
# `git show <tag>:IndoorHockey/source/ShiftDetector.mc` for every tag: one
# constant set covers all six of those bands.
_OLD = dict(CONFIRM_ICE=6, CONFIRM_BENCH=10, CONFIRM_ICE_FAST=3,
            CONFIRM_BENCH_FAST=5, HR_VETO=None, HR_OFFSET_ARM=True,
            MIN_SHIFT_SEC=8, MIN_BENCH_SEC=8)
# v2.2.0 to v2.5.2: today's constants, plus the heart-rate offset arm on
# corroboration that 2.5.3 removed.
_MID = dict(CONFIRM_ICE=6, HR_OFFSET_ARM=True, MIN_SHIFT_SEC=8, MIN_BENCH_SEC=8)

ERAS = {
    0.55: _OLD, 0.45: _OLD, 0.35: _OLD, 0.27: _OLD, 0.21: _OLD,
    0.24: _MID, 0.18: _MID, 0.14: _MID,
}

# Everything the Learner uses - MOTION_FLOOR, the 40/400 seeds, the 0.15/0.01
# chase rates, the 60 mg minimum gap - and HYSTERESIS, HR_SLOPE, HR_OFFSET and
# HR_WINDOW are unchanged at every tag, so none of them need an era entry.
# MIN_SHIFT_SEC and MIN_BENCH_SEC did change, at 2.5.4, and are carried above.


def era_for(band):
    """The constants that shipped with the band this file was recorded at,
    or None when the band matches no release - in which case the file CANNOT
    be validated and nothing downstream of it should be believed.

    One caveat, new in 2.5.3. The band stopped identifying the era at that
    release: 2.5.3 changed corroboration and left HYSTERESIS alone, so a
    2.5.3 recording and a 2.4.0 recording are both band 0.18 and this
    function returns _MID for either. _MID is wrong for the newer file by
    exactly one constant, HR_OFFSET_ARM. Pass --no-offset-arm for a file a
    2.5.3-or-later build recorded."""
    key = min(ERAS, key=lambda b: abs(b - band))
    return ERAS[key] if abs(key - band) < 0.005 else None


def run(rows, band, confirm_ice_slow=None, start_on_ice=True, era=None):
    """Replay the state machine; returns (raw, dated). See run_detector()."""
    raw, dated, _ = run_detector(rows, band, confirm_ice_slow=confirm_ice_slow,
                                 start_on_ice=start_on_ice, era=era)
    return raw, dated


def strip_hr(rows):
    """The same game with no heart rate at all.

    Not a hypothetical. The rate comes from a wrist optical sensor under a
    glove, an elbow pad and a jersey sleeve, with no chest strap, and the
    detector's heart-rate votes all return 0.0 the moment the window has fewer
    than eight samples - so a dropout hands the state machine motion alone.
    Every entry window has to be judged in that condition as well as in the
    comfortable one, because that is the condition it will be in when it
    matters. See sweep().
    """
    return mark_stale([dict(r, hr=None) for r in rows])


def run_detector(rows, band, confirm_ice_slow=None, start_on_ice=True, era=None):
    """Replay the whole state machine. Returns (raw, dated, detector).

    `rows` must be ALL the rows, stale ones included - see mark_stale().
    """
    det = Detector(Learner(band=band), start_on_ice=start_on_ice,
                   confirm_ice_slow=confirm_ice_slow)
    for k, v in (era or {}).items():
        setattr(det, k, v)
    # TWO traces, because the watch keeps two and they are not the same.
    #
    # `raw` is the state second by second, which is what the on_ice developer
    # field records - the watch writes it as it goes and never revises it.
    # That is the trace to validate against, because it is the one in the file.
    #
    # `dated` applies the backdate: transition() sets _backtrackMs to the
    # length of the window that confirmed the change, and the segment
    # accounting dates the boundary back by that much. That is what feeds
    # ice_time, so it is the trace to quote an ice share from. On the game of
    # 2026-11-05 the difference is not academic - the record trace says 26.3%
    # and the session says 23.5%, because a bench spell is backdated 14
    # seconds and a shift only 6.
    raw, dated = [], []
    for r in rows:
        if det.tick(r['motion'] or 0, r['hr'], stale=r['stale']):
            now = 1 if det.on_ice else 0
            for i in range(max(0, len(dated) - det.backtrack), len(dated)):
                dated[i] = now
        v = 1 if det.on_ice else 0
        raw.append(v); dated.append(v)
    return raw, dated, det


def agreement(flags, rows):
    """Share of seconds the replay and the watch agree on."""
    same = sum(1 for f, r in zip(flags, rows) if f == r['on_ice'])
    return 100.0 * same / len(rows) if rows else 0.0


def session_ice_pct(path):
    """The ice share the watch itself reported. Returns (percent, note).

    The denominator used to be total_elapsed_time, which is wrong whenever the
    game was paused, and wrong in a way that quietly poisoned a comparison the
    harness printed side by side with its own number.

    On the game of 2026-11-03 the record stream has four breaks totalling 544
    seconds: elapsed is 4150 s, the timer 3601 s, and the trace 3605 rows. So
    the old line divided the watch's ice seconds by a clock 544 seconds longer
    than the trace it was being compared against, and read 16.3% where
    ice/timer is 18.8%.

    Worse, on that file the numerator is polluted too. The v1.0.0 pause() banks
    no segment clock and does not stop the detector, and the file's own
    ice_time + bench_time comes to 4148 s - elapsed, not timer - so a 205
    second pause that fell inside a shift was banked as ice time. (max_shift in
    that session is 220 s.) There is no denominator that rescues that
    numerator, so a gapped file gets no number at all rather than a number
    somebody might quote.
    """
    gaps = record_gaps(load(path))
    d = parsed(path)
    for m in d['session']:
        ice = m.get('dev:ice_time')
        timer = m.get('total_timer_time')
        elapsed = m.get('total_elapsed_time')
        if ice is None or not timer:
            continue
        if gaps:
            return None, (
                "refused: the record stream has %d break(s) totalling %d s, so "
                "the session's ice_time banked paused wall-clock into whichever "
                "segment was open and no denominator fixes it"
                % (len(gaps), sum(n for _, n in gaps)))
        note = "ice_time / total_timer_time"
        if elapsed and abs(elapsed - timer) > 1000:
            note += " (elapsed differs by %.0f s and is NOT the denominator)" \
                    % ((elapsed - timer) / 1000.0)
        return 100.0 * ice / (timer / 1000.0), note
    return None, "refused: no session ice_time in this file"


def has_position(path):
    """Seconds carrying a GPS speed or a position.

    The detector takes a speed vote the harness cannot model - see the caveat
    sweep() prints - so a file with a fix is a file this harness should not be
    trusted on.
    """
    n = 0
    for m in parsed(path)['record']:
        if m.get('speed') is not None or m.get('enh_speed') is not None \
                or m.get('lat') is not None:
            n += 1
    return n


def _main(argv):
    args = list(argv)
    band = None
    mode_shifts = '--shifts' in args
    if mode_shifts:
        args.remove('--shifts')
    windows = None
    if '--sweep' in args:
        i = args.index('--sweep')
        windows = [int(x) for x in args[i + 1].split(',')]
        del args[i:i + 2]
        mode_shifts = True
    # The sweep band is deliberately NOT --band. --band says what the file was
    # recorded with, which is a validation input; this says what to run a
    # counterfactual at, and it defaults to what the app ships. Conflating the
    # two is the mistake that produced the 2.5.0 entry-window retune.
    sweep_band = SHIPPED_BAND
    if '--sweep-band' in args:
        i = args.index('--sweep-band')
        sweep_band = float(args[i + 1])
        del args[i:i + 2]
    # 2.5.3 removed the offset arm without changing the band, so era_for()
    # cannot tell a 2.5.3 recording from a 2.4.0 one. This says which.
    offset_arm = None
    if '--no-offset-arm' in args:
        args.remove('--no-offset-arm'); offset_arm = False
    if '--offset-arm' in args:
        args.remove('--offset-arm'); offset_arm = True
    if '--band' in args:
        i = args.index('--band')
        band = args[i + 1]
        del args[i:i + 2]
    if not args:
        print("usage: replay_detector.py GAME.fit [--band auto|0.18]")
        print("                                   [--shifts] [--sweep 6,9,12]")
        print("                                   [--sweep-band 0.18]")
        print()
        print("  --band       the band the FILE was recorded with. Validation")
        print("               only; 'auto' recovers it from the file.")
        print("  --no-offset-arm  the file was recorded by 2.5.3 or later,")
        print("               where corroboration stopped consulting")
        print("               hrOffset(). --offset-arm forces the old")
        print("               behaviour. The band cannot tell them apart.")
        print("  --sweep-band the band to run the counterfactual sweep at.")
        print("               Defaults to the shipped %.2f. Changing it does"
              % SHIPPED_BAND)
        print("               not describe the shipped app.")
        return 2

    if mode_shifts:
        path = args[0]
        allrows = mark_stale(load(path))
        if not allrows:
            print("No motion developer fields in this file.")
            return 1
        livedup = [r for r in allrows if not r['stale']]
        given = band is not None and band != 'auto'
        if given:
            band = float(band)
        else:
            band, _ = fit_band(livedup)
        total = len(allrows)
        print("%d seconds, %d of them stale (%.1f%%), band %.3f%s"
              % (total, total - len(livedup),
                 100.0 * (total - len(livedup)) / total, band,
                 " (given)" if given else " (recovered from the file)"))
        gaps = record_gaps(allrows)
        if gaps:
            print("  the record stream has %d break(s) totalling %d s - the "
                  "game was paused.\n  The detector does not tick while paused,"
                  " so replaying the rows as\n  contiguous is right; any ice"
                  " SHARE off this file is not."
                  % (len(gaps), sum(n for _, n in gaps)))
        fixes = has_position(path)
        if fixes:
            print("  WARNING: %d records carry a GPS speed or position. This"
                  " harness does\n  not model the speed vote, so it cannot"
                  " answer for this file." % fixes)

        report("the watch, as recorded", [r['on_ice'] for r in allrows],
               total, allrows)
        pct, note = session_ice_pct(path)
        if pct is None:
            print("  (that line's ice%% is the record trace; the session's own "
                  "share is\n   %s)" % note)
        else:
            print("  (that line's ice%% is the record trace; this file's session"
                  " says %.1f%%,\n   %s - the two differ by the backdate)"
                  % (pct, note))

        # Validation first, AT THIS FILE'S OWN BAND: can the harness reproduce
        # what the watch did, with the constants the watch was running?
        # Everything after this is only worth reading if that number is high.
        era = era_for(band)
        if era is not None and offset_arm is not None:
            era = dict(era, HR_OFFSET_ARM=offset_arm)
        if era is None:
            print("band %.3f matches no release in ERAS - CANNOT VALIDATE, and"
                  " nothing\nbelow should be believed for this file." % band)
        else:
            raw, dated = run(allrows, band, era=era)
            print("replay at this file's own era (band %.3f) reproduces %.1f%%"
                  " of the watch's seconds" % (band, agreement(raw, allrows)))
            report("replay, that era", dated, total, allrows)

        if windows:
            sweep(allrows, windows, band=sweep_band)
        return 0

    rows = live(load(args[0]))
    if not rows:
        print("No motion/motion_threshold developer fields in this file - it")
        print("was recorded by a build that did not write them. Nothing to")
        print("replay.")
        return 1
    if band is None or band == 'auto':
        band, err = fit_band(rows)
        print("samples: %d   band recovered from the file: %.3f" % (len(rows), band))
    else:
        band = float(band)
        print("samples: %d   replaying at band %.3f (given)" % (len(rows), band))
    lr = Learner(band=band)
    err = 0
    mine, theirs = [], []
    for r in rows:
        t = lr.step(r['motion'])
        mine.append(t); theirs.append(r['threshold'])
        err = max(err, abs(t - r['threshold']))
    print("replayed threshold vs recorded: max abs difference = %d mg" % err)
    print("  recorded first/last: %d -> %d" % (theirs[0], theirs[-1]))
    print("  replayed first/last: %d -> %d" % (mine[0], mine[-1]))
    # A few milli-g of disagreement is the Float-to-Number truncation in
    # Monkey C against Python's, accumulated over an hour. Anything larger
    # means the model of the watch is wrong, not merely rounded.
    print("VERDICT:", "replay matches the watch" if err <= 5
          else "replay does NOT match - do not tune against it")
    return 0 if err <= 5 else 1


class Detector:
    """The whole state machine, not just the threshold.

    Mirrors ShiftDetector.tick(): learn, hysteresis band, confirmation streaks
    with a decaying dead band, and the minimum-dwell guard. Validated by
    replaying a game and comparing against the on_ice the watch recorded.
    """
    HYSTERESIS = 0.18
    # Six, not ten. Ten was the reverted entry-window experiment of
    # 2026-11-07; this default sat at it afterwards, which quietly scored
    # every replay that did not come through an era dict at a window the app
    # has never shipped.
    CONFIRM_ICE, CONFIRM_BENCH = 6, 14
    CONFIRM_ICE_FAST, CONFIRM_BENCH_FAST = 3, 7
    # 20 from 2.5.4; 8 before it. Every era below predates that, so both
    # carry the 8 explicitly rather than relying on this default.
    MIN_SHIFT_SEC, MIN_BENCH_SEC = 20, 20
    HR_SLOPE, HR_OFFSET, HR_WINDOW = 0.25, 4.0, 20
    HR_VETO = 12.0

    # Whether corroboration consults hrOffset() at all. False from 2.5.3,
    # where the arm was removed: scored over the three recorded games it ran
    # at a likelihood ratio of 1.54, flat across its whole range, while
    # taking the combined test's false-positive rate from 0.185 to 0.424.
    # HR_OFFSET itself stays, because HR_VETO still reads it.
    HR_OFFSET_ARM = False

    # The plain entry window: how long motion alone, with nothing agreeing
    # with it, has to hold before a shift opens. None means "same as
    # CONFIRM_ICE", which is what shipped up to and including 2.4.0.
    CONFIRM_ICE_SLOW = None

    def __init__(self, learner=None, hysteresis=None, start_on_ice=True,
                 confirm_ice_slow=None):
        self.lr = learner or Learner()
        if hysteresis is not None:
            self.HYSTERESIS = hysteresis
        if confirm_ice_slow is not None:
            self.CONFIRM_ICE_SLOW = confirm_ice_slow
        # The watch opens a game ON the ice: the press that starts it is the
        # one at the faceoff. See GameModel.toggleRun().
        self.on_ice = start_on_ice
        self.ice_streak = self.bench_streak = 0
        self.dwell = 0
        self.backtrack = 0
        self.hr, self.base = [], 0.0
        # Which window actually opened each shift. Worth counting, because it
        # turns out to decide whether an entry-window sweep means anything at
        # all: with heart rate present, corroboratesIce() is true on about half
        # of all judgeable seconds, so nearly every shift enters on the 3
        # second fast path and CONFIRM_ICE is never consulted.
        self.entries_fast = self.entries_slow = 0

    def observe(self, hr):
        if hr:
            self.hr.append(hr)
            if len(self.hr) > self.HR_WINDOW:
                self.hr.pop(0)
            self.base = float(hr) if self.base <= 0 else \
                self.base + (hr - self.base) * 0.0055

    # These two mirror ShiftDetector.hrSlope() and hrOffset() exactly, and the
    # word "exactly" is doing real work. This harness used to compute the slope
    # by least squares over the window and to skip the size guard on the offset.
    # Both are better statistics than the watch's - which is the problem. The
    # harness exists to answer "what would the watch have done", so where the
    # watch is crude the harness has to be crude in the same way. Matching them
    # took the harness from reproducing 98.3% of the watch's own on-ice
    # decisions to 100.0%.

    def _slope(self):
        """Two-point endpoint slope over the window, as the watch computes it."""
        n = len(self.hr)
        if n < 8:
            return 0.0
        return (self.hr[-1] - self.hr[0]) / float(n - 1)

    def _offset(self):
        if len(self.hr) < 8 or self.base <= 0:
            return 0.0
        return self.hr[-1] - self.base

    def _resting(self):
        """Heart rate far enough under its baseline to rule a shift out.

        Mirrors ShiftDetector.restingHeartRate(). The learner and the streaks
        still run while the veto holds - only the flip is refused - because
        that is what the watch does: learn() and the streak update both sit
        above the transition test in tick().
        """
        if self.HR_VETO is None:
            return False        # the veto did not exist before v2.2.0
        return self._offset() <= -self.HR_VETO

    def tick(self, sample, hr, stale=False):
        # observe() and the dwell counter run on EVERY second, including the
        # ones with no accelerometer sample: on the watch, GameModel calls
        # observe() before tick(), and tick() increments _secondsInState
        # before it checks for a sample. Only learn() and the streaks are
        # skipped. Getting this wrong makes every dwell guard fire early.
        self.observe(hr)
        self.dwell += 1
        if stale:
            return False
        t = self.lr.step(sample)
        upper, lower = int(t * (1 + self.HYSTERESIS)), int(t * (1 - self.HYSTERESIS))
        if sample >= upper:
            self.ice_streak += 1; self.bench_streak = 0
        elif sample <= lower:
            self.bench_streak += 1; self.ice_streak = 0
        else:
            self.ice_streak = max(0, self.ice_streak - 1)
            self.bench_streak = max(0, self.bench_streak - 1)

        if not self.on_ice:
            fast = self._slope() >= self.HR_SLOPE or (
                self.HR_OFFSET_ARM and self._offset() >= self.HR_OFFSET)
            if fast:
                need = self.CONFIRM_ICE_FAST
            elif self.CONFIRM_ICE_SLOW is not None:
                need = self.CONFIRM_ICE_SLOW
            else:
                need = self.CONFIRM_ICE
            if self.ice_streak >= need and self.dwell >= self.MIN_BENCH_SEC \
                    and not self._resting():
                self.on_ice = True; self.backtrack = need
                if fast:
                    self.entries_fast += 1
                else:
                    self.entries_slow += 1
                self._reset_streaks(); return True
        else:
            fast = self._slope() <= -self.HR_SLOPE or (
                self.HR_OFFSET_ARM and self._offset() <= -self.HR_OFFSET)
            need = self.CONFIRM_BENCH_FAST if fast else self.CONFIRM_BENCH
            if self.bench_streak >= need and self.dwell >= self.MIN_SHIFT_SEC:
                self.on_ice = False; self.backtrack = need
                self._reset_streaks(); return True
        return False

    def _reset_streaks(self):
        self.ice_streak = self.bench_streak = 0
        self.dwell = 0


def segments(flags):
    """Run-length the on-ice flags into (on_ice, seconds) segments."""
    out, cur, n = [], None, 0
    for v in flags:
        v = 1 if v else 0
        if v != cur:
            if cur is not None:
                out.append((cur, n))
            cur, n = v, 1
        else:
            n += 1
    if cur is not None:
        out.append((cur, n))
    return out


def shift_spans(flags):
    """(start, end) index pairs for each on-ice run."""
    out, start = [], None
    for i, v in enumerate(flags):
        if v and start is None:
            start = i
        elif not v and start is not None:
            out.append((start, i)); start = None
    if start is not None:
        out.append((start, len(flags)))
    return out


def baseline_hr(rows):
    """The median heart rate over the whole file, or None.

    Read what this number actually is before leaning on it. It is the median
    of every second in the file, and both recorded games are mostly bench - 83%
    on 2026-11-03, 74% on 2026-11-05 - so it is a BENCH heart rate, and the
    test "is this shift above it" is a generous one. The per-second separation
    it is being asked to resolve is 1.1 bpm on 2026-11-03 (ice mean 159.5,
    bench mean 158.4) and 3.8 bpm on 2026-11-05. The 42-62 bpm figure quoted
    in ShiftDetector.mc is a within-cycle peak-to-trough swing and is not this.

    So the proxy is weak, and weak in the direction of UNDER-counting sitting
    shifts on a bench-heavy game. It is still the only thing a FIT file
    supplies without someone writing down line changes at the rink, which is
    why it is here - but a one or two shift margin in it decides nothing.
    """
    known = sorted(h for h in (r['hr'] for r in rows) if h)
    return known[len(known) // 2] if known else None


def classify(flags, rows, base=None):
    """Each on-ice span as (start, end, mean heart rate, below baseline?)."""
    if base is None:
        base = baseline_hr(rows)
    hrs = [r['hr'] for r in rows]
    out = []
    for a, b in shift_spans(flags):
        seg = [h for h in hrs[a:b] if h]
        mean = sum(seg) / float(len(seg)) if seg else None
        out.append((a, b, mean,
                    bool(mean is not None and base is not None and mean < base)))
    return out


def suspect(flags, rows):
    """(below-baseline shifts, total shifts). A level, not a difference."""
    spans = classify(flags, rows)
    return sum(1 for s in spans if s[3]), len(spans)


def compare(ref, cand):
    """How a candidate's shifts differ from a reference's, counted HONESTLY.

    The difference of two below-baseline COUNTS cannot be read as "the shifts
    the change removed", and the published 6->10 table was read exactly that
    way. Changing the entry window changes the backdate - transition() dates
    the boundary back by the length of the window that confirmed it - so every
    SURVIVING shift's start moves too, by (new - old) seconds, into seconds
    whose heart rate had not caught up yet. That re-means the survivors.

    On 2026-11-05 at the shipped band, 6->10 removes 3 shifts but 4
    below-baseline ones: a shift that survived crossed the baseline because its
    start moved, not because anything was removed. So removal and
    reclassification are reported separately and never summed.

    Spans are matched by overlap, which is the only correspondence that
    survives a boundary moving by a few seconds.
    """
    def overlaps(x, ys):
        return [y for y in ys if x[0] < y[1] and y[0] < x[1]]

    removed = [r for r in ref if not overlaps(r, cand)]
    added = [c for c in cand if not overlaps(c, ref)]
    reclassified = 0
    for r in ref:
        hit = overlaps(r, cand)
        if hit and any(h[3] != r[3] for h in hit):
            reclassified += 1
    return {
        'removed': len(removed),
        'removed_below': sum(1 for r in removed if r[3]),
        'added': len(added),
        'added_below': sum(1 for c in added if c[3]),
        'reclassified': reclassified,
    }


# No defenceman sits for ten minutes. A bench spell this long is not a long
# bench spell, it is the detector having stopped detecting - and nothing on the
# watch warns about it, because isHealthy() only watches the accelerometer.
IMPLAUSIBLE_BENCH_SEC = 600


def shape(flags, total, rows=None):
    """The numbers worth printing about one replayed trace."""
    segs = segments(flags)
    ice = [n for v, n in segs if v == 1]
    ben = [n for v, n in segs if v == 0]
    bad = n = None
    if rows is not None:
        bad, n = suspect(flags, rows)
    return {
        'ice_pct': 100.0 * sum(ice) / total,
        'shifts': len(ice),
        'median': sorted(ice)[len(ice) // 2] if ice else 0,
        'median_bench': sorted(ben)[len(ben) // 2] if ben else 0,
        # The signature of a detector that has stopped detecting. A median
        # hides it; a maximum does not.
        'max_bench': max(ben) if ben else 0,
        'below': bad, 'spans': n,
    }


def report(name, flags, total, rows=None):
    s = shape(flags, total, rows)
    extra = ""
    if s['below'] is not None:
        extra = "  below-baseline HR %2d/%-3d" % (s['below'], s['spans'])
    print("%-26s ice %5.1f%%  shifts %3d  median shift %3ds  median bench %3ds"
          "  max bench %4ds%s"
          % (name, s['ice_pct'], s['shifts'], s['median'], s['median_bench'],
             s['max_bench'], extra))
    return s


def sweep(allrows, windows, band=SHIPPED_BAND, ref=6):
    """What each candidate entry window would do, at the SHIPPED band.

    Two separate mistakes used to live in this one function.

    The band. Validation has to replay at the band the file was recorded with,
    or it compares against a threshold no watch ever computed. A COUNTERFACTUAL
    is the opposite case: "what would the shipped detector do" is a question
    about the band the app actually ships, and the sweep used to inherit the
    recovered band instead. On the two files on record that meant sweeping at
    0.45 and 0.27 - two bands ShiftDetector.mc itself documents as wrong - and
    it changed the answer: the reason given for stopping at ten seconds rather
    than twelve ("twelve costs a good shift on 11-05 and buys nothing") is true
    at 0.27 and false at 0.18.

    The heart rate. Every row of the published table was computed with heart
    rate present, and with heart rate present the sweep barely measures its own
    variable: corroboratesIce() is true on about half of all judgeable seconds,
    so 29 of 32 entries on 2026-11-05 and 16 of 16 on 2026-11-03 open on the 3
    second fast path, where CONFIRM_ICE is not consulted at all. The whole
    table turned on 3 slow-path entries on one game and none on the other.
    Strip the rate - the real case for a wrist optical sensor under a sleeve,
    with no strap - and the longer windows collapse: at the shipped band, entry
    10 records a single twenty-minute bench block on 2026-11-05 and entry 12 a
    thirty-two-minute one on 2026-11-03, because with no fast path 0 of 196
    motion bursts on that game ever reach a ten-second streak.

    So the no-heart-rate column is not optional and not a footnote. It is the
    column that says whether a window is safe.
    """
    total = len(allrows)
    nohr = strip_hr(allrows)
    base_ref = classify(run(allrows, band, confirm_ice_slow=ref)[1], allrows)

    if abs(band - SHIPPED_BAND) < 1e-9:
        print("\nentry-window sweep at the SHIPPED band %.3f" % band)
        print("  (a counterfactual runs at the band the app ships, not at the"
              " band\n   this file was recorded with - that one is for"
              " validation only)")
    else:
        print("\nentry-window sweep at band %.3f, which is NOT the shipped"
              " %.3f" % (band, SHIPPED_BAND))
        print("  (asked for explicitly. Nothing below describes what the"
              " shipped app\n   would do, and it is not evidence for a"
              " constant change.)")
    print("  all \"vs\" columns are measured against the %ds row%s"
          % (ref, "" if ref in windows else " (not listed below)"))

    print("\n  with heart rate -- the comfortable case, and the one that"
          " measures least:")
    for n in windows:
        dated, det = run_detector(allrows, band, confirm_ice_slow=n)[1:]
        s = shape(dated, total, allrows)
        d = compare(base_ref, classify(dated, allrows))
        rel = "reference" if n == ref else (
            "vs %ds: %d removed (%d below), %d added (%d below), %d reclassified"
            % (ref, d['removed'], d['removed_below'], d['added'],
               d['added_below'], d['reclassified']))
        print("    %3ds  shifts %3d  ice %5.1f%%  below-baseline %2d/%-3d  "
              "entries %2d fast / %2d slow\n          %s"
              % (n, s['shifts'], s['ice_pct'], s['below'], s['spans'],
                 det.entries_fast, det.entries_slow, rel))

    print("\n  WITH NO HEART RATE -- motion alone, which is what a dropout"
          " leaves:")
    alarm = []
    for n in windows:
        dated = run(nohr, band, confirm_ice_slow=n)[1]
        s = shape(dated, total)
        flag = ""
        if s['max_bench'] >= IMPLAUSIBLE_BENCH_SEC:
            flag = "  <== %d min on the bench; the detector has stopped" \
                   % (s['max_bench'] // 60)
            alarm.append(n)
        print("    %3ds  shifts %3d  ice %5.1f%%  median bench %4ds  "
              "max bench %4ds%s"
              % (n, s['shifts'], s['ice_pct'], s['median_bench'],
                 s['max_bench'], flag))
    if alarm:
        print("\n  NOT SAFE with no heart rate: %s. A window is only a"
              % ", ".join("%ds" % n for n in alarm))
        print("  candidate if it survives BOTH blocks above.")

    print("\n  Two caveats this harness cannot measure its way out of:")
    print("   - The GPS speed vote is NOT modelled. corroboratesIce() returns"
          "\n     true outright at >= 2.5 m/s and corroboratesBench() at"
          " <= 0.6 m/s,"
          "\n     so on a file with a fix the entry window can be bypassed"
          " entirely"
          "\n     and the exit window halved. Everything above holds for"
          " FIXLESS"
          "\n     recordings only. Worth recording while it is in view:"
          " GameModel"
          "\n     caches _speed from onPosition() and observe() re-feeds that"
          " same"
          "\n     value every second without ever ageing it, so ONE fix"
          " reporting a"
          "\n     near-zero speed latches corroboratesBench() true for the"
          " rest of"
          "\n     the game.")
    print("   - The rate fed to observe() on the watch is"
          " Activity.getActivityInfo()"
          "\n     .currentHeartRate sampled when onTick ran; the rate here is"
          " the"
          "\n     per-second value the firmware wrote into the record. Two"
          " samplings"
          "\n     of one stream. Shifting this feed by a single second moves"
          " agreement"
          "\n     by up to 1.6 points, so treat every figure above as +-1.5.")

if __name__ == '__main__':
    import sys
    sys.exit(_main(sys.argv[1:]))
