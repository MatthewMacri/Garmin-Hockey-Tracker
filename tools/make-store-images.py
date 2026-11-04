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
BODY = (26, 28, 33)
RIM = (205, 214, 224)

SS = 4   # supersample


def mark(draw, cx, cy, r):
    """The launcher icon at an arbitrary size: a puck inside the shift ring.

    Kept in the same proportions as tools/make-launcher-icons.py draws it, so
    the store artwork and the icon on the watch are the same mark rather than
    two drawings that drifted apart. r is the radius of the ring itself.
    """
    ring = max(1, int(r * 0.342))
    draw.arc([cx - r, cy - r, cx + r, cy + r], -215, 35, fill=GREEN, width=ring)
    pr = int(r * 0.711)
    draw.ellipse([cx - pr, cy - pr, cx + pr, cy + pr],
                 fill=BODY, outline=RIM, width=max(1, int(r * 0.092)))


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

    mark(d, w // 2, int(h * 0.40), int(w * 0.25))

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
    mark(d, col, int(h * 0.30), int(w * 0.072))

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
