#!/usr/bin/env python3
"""Этап 14.5: кадр «победа» — удар последнего блока, волна по полю, мозаика и звёзды окна по шагам; из настоящих
шейдеров (shaders/win_wave.gdshader — волна, shaders/block.gdshader — вспышка `flash`, мозаика `merge` и свет
`glow` закрытого числа, board.gdshader — рамка, card.gdshader — карточка окна) через переводчик
tools/shader_preview.py; карточка и звёзды — как в tools/window_preview.py (render_win).

Поле 6×4, клетка 60 px, все места заняты: последний блок 2 (2×1) только что встал в правый нижний угол. Время
верхних рядов — от мига касания поля (Board.landed → Game._on_block_landed → _celebrate). Первые hitstop_win —
hit-stop: твины эффектов (волна, вспышка, подскок, мозаика, закрытое число) созданы, но стоят. Потом от середины
последнего блока к дальнему углу бежит кольцо света (WinWave.play: фронт — reach · (1 − (1 − u)²)), блоки
вспыхивают и подпрыгивают, когда фронт доходит до их середины (WinWave.arrival), и через win_merge_delay сходятся в
мозаику (Block.merge). Последний кадр ряда — миг показа окна (Game.WIN_SHOW_AT от броска = WIN_SHOW_AT − land_time
от касания): дальше поле уезжает на место победы.

Нижние ряды — звёзды окна (WinPanel._play_star) по времени от показа окна: «штамп» заработанной (×star_slam с
поворотом → ×star_slam_squash, EASE_IN; удар; дожим TRANS_BACK), толчок карточки (star_punch за PUNCH_TIME),
незаработанная — тихо (×STAR_QUIET_FROM → 1); счёт накручивается (SCORE_AT, SCORE_TIME). Числа — из
scripts/juice_config.gd, board.gd, win_wave.gd, block.gd, win_panel.gd, game.gd.

Не нарисованы: тряска Content, сплющивание последнего блока (Block.squash), звёздочки удара и искры звёзд (частицы
случайны), лучи и конфетти за полем (WinBackdrop), заголовок окна.

    python3 tools/win_preview.py     # -> docs/style_frames/G14_5_win.png
"""
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_preview as sp    # noqa: E402
import close_preview as cp     # noqa: E402
import window_preview as wp    # noqa: E402

ROOT = sp.ROOT
OUT = os.path.join(sp.FRAMES, "G14_5_win.png")
BOARD_TIMES = [0.0, 0.07, 0.15, 0.25, 0.4, 0.55, 0.75, None]   # None — миг показа окна
STAR_TIMES = [0.5, 0.535, 0.6, 0.64, 0.72, 0.86, 1.08, 1.25]
COLS, ROWS = 6, 4
# Блоки на поле: (x, y, w, h, число x, число y); LAST — тот, что встал последним (удар победы).
BLOCKS = [(0, 0, 3, 2, 1, 0), (3, 0, 3, 1, 4, 0), (3, 1, 1, 2, 3, 2), (4, 1, 2, 2, 5, 1),
          (0, 2, 3, 1, 0, 2), (0, 3, 4, 1, 2, 3), (4, 3, 2, 1, 5, 3)]
LAST = 6
CELL_PX = 60
PAD_X = 40
PAD_TOP = 44
PAD_BOTTOM = 44
CAPTION = 46
ROW_TITLE = 42
FOOT = 40
# Ряд звёзд: участок экрана 720×1280 вокруг верха карточки, рисуется 1:1 и уменьшается до ширины кадра поля.
STAR_CROP_W, STAR_CROP_H = 640, 440
STAR_CARD_TOP = 196      # верх лица карточки на участке, px
STAR_POINTS = {2: 180, 3: 240}


def gd_src(path):
    return open(os.path.join(ROOT, path), encoding="utf-8").read()


def need(m, what):
    if not m:
        raise KeyError("не найдено: " + what)
    return m


def gdc(path, name):
    return sp.gd_value(sp.gd_const(path, name))


def fmt(x, nd=2):
    s = ("%." + str(nd) + "f") % x
    s = s.rstrip("0").rstrip(".") if "." in s else s
    return s.replace(".", ",")


def semitones():
    src = gd_src("scripts/juice_config.gd")
    m = need(re.search(r"@export var star_semitones := PackedInt32Array\(\[([^\]]*)\]\)", src), "star_semitones")
    return [int(x) for x in m.group(1).split(",") if x.strip()]


def block_flash_fade():
    m = need(re.search(r'"flash", v\), amount, 0\.0, ([0-9.]+)\)', gd_src("scenes/game/block.gd")),
             "время вспышки Block.flash")
    return float(m.group(1))


def block_pop_steps():
    """Block.pop: до 1 + strength за t1 (QUAD, EASE_OUT), назад за t2 (BACK, EASE_OUT)."""
    src = gd_src("scenes/game/block.gd")
    body = need(re.search(r"func pop\(.*?\n(.*?)\n\n", src, re.S), "Block.pop").group(1)
    t = [float(x) for x in re.findall(r'"scale", Vector2\.ONE[^,]*, ([0-9.]+)\)', body)]
    need(len(t) == 2, "два шага Block.pop")
    return t


def gap_radius():
    """Зазор и скругление обычного блока (униформы gap / radius по умолчанию в block.gdshader), доли клетки."""
    src = gd_src("shaders/block.gdshader")
    g = float(need(re.search(r"uniform float gap = ([0-9.]+);", src), "gap").group(1))
    r = float(need(re.search(r"uniform float radius = ([0-9.]+);", src), "radius").group(1))
    return g, r


# ---------------------------------------------------------------- лёгкие кривые Godot (Tween)

def cubic_in_out(u):
    return 4 * u ** 3 if u < 0.5 else 1 - (-2 * u + 2) ** 3 / 2


def sine_out(u):
    return math.sin(u * math.pi / 2)


# ---------------------------------------------------------------- поле: волна, вспышка, подскок, мозаика

def board_size():
    return COLS * sp.CELL, ROWS * sp.CELL


def origin():
    bx, by, bw, bh = BLOCKS[LAST][:4]
    return (bx + bw * 0.5) * sp.CELL, (by + bh * 0.5) * sp.CELL


def reach():
    """WinWave: путь фронта — до дальнего угла поля, px поля."""
    ox, oy = origin()
    w, h = board_size()
    return max(max(math.hypot(ox - x, oy - y) for x in (0.0, w) for y in (0.0, h)), 1.0)


def arrival(p, c):
    """WinWave.arrival: через сколько секунд после старта волны фронт дойдёт до точки p (px поля)."""
    ox, oy = origin()
    k = min(max(math.hypot(p[0] - ox, p[1] - oy) / reach(), 0.0), 1.0)
    return c["win_wave_time"] * (1.0 - math.sqrt(1.0 - k))


def wave_peak(c, reduced):
    peak = min(max(c["win_wave_strength"], 0.0), 1.0)
    return min(peak, c["reduced_wave"]) if reduced else peak


def flash_amount(c, reduced):
    return min(c["win_block_flash"], c["reduced_wave"]) if reduced else c["win_block_flash"]


def wave_state(te, c, reduced):
    """Сила и радиус фронта (WinWave.play); (0, 0) — узел создан, но стоит (hit-stop); None — доиграл и удалён."""
    if te is None:
        return 0.0, 0.0
    T, fade, peak = max(c["win_wave_time"], 0.01), max(c["win_fade"], 0.01), wave_peak(c, reduced)
    if te < T:
        return peak, reach() * cp.quad_out(te / T)
    if te < T + fade:
        return peak * (1.0 - (te - T) / fade), reach()
    return None


def block_state(te, i, c, reduced, fade, pop_steps):
    """Вспышка, масштаб Visual и мозаика блока i в миг te (после hit-stop)."""
    if te is None:
        return 0.0, 1.0, 0.0
    bx, by, bw, bh = BLOCKS[i][:4]
    arr = arrival(((bx + bw * 0.5) * sp.CELL, (by + bh * 0.5) * sp.CELL), c)
    flash = 0.0 if te < arr else flash_amount(c, reduced) * max(0.0, 1.0 - (te - arr) / fade)
    k = 1.0
    if i != LAST and not reduced and c["win_block_pop"] > 0.0 and te >= arr:
        t1, t2 = pop_steps
        top = 1.0 + c["win_block_pop"]
        if te < arr + t1:
            k = cp.lerp(1.0, top, cp.quad_out(cp.seg(te, arr, t1)))
        else:
            k = cp.lerp(top, 1.0, cp.back_out(cp.seg(te, arr + t1, t2)))
    merge = cubic_in_out(cp.seg(te, arr + c["win_merge_delay"], max(c["win_merge_time"], 0.01)))
    return flash, k, merge


def glow_state(te, c, reduced):
    """Свет закрытого числа по клеткам последнего блока (Block._glow_step, 14.3)."""
    if te is None or reduced or te >= c["glow_time"]:
        return 0.0, 0.0
    bx, by, bw, bh, nx, ny = BLOCKS[LAST]
    cell = sp.CELL
    lift = sp.B["DEPTH"] * cell * 0.6
    fx, fy = (nx - bx + 0.5) * cell, (ny - by + 0.5) * cell - lift
    rr = max(math.hypot(fx - x, fy - y) for x in (0, bw * cell) for y in (0, bh * cell))
    v = te / c["glow_time"]
    return c["glow_strength"] * (1 - v), v * (rr + 0.3 * cell)


def board_frame_size():
    return COLS * CELL_PX + 2 * PAD_X, ROWS * CELL_PX + PAD_TOP + PAD_BOTTOM


_bg = {}


def draw_block(cv, ox, oy, s, rect, flash, k, merge, c, glow=(0.0, 0.0), close=None):
    """Block на поле: Visual ×k вокруг середины блока, униформы flash / merge / glow, цифра (и галочка 14.3)."""
    px = 1.0 / s
    rx, ry, rw, rh, nx, ny = rect
    area = rw * rh
    col = sp.color_for(area)
    m = sp.B["MARGIN_REST"] * px
    w, h = rw * sp.CELL, rh * sp.CELL
    lift = sp.B["DEPTH"] * sp.CELL * 0.6
    center = ((nx - rx + 0.5) * sp.CELL, (ny - ry + 0.5) * sp.CELL - lift)
    sk = s * k
    mx, my = ox + (rx + rw * 0.5) * CELL_PX, oy + (ry + rh * 0.5) * CELL_PX   # середина блока на экране
    gx, gy = mx - w * 0.5 * sk, my - h * 0.5 * sk
    sp.draw_rect(cv, "block", gx - m * sk, gy - m * sk, w + 2 * m, h + 2 * m, sk, col, {
        "rect_size": (w, h), "cells": (float(rw), float(rh)), "margin": m, "num_center": center, "px": px,
        "shadow_offset": sp.B["SHADOW_REST"], "shadow_blur": sp.B["BLUR_REST"], "shadow_color": sp.SHADE,
        "flash": flash, "glow": glow[0], "glow_r": glow[1], "merge": merge,
        "merge_gap": c["win_merge_gap"], "merge_radius": c["win_merge_radius"]})
    st = close or {"d_scale": 1.0, "d_mod": 1.0, "d_alpha": 1.0, "c_scale": 1.0, "c_alpha": 0.0}
    dk, md = st["d_scale"] * k, st["d_mod"]

    def mod(cc):
        return tuple(min(1.0, x * md) for x in cc[:3]) + tuple(cc[3:])

    cx, cy = gx + center[0] * sk, gy + center[1] * sk
    if st["d_alpha"] > 0.001:
        sp.draw_digit(cv, str(area), cx, cy, 46 * s * dk, mod((1, 1, 1, 1)), mod(sp.darkened(col, 0.45)),
                      sp.B["DIGIT_OUTLINE"] * s * dk, mod(sp.darkened(col, 0.6))[:3] + (0.47,), (0, 4 * s * dk),
                      st["d_alpha"])
    if st["c_alpha"] > 0.001:
        kc = st["c_scale"] * k
        sp.draw_rect(cv, "check", cx - 50 * kc * s, cy - 50 * kc * s, 100, 100, s * kc, (1, 1, 1, st["c_alpha"]), {
            "rect_size": (100.0, 100.0), "outline": sp.B["DIGIT_OUTLINE"],
            "outline_color": sp.darkened(col, 0.45), "shadow_color": sp.darkened(col, 0.6)[:3] + (0.47,)})


def board_frame(t, c, reduced, fade, pop_steps):
    s = CELL_PX / sp.CELL
    px = 1.0 / s
    w, h = board_frame_size()
    if (w, h) not in _bg:
        _bg[(w, h)] = sp.background(w, h).rgb
    cv = sp.Canvas(np.zeros((h, w, 3)))
    cv.rgb = _bg[(w, h)].copy()
    ox, oy = PAD_X, PAD_TOP
    hs = min(c["hitstop_win"], c["hitstop_max"])
    te = None if t < hs else t - hs
    # Board/Frame
    m = (sp.BD["FRAME_MARGIN"] + sp.BD["PAD"]) * px
    fw, fh = COLS * sp.CELL + 2 * m, ROWS * sp.CELL + 2 * m + sp.BD["FRAME_DEPTH"] * px
    sp.draw_rect(cv, "board", ox - m * s, oy - m * s, fw, fh, s, (1, 1, 1, 1), {
        "frame_size": (fw, fh), "grid": (float(COLS), float(ROWS)), "px": px, "margin": sp.BD["FRAME_MARGIN"],
        "pad": sp.BD["PAD"], "rim": sp.BD["RIM"], "lip": sp.BD["FRAME_DEPTH"]})
    # Блоки по рядам (Board._sort_block); подскочивший блок рисуется на своём месте в порядке (как в Godot).
    for i in sorted(range(len(BLOCKS)), key=lambda j: (BLOCKS[j][1], BLOCKS[j][0])):
        flash, k, merge = block_state(te, i, c, reduced, fade, pop_steps)
        if i == LAST:
            close = cp.close_state(te, c) if te is not None else None
            draw_block(cv, ox, oy, s, BLOCKS[i], flash, k, merge, c, glow_state(te, c, reduced), close)
        else:
            draw_block(cv, ox, oy, s, BLOCKS[i], flash, k, merge, c)
    # Board/Fx/WinWave — поверх блоков, во всё поле.
    ws = wave_state(te, c, reduced)
    if ws is not None and ws[0] > 0.001:
        bw, bh = board_size()
        sp.draw_rect(cv, "win_wave", ox, oy, bw, bh, s, (1, 1, 1, 1), {
            "rect_size": (bw, bh), "radius": gdc("scenes/game/win_wave.gd", "RADIUS"), "origin": origin(),
            "front": ws[1], "band": c["win_wave_width"] * sp.CELL, "trail": c["win_trail"], "strength": ws[0]})
    return cv.image()


# ---------------------------------------------------------------- окно: звёзды, толчок карточки, счёт

W_GD = "scenes/ui/win_panel.gd"


def star_state(t, i, n, c, reduced):
    """Звезда i (WinPanel._play_star) в миг t от показа окна: прозрачность, масштаб, поворот (градусы)."""
    at = gdc(W_GD, "STARS_AT") + gdc(W_GD, "STAR_STEP") * i
    tilt = wp.gd_list(W_GD, "STAR_TILT")[i]
    if i >= n or reduced:
        qf, qt = gdc(W_GD, "STAR_QUIET_FROM"), gdc(W_GD, "STAR_QUIET_TIME")
        u = cp.seg(t, at, qt)
        return u, cp.lerp(qf, 1.0, sine_out(u)), tilt
    ts = max(c["star_slam_time"], 0.01)
    spin = c["star_slam_spin"] * (-1.0 if i % 2 == 0 else 1.0)
    alpha = cp.seg(t, at, ts * 0.5)
    if t < at + ts:
        u = cp.seg(t, at, ts)
        return alpha, cp.lerp(c["star_slam"], c["star_slam_squash"], cp.quad_in(u)), cp.lerp(tilt + spin, tilt,
                                                                                            cp.quad_out(u))
    u = cp.seg(t, at + ts, max(c["star_settle_time"], 0.01))
    return alpha, cp.lerp(c["star_slam_squash"], 1.0, cp.back_out(u)), tilt


def card_offset(t, n, c, reduced):
    """Толчок карточки вниз (star_punch) от удара каждой заработанной звезды: px."""
    if reduced or c["star_punch"] <= 0.0:
        return 0.0
    pt = gdc(W_GD, "PUNCH_TIME")
    dy = 0.0
    for i in range(n):
        hit = gdc(W_GD, "STARS_AT") + gdc(W_GD, "STAR_STEP") * i + max(c["star_slam_time"], 0.01)
        if hit <= t < hit + pt:
            dy = c["star_punch"] * (1.0 - cp.back_out(cp.seg(t, hit, pt)))
    return dy


def star_frame(t, c, n, reduced, out_w):
    cw, ch = STAR_CROP_W, STAR_CROP_H
    cv = sp.background(cw, ch, win=True)
    L = wp.lm.compute(720, 1280, wp.lm.pick(720, 1280, False))
    card_w, card_h = L["win_card"][2], L["win_card"][3]
    cx0 = (cw - card_w) / 2
    cy0 = STAR_CARD_TOP + card_offset(t, n, c, reduced)
    wp.draw_card(cv, (cx0, cy0, card_w, card_h), "orange")
    N = wp.tscn_nodes("scenes/ui/win_panel.tscn")
    heads = re.findall(r'"([^"]+)"', need(re.search(r"const WIN_HEADS[^=]*=\s*\[(.*?)\]", gd_src(W_GD)),
                                          "WIN_HEADS").group(1))
    hx, hy, hw, hh = wp.node_rect(N["Head"])
    wp.label(cv, heads[max(0, min(n, len(heads)) - 1)], cx0 + hx + hw / 2, cy0 + hy + hh / 2, "WinHead")
    # Строка очков: «+N» накручивается (SCORE_AT, SCORE_TIME, QUAD EASE_OUT), ряд по центру (_place_score_row);
    # в конце «+N» ×1,15 за 0,08 с и назад за 0,18 с (BACK).
    points = STAR_POINTS[n]
    sa, stime = gdc(W_GD, "SCORE_AT"), gdc(W_GD, "SCORE_TIME")
    shown = int(round(points * cp.quad_out(cp.seg(t, sa, stime))))
    end = sa + stime
    sk = cp.lerp(1.0, 1.15, cp.seg(t, end, 0.08)) if t < end + 0.08 else cp.lerp(1.15, 1.0, cp.back_out(cp.seg(t, end + 0.08, 0.18)))
    score_y, score_star, gap = gdc(W_GD, "SCORE_Y"), gdc(W_GD, "SCORE_STAR"), gdc(W_GD, "SCORE_GAP")
    fit, star_cy = gdc(W_GD, "STAR_FIT"), gdc(W_GD, "STAR_CY")
    sh_col, sh_a = gdc(W_GD, "STAR_SHADOW"), gdc(W_GD, "STAR_SHADOW_ALPHA")
    txt = "+" + "{:,}".format(shown).replace(",", "\u00a0")
    sfs = int(wp.th("WinScore", "font_sizes", "font_size", 48))
    tw = wp.text_w(txt, wp.font_of("WinScore"), sfs)
    x0 = (card_w - (score_star + gap + tw)) / 2
    box = 1.75 * score_star * 0.5 / fit
    q = score_star * 0.5 / 56.0
    lay, mpad = wp.with_tex_shadow(wp.png_layer("star", box), 4, (0.0, 8 * q), 10 * q, sh_col, sh_a)
    wp.blit(cv, lay, 4, (mpad + box / 2, mpad + box * star_cy), (cx0 + x0 + score_star / 2, cy0 + score_y - score_star * 0.04))
    wp.label(cv, txt, cx0 + x0 + score_star + gap + tw / 2, cy0 + score_y, "WinScore", size=int(round(sfs * sk)))
    # «Всего очков» проявляется с TOTAL_AT за TEXT_FADE.
    ta = cp.seg(t, gdc(W_GD, "TOTAL_AT"), gdc(W_GD, "TEXT_FADE"))
    if ta > 0.001:
        tx, ty, tw_, th_ = wp.node_rect(N["TotalLabel"])
        fs_total = int(N["TotalLabel"].get("theme_override_font_sizes/font_size",
                                           wp.th("CardText", "font_sizes", "font_size")))
        wp.label(cv, "Всего очков: 2\u00a0460", cx0 + tx + tw_ / 2, cy0 + ty + th_ / 2, "CardText", size=fs_total,
                 alpha=ta)
    # Звёзды на кромке: TextureRect со своей тенью (TexShadow поворачивается и масштабируется со звездой).
    centers, radii = wp.gd_list(W_GD, "STAR_CENTERS"), wp.gd_list(W_GD, "STAR_R")
    for i in range(3):
        alpha, k, rot = star_state(t, i, n, c, reduced)
        if alpha <= 0.001:
            continue
        r = radii[i]
        bx = 1.75 * r / fit * k
        q = r / 56.0 * k
        lay = wp.png_layer("star" if i < n else "star_empty", bx)
        lay, mpad = wp.with_tex_shadow(lay, 4, (0.0, 8 * q), 10 * q, sh_col, sh_a)
        wp.blit(cv, lay * alpha, 4, (mpad + bx / 2, mpad + bx * star_cy), (cx0 + centers[i][0], cy0 + centers[i][1]), rot)
    img = cv.image()
    return img.resize((out_w, int(round(ch * out_w / cw))), Image.LANCZOS)


# ---------------------------------------------------------------- лист

def main():
    c = cp.juice_config()
    fade = block_flash_fade()
    pop_steps = block_pop_steps()
    semis = semitones()
    g0, r0 = gap_radius()
    font = ImageFont.truetype(sp.UI_FONT, 26)
    small = ImageFont.truetype(sp.UI_FONT, 22)
    hs = min(c["hitstop_win"], c["hitstop_max"])
    land = c["land_time"]
    show = gdc("scenes/game/game.gd", "WIN_SHOW_AT") - land       # показ окна — от касания
    fw, fh = board_frame_size()
    star_h = int(round(STAR_CROP_H * fw / STAR_CROP_W))
    notes = ["до", "до#", "ре", "ре#", "ми", "фа", "фа#", "соль", "соль#", "ля", "ля#", "си"]

    rows = [
        ("board", False, "Поле: удар последнего блока — hit-stop %d мс, тряска %s; волна %s, полоса %s клетки, до "
         "дальнего угла за %s с; вспышка %s, подскок ×%s, мозаика: зазор с %s до %s, скругление с %s до %s за %s с"
         % (round(hs * 1000), fmt(c["trauma_win"]), fmt(wave_peak(c, False)), fmt(c["win_wave_width"], 1),
            fmt(c["win_wave_time"]), fmt(flash_amount(c, False)), fmt(1 + c["win_block_pop"]), fmt(g0, 3),
            fmt(c["win_merge_gap"], 3), fmt(r0), fmt(c["win_merge_radius"]), fmt(c["win_merge_time"]))),
        ("board", True, "Поле, «Меньше движения»: волна %s и вспышка %s (не сильнее %s), без подскока, тряски и света "
         "по клеткам; мозаика — та же" % (fmt(wave_peak(c, True)), fmt(flash_amount(c, True)), fmt(c["reduced_wave"]))),
        ("stars", (2, False), "Окно, 2 звезды из 3: штамп с ×%s и поворота %s° до ×%s за %s с, дожим за %s с, нота +%s "
         "полутонов (%s), толчок карточки %s px; третья — тихо (с ×%s до ×1 за %s с)"
         % (fmt(c["star_slam"], 1), fmt(c["star_slam_spin"], 0), fmt(c["star_slam_squash"]), fmt(c["star_slam_time"]),
            fmt(c["star_settle_time"]), " / ".join(str(x) for x in semis), ", ".join(notes[x % 12] for x in semis),
            fmt(c["star_punch"], 0), fmt(gdc(W_GD, "STAR_QUIET_FROM"), 1), fmt(gdc(W_GD, "STAR_QUIET_TIME")))),
        ("stars", (3, True), "Окно, 3 звезды, «Меньше движения»: без штампа — каждая с ×%s до ×1 за %s с, нота и искры "
         "(вдвое меньше) — в миг появления, карточка не вздрагивает"
         % (fmt(gdc(W_GD, "STAR_QUIET_FROM"), 1), fmt(gdc(W_GD, "STAR_QUIET_TIME")))),
    ]
    W = fw * len(BOARD_TIMES)
    H = FOOT
    for kind, _, _ in rows:
        H += ROW_TITLE + CAPTION + (fh if kind == "board" else star_h)
    out = Image.new("RGB", (W, H), (36, 18, 92))
    d = ImageDraw.Draw(out)
    y = 0
    stars_at, step = gdc(W_GD, "STARS_AT"), gdc(W_GD, "STAR_STEP")
    for kind, arg, title in rows:
        d.text((16, y + 7), title, font=font, fill=(255, 255, 255))
        y += ROW_TITLE
        if kind == "board":
            for i, t in enumerate(BOARD_TIMES):
                tt = show if t is None else t
                out.paste(board_frame(tt, c, arg, fade, pop_steps), (i * fw, y))
                cap = "%d мс" % round(tt * 1000)
                if t == 0:
                    cap += " · удар"
                elif t is None:
                    cap += " · окно"
                elif tt < hs:
                    cap += " · hit-stop"
                d.text((i * fw + fw / 2, y + fh + CAPTION / 2), cap, font=font, fill=(255, 228, 92), anchor="mm")
            y += fh + CAPTION
        else:
            n, reduced = arg
            for i, t in enumerate(STAR_TIMES):
                out.paste(star_frame(t, c, n, reduced, fw), (i * fw, y))
                cap = "%d мс" % round(t * 1000)
                for j in range(3):
                    at = stars_at + step * j
                    hit = at if (reduced or j >= n) else at + c["star_slam_time"]
                    if abs(t - hit) < 1e-6:
                        cap += " · звезда %d" % (j + 1) if (reduced or j >= n) else " · удар %d" % (j + 1)
                if abs(t - gdc(W_GD, "BUTTONS_DELAY")) < 1e-6:
                    cap += " · кнопки"
                d.text((i * fw + fw / 2, y + star_h + CAPTION / 2), cap, font=font, fill=(255, 228, 92), anchor="mm")
            y += star_h + CAPTION
    d.text((16, y + 8), "Поле — время от касания (Board.landed), окно — от его показа (через %s с после броска). Пока идёт "
           "hit-stop, твины эффектов стоят. Не нарисованы: тряска, сплющивание блока, звёздочки и искры, лучи и "
           "конфетти, заголовок окна." % fmt(gdc("scenes/game/game.gd", "WIN_SHOW_AT")),
           font=small, fill=(200, 190, 255))
    out.save(OUT, optimize=True)
    print("->", os.path.relpath(OUT, ROOT), out.size)


if __name__ == "__main__":
    main()
