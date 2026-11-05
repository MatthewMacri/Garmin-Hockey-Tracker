#!/usr/bin/env python3
"""Heart rate zones per shift, from a recorded game.

    tools/fit/shift-zones.py data/2026-11-03-game/2026-11-03-22-11-07.fit
    tools/fit/shift-zones.py GAME.fit --csv shifts.csv

Why this exists
---------------
A player asked whether the app gives per-shift heart rate zones. The answer
about the app was no. The answer about the FILE turned out to be yes, and
nobody had looked.

Every shift in this app is a lap, and the watch firmware writes a time_in_zone
message for every lap - 50 laps and 51 of them in the game this was written
against, one per lap plus one for the session. So a zone breakdown per shift
has been recorded on every game ever played with this app. Nothing surfaces
it: Garmin Connect's Splits tab shows lap duration and average heart rate, and
its zone chart covers the whole activity.

The number this prints that exists nowhere else is the last one: zone time on
the ice against zone time on the bench. Connect cannot produce it because
Connect does not know which laps were shifts. This app does - it wrote the
shift_time and bench_time_lap fields on every lap itself.

None of this is a measurement by this script. The zone boundaries, the
bucketing and the seconds are all the watch's own; this reads them out and
groups them by a split the watch recorded but never used.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fitread  # noqa: E402

LAP_MESG = 19
SESSION_MESG = 18


def clock(seconds):
    """m:ss, or h:mm:ss once there is an hour of it."""
    seconds = int(round(seconds))
    if seconds >= 3600:
        return "%d:%02d:%02d" % (seconds // 3600, (seconds // 60) % 60, seconds % 60)
    return "%d:%02d" % (seconds // 60, seconds % 60)


def zone_seconds(msg):
    """The time_in_hr_zone array in seconds, holes preserved as 0.0."""
    raw = msg.get("time_in_hr_zone") or []
    return [(v or 0) / 1000.0 for v in raw]


def classify(lap):
    """Shift, bench, or unknown - from the fields the app wrote on the lap."""
    shift = lap.get("dev:shift_time") or 0
    bench = lap.get("dev:bench_time_lap") or 0
    if shift > 0 and bench == 0:
        return "shift"
    if bench > 0 and shift == 0:
        return "bench"
    return "unknown"


def bar(zone_times, width=24):
    """A stacked bar of the five real zones, hardest zone as the densest mark.

    Deliberately not colour: this gets piped into files and pasted into
    forum replies, and a bar that survives both is worth more than one that
    looks better in a terminal that supports it.
    """
    marks = ".-=#@"
    total = sum(zone_times[1:6])
    if total <= 0:
        return ""
    out = ""
    for i in range(5):
        out += marks[i] * int(round(width * zone_times[1 + i] / total))
    return out[:width]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("fit", help="a .fit file saved by the watch")
    ap.add_argument("--csv", metavar="PATH",
                    help="also write one row per lap, for charting elsewhere")
    ap.add_argument("--all-laps", action="store_true",
                    help="list bench spells individually too, not just shifts")
    args = ap.parse_args()

    data = fitread.parse(args.fit)
    laps = data["lap"]
    zones = data["time_in_zone"]

    if not zones:
        print("No time_in_zone messages in this file.")
        print()
        print("That is firmware behaviour rather than anything this app controls,")
        print("so it can differ by device and by firmware version. The per-lap")
        print("breakdown was confirmed on a Forerunner 570; if your watch does not")
        print("write it, nothing here can recover it after the fact.")
        return 1

    by_lap = {}
    session_zone = None
    for z in zones:
        if z.get("reference_mesg") == LAP_MESG:
            by_lap[z.get("reference_index")] = z
        elif z.get("reference_mesg") == SESSION_MESG:
            session_zone = z

    meta = session_zone or zones[0]
    bounds = [b for b in (meta.get("hr_zone_high_boundary") or []) if b]
    max_hr = meta.get("max_heart_rate")

    print("Per-shift heart rate zones - %s" % os.path.basename(args.fit))
    print()
    if bounds:
        labels = []
        for i in range(min(5, len(bounds) - 1)):
            labels.append("Z%d %d-%d" % (i + 1, bounds[i], bounds[i + 1]))
        print("  Zones from the watch: " + "   ".join(labels))
    if max_hr:
        print("  Max heart rate on file: %d" % max_hr)
    print()

    rows = []
    t0 = None
    for i, lap in enumerate(laps):
        index = lap.get("f254")
        if index is None:
            index = i
        z = by_lap.get(index)
        if z is None:
            continue
        start = lap.get("start_time")
        if t0 is None:
            t0 = start
        rows.append({
            "index": index,
            "kind": classify(lap),
            "offset": (start - t0) if (start is not None and t0 is not None) else 0,
            # Timer time, not elapsed. A lap's elapsed time includes any pause
            # taken inside it; its time_in_zone does not. Checked against the
            # recorded game: with timer time the two agree to under a second on
            # every one of the fifty laps, and with elapsed time one lap was out
            # by more than three minutes.
            "length": (lap.get("total_timer_time") or 0) / 1000.0,
            "avg_hr": lap.get("avg_heart_rate"),
            "max_hr": lap.get("max_heart_rate"),
            "zones": zone_seconds(z),
        })

    shown = [r for r in rows if args.all_laps or r["kind"] == "shift"]
    heading = "EVERY LAP" if args.all_laps else "SHIFTS"
    print(heading)
    print("   #  at       length  avg  max " +
          "".join("%6s" % ("Z%d" % (i + 1)) for i in range(5)) + "  zones")
    n = 0
    for r in shown:
        n += 1
        label = "%3d" % n if not args.all_laps else "%3d%s" % (n, r["kind"][0].upper())
        zs = r["zones"]
        cells = ""
        for i in range(5):
            v = zs[1 + i] if len(zs) > 1 + i else 0
            cells += "%6s" % (("%ds" % int(round(v))) if v >= 0.5 else "-")
        print("  %s  %-7s %6s  %3s  %3s %s  %s" % (
            label, clock(r["offset"]), clock(r["length"]),
            r["avg_hr"] if r["avg_hr"] is not None else "-",
            r["max_hr"] if r["max_hr"] is not None else "-",
            cells, bar(zs)))
    print()

    # The part that exists nowhere else.
    totals = {}
    for kind in ("shift", "bench"):
        acc = [0.0] * 7
        for r in rows:
            if r["kind"] != kind:
                continue
            for i, v in enumerate(r["zones"]):
                if i < 7:
                    acc[i] += v
        totals[kind] = acc

    print("ON THE ICE vs ON THE BENCH")
    print("  Garmin Connect cannot draw this: it does not know which laps were")
    print("  shifts. The app wrote that onto every lap, so this script does.")
    print()
    print("            total  " + "".join("%8s" % ("Z%d" % (i + 1)) for i in range(5)))
    for kind, label in (("shift", "Ice"), ("bench", "Bench")):
        acc = totals[kind]
        total = sum(acc)
        cells = "".join("%8s" % clock(acc[1 + i]) for i in range(5))
        print("  %-6s %8s  %s" % (label, clock(total), cells))

    if session_zone:
        acc = zone_seconds(session_zone)
        cells = "".join("%8s" % clock(acc[1 + i]) for i in range(5))
        print("  %-6s %8s  %s" % ("Game", clock(sum(acc)), cells))
        print()
        print("  The Game row is what Connect's zone chart shows. The two rows")
        print("  above it are the same seconds, split by where they were spent.")

    off = sum(totals["shift"][4:6])
    ice_total = sum(totals["shift"])
    if ice_total > 0:
        print()
        print("  Z4+Z5 on the ice: %s of %s (%.0f%% of ice time)" % (
            clock(off), clock(ice_total), 100.0 * off / ice_total))

    print()
    print("  Read the ice row as a claim about the DETECTOR as much as about")
    print("  the player: these are the laps the app decided were shifts. A")
    print("  missed line change moves seconds from one row to the other, and")
    print("  nothing in the file can tell you it happened. Compare the shift")
    print("  count above against what you remember before quoting any of it.")

    if args.csv:
        with open(args.csv, "w") as fh:
            fh.write("lap,kind,offset_s,length_s,avg_hr,max_hr," +
                     ",".join("z%d_s" % (i + 1) for i in range(5)) + "\n")
            for r in rows:
                zs = r["zones"]
                fh.write("%d,%s,%d,%d,%s,%s,%s\n" % (
                    r["index"], r["kind"], round(r["offset"]), round(r["length"]),
                    r["avg_hr"] if r["avg_hr"] is not None else "",
                    r["max_hr"] if r["max_hr"] is not None else "",
                    ",".join("%.1f" % (zs[1 + i] if len(zs) > 1 + i else 0)
                             for i in range(5))))
        print()
        print("Wrote %s" % args.csv)
    return 0


if __name__ == "__main__":
    sys.exit(main())
