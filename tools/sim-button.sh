#!/usr/bin/env bash
# Click a simulator bezel button by name.  btn.sh START|BACK|UP|DOWN
export DISPLAY=:1
W=$(xdotool search --name "CIQ Simulator" | head -1)
eval "$(xdotool getwindowgeometry --shell "$W")"
case "$1" in
  START) rx=565; ry=341 ;;
  BACK)  rx=565; ry=577 ;;
  UP)    rx=84;  ry=414 ;;
  DOWN)  rx=84;  ry=561 ;;
  *) echo "unknown button $1" >&2; exit 1 ;;
esac
xdotool windowactivate --sync "$W"
xdotool mousemove $((X+rx)) $((Y+ry)) click 1
