#!/usr/bin/env python3
"""Этап 14.6g: кадр «Тупик и подсказка» по шагам — из настоящих шейдеров (board, nest, block с униформой crack,
shelf, soft_shadow) через переводчик tools/shader_preview.py, раскладка портрета 720×1280 — tools/layout_model.py.
Godot в песочнице нет: так трещину и искру видно до первого запуска.

Уровень 12 (5×6), на поле верные блоки 6 и 8. Повторены:
  * Тупик (Game._after_move → через 0,45 с Game._play_dead_end), время — от хода (блок уже лёг):
    - Block.warn(0,45): тряска Visual ±14 px (4 × 0,04 с и 0,04 с назад), дважды краснеет до (1; 0,55; 0,6) за
      0,12 с и белеет за 0,18 с;
    - Board.dim_flash: слои Frame / Cells / Blocks × (k, k, min(1, k + 0,35·d)), k = 1 − d; d: 0 → dead_dim за
      dead_dim_in (QUAD, EASE_OUT), держится dead_dim_hold, → 0 за dead_dim_out (SINE, EASE_IN_OUT);
    - Block.crack: униформа crack 0 → 1 за dead_crack_time (QUAD, EASE_OUT); «Меньше движения» — сразу 1;
    - Fx.hop(«Отмена»): лицо (не тень) вверх на dead_hop и на 55 % от него, каждый прыжок — dead_hop_time
      (половина вверх QUAD EASE_OUT, половина вниз QUAD EASE_IN); «Меньше движения» — Fx.pulse (×1,2 дважды).
  * Подсказка (12.10; HintController._place → Board.place_block(b, r, float), HintSpark.fly), время — от нажатия:
    - блок сразу поднимается (тень «поднят», цифра — на клетку числа) и летит из гнезда на место за
      hint_float_time (SINE EASE_IN_OUT: левый верх и масштаб гнезда → поля), за 0,12 с до конца тень «лежит»;
    - искра летит вместе с ним: по прямой из середины блока в гнезде в середину места, тем же ходом, под блоком
      (ядро закрыто блоком, виден след — 12 точек, кадры по 1/60 с; ореол 24 и 13 px, ядро 7 px, сложение света,
      BLEND_MODE_ADD); в миг касания — вспышка искр (здесь — кольцо);
    - новый блок в гнездо — Block.slide_in(0,12) снизу (как появление уровня, 14.6b);
    - «Меньше движения» — без искры.
    До 12.10: сначала искра от кнопки по дуге 0,42 с, блок ждал её в гнезде и только потом вплывал 0,36 с.

    python3 tools/dead_hint_preview.py     # -> docs/style_frames/G14_6_dead_hint.png
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_preview as sp    # noqa: E402
import close_preview as cp     # noqa: E402
import intro_preview as ip     # noqa: E402
import layout_model as lm      # noqa: E402

ROOT = sp.ROOT
OUT = os.path.join(sp.FRAMES, "G14_6_dead_hint.png")
LEVEL = 12
PLACED = [0, 1]                    # верные блоки на поле (6 и 8)
WRONG = (0, 2, 2, 1, 1, 0)         # «2» лёг (0,2)–(1,2) лёжа: четвёрке (0,5) больше не встать — тупик
DEAD_TRAY = [2, 4, 6]              # лоток в тупике: 4 (1×4), 2, 4 (2×2)
HINT = 2                           # подсказка ставит прямоугольник 2 (1×4, число 4 в (0,5)) из гнезда 0
HINT_TRAY = [2, 3, 6]
HINT_NEXT = 4                      # новый блок в гнездо 0 после хода
DEAD_AT = 0.45
SCREEN_W, SCREEN_H = 720, 1280
CROP = (0, 170, 720, 1280)         # шапка не меняется — без неё
SCALE = 0.42
CAPTION = 118                      # подпись кадра: время и до трёх строк пояснений
ROW_TITLE = 34
FOOT = 44
SPARK = {"COLOR": (1.0, 0.9, 0.5), "CORE": (1.0, 0.99, 0.92), "CORE_R": 7.0, "GLOW_R": 24.0, "TRAIL": 12,
         "TRAIL_R": 6.0}

fmt = ip.fmt
_EXTRA = {}
_orig_draw_rect = sp.draw_rect


def _draw_rect(cv, shader, *a, **kw):
    """sp.draw_rect с добавочными униформами блока (crack) из _EXTRA."""
    if shader == "block" and _EXTRA:
        a = list(a)
        a[6] = dict(a[6], **_EXTRA)
    return _orig_draw_rect(cv, shader, *a, **kw)


sp.draw_rect = _draw_rect


def sine_io(u):
    return 0.5 - 0.5 * math.cos(math.pi * min(max(u, 0.0), 1.0))


def quad_out(u):
    return cp.quad_out(min(max(u, 0.0), 1.0))


def quad_in(u):
    return cp.quad_in(min(max(u, 0.0), 1.0))


# ---------------------------------------------------------------- состояния эффектов во времени

def dim_at(t, c):
    """Board.dim_flash, запущенный в DEAD_AT: насколько поле темнее."""
    u = t - DEAD_AT
    if u <= 0:
        return 0.0
    d_in, hold, d_out = max(c["dead_dim_in"], 0.01), c["dead_dim_hold"], max(c["dead_dim_out"], 0.01)
    if u < d_in:
        return c["dead_dim"] * quad_out(u / d_in)
    if u < d_in + hold:
        return c["dead_dim"]
    return c["dead_dim"] * (1.0 - sine_io((u - d_in - hold) / d_out))


def crack_at(t, c, reduced):
    if t < DEAD_AT:
        return 0.0
    if reduced or c["dead_crack_time"] <= 0:
        return 1.0
    return quad_out((t - DEAD_AT) / c["dead_crack_time"])


def hop_at(t, c, reduced):
    """Fx.hop: подъём лица «Отмены», px; «Меньше движения» — 0 (там pulse_at)."""
    if reduced or t < DEAD_AT:
        return 0.0
    half = max(c["dead_hop_time"], 0.02) * 0.5
    u = t - DEAD_AT
    for k in range(2):
        h = c["dead_hop"] * (1.0 if k == 0 else 0.55)
        if u < half:
            return h * quad_out(u / half)
        u -= half
        if u < half:
            return h * (1.0 - quad_in(u / half))
        u -= half
    return 0.0


def pulse_at(t, reduced):
    """Fx.pulse («Меньше движения»): масштаб кнопки — дважды ×1,2 за 0,12 с (QUAD) и назад за 0,18 с (BACK)."""
    if not reduced or t < DEAD_AT:
        return 1.0
    u = t - DEAD_AT
    for _ in range(2):
        if u < 0.12:
            return cp.lerp(1.0, 1.2, quad_out(u / 0.12))
        u -= 0.12
        if u < 0.18:
            return cp.lerp(1.2, 1.0, cp.back_out(u / 0.18))
        u -= 0.18
    return 1.0


def warn_at(t):
    """Block.warn(0,45): (сдвиг Visual по x, px блока; оттенок)."""
    u = t - DEAD_AT
    if u < 0:
        return 0.0, (1, 1, 1, 1)
    keys = [0.0, 14.0, -14.0, 14.0, -14.0, 0.0]
    x = 0.0
    if u < 0.2:
        i = int(u / 0.04)
        x = cp.lerp(keys[i], keys[i + 1], (u - i * 0.04) / 0.04)
    red = (1.0, 0.55, 0.6)
    k = 0.0
    v = u
    for _ in range(2):
        if v < 0.12:
            k = v / 0.12
            break
        v -= 0.12
        if v < 0.18:
            k = 1.0 - v / 0.18
            break
        v -= 0.18
    return x, tuple(cp.lerp(1.0, r, k) for r in red) + (1.0,)


# ---------------------------------------------------------------- рисование

def board_geom(level):
    cols, rows, _ = level
    ox, oy, cell_px = ip.board_place(cols, rows)
    return ox, oy, cell_px / sp.CELL


def draw_board_layers(cv, level, placed, wrong=None, crack=0.0, wrong_dx=0.0, wrong_tint=(1, 1, 1, 1)):
    """Board: Frame, Cells (гнёзда открытых чисел), Blocks (верные + неверный с трещиной)."""
    cols, rows, rects = level
    ox, oy, s = board_geom(level)
    px = 1.0 / s
    m = (sp.BD["FRAME_MARGIN"] + sp.BD["PAD"]) * px
    fw, fh = cols * sp.CELL + 2 * m, rows * sp.CELL + 2 * m + sp.BD["FRAME_DEPTH"] * px
    sp.draw_rect(cv, "board", ox - m * s, oy - m * s, fw, fh, s, (1, 1, 1, 1), {
        "frame_size": (fw, fh), "grid": (float(cols), float(rows)), "px": px, "margin": sp.BD["FRAME_MARGIN"],
        "pad": sp.BD["PAD"], "rim": sp.BD["RIM"], "lip": sp.BD["FRAME_DEPTH"]})
    blocks = [rects[i] for i in placed] + ([wrong] if wrong else [])
    covered = set()
    for rx, ry, rw, rh, *_ in blocks:
        covered |= {(x, y) for x in range(rx, rx + rw) for y in range(ry, ry + rh)}
    for rx, ry, rw, rh, nx, ny in rects:
        if (nx, ny) in covered:
            continue
        area = rw * rh
        col = sp.color_for(area)
        bx, by = nx * sp.CELL, ny * sp.CELL
        sp.draw_rect(cv, "nest", ox + (bx + 50 - 98) * s, oy + (by + 50 - 98) * s, sp.CELL + 96, sp.CELL + 96, s,
                     col[:3] + (1.0,), {"px": px, "ring": 0.0, "margin": 48.0})
        sp.draw_digit(cv, str(area), ox + (bx + 50) * s, oy + (by + 50) * s, 40 * s, col, sp.darkened(col, 0.42),
                      sp.CL["DIGIT_OUTLINE"] * s, sp.darkened(col, 0.5)[:3] + (0.35,), (0, 2 * s))
    for b in sorted(blocks, key=lambda r: (r[1], r[0])):
        rx, ry, rw, rh, nx, ny = b
        is_wrong = b is wrong
        if is_wrong:
            _EXTRA["crack"] = crack
            sp.draw_block(cv, ox + rx * sp.CELL * s + wrong_dx * s, oy + ry * sp.CELL * s, s, rw, rh, rw * rh,
                          (nx, ny), False, wrong_tint)
            _EXTRA.clear()
        else:
            sp.draw_block(cv, ox + rx * sp.CELL * s, oy + ry * sp.CELL * s, s, rw, rh, rw * rh, (nx - rx, ny - ry),
                          False)


def board_with_dim(cv, d, draw):
    """Слои поля с modulate (k, k, min(1, k + 0,35·d)): рисуем их на чёрном и белом — так известны цвет
    (премультиплицированный) и непрозрачность — и кладём поверх cv с оттенком."""
    if d <= 0.0005:
        draw(cv)
        return
    blk = sp.Canvas(np.zeros((cv.h, cv.w, 3)))
    wht = sp.Canvas(np.full((cv.h, cv.w, 3), 255.0))
    draw(blk)
    draw(wht)
    a = np.clip(1.0 - (wht.rgb - blk.rgb).mean(axis=2, keepdims=True), 0.0, 1.0)
    k = 1.0 - d
    mod = np.array([k, k, min(1.0, k + 0.35 * d)])
    cv.rgb = cv.rgb * (1.0 - a) + blk.rgb * mod


def tray_shelf(cv):
    L = lm.compute(SCREEN_W, SCREEN_H, False)
    shelf = L["shelf"]
    slots = lm.slots(L)
    params = {"shelf_size": (shelf[2], shelf[3]), "well_empty": (0.0, 0.0, 0.0)}
    for i, sr in enumerate(slots):
        params["well%d" % i] = (sr[0] - shelf[0], sr[1] - shelf[1], sr[2], sr[3])
    sp.draw_rect(cv, "shelf", shelf[0], shelf[1], shelf[2], shelf[3], 1.0, (1, 1, 1, 1), params)
    return slots


def slot_place(sr, bw, bh):
    """Tray._place_in_slot: масштаб и левый верх блока bw×bh в гнезде sr."""
    k = min(sp.TRAY_SCALE, (sr[2] - sp.SLOT_MARGIN) / (bw * sp.CELL), (sr[3] - sp.SLOT_MARGIN) / (bh * sp.CELL))
    return sr[0] + (sr[2] - bw * sp.CELL * k) / 2, sr[1] + (sr[3] - bh * sp.CELL * k) / 2, k


def button_places():
    L = lm.compute(SCREEN_W, SCREEN_H, False)
    d = sp.BTN_D
    tx, ty, tw, th = L["top_bar"]
    ax, ay, aw, ah = L["actions"]
    return {"pause": (tx + d / 2, ty + th / 2), "restart": (tx + tw - d / 2, ty + th / 2),
            "undo": (ax + d / 2, ay + ah / 2), "hint": (ax + aw - d / 2, ay + ah / 2)}


def draw_buttons(cv, hop=0.0, pulse=1.0, badge="3"):
    """Кнопки; у «Отмены» лицо поднято на hop px (тень на месте, CandyButton.set_hop) или вся кнопка ×pulse."""
    d = sp.BTN_D
    for name, (cx, cy) in button_places().items():
        if name != "undo":
            sp.draw_button(cv, cx, cy, d, name, badge if name == "hint" else None)
            continue
        if pulse != 1.0:
            sp.draw_button(cv, cx, cy, d * pulse, name)
            continue
        t = d * sp.FACE_OVERSCAN
        sp.draw_soft_shadow(cv, cx - t / 2, cy - t / 2, t, t, sp.FACE_SHAPE, 1.0, (0.0, d * sp.CB["SHADOW_OFFSET"]),
                            d * sp.CB["SHADOW_BLUR"], sp.CB["SHADOW_STRENGTH"])
        sp.draw_png(cv, name, cx - t / 2, cy - t / 2 - hop, t, t)


def draw_pill(cv, n):
    sp.draw_pill(cv, lm.compute(SCREEN_W, SCREEN_H, False), text="Осталось блоков: %d" % n)


def add_disk(rgb, cx, cy, r, color, alpha):
    """Сложение света (BLEND_MODE_ADD): диск радиуса r со сглаженным краем."""
    h, w = rgb.shape[:2]
    x0, x1 = max(0, int(cx - r - 2)), min(w, int(cx + r + 3))
    y0, y1 = max(0, int(cy - r - 2)), min(h, int(cy + r + 3))
    if x1 <= x0 or y1 <= y0:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    cov = np.clip(r + 0.5 - np.hypot(xx + 0.5 - cx, yy + 0.5 - cy), 0.0, 1.0)[..., None]
    rgb[y0:y1, x0:x1] += cov * alpha * np.array(color)


def spark_points(t, c, p0, p2):
    """Путь искры: по прямой (HintController._place пускает её с arc = 0 — вместе с блоком)."""
    def at(u):
        return (p0[0] + (p2[0] - p0[0]) * u, p0[1] + (p2[1] - p0[1]) * u)
    return at


def draw_spark(cv, t, c, p0, p2):
    T = max(c["hint_float_time"], 0.01)
    if t < 0 or t >= T:  # в миг касания искры уже нет — вспышка (draw_burst)
        return
    at = spark_points(t, c, p0, p2)
    trail = [at(sine_io(max(t - k / 60.0, 0.0) / T)) for k in range(SPARK["TRAIL"])]
    n = len(trail)
    for k in range(n - 1, 0, -1):
        f = 1.0 - k / SPARK["TRAIL"]
        add_disk(cv.rgb, trail[k][0], trail[k][1], SPARK["TRAIL_R"] * (0.35 + 0.65 * f), SPARK["COLOR"], 0.5 * f * f)
    x, y = trail[0]
    add_disk(cv.rgb, x, y, SPARK["GLOW_R"], SPARK["COLOR"], 0.16)
    add_disk(cv.rgb, x, y, SPARK["GLOW_R"] * 0.55, SPARK["COLOR"], 0.3)
    add_disk(cv.rgb, x, y, SPARK["CORE_R"], SPARK["CORE"], 1.0)


def draw_path(cv, c, p0, p2):
    """Пунктир всего пути блока и искры (только в кадре-пояснении, в игре его нет)."""
    at = spark_points(0, c, p0, p2)
    for i in range(0, 41, 2):
        x, y = at(i / 40.0)
        add_disk(cv.rgb, x, y, 2.0, (1.0, 1.0, 1.0), 0.35)


def draw_burst(cv, u, at_pt):
    """Вспышка искр Juice.SPARKS в точке места (приближение: кольцо разлетающихся точек, гаснет за 0,35 с)."""
    if u < 0 or u > 0.35:
        return
    f = u / 0.35
    for i in range(10):
        a = i * math.tau / 10 + 0.3
        r = 18 + 70 * cp.quad_out(f)
        add_disk(cv.rgb, at_pt[0] + math.cos(a) * r, at_pt[1] + math.sin(a) * r, 5.0 * (1 - f) + 1.5,
                 (1.0, 0.92, 0.55), 0.9 * (1 - f))


# ---------------------------------------------------------------- кадры

def dead_frame(t, c, reduced, level, bg):
    cols, rows, rects = level
    cv = sp.Canvas(np.zeros((SCREEN_H, SCREEN_W, 3)))
    cv.rgb = bg.copy()
    dx, tint = warn_at(t)
    cr = crack_at(t, c, reduced)
    board_with_dim(cv, dim_at(t, c), lambda k: draw_board_layers(k, level, PLACED, WRONG, cr, dx, tint))
    slots = tray_shelf(cv)
    for i, sr in enumerate(slots):
        _, _, bw, bh, _, _ = rects[DEAD_TRAY[i]]
        gx, gy, k = slot_place(sr, bw, bh)
        sp.draw_block(cv, gx, gy, k, bw, bh, bw * bh, None, False)
    draw_pill(cv, len(rects) - len(PLACED) - 1)
    draw_buttons(cv, hop_at(t, c, reduced), pulse_at(t, reduced))
    return cv


def hint_frame(t, c, reduced, level, bg, path=False):
    cols, rows, rects = level
    cv = sp.Canvas(np.zeros((SCREEN_H, SCREEN_W, 3)))
    cv.rgb = bg.copy()
    ox, oy, s = board_geom(level)
    rx, ry, rw, rh, nx, ny = rects[HINT]
    ft = max(c["hint_float_time"], 0.01)
    landed = t >= ft
    draw_board_layers(cv, level, PLACED + ([HINT] if landed else []))
    slots = tray_shelf(cv)
    for i, sr in enumerate(slots):
        if i == 0:
            continue
        _, _, bw, bh, _, _ = rects[HINT_TRAY[i]]
        gx, gy, k = slot_place(sr, bw, bh)
        sp.draw_block(cv, gx, gy, k, bw, bh, bw * bh, None, False)
    # Новый блок в гнездо 0: Block.slide_in(0,12) снизу.
    _, _, bw, bh, _, _ = rects[HINT_NEXT]
    a, slide = ip.block_state(t, 0.12, c, reduced)
    ip.tray_block(cv, slots[0], rects[HINT_NEXT], a, slide)
    draw_pill(cv, len(rects) - len(PLACED) - (1 if t >= 0 else 0))
    draw_buttons(cv)
    # Искра — из середины блока в гнезде в середину места, под блоком (z FxLayer ниже FLOAT_Z).
    gx, gy, k = slot_place(slots[0], rw, rh)
    p0 = (gx + rw * sp.CELL * k / 2, gy + rh * sp.CELL * k / 2)
    p2 = (ox + (rx + rw / 2) * sp.CELL * s, oy + (ry + rh / 2) * sp.CELL * s)
    if path:
        draw_path(cv, c, p0, p2)
    if not reduced:
        draw_spark(cv, t, c, p0, p2)
    if not landed:
        # Блок подсказки (z FLOAT_Z — над лотком и искрой): сразу летит на место.
        tx, ty = ox + rx * sp.CELL * s, oy + ry * sp.CELL * s
        u = sine_io(t / ft)
        lifted = t < ft - 0.12
        sp.draw_block(cv, cp.lerp(gx, tx, u), cp.lerp(gy, ty, u), cp.lerp(k, s, u), rw, rh, rw * rh,
                      (nx - rx, ny - ry), lifted)
    if not reduced:
        draw_burst(cv, t - ft, p2)
    return cv


def crop(cv, fw, fh):
    return cv.image().crop(CROP).resize((fw, fh), Image.LANCZOS)


def closeup(c, level, bg, crack, z=1.25):
    """Неверный блок крупно (трещина) — фрагмент поля вокруг него."""
    cv = sp.Canvas(np.zeros((SCREEN_H, SCREEN_W, 3)))
    cv.rgb = bg.copy()
    draw_board_layers(cv, level, PLACED, WRONG, crack)
    ox, oy, s = board_geom(level)
    x0, y0 = ox - 0.3 * sp.CELL * s, oy + 1.6 * sp.CELL * s
    box = (int(x0), int(y0), int(x0 + 2.6 * sp.CELL * s), int(y0 + 1.8 * sp.CELL * s))
    im = cv.image().crop(box)
    return im.resize((int(im.width * z), int(im.height * z)), Image.LANCZOS)


def main():
    c = cp.juice_config()
    level = sp.load_level(LEVEL)
    bg = sp.background(SCREEN_W, SCREEN_H).rgb
    font = ImageFont.truetype(sp.UI_FONT, 25)
    small = ImageFont.truetype(sp.UI_FONT, 21)
    cw, ch = CROP[2] - CROP[0], CROP[3] - CROP[1]
    fw, fh = int(round(cw * SCALE)), int(round(ch * SCALE))
    F = c["hint_float_time"]
    dsum = c["dead_dim_in"] + c["dead_dim_hold"] + c["dead_dim_out"]
    dead_t = [0.40, 0.50, 0.58, 0.66, 0.78, 0.92, 1.12]
    hint_t = [0.0, round(F / 4, 2), round(F / 2, 2), round(3 * F / 4, 2), F, round(F + 0.12, 2), round(F + 0.3, 2)]
    rows = [
        ("Тупик: ход «2» лёжа в (0,2)–(1,2) — четвёрке (0,5) не встать. Через %s с после хода: поле темнее на %d %% "
         "(%s + %s + %s с), блок трескается за %s с\nи трясётся (warn), лицо «Отмены» прыгает на %s px и на 55 %% "
         "(по %s с), тень на месте. Трещина остаётся до отмены." % (
             fmt(DEAD_AT), round(c["dead_dim"] * 100), fmt(c["dead_dim_in"]), fmt(c["dead_dim_hold"]),
             fmt(c["dead_dim_out"]), fmt(c["dead_crack_time"]), fmt(c["dead_hop"], 0), fmt(c["dead_hop_time"])),
         [("dead", t, False) for t in dead_t], "мс после хода"),
        ("Подсказка (12.10): блок сразу летит из гнезда на место за %s с (тень «поднят»), искра — вместе с ним, под "
         "блоком (виден след),\nв миг касания — вспышка. Ход засчитан сразу, «+очки» — в миг касания, новый блок — "
         "через 0,12 с. Было: искра 0,42 с, потом блок 0,36 с." % fmt(F),
         [("hint", t, False) for t in hint_t], "мс после нажатия"),
        ("«Меньше движения»: тупик — трещина сразу целиком, «Отмена» пульсирует (×1,2) без прыжка, затемнение то же; "
         "подсказка —\nбез искры, блок так же сразу летит на место за %s с." % fmt(F),
         [("dead", 0.40, True), ("dead", 0.50, True), ("dead", 0.70, True), ("hint", 0.0, True),
          ("hint", round(F / 3, 2), True), ("hint", round(2 * F / 3, 2), True), ("hint", F + 0.05, True)], None),
    ]
    zooms = [closeup(c, level, bg, v) for v in (0.0, 0.35, 0.7, 1.0)]
    zw, zh = zooms[0].size
    keep = {}                      # кадры для «Отмены» крупно: в покое и на вершине первого прыжка
    hop_peak = round(DEAD_AT + c["dead_hop_time"] * 0.5, 2)
    W = fw * 7
    H = FOOT * 2 + sum(ROW_TITLE * (t.count("\n") + 1) + 6 + fh + CAPTION for t, _, _ in rows) + ROW_TITLE + 12 \
        + zh + 56
    out = Image.new("RGB", (W, H), (36, 18, 92))
    d = ImageDraw.Draw(out)
    y = 0
    for title, cells, unit in rows:
        for j, line in enumerate(title.split("\n")):
            d.text((16, y + 7 + j * ROW_TITLE), line, font=font, fill=(255, 255, 255))
        y += ROW_TITLE * (title.count("\n") + 1) + 6
        for i, (kind, t, red) in enumerate(cells):
            if kind == "dead":
                cv = dead_frame(t, c, red, level, bg)
                if not red and t in (dead_t[0], hop_peak):
                    keep[t] = cv
                cap = "тупик · %d мс" % round(t * 1000) if unit is None else "%d %s" % (round(t * 1000), unit)
                extra = []
                if dim_at(t, c) > 0.001:
                    extra.append("темнее %d %%" % round(dim_at(t, c) * 100))
                cr = crack_at(t, c, red)
                if cr > 0:
                    extra.append("трещина %d %%" % round(cr * 100))
                hp = hop_at(t, c, red)
                if hp > 0.05:
                    extra.append("прыжок %s px" % fmt(hp, 0))
                if t < DEAD_AT:
                    extra += ["блок лёг,", "тупик ещё не показан"]
                if t >= DEAD_AT + max(dsum, c["dead_hop_time"] * 2):
                    extra += ["всё стихло,", "трещина осталась"]
            else:
                cv = hint_frame(t, c, red, level, bg, path=(t == 0 and not red))
                cap = "подсказка · %d мс" % round(t * 1000) if unit is None else "%d %s" % (round(t * 1000), unit)
                extra = []
                if t == 0 and not red:
                    extra += ["нажатие: блок взлетает", "(пунктир — путь)"]
                elif t == 0:
                    extra.append("нажатие: блок взлетает")
                elif t < F - 0.005:
                    extra.append("блок летит" + ("" if red else ", за ним след"))
                elif abs(t - F) < 0.005:
                    extra.append("касание" + ("" if red else " — вспышка"))
                else:
                    extra.append("блок на месте")
            out.paste(crop(cv, fw, fh), (i * fw, y))
            d.text((i * fw + fw / 2, y + fh + 18), cap, font=font, fill=(255, 228, 92), anchor="mm")
            for j, line in enumerate(extra):
                d.text((i * fw + fw / 2, y + fh + 46 + 24 * j), line, font=small, fill=(200, 190, 255), anchor="mm")
        y += fh + CAPTION
    d.text((16, y + 7), "Крупно: трещина (униформа crack в block.gdshader) — 0, 35 %%, 70 %%, 100 %%; «Отмена» — в покое "
           "и на вершине прыжка (%s px, %d мс после хода)" % (fmt(c["dead_hop"], 0), round(hop_peak * 1000)),
           font=font, fill=(255, 255, 255))
    y += ROW_TITLE + 12
    x = 16
    for i, z in enumerate(zooms):
        out.paste(z, (x, y))
        d.text((x + zw / 2, y + zh + 24), "crack = %s" % fmt((0.0, 0.35, 0.7, 1.0)[i]), font=font,
               fill=(255, 228, 92), anchor="mm")
        x += zw + 24
    ux, uy = button_places()["undo"]
    for t, lab in ((dead_t[0], "в покое"), (hop_peak, "прыжок %s px" % fmt(hop_at(hop_peak, c, False), 0))):
        if t not in keep:
            continue
        im = keep[t].image().crop((int(ux - 80), int(uy - 100), int(ux + 80), int(uy + 70)))
        k = zh / im.height
        im = im.resize((int(im.width * k), zh), Image.LANCZOS)
        out.paste(im, (x, y))
        d.text((x + im.width / 2, y + zh + 24), lab, font=font, fill=(255, 228, 92), anchor="mm")
        x += im.width + 24
    y += zh + 56
    for j, line in enumerate((
            "Шапка не меняется — в кадр не входит. Искра — свет (сложение), под блоком; вспышка нарисована приближённо "
            "(в игре — частицы Juice.SPARKS).",
            "Тряска и краснота неверного блока — прежние (Block.warn). «+очки» над блоком подсказки в кадре не "
            "нарисованы.")):
        d.text((16, y + 8 + 26 * j), line, font=small, fill=(200, 190, 255))
    out.save(OUT, optimize=True)
    print("->", os.path.relpath(OUT, ROOT), out.size)


if __name__ == "__main__":
    main()
