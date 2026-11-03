#!/usr/bin/env bash
# Run the Connect IQ simulator inside the jammy container.
#
# The simulator links webkit2gtk-4.0 just like the SDK Manager does, so it
# cannot run natively on Ubuntu 24.04 either. --network host is what lets
# monkeydo, running on the host, reach the simulator's socket on localhost.
set -euo pipefail

IMAGE=ciq-sdkmanager:jammy
export DISPLAY="${DISPLAY:-:1}"
SDK=$(cat "$HOME/.Garmin/ConnectIQ/current-sdk.cfg")

TTY_FLAGS=(-i)
[ -t 0 ] && TTY_FLAGS+=(-t)

exec docker run --rm "${TTY_FLAGS[@]}" \
  --name ciq-simulator \
  --network host \
  --user "$(id -u):$(id -g)" \
  -e HOME="$HOME" \
  -e DISPLAY="$DISPLAY" \
  -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
  -v "$HOME/.Garmin:$HOME/.Garmin" \
  -v "$HOME/projects/Garmin:$HOME/projects/Garmin" \
  -v /etc/passwd:/etc/passwd:ro \
  -v /etc/group:/etc/group:ro \
  "$IMAGE" \
  "$SDK/bin/simulator"
