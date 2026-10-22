#!/usr/bin/env python3
"""Этап 14.3: кадр «число закрыто» — Block.close_number по шагам, из настоящих шейдеров (shaders/block.gdshader
с униформами glow / glow_r и shaders/check.gdshader) через переводчик tools/shader_preview.py.

Блок 3×2 (площадь 6, число в левой нижней клетке) на поле 3×2, клетка 80 px. Верхний ряд — обычный режим,
нижний — «Меньше движения» (волны света нет). Времена — от мига удара (Board._on_landed); твины повторены
по Block.close_number: те же шаги, переходы (QUAD, BACK) и числа из scripts/juice_config.gd. Сплющивание
удара (Block.squash, 0,12 с) и hit-stop в кадр не входят.

    python3 tools/close_preview.py     # -> docs/style_frames/G14_3_close.png
"""
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_preview as sp  # noqa: E402

ROOT = sp.ROOT
OUT = os.path.join(sp.FRAMES, "G14_3_close.png")
TIMES = [0.0, 0.04, 0.08, 0.13, 0.2, 0.42, 0.6, 0.85]
BW, BH, NUM = 3, 2, (0, 1)
CELL_PX = 80
PAD = 44            # поле вокруг блока в кадре, px
CAPTION = 46        # подпись под кадром, px
ROW_TITLE = 40


def juice_config():
    src = open(os.path.join(ROOT, "scripts", "juice_config.gd"), encoding="utf-8").read()
    cfg = {}
    for name, val in re.findall(r"@export var (\w+) := ([0-9.]+)\s*$", src, re.M):
        cfg[name] = float(val)
    return cfg


def quad_out(u):
    return 1 - (1 - u) ** 2


def quad_in(u):
    return u * u


def back_out(u):
    s = 1.70158
    u -= 1
    return u * u * ((s + 1) * u + s) + 1


def lerp(a, b, u):
    return a + (b - a) * u


def seg(t, t0, dur):
    """Доля шага [t0, t0 + dur], 0…1."""
    if dur <= 0:
        return 1.0 if t >= t0 else 0.0
    return min(max((t - t0) / dur, 0.0), 1.0)


def close_state(t, c):
    """Цифра и галочка в момент t, с, — как твины Block.close_number."""
    pop, flash, t1, sw, hold = c["close_pop"], c["close_flash"], c["close_pop_time"], c["close_swap"], c["close_hold"]
    dmin = sp.gd_value(sp.gd_const("scenes/game/block.gd", "CLOSE_DIGIT_MIN"))
    st = {"d_scale": 1.0, "d_mod": 1.0, "d_alpha": 1.0, "c_scale": 0.5, "c_alpha": 0.0}
    # 1. вспышка
    u = seg(t, 0.0, t1)
    st["d_scale"] = lerp(1.0, pop, quad_out(u))
    st["d_mod"] = lerp(1.0, flash, u)
    if t < t1:
        return st
    # 2. цифра -> галочка
    st["d_scale"] = lerp(pop, dmin, quad_in(seg(t, t1, sw)))
    st["d_alpha"] = 1.0 - seg(t, t1, sw)
    st["c_alpha"] = seg(t, t1, sw)
    st["c_scale"] = lerp(0.5, 1.0, back_out(seg(t, t1, 2 * sw)))
    t3 = t1 + 2 * sw
    t4 = t3 + max(hold - sw, 0.0)
    if t < t4:
        return st
    # 4. галочка тает, цифра возвращается
    back = 1.5 * sw
    u = seg(t, t4, back)
    st["c_alpha"] = 1.0 - u
    st["c_scale"] = lerp(1.0, 0.8, quad_in(u))
    st["d_mod"] = lerp(flash, 1.0, u)
    st["d_alpha"] = u
    st["d_scale"] = lerp(dmin, 1.0, back_out(seg(t, t4, 2.5 * sw)))
    if t >= t4 + 2.5 * sw:
        st.update(d_scale=1.0, d_mod=1.0, d_alpha=1.0, c_alpha=0.0)
    return st


def glow_state(t, c, reduced):
    """Сила и радиус волны света (Block._glow_step), px блока."""
    if reduced or t >= c["glow_time"]:
        return 0.0, 0.0
    cell = sp.CELL
    lift = sp.B["DEPTH"] * cell * 0.6
    fx, fy = (NUM[0] + 0.5) * cell, (NUM[1] + 0.5) * cell - lift
    reach = max(math.hypot(fx - x, fy - y) for x in (0, BW * cell) for y in (0, BH * cell))
    v = t / c["glow_time"]
    return c["glow_strength"] * (1 - v), v * (reach + 0.3 * cell)


def frame(t, c, reduced):
    s = CELL_PX / sp.CELL
    px = 1.0 / s
    w, h = BW * CELL_PX + 2 * PAD, BH * CELL_PX + 2 * PAD
    cv = sp.background(w, h)
    ox, oy = PAD, PAD
    # Поле 3×2 под блоком (Board/Frame).
    m = (sp.BD["FRAME_MARGIN"] + sp.BD["PAD"]) * px
    fw, fh = BW * sp.CELL + 2 * m, BH * sp.CELL + 2 * m + sp.BD["FRAME_DEPTH"] * px
    sp.draw_rect(cv, "board", ox - m * s, oy - m * s, fw, fh, s, (1, 1, 1, 1), {
        "frame_size": (fw, fh), "grid": (float(BW), float(BH)), "px": px, "margin": sp.BD["FRAME_MARGIN"],
        "pad": sp.BD["PAD"], "rim": sp.BD["RIM"], "lip": sp.BD["FRAME_DEPTH"]})
    # Block/Visual/Shape с волной света.
    area = BW * BH
    col = sp.color_for(area)
    lift = sp.B["DEPTH"] * sp.CELL * 0.6
    center = ((NUM[0] + 0.5) * sp.CELL, (NUM[1] + 0.5) * sp.CELL - lift)
    mb = sp.B["MARGIN_REST"] * px
    bw, bh = BW * sp.CELL, BH * sp.CELL
    g, gr = glow_state(t, c, reduced)
    sp.draw_rect(cv, "block", ox - mb * s, oy - mb * s, bw + 2 * mb, bh + 2 * mb, s, col, {
        "rect_size": (bw, bh), "cells": (float(BW), float(BH)), "margin": mb, "num_center": center, "px": px,
        "shadow_offset": sp.B["SHADOW_REST"], "shadow_blur": sp.B["BLUR_REST"], "shadow_color": sp.SHADE,
        "glow": g, "glow_r": gr})
    # Number (Label, pivot — центр клетки с числом) и Check поверх.
    st = close_state(t, c)
    k, md = st["d_scale"], st["d_mod"]

    def mod(cc):
        return tuple(min(1.0, x * md) for x in cc[:3]) + tuple(cc[3:])

    if st["d_alpha"] > 0.001:
        sp.draw_digit(cv, str(area), ox + center[0] * s, oy + center[1] * s, 46 * s * k, mod((1, 1, 1, 1)),
                      mod(sp.darkened(col, 0.45)), sp.B["DIGIT_OUTLINE"] * s * k,
                      mod(sp.darkened(col, 0.6))[:3] + (0.47,), (0, 4 * s * k), st["d_alpha"])
    if st["c_alpha"] > 0.001:
        kc = st["c_scale"]
        sp.draw_rect(cv, "check", ox + (center[0] - 50 * kc) * s, oy + (center[1] - 50 * kc) * s, 100, 100, s * kc,
                     (1, 1, 1, st["c_alpha"]), {
                         "rect_size": (100.0, 100.0), "outline": sp.B["DIGIT_OUTLINE"],
                         "outline_color": sp.darkened(col, 0.45), "shadow_color": sp.darkened(col, 0.6)[:3] + (0.47,)})
    return cv.image()


def main():
    c = juice_config()
    font = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "nunito_extrabold.ttf"), 26)
    fw, fh = BW * CELL_PX + 2 * PAD, BH * CELL_PX + 2 * PAD
    rows = [("Обычный режим", False), ("«Меньше движения»: без волны света", True)]
    W = fw * len(TIMES)
    H = len(rows) * (ROW_TITLE + fh + CAPTION)
    out = Image.new("RGB", (W, H), (36, 18, 92))
    d = ImageDraw.Draw(out)
    y = 0
    for title, reduced in rows:
        d.text((16, y + 6), title, font=font, fill=(255, 255, 255))
        y += ROW_TITLE
        for i, t in enumerate(TIMES):
            out.paste(frame(t, c, reduced), (i * fw, y))
            d.text((i * fw + fw / 2, y + fh + CAPTION / 2), "%d мс" % round(t * 1000), font=font,
                   fill=(255, 228, 92), anchor="mm")
        y += fh + CAPTION
    out.save(OUT, optimize=True)
    print("->", os.path.relpath(OUT, ROOT), out.size)


if __name__ == "__main__":
    main()
