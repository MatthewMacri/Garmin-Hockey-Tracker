#!/usr/bin/env bash
# Capture the six store screenshots by driving the app in the simulator.
#
#   tools/make-screenshots.sh
#
# Needs the simulator running the current build and sitting on READY:
#   cd IndoorHockey && $SDK/bin/monkeydo bin/IndoorHockey.prg fr57042mm
#
# Why the game is driven rather than left to run: the app reads raw
# accelerometer samples and the simulator delivers a flat zero, so the detector
# correctly decides nobody is skating and backdates every shift away. Left
# alone the summary reads Ice 0:00 and Work:Rest --, which is what the store
# was sent. Lapping every 8s is inside the detector's 10-sample confirmation
# and resets its streak, so the lap key's own boundaries are what land in the
# totals. Nothing on screen is faked; it is the app's own arithmetic.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
export DISPLAY="${DISPLAY:-:1}"

OUT=docs/screenshots
mkdir -p "$OUT"
press() { tools/sim-button.sh "$1" >/dev/null 2>&1; }
shot()  { python3 tools/simshot.py "$OUT/$1" ${2:-}; }   # exits non-zero if misaligned

shot 01-ready.png

press START
# Build a few real shifts so the totals on screen are worth showing.
for _ in $(seq 4); do sleep 8; press BACK; done     # ends on the bench
sleep 4
shot 03-bench.png

press BACK; sleep 9                                  # back on the ice
shot 02-on-ice.png

press START; sleep 2
shot 04-press-again.png

press START; sleep 2
shot 05-menu.png --no-rim-check    # a system menu fills the screen to its edge

press DOWN;  sleep 2
press START; sleep 2
press DOWN;  sleep 2
press START; sleep 4
shot 06-summary.png

echo
ls -la "$OUT"
