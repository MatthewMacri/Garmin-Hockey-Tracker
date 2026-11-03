#!/usr/bin/env python3
"""Draw the Connect IQ Store's cover and hero images.

The store asks for a 500x500 cover (under 300 KB) and an optional 1440x720
hero (under 2 MB). Both are generated rather than hand-made so they stay in
step with the launcher icon.

    python3 tools/make-store-images.py
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "store", "images")

BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

BG = (14, 16, 20)
FACE = (236, 240, 244)
SIDE = (90, 101, 114)
EDGE = (10, 12, 15)
GREEN = (0, 200, 120)
DIM = (150, 160, 172)

SS = 4   # supersample


def puck(draw, cx, cy, half_width, ss=1):
    """The same puck as the launcher icon, at an arbitrary size."""
    rx = half_width
    ry = int(rx * 0.39)
    depth = int(rx * 0.52)
    top, bot = cy - depth // 2, cy + depth // 2
    line = max(1, int(rx * 0.055))
    draw.ellipse([cx - rx, bot - ry, cx + rx, bot + ry], fill=SIDE, outline=EDGE, width=line)
    draw.rectangle([cx - rx, top, cx + rx, bot], fill=SIDE)
    draw.line([cx - rx, top, cx - rx, bot], fill=EDGE, width=line)
    draw.line([cx + rx, top, cx + rx, bot], fill=EDGE, width=line)
    draw.ellipse([cx - rx, top - ry, cx + rx, top + ry], fill=FACE, outline=EDGE, width=line)


def centred(draw, text, font, cy, width, fill, cx=None):
    l, t, r, b = draw.textbbox((0, 0), text, font=font)
    x = (width // 2 if cx is None else cx) - (r - l) // 2 - l
    draw.text((x, cy - (b - t) // 2 - t), text, font=font, fill=fill)


def round_shot(path, size):
    """A screenshot as a circle, so it sits on the background with no box."""
    s = Image.open(path).convert("RGB").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(s, (0, 0), mask)
    return out


def cover(path):
    w = h = 500 * SS
    img = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(img)

    # A shift ring round the edge, the app's one visual signature, drawn as the
    # period clock draws it: most of the way round, and green.
    # Only over the puck: a ring sweeping behind the wordmark reads as clutter.
    pad = int(30 * SS)
    d.arc([pad, pad, w - pad, h - pad], start=183, end=357, fill=GREEN, width=int(10 * SS))

    puck(d, w // 2, int(h * 0.44), int(w * 0.255))

    title = ImageFont.truetype(BOLD, int(46 * SS))
    sub = ImageFont.truetype(REG, int(23 * SS))
    centred(d, "ICE HOCKEY", title, int(h * 0.705), w, FACE)
    centred(d, "SHIFTS", title, int(h * 0.795), w, FACE)
    centred(d, "hands-free shift tracking", sub, int(h * 0.885), w, DIM)

    img.resize((500, 500), Image.LANCZOS).save(path, optimize=True)
    print(f"{path}: 500x500, {os.path.getsize(path)//1024} KB")


def hero(path, shots):
    w, h = 1440 * SS, 720 * SS
    img = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(img)

    margin = int(40 * SS)
    split = int(w * 0.34)          # where the screenshots begin
    col = split // 2               # centre of the left column

    # Right: the screens, sized to the space left rather than to the canvas,
    # so adding or removing one cannot push the last off the edge.
    gap_frac = 0.12
    avail = w - split - margin
    size = int(avail / (len(shots) + (len(shots) - 1) * gap_frac))
    gap = int(size * gap_frac)
    span = len(shots) * size + (len(shots) - 1) * gap
    x = split + (avail - span) // 2
    for shot in shots:
        s = round_shot(shot, size)
        img.paste(s, (x, (h - size) // 2), s)
        x += size + gap

    # Left: the mark over the wordmark, both centred on the column.
    puck_y = int(h * 0.30)
    r = int(w * 0.048)
    d.arc([col - int(r * 1.6), puck_y - int(r * 1.6), col + int(r * 1.6), puck_y + int(r * 1.6)],
          start=183, end=357, fill=GREEN, width=int(7 * SS))
    puck(d, col, puck_y, r)

    title = ImageFont.truetype(BOLD, int(44 * SS))
    sub = ImageFont.truetype(REG, int(23 * SS))
    centred(d, "ICE HOCKEY", title, int(h * 0.595), w, FACE, cx=col)
    centred(d, "SHIFTS", title, int(h * 0.675), w, FACE, cx=col)
    centred(d, "One press at the faceoff.", sub, int(h * 0.775), w, DIM, cx=col)
    centred(d, "It does the rest.", sub, int(h * 0.830), w, DIM, cx=col)

    img.resize((1440, 720), Image.LANCZOS).save(path, quality=92, optimize=True)
    print(f"{path}: 1440x720, {os.path.getsize(path)//1024} KB")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    shots = [os.path.join(ROOT, "docs/screenshots", n)
             for n in ("02-on-ice.png", "03-bench.png", "06-summary.png")]
    cover(os.path.join(OUT, "cover-500x500.png"))
    hero(os.path.join(OUT, "hero-1440x720.jpg"), shots)
