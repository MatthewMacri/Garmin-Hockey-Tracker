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

case "$1" in
  START) rx=564; ry=321 ;;
  BACK)  rx=564; ry=557 ;;
  UP)    rx=65;  ry=452 ;;
  DOWN)  rx=83;  ry=541 ;;
  LIGHT) rx=100; ry=318 ;;
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
