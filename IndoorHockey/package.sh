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
# path of every source file, hundreds of times over, in every one of the 202
# device variants the 126 manifest products expand to. Release mode
# strips those paths from the .prg and does nothing for the .iq. Building from
# a copy under a path that names nobody means the upload carries build paths
# that are true and say nothing about the machine that produced it.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
SRC="$PWD"

SDK=$(cat "$HOME/.Garmin/ConnectIQ/current-sdk.cfg")
KEY="$HOME/.Garmin/ConnectIQ/keys/developer_key.der"
STAGE="${CIQ_STAGE:-$(mktemp -d)}/IndoorHockey"

if [ ! -f "$KEY" ]; then
  echo "No developer key at $KEY." >&2
  echo "Without it monkeyc fails with a 60-line usage dump that does not say so." >&2
  exit 1
fi

# A failed build used to leave the whole staged source tree behind in /tmp.
cleanup() { rm -rf "$(dirname "$STAGE")"; }
trap cleanup EXIT

mkdir -p "$STAGE"
# Everything but the things that must not ship: build output, VCS, scripts.
# An explicit allow-list was used here before and silently dropped anything
# whose name did not match, which for a resource directory means a device
# quietly losing its icons.
tar -cf - \
  --exclude=./bin --exclude=./dist --exclude=./.git \
  --exclude='./*.sh' --exclude=./README.md \
  . | tar -xf - -C "$STAGE"

# Only the file that is meant to be uploaded, so nothing else in bin/ can be
# attached to a release by mistake - the debug sidecars there do carry paths.
DIST="$SRC/dist"
rm -rf "$DIST"
mkdir -p "$DIST"
(
  cd "$STAGE"
  # -e packages for the store, -r strips debug data from the executables.
  "$SDK/bin/monkeyc" \
    -o "$DIST/IndoorHockey.iq" \
    -f "monkey.jungle;icons.jungle" \
    -y "$KEY" \
    -l 1 \
    -e -r -w
)

# Fail loudly rather than hand over a package that still carries the paths.
#
# The .iq must be unpacked to check it. It is a 7-zip archive, so grepping the
# file itself finds nothing whatever it contains - a check that passes for the
# wrong reason is worse than no check, and this one passed on the build that
# leaked. 7z is required rather than optional for the same reason: silently
# skipping the check is how the leak shipped the first time.
if ! command -v 7z >/dev/null 2>&1; then
  echo "7z is needed to verify the package does not leak build paths." >&2
  echo "Install it (apt install p7zip-full) and run this again." >&2
  exit 1
fi

VERIFY="$(mktemp -d)"
trap 'cleanup; rm -rf "$VERIFY"' EXIT
7z x -o"$VERIFY" "$DIST/IndoorHockey.iq" >/dev/null
if grep -rqa "$HOME" "$VERIFY"; then
  echo "Package contains the builder's home path - refusing to ship it." >&2
  grep -rla "$HOME" "$VERIFY" | head -3 >&2
  exit 1
fi
echo "Verified: no build paths in $(find "$VERIFY" -type f | wc -l) packaged files."

echo "Built dist/IndoorHockey.iq"
ls -lh "$DIST/IndoorHockey.iq"
