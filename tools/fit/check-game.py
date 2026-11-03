#!/usr/bin/env python3
"""Check that a recorded game actually logged what the app was supposed to log.

Run this on the .FIT the watch wrote, before trusting a gameday to it:

    python3 tools/fit/check-game.py /path/to/ACTIVITY.fit

It answers the only question that matters after a dry run - did the shift
detector receive data and act on it, or did the watch quietly record one very
long shift - and exits non-zero if anything is wrong.
"""
import sys, os, statistics as st

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fitread import parse, when, SPORT, SUBSPORT

FAIL, WARN = [], []


def check(path):
    f = parse(path)
    recs, laps = f['record'], f['lap']
    sess = f['session'][0] if f['session'] else {}
    names = sorted(v['name'] for v in f['devfields'].values())

    print('file     : %s' % os.path.basename(path))
    t = when(sess.get('start_time'))
    print('start    : %s' % (t.strftime('%Y-%m-%d %H:%M UTC') if t else '?'))
    print('sport    : %s / %s' % (SPORT.get(sess.get('sport'), sess.get('sport')),
                                  SUBSPORT.get(sess.get('sub_sport'), sess.get('sub_sport'))))
    print('elapsed  : %.1f min' % ((sess.get('total_elapsed_time') or 0) / 60000.0))
    print('records  : %d     laps: %d' % (len(recs), len(laps)))
    print('devfields: %s' % (', '.join(names) if names else 'NONE'))
    print()

    if not recs:
        FAIL.append('no record messages at all - nothing was recorded')
        return

    # --- the detector's own input signal -------------------------------
    motion = [r.get('dev:motion') for r in recs if r.get('dev:motion') is not None]
    if not motion:
        FAIL.append('no "motion" field - the app did not log its detection '
                    'signal, so this game cannot be used for tuning')
    else:
        nz = [m for m in motion if m > 0]
        print('motion   : %d samples, %d non-zero, median %.0f mg, p90 %.0f, max %.0f'
              % (len(motion), len(nz), st.median(motion) if motion else 0,
                 sorted(motion)[int(len(motion) * 0.9)], max(motion)))
        if len(nz) < 0.5 * len(motion):
            FAIL.append('motion was zero for %.0f%% of the game - the '
                        'accelerometer was not delivering'
                        % (100.0 * (len(motion) - len(nz)) / len(motion)))
        elif max(motion) < 150:
            WARN.append('motion never exceeded %d mg; that is low for skating '
                        'and may mean the watch was not on the wrist' % max(motion))

    thr = [r.get('dev:motion_threshold') for r in recs
           if r.get('dev:motion_threshold') is not None]
    if thr:
        print('threshold: median %.0f mg, range %.0f-%.0f'
              % (st.median(thr), min(thr), max(thr)))

    # --- did it actually split the game into shifts? --------------------
    on = [r.get('dev:on_ice') for r in recs if r.get('dev:on_ice') is not None]
    if not on:
        FAIL.append('no "on_ice" field - no shift state was recorded')
    else:
        flips = sum(1 for i in range(1, len(on)) if on[i] != on[i - 1])
        share = 100.0 * sum(1 for v in on if v == 1) / len(on)
        print('on-ice   : %.0f%% of the game, %d transitions' % (share, flips))
        if flips == 0:
            FAIL.append('the on-ice state never changed - the game recorded as '
                        'one single shift, which is the exact failure this '
                        'check exists to catch')
        elif flips < 6:
            WARN.append('only %d transitions; detection barely fired' % flips)
        if share > 85:
            WARN.append('on the ice for %.0f%% of the game - implausibly high'
                        % share)
        elif share < 10:
            WARN.append('on the ice for only %.0f%% of the game - implausibly '
                        'low' % share)

    # --- the summary numbers -------------------------------------------
    print()
    for k in ('shifts', 'ice_time', 'bench_time', 'avg_shift', 'max_shift',
              'work_rest', 'ice_avg_hr', 'hard_time'):
        v = sess.get('dev:' + k)
        print('  %-11s %s' % (k, 'MISSING' if v is None else v))
        if v is None:
            WARN.append('session field "%s" missing' % k)
    if (sess.get('dev:shifts') or 0) < 2:
        FAIL.append('session reports %s shifts' % sess.get('dev:shifts'))

    hr = [r.get('heart_rate') for r in recs if r.get('heart_rate')]
    if not hr:
        WARN.append('no heart rate recorded')
    else:
        print('\n  heart rate  avg %.0f  max %d  samples %d'
              % (st.mean(hr), max(hr), len(hr)))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    for p in sys.argv[1:]:
        check(p)
        print()
    for m in FAIL:
        print('FAIL: %s' % m)
    for m in WARN:
        print('WARN: %s' % m)
    if not FAIL and not WARN:
        print('OK: everything the app should have logged is present and sane.')
    elif not FAIL:
        print('OK with warnings: usable, but read the warnings above.')
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
