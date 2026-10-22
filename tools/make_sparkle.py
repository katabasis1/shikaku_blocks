#!/usr/bin/env python3
"""Искра логотипа меню (07.10): assets/icons/sparkle.png — четырёхлучевая звёздочка (астроида
|x|^(2/3) + |y|^(2/3) = r^(2/3)) с мягким ореолом, белая (цвет задаёт modulate в LogoSparkles).

128×128, звёздочка — до края (r = 0,5 стороны), ореол — гаусс σ = 0,2 стороны, 55 % в центре; рисуется с
4× запасом и уменьшается (сглаженный край). Результат одинаковый при каждом запуске.

  python3 tools/make_sparkle.py           записать assets/icons/sparkle.png
  python3 tools/make_sparkle.py --check   только сравнить с файлом (0 — совпадает)
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "icons", "sparkle.png")
SIZE = 128
SS = 4                 # запас при рисовании
GLOW_SIGMA = 0.2       # ореол: σ — доля стороны
GLOW_ALPHA = 0.55      # ореол в центре


def render() -> Image.Image:
    n = SIZE * SS
    ys, xs = np.mgrid[0:n, 0:n]
    x = (xs + 0.5) / n - 0.5
    y = (ys + 0.5) / n - 0.5
    r = 0.5
    # Астроида: внутри, где |x|^(2/3) + |y|^(2/3) < r^(2/3); край — 1,5 px запаса.
    d = np.abs(x) ** (2 / 3) + np.abs(y) ** (2 / 3) - r ** (2 / 3)
    star = np.clip(-d * n * 0.6, 0.0, 1.0)
    glow = GLOW_ALPHA * np.exp(-(x * x + y * y) / (2 * GLOW_SIGMA ** 2))
    a = np.clip(star + glow * (1.0 - star), 0.0, 1.0)
    img = np.ones((n, n, 4))
    img[..., 3] = a
    im = Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA")
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> int:
    im = render()
    if "--check" in sys.argv:
        old = np.asarray(Image.open(OUT).convert("RGBA")).astype(int)
        diff = int(np.abs(old - np.asarray(im).astype(int)).max())
        print("sparkle.png: разница %d" % diff)
        return 0 if diff == 0 else 1
    im.save(OUT, optimize=True)
    print("записано", OUT, os.path.getsize(OUT), "байт")
    return 0


if __name__ == "__main__":
    sys.exit(main())
