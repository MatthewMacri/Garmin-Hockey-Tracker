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
    args = sys.argv[1:]
    # The rim check below assumes the app's own black margin at the edge of the
    # screen. A system menu draws its backdrop right to the edge, so the check
    # has to be waived for those - the alignment is the same for every capture
    # in a run, and the other shots still assert it.
    rim_check = True
    if "--no-rim-check" in args:
        args.remove("--no-rim-check")
        rim_check = False
    out = args[0]
    size = int(args[1]) if len(args) > 1 else DEFAULT_SIZE
    x = int(args[2]) if len(args) > 2 else DEFAULT_X
    y = int(args[3]) if len(args) > 3 else DEFAULT_Y

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

    # Guard against a crop that has slipped off the watch face. A correctly
    # placed crop is the screen plus four corners of bezel, and the mask above
    # removes the corners; a slipped one leaves a grey crescent of bezel inside
    # the mask, around the rim. The app's own ring track sits at about 0.96 of
    # the radius and is grey too, so the band is measured where only bezel can
    # be: outside the track, inside the mask.
    import numpy as np
    a = np.asarray(shot, dtype=np.float32)
    c = (size - 1) / 2.0
    yy, xx = np.mgrid[0:size, 0:size]
    rr = np.hypot(xx - c, yy - c) / (size / 2.0)
    edge = a[(rr >= 0.985) & (rr <= 1.0)].mean()
    if rim_check and edge > 12.0:
        sys.exit(f"crop has slipped off the watch face: rim reads {edge:.1f}, "
                 f"expected near zero. Re-measure the offset (see above).")

    shot.save(out)
    print(f"{out}: {size}x{size}  rim {edge:.2f}")


if __name__ == "__main__":
    main()
