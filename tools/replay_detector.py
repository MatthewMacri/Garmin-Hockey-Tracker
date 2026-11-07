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


def load(path):
    """Per-second motion, threshold, on_ice and heart rate from one game.

    Read with this repo's own decoder rather than fitdecode. The harness is
    the thing that says whether a detector change is safe, so it should not
    be the one file in the project that cannot run without pip.
    """
    out = []
    for m in fitread.parse(path)['record']:
        if m.get('dev:motion') is None:
            continue
        out.append({
            'motion': m.get('dev:motion'),
            'threshold': m.get('dev:motion_threshold'),
            'on_ice': 1 if m.get('dev:on_ice') else 0,
            'hr': m.get('heart_rate'),
        })
    return out


def mark_stale(rows):
    """Flag the seconds the accelerometer delivered nothing.

    The watch still ticks on those seconds - _secondsInState advances before
    tick() checks for a sample - so the harness has to tick on them too, or
    every minimum-dwell guard fires earlier in the replay than it did on the
    wrist. The 2026-11-03 game has 501 of them.

    They are recognisable because tick() returns before learn(): motion and
    threshold both repeat the row before. The leading motion-0 rows are the
    same case before any sample had arrived at all.
    """
    prev = None
    for r in rows:
        r['stale'] = (not r['motion']) or (
            prev is not None
            and r['motion'] == prev['motion']
            and r['threshold'] == prev['threshold'])
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

    When no sample arrives, tick() returns before learn(): the threshold does
    not move, and `motion` keeps whatever it last held. So a stale second shows
    up in the FIT as a row whose motion AND threshold both repeat the row
    before it. Replaying those rows feeds the same sample to the learner twice
    and inflates its working estimate, which is what made the first versions of
    this harness disagree with the watch.

    The leading motion-0 rows are the same case before any sample had arrived.
    """
    return [r for r in mark_stale(rows) if not r['stale']]


# Which band a recording was made with is a property OF THE FILE, and getting
# it wrong invalidates the whole replay: the harness would compare against a
# threshold no watch ever computed and report a disagreement that is really a
# settings difference. This went wrong once already, with 0.45 hardcoded while
# the watch had shipped 0.27, and it would have gone wrong again at 0.18.
#
# So stop asking the reader to remember. The recorded threshold is in the file,
# and exactly one band reproduces it, so the band can simply be recovered:
#
#   0.45  builds before b20a726        0.27  v2.0.0 to v2.1.0, normal
#   0.18  from v2.2.0, normal          0.24 low   0.14 high
#
# --band still overrides, for asking what a different band would have done.
BAND_GRID = [round(0.08 + 0.005 * i, 3) for i in range(0, 89)]


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
ERAS = {
    0.45: dict(CONFIRM_ICE=6, CONFIRM_BENCH=10, CONFIRM_BENCH_FAST=5, HR_VETO=None),
    0.27: dict(CONFIRM_ICE=6, CONFIRM_BENCH=10, CONFIRM_BENCH_FAST=5, HR_VETO=None),
    # v2.2.0 to v2.4.0: today's constants but the six-second entry window.
    0.24: dict(CONFIRM_ICE=6), 0.18: dict(CONFIRM_ICE=6), 0.14: dict(CONFIRM_ICE=6),
}


def era_for(band):
    """The constants that shipped with the band this file was recorded at."""
    key = min(ERAS, key=lambda b: abs(b - band))
    return ERAS[key] if abs(key - band) < 0.005 else None


def run(rows, band, confirm_ice_slow=None, start_on_ice=True, era=None):
    """Replay the whole state machine. Returns the per-second on-ice flags.

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
    return raw, dated


def agreement(flags, rows):
    """Share of seconds the replay and the watch agree on."""
    same = sum(1 for f, r in zip(flags, rows) if f == r['on_ice'])
    return 100.0 * same / len(rows) if rows else 0.0


def session_ice_pct(path):
    """The ice share the watch itself reported, from the session message."""
    d = fitread.parse(path)
    for m in d['session']:
        ice = m.get('dev:ice_time')
        total = m.get('total_elapsed_time')
        if ice is not None and total:
            return 100.0 * ice / (total / 1000.0)
    return float('nan')


def _main(argv):
    args = list(argv)
    band = None
    mode_shifts = '--shifts' in args
    if mode_shifts:
        args.remove('--shifts')
    sweep = None
    if '--sweep' in args:
        i = args.index('--sweep')
        sweep = [int(x) for x in args[i + 1].split(',')]
        del args[i:i + 2]
        mode_shifts = True
    if '--band' in args:
        i = args.index('--band')
        band = args[i + 1]
        del args[i:i + 2]
    if not args:
        print("usage: replay_detector.py GAME.fit [--band auto|0.18]")
        print("                                   [--shifts] [--sweep 6,9,12]")
        return 2

    if mode_shifts:
        allrows = mark_stale(load(args[0]))
        if not allrows:
            print("No motion developer fields in this file.")
            return 1
        livedup = [r for r in allrows if not r['stale']]
        if band is None or band == 'auto':
            band, _ = fit_band(livedup)
        else:
            band = float(band)
        total = len(allrows)
        print("%d seconds, %d of them stale (%.1f%%), band %.3f"
              % (total, total - len(livedup),
                 100.0 * (total - len(livedup)) / total, band))
        # Quoted from the session, not from the trace: the two differ by the
        # backdate and the session is the one the player sees.
        report("the watch, as recorded", [r['on_ice'] for r in allrows],
               total, allrows)
        print("  (that line's ice%% is the record trace; this file's session "
              "says %.1f%%)" % session_ice_pct(args[0]))

        # Validation first: can the harness reproduce what the watch did, with
        # the constants the watch was running? Everything after this is only
        # worth reading if that number is high.
        era = era_for(band)
        if era is None:
            print("band %.3f matches no known release - cannot validate" % band)
        else:
            raw, dated = run(allrows, band, era=era)
            print("replay at this file's own era reproduces %.1f%% of the "
                  "watch's seconds" % agreement(raw, allrows))
            report("replay, that era", dated, total, allrows)

        _, dated = run(allrows, band)
        report("replay, today's constants", dated, total, allrows)
        for n in (sweep or []):
            report("replay, plain entry %2ds" % n,
                   run(allrows, band, confirm_ice_slow=n)[1], total, allrows)
        if sweep:
            print("\n(plain entry = how long motion alone, with no heart rate\n"
                  " agreeing, must hold before a shift opens. The transition is\n"
                  " backdated by that many seconds, so a longer window costs\n"
                  " on-screen latency, not recorded ice time.)")
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
    CONFIRM_ICE, CONFIRM_BENCH = 10, 14
    CONFIRM_ICE_FAST, CONFIRM_BENCH_FAST = 3, 7
    MIN_SHIFT_SEC, MIN_BENCH_SEC = 8, 8
    HR_SLOPE, HR_OFFSET, HR_WINDOW = 0.25, 4.0, 20
    HR_VETO = 12.0

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
            fast = self._slope() >= self.HR_SLOPE or self._offset() >= self.HR_OFFSET
            if fast:
                need = self.CONFIRM_ICE_FAST
            elif self.CONFIRM_ICE_SLOW is not None:
                need = self.CONFIRM_ICE_SLOW
            else:
                need = self.CONFIRM_ICE
            if self.ice_streak >= need and self.dwell >= self.MIN_BENCH_SEC \
                    and not self._resting():
                self.on_ice = True; self.backtrack = need
                self._reset_streaks(); return True
        else:
            fast = self._slope() <= -self.HR_SLOPE or self._offset() <= -self.HR_OFFSET
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


def suspect(flags, rows):
    """Shifts the heart rate says were not shifts.

    A real shift raises the rate: across twelve recorded games the swing
    between a shift and the bench after it is 42-62 bpm. A shift whose own
    mean rate sits BELOW the game's slow baseline is a player who was sitting
    down and moved their arm - which is the complaint this metric exists to
    count. It is a proxy, not ground truth, but it is the only one a FIT file
    can supply without someone writing down line changes at the rink.
    """
    hrs = [r['hr'] for r in rows]
    known = [h for h in hrs if h]
    if not known:
        return 0, 0
    base = sorted(known)[len(known) // 2]
    bad = 0
    spans = shift_spans(flags)
    for a, b in spans:
        seg = [h for h in hrs[a:b] if h]
        if seg and sum(seg) / float(len(seg)) < base:
            bad += 1
    return bad, len(spans)


def report(name, flags, total, rows=None):
    segs = segments(flags)
    ice = [n for v, n in segs if v == 1]
    ben = [n for v, n in segs if v == 0]
    icesec = sum(ice)
    med = sorted(ice)[len(ice) // 2] if ice else 0
    extra = ""
    if rows is not None:
        bad, n = suspect(flags, rows)
        extra = "  below-baseline HR %2d/%-3d" % (bad, n)
    print("%-26s ice %5.1f%%  shifts %3d  median shift %3ds  median bench %3ds%s"
          % (name, 100.0 * icesec / total, len(ice), med,
             sorted(ben)[len(ben) // 2] if ben else 0, extra))
    return {'ice_pct': 100.0 * icesec / total, 'shifts': len(ice), 'median': med}

if __name__ == '__main__':
    import sys
    sys.exit(_main(sys.argv[1:]))
