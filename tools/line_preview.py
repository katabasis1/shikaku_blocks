#!/usr/bin/env python3
"""Этап 14.4: кадр «линия и серия» — что видно в миг удара блока, закрывшего линию, по шагам; из настоящих
шейдеров (shaders/line_wave.gdshader — волна, shaders/block.gdshader — вспышка `flash` и свет `glow` закрытого
числа, board / nest — поле) через переводчик tools/shader_preview.py.

Сцена — поле 6×3, клетка 60 px: блок 2 (2×1) только что встал в столбцы 1–2 нижней строки и закрыл её. Волна
бежит из его клеток к обоим концам строки (до левого — 2 клетки, до правого — 4: фронт доходит до дальнего конца
за line_wave_time), блоки 3 и 6 вспыхивают, когда до них дошёл фронт (LineFlash.arrival), над блоком — текст
комбо «штампом» (на 70 px экрана выше середины блока — почти над линией). На самом блоке 2 — закрытое число 14.3
(вспышка цифры, галочка, свет по клеткам).

Ряды: сила хода 0 (первая линия серии), сила 4 (наибольшая) и «Меньше движения» при силе 4. Время — от мига
касания поля (Board.landed → Game._on_block_landed). Первые hitstop_line + combo_hitstop · сила — hit-stop:
твины эффектов (волна, вспышка, штамп, закрытое число) созданы, но стоят — на экране их ещё нет. Твины повторены
по LineFlash.play / arrival, Block.flash, FloatingText.slam и Block.close_number (через tools/close_preview.py):
те же шаги, переходы и числа из scripts/juice_config.gd, floating_text.gd, game.gd и темы. Не нарисованы:
тряска Content, сплющивание блока (Block.squash), искры вдоль линии (частицы случайны).

    python3 tools/line_preview.py     # -> docs/style_frames/G14_4_line.png
"""
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_preview as sp  # noqa: E402
import close_preview as cp   # noqa: E402

ROOT = sp.ROOT
OUT = os.path.join(sp.FRAMES, "G14_4_line.png")
TIMES = [0.0, 0.06, 0.12, 0.2, 0.3, 0.45, 0.7, 1.0]
COLS, ROWS = 6, 3
LINE = (0, 2, COLS, 1)            # Rect2i закрытой линии: нижняя строка
# Блоки на поле: (x, y, w, h, число x, число y); PLACED — тот, что только что встал и закрыл линию.
BLOCKS = [(0, 0, 1, 3, 0, 0), (1, 2, 2, 1, 1, 2), (3, 1, 3, 2, 5, 1)]
PLACED = 1
NESTS = [(1, 0, 2, 2, 1, 0), (3, 0, 3, 1, 4, 0)]   # пустые места: гнёзда с числами
CELL_PX = 60
PAD_X = 40          # поле вокруг сетки в кадре, px
PAD_TOP = 48
PAD_BOTTOM = 40
CAPTION = 46        # подпись под кадром, px
ROW_TITLE = 42
FOOT = 40


def gd_src(path):
    return open(os.path.join(ROOT, path), encoding="utf-8").read()


def need(m, what):
    if not m:
        raise KeyError("не найдено: " + what)
    return m


def combo_words():
    src = gd_src("scenes/game/game.gd")
    words = re.findall(r'"([^"]+)"', need(re.search(r"const COMBO_WORDS[^=]*=\s*\[(.*?)\]", src), "COMBO_WORDS").group(1))
    body = need(re.search(r"const COMBO_COLORS[^=]*=\s*\[(.*?)\]\n", src), "COMBO_COLORS").group(1)
    cols = [tuple(float(x) for x in m.split(",")) for m in re.findall(r"Color\(([^)]*)\)", body)]
    lift = float(need(re.search(r"cell_center_global\(r\) \+ Vector2\(0, (-?[0-9.]+)\)", src), "сдвиг текста").group(1))
    return words, cols, lift


def label_style():
    """FloatingText/Text: обводка из floating_text.tscn, цвета обводки и тени — Label в main_theme.tres."""
    tscn = gd_src("scenes/ui/floating_text.tscn")
    theme = gd_src("theme/main_theme.tres")
    outline = float(need(re.search(r"outline_size = (\d+)", tscn), "outline_size").group(1))

    def col(name):
        m = need(re.search(r"^Label/colors/%s = Color\(([^)]*)\)" % name, theme, re.M), name)
        return tuple(float(x) for x in m.group(1).split(","))

    sy = float(need(re.search(r"^Label/constants/shadow_offset_y = (-?\d+)", theme, re.M), "shadow_offset_y").group(1))
    return outline, col("font_outline_color"), col("font_shadow_color"), sy


def block_flash_fade():
    src = gd_src("scenes/game/block.gd")
    m = need(re.search(r'"flash", v\), amount, 0\.0, ([0-9.]+)\)', src), "время вспышки Block.flash")
    return float(m.group(1))


def fmt(x, nd=2):
    s = ("%." + str(nd) + "f") % x
    s = s.rstrip("0").rstrip(".") if "." in s else s
    return s.replace(".", ",")


# ---------------------------------------------------------------- твины эффектов (время te — после hit-stop)

def hit_stop(c, power):
    return min(c["hitstop_line"] + c["combo_hitstop"] * power, c["hitstop_max"])


def line_geometry():
    """LineFlash: размер узла, точка старта (середина клеток блока на линии), путь до дальнего конца — px поля."""
    lx, ly, lw, lh = LINE
    bx, by, bw, bh = BLOCKS[PLACED][:4]
    ix0, iy0 = max(lx, bx), max(ly, by)
    ix1, iy1 = min(lx + lw, bx + bw), min(ly + lh, by + bh)
    size = (lw * sp.CELL, lh * sp.CELL)
    origin = (((ix0 - lx) + (ix1 - ix0) * 0.5) * sp.CELL, ((iy0 - ly) + (iy1 - iy0) * 0.5) * sp.CELL)
    horiz = size[0] >= size[1]
    along, span = (origin[0], size[0]) if horiz else (origin[1], size[1])
    return size, origin, max(along, span - along, 1.0), horiz


def arrival(p, c):
    """LineFlash.arrival: через сколько секунд фронт дойдёт до точки p (px узла)."""
    size, origin, reach, horiz = line_geometry()
    d = abs(p[0] - origin[0]) if horiz else abs(p[1] - origin[1])
    k = min(max(d / reach, 0.0), 1.0)
    return c["line_wave_time"] * (1.0 - math.sqrt(1.0 - k))


def wave_peak(c, power, reduced):
    peak = min(max(c["line_wave_strength"] + c["combo_wave"] * power, 0.0), 1.0)
    return min(peak, c["reduced_wave"]) if reduced else peak


def flash_amount(c, power, reduced):
    amount = c["line_block_flash"] + c["combo_flash"] * power
    return min(amount, c["reduced_wave"]) if reduced else amount


def wave_state(te, c, power, reduced):
    """Сила и путь фронта волны (LineFlash.play): None — узла ещё (hit-stop) или уже (доиграл) нет."""
    if te is None:
        return 0.0, 0.0
    _, _, reach, _ = line_geometry()
    T, fade, peak = max(c["line_wave_time"], 0.01), max(c["line_fade"], 0.01), wave_peak(c, power, reduced)
    if te < T:
        u = te / T
        return peak, reach * (1.0 - (1.0 - u) ** 2)
    if te < T + fade:
        return peak * (1.0 - (te - T) / fade), reach
    return None


def flash_state(te, delay, c, power, reduced, fade):
    """Block.flash(delay, amount): ждёт delay, потом amount → 0 за fade, линейно."""
    if te is None or te < delay:
        return 0.0
    return flash_amount(c, power, reduced) * max(0.0, 1.0 - (te - delay) / fade)


def text_state(te, c, power, reduced):
    """FloatingText.slam (через Fx.combo_text): масштаб, прозрачность, подъём (px экрана) или None — нет узла."""
    if te is None:
        return 0.0, 1.0, 0.0   # создан, но стоит: modulate.a = 0
    under = sp.gd_value(sp.gd_const("scenes/ui/floating_text.gd", "SLAM_UNDER"))
    hold = sp.gd_value(sp.gd_const("scenes/ui/floating_text.gd", "SLAM_HOLD"))
    rise = sp.gd_value(sp.gd_const("scenes/ui/floating_text.gd", "SLAM_RISE"))
    fly = sp.gd_value(sp.gd_const("scenes/ui/floating_text.gd", "SLAM_FLY"))
    slam = 0.0 if reduced else c["combo_slam"] + c["combo_slam_grow"] * power
    ts = max(c["combo_slam_time"], 0.01)
    if slam > 1.0:
        alpha = min(te / (ts * 0.6), 1.0)
        if te < ts:
            scale = cp.lerp(slam, under, cp.quad_in(te / ts))
        else:
            scale = cp.lerp(under, 1.0, cp.back_out(cp.seg(te, ts, 0.12)))
        h0 = ts + 0.12
    else:
        alpha, scale, h0 = min(te / 0.15, 1.0), 1.0, 0.15
    f0 = h0 + hold
    if te >= f0 + fly:
        return None
    u = cp.seg(te, f0, fly)
    dy = -rise * (1.0 - math.cos(u * math.pi / 2))          # TRANS_SINE, EASE_IN
    alpha *= 1.0 - cp.seg(te, f0 + fly * 0.4, fly * 0.6)
    return alpha, scale, dy


def glow_state(te, c, reduced):
    """Свет закрытого числа по клеткам блока (Block._glow_step, 14.3) — как close_preview.glow_state."""
    if te is None or reduced or te >= c["glow_time"]:
        return 0.0, 0.0
    bx, by, bw, bh, nx, ny = BLOCKS[PLACED]
    cell = sp.CELL
    lift = sp.B["DEPTH"] * cell * 0.6
    fx, fy = (nx - bx + 0.5) * cell, (ny - by + 0.5) * cell - lift
    reach = max(math.hypot(fx - x, fy - y) for x in (0, bw * cell) for y in (0, bh * cell))
    v = te / c["glow_time"]
    return c["glow_strength"] * (1 - v), v * (reach + 0.3 * cell)


# ---------------------------------------------------------------- кадр

def frame_size():
    return COLS * CELL_PX + 2 * PAD_X, ROWS * CELL_PX + PAD_TOP + PAD_BOTTOM


_bg = {}


def draw_block(cv, ox, oy, s, rect, flash=0.0, glow=(0.0, 0.0), close=None):
    """Block на поле (как shader_preview.draw_block) + униформы flash / glow и цифра закрытого числа."""
    px = 1.0 / s
    rx, ry, rw, rh, nx, ny = rect
    area = rw * rh
    col = sp.color_for(area)
    m = sp.B["MARGIN_REST"] * px
    w, h = rw * sp.CELL, rh * sp.CELL
    lift = sp.B["DEPTH"] * sp.CELL * 0.6
    center = ((nx - rx + 0.5) * sp.CELL, (ny - ry + 0.5) * sp.CELL - lift)
    gx, gy = ox + rx * CELL_PX, oy + ry * CELL_PX
    sp.draw_rect(cv, "block", gx - m * s, gy - m * s, w + 2 * m, h + 2 * m, s, col, {
        "rect_size": (w, h), "cells": (float(rw), float(rh)), "margin": m, "num_center": center, "px": px,
        "shadow_offset": sp.B["SHADOW_REST"], "shadow_blur": sp.B["BLUR_REST"], "shadow_color": sp.SHADE,
        "flash": flash, "glow": glow[0], "glow_r": glow[1]})
    st = close or {"d_scale": 1.0, "d_mod": 1.0, "d_alpha": 1.0, "c_scale": 1.0, "c_alpha": 0.0}
    k, md = st["d_scale"], st["d_mod"]

    def mod(cc):
        return tuple(min(1.0, x * md) for x in cc[:3]) + tuple(cc[3:])

    cx, cy = gx + center[0] * s, gy + center[1] * s
    if st["d_alpha"] > 0.001:
        sp.draw_digit(cv, str(area), cx, cy, 46 * s * k, mod((1, 1, 1, 1)), mod(sp.darkened(col, 0.45)),
                      sp.B["DIGIT_OUTLINE"] * s * k, mod(sp.darkened(col, 0.6))[:3] + (0.47,), (0, 4 * s * k),
                      st["d_alpha"])
    if st["c_alpha"] > 0.001:
        kc = st["c_scale"]
        sp.draw_rect(cv, "check", cx - 50 * kc * s, cy - 50 * kc * s, 100, 100, s * kc, (1, 1, 1, st["c_alpha"]), {
            "rect_size": (100.0, 100.0), "outline": sp.B["DIGIT_OUTLINE"],
            "outline_color": sp.darkened(col, 0.45), "shadow_color": sp.darkened(col, 0.6)[:3] + (0.47,)})


def frame(t, c, power, reduced, words, colors, text_lift, style, fade):
    s = CELL_PX / sp.CELL
    px = 1.0 / s
    f = CELL_PX / sp.CELL_PX            # px экрана игры (клетка CELL_PX shader_preview) → px кадра
    w, h = frame_size()
    if (w, h) not in _bg:
        _bg[(w, h)] = sp.background(w, h).rgb
    cv = sp.Canvas(np.zeros((h, w, 3)))
    cv.rgb = _bg[(w, h)].copy()
    ox, oy = PAD_X, PAD_TOP
    hs = hit_stop(c, power)
    te = None if t < hs else t - hs
    # Board/Frame
    m = (sp.BD["FRAME_MARGIN"] + sp.BD["PAD"]) * px
    fw, fh = COLS * sp.CELL + 2 * m, ROWS * sp.CELL + 2 * m + sp.BD["FRAME_DEPTH"] * px
    sp.draw_rect(cv, "board", ox - m * s, oy - m * s, fw, fh, s, (1, 1, 1, 1), {
        "frame_size": (fw, fh), "grid": (float(COLS), float(ROWS)), "px": px, "margin": sp.BD["FRAME_MARGIN"],
        "pad": sp.BD["PAD"], "rim": sp.BD["RIM"], "lip": sp.BD["FRAME_DEPTH"]})
    # Cells: гнёзда пустых мест (никто не несёт блок — без магнита и без приглушения).
    for rx, ry, rw, rh, nx, ny in NESTS:
        area = rw * rh
        col = sp.color_for(area)
        sp.draw_rect(cv, "nest", ox + (nx * sp.CELL - 48) * s, oy + (ny * sp.CELL - 48) * s, sp.CELL + 96,
                     sp.CELL + 96, s, col, {"px": px, "ring": 0.0, "margin": 48.0})
        sp.draw_digit(cv, str(area), ox + (nx * sp.CELL + 50) * s, oy + (ny * sp.CELL + 50) * s, 40 * s, col,
                      sp.darkened(col, 0.42), sp.CL["DIGIT_OUTLINE"] * s, sp.darkened(col, 0.5)[:3] + (0.35,),
                      (0, 2 * s))
    # Блоки по рядам (Board._sort_block): вспышка — когда до части блока на линии дошёл фронт.
    lx, ly, lw, lh = LINE
    for i in sorted(range(len(BLOCKS)), key=lambda j: (BLOCKS[j][1], BLOCKS[j][0])):
        rect = BLOCKS[i]
        rx, ry, rw, rh = rect[:4]
        ix0, iy0, ix1, iy1 = max(lx, rx), max(ly, ry), min(lx + lw, rx + rw), min(ly + lh, ry + rh)
        fl = 0.0
        if ix1 > ix0 and iy1 > iy0:
            mid = (((ix0 - lx) + (ix1 - ix0) * 0.5) * sp.CELL, ((iy0 - ly) + (iy1 - iy0) * 0.5) * sp.CELL)
            fl = flash_state(te, arrival(mid, c), c, power, reduced, fade)
        if i == PLACED:
            close = cp.close_state(te, c) if te is not None else None
            draw_block(cv, ox, oy, s, rect, fl, glow_state(te, c, reduced), close)
        else:
            draw_block(cv, ox, oy, s, rect, fl)
    # Board/Fx/LineFlash — поверх блоков.
    ws = wave_state(te, c, power, reduced)
    if ws is not None and ws[0] > 0.001:
        size, origin, _, _ = line_geometry()
        sp.draw_rect(cv, "line_wave", ox + lx * CELL_PX, oy + ly * CELL_PX, size[0], size[1], s, (1, 1, 1, 1), {
            "rect_size": size, "radius": sp.gd_value(sp.gd_const("scenes/game/line_flash.gd", "RADIUS")),
            "origin": origin, "front": ws[1], "band": c["line_wave_width"] * sp.CELL, "trail": c["line_trail"],
            "strength": ws[0]})
    # FxLayer/FloatingText: над серединой блока на text_lift px экрана.
    ts = text_state(te, c, power, reduced)
    if ts is not None and ts[0] > 0.001:
        alpha, scale, dy = ts
        word = min(power, len(words) - 1)
        bx, by, bw, bh = BLOCKS[PLACED][:4]
        cx = ox + (bx + bw * 0.5) * CELL_PX
        cy = oy + (by + bh * 0.5) * CELL_PX + (text_lift + dy) * f
        size = (c["combo_text_size"] + c["combo_text_grow"] * power) * f * scale
        outline, ocol, scol, sy = style
        sp.draw_digit(cv, words[word], cx, cy, size, colors[word] + (1.0,), ocol, outline * f * scale, scol,
                      (0, sy * f * scale), alpha, font_path=sp.UI_FONT)
    return cv.image()


def main():
    c = cp.juice_config()
    words, colors, text_lift = combo_words()
    style = label_style()
    fade = block_flash_fade()
    font = ImageFont.truetype(sp.UI_FONT, 26)
    small = ImageFont.truetype(sp.UI_FONT, 22)
    pmax = int(c["combo_max"])

    def title(power, reduced):
        word = words[min(power, len(words) - 1)]
        size = int(c["combo_text_size"] + c["combo_text_grow"] * power)
        hs = round(hit_stop(c, power) * 1000)
        if reduced:
            return ("«Меньше движения», сила %d: волна %s и вспышка блоков %s (не сильнее %s), «%s» без штампа "
                    "(проявляется), нет света по клеткам и тряски; hit-stop %d мс"
                    % (power, fmt(wave_peak(c, power, True)), fmt(flash_amount(c, power, True)),
                       fmt(c["reduced_wave"]), word, hs))
        lead = "первая линия серии" if power == 0 else "наибольшая: 5-й ход серии или 2 линии на 4-м ходу"
        return ("Сила %d (%s): «%s» %d px, штамп ×%s, волна %s, вспышка блоков %s, тряска %s, hit-stop %d мс"
                % (power, lead, word, size, fmt(c["combo_slam"] + c["combo_slam_grow"] * power),
                   fmt(wave_peak(c, power, False)), fmt(flash_amount(c, power, False)),
                   fmt(c["trauma_line"] + c["combo_trauma"] * power), hs))

    rows = [(0, False), (pmax, False), (pmax, True)]
    fw, fh = frame_size()
    W = fw * len(TIMES)
    H = len(rows) * (ROW_TITLE + fh + CAPTION) + FOOT
    out = Image.new("RGB", (W, H), (36, 18, 92))
    d = ImageDraw.Draw(out)
    y = 0
    for power, reduced in rows:
        d.text((16, y + 7), title(power, reduced), font=font, fill=(255, 255, 255))
        y += ROW_TITLE
        hs = hit_stop(c, power)
        for i, t in enumerate(TIMES):
            out.paste(frame(t, c, power, reduced, words, colors, text_lift, style, fade), (i * fw, y))
            cap = "%d мс" % round(t * 1000)
            if t == 0:
                cap += " · удар"
            elif t < hs:
                cap += " · hit-stop"
            d.text((i * fw + fw / 2, y + fh + CAPTION / 2), cap, font=font, fill=(255, 228, 92), anchor="mm")
        y += fh + CAPTION
    d.text((16, y + 8), "Время — от касания поля (Board.landed). Пока идёт hit-stop, твины эффектов стоят. "
           "Не нарисованы: тряска Content, сплющивание блока, искры вдоль линии. "
           "Сцена: блок 2 закрыл нижнюю строку, волна — из его клеток к обоим концам.",
           font=small, fill=(200, 190, 255))
    out.save(OUT, optimize=True)
    print("->", os.path.relpath(OUT, ROOT), out.size)


if __name__ == "__main__":
    main()
