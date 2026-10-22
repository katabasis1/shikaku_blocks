#!/usr/bin/env python3
"""Этап 14.6: кадр «появление уровня» по шагам — ячейки поля волной, числа выпрыгивают после своих ячеек, блоки
выезжают в лоток по одному; из настоящих шейдеров (board.gdshader — рамка и ячейки с униформами appear /
appear_step, nest.gdshader — гнёзда чисел, block.gdshader и shelf.gdshader — лоток) через переводчик
tools/shader_preview.py, раскладка портрета 720×1280 — tools/layout_model.py.

Время — от Board.setup / Tray.setup (миг, когда уровень построен). Повторены:
  * Board._play_appear: униформа appear = t, appear_step = intro_cell_step (ячейка (x, y) — через step · (x + y);
    рост ×0,3 → 1 с перелётом за 0,35 с — в самом шейдере);
  * Cell.appear(step · (x + y) + intro_number_delay): прозрачность 0 → 1 за 35 % intro_number_time (линейно),
    масштаб ×intro_number_from → 1 и подъём снизу с intro_number_rise px экрана → 0 за intro_number_time
    (TRANS_BACK, EASE_OUT); «Меньше движения» — только проявление за intro_number_time;
  * Tray.setup → Block.slide_in(intro_block_start + intro_block_step · i, Tray.slide_dir()): Visual проявляется за
    35 % intro_block_time и въезжает с intro_block_from px экрана снизу (в портрете) за intro_block_time
    (TRANS_BACK, EASE_OUT); «Меньше движения» — только проявление за intro_block_time.
Уровень 12 (5×6) — как в selftest; в лотке — три блока этого уровня (порядок очереди в игре свой).
Шапка, кнопки и плашка «Осталось блоков» не появляются — нарисованы на месте. В альбоме блоки едут справа, от края
экрана (Tray.slide_dir) — в кадр не входит, шторка — отдельный кадр G14_6_curtain.png (tools/curtain_preview.py).

    python3 tools/intro_preview.py     # -> docs/style_frames/G14_6_intro.png
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_preview as sp    # noqa: E402
import close_preview as cp     # noqa: E402
import layout_model as lm      # noqa: E402

ROOT = sp.ROOT
OUT = os.path.join(sp.FRAMES, "G14_6_intro.png")
LEVEL = 12
TRAY = [0, 1, 3]          # какие прямоугольники уровня лежат в гнёздах 0, 1, 2
TIMES = [0.0, 0.08, 0.16, 0.24, 0.32, 0.4, 0.5, 0.6, 0.8]
SCREEN_W, SCREEN_H = 720, 1280
SCALE = 0.38              # кадр экрана уменьшается до SCALE
CAPTION = 44
ROW_TITLE = 36            # на строку заголовка
FOOT = 40


def fmt(x, nd=2):
    s = ("%." + str(nd) + "f") % x
    s = s.rstrip("0").rstrip(".") if "." in s else s
    return s.replace(".", ",")


def number_state(t, delay, c, reduced):
    """Cell.appear: прозрачность, масштаб, подъём (px экрана) числа в миг t."""
    time = max(c["intro_number_time"], 0.01)
    if reduced:
        return cp.seg(t, delay, time), 1.0, 0.0
    a = cp.seg(t, delay, time * 0.35)
    u = cp.back_out(cp.seg(t, delay, time))
    return a, cp.lerp(c["intro_number_from"], 1.0, u), cp.lerp(c["intro_number_rise"], 0.0, u)


def block_state(t, delay, c, reduced):
    """Block.slide_in: прозрачность Visual и сдвиг выезда (px экрана) в миг t."""
    time = max(c["intro_block_time"], 0.01)
    if reduced:
        return cp.seg(t, delay, time), 0.0
    a = cp.seg(t, delay, time * 0.35)
    return a, cp.lerp(c["intro_block_from"], 0.0, cp.back_out(cp.seg(t, delay, time)))


def board_place(cols, rows):
    """Левый верх сетки на экране и px клетки — как shader_preview.render (поле по центру BOARD_C)."""
    cell_px = sp.CELL_PX
    return sp.BOARD_C[0] - cols * cell_px / 2, sp.BOARD_C[1] - rows * cell_px / 2, cell_px


def draw_static(cv, remaining):
    sp.draw_buttons(cv, badge="3")
    L = lm.compute(SCREEN_W, SCREEN_H, False)
    sp.draw_header(cv, L, level=LEVEL, score=2340)
    sp.draw_pill(cv, L, text="Осталось блоков: %d" % remaining)


def tray_block(cv, sr, rect, alpha, slide):
    """Блок в гнезде (Tray._place_in_slot, цифра по центру), Visual сдвинут вниз на slide px, прозрачность alpha."""
    if alpha <= 0.001:
        return
    _, _, bw, bh, _, _ = rect
    k = min(sp.TRAY_SCALE, (sr[2] - sp.SLOT_MARGIN) / (bw * sp.CELL), (sr[3] - sp.SLOT_MARGIN) / (bh * sp.CELL))
    gx = sr[0] + (sr[2] - bw * sp.CELL * k) / 2
    gy = sr[1] + (sr[3] - bh * sp.CELL * k) / 2 + slide
    if alpha >= 0.999:
        sp.draw_block(cv, gx, gy, k, bw, bh, bw * bh, None, False)
        return
    # modulate.a у Visual: рисуем блок на копии и смешиваем.
    before = cv.rgb.copy()
    sp.draw_block(cv, gx, gy, k, bw, bh, bw * bh, None, False)
    cv.rgb = before + (cv.rgb - before) * alpha


def frame(t, c, reduced, level, bg):
    cols, rows, rects = level
    cv = sp.Canvas(np.zeros((SCREEN_H, SCREEN_W, 3)))
    cv.rgb = bg.copy()
    ox, oy, cell_px = board_place(cols, rows)
    s = cell_px / sp.CELL
    px = 1.0 / s
    step = c["intro_cell_step"]
    # Board/Frame с униформой appear: ячейки вырастают волной.
    m = (sp.BD["FRAME_MARGIN"] + sp.BD["PAD"]) * px
    fw, fh = cols * sp.CELL + 2 * m, rows * sp.CELL + 2 * m + sp.BD["FRAME_DEPTH"] * px
    sp.draw_rect(cv, "board", ox - m * s, oy - m * s, fw, fh, s, (1, 1, 1, 1), {
        "frame_size": (fw, fh), "grid": (float(cols), float(rows)), "px": px, "margin": sp.BD["FRAME_MARGIN"],
        "pad": sp.BD["PAD"], "rim": sp.BD["RIM"], "lip": sp.BD["FRAME_DEPTH"],
        "appear": t, "appear_step": step})
    # Cells с числами: Cell.scale вокруг pivot (50, 50), подъём — position на rise px экрана, modulate.a.
    for rx, ry, rw, rh, nx, ny in rects:
        area = rw * rh
        a, k, rise = number_state(t, step * (nx + ny) + c["intro_number_delay"], c, reduced)
        if a <= 0.001:
            continue
        bx, by = nx * sp.CELL, ny * sp.CELL + rise * px
        col = sp.color_for(area)
        sp.draw_rect(cv, "nest", ox + (bx + 50 - 98 * k) * s, oy + (by + 50 - 98 * k) * s, sp.CELL + 96,
                     sp.CELL + 96, s * k, col[:3] + (a,), {"px": px, "ring": 0.0, "margin": 48.0})
        sp.draw_digit(cv, str(area), ox + (bx + 50) * s, oy + (by + 50) * s, 40 * s * k, col,
                      sp.darkened(col, 0.42), sp.CL["DIGIT_OUTLINE"] * s * k,
                      sp.darkened(col, 0.5)[:3] + (0.35,), (0, 2 * s * k), a)
    # Content/Tray: полка, гнёзда заняты (блок уже в гнезде, едет только Visual), блоки по одному.
    L = lm.compute(SCREEN_W, SCREEN_H, False)
    shelf = L["shelf"]
    slots = lm.slots(L)
    params = {"shelf_size": (shelf[2], shelf[3]), "well_empty": (0.0, 0.0, 0.0)}
    for i, sr in enumerate(slots):
        params["well%d" % i] = (sr[0] - shelf[0], sr[1] - shelf[1], sr[2], sr[3])
    sp.draw_rect(cv, "shelf", shelf[0], shelf[1], shelf[2], shelf[3], 1.0, (1, 1, 1, 1), params)
    draw_static(cv, len(rects))
    for i, sr in enumerate(slots):
        a, slide = block_state(t, c["intro_block_start"] + c["intro_block_step"] * i, c, reduced)
        tray_block(cv, sr, rects[TRAY[i]], a, slide)
    return cv.image()


def done_at(level, c):
    cols, rows, rects = level
    step = c["intro_cell_step"]
    cells = step * (cols - 1 + rows - 1) + 0.35
    numbers = max(step * (nx + ny) for _, _, _, _, nx, ny in rects) + c["intro_number_delay"] + c["intro_number_time"]
    blocks = c["intro_block_start"] + c["intro_block_step"] * 2 + c["intro_block_time"]
    return cells, numbers, blocks


def main():
    c = cp.juice_config()
    level = sp.load_level(LEVEL)
    bg = sp.background(SCREEN_W, SCREEN_H).rgb
    font = ImageFont.truetype(sp.UI_FONT, 26)
    small = ImageFont.truetype(sp.UI_FONT, 22)
    fw, fh = int(round(SCREEN_W * SCALE)), int(round(SCREEN_H * SCALE))
    cells, numbers, blocks = done_at(level, c)
    rows = [
        (False, "Появление уровня %d (%d×%d): ячейки волной (шаг %s с по диагонали), число — через %s с после своей "
         "ячейки:\nснизу с %s px и с ×%s до ×1 за %s с с дожимом; блоки по одному (гнездо i — через %s + %s · i с) "
         "снизу с %s px за %s с с пружиной" % (LEVEL, level[0], level[1], fmt(c["intro_cell_step"]), fmt(c["intro_number_delay"]),
                                fmt(c["intro_number_rise"], 0), fmt(c["intro_number_from"], 1),
                                fmt(c["intro_number_time"]), fmt(c["intro_block_start"]),
                                fmt(c["intro_block_step"]), fmt(c["intro_block_from"], 0),
                                fmt(c["intro_block_time"]))),
        (True, "«Меньше движения»: ячейки — той же волной, числа (%s с) и блоки (%s с) только проявляются, без "
         "прыжка и выезда" % (fmt(c["intro_number_time"]), fmt(c["intro_block_time"]))),
    ]
    W = fw * len(TIMES)
    H = FOOT + sum(ROW_TITLE * (t.count("\n") + 1) + 6 + fh + CAPTION for _, t in rows)
    out = Image.new("RGB", (W, H), (36, 18, 92))
    d = ImageDraw.Draw(out)
    y = 0
    for reduced, title in rows:
        for j, line in enumerate(title.split("\n")):
            d.text((16, y + 7 + j * ROW_TITLE), line, font=font, fill=(255, 255, 255))
        y += ROW_TITLE * (title.count("\n") + 1) + 6
        for i, t in enumerate(TIMES):
            img = frame(t, c, reduced, level, bg).resize((fw, fh), Image.LANCZOS)
            out.paste(img, (i * fw, y))
            cap = "%d мс" % round(t * 1000)
            if t == 0:
                cap += " · старт"
            elif t >= max(cells, numbers, blocks):
                cap += " · всё на месте"
            d.text((i * fw + fw / 2, y + fh + CAPTION / 2), cap, font=font, fill=(255, 228, 92), anchor="mm")
        y += fh + CAPTION
    d.text((16, y + 8), "Время — от Board.setup. Ячейки встают к %s с, числа — к %s с, блоки — к %s с. Ввод не ждёт: "
           "блок можно взять на лету. В альбоме блоки едут справа (Tray.slide_dir); шторка — G14_6_curtain.png."
           % (fmt(cells), fmt(numbers), fmt(blocks)), font=small, fill=(200, 190, 255))
    out.save(OUT, optimize=True)
    print("->", os.path.relpath(OUT, ROOT), out.size)


if __name__ == "__main__":
    main()
