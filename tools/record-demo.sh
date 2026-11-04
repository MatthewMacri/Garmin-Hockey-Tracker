#!/usr/bin/env bash
# Record the store demo: drive the app in the simulator and capture the screen.
#
# The previous demo was made by hand, which is why it went stale the moment the
# app changed and nobody noticed until the store asked for a video. This script
# exists so re-recording is one command after a behaviour change.
#
#   tools/record-demo.sh                # record and encode
#   tools/record-demo.sh --encode-only  # re-encode the last raw capture
#
# It needs the simulator already running with the current build, freshly
# started so the app is on its READY screen:
#   cd IndoorHockey && $SDK/bin/monkeydo bin/IndoorHockey.prg fr57042mm
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."

export DISPLAY="${DISPLAY:-:1}"
OUT=store/video
WORK="${DEMO_WORK:-/tmp/ciq-demo}"
RAW="$WORK/raw.mkv"
SIZE=390                      # FR570 screen, drawn 1:1
OFFX=133; OFFY=265            # where the screen sits inside the sim window
FPS=15

mkdir -p "$WORK" "$OUT"
press() { tools/sim-button.sh "$1" >/dev/null 2>&1; }

if [ "${1:-}" != "--encode-only" ]; then
    WID=$(xdotool search --name "CIQ Simulator" | head -1)
    [ -n "$WID" ] || { echo "no CIQ Simulator window on $DISPLAY" >&2; exit 1; }

    # xwininfo, not xdotool: xdotool reports the window manager's frame, which
    # sits 20px above the client area here. Recording from the frame origin
    # shifts the watch face inside the capture, and the round mask applied
    # below then cuts across the screen instead of landing on the bezel.
    CX=$(xwininfo -id "$WID" | awk '/Absolute upper-left X/{print $4}')
    CY=$(xwininfo -id "$WID" | awk '/Absolute upper-left Y/{print $4}')
    python3 tools/make-round-mask.py "$WORK/mask.png" "$SIZE" >/dev/null

    # -draw_mouse 0 because the buttons are clicked with the pointer, and a
    # cursor skating across the watch face would be in every frame.
    ffmpeg -y -loglevel error -f x11grab -draw_mouse 0 -framerate "$FPS" \
        -video_size "${SIZE}x${SIZE}" \
        -i "${DISPLAY}+$((CX+OFFX)),$((CY+OFFY))" \
        -c:v libx264 -preset ultrafast -qp 0 "$RAW" &
    FFPID=$!
    trap 'kill $FFPID 2>/dev/null || true' EXIT

    # The choreography. Timings are load-bearing: encode() slices the capture
    # at these marks, so changing a sleep means changing the matching trim.
    sleep 3                       # 0-3   READY
    press START                   # 3     the only press a real game needs

    # 3-57: play, driven by the lap key.
    #
    # The app reads raw accelerometer samples, and the simulator delivers a
    # flat zero: there is no wrist motion to detect, so the detector correctly
    # decides the player is sitting down, and backdates each confirmed change
    # to when the motion actually stopped. In the simulator that is always
    # "immediately", so every shift is erased as soon as it is banked and the
    # recording ends on a summary reading Ice 0:00. Nothing is wrong with the
    # app; there is simply nothing for it to detect.
    #
    # Lapping every 8s is below the detector's 10-sample confirmation, and a
    # manual switch resets the streak, so the detector never reaches a verdict
    # and never backdates. What lands in the summary is the lap key's own
    # boundaries - a real feature, honestly recorded - instead of a flat zero.
    for _ in $(seq 6); do
        sleep 8
        press BACK
    done
    sleep 6

    press START; sleep 4          # 57-61 first press: PRESS AGAIN
    press START; sleep 4          # 61-65 second press: the stop menu
    press DOWN;  sleep 4          # 65-69 End & Save Game
    press START; sleep 4          # 69-73 the confirmation
    press DOWN;  sleep 3          # 73-76 Confirm
    press START; sleep 10         # 76-86 the saved summary

    kill -INT $FFPID 2>/dev/null || true
    wait $FFPID 2>/dev/null || true
    trap - EXIT
fi

[ -f "$RAW" ] || { echo "no capture at $RAW" >&2; exit 1; }
python3 tools/make-round-mask.py "$WORK/mask.png" "$SIZE" >/dev/null

# Play is sped up hard, anything with a button press stays readable. A single
# uniform speed cannot do both: fast enough to sit through the shifts is too
# fast to read the confirmation.
SPEED="
[0:v]trim=0:3,setpts=(PTS-STARTPTS)/1[a];
[0:v]trim=3:57,setpts=(PTS-STARTPTS)/4[b];
[0:v]trim=57:86,setpts=(PTS-STARTPTS)/2[c];
[a][b][c]concat=n=3:v=1:a=0[sped];
[sped][1:v]overlay=0:0[masked]
"

# Square: the watch screen alone.
ffmpeg -y -loglevel error -i "$RAW" -i "$WORK/mask.png" -filter_complex \
    "${SPEED};[masked]scale=780:780:flags=lanczos[v]" \
    -map "[v]" -r "$FPS" -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p \
    -movflags +faststart "$OUT/demo-square-780.mp4"

# 1080p: the same square centred on black, which is what the store wants.
ffmpeg -y -loglevel error -i "$RAW" -i "$WORK/mask.png" -filter_complex \
    "${SPEED};[masked]scale=1000:1000:flags=lanczos,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black[v]" \
    -map "[v]" -r "$FPS" -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p \
    -movflags +faststart "$OUT/demo-1080p.mp4"

# Poster: a frame with a shift actually running, not the READY screen or a
# bench spell - the thumbnail should show the app mid-shift.
ffmpeg -y -loglevel error -ss 8 -i "$OUT/demo-1080p.mp4" -frames:v 1 -q:v 3 \
    "$OUT/poster-1080p.jpg"

# README GIF: smaller and slower-framed, since it autoplays on the page.
ffmpeg -y -loglevel error -i "$OUT/demo-square-780.mp4" \
    -vf "fps=10,scale=420:420:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3" \
    docs/demo.gif

ls -lh "$OUT"/demo-*.mp4 "$OUT"/poster-1080p.jpg docs/demo.gif
