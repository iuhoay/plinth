"""Draw the disk image's window background: a sheet of rice paper.

The same ink as Settings > Why a Fish: an ensō, one brushstroke round, for
the app to sit in; a short stroke pointing on to Applications; and, written
top to bottom at the right, 「放下着」 ("put it down", Zhaozhou's answer to a
monk who had brought nothing), with a cinnabar seal. Drag the fish into
Applications and put it down.

The coordinates match the icon positions in scripts/dmg_settings.py, in
points of a 640 x 400 window. Writes the 1x and @2x images, rendered at 4x
and downsampled. Needs Songti SC, which ships with macOS.

The image is original and released under CC0, like the project's other art
(the code itself is MIT).

Usage: python draw_dmg_background.py <out.png>   (also writes <out>@2x.png)
"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 640, 400
R = 4  # render scale
SONGTI = "/System/Library/Fonts/Supplemental/Songti.ttc"
REGULAR, BOLD = 6, 1  # faces in Songti.ttc

PAPER = (243, 238, 227)
INK = (41, 38, 36)
CINNABAR = (179, 51, 38)

APP = (180, 186)  # centre of the app icon; Applications sits at (460, 186)


def px(v):
    return v * R


def enso(draw, cx, cy, radius):
    """The stroke from Settings: lands at the lower left, goes round
    clockwise, thins, and runs dry into a few hairs before it closes."""
    thickest = radius * 0.15

    def width(t):
        return thickest * max(0.0, 1 - t) ** 1.1

    def point(t, offset):
        angle = 2.3 + 2 * np.pi * 0.9 * t
        r = radius - thickest / 2 + radius * 0.012 * np.sin(t * 9 + 0.5) + offset
        return (px(cx + r * np.cos(angle)), px(cy + r * np.sin(angle)))

    wet = np.linspace(0, 0.8, 360)
    outline = [point(t, width(t) / 2) for t in wet] + [point(t, -width(t) / 2) for t in wet[::-1]]
    draw.polygon(outline, fill=255)
    # The blunt drop where the brush lands.
    lx, ly = point(0.012, 0)
    ax, ay = point(0.03, 0)
    along = np.arctan2(ay - ly, ax - lx)
    a, b = px(thickest * 0.75), px(thickest * 0.6)
    s = np.linspace(0, 2 * np.pi, 64)
    draw.polygon([(lx + a * np.cos(u) * np.cos(along) - b * np.sin(u) * np.sin(along),
                   ly + a * np.cos(u) * np.sin(along) + b * np.sin(u) * np.cos(along)) for u in s], fill=255)
    for across, end in [(-0.45, 0.86), (-0.2, 0.97), (0.05, 0.91), (0.3, 0.95), (0.48, 0.84)]:
        line(draw, [point(t, across * width(0.55)) for t in np.linspace(0.55, end, 120)], thickest * 0.09)


def line(draw, points, w):
    """A polyline with round joins and caps, w points wide."""
    draw.line(points, fill=255, width=max(1, round(px(w))))
    rr = px(w) / 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - rr, y - rr, x + rr, y + rr), fill=255)


def stroke(draw, x0, x1, y, thickest):
    """A short horizontal stroke: pressed in at the left, lifted to a point."""
    xs = np.linspace(x0, x1, 120)
    t = (xs - x0) / (x1 - x0)
    w = thickest * (0.55 + 0.45 * np.minimum(1, t / 0.12)) * (1 - t) ** 0.7
    sag = 1.2 * np.sin(np.pi * t)  # the slightest dip, like a hand
    top = [(px(x), px(y + s - ww / 2)) for x, s, ww in zip(xs, sag, w)]
    bottom = [(px(x), px(y + s + ww / 2)) for x, s, ww in zip(xs, sag, w)]
    draw.polygon(top + bottom[::-1], fill=255)
    r = px(thickest * 0.55 / 2)
    draw.ellipse((px(x0) - r, px(y) - r, px(x0) + r, px(y) + r), fill=255)


def column(draw, text, x, y, size, face, fill):
    """Characters top to bottom, centred on x, from y."""
    font = ImageFont.truetype(SONGTI, px(size), index=face)
    for i, ch in enumerate(text):
        draw.text((px(x), px(y + i * size * 1.32)), ch, font=font, fill=fill, anchor="mt")


def main(out):
    rng = np.random.default_rng(7)
    # Rice paper: flat, with faint fibres and a little grain.
    paper = np.ones((px(H), px(W), 3)) * np.array(PAPER, dtype=np.float64)
    grain = rng.normal(0, 1, (px(H) // 4, px(W) // 4))
    grain = np.array(Image.fromarray(grain.astype(np.float32)).resize((px(W), px(H)), Image.BICUBIC))
    paper += grain[..., None] * 1.6
    fibres = Image.new("L", (px(W), px(H)), 0)
    fd = ImageDraw.Draw(fibres)
    for _ in range(260):
        x, y = rng.uniform(0, px(W)), rng.uniform(0, px(H))
        angle, length = rng.uniform(0, np.pi), rng.uniform(px(6), px(26))
        bend = rng.uniform(-0.4, 0.4)
        pts = [(x + length * s * np.cos(angle + bend * s), y + length * s * np.sin(angle + bend * s))
               for s in np.linspace(0, 1, 12)]
        fd.line(pts, fill=int(rng.uniform(40, 110)), width=R)
    fibres = np.asarray(fibres.filter(ImageFilter.GaussianBlur(R * 0.6)), dtype=np.float64) / 255
    paper -= fibres[..., None] * 9

    def wash(mask, colour, opacity):
        nonlocal paper
        a = np.asarray(mask, dtype=np.float64)[..., None] / 255 * opacity
        paper = paper * (1 - a) + np.array(colour, dtype=np.float64) * a

    # The ensō around the app, and the stroke on to Applications.
    m = Image.new("L", (px(W), px(H)), 0)
    enso(ImageDraw.Draw(m), *APP, radius=104)
    stroke(ImageDraw.Draw(m), 302, 362, APP[1] - 8, 4.2)
    wash(m.filter(ImageFilter.GaussianBlur(R * 0.35)), INK, 0.32)

    # 「放下着」, its source, and the seal.
    m = Image.new("L", (px(W), px(H)), 0)
    column(ImageDraw.Draw(m), "放下着", 590, 40, 30, REGULAR, 255)
    wash(m, INK, 0.86)
    m = Image.new("L", (px(W), px(H)), 0)
    column(ImageDraw.Draw(m), "赵州", 553, 92, 12, REGULAR, 255)
    wash(m, INK, 0.5)
    seal = Image.new("L", (px(W), px(H)), 0)
    carved = Image.new("L", (px(W), px(H)), 0)
    sx, sy = 553, 134
    ImageDraw.Draw(seal).rounded_rectangle((px(sx - 8), px(sy), px(sx + 8), px(sy + 30)), radius=px(2), fill=255)
    column(ImageDraw.Draw(carved), "常醒", sx, sy + 3.5, 10, BOLD, 255)
    seal = Image.fromarray(np.minimum(np.asarray(seal), 255 - np.asarray(carved)))
    wash(seal, CINNABAR, 0.9)

    image = Image.fromarray(np.clip(paper, 0, 255).astype(np.uint8))
    base = out[:-4] if out.endswith(".png") else out
    image.resize((W * 2, H * 2), Image.LANCZOS).save(f"{base}@2x.png", dpi=(144, 144))
    image.resize((W, H), Image.LANCZOS).save(f"{base}.png", dpi=(72, 72))


if __name__ == "__main__":
    main(sys.argv[1])
