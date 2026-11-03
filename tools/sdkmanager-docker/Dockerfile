# Runs the Garmin Connect IQ SDK Manager AND the simulator, both of which need
# webkit2gtk-4.0 (libsoup2).
# Ubuntu 24.04 only ships webkit2gtk-4.1 (libsoup3), and mixing the two aborts,
# so the manager runs inside jammy and writes device files to the host ~/.Garmin.
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      libwebkit2gtk-4.0-37 \
      libjavascriptcoregtk-4.0-18 \
      libsoup2.4-1 \
      libgtk-3-0 \
      libcanberra-gtk3-module \
      libnotify4 \
      dbus-x11 \
      ca-certificates \
      unzip \
      curl \
      xdg-utils \
      fonts-dejavu-core \
      libgl1 \
      libegl1 \
      libsm6 \
      libice6 \
      libxt6 \
      libxtst6 \
      libxss1 \
      libasound2 \
      libusb-1.0-0 \
    && rm -rf /var/lib/apt/lists/*
ENV WEBKIT_DISABLE_COMPOSITING_MODE=1
ENV GDK_BACKEND=x11
