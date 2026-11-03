#!/usr/bin/env bash
# Build the Connect IQ Store package (.iq) - the file you upload to the
# developer dashboard at apps.garmin.com. Unlike build.sh, which builds for one
# device, this compiles for every product in manifest.xml, so it is slow and it
# fails if any single device is missing locally or breaks the layout.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

SDK=$(cat "$HOME/.Garmin/ConnectIQ/current-sdk.cfg")
KEY="$HOME/.Garmin/ConnectIQ/keys/developer_key.der"

mkdir -p bin
"$SDK/bin/monkeyc" \
  -e \
  -o "bin/IndoorHockey.iq" \
  -f "monkey.jungle;icons.jungle" \
  -y "$KEY" \
  -l "${TYPECHECK:-1}" \
  -w

echo
echo "Built bin/IndoorHockey.iq - upload this at"
echo "  https://apps.garmin.com/en-US/developer/upload"
echo "  (dashboard: https://apps-developer.garmin.com)"
