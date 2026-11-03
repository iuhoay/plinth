"""Draw the singing bowl's impact burst: golden sound ripples.

Three concentric rings of warm gold light spread from a bright point; the
outer ring breaks into arcs, and a few motes drift between them. The alpha
is exact, so the burst sits cleanly on any desktop. Rendered at 1024 px and
downsampled to 256.

The image is original and released under CC0, like the project's other art
(the code itself is MIT).

Usage: python draw_ripple.py <output.png>
"""
import sys
import numpy as np
from PIL import Image

N = 1024  # render large, downsample to 256
y, x = np.mgrid[0:N, 0:N].astype(np.float64)
c = (N - 1) / 2
dx, dy = x - c, y - c
r = np.hypot(dx, dy) / (N / 2)  # 0 at centre, 1 at edge
theta = np.arctan2(dy, dx)
rng = np.random.default_rng(7)

def ring(radius, width, strength):
    return strength * np.exp(-((r - radius) / width) ** 2)

# Three rings: inner brightest, outer thinner, fainter and broken into arcs.
a = ring(0.30, 0.022, 1.0) + ring(0.30, 0.07, 0.35)
a += ring(0.58, 0.016, 0.75) + ring(0.58, 0.05, 0.22)
arcs = np.clip(0.55 + 0.75 * np.sin(5 * theta + 0.7) + 0.35 * np.sin(11 * theta + 2.1), 0, 1)
a += (ring(0.86, 0.012, 0.55) + ring(0.86, 0.04, 0.15)) * arcs

# Bright point in the middle with a soft halo and a four-point glint.
core = np.exp(-(r / 0.05) ** 2) + 0.45 * np.exp(-(r / 0.14) ** 2)
glint = (np.exp(-(dx / (N * 0.006)) ** 2) + np.exp(-(dy / (N * 0.006)) ** 2)) * np.exp(-(r / 0.22) ** 2) * 0.6
a += core + glint

# A few motes between the rings.
for _ in range(14):
    rr = rng.choice([rng.uniform(0.38, 0.5), rng.uniform(0.66, 0.8)])
    t = rng.uniform(-np.pi, np.pi)
    mx, my = c + rr * np.cos(t) * N / 2, c + rr * np.sin(t) * N / 2
    s = N * rng.uniform(0.004, 0.008)
    a += rng.uniform(0.5, 0.9) * np.exp(-(((x - mx) ** 2 + (y - my) ** 2) / s ** 2))

a = np.clip(a, 0, 1)
# Warm gold, whitening where it is brightest.
gold = np.array([255, 196, 84], dtype=np.float64)
white = np.array([255, 247, 220], dtype=np.float64)
mix = np.clip((a - 0.6) / 0.4, 0, 1)[..., None]
rgb = gold * (1 - mix) + white * mix
img = np.dstack([rgb, a * 255]).astype(np.uint8)
Image.fromarray(img, "RGBA").resize((256, 256), Image.LANCZOS).save(sys.argv[1])
