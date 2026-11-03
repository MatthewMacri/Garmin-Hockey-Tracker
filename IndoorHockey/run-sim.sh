#!/usr/bin/env bash
# Build Indoor Hockey and run it in the Connect IQ simulator on your desktop.
#   ./run-sim.sh               -> Forerunner 570 42mm
#   ./run-sim.sh venu3         -> some other watch
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

SDK=$(cat "$HOME/.Garmin/ConnectIQ/current-sdk.cfg")
DEVICE="${1:-fr57042mm}"
# Defaults to :1, which on a headless box is typically a virtual display (Xvfb)
# fronted by VNC. Export DISPLAY yourself to target a different screen.
export DISPLAY="${DISPLAY:-:1}"

./build.sh "$DEVICE"

# Reuse a simulator that is already open, otherwise start one and give it a
# moment to come up before pushing the app to it.
if ! pgrep -u "$(id -u)" -f "$SDK/bin/simulator" >/dev/null 2>&1; then
  echo "Starting the simulator on display $DISPLAY..."
  "$SDK/bin/connectiq" >/dev/null 2>&1 &
  for _ in $(seq 1 40); do
    pgrep -u "$(id -u)" -f "$SDK/bin/simulator" >/dev/null 2>&1 && break
    sleep 0.5
  done
  sleep 2
fi

"$SDK/bin/monkeydo" bin/IndoorHockey.prg "$DEVICE"
