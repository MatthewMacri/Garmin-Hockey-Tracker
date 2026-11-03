#!/usr/bin/env bash
# Opens the Garmin Connect IQ SDK Manager window on your desktop.
#
# Why Docker: the SDK Manager links webkit2gtk-4.0 (libsoup2), Ubuntu 24.04 only
# ships webkit2gtk-4.1 (libsoup3), and loading both in one process aborts. The
# manager therefore runs inside Ubuntu 22.04 but reads and writes the real
# ~/.Garmin on this machine, so downloaded device files land where monkeyc
# and the simulator look for them.
#
# Sign in with your Garmin account, then on the Devices tab download at least
# "Forerunner 570 42mm". Close the window when the downloads finish.
set -euo pipefail

IMAGE=ciq-sdkmanager:jammy

# Defaults to :1, which on a headless box is typically a virtual display (Xvfb)
# fronted by VNC. Export DISPLAY yourself to target a different screen.
export DISPLAY="${DISPLAY:-:1}"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Building $IMAGE (one time)..."
  docker build -t "$IMAGE" "$(dirname "$(readlink -f "$0")")"
fi

# Give the container access to this X display without opening it to the world.
XAUTH=$(mktemp /tmp/.ciq-xauth.XXXXXX)
if command -v xauth >/dev/null 2>&1; then
  xauth nlist "$DISPLAY" 2>/dev/null | sed -e 's/^..../ffff/' | xauth -f "$XAUTH" nmerge - 2>/dev/null || true
fi
chmod 644 "$XAUTH"
trap 'rm -f "$XAUTH"' EXIT

# -t only when there is a terminal, so this also works launched in the background.
TTY_FLAGS=(-i)
[ -t 0 ] && TTY_FLAGS+=(-t)

docker run --rm "${TTY_FLAGS[@]}" \
  --network host \
  --user "$(id -u):$(id -g)" \
  -e HOME="$HOME" \
  -e DISPLAY="$DISPLAY" \
  -e XAUTHORITY=/tmp/.ciq-xauth \
  -v "$XAUTH:/tmp/.ciq-xauth:ro" \
  -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
  -v "$HOME/.Garmin:$HOME/.Garmin" \
  -v /etc/passwd:/etc/passwd:ro \
  -v /etc/group:/etc/group:ro \
  "$IMAGE" \
  "$HOME/.Garmin/ConnectIQ/sdk-manager/bin/sdkmanager"
