#!/usr/bin/env python3
"""Replay ShiftDetector's entry/exit logic over a recorded game.

The per-second diagnostics the app writes - motion, motion_threshold,
on_ice - are enough to re-run the detector offline against any FIT file it
produced, with the heart-rate arithmetic reproduced exactly. That makes a
recorded game a regression test for a tuning change: score a candidate
against the games already on disk before putting it on a wrist.

Two things it will not tell you. The labels it scores against are the
detector's own `on_ice`, not ground truth, so a likelihood ratio here
measures agreement with the motion verdict rather than with reality - and
the bias runs in favour of whatever configuration recorded the file. And a
game recorded without GPS (every game at this player's rink so far) never
exercises the speed arm of corroboration, so only the HR arms are scored.

    tools/fit/replay-detector.py data/2026-11-05-game/*.fit
    tools/fit/replay-detector.py --lr data/*/*.fit
"""

import argparse
import os
import statistics as st
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fitread  # noqa: E402

# Kept in step with IndoorHockey/source/ShiftDetector.mc by hand. If a
# constant moves there and not here, this tool quietly scores the old code.
HR_WINDOW, HR_BASE_ALPHA = 20, 0.0055
HR_SLOPE, HR_VETO = 0.25, 12.0
HYSTERESIS = 0.18
CONFIRM_ICE, CONFIRM_BENCH = 6, 14
CONFIRM_ICE_FAST, CONFIRM_BENCH_FAST = 3, 7
MIN_SHIFT_SEC = MIN_BENCH_SEC = 8

# The arm removed on 2026-11-07, kept so its cost stays reproducible.
LEGACY_HR_OFFSET = 4.0


def samples(path):
    """Per-second (motion, threshold, hr, on_ice, hrOffset, hrSlope)."""
    out, hr, base = [], [], 0.0
    for r in fitread.parse(path).get("record") or []:
        motion, thr = r.get("dev:motion"), r.get("dev:motion_threshold")
        if motion is None or thr is None:
            continue
        rate = r.get("heart_rate")
        if rate is not None:
            hr.append(rate)
            if len(hr) > HR_WINDOW:
                hr = hr[1:]
            base = float(rate) if base <= 0.0 \
                else base + (float(rate) - base) * HR_BASE_ALPHA
        n = len(hr)
        offset = 0.0 if (n < 8 or base <= 0.0) else float(hr[-1]) - base
        slope = 0.0 if n < 8 else (float(hr[-1]) - float(hr[0])) / (n - 1)
        out.append((motion, thr, rate, r.get("dev:on_ice"), offset, slope))
    return out


def replay(rows, offset_arm=False):
    """Run the state machine. Returns [(start, seconds, peak_hr), ...]."""
    ice = bench = held = 0
    on_ice, shifts, cur = False, [], None
    for i, (motion, thr, rate, _, offset, slope) in enumerate(rows):
        upper, lower = int(thr * (1 + HYSTERESIS)), int(thr * (1 - HYSTERESIS))
        if motion >= upper:
            ice, bench = ice + 1, 0
        elif motion <= lower:
            bench, ice = bench + 1, 0
        else:                                   # dead band: decay, don't reset
            ice, bench = max(0, ice - 1), max(0, bench - 1)

        fresh = rate is not None
        if offset_arm:
            corr_ice = fresh and (slope >= HR_SLOPE or offset >= LEGACY_HR_OFFSET)
            corr_bench = fresh and (slope <= -HR_SLOPE or offset <= -LEGACY_HR_OFFSET)
        else:
            corr_ice, corr_bench = fresh and slope >= HR_SLOPE, fresh and slope <= -HR_SLOPE

        held += 1
        if not on_ice:
            need = CONFIRM_ICE_FAST if corr_ice else CONFIRM_ICE
            if ice >= need and held >= MIN_BENCH_SEC \
                    and not (fresh and offset <= -HR_VETO):
                on_ice, held, ice, bench = True, 0, 0, 0
                cur = [i - need, []]            # entry is dated back by `need`
        else:
            cur[1].append(rate or 0)
            want = CONFIRM_BENCH_FAST if corr_bench else CONFIRM_BENCH
            if bench >= want and held >= MIN_SHIFT_SEC:
                on_ice, held, ice, bench = False, 0, 0, 0
                shifts.append((cur[0], (i - want) - cur[0], max(cur[1] or [0])))
                cur = None
    return shifts


def summarise(label, shifts):
    total = sum(s[1] for s in shifts)
    quiet = sum(1 for s in shifts if s[2] and s[2] < 130)
    mean = total // len(shifts) if shifts else 0
    print(f"  {label:<26} {len(shifts):3d} shifts  ice {total:5d}s"
          f"  avg {mean:3d}s  never above 130bpm: {quiet}")


def likelihood(rows):
    """P(test | ice) against P(test | bench) for each HR arm."""
    judged = [r for r in rows if r[2] is not None and r[3] is not None]
    ice = [r for r in judged if r[3]]
    bench = [r for r in judged if not r[3]]
    if not ice or not bench:
        print("  (no judgeable seconds)")
        return
    print(f"  {len(judged)} s carrying both a heart rate and a verdict"
          f"   ice={len(ice)}  bench={len(bench)}")
    tests = [
        ("slope>=.25 OR offset>=4 (old)", lambda r: r[5] >= HR_SLOPE or r[4] >= LEGACY_HR_OFFSET),
        ("slope>=.25 alone      (now)", lambda r: r[5] >= HR_SLOPE),
        ("offset>=4 alone", lambda r: r[4] >= LEGACY_HR_OFFSET),
        ("veto: offset<=-12", lambda r: r[4] <= -HR_VETO),
    ]
    for name, fn in tests:
        pi = sum(1 for r in ice if fn(r)) / len(ice)
        pb = sum(1 for r in bench if fn(r)) / len(bench)
        ratio = f"{pi / pb:6.2f}" if pb else "   inf"
        print(f"    {name:<32} P(+|ice)={pi:6.3f}  P(+|bench)={pb:6.3f}  LR={ratio}")
    for name, idx in (("hrOffset", 4), ("hrSlope", 5)):
        mi, mb = st.mean([r[idx] for r in ice]), st.mean([r[idx] for r in bench])
        si, sb = st.pstdev([r[idx] for r in ice]), st.pstdev([r[idx] for r in bench])
        pooled = ((si ** 2 + sb ** 2) / 2) ** 0.5
        d = (mi - mb) / pooled if pooled else 0.0
        print(f"    {name:<32} ice {mi:+7.2f}  bench {mb:+7.2f}"
              f"  separation {mi - mb:+6.2f}  Cohen d {d:+5.2f}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+")
    ap.add_argument("--lr", action="store_true",
                    help="also score the heart-rate arms as likelihood ratios")
    args = ap.parse_args()

    for path in args.files:
        try:
            rows = samples(path)
        except Exception as exc:                # noqa: BLE001 - report and continue
            print(f"\n{path}\n  unreadable: {exc}")
            continue
        if not rows:
            print(f"\n{path}\n  no per-second diagnostics - not a game this app recorded")
            continue
        print(f"\n{os.path.basename(path)}  ({len(rows)} s)")
        summarise("shipped (slope only)", replay(rows, offset_arm=False))
        summarise("legacy (slope OR offset)", replay(rows, offset_arm=True))
        if args.lr:
            likelihood(rows)


if __name__ == "__main__":
    main()
