#!/usr/bin/env python3
"""Write an overlay that blacks out the corners of a round watch screen.

The simulator draws a square framebuffer; on a round device the corners are
watch body, not display. Overlaying this mask on a screen recording leaves the
circular screen untouched and paints the corners black, which is what the
screenshots already do in simshot.py.
"""
import sys
from PIL import Image, ImageDraw

size = int(sys.argv[2]) if len(sys.argv) > 2 else 390
mask = Image.new("RGBA", (size, size), (0, 0, 0, 255))
ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=(0, 0, 0, 0))
mask.save(sys.argv[1])
print(f"{sys.argv[1]}: {size}x{size}")
