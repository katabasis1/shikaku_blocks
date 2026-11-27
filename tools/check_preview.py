#!/usr/bin/env python3
"""20.8, строка 10 (docs/shader_refs/PROMPTS.md): галочка «число закрыто» (shaders/check.gdshader) крупно —
кадр для генератора изображений и сравнение с референсом.

Кадр 1200×800: фон, поле 5×3 (клетка 150 px, масштаб 1,5), четыре блока разных цветов — жёлтый 4 (2×2), голубой 6
(3×2), красный 2 (2×1), оранжевый 3 (3×1); на месте числа каждого — галочка, как в Block.close_number на шаге 3
(масштаб 1, непрозрачная; униформы — как ставит Block._check_node). Всё — настоящими шейдерами через переводчик
tools/shader_preview.py.

    python3 tools/check_preview.py                  # -> /tmp/check_frame.png (кадр текущим шейдером)
    python3 tools/check_preview.py --input          # -> docs/shader_refs/check_input.jpg (вход генератора)
    python3 tools/check_preview.py --shader ФАЙЛ    # кадр другим вариантом шейдера (путь к .gdshader)
    python3 tools/check_preview.py --cmp            # -> docs/shader_refs/check_cmp.jpg: референс / до / после

«До» в сравнении — check_input.jpg (кадр шейдером до переделки, его и давали генератору), «после» — кадр текущим
шейдером, «референс» — docs/shader_refs/check.jpg (П9), приведённый к 1200×800. Снизу — галочки крупно (×1,4) в том
же порядке. Печатает среднее отличие от референса (0–255) в окне 150×150 вокруг каждой галочки — до и после.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_preview as sp  # noqa: E402

ROOT = sp.ROOT
REFS = os.path.join(ROOT, "docs", "shader_refs")
W, H = 1200, 800
COLS, ROWS = 5, 3
CELL_PX = 150
# Блоки на поле: x, y, ширина, высота, клетка числа (в клетках поля).
BLOCKS = [(0, 0, 2, 2, 0, 1), (2, 0, 3, 2, 3, 1), (0, 2, 2, 1, 0, 2), (2, 2, 3, 1, 3, 2)]
ZOOM_BOX = 150      # окно вокруг галочки, px кадра
ZOOM_K = 1.4
FONT = os.path.join(ROOT, "assets", "fonts", "nunito_extrabold.ttf")


def grid_origin():
    """Левый верх сетки на кадре: рамка поля вместе с губой (FRAME_DEPTH) — по центру кадра."""
    return W / 2 - COLS * CELL_PX / 2, H / 2 - ROWS * CELL_PX / 2 - sp.BD["FRAME_DEPTH"] / 2


def check_centers():
    """Центры узлов Check на кадре, px: клетка числа, поднятая на lift (как Label блока)."""
    ox, oy = grid_origin()
    s = CELL_PX / sp.CELL
    lift = sp.B["DEPTH"] * sp.CELL * 0.6
    out = []
    for x, y, w, h, nx, ny in BLOCKS:
        out.append((ox + (nx + 0.5) * CELL_PX, oy + (ny + 0.5) * CELL_PX - lift * s))
    return out


def render(shader="check"):
    """Кадр 1200×800; shader — имя в shaders/ или путь к другому .gdshader (вариант для сравнения)."""
    name = os.path.splitext(os.path.abspath(shader))[0] if shader.endswith(".gdshader") else shader
    sh = sp.Shader.get(name)
    cv = sp.background(W, H)
    s = CELL_PX / sp.CELL
    px = 1.0 / s
    ox, oy = grid_origin()
    m = (sp.BD["FRAME_MARGIN"] + sp.BD["PAD"]) * px
    fw, fh = COLS * sp.CELL + 2 * m, ROWS * sp.CELL + 2 * m + sp.BD["FRAME_DEPTH"] * px
    sp.draw_rect(cv, "board", ox - m * s, oy - m * s, fw, fh, s, (1, 1, 1, 1), {
        "frame_size": (fw, fh), "grid": (float(COLS), float(ROWS)), "px": px, "margin": sp.BD["FRAME_MARGIN"],
        "pad": sp.BD["PAD"], "rim": sp.BD["RIM"], "lip": sp.BD["FRAME_DEPTH"]})
    lift = sp.B["DEPTH"] * sp.CELL * 0.6
    mb = sp.B["MARGIN_REST"] * px
    for x, y, bw, bh, nx, ny in sorted(BLOCKS, key=lambda b: (b[1], b[0])):
        area = bw * bh
        col = sp.color_for(area)
        gx, gy = ox + x * CELL_PX, oy + y * CELL_PX
        center = ((nx - x + 0.5) * sp.CELL, (ny - y + 0.5) * sp.CELL - lift)
        w, h = bw * sp.CELL, bh * sp.CELL
        sp.draw_rect(cv, "block", gx - mb * s, gy - mb * s, w + 2 * mb, h + 2 * mb, s, col, {
            "rect_size": (w, h), "cells": (float(bw), float(bh)), "margin": mb, "num_center": center, "px": px,
            "shadow_offset": sp.B["SHADOW_REST"], "shadow_blur": sp.B["BLUR_REST"], "shadow_color": sp.SHADE})
        params = {"rect_size": (100.0, 100.0), "outline": sp.B["DIGIT_OUTLINE"],
                  "outline_color": sp.darkened(col, 0.45), "shadow_color": sp.darkened(col, 0.6)[:3] + (0.47,)}
        if "tint_color" in sh.defaults:     # униформа нового шейдера (20.8); у прежнего её нет
            params["tint_color"] = col
        sp.draw_rect(cv, name, gx + (center[0] - 50) * s, gy + (center[1] - 50) * s, 100, 100, s, (1, 1, 1, 1),
                     params)
    return cv.image()


def zoom_boxes():
    h = ZOOM_BOX // 2
    return [(int(cx - h + 6), int(cy - h + 6), int(cx + h + 6), int(cy + h + 6)) for cx, cy in check_centers()]


def score(a, b):
    """Среднее отличие (0–255) в окнах вокруг галочек."""
    A, B = np.asarray(a, float), np.asarray(b, float)
    return [float(np.abs(A[y0:y1, x0:x1] - B[y0:y1, x0:x1]).mean()) for x0, y0, x1, y1 in zoom_boxes()]


def compare(after):
    ref = Image.open(os.path.join(REFS, "check.jpg")).convert("RGB").resize((W, H), Image.LANCZOS)
    before = Image.open(os.path.join(REFS, "check_input.jpg")).convert("RGB")
    trio = [("референс", ref), ("до", before), ("после", after)]
    k = 0.6
    tw, th = int(W * k), int(H * k)
    zs = int(ZOOM_BOX * ZOOM_K)
    gap = 10
    out_w = 3 * tw + 2 * gap
    out = Image.new("RGB", (out_w, 36 + th + gap + 2 * (zs + gap)), (30, 30, 30))
    d = ImageDraw.Draw(out)
    f = ImageFont.truetype(FONT, 22)
    for i, (title, im) in enumerate(trio):
        out.paste(im.resize((tw, th), Image.LANCZOS), (i * (tw + gap), 36))
        d.text((i * (tw + gap) + 10, 6), title, fill=(255, 255, 255), font=f)
    y0 = 36 + th + gap
    group = 3 * zs + 2 * gap
    for j, box in enumerate(zoom_boxes()):
        col, row = j % 2, j // 2
        gx = (out_w // 2 - group) // 2 + col * (out_w // 2)
        for i, (_, im) in enumerate(trio):
            out.paste(im.crop(box).resize((zs, zs), Image.LANCZOS), (gx + i * (zs + gap), y0 + row * (zs + gap)))
    path = os.path.join(REFS, "check_cmp.jpg")
    out.save(path, quality=90, optimize=True)
    names = ["жёлтый", "голубой", "красный", "оранжевый"]
    for n, b, a in zip(names, score(ref, before), score(ref, after)):
        print("%-10s отличие от референса: до %5.1f  после %5.1f" % (n, b, a))
    print("->", os.path.relpath(path, ROOT), out.size)


def main(argv):
    shader = argv[argv.index("--shader") + 1] if "--shader" in argv else "check"
    img = render(shader)
    if "--input" in argv:
        path = os.path.join(REFS, "check_input.jpg")
        img.save(path, quality=92, optimize=True)
        print("->", os.path.relpath(path, ROOT), img.size)
    elif "--cmp" in argv:
        compare(img)
    else:
        img.save("/tmp/check_frame.png")
        print("-> /tmp/check_frame.png", img.size)


if __name__ == "__main__":
    main(sys.argv[1:])
