#!/usr/bin/env python3
"""20.8, строка 11 (docs/shader_refs/PROMPTS.md): волна света по закрытой линии (shaders/line_wave.gdshader) крупно —
кадр для генератора изображений и сравнение с референсом.

Кадр 1500×1000: сцена tools/line_preview.py (поле 6×3, блок 2 закрыл нижнюю строку, волна бежит из его клеток к
концам) в клетке 170 px, сила хода 0, миг T после касания поля — фронт уже на голубом блоке 6. Всё как в
line_preview.frame (те же твины, вспышки блоков, закрытое число на блоке 2), только без текста комбо — он закрыл бы
линию. Всё — настоящими шейдерами через переводчик tools/shader_preview.py.

    python3 tools/line_wave_preview.py                  # -> /tmp/line_wave_frame.png (кадр текущим шейдером)
    python3 tools/line_wave_preview.py --input          # -> docs/shader_refs/line_wave_input.jpg (вход генератора)
    python3 tools/line_wave_preview.py --shader ФАЙЛ    # кадр другим вариантом шейдера (путь к .gdshader)
    python3 tools/line_wave_preview.py --cmp            # -> docs/shader_refs/line_wave_cmp.jpg: референс / до / после

«До» — line_wave_input.jpg (кадр шейдером до переделки, его и давали генератору), «после» — кадр текущим шейдером,
«референс» — docs/shader_refs/line_wave.jpg (П10), приведённый к 1500×1000. Снизу — линия крупно. Печатает среднее
отличие от референса (0–255) по трём блокам линии (их лица в нижней строке) — до и после.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_preview as sp  # noqa: E402
import close_preview as cp   # noqa: E402
import line_preview as lp    # noqa: E402

ROOT = sp.ROOT
REFS = os.path.join(ROOT, "docs", "shader_refs")
W, H = 1500, 1000
CELL_PX = 170
T = 0.14            # с от касания поля
FONT = os.path.join(ROOT, "assets", "fonts", "nunito_extrabold.ttf")


def setup(shader="line_wave"):
    """line_preview → крупный кадр: клетка CELL_PX, сетка с рамкой и губой — по центру W × H, без текста комбо."""
    lp.CELL_PX = CELL_PX
    lp.PAD_X = (W - lp.COLS * CELL_PX) // 2
    lp.PAD_TOP = int(round(H / 2 - lp.ROWS * CELL_PX / 2 - sp.BD["FRAME_DEPTH"] / 2))
    lp.PAD_BOTTOM = H - lp.ROWS * CELL_PX - lp.PAD_TOP
    lp.text_state = lambda *a: None
    lp.WAVE_SHADER = os.path.splitext(os.path.abspath(shader))[0] if shader.endswith(".gdshader") else shader


def render(shader="line_wave", t=T):
    setup(shader)
    c = cp.juice_config()
    words, colors, lift = lp.combo_words()
    return lp.frame(t, c, 0, False, words, colors, lift, lp.label_style(), lp.block_flash_fade())


def boxes():
    """Лица блоков в нижней строке (окна для оценки), px кадра."""
    lx, ly, lw, lh = lp.LINE
    out = []
    for rx, ry, rw, rh in (b[:4] for b in lp.BLOCKS):
        x0 = max(lx, rx) * CELL_PX + lp.PAD_X
        x1 = min(lx + lw, rx + rw) * CELL_PX + lp.PAD_X
        y0, y1 = ly * CELL_PX + lp.PAD_TOP, (ly + lh) * CELL_PX + lp.PAD_TOP
        out.append((x0 + 12, y0 + 12, x1 - 12, y1 - 6))
    return out


def score(a, b):
    A, B = np.asarray(a, float), np.asarray(b, float)
    return [float(np.abs(A[y0:y1, x0:x1] - B[y0:y1, x0:x1]).mean()) for x0, y0, x1, y1 in boxes()]


def compare(after):
    setup()
    ref = Image.open(os.path.join(REFS, "line_wave.jpg")).convert("RGB").resize((W, H), Image.LANCZOS)
    before = Image.open(os.path.join(REFS, "line_wave_input.jpg")).convert("RGB")
    trio = [("референс", ref), ("до", before), ("после", after)]
    k = 0.4
    tw, th = int(W * k), int(H * k)
    gap = 10
    out_w = 3 * tw + 2 * gap
    lx, ly, lw, lh = lp.LINE
    crop = (lp.PAD_X - 50, (ly - 1) * CELL_PX + lp.PAD_TOP + 40, lp.PAD_X + lw * CELL_PX + 50,
            (ly + lh) * CELL_PX + lp.PAD_TOP + 60)
    zk = out_w / (crop[2] - crop[0])
    zh = int((crop[3] - crop[1]) * zk)
    out = Image.new("RGB", (out_w, 36 + th + 3 * (zh + gap)), (30, 30, 30))
    d = ImageDraw.Draw(out)
    f = ImageFont.truetype(FONT, 22)
    for i, (title, im) in enumerate(trio):
        out.paste(im.resize((tw, th), Image.LANCZOS), (i * (tw + gap), 36))
        d.text((i * (tw + gap) + 10, 6), title, fill=(255, 255, 255), font=f)
    y = 36 + th + gap
    for title, im in trio:
        out.paste(im.crop(crop).resize((out_w, zh), Image.LANCZOS), (0, y))
        d.text((10, y + 6), title, fill=(255, 255, 255), font=f, stroke_width=2, stroke_fill=(30, 30, 30))
        y += zh + gap
    path = os.path.join(REFS, "line_wave_cmp.jpg")
    out.save(path, quality=90, optimize=True)
    names = ["оранжевый 3", "красный 2", "голубой 6"]
    for n, b, a in zip(names, score(ref, before), score(ref, after)):
        print("%-12s отличие от референса: до %5.1f  после %5.1f" % (n, b, a))
    print("->", os.path.relpath(path, ROOT), out.size)


def main(argv):
    shader = argv[argv.index("--shader") + 1] if "--shader" in argv else "line_wave"
    t = float(argv[argv.index("--t") + 1]) if "--t" in argv else T
    img = render(shader, t)
    if "--input" in argv:
        path = os.path.join(REFS, "line_wave_input.jpg")
        img.save(path, quality=92, optimize=True)
        print("->", os.path.relpath(path, ROOT), img.size)
    elif "--cmp" in argv:
        compare(img)
    else:
        img.save("/tmp/line_wave_frame.png")
        print("-> /tmp/line_wave_frame.png", img.size)


if __name__ == "__main__":
    main(sys.argv[1:])
