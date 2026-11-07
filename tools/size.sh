#!/usr/bin/env bash
# What the app costs on the tightest device it supports.
#
# This script exists because the figure was published wrong three times in one
# day, the same way each time: measured by hand, then more code was written
# before the commit was made, and the number in the release notes described a
# tree that no longer existed. Measuring from a git ref removes the window.
#
#   tools/size.sh              # the working tree
#   tools/size.sh v2.5.2       # any tag, branch or commit
#   tools/size.sh v2.4.0 v2.5.2 HEAD
#
# Release builds only. A debug build's data segment carries the build
# directory's PATH and grows ~8 bytes per character of it, so a debug size is a
# property of where it was built and not of the commit - which is how a 512 B
# difference between two worktrees once got published as a release's worth of
# code.
set -eu

SDK="${SDK:-$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.3.0-2026-10-20-95888f262}"
KEY="${KEY:-$HOME/.Garmin/ConnectIQ/keys/developer_key.der}"
# watch-app, not datafield: the manifest declares type="watch-app", and the two
# have different limits on the same hardware. 98,304 B is a five-way tie -
# descentg1, instinct2, instinct2s, instinct2x and instinctcrossover all
# compile byte-identically - so "instinct2 and its siblings" is the honest
# phrase, not "instinct2".
DEVICE="${DEVICE:-instinct2}"
LIMIT=98304

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; git -C "$ROOT" worktree prune >/dev/null 2>&1 || true' EXIT

[ -x "$SDK/bin/monkeyc" ] || { echo "No SDK at $SDK" >&2; exit 1; }
[ -f "$KEY" ] || { echo "No signing key at $KEY" >&2; exit 1; }

measure() {   # <source-dir> -> "total code data"
    "$SDK/bin/monkeyc" -d "$DEVICE" -f "monkey.jungle;icons.jungle" \
        -o "$TMP/out.prg" -y "$KEY" -r --build-stats 0 2>&1 \
        | awk '/Code:/{c=$2} /Data:/{d=$2} /Total:/{t=$2} END{print t, c, d}'
}

printf '%-12s %10s %10s %10s %8s\n' ref total code data "of $LIMIT"

report() {    # <label> <dir>
    local out total code data
    out="$(cd "$2/IndoorHockey" && measure .)"
    read -r total code data <<<"$out"
    [ -n "${total:-}" ] || { echo "$1: build failed" >&2; return 1; }
    printf '%-12s %10s %10s %10s %7.1f%%\n' \
        "$1" "$total" "$code" "$data" \
        "$(awk -v t="$total" -v l="$LIMIT" 'BEGIN{printf "%.1f", 100*t/l}')"
}

if [ "$#" -eq 0 ]; then
    report "(worktree)" "$ROOT"
    exit 0
fi

for ref in "$@"; do
    wt="$TMP/wt-$(echo "$ref" | tr -c 'A-Za-z0-9._-' '_')"
    git -C "$ROOT" worktree add -q --detach "$wt" "$ref"
    report "$ref" "$wt"
    git -C "$ROOT" worktree remove --force "$wt"
done
