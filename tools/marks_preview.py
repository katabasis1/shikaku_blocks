#!/usr/bin/env python3
"""Кадр G19_3_marks: знаки механик на поле (CellMark, STYLE 11.5) — картинки листа 5 (10.10).

Три поля уровней глав с механикой, у которых знаков больше одного: препятствия, закреплённый блок, цветные
клетки (у числа «?» своих картинок нет — это гнездо Palette.UNKNOWN, его рисует Cell). Поле — shaders/board.gdshader, гнёзда — nest.gdshader,
закреплённый блок — block.gdshader цвета Palette.PINNED без цифры (как Board._setup_mechanics); знаки —
как CellMark._draw: obstacle.png и tint_frame.png (перекрашена в цвет площади, внутри заливка 40 %), заклёпки
rivet.png; под картинками — тень Palette.SHADE (StyleBoxFlat / draw_circle).

    python3 tools/marks_preview.py              # -> docs/style_frames/G19_3_marks.png
    python3 tools/marks_preview.py --out FILE
"""
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import make_lab  # noqa: E402
import shader_preview as sp  # noqa: E402

OUT = os.path.join(sp.FRAMES, "G19_3_marks.png")
CM = "scenes/game/cell_mark.gd"
# Уровни: глава 4 — препятствия (6 плиток), 5 — закреплённый блок 3 × 2, 8 — две цветные клетки.
LEVELS = [(197, "Препятствия · 197"), (202, "Закреплённый блок · 202"), (372, "Цветные клетки · 372")]
CELL_PX = 72        # клетка на кадре (в игре на телефоне — 80–104)
SS = 3              # сглаживание слоя знаков
PAD, HEAD = 28, 56


def gd(name, path=CM):
    return sp.gd_value(sp.gd_const(path, name))


C = {k: gd(k) for k in ("ICON_FIT", "TILE_INSET", "TILE_RADIUS", "TILE_SHADOW_Y", "TINT_INSET", "TINT_FILL",
                        "TINT_FILL_K", "RIVET_INSET", "RIVET_D")}
PINNED = sp.gd_value(sp.gd_const("scripts/palette.gd", "PINNED")) + (1.0,)
UNKNOWN = sp.gd_value(sp.gd_const("scripts/palette.gd", "UNKNOWN")) + (1.0,)
TEX = {n: Image.open(os.path.join(sp.ICONS, n + ".png")).convert("RGBA") for n in ("obstacle", "tint_frame", "rivet")}


def level(n):
    src = open(os.path.join(ROOT, "scripts", "level_pack_data.gd"), encoding="utf-8").read()
    return make_lab.decode(re.findall(r'"(\d\d:\d+:\d+(?::[a-z0-9]*)?)"', src)[n - 1])


def color_of(value):
    return UNKNOWN if value <= 0 else sp.color_for(value)


def rgba8(col, a=None):
    return tuple(int(round(v * 255)) for v in col[:3]) + (int(round((col[3] if a is None else a) * 255)),)


class Layer:
    """Слой _draw в px холста ×SS: прямоугольники StyleBoxFlat, круги, картинки draw_texture_rect."""

    def __init__(self, w, h):
        self.im = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))

    def _put(self, shape):
        self.im.alpha_composite(shape)

    def rrect(self, x, y, w, h, r, col):
        sh = Image.new("RGBA", self.im.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle([x * SS, y * SS, (x + w) * SS, (y + h) * SS], radius=r * SS,
                                             fill=rgba8(col))
        self._put(sh)

    def circle(self, cx, cy, r, col):
        sh = Image.new("RGBA", self.im.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse([(cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS], fill=rgba8(col))
        self._put(sh)

    def texture(self, name, x, y, side, modulate=(1, 1, 1, 1)):
        n = max(1, int(round(side * SS)))
        im = TEX[name].resize((n, n), Image.LANCZOS)
        if modulate != (1, 1, 1, 1):
            a = np.asarray(im).astype(np.float64)
            a *= np.array(modulate, dtype=np.float64)
            im = Image.fromarray(np.clip(a + 0.5, 0, 255).astype(np.uint8), "RGBA")
        self.im.alpha_composite(im, dest=(int(round(x * SS)), int(round(y * SS))))

    def flush(self, cv):
        small = self.im.resize((self.im.width // SS, self.im.height // SS), Image.LANCZOS)
        cv.over(0, 0, np.asarray(small).astype(float) / 255.0)


def icon_rect(c, side):
    """CellMark.icon_rect: картинка, видимая часть которой — квадрат side с центром c."""
    full = side / C["ICON_FIT"]
    return c[0] - full / 2, c[1] - full / 2, full


def draw_hole(L, ox, oy, s):
    """CellMark._draw, HOLE: тень плитки и obstacle.png (ox, oy — левый верх клетки на холсте)."""
    side = sp.CELL - C["TILE_INSET"] * 2
    c = (ox + sp.CELL / 2 * s, oy + sp.CELL / 2 * s)
    L.rrect(c[0] - side * s / 2, c[1] - side * s / 2 + C["TILE_SHADOW_Y"] * s, side * s, side * s,
            C["TILE_RADIUS"] * s, sp.SHADE)
    x, y, full = icon_rect(c, side * s)
    L.texture("obstacle", x, y, full)


def draw_tint(L, ox, oy, s, area):
    """CellMark._draw, TINT: заливка цвета площади TINT_FILL под кольцом и tint_frame.png, перекрашенная в цвет."""
    col = sp.color_for(area)
    side = sp.CELL - C["TINT_INSET"] * 2
    c = (ox + sp.CELL / 2 * s, oy + sp.CELL / 2 * s)
    inner = side * (1 - C["TINT_FILL_K"] * 2)
    L.rrect(c[0] - inner * s / 2, c[1] - inner * s / 2, inner * s, inner * s, int(side * 0.2) * s,
            col[:3] + (C["TINT_FILL"],))
    x, y, full = icon_rect(c, side * s)
    L.texture("tint_frame", x, y, full, col[:3] + (1.0,))


def draw_pins(L, ox, oy, s, bw, bh):
    """CellMark._draw, PIN: 4 заклёпки по углам лица закреплённого блока (лицо поднято на 0,6 высоты блока)."""
    lift = sp.B["DEPTH"] * sp.CELL * 0.6
    w, h = bw * sp.CELL, bh * sp.CELL
    for kx, ky in ((0, 0), (1, 0), (0, 1), (1, 1)):
        ax = C["RIVET_INSET"] + kx * (w - C["RIVET_INSET"] * 2)
        ay = C["RIVET_INSET"] - lift + ky * (h - C["RIVET_INSET"] * 2)
        at = (ox + ax * s, oy + ay * s)
        L.circle(at[0], at[1] + 2 * s, C["RIVET_D"] / 2 * s, sp.SHADE)
        x, y, full = icon_rect(at, C["RIVET_D"] * s)
        L.texture("rivet", x, y, full)


def draw_board(cv, d, x0, y0, cell_px, marks=None):
    """Board уровня d (make_lab.decode): рамка, гнёзда чисел, знаки, закреплённые блоки. marks — функции знаков
    (hole, tint, pins), по умолчанию — нынешние (CellMark)."""
    hole, tint, pins = marks or (draw_hole, draw_tint, draw_pins)
    cols, rows = d["cols"], d["rows"]
    s = cell_px / sp.CELL
    px = 1.0 / s
    ox, oy = x0 + sp.BD["PAD"], y0 + sp.BD["PAD"]
    m = (sp.BD["FRAME_MARGIN"] + sp.BD["PAD"]) * px
    fw, fh = cols * sp.CELL + 2 * m, rows * sp.CELL + 2 * m + sp.BD["FRAME_DEPTH"] * px
    sp.draw_rect(cv, "board", ox - m * s, oy - m * s, fw, fh, s, (1, 1, 1, 1), {
        "frame_size": (fw, fh), "grid": (float(cols), float(rows)), "px": px, "margin": sp.BD["FRAME_MARGIN"],
        "pad": sp.BD["PAD"], "rim": sp.BD["RIM"], "lip": sp.BD["FRAME_DEPTH"]})
    for (nx, ny), value in d["numbers"]:
        col = color_of(value)
        bx, by = nx * sp.CELL, ny * sp.CELL
        sp.draw_rect(cv, "nest", ox + (bx - 48) * s, oy + (by - 48) * s, sp.CELL + 96, sp.CELL + 96, s, col,
                     {"px": px, "ring": 0.0, "margin": 48.0})
        sp.draw_digit(cv, "?" if value <= 0 else str(value), ox + (bx + 50) * s, oy + (by + 50) * s, 40 * s, col,
                      sp.darkened(col, 0.42), sp.CL["DIGIT_OUTLINE"] * s, sp.darkened(col, 0.5)[:3] + (0.35,),
                      (0, 2 * s))
    L = Layer(cv.w, cv.h)
    for hx, hy in d["holes"]:
        hole(L, ox + hx * cell_px, oy + hy * cell_px, s)
    for (tx, ty), area in sorted(d["tints"].items()):
        tint(L, ox + tx * cell_px, oy + ty * cell_px, s, area)
    L.flush(cv)
    for rx, ry, rw, rh in d["pinned"]:
        gx, gy = ox + rx * cell_px, oy + ry * cell_px
        mm = sp.B["MARGIN_REST"] * px
        w, h = rw * sp.CELL, rh * sp.CELL
        lift = sp.B["DEPTH"] * sp.CELL * 0.6
        sp.draw_rect(cv, "block", gx - mm * s, gy - mm * s, w + 2 * mm, h + 2 * mm, s, PINNED, {
            "rect_size": (w, h), "cells": (float(rw), float(rh)), "margin": mm, "num_center": (w / 2, h / 2 - lift),
            "px": px, "shadow_offset": sp.B["SHADOW_REST"], "shadow_blur": sp.B["BLUR_REST"],
            "shadow_color": sp.SHADE})
        P = Layer(cv.w, cv.h)
        pins(P, gx, gy, s, rw, rh)
        P.flush(cv)


def render(marks=None, title="Знаки механик на поле (CellMark, лист 5)"):
    ds = [(level(n), cap) for n, cap in LEVELS]
    m = sp.BD["FRAME_MARGIN"] + sp.BD["PAD"]
    bw = max(d["cols"] for d, _ in ds) * CELL_PX + 2 * m
    bh = max(d["rows"] for d, _ in ds) * CELL_PX + 2 * m + sp.BD["FRAME_DEPTH"]
    W = int(round(PAD + len(ds) * (bw + PAD)))
    H = int(round(HEAD + 40 + bh + PAD))
    cv = sp.background(W, H)
    for i, (d, _) in enumerate(ds):
        x = PAD + i * (bw + PAD)
        draw_board(cv, d, x + (bw - d["cols"] * CELL_PX - 2 * m) / 2 + m - sp.BD["PAD"], HEAD + 40 + m - sp.BD["PAD"],
                   CELL_PX, marks)
    im = cv.image()
    dr = ImageDraw.Draw(im)
    f_head = sp._font(sp.UI_FONT, 30)
    f_cap = sp._font(sp.UI_FONT, 24)
    dr.text((PAD, HEAD / 2), title, font=f_head, fill=(255, 255, 255), anchor="lm")
    for i, (_, cap) in enumerate(ds):
        dr.text((PAD + i * (bw + PAD) + bw / 2, HEAD + 18), cap, font=f_cap, fill=(255, 228, 92), anchor="mm")
    return im


def main(argv):
    out = argv[argv.index("--out") + 1] if "--out" in argv else OUT
    render().save(out, optimize=True)
    print(os.path.relpath(out, ROOT))


if __name__ == "__main__":
    main(sys.argv[1:])
