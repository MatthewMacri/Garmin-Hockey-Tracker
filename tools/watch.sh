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
    # Two different things make the first mount fail, and they look identical.
    #
    # Only one process may hold an MTP device at a time. On a machine with a
    # desktop session, gvfs grabs the watch the moment it is plugged in, and
    # then jmtpfs and mtp-detect both fail with "Unable to open raw device 0",
    # which reads like a broken cable rather than a daemon holding the handle.
    #
    # The watch also re-enumerates on its own - it drops off the bus and comes
    # back with a new device number - so a mount can fail several times and
    # then succeed with nothing changed. Retrying is the fix; giving up after
    # one attempt reports a healthy watch as broken.
    local mounted=0 attempt
    for attempt in 1 2 3 4 5 6; do
        if jmtpfs "$MNT" >/dev/null 2>&1 && [ -n "$(ls -A "$MNT" 2>/dev/null)" ]; then
            mounted=1; break
        fi
        fusermount -u "$MNT" 2>/dev/null
        if pgrep -x gvfsd-mtp >/dev/null 2>&1; then
            msg "gvfsd-mtp is holding the watch; releasing it"
            pkill -x gvfsd-mtp
        fi
        lsusb 2>/dev/null | grep -qiE 'garmin|091e' \
            || msg "attempt $attempt: watch is not on the USB bus"
        sleep 4
    done
    if [ "$mounted" != 1 ]; then
        msg "could not mount the watch after 6 attempts."
        msg "Check it is plugged in and awake, then run this again."
        return 1
    fi
    # The watch exposes one store ("Internal Storage"); descend into it if that
    # is the layout, so callers always get the directory holding GARMIN.
    local inner
    inner="$(find "$MNT" -maxdepth 2 -type d -name GARMIN 2>/dev/null | head -1)"
    if [ -n "$inner" ]; then echo "$(dirname "$inner")"; else echo "$MNT"; fi
    return 0
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
