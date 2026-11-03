#!/usr/bin/env bash
# Talk to a Garmin watch over USB: install a build, or pull recorded activities.
#
# Modern Garmin watches present as MTP, not as a USB drive, so this mounts
# them with jmtpfs. Older ones appear as a plain filesystem labelled GARMIN
# and are handled too.
#
#   tools/watch.sh detect
#   tools/watch.sh install IndoorHockey/bin/IndoorHockey.prg
#   tools/watch.sh pull <destination-dir>     # newest activities
set -u

MNT="${WATCH_MNT:-/tmp/garmin-watch}"

msg() { printf '%s\n' "$*" >&2; }

# Garmin spells these directories differently across models (APPS vs Apps,
# ACTIVITY vs Activity), so never hard-code the case.
subdir() {
    find "$1/GARMIN" -maxdepth 1 -type d -iname "$2" 2>/dev/null | head -1
}

find_massstorage() {
    lsblk -no LABEL,MOUNTPOINT 2>/dev/null | awk '$1=="GARMIN" && $2!="" {print $2; exit}'
}

mount_watch() {
    local ms
    ms="$(find_massstorage)"
    if [ -n "$ms" ]; then
        echo "$ms"; return 0
    fi
    if mountpoint -q "$MNT" 2>/dev/null; then
        echo "$MNT"; return 0
    fi
    mkdir -p "$MNT"
    if jmtpfs "$MNT" >/dev/null 2>&1 && [ -n "$(ls -A "$MNT" 2>/dev/null)" ]; then
        # The watch exposes one store; descend into it if that is the layout.
        local inner
        inner="$(find "$MNT" -maxdepth 2 -type d -name GARMIN 2>/dev/null | head -1)"
        if [ -n "$inner" ]; then echo "$(dirname "$inner")"; else echo "$MNT"; fi
        return 0
    fi
    return 1
}

unmount_watch() {
    mountpoint -q "$MNT" 2>/dev/null && fusermount -u "$MNT" 2>/dev/null
    return 0
}

case "${1:-detect}" in
detect)
    msg "== USB devices =="
    lsusb | grep -iE "garmin|0x091e|091e" || msg "no Garmin on the USB bus"
    msg ""
    msg "== MTP =="
    mtp-detect 2>&1 | grep -iE "device [0-9]|friendly|model|error|no raw dev" | head -8
    root="$(mount_watch)" || { msg "could not mount the watch"; exit 1; }
    msg ""
    msg "mounted at: $root"
    ls "$root" 2>/dev/null
    ls "$root/GARMIN" 2>/dev/null | head -20
    ;;
install)
    prg="${2:?usage: watch.sh install <file.prg>}"
    [ -f "$prg" ] || { msg "no such file: $prg"; exit 1; }
    root="$(mount_watch)" || { msg "could not mount the watch"; exit 1; }
    dest="$(subdir "$root" APPS)"
    [ -d "$dest" ] || { msg "no $dest on this device"; unmount_watch; exit 1; }
    cp -v "$prg" "$dest/" || { msg "copy failed"; unmount_watch; exit 1; }
    sync
    ls -la "$dest" | head
    unmount_watch
    msg "done - safely unplug the watch"
    ;;
pull)
    out="${2:?usage: watch.sh pull <dir>}"
    mkdir -p "$out"
    root="$(mount_watch)" || { msg "could not mount the watch"; exit 1; }
    src="$(subdir "$root" ACTIVITY)"
    [ -d "$src" ] || { msg "no $src on this device"; unmount_watch; exit 1; }
    ls -t "$src" | head -40 | while read -r f; do
        cp -n "$src/$f" "$out/" 2>/dev/null && msg "pulled $f"
    done
    unmount_watch
    ls -la "$out" | tail -10
    ;;
*)
    sed -n '2,12p' "$0"
    ;;
esac
