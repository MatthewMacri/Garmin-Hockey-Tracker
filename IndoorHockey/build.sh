#!/usr/bin/env bash
# Compile Indoor Hockey for one device.
#   ./build.sh                 -> builds for fr57042mm
#   ./build.sh fenix847mm      -> builds for another device
#   TYPECHECK=3 ./build.sh     -> strict type checking
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

SDK=$(cat "$HOME/.Garmin/ConnectIQ/current-sdk.cfg")
DEVICE="${1:-fr57042mm}"
KEY="$HOME/.Garmin/ConnectIQ/keys/developer_key.der"
TYPECHECK="${TYPECHECK:-1}"

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
  -w

echo "Built bin/IndoorHockey.prg for $DEVICE"
