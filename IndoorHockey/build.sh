#!/usr/bin/env bash
# Compile Indoor Hockey for one device.
#   ./build.sh                 -> builds for fr57042mm
#   ./build.sh fenix847mm      -> builds for another device
#   TYPECHECK=3 ./build.sh     -> strict type checking
#   RELEASE=1 ./build.sh       -> release build, for handing to someone else
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

SDK=$(cat "$HOME/.Garmin/ConnectIQ/current-sdk.cfg")
DEVICE="${1:-fr57042mm}"
KEY="$HOME/.Garmin/ConnectIQ/keys/developer_key.der"
TYPECHECK="${TYPECHECK:-1}"

# A debug build records the absolute path of every source file, which on a
# binary that gets published means publishing the layout of the machine that
# built it. Release mode drops that along with the rest of the debug data, so
# anything leaving this machine is built with RELEASE=1.
RELEASE_FLAG=()
if [ -n "${RELEASE:-}" ]; then
  RELEASE_FLAG=(-r)
fi

if [ ! -d "$HOME/.Garmin/ConnectIQ/Devices/$DEVICE" ]; then
  echo "Device '$DEVICE' is not installed." >&2
  echo "Run ../tools/sdkmanager-docker/run.sh, sign in, and download it on the Devices tab." >&2
  exit 1
fi

mkdir -p bin
"$SDK/bin/monkeyc" \
  -o "bin/IndoorHockey.prg" \
  -d "$DEVICE" \
  -f "monkey.jungle;icons.jungle" \
  -y "$KEY" \
  -l "$TYPECHECK" \
  "${RELEASE_FLAG[@]}" \
  -w

echo "Built bin/IndoorHockey.prg for $DEVICE${RELEASE:+ (release)}"
