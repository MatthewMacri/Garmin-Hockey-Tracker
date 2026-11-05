#!/usr/bin/env python3
"""Replay the shift detector against a recorded game.

The app writes its motion index and its learned threshold into the FIT file
once a second, which means a real game can be run through a candidate detector
offline, as many times as needed, without going back to a rink. That is the
whole point of the motion/motion_threshold developer fields.
"""
import sys, fitdecode

def load(path):
    """Per-second motion, threshold, on_ice and heart rate from one game."""
    out = []
    with fitdecode.FitReader(path) as fr:
        for m in fr:
            if not isinstance(m, fitdecode.FitDataMessage) or m.name != 'record':
                continue
            dev = {f.name: f.value for f in m.fields
                   if type(f.field).__name__ == 'DevField'}
            if 'motion' not in dev:
                continue
            out.append({
                'motion': dev.get('motion'),
                'threshold': dev.get('motion_threshold'),
                'on_ice': 1 if dev.get('on_ice') else 0,
                'hr': m.get_value('heart_rate') if m.has_field('heart_rate') else None,
            })
    return out


class Learner:
    """The threshold rule as currently shipped in ShiftDetector.learn()."""
    MOTION_FLOOR = 85

    def __init__(self, band=0.27, rest=40.0, work=400.0,
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
    out, prev = [], None
    for r in rows:
        if not r['motion']:
            continue
        if prev is not None and r['motion'] == prev['motion'] \
                and r['threshold'] == prev['threshold']:
            prev = r
            continue
        out.append(r)
        prev = r
    return out


# The band the recording was made with, which is NOT necessarily the band
# currently shipped. Validation replays the recorded motion through the rule
# the watch was running AT THE TIME and compares against the threshold it
# actually wrote; replaying at a different band compares against a threshold no
# watch ever computed and reports a disagreement that is really a settings
# difference.
#
#   0.45  builds before b20a726 - the 2026-11-03 recording
#   0.27  v2.0.0 onwards, normal sensitivity
#   0.35  low sensitivity        0.21  high sensitivity
#
# Default is the shipped value, so a game recorded today replays correctly
# without an argument. Pass --band 0.45 for the 2026-11-03 file.
RECORDED_BAND = 0.27

if __name__ == '__main__':
    args = [a for a in sys.argv[1:]]
    band = RECORDED_BAND
    if '--band' in args:
        i = args.index('--band')
        band = float(args[i + 1])
        del args[i:i + 2]
    if not args:
        print("usage: replay_detector.py GAME.fit [--band 0.27]")
        sys.exit(2)
    rows = live(load(args[0]))
    print("samples: %d   replaying at band %.2f" % (len(rows), band))
    if not rows:
        print("No motion/threshold developer fields in this file - it was")
        print("recorded by a build that did not write them. Nothing to replay.")
        sys.exit(1)
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


class Detector:
    """The whole state machine, not just the threshold.

    Mirrors ShiftDetector.tick(): learn, hysteresis band, confirmation streaks
    with a decaying dead band, and the minimum-dwell guard. Validated by
    replaying a game and comparing against the on_ice the watch recorded.
    """
    HYSTERESIS = 0.18
    CONFIRM_ICE, CONFIRM_BENCH = 6, 10
    CONFIRM_ICE_FAST, CONFIRM_BENCH_FAST = 3, 5
    MIN_SHIFT_SEC, MIN_BENCH_SEC = 8, 8
    HR_SLOPE, HR_OFFSET, HR_WINDOW = 0.25, 4.0, 20

    def __init__(self, learner=None, hysteresis=None, start_on_ice=True):
        self.lr = learner or Learner()
        if hysteresis is not None:
            self.HYSTERESIS = hysteresis
        self.on_ice = start_on_ice
        self.ice_streak = self.bench_streak = 0
        self.dwell = 0
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

    def tick(self, sample, hr):
        self.observe(hr)
        self.dwell += 1
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
            need = self.CONFIRM_ICE_FAST if fast else self.CONFIRM_ICE
            if self.ice_streak >= need and self.dwell >= self.MIN_BENCH_SEC:
                self.on_ice = True; self._reset_streaks(); return True
        else:
            fast = self._slope() <= -self.HR_SLOPE or self._offset() <= -self.HR_OFFSET
            need = self.CONFIRM_BENCH_FAST if fast else self.CONFIRM_BENCH
            if self.bench_streak >= need and self.dwell >= self.MIN_SHIFT_SEC:
                self.on_ice = False; self._reset_streaks(); return True
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


def report(name, flags, total):
    segs = segments(flags)
    ice = [n for v, n in segs if v == 1]
    ben = [n for v, n in segs if v == 0]
    icesec = sum(ice)
    med = sorted(ice)[len(ice) // 2] if ice else 0
    print("%-26s ice %5.1f%%  shifts %3d  median shift %3ds  median bench %3ds"
          % (name, 100.0 * icesec / total, len(ice), med,
             sorted(ben)[len(ben) // 2] if ben else 0))
    return {'ice_pct': 100.0 * icesec / total, 'shifts': len(ice), 'median': med}
