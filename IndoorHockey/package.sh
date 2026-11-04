#!/usr/bin/env bash
# Build the Connect IQ store package: every device in the manifest, release
# mode, signed with the developer key.
#
# This is what gets uploaded to https://apps-developer.garmin.com - not the
# .prg, which is a single-device build for sideloading.
#
# It builds from a staging copy at a neutral path, and that is the whole
# reason this script exists rather than a one-line monkeyc call.
#
# A store package carries a debug.xml per device - Garmin uses it to turn a
# crash report back into line numbers - and that file records the absolute
# path of every source file, 849 times over, in all 202 of them. Release mode
# strips those paths from the .prg and does nothing for the .iq. Building from
# a copy under a path that names nobody means the upload carries build paths
# that are true and say nothing about the machine that produced it.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
SRC="$PWD"

SDK=$(cat "$HOME/.Garmin/ConnectIQ/current-sdk.cfg")
KEY="$HOME/.Garmin/ConnectIQ/keys/developer_key.der"
STAGE="${CIQ_STAGE:-/tmp/ciq-build}/IndoorHockey"

rm -rf "$STAGE"
mkdir -p "$STAGE"
# Sources and resources only. No bin/, no VCS, nothing local.
for item in source resources resources-* monkey.jungle icons.jungle manifest.xml; do
  [ -e "$item" ] && cp -r "$item" "$STAGE/"
done

mkdir -p "$SRC/bin"
(
  cd "$STAGE"
  # -e packages for the store, -r strips debug data from the executables.
  "$SDK/bin/monkeyc" \
    -o "$SRC/bin/IndoorHockey.iq" \
    -f "monkey.jungle;icons.jungle" \
    -y "$KEY" \
    -l 1 \
    -e -r -w
)

rm -rf "$STAGE"
echo "Built bin/IndoorHockey.iq"
ls -lh "$SRC/bin/IndoorHockey.iq"
