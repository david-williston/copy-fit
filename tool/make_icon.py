"""Generate the Copy Fit launcher icon and README logo.

Run from anywhere; paths resolve relative to the repository:

    python3 tool/make_icon.py

Needs Pillow (`pip install Pillow`). Writes every density of the adaptive-icon
foreground and the legacy launcher icon into android/app/src/main/res, plus
docs/logo.png. The adaptive background is not generated here: it is
drawable/ic_launcher_background.xml, whose two colours must match BLUE_HI and
BLUE_LO below.

After writing, the script measures how far the mark reaches from the centre of
the adaptive canvas and exits non-zero if it leaves the 66dp safe zone. A
full-bleed preview can look fine while a circular launcher mask clips a corner,
so the check exists to catch exactly the edit that would look harmless.
"""

import math
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

SS = 4                      # supersample factor
D = 1000                    # design space
BLUE_HI = (58, 110, 165)    # #3A6EA5 — keep in step with ic_launcher_background.xml
BLUE_LO = (17, 38, 62)      # #11263E
WHITE = (255, 255, 255)

# The mark's union bounding box is 227..750 once the back sheet's stroke is
# included, so its centre sits at 488.5 rather than 500. Shift it back.
CENTRE_FIX = 11.5

# Adaptive icons are 108dp square, and launchers guarantee only a 66dp circle.
CANVAS_DP = 108
SAFE_RADIUS_DP = 33


def design(draw, s, k=1.0):
    """Draw the mark in a 1000x1000 design space scaled by s, shrunk by k about
    the centre so it can be fitted inside a launcher's safe zone."""
    def t(v): return ((v + CENTRE_FIX) - 500) * k + 500
    def p(*v): return tuple(int(round(t(x) * s)) for x in v)

    # Back sheet: outlined, peeking out top-left. Reads as "copy".
    draw.rounded_rectangle(p(250, 250, 645, 645), radius=int(72 * s * k),
                           outline=WHITE + (150,), width=int(46 * s * k))
    # Front sheet: solid, carries the mark.
    draw.rounded_rectangle(p(355, 355, 750, 750), radius=int(72 * s * k),
                           fill=WHITE + (255,))
    # Pulse line: few points so it stays legible at 48px.
    pts = [(408, 553), (492, 553), (543, 452), (600, 652), (652, 553), (712, 553)]
    draw.line([p(*q) for q in pts], fill=BLUE_LO + (255,),
              width=int(38 * s * k), joint="curve")


def gradient(size):
    g = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        g.putpixel((0, y), tuple(int(BLUE_HI[i] + (BLUE_LO[i] - BLUE_HI[i]) * t) for i in range(3)))
    return g.resize((size, size))


def foreground(px):
    """Adaptive-icon foreground: transparent, mark inside the safe zone."""
    img = Image.new("RGBA", (px * SS, px * SS), (0, 0, 0, 0))
    design(ImageDraw.Draw(img), px * SS / D, k=0.74)
    return img.resize((px, px), Image.LANCZOS)


def full(px, rounded=False):
    """Legacy launcher icon: background baked in."""
    big = px * SS
    img = gradient(big).convert("RGBA")
    if rounded:
        mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1],
                                               radius=int(big * 0.22), fill=255)
        img.putalpha(mask)
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    design(ImageDraw.Draw(layer), big / D, k=1.12)
    img.alpha_composite(layer)
    return img.resize((px, px), Image.LANCZOS)


def reach_dp(img):
    """How far the furthest visible pixel sits from the centre, in dp."""
    n = img.size[0]
    alpha = img.split()[3].load()
    c = n / 2
    far = max((math.hypot(x - c, y - c)
               for y in range(n) for x in range(n) if alpha[x, y] > 20),
              default=0)
    return far / n * CANVAS_DP


def main():
    # Adaptive foreground: 108dp at each density.
    for name, px in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
                     ("xxhdpi", 324), ("xxxhdpi", 432)]:
        foreground(px).save(os.path.join(RES, f"mipmap-{name}", "ic_launcher_foreground.png"))

    # Legacy square icon: 48dp at each density.
    for name, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                     ("xxhdpi", 144), ("xxxhdpi", 192)]:
        full(px, rounded=True).save(os.path.join(RES, f"mipmap-{name}", "ic_launcher.png"))

    full(512, rounded=True).save(os.path.join(ROOT, "docs", "logo.png"))

    reach = reach_dp(foreground(432))
    print(f"mark reaches {reach:.1f}dp from centre (safe zone: {SAFE_RADIUS_DP}dp)")
    if reach > SAFE_RADIUS_DP:
        sys.exit(f"mark leaves the safe zone by {reach - SAFE_RADIUS_DP:.1f}dp; "
                 "a circular launcher mask would clip it")


if __name__ == "__main__":
    main()
