#!/usr/bin/env python3
"""Grab the watch screen out of the Connect IQ simulator, without the bezel.

The simulator draws the device screen 1:1 inside a picture of the watch, so a
plain window grab is mostly watch body and strap. Store listings and the README
want the screen alone.

    python3 tools/simshot.py out.png              # FR570, default window
    python3 tools/simshot.py out.png 390 133 265  # size and offset

To re-measure the offset after changing device or simulator zoom, make the app
fill the screen with one colour, grab the window, and take the bounding box of
that colour.
"""
import subprocess
import sys
from PIL import Image, ImageDraw

DEFAULT_SIZE = 390      # FR570 resolution
DEFAULT_X, DEFAULT_Y = 133, 265


def main():
    out = sys.argv[1]
    size = int(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_SIZE
    x = int(sys.argv[3]) if len(sys.argv) > 3 else DEFAULT_X
    y = int(sys.argv[4]) if len(sys.argv) > 4 else DEFAULT_Y

    wid = subprocess.run(["xdotool", "search", "--name", "CIQ Simulator"],
                         capture_output=True, text=True).stdout.split()
    if not wid:
        sys.exit("no CIQ Simulator window on $DISPLAY")

    tmp = "/tmp/_simshot.png"
    subprocess.run(["import", "-window", wid[0], tmp], check=True)
    shot = Image.open(tmp).convert("RGB").crop((x, y, x + size, y + size))

    # A round display's corners are not display at all - the simulator shows
    # the watch body through them, button labels and all. Black them out so the
    # result is the screen and nothing else.
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    shot = Image.composite(shot, Image.new("RGB", (size, size), (0, 0, 0)), mask)

    shot.save(out)
    print(f"{out}: {size}x{size}")


if __name__ == "__main__":
    main()
