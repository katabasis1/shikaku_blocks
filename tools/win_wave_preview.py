#!/usr/bin/env python3
"""20.8, строка 12 (docs/shader_refs/PROMPTS.md): волна света победы (shaders/win_wave.gdshader) крупно — кадр для
генератора изображений и сравнение с референсом.

Кадр 1500×1000: поле tools/win_preview.py (6×4, все места заняты, последний блок 2 встал в правый нижний угол, от
него к дальнему углу бежит кольцо света) в клетке 170 px, миг T после касания поля — фронт посередине поля. Всё как в
win_preview.board_frame (те же твины: hit-stop, вспышки и подскоки блоков, галочка на блоке 2). Всё — настоящими
шейдерами через переводчик tools/shader_preview.py.

    python3 tools/win_wave_preview.py                  # -> /tmp/win_wave_frame.png (кадр текущим шейдером)
    python3 tools/win_wave_preview.py --input          # -> docs/shader_refs/win_wave_input.jpg (вход генератора)
    python3 tools/win_wave_preview.py --shader ФАЙЛ    # кадр другим вариантом шейдера (путь к .gdshader)
    python3 tools/win_wave_preview.py --t 0.3          # другой миг, с от касания
    python3 tools/win_wave_preview.py --cmp            # -> docs/shader_refs/win_wave_cmp.jpg: референс / до / после

«До» — win_wave_input.jpg (кадр шейдером до переделки, его и давали генератору), «после» — кадр текущим шейдером,
«референс» — docs/shader_refs/win_wave.jpg (П11), приведённый к 1500×1000. Снизу — поле крупно. Печатает среднее
отличие от референса (0–255) по лицам блоков и по зазорам между ними — до и после.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_preview as sp  # noqa: E402
import close_preview as cp   # noqa: E402
import win_preview as wp     # noqa: E402

ROOT = sp.ROOT
REFS = os.path.join(ROOT, "docs", "shader_refs")
W, H = 1500, 1000
CELL_PX = 170
T = 0.21            # с от касания поля (hit-stop 0,07 + 0,14 — фронт посередине поля)
FONT = os.path.join(ROOT, "assets", "fonts", "nunito_extrabold.ttf")


def setup(shader="win_wave"):
    """win_preview → крупный кадр: клетка CELL_PX, поле с рамкой и губой — по центру W × H."""
    wp.CELL_PX = CELL_PX
    wp.PAD_X = (W - wp.COLS * CELL_PX) // 2
    wp.PAD_TOP = int(round(H / 2 - wp.ROWS * CELL_PX / 2 - sp.BD["FRAME_DEPTH"] / 2))
    wp.PAD_BOTTOM = H - wp.ROWS * CELL_PX - wp.PAD_TOP
    wp.WAVE_SHADER = os.path.splitext(os.path.abspath(shader))[0] if shader.endswith(".gdshader") else shader


def render(shader="win_wave", t=T):
    setup(shader)
    c = cp.juice_config()
    return wp.board_frame(t, c, False, wp.block_flash_fade(), wp.block_pop_steps())


def zones():
    """Окна оценки, px кадра: лица блоков (без краёв) и зазоры между блоками (полосы вдоль общих сторон)."""
    faces, gaps = [], []
    k = CELL_PX
    for bx, by, bw, bh in (b[:4] for b in wp.BLOCKS):
        x0, y0 = wp.PAD_X + bx * k, wp.PAD_TOP + by * k
        faces.append((x0 + 18, y0 + 18, x0 + bw * k - 18, y0 + bh * k - 14))
    cols, rows = wp.COLS, wp.ROWS
    owner = {}
    for i, (bx, by, bw, bh) in enumerate(b[:4] for b in wp.BLOCKS):
        for y in range(by, by + bh):
            for x in range(bx, bx + bw):
                owner[(x, y)] = i
    for y in range(rows):
        for x in range(cols):
            if x + 1 < cols and owner[(x, y)] != owner[(x + 1, y)]:
                gx = wp.PAD_X + (x + 1) * k
                gaps.append((gx - 5, wp.PAD_TOP + y * k + 30, gx + 5, wp.PAD_TOP + (y + 1) * k - 30))
            if y + 1 < rows and owner[(x, y)] != owner[(x, y + 1)]:
                gy = wp.PAD_TOP + (y + 1) * k
                gaps.append((wp.PAD_X + x * k + 30, gy - 4, wp.PAD_X + (x + 1) * k - 30, gy + 8))
    return faces, gaps


def score(a, b):
    A, B = np.asarray(a, float), np.asarray(b, float)
    faces, gaps = zones()
    f = float(np.mean([np.abs(A[y0:y1, x0:x1] - B[y0:y1, x0:x1]).mean() for x0, y0, x1, y1 in faces]))
    g = float(np.mean([np.abs(A[y0:y1, x0:x1] - B[y0:y1, x0:x1]).mean() for x0, y0, x1, y1 in gaps]))
    return f, g


def compare(after):
    setup()
    ref = Image.open(os.path.join(REFS, "win_wave.jpg")).convert("RGB").resize((W, H), Image.LANCZOS)
    before = Image.open(os.path.join(REFS, "win_wave_input.jpg")).convert("RGB")
    trio = [("референс", ref), ("до", before), ("после", after)]
    k = 0.4
    tw, th = int(W * k), int(H * k)
    gap = 10
    out_w = 3 * tw + 2 * gap
    crop = (wp.PAD_X - 40, wp.PAD_TOP - 40, wp.PAD_X + wp.COLS * CELL_PX + 40, wp.PAD_TOP + wp.ROWS * CELL_PX + 50)
    zw = (out_w - 2 * gap) // 3
    zh = int((crop[3] - crop[1]) * zw / (crop[2] - crop[0]))
    out = Image.new("RGB", (out_w, 36 + th + gap + zh + 36), (30, 30, 30))
    d = ImageDraw.Draw(out)
    f = ImageFont.truetype(FONT, 22)
    for i, (title, im) in enumerate(trio):
        out.paste(im.resize((tw, th), Image.LANCZOS), (i * (tw + gap), 36))
        d.text((i * (tw + gap) + 10, 6), title, fill=(255, 255, 255), font=f)
    y = 36 + th + gap
    for i, (title, im) in enumerate(trio):
        out.paste(im.crop(crop).resize((zw, zh), Image.LANCZOS), (i * (zw + gap), y))
    d.text((10, y + zh + 6), "снизу — поле крупно (референс / до / после)", fill=(255, 255, 255), font=f)
    path = os.path.join(REFS, "win_wave_cmp.jpg")
    out.save(path, quality=90, optimize=True)
    (fb, gb), (fa, ga) = score(ref, before), score(ref, after)
    print("лица блоков  отличие от референса: до %5.1f  после %5.1f" % (fb, fa))
    print("зазоры       отличие от референса: до %5.1f  после %5.1f" % (gb, ga))
    print("->", os.path.relpath(path, ROOT), out.size)


def main(argv):
    shader = argv[argv.index("--shader") + 1] if "--shader" in argv else "win_wave"
    t = float(argv[argv.index("--t") + 1]) if "--t" in argv else T
    img = render(shader, t)
    if "--input" in argv:
        path = os.path.join(REFS, "win_wave_input.jpg")
        img.save(path, quality=92, optimize=True)
        print("->", os.path.relpath(path, ROOT), img.size)
    elif "--cmp" in argv:
        compare(img)
    else:
        out = argv[argv.index("--out") + 1] if "--out" in argv else "/tmp/win_wave_frame.png"
        img.save(out)
        print("->", out, img.size)


if __name__ == "__main__":
    main(sys.argv[1:])
