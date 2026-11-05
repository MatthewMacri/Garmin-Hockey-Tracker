#!/usr/bin/env bash
# Click a simulator bezel button by name.
#   tools/sim-button.sh START|BACK|UP|DOWN|LIGHT
#   tools/sim-button.sh UP hold     # long press, for the in-game menu
export DISPLAY="${DISPLAY:-:1}"
W=$(xdotool search --name "CIQ Simulator" | head -1)

# xwininfo gives the CLIENT origin; xdotool getwindowgeometry gives the window
# manager FRAME, and the two are 20px apart vertically. These offsets were
# measured against a client-area capture (import -window), so they have to be
# added to the client origin. Using the frame origin here is what left UP
# landing in dead bezel and the in-game menu untestable.
CX=$(xwininfo -id "$W" | awk '/Absolute upper-left X/{print $4}')
CY=$(xwininfo -id "$W" | awk '/Absolute upper-left Y/{print $4}')

# Measured off a client-area capture of the window by cropping the two bezel
# strips at 3x with a 20px grid drawn over them, and reading the centre of each
# protruding nub. START and UP were already right; BACK and DOWN were not, and
# both were wrong in the direction that lands on bezel rather than on a button
# - so they did nothing at all, silently, and every "verified in the simulator"
# claim that depended on them was worth nothing. Check a new button by pressing
# it and watching the screen change, never by pressing it and assuming.
case "$1" in
  START) rx=570; ry=325 ;;
  BACK)  rx=566; ry=583 ;;
  UP)    rx=58;  ry=458 ;;
  DOWN)  rx=112; ry=590 ;;
  LIGHT) rx=110; ry=318 ;;
  *) echo "unknown button $1" >&2; exit 1 ;;
esac

xdotool windowactivate --sync "$W"
if [ "${2:-}" = "hold" ]; then
    # A long press is how this watch reaches the in-game menu. Two seconds is
    # comfortably past the threshold without being slow to run.
    xdotool mousemove $((CX+rx)) $((CY+ry)) mousedown 1
    sleep 2
    xdotool mouseup 1
else
    xdotool mousemove $((CX+rx)) $((CY+ry)) click 1
fi
