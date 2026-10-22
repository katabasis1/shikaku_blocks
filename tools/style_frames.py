#!/usr/bin/env python3
"""Стиль-кадры этапа 12 (PLAN.md, раздел 4.2): как может выглядеть игра в трёх направлениях.

Рисует без Godot (Pillow + numpy) экран игры 720×1280 с размерами из game.tscn: верхняя
панель, поле 6×6 (уровень 20 из пака), панель отмены и подсказки, лоток на 3 блока. Отдельно —
момент победы. Это эскиз направления, а не финальная графика: шрифты — системные заменители
(финальный шрифт — этап 13), движение показано одним кадром (поднятый блок, «призрак», магнит).

    python3 tools/style_frames.py            # все стили -> docs/style_frames/
    python3 tools/style_frames.py --only A   # один стиль
    python3 tools/style_frames.py --out DIR

Файлы: <A|B|C>_game.png, <A|B|C>_win.png, sheet.png (лист сравнения).
Детерминирован: вся случайность — с фиксированным зерном.
"""
import math
import os
import random
import re
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 720, 1280          # размер экрана игры (project.godot)
SS = 2                    # рисуем в 2× и уменьшаем — сглаживание
LEVEL_N = 20              # уровень из пака для кадров


def P(v):
    """Дизайн-пиксели (720×1280) -> пиксели холста."""
    return int(round(v * SS))


# ---------------------------------------------------------------- цвета

def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(3))


def lighten(c, t):
    return mix(c, (255, 255, 255), t)


def darken(c, t):
    return mix(c, (0, 0, 0), t)


def rgba(c, a=255):
    return (c[0], c[1], c[2], int(round(a)))


# ---------------------------------------------------------------- слои и маски

def comp(dst, src, x, y):
    """alpha_composite с отрицательными координатами (x, y — пиксели холста)."""
    x, y = int(round(x)), int(round(y))
    sx, sy = max(0, -x), max(0, -y)
    dx, dy = max(0, x), max(0, y)
    w = min(src.width - sx, dst.width - dx)
    h = min(src.height - sy, dst.height - dy)
    if w <= 0 or h <= 0:
        return
    if sx or sy or w != src.width or h != src.height:
        src = src.crop((sx, sy, sx + w, sy + h))
    dst.alpha_composite(src, dest=(dx, dy))


def new_l(w, h):
    return Image.new("L", (int(w), int(h)), 0)


def rr_mask(w, h, box, r):
    m = new_l(w, h)
    ImageDraw.Draw(m).rounded_rectangle([int(v) for v in box], radius=int(r), fill=255)
    return m


def ellipse_mask(w, h, box):
    m = new_l(w, h)
    ImageDraw.Draw(m).ellipse([int(v) for v in box], fill=255)
    return m


def mul_mask(a, b):
    return ImageChops.multiply(a, b)


def scale_mask(m, k):
    return m.point(lambda v: int(v * k))


def paint(mask, fill):
    """RGBA-картинка: цвет (кортеж) или картинка, прозрачность — по маске."""
    if isinstance(fill, tuple):
        src = Image.new("RGBA", mask.size, rgba(fill[:3], fill[3] if len(fill) > 3 else 255))
    else:
        src = fill.copy()
    src.putalpha(ImageChops.multiply(src.getchannel("A"), mask))
    return src


def blurred(mask, radius, pad=None):
    """Маска с полями pad вокруг и размытием radius. Возвращает (маска, pad)."""
    pad = int(radius * 3) if pad is None else pad
    m = new_l(mask.width + 2 * pad, mask.height + 2 * pad)
    m.paste(mask, (pad, pad))
    if radius > 0:
        m = m.filter(ImageFilter.GaussianBlur(radius))
    return m, pad


def shadow(dst, mask, x, y, dx, dy, radius, color, alpha):
    """Тень маски, лежащей на холсте в (x, y), со смещением (dx, dy)."""
    m, pad = blurred(mask, radius)
    comp(dst, paint(scale_mask(m, alpha), color), x - pad + dx, y - pad + dy)


def glow(dst, mask, x, y, radius, color, alpha, passes=1):
    for _ in range(passes):
        shadow(dst, mask, x, y, 0, 0, radius, color, alpha)


def round_shape(mask, k):
    """Скругляет углы маски: размытие + порог."""
    m, pad = blurred(mask, k, pad=int(k * 2))
    m = m.point(lambda v: 255 if v > 127 else 0).filter(ImageFilter.GaussianBlur(0.7 * SS))
    return m.crop((pad, pad, pad + mask.width, pad + mask.height))


def grad_v(w, h, stops):
    """Вертикальный градиент RGBA: stops = [(t, (r, g, b[, a])), ...]."""
    t = np.linspace(0.0, 1.0, int(h))
    ts = [s[0] for s in stops]
    ch = []
    for i in range(4):
        vals = [(s[1][i] if i < len(s[1]) else 255) for s in stops]
        ch.append(np.interp(t, ts, vals))
    col = np.stack(ch, -1)
    arr = np.repeat(col[:, None, :], int(w), axis=1)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def grad_radial(w, h, cx, cy, r, stops):
    yy, xx = np.mgrid[0:int(h), 0:int(w)]
    d = np.clip(np.hypot(xx - cx, yy - cy) / r, 0, 1)
    ts = [s[0] for s in stops]
    ch = []
    for i in range(4):
        vals = [(s[1][i] if i < len(s[1]) else 255) for s in stops]
        ch.append(np.interp(d, ts, vals))
    arr = np.stack(ch, -1)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def noise(w, h, scale, seed, octaves=3):
    """Гладкий шум 0..1 (сумма октав увеличенного случайного шума)."""
    rng = np.random.default_rng(seed)
    out = np.zeros((int(h), int(w)))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        gw = max(2, int(w / scale) + 2)
        gh = max(2, int(h / scale) + 2)
        g = Image.fromarray((rng.random((gh, gw)) * 255).astype(np.uint8), "L")
        g = g.resize((int(w), int(h)), Image.BICUBIC)
        out += np.asarray(g, dtype=float) / 255.0 * amp
        tot += amp
        amp *= 0.5
        scale /= 2.0
    return out / tot


# ---------------------------------------------------------------- шрифты и текст

FONT_DIRS = ["/usr/share/fonts", os.path.join(ROOT, "assets", "fonts")]
_font_cache = {}


def find_font(names):
    for name in names:
        for base in FONT_DIRS:
            for d, _, fs in os.walk(base):
                if name in fs:
                    return os.path.join(d, name)
    return os.path.join(ROOT, "assets", "fonts", "nunito_extrabold.ttf")  # до 13.3 — game_font.ttf (Noto Sans ExtraBold)


def font(names, size):
    key = (tuple(names), size)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(find_font(names), P(size))
    return _font_cache[key]


def text(dst, cx, cy, s, fnt, fill, anchor="mm", stroke=0, stroke_fill=None,
         shadow_off=None, shadow_col=(0, 0, 0), shadow_a=90, shadow_blur=0,
         glow_col=None, glow_r=0, glow_a=200, spacing=0, align="center"):
    """Текст с обводкой, тенью и свечением. cx, cy — дизайн-пиксели."""
    probe = ImageDraw.Draw(new_l(1, 1))
    sw = P(stroke)
    multi = "\n" in s
    if multi:
        bb = probe.multiline_textbbox((0, 0), s, font=fnt, anchor=anchor, stroke_width=sw,
                                      spacing=P(spacing), align=align)
    else:
        bb = probe.textbbox((0, 0), s, font=fnt, anchor=anchor, stroke_width=sw)
    m = P(8) + int(glow_r * SS * 3) + int(shadow_blur * SS * 3)
    if shadow_off:
        m += P(max(abs(shadow_off[0]), abs(shadow_off[1])))
    lw, lh = int(math.ceil(bb[2] - bb[0])) + 2 * m, int(math.ceil(bb[3] - bb[1])) + 2 * m
    org = (m - bb[0], m - bb[1])
    X, Y = P(cx) + bb[0] - m, P(cy) + bb[1] - m

    def layer(color, with_stroke=True):
        im = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        kw = dict(font=fnt, anchor=anchor, fill=rgba(color[:3], color[3] if len(color) > 3 else 255))
        if with_stroke and sw:
            kw.update(stroke_width=sw, stroke_fill=rgba(stroke_fill[:3], stroke_fill[3] if len(stroke_fill) > 3 else 255))
        if multi:
            d.multiline_text(org, s, spacing=P(spacing), align=align, **kw)
        else:
            d.text(org, s, **kw)
        return im

    if glow_col is not None and glow_r > 0:
        a = layer(glow_col).getchannel("A")
        g, pad = blurred(a, P(glow_r), pad=0)
        comp(dst, paint(scale_mask(g, glow_a / 255), glow_col), X, Y)
    if shadow_off:
        a = layer((0, 0, 0)).getchannel("A")
        if shadow_blur:
            a = a.filter(ImageFilter.GaussianBlur(P(shadow_blur)))
        comp(dst, paint(scale_mask(a, shadow_a / 255), shadow_col), X + P(shadow_off[0]), Y + P(shadow_off[1]))
    comp(dst, layer(fill), X, Y)


# ---------------------------------------------------------------- иконки (векторно)

def star_points(cx, cy, R, r, n=5, rot=-90.0):
    pts = []
    for i in range(n * 2):
        a = math.radians(rot + i * 180.0 / n)
        rad = R if i % 2 == 0 else r
        pts.append((cx + rad * math.cos(a), cy + rad * math.sin(a)))
    return pts


def icon_mask(kind, size, width):
    """Маска иконки size×size (пиксели холста), толщина линии width."""
    S = int(size)
    m = new_l(S, S)
    d = ImageDraw.Draw(m)
    c = S / 2
    w = int(width)
    if kind == "pause":
        bw, bh = S * 0.16, S * 0.52
        for sx in (-1, 1):
            x0 = c + sx * S * 0.13 - bw / 2
            d.rounded_rectangle([x0, c - bh / 2, x0 + bw, c + bh / 2], radius=bw / 2, fill=255)
    elif kind in ("restart", "undo"):
        # PIL: углы по часовой стрелке от «3 часов»
        R = S * 0.29
        if kind == "restart":
            a0, a1, head_end = 50.0, 320.0, True      # кольцо с разрывом справа, стрелка вверху справа
        else:
            a0, a1, head_end = 180.0, 400.0, False    # ↶: дуга сверху, стрелка слева вниз
        d.arc([c - R, c - R, c + R, c + R], a0, a1, fill=255, width=w)
        tail = a0 if head_end else a1
        px, py = c + R * math.cos(math.radians(tail)), c + R * math.sin(math.radians(tail))
        d.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill=255)
        ang = math.radians(a1 if head_end else a0)
        px, py = c + R * math.cos(ang), c + R * math.sin(ang)
        sgn = 1.0 if head_end else -1.0
        tx, ty = -math.sin(ang) * sgn, math.cos(ang) * sgn    # куда продолжается дуга
        nx, ny = math.cos(ang), math.sin(ang)
        L = S * 0.24
        tip = (px + tx * L * 0.9, py + ty * L * 0.9)
        p1 = (px + nx * L * 0.62 - tx * L * 0.12, py + ny * L * 0.62 - ty * L * 0.12)
        p2 = (px - nx * L * 0.62 - tx * L * 0.12, py - ny * L * 0.62 - ty * L * 0.12)
        d.polygon([tip, p1, p2], fill=255)
    elif kind in ("bulb", "bulb_glass"):
        R = S * 0.21
        cy = c - S * 0.08
        d.ellipse([c - R, cy - R, c + R, cy + R], fill=255)
        d.polygon([(c - R * 0.78, cy + R * 0.55), (c + R * 0.78, cy + R * 0.55),
                   (c + R * 0.46, cy + R * 1.25), (c - R * 0.46, cy + R * 1.25)], fill=255)
        if kind == "bulb":
            bw = R * 0.5
            y = cy + R * 1.42
            d.rounded_rectangle([c - bw, y, c + bw, y + w * 0.8], radius=w * 0.4, fill=255)
            y += w * 1.25
            d.rounded_rectangle([c - bw * 0.7, y, c + bw * 0.7, y + w * 0.8], radius=w * 0.4, fill=255)
        else:
            m2 = new_l(S, S)
            ImageDraw.Draw(m2).ellipse([c - R * 0.55, cy - R * 0.62, c - R * 0.05, cy - R * 0.2], fill=255)
            m = ImageChops.subtract(m, m2)
    elif kind == "star":
        d.polygon(star_points(c, c * 1.04, S * 0.46, S * 0.2), fill=255)
    return m


# ---------------------------------------------------------------- уровень

def load_level(n):
    src = open(os.path.join(ROOT, "scripts", "level_pack_data.gd"), encoding="utf-8").read()
    levels = re.findall(r'"(\d\d:\d+:\d+)"', src)
    head, rs, _ = levels[n - 1].split(":")
    cols, rows = int(head[0]), int(head[1])
    rects = [tuple(int(ch) for ch in rs[i:i + 6]) for i in range(0, len(rs), 6)]
    return cols, rows, rects


class Geo:
    """Геометрия поля на экране (дизайн-пиксели)."""

    def __init__(self, cols, rows, cell, cx, cy):
        self.cols, self.rows, self.cell = cols, rows, cell
        self.x = cx - cols * cell / 2
        self.y = cy - rows * cell / 2

    def cell_xy(self, cx, cy):
        return self.x + cx * self.cell, self.y + cy * self.cell

    @property
    def w(self):
        return self.cols * self.cell

    @property
    def h(self):
        return self.rows * self.cell


# ---------------------------------------------------------------- сцена (общая для стилей)

# Размеры и места — из scenes/game/game.tscn (экран 720×1280).
PAUSE, RESTART = (72, 82), (648, 82)
TITLE_Y, SCORE_Y = 60, 112
BOARD_C = (360, 520)            # центр BoardArea (22..698 × 160..876)
CELL = 104                      # клетка 6×6 при вписывании в BoardArea
UNDO, LEFT, HINT = (76, 940), (360, 940), (644, 940)
SLOTS = [(18 + i * 234, 1004, 216, 236) for i in range(3)]   # лоток: 3 гнезда 216×236
TRAY_CELL = 50                  # клетка блока в лотке (сейчас 46 — Tray.BLOCK_SCALE 0.46)

# Кадр игры на уровне 20: стоят 6, 8, 6, 3, 2; блок 4 несут к месту (правый верх) — видно «призрак»
# и магнит (число 4 внизу подпрыгивает); в лотке 3 и 4, первое гнездо пустое — оттуда взяли блок.
PLACED = [0, 1, 3, 4, 7]
DRAGGED = 2
DRAG_OFF = (-70, 128)            # несомый блок: смещение от места, дизайн-пиксели
TRAY = [None, (5, 1, 3), (6, 2, 2)]     # (индекс, ширина, высота) в лотке
MAGNET = [2, 6]                  # числа той же площади, что у несомого блока
LEFT_N = 3


class Style:
    key = "?"
    name = "?"
    pal = {}
    fonts = ["NotoSans-Black.ttf"]

    def color(self, area):
        return hexc(self.pal[max(1, min(12, area))])

    # --- примитивы (переопределяются стилями)
    def background(self, img, win=False):
        raise NotImplementedError

    def board(self, img, geo):
        raise NotImplementedError

    def badge(self, img, cx, cy, n, cell, ring=False):
        raise NotImplementedError

    def block_layer(self, wc, hc, cell, area, num=None, lifted=False):
        """Картинка блока и отступ M: клетка (0, 0) начинается в (M, M)."""
        raise NotImplementedError

    def block_shadow(self, lifted):
        """(dx, dy, размытие, цвет, непрозрачность) — дизайн-пиксели."""
        return (0, 6, 6, (0, 0, 0), 0.25) if not lifted else (10, 26, 16, (0, 0, 0), 0.35)

    def ghost(self, img, x, y, wc, hc, cell, area):
        raise NotImplementedError

    def button(self, img, cx, cy, icon, enabled=True, badge=None):
        raise NotImplementedError

    def title(self, img, cx, cy, s, size=46):
        raise NotImplementedError

    def score(self, img, cx, cy, value):
        raise NotImplementedError

    def label(self, img, cx, cy, s, size=28):
        raise NotImplementedError

    def slot(self, img, x, y, w, h, empty=False):
        raise NotImplementedError

    def win_panel(self, img):
        raise NotImplementedError

    def win_backdrop(self, img, geo):
        pass

    def fx_top(self, img, win=False):
        pass

    # --- общие
    def place_block(self, img, x, y, wc, hc, cell, area, num=None, lifted=False, scale=1.0, tilt=0.0,
                    shadow_on=True):
        im, M = self.block_layer(wc, hc, cell, area, num=num, lifted=lifted)
        if scale != 1.0 or tilt:
            cxl, cyl = im.width / 2, im.height / 2
            if scale != 1.0:
                im = im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)
            if tilt:
                im = im.rotate(tilt, resample=Image.BICUBIC, expand=True)
            X = P(x) + P(wc * cell) / 2 - im.width / 2
            Y = P(y) + P(hc * cell) / 2 - im.height / 2
        else:
            X, Y = P(x) - M, P(y) - M
        if shadow_on:
            dx, dy, bl, col, a = self.block_shadow(lifted)
            if a > 0:
                shadow(img, im.getchannel("A"), X, Y, P(dx), P(dy), P(bl), col, a)
        comp(img, im, X, Y)

    def render_game(self):
        img = Image.new("RGBA", (P(W), P(H)), (0, 0, 0, 255))
        self.background(img)
        cols, rows, rects = LEVEL
        geo = Geo(cols, rows, CELL, *BOARD_C)
        self.board(img, geo)
        for i, (x, y, w, h, nx, ny) in enumerate(rects):
            if i not in PLACED:
                cx, cy = geo.cell_xy(nx + 0.5, ny + 0.5)
                self.badge(img, cx, cy, w * h, CELL, ring=(i in MAGNET))
        for i in PLACED:
            x, y, w, h, nx, ny = rects[i]
            X, Y = geo.cell_xy(x, y)
            self.place_block(img, X, Y, w, h, CELL, w * h, num=(nx - x, ny - y))
        x, y, w, h, nx, ny = rects[DRAGGED]
        X, Y = geo.cell_xy(x, y)
        self.ghost(img, X, Y, w, h, CELL, w * h)
        # верхняя панель
        self.button(img, *PAUSE, "pause")
        self.button(img, *RESTART, "restart")
        self.title(img, 360, TITLE_Y, "УРОВЕНЬ %d" % LEVEL_N)
        self.score(img, 360, SCORE_Y, "2 340")
        # панель отмены
        self.button(img, *UNDO, "undo")
        self.label(img, *LEFT, "Осталось блоков: %d" % LEFT_N)
        self.button(img, *HINT, "bulb", badge="3")
        # лоток
        for k, (sx, sy, sw, sh) in enumerate(SLOTS):
            self.slot(img, sx, sy, sw, sh, empty=TRAY[k] is None)
            if TRAY[k] is not None:
                idx, bw, bh = TRAY[k]
                bx = sx + sw / 2 - bw * TRAY_CELL / 2
                by = sy + sh / 2 - bh * TRAY_CELL / 2
                a = bw * bh
                self.place_block(img, bx, by, bw, bh, TRAY_CELL, a, num=((bw - 1) / 2, (bh - 1) / 2))
        # несомый блок — поверх всего, чуть больше клетки поля
        self.place_block(img, X + DRAG_OFF[0], Y + DRAG_OFF[1], w, h, CELL, w * h,
                         num=((w - 1) / 2, (h - 1) / 2), lifted=True, scale=1.08, tilt=-5)
        self.fx_top(img)
        return img

    def render_win(self):
        img = Image.new("RGBA", (P(W), P(H)), (0, 0, 0, 255))
        self.background(img, win=True)
        cols, rows, rects = LEVEL
        geo = Geo(cols, rows, 80, 360, 405)
        self.win_backdrop(img, geo)
        self.board(img, geo)
        for (x, y, w, h, nx, ny) in rects:
            X, Y = geo.cell_xy(x, y)
            self.place_block(img, X, Y, w, h, 80, w * h, num=(nx - x, ny - y))
        self.title(img, 360, 92, "УРОВЕНЬ %d ПРОЙДЕН!" % LEVEL_N, size=44)
        self.win_panel(img)
        self.fx_top(img, win=True)
        return img


def replay_link(img, cy, fnt, col, draw_icon):
    """Строка «⟳ Переиграть уровень» по центру: иконка слева от текста, без наложения."""
    s = "Переиграть уровень"
    tw = ImageDraw.Draw(new_l(1, 1)).textlength(s, font=fnt) / SS
    x0 = 360 - (tw + 46) / 2
    draw_icon(x0 + 16, cy + 1)
    return x0 + 46 + tw / 2, s


TITLE_BOX = (60, 56, 660, 130)  # заголовок «УРОВЕНЬ N ПРОЙДЕН!» — конфетти его не закрывают


WIN_BOARD_BOX = (100, 145, 620, 665)  # поле в кадре победы (Geo(…, 80, 360, 405) + рамка)


def free_point(rng, area, avoid):
    """Случайная точка в area (дизайн-пиксели) вне прямоугольника avoid (или списка прямоугольников)."""
    boxes = [avoid] if avoid and not isinstance(avoid[0], (tuple, list)) else (avoid or [])
    x0, y0, x1, y1 = area
    while True:
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        if not any(b[0] <= x <= b[2] and b[1] <= y <= b[3] for b in boxes):
            return x, y


def confetti(img, colors, seed, n, area, size=(8, 16), blur_share=0.3, alpha=235, avoid=TITLE_BOX):
    rng = random.Random(seed)
    for _ in range(n):
        w = P(rng.uniform(size[0] * 0.8, size[0] * 1.3))
        h = P(rng.uniform(size[1] * 0.8, size[1] * 1.3))
        pad = max(w, h)
        m = new_l(w + 2 * pad, h + 2 * pad)
        if rng.random() < 0.35:
            ImageDraw.Draw(m).ellipse([pad, pad, pad + w, pad + w], fill=255)
        else:
            ImageDraw.Draw(m).rounded_rectangle([pad, pad, pad + w, pad + h], radius=w // 3, fill=255)
        m = m.rotate(rng.uniform(0, 360), resample=Image.BICUBIC)
        if rng.random() < blur_share:
            m = m.filter(ImageFilter.GaussianBlur(P(rng.uniform(1.5, 3))))
        col = colors[rng.randrange(len(colors))]
        px, py = free_point(rng, area, avoid)
        comp(img, paint(scale_mask(m, alpha / 255), col), P(px) - m.width // 2, P(py) - m.height // 2)


def rays(img, cx, cy, n, r, color, alpha, rot=0.0):
    m = new_l(P(W), P(H))
    d = ImageDraw.Draw(m)
    for i in range(n):
        a0 = math.radians(rot + i * 360.0 / n)
        a1 = math.radians(rot + (i + 0.5) * 360.0 / n)
        d.polygon([(P(cx), P(cy)), (P(cx) + P(r) * math.cos(a0), P(cy) + P(r) * math.sin(a0)),
                   (P(cx) + P(r) * math.cos(a1), P(cy) + P(r) * math.sin(a1))], fill=255)
    fade = grad_radial(P(W), P(H), P(cx), P(cy), P(r), [(0, (0, 0, 0, 255)), (0.15, (0, 0, 0, 255)), (1, (0, 0, 0, 0))])
    m = mul_mask(m, fade.getchannel("A")).filter(ImageFilter.GaussianBlur(P(1.5)))
    comp(img, paint(scale_mask(m, alpha), color), 0, 0)


# ================================================================ A. «Мармелад»

class Jelly(Style):
    key = "A"
    name = "Мармелад"
    fonts = ["NotoSans-Black.ttf"]
    pal = {1: "#A5B4FC", 2: "#FF5470", 3: "#FF9636", 4: "#FFCE2E", 5: "#27D39B", 6: "#33C6F4",
           7: "#4C86FF", 8: "#9A63FF", 9: "#F25BCF", 10: "#FF8ADD", 11: "#B2E542", 12: "#62C93A"}
    INK = hexc("#3A1D8F")        # тёмный фиолетовый: обводки текста, иконки
    ACCENT = hexc("#5B3FD9")

    def background(self, img, win=False):
        w, h = img.size
        g = grad_v(w, h, [(0, hexc("#5436D6")), (0.55, hexc("#7A45E0")), (1, hexc("#B454D9"))])
        img.alpha_composite(g)
        comp(img, grad_radial(w, h, w * 0.5, h * 0.18, w * 0.9,
                              [(0, (255, 255, 255, 60)), (1, (255, 255, 255, 0))]), 0, 0)
        rng = random.Random(7)
        for _ in range(16):   # плывущие квадраты — как сейчас, мягче
            s = P(rng.uniform(40, 130))
            m = rr_mask(s * 2, s * 2, (s / 2, s / 2, s * 1.5, s * 1.5), s * 0.28)
            m = m.rotate(rng.uniform(-30, 30), resample=Image.BICUBIC)
            if rng.random() < 0.5:
                m = m.filter(ImageFilter.GaussianBlur(P(3)))
            comp(img, paint(scale_mask(m, rng.uniform(0.05, 0.11)), (255, 255, 255)),
                 P(rng.uniform(-40, W)) - s, P(rng.uniform(-40, H)) - s)

    def board(self, img, geo):
        pad, depth, r = 18, 12, 38
        x0, y0 = P(geo.x - pad), P(geo.y - pad)
        fw, fh = P(geo.w + 2 * pad), P(geo.h + 2 * pad)
        lw, lh = fw, fh + P(depth)
        lip = rr_mask(lw, lh, (0, P(depth), fw, lh), P(r))
        face = rr_mask(lw, lh, (0, 0, fw, fh), P(r))
        shadow(img, lip, x0, y0, 0, P(14), P(18), hexc("#24106B"), 0.45)
        comp(img, paint(lip, hexc("#CDBBFF")), x0, y0)
        comp(img, paint(face, grad_v(lw, lh, [(0, (255, 255, 255)), (1, hexc("#F1EAFF"))])), x0, y0)
        C = P(geo.cell)
        ins = P(4)
        for cy in range(geo.rows):
            for cx in range(geo.cols):
                X, Y = P(geo.x) + cx * C, P(geo.y) + cy * C
                well = rr_mask(C, C, (ins, ins, C - ins, C - ins), P(20))
                comp(img, paint(well, hexc("#DDD2FB")), X, Y)
                inner = rr_mask(C, C, (ins, ins + P(4), C - ins, C - ins), P(20))
                comp(img, paint(inner, hexc("#EEE8FF")), X, Y)

    def _gummy(self, lw, lh, box, r, depth, col, gloss=True):
        """Мармеладная форма: нижняя грань, тело с градиентом, мягкий край, блик."""
        im = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
        x0, y0, x1, y1 = box
        lip = rr_mask(lw, lh, (x0, y0 + depth, x1, y1), r)
        face = rr_mask(lw, lh, (x0, y0, x1, y1 - depth), r)
        im.alpha_composite(paint(lip, darken(col, 0.28)))
        t0, t1 = y0 / lh, (y1 - depth) / lh
        im.alpha_composite(paint(face, grad_v(lw, lh, [(t0, lighten(col, 0.28)), (t1, darken(col, 0.02))])))
        k = min(x1 - x0, y1 - y0)
        core = rr_mask(lw, lh, (x0 + k * 0.09, y0 + k * 0.07, x1 - k * 0.09, y1 - depth - k * 0.1), r * 0.8)
        core = core.filter(ImageFilter.GaussianBlur(k * 0.06))
        rim = mul_mask(face, ImageChops.invert(core))
        im.alpha_composite(paint(scale_mask(rim, 0.55), darken(col, 0.16)))
        if gloss:
            gh = min(k * 0.34, (y1 - depth - y0) * 0.4)
            gl = rr_mask(lw, lh, (x0 + k * 0.1, y0 + k * 0.06, x1 - k * 0.1, y0 + k * 0.06 + gh), gh / 2)
            fade = grad_v(lw, lh, [(y0 / lh, (255, 255, 255, 150)), ((y0 + k * 0.06 + gh) / lh, (255, 255, 255, 10))])
            im.alpha_composite(paint(gl, fade))
            s = k * 0.07
            sx, sy = x0 + k * 0.14, y0 + k * 0.1
            im.alpha_composite(paint(ellipse_mask(lw, lh, (sx, sy, sx + s * 1.6, sy + s)), (255, 255, 255, 235)))
        return im

    def block_layer(self, wc, hc, cell, area, num=None, lifted=False):
        C = P(cell)
        M = int(C * 0.3)
        Wb, Hb = int(wc * C), int(hc * C)
        lw, lh = Wb + 2 * M, Hb + 2 * M
        col = self.color(area)
        g = C * 0.045
        depth = C * 0.08
        im = self._gummy(lw, lh, (M + g, M + g, M + Wb - g, M + Hb - g), C * 0.27, depth, col)
        # мягкие швы между клетками — видно, сколько клеток в блоке
        d = ImageDraw.Draw(seam := new_l(lw, lh))
        for k in range(1, wc):
            X = M + k * C
            d.line([X, M + C * 0.22, X, M + Hb - depth - C * 0.2], fill=255, width=max(2, P(2)))
        for k in range(1, hc):
            Y = M + k * C - depth / 2
            d.line([M + C * 0.22, Y, M + Wb - C * 0.22, Y], fill=255, width=max(2, P(2)))
        seam = seam.filter(ImageFilter.GaussianBlur(P(0.8)))
        im.alpha_composite(paint(scale_mask(seam, 0.28), darken(col, 0.3)))
        im.alpha_composite(paint(scale_mask(ImageChops.offset(seam, 0, P(2)), 0.3), (255, 255, 255)))
        if num is not None:
            cx = M + (num[0] + 0.5) * C
            cy = M + (num[1] + 0.5) * C - depth / 2
            f = font(self.fonts, cell * 0.44)
            text(im, cx / SS, cy / SS, str(area), f, (255, 255, 255), stroke=cell * 0.035,
                 stroke_fill=darken(col, 0.38), shadow_off=(0, cell * 0.03), shadow_col=darken(col, 0.5),
                 shadow_a=120)
        return im, M

    def block_shadow(self, lifted):
        if lifted:
            return (8, 26, 14, hexc("#2A1270"), 0.38)
        return (0, 4, 4, hexc("#3A2090"), 0.22)

    def badge(self, img, cx, cy, n, cell, ring=False):
        col = self.color(n)
        D = P(cell * 0.62)
        M = P(cell * 0.2)
        lw = D + 2 * M
        im = self._gummy(lw, lw, (M, M, M + D, M + D), D / 2, P(cell * 0.05), col)
        text(im, lw / 2 / SS, (lw / 2 - P(cell * 0.025)) / SS, str(n), font(self.fonts, cell * 0.36),
             (255, 255, 255), stroke=cell * 0.03, stroke_fill=darken(col, 0.4))
        X, Y = P(cx) - lw / 2, P(cy) - lw / 2
        if ring:   # магнит: числа той же площади «подпрыгивают» — кольцо и подъём
            R = D * 0.62
            rm = new_l(lw * 2, lw * 2)
            ImageDraw.Draw(rm).ellipse([lw - R, lw - R, lw + R, lw + R], outline=255, width=P(4))
            comp(img, paint(scale_mask(rm, 0.9), (255, 255, 255)), P(cx) - lw, P(cy) - lw)
            Y -= P(5)
        shadow(img, im.getchannel("A"), X, Y, 0, P(4), P(4), hexc("#3A2090"), 0.25)
        comp(img, im, X, Y)

    def ghost(self, img, x, y, wc, hc, cell, area):
        col = self.color(area)
        C = P(cell)
        g = C * 0.05
        w, h = int(wc * C), int(hc * C)
        body = rr_mask(w, h, (g, g, w - g, h - g), C * 0.27)
        comp(img, paint(scale_mask(body, 0.55), col), P(x), P(y))
        inner = rr_mask(w, h, (g + P(5), g + P(5), w - g - P(5), h - g - P(5)), C * 0.22)
        rim = mul_mask(body, ImageChops.invert(inner))
        comp(img, paint(scale_mask(rim, 0.95), (255, 255, 255)), P(x), P(y))

    def button(self, img, cx, cy, icon, enabled=True, badge=None):
        D = P(96)
        M = P(14)
        lw = D + 2 * M
        im = Image.new("RGBA", (lw, lw), (0, 0, 0, 0))
        lip = ellipse_mask(lw, lw, (M, M + P(7), M + D, M + D))
        face = ellipse_mask(lw, lw, (M, M, M + D, M + D - P(7)))
        im.alpha_composite(paint(lip, hexc("#BBA6F7")))
        im.alpha_composite(paint(face, grad_v(lw, lw, [(0.1, (255, 255, 255)), (0.9, hexc("#EEE7FF"))])))
        ic = icon_mask(icon, P(54), P(8.5))
        col = self.ACCENT if enabled else hexc("#B3A6DA")
        comp(im, paint(ic, col), lw / 2 - ic.width / 2, lw / 2 - ic.height / 2 - P(3.5))
        if icon == "bulb" and enabled:
            gm = icon_mask("bulb_glass", P(54), P(8.5))
            comp(im, paint(gm, hexc("#FFC21A")), lw / 2 - gm.width / 2, lw / 2 - gm.height / 2 - P(3.5))
        X, Y = P(cx) - lw / 2, P(cy) - lw / 2
        shadow(img, im.getchannel("A"), X, Y, 0, P(6), P(8), hexc("#24106B"), 0.35)
        comp(img, im, X, Y)
        if badge:
            bd = P(40)
            bm = P(8)
            bl = bd + 2 * bm
            b = self._gummy(bl, bl, (bm, bm, bm + bd, bm + bd), bd / 2, P(4), hexc("#FF4D6A"), gloss=False)
            text(b, bl / 2 / SS, (bl / 2 - P(2)) / SS, badge, font(self.fonts, 24), (255, 255, 255))
            comp(img, b, P(cx + 34) - bl / 2, P(cy - 34) - bl / 2)

    def title(self, img, cx, cy, s, size=46):
        text(img, cx, cy, s, font(self.fonts, size), (255, 255, 255), stroke=6, stroke_fill=self.INK,
             shadow_off=(0, 5), shadow_col=hexc("#1E0B5C"), shadow_a=150)

    def score(self, img, cx, cy, value):
        f = font(self.fonts, 36)
        tw = ImageDraw.Draw(new_l(1, 1)).textlength(value, font=f) / SS
        sx = cx - (tw + 46) / 2
        st = P(44)
        m = icon_mask("star", st, 1)
        m = round_shape(m, P(2.5))
        comp(img, paint(m, darken(hexc("#FFB800"), 0.25)), P(sx) , P(cy - 22) + P(3))
        comp(img, paint(m, grad_v(st, st, [(0, hexc("#FFF3A0")), (1, hexc("#FFB800"))])), P(sx), P(cy - 22))
        text(img, sx + 46 + tw / 2, cy, value, f, hexc("#FFE066"), stroke=5, stroke_fill=self.INK,
             shadow_off=(0, 4), shadow_col=hexc("#1E0B5C"), shadow_a=130)

    def label(self, img, cx, cy, s, size=28):
        text(img, cx, cy, s, font(self.fonts, size), (255, 255, 255), stroke=0,
             shadow_off=(0, 3), shadow_col=hexc("#1E0B5C"), shadow_a=120)

    def slot(self, img, x, y, w, h, empty=False):
        lw, lh = P(w), P(h)
        m = rr_mask(lw, lh, (0, 0, lw, lh), P(32))
        comp(img, paint(scale_mask(m, 0.10 if not empty else 0.05), (255, 255, 255)), P(x), P(y))
        inner = rr_mask(lw, lh, (P(3), P(3), lw - P(3), lh - P(3)), P(29))
        rim = mul_mask(m, ImageChops.invert(inner))
        comp(img, paint(scale_mask(rim, 0.22 if not empty else 0.12), (255, 255, 255)), P(x), P(y))

    def win_backdrop(self, img, geo):
        rays(img, 360, 405, 18, 700, (255, 255, 255), 0.10, rot=8)
        m = new_l(P(W), P(H))
        ImageDraw.Draw(m).ellipse([P(40), P(80), P(680), P(730)], fill=255)
        m = m.filter(ImageFilter.GaussianBlur(P(60)))
        comp(img, paint(scale_mask(m, 0.35), (255, 230, 255)), 0, 0)

    def _star(self, img, cx, cy, R, rot):
        S = int(P(R) * 2.6)
        m = new_l(S, S)
        ImageDraw.Draw(m).polygon(star_points(S / 2, S / 2, P(R), P(R) * 0.5, rot=-90 + rot), fill=255)
        m = round_shape(m, P(R) * 0.12)
        lip = ImageChops.offset(m, 0, P(R * 0.12))
        im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        im.alpha_composite(paint(lip, hexc("#E08A00")))
        im.alpha_composite(paint(m, grad_v(S, S, [(0.2, hexc("#FFF08A")), (0.75, hexc("#FFC21A"))])))
        hl = new_l(S, S)
        ImageDraw.Draw(hl).ellipse([S * 0.36, S * 0.26, S * 0.5, S * 0.36], fill=255)
        im.alpha_composite(paint(scale_mask(mul_mask(hl, m), 0.9), (255, 255, 255)))
        shadow(img, im.getchannel("A"), P(cx) - S / 2, P(cy) - S / 2, 0, P(8), P(10), hexc("#5A2A00"), 0.35)
        comp(img, im, P(cx) - S / 2, P(cy) - S / 2)

    def win_panel(self, img):
        x0, y0, x1, y1 = 56, 742, 664, 1214
        lw, lh = P(x1 - x0), P(y1 - y0 + 14)
        lip = rr_mask(lw, lh, (0, P(14), lw, lh), P(48))
        face = rr_mask(lw, lh, (0, 0, lw, lh - P(14)), P(48))
        shadow(img, lip, P(x0), P(y0), 0, P(18), P(24), hexc("#1E0B5C"), 0.5)
        comp(img, paint(lip, hexc("#CDBBFF")), P(x0), P(y0))
        comp(img, paint(face, grad_v(lw, lh, [(0, (255, 255, 255)), (1, hexc("#F3EDFF"))])), P(x0), P(y0))
        self._star(img, 222, 772, 56, -14)
        self._star(img, 498, 772, 56, 14)
        self._star(img, 360, 742, 74, 0)
        text(img, 360, 872, "Новый рекорд! +120 к счёту", font(self.fonts, 30), self.ACCENT)
        text(img, 360, 918, "Всего очков: 2 460", font(self.fonts, 25), hexc("#8B7BC0"))
        # кнопка «ДАЛЕЕ» — зелёный мармелад
        bw, bh = P(392), P(112)
        m = P(10)
        b = self._gummy(bw + 2 * m, bh + 2 * m, (m, m, m + bw, m + bh), bh / 2, P(10), hexc("#2FCF78"))
        text(b, (bw / 2 + m) / SS, (bh / 2 + m - P(5)) / SS, "ДАЛЕЕ", font(self.fonts, 44), (255, 255, 255),
             stroke=5, stroke_fill=hexc("#137A43"))
        X, Y = P(360) - b.width / 2, P(1022) - b.height / 2
        shadow(img, b.getchannel("A"), X, Y, 0, P(8), P(10), hexc("#0E5A31"), 0.3)
        comp(img, b, X, Y)
        f = font(self.fonts, 26)
        ic = icon_mask("restart", P(36), P(5))
        tx, s = replay_link(img, 1130, f, None, lambda x, y: comp(img, paint(ic, hexc("#7A68B5")),
                                                                    P(x) - ic.width / 2, P(y) - ic.height / 2))
        text(img, tx, 1130, s, f, hexc("#7A68B5"))

    def fx_top(self, img, win=False):
        if win:
            cols = [self.color(a) for a in (2, 3, 4, 5, 6, 8, 9)] + [(255, 255, 255)]
            confetti(img, cols, 11, 70, (0, 20, W, 720))


# ================================================================ B. «Настольная игра»

def wood(w, h, base, dark, seed, along=90.0, across=3.0, rings=26.0, vertical=True, strength=0.55, warp_k=1.8):
    """Процедурное дерево: годовые кольца с искажением + продольные волокна. RGBA w×h."""
    w, h = int(w), int(h)
    rng = np.random.default_rng(seed)
    if not vertical:
        w, h = h, w
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    warp = noise(w, h, max(8, w / 3), seed + 1, octaves=2)
    ring = np.sin((xx / rings + warp * warp_k) * 2 * math.pi) * 0.5 + 0.5
    ring = ring ** 2
    gh, gw = max(2, int(h / along) + 2), max(2, int(w / across) + 2)
    fib = Image.fromarray((rng.random((gh, gw)) * 255).astype(np.uint8), "L").resize((w, h), Image.BICUBIC)
    fib = np.asarray(fib, dtype=float) / 255.0
    t = np.clip(0.4 * ring + 0.6 * fib, 0, 1) * strength
    b = np.array(base, dtype=float)
    d = np.array(dark, dtype=float)
    arr = b[None, None, :] * (1 - t[..., None]) + d[None, None, :] * t[..., None]
    alpha = np.full((h, w, 1), 255.0)
    img = Image.fromarray(np.concatenate([arr, alpha], -1).clip(0, 255).astype(np.uint8), "RGBA")
    return img if vertical else img.transpose(Image.Transpose.ROTATE_90)


def bevel(mask, size, light=(255, 244, 220), dark=(40, 20, 5), la=0.55, da=0.55):
    """Фаска по маске: светлый край сверху-слева, тёмный снизу-справа. Возвращает RGBA."""
    k = max(1, int(size))
    inner_tl = ImageChops.offset(mask, k, k)
    inner_br = ImageChops.offset(mask, -k, -k)
    hl = ImageChops.subtract(mask, inner_tl).filter(ImageFilter.GaussianBlur(k * 0.5))
    sh = ImageChops.subtract(mask, inner_br).filter(ImageFilter.GaussianBlur(k * 0.5))
    out = paint(mul_mask(scale_mask(hl, la), mask), light)
    out.alpha_composite(paint(mul_mask(scale_mask(sh, da), mask), dark))
    return out


class Tabletop(Style):
    key = "B"
    name = "Настольная игра"
    fonts = ["URWBookman-Demi.otf"]
    pal = {1: "#8D99AE", 2: "#C8553D", 3: "#E0893F", 4: "#E7BE55", 5: "#6A994E", 6: "#2A9D8F",
           7: "#3D5A80", 8: "#7B5EA7", 9: "#B5487A", 10: "#D98BA8", 11: "#A7C957", 12: "#588157"}
    CREAM = hexc("#FFF3DA")
    INK = hexc("#3B2414")
    IVORY = hexc("#F6ECD6")
    LIGHT = (-1, -1)   # свет сверху-слева: тени уходят вправо-вниз

    def background(self, img, win=False):
        w, h = img.size
        plank = P(180)
        for i in range(0, w // plank + 2):
            tone = [hexc("#9C6B42"), hexc("#94643D"), hexc("#A2714A")][i % 3]
            wd = wood(plank, h, tone, darken(tone, 0.35), seed=30 + i, along=160 * SS, across=2.5 * SS,
                      rings=38 * SS, strength=0.5)
            comp(img, wd, i * plank - P(40), 0)
            seam = Image.new("RGBA", (P(3), h), rgba(darken(tone, 0.55), 200))
            comp(img, seam, i * plank - P(40), 0)
        # тёплый свет сверху-слева и виньетка
        comp(img, grad_radial(w, h, w * 0.3, h * 0.25, w * 1.05,
                              [(0, (255, 214, 150, 70)), (1, (255, 214, 150, 0))]), 0, 0)
        comp(img, grad_radial(w, h, w * 0.5, h * 0.45, h * 0.75,
                              [(0.45, (20, 8, 0, 0)), (1, (20, 8, 0, 170))]), 0, 0)

    def board(self, img, geo):
        pad, r = 22, 26
        x0, y0 = P(geo.x - pad), P(geo.y - pad)
        fw, fh = P(geo.w + 2 * pad), P(geo.h + 2 * pad)
        frame = rr_mask(fw, fh, (0, 0, fw, fh), P(r))
        shadow(img, frame, x0, y0, P(14), P(20), P(18), hexc("#1A0C02"), 0.6)
        comp(img, paint(frame, wood(fw, fh, hexc("#6B4226"), hexc("#3A2212"), 5, along=120 * SS,
                                    across=2 * SS, rings=30 * SS, vertical=False)), x0, y0)
        comp(img, bevel(frame, P(5), la=0.45, da=0.6), x0, y0)
        # дно: темнее, с внутренней тенью сверху-слева
        ins = P(pad - 8)
        floor = rr_mask(fw, fh, (ins, ins, fw - ins, fh - ins), P(12))
        comp(img, paint(floor, wood(fw, fh, hexc("#4A2E1B"), hexc("#2C1A0E"), 6, along=110 * SS,
                                    across=2 * SS, rings=24 * SS)), x0, y0)
        inner = ImageChops.offset(floor, P(6), P(7))
        ish = ImageChops.subtract(floor, inner).filter(ImageFilter.GaussianBlur(P(5)))
        comp(img, paint(mul_mask(ish, floor), (10, 4, 0, 220)), x0, y0)
        # резные линии сетки
        d = ImageDraw.Draw(g := new_l(fw, fh))
        d2 = ImageDraw.Draw(gl := new_l(fw, fh))
        C = P(geo.cell)
        ox, oy = P(geo.x) - x0, P(geo.y) - y0
        for k in range(1, geo.cols):
            X = ox + k * C
            d.line([X, oy + P(6), X, oy + geo.rows * C - P(6)], fill=255, width=P(3))
            d2.line([X + P(2), oy + P(6), X + P(2), oy + geo.rows * C - P(6)], fill=255, width=P(1.5))
        for k in range(1, geo.rows):
            Y = oy + k * C
            d.line([ox + P(6), Y, ox + geo.cols * C - P(6), Y], fill=255, width=P(3))
            d2.line([ox + P(6), Y + P(2), ox + geo.cols * C - P(6), Y + P(2)], fill=255, width=P(1.5))
        comp(img, paint(scale_mask(g, 0.75), hexc("#1C0F06")), x0, y0)
        comp(img, paint(scale_mask(gl, 0.22), hexc("#E8C9A0")), x0, y0)

    def _tile(self, lw, lh, box, r, col, depth, seed):
        """Крашеная деревянная плитка: боковая грань, тело с волокнами, фаска."""
        x0, y0, x1, y1 = box
        im = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
        side = rr_mask(lw, lh, (x0, y0 + depth, x1, y1), r)
        top = rr_mask(lw, lh, (x0, y0, x1, y1 - depth), r)
        im.alpha_composite(paint(side, darken(col, 0.42)))
        grain = wood(lw, lh, col, darken(col, 0.25), seed, along=90 * SS, across=1.6 * SS, rings=28 * SS,
                     vertical=(x1 - x0) < (y1 - y0), strength=0.32, warp_k=1.2)
        im.alpha_composite(paint(top, grain))
        light = grad_v(lw, lh, [(y0 / lh, (255, 240, 210, 50)), ((y1 - depth) / lh, (0, 0, 0, 0))])
        im.alpha_composite(paint(top, light))
        im.alpha_composite(bevel(top, max(2, P(3)), la=0.5, da=0.35))
        return im

    def _pip(self, im, cx, cy, rad, col):
        m = ellipse_mask(im.width, im.height, (cx - rad, cy - rad, cx + rad, cy + rad))
        im.alpha_composite(paint(m, darken(col, 0.38)))
        hl = ImageChops.subtract(m, ImageChops.offset(m, -max(1, int(rad * 0.35)), -max(1, int(rad * 0.35))))
        im.alpha_composite(paint(scale_mask(hl, 0.5), lighten(col, 0.4)))

    def _token(self, im, cx, cy, D, n, ring_col, fsize):
        """Фарфоровая фишка с числом (на поле и на блоке)."""
        lw, lh = im.size
        m = ellipse_mask(lw, lh, (cx - D / 2, cy - D / 2, cx + D / 2, cy + D / 2))
        edge = ellipse_mask(lw, lh, (cx - D / 2, cy - D / 2 + D * 0.06, cx + D / 2, cy + D / 2 + D * 0.06))
        im.alpha_composite(paint(edge, hexc("#B9A27C")))
        im.alpha_composite(paint(m, grad_v(lw, lh, [((cy - D / 2) / lh, hexc("#FFFBF0")),
                                                    ((cy + D / 2) / lh, hexc("#EADBBE"))])))
        inner = ellipse_mask(lw, lh, (cx - D * 0.4, cy - D * 0.4, cx + D * 0.4, cy + D * 0.4))
        ring = ImageChops.subtract(inner, ellipse_mask(lw, lh, (cx - D * 0.34, cy - D * 0.34, cx + D * 0.34,
                                                                cy + D * 0.34)))
        im.alpha_composite(paint(scale_mask(ring, 0.9), ring_col))
        text(im, cx / SS, (cy + P(1)) / SS, str(n), font(self.fonts, fsize), darken(ring_col, 0.35))

    def block_layer(self, wc, hc, cell, area, num=None, lifted=False):
        C = P(cell)
        M = int(C * 0.3)
        Wb, Hb = int(wc * C), int(hc * C)
        lw, lh = Wb + 2 * M, Hb + 2 * M
        col = self.color(area)
        g = C * 0.035
        depth = C * 0.07
        im = self._tile(lw, lh, (M + g, M + g, M + Wb - g, M + Hb - g), C * 0.12, col, depth, seed=area * 7 + wc)
        for yy in range(hc):
            for xx in range(wc):
                cx = M + (xx + 0.5) * C
                cy = M + (yy + 0.5) * C - depth / 2
                if num is not None and abs(xx - num[0]) < 0.6 and abs(yy - num[1]) < 0.6 and float(num[0]).is_integer() \
                        and float(num[1]).is_integer():
                    continue
                if num is not None and not (float(num[0]).is_integer() and float(num[1]).is_integer()):
                    continue
                self._pip(im, cx, cy, C * 0.07, col)
        if num is not None:
            cx = M + (num[0] + 0.5) * C
            cy = M + (num[1] + 0.5) * C - depth / 2
            self._token(im, cx, cy, C * 0.6, area, col, cell * 0.3)
        return im, M

    def block_shadow(self, lifted):
        if lifted:
            return (22, 30, 14, hexc("#140800"), 0.5)
        return (4, 6, 4, hexc("#0E0500"), 0.55)

    def badge(self, img, cx, cy, n, cell, ring=False):
        D = P(cell * 0.62)
        M = P(cell * 0.2)
        lw = D + 2 * M
        im = Image.new("RGBA", (lw, lw), (0, 0, 0, 0))
        self._token(im, lw / 2, lw / 2, D, n, self.color(n), cell * 0.33)
        X, Y = P(cx) - lw / 2, P(cy) - lw / 2
        if ring:   # магнит: тёплая подсветка под фишкой и приподнятость
            m = ellipse_mask(lw * 2, lw * 2, (lw - D * 0.75, lw - D * 0.75, lw + D * 0.75, lw + D * 0.75))
            glow(img, m, P(cx) - lw, P(cy) - lw, P(8), hexc("#FFD27A"), 0.55)
            Y -= P(4)
            shadow(img, im.getchannel("A"), X, Y, P(6), P(9), P(5), hexc("#0E0500"), 0.55)
        else:
            shadow(img, im.getchannel("A"), X, Y, P(2), P(3), P(2), hexc("#0E0500"), 0.5)
        comp(img, im, X, Y)

    def ghost(self, img, x, y, wc, hc, cell, area):
        col = self.color(area)
        C = P(cell)
        g = C * 0.05
        w, h = int(wc * C), int(hc * C)
        body = rr_mask(w, h, (g, g, w - g, h - g), C * 0.12)
        comp(img, paint(scale_mask(body, 0.38), lighten(col, 0.1)), P(x), P(y))
        # пунктир мелом
        d = ImageDraw.Draw(dash := new_l(w, h))
        step, ln = P(18), P(10)
        x0, y0, x1, y1 = g + P(4), g + P(4), w - g - P(4), h - g - P(4)
        for t in range(int(x0), int(x1), step):
            d.line([t, y0, min(t + ln, x1), y0], fill=255, width=P(3.5))
            d.line([t, y1, min(t + ln, x1), y1], fill=255, width=P(3.5))
        for t in range(int(y0), int(y1), step):
            d.line([x0, t, x0, min(t + ln, y1)], fill=255, width=P(3.5))
            d.line([x1, t, x1, min(t + ln, y1)], fill=255, width=P(3.5))
        comp(img, paint(scale_mask(dash, 0.85), self.CREAM), P(x), P(y))

    def button(self, img, cx, cy, icon, enabled=True, badge=None):
        D = P(92)
        M = P(14)
        lw = D + 2 * M
        im = Image.new("RGBA", (lw, lw), (0, 0, 0, 0))
        outer = ellipse_mask(lw, lw, (M, M, M + D, M + D))
        im.alpha_composite(paint(ellipse_mask(lw, lw, (M, M + P(6), M + D, M + D + P(6))), hexc("#6E4B1F")))
        im.alpha_composite(paint(outer, grad_v(lw, lw, [(0.15, hexc("#F3D48B")), (0.85, hexc("#B7862F"))])))
        inner = ellipse_mask(lw, lw, (M + P(8), M + P(8), M + D - P(8), M + D - P(8)))
        im.alpha_composite(paint(inner, grad_v(lw, lw, [(0.2, hexc("#FFF9EC")), (0.8, hexc("#EADCC0"))])))
        im.alpha_composite(bevel(inner, P(3), light=(90, 60, 20), dark=(255, 255, 255), la=0.35, da=0.5))
        ic = icon_mask(icon, P(50), P(7.5))
        col = self.INK if enabled else hexc("#B8A68A")
        comp(im, paint(ic, col), lw / 2 - ic.width / 2, lw / 2 - ic.height / 2)
        X, Y = P(cx) - lw / 2, P(cy) - lw / 2
        if not enabled:
            im.putalpha(scale_mask(im.getchannel("A"), 0.75))
        shadow(img, im.getchannel("A"), X, Y, P(6), P(9), P(6), hexc("#140800"), 0.5)
        comp(img, im, X, Y)
        if badge:
            bl = P(52)
            b = Image.new("RGBA", (bl, bl), (0, 0, 0, 0))
            m = ellipse_mask(bl, bl, (P(6), P(6), bl - P(6), bl - P(6)))
            b.alpha_composite(paint(m, hexc("#B23A2A")))
            b.alpha_composite(bevel(m, P(2.5), la=0.4, da=0.5))
            text(b, bl / 2 / SS, bl / 2 / SS, badge, font(self.fonts, 22), self.CREAM)
            shadow(img, b.getchannel("A"), P(cx + 34) - bl / 2, P(cy - 34) - bl / 2, P(2), P(3), P(2),
                   hexc("#140800"), 0.5)
            comp(img, b, P(cx + 34) - bl / 2, P(cy - 34) - bl / 2)

    def title(self, img, cx, cy, s, size=46):
        text(img, cx, cy, s, font(self.fonts, size * 0.92), self.CREAM, shadow_off=(2, 4),
             shadow_col=hexc("#1C0D03"), shadow_a=200, shadow_blur=1.5)

    def score(self, img, cx, cy, value):
        f = font(self.fonts, 32)
        tw = ImageDraw.Draw(new_l(1, 1)).textlength(value, font=f) / SS
        sx = cx - (tw + 46) / 2
        st = P(42)
        m = round_shape(icon_mask("star", st, 1), P(1.5))
        shadow(img, m, P(sx), P(cy - 21), P(2), P(3), P(2), hexc("#1C0D03"), 0.6)
        comp(img, paint(m, grad_v(st, st, [(0.1, hexc("#FBE3A1")), (0.9, hexc("#B7862F"))])), P(sx), P(cy - 21))
        comp(img, bevel(m, P(2), la=0.5, da=0.4), P(sx), P(cy - 21))
        text(img, sx + 46 + tw / 2, cy, value, f, hexc("#F7DA92"), shadow_off=(2, 3),
             shadow_col=hexc("#1C0D03"), shadow_a=190, shadow_blur=1)

    def label(self, img, cx, cy, s, size=28):
        text(img, cx, cy, s, font(self.fonts, size * 0.9), self.CREAM, shadow_off=(2, 3),
             shadow_col=hexc("#1C0D03"), shadow_a=190, shadow_blur=1)

    def _felt(self, w, h, col, seed):
        n = noise(w, h, 3 * SS, seed, octaves=2)
        b = np.array(col, dtype=float)
        arr = b[None, None, :] * (0.86 + 0.22 * n[..., None])
        alpha = np.full((int(h), int(w), 1), 255.0)
        return Image.fromarray(np.concatenate([arr, alpha], -1).clip(0, 255).astype(np.uint8), "RGBA")

    def slot(self, img, x, y, w, h, empty=False):
        if x < 30:   # общая деревянная полка под лотком — один раз
            rx0, ry0, rw, rh = P(6), P(y - 14), P(W - 12), P(h + 28)
            rack = rr_mask(rw, rh, (0, 0, rw, rh), P(26))
            shadow(img, rack, rx0, ry0, P(10), P(16), P(16), hexc("#140800"), 0.55)
            comp(img, paint(rack, wood(rw, rh, hexc("#6B4226"), hexc("#3A2212"), 9, along=120 * SS,
                                       across=2 * SS, rings=30 * SS, vertical=False)), rx0, ry0)
            comp(img, bevel(rack, P(4), la=0.45, da=0.6), rx0, ry0)
        lw, lh = P(w), P(h)
        m = rr_mask(lw, lh, (0, 0, lw, lh), P(20))
        comp(img, paint(m, self._felt(lw, lh, hexc("#2E5B4B") if not empty else hexc("#284F41"), 21 + int(x))),
             P(x), P(y))
        inner = ImageChops.offset(m, P(5), P(6))
        ish = ImageChops.subtract(m, inner).filter(ImageFilter.GaussianBlur(P(4)))
        comp(img, paint(mul_mask(ish, m), (5, 15, 10, 230)), P(x), P(y))

    def win_backdrop(self, img, geo):
        m = new_l(P(W), P(H))
        ImageDraw.Draw(m).ellipse([P(20), P(60), P(700), P(760)], fill=255)
        m = m.filter(ImageFilter.GaussianBlur(P(70)))
        comp(img, paint(scale_mask(m, 0.4), hexc("#FFD9A0")), 0, 0)

    def _medal(self, img, cx, cy, R, rot, lit=True):
        S = int(P(R) * 2.6)
        m = new_l(S, S)
        ImageDraw.Draw(m).polygon(star_points(S / 2, S / 2, P(R), P(R) * 0.52, rot=-90 + rot), fill=255)
        m = round_shape(m, P(R) * 0.06)
        im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        im.alpha_composite(paint(m, grad_v(S, S, [(0.2, hexc("#FFEFB8")), (0.5, hexc("#E2B252")),
                                               (0.8, hexc("#9C6A1E"))])))
        im.alpha_composite(bevel(m, P(R) * 0.1, la=0.7, da=0.55))
        inner = new_l(S, S)
        ImageDraw.Draw(inner).polygon(star_points(S / 2, S / 2, P(R) * 0.62, P(R) * 0.32, rot=-90 + rot), fill=255)
        inner = round_shape(inner, P(R) * 0.04)
        im.alpha_composite(bevel(inner, P(R) * 0.06, light=(90, 50, 0), dark=(255, 245, 210), la=0.5, da=0.6))
        shadow(img, im.getchannel("A"), P(cx) - S / 2, P(cy) - S / 2, P(8), P(12), P(8), hexc("#140800"), 0.5)
        comp(img, im, P(cx) - S / 2, P(cy) - S / 2)

    def win_panel(self, img):
        x0, y0, x1, y1 = 52, 740, 668, 1216
        lw, lh = P(x1 - x0), P(y1 - y0)
        card = rr_mask(lw, lh, (0, 0, lw, lh), P(18))
        shadow(img, card, P(x0), P(y0), P(14), P(20), P(18), hexc("#140800"), 0.6)
        n = noise(lw, lh, 2 * SS, 77, octaves=2)
        base = np.array(hexc("#F4E6C8"), dtype=float)
        paper = base[None, None, :] * (0.93 + 0.1 * n[..., None])
        paper = Image.fromarray(np.concatenate([paper, np.full((lh, lw, 1), 255.0)], -1).clip(0, 255)
                                .astype(np.uint8), "RGBA")
        comp(img, paint(card, paper), P(x0), P(y0))
        d = ImageDraw.Draw(img)
        for k, wdt in ((14, 3), (22, 1.5)):
            d.rounded_rectangle([P(x0 + k), P(y0 + k), P(x1 - k), P(y1 - k)], radius=P(max(4, 18 - k / 2)),
                                outline=rgba(hexc("#8A5A2B"), 200), width=P(wdt))
        self._medal(img, 222, 782, 54, -12)
        self._medal(img, 498, 782, 54, 12)
        self._medal(img, 360, 752, 72, 0)
        text(img, 360, 880, "Новый рекорд! +120 к счёту", font(self.fonts, 28), hexc("#7A3B1C"))
        text(img, 360, 924, "Всего очков: 2 460", font(self.fonts, 23), hexc("#8A6A48"))
        bw, bh = P(380), P(104)
        m = P(12)
        b = self._tile(bw + 2 * m, bh + 2 * m + P(8), (m, m, m + bw, m + bh + P(8)), P(22), hexc("#4F8A4B"),
                       P(8), 3)
        text(b, (bw / 2 + m) / SS, (bh / 2 + m) / SS, "ДАЛЕЕ", font(self.fonts, 40), self.CREAM,
             shadow_off=(1, 2), shadow_col=hexc("#1E3A1C"), shadow_a=200)
        X, Y = P(360) - b.width / 2, P(1024) - b.height / 2
        shadow(img, b.getchannel("A"), X, Y, P(6), P(9), P(6), hexc("#140800"), 0.45)
        comp(img, b, X, Y)
        f = font(self.fonts, 24)
        ic = icon_mask("restart", P(36), P(5))
        tx, s = replay_link(img, 1134, f, None, lambda x, y: comp(img, paint(ic, hexc("#7A5634")),
                                                                    P(x) - ic.width / 2, P(y) - ic.height / 2))
        text(img, tx, 1134, s, f, hexc("#7A5634"))

    def fx_top(self, img, win=False):
        # пылинки в луче света
        rng = random.Random(5 if not win else 6)
        for _ in range(26 if not win else 60):
            r = P(rng.uniform(1.2, 3.2))
            m = new_l(r * 6, r * 6)
            ImageDraw.Draw(m).ellipse([r * 2, r * 2, r * 4, r * 4], fill=255)
            m = m.filter(ImageFilter.GaussianBlur(r * 0.6))
            comp(img, paint(scale_mask(m, rng.uniform(0.25, 0.6)), hexc("#FFE6B0")),
                 P(rng.uniform(0, W * 0.8)) - r * 3, P(rng.uniform(0, H * 0.6)) - r * 3)
        if win:
            cols = [self.color(a) for a in (2, 3, 4, 5, 6, 8)] + [self.IVORY]
            confetti(img, cols, 12, 36, (0, 20, W, 700), size=(9, 15), blur_share=0.2, alpha=225)


# ================================================================ C. «Неон»

def outline_rr(w, h, box, r, width):
    m = new_l(w, h)
    ImageDraw.Draw(m).rounded_rectangle([int(v) for v in box], radius=int(r), outline=255, width=max(1, int(width)))
    return m


def outline_ellipse(w, h, box, width):
    m = new_l(w, h)
    ImageDraw.Draw(m).ellipse([int(v) for v in box], outline=255, width=max(1, int(width)))
    return m


def dashed_rr(w, h, box, width, step, ln):
    m = new_l(w, h)
    d = ImageDraw.Draw(m)
    x0, y0, x1, y1 = box
    for t in np.arange(x0, x1, step):
        d.line([t, y0, min(t + ln, x1), y0], fill=255, width=int(width))
        d.line([t, y1, min(t + ln, x1), y1], fill=255, width=int(width))
    for t in np.arange(y0, y1, step):
        d.line([x0, t, x0, min(t + ln, y1)], fill=255, width=int(width))
        d.line([x1, t, x1, min(t + ln, y1)], fill=255, width=int(width))
    return m


def neon(dst, line_mask, X, Y, col, r_wide, a_wide=0.75, core=None):
    """Неоновая линия: широкое свечение, узкое свечение, цветная линия, светлая сердцевина."""
    glow(dst, line_mask, X, Y, r_wide, col, a_wide)
    glow(dst, line_mask, X, Y, max(1, r_wide * 0.3), col, 0.9)
    comp(dst, paint(line_mask, col), X, Y)
    if core is not None:
        comp(dst, paint(core, lighten(col, 0.75)), X, Y)


class Neon(Style):
    key = "C"
    name = "Неон"
    fonts = ["NotoSansDisplay-SemiBold.ttf", "NotoSans-SemiBold.ttf"]  # URW Gothic: Д/Л как Δ/Λ
    pal = {1: "#9AA8FF", 2: "#FF3B6B", 3: "#FF8A1F", 4: "#FFE23B", 5: "#1FFFA5", 6: "#18E4FF",
           7: "#3D7BFF", 8: "#B84DFF", 9: "#FF3FD8", 10: "#FF8AF0", 11: "#B6FF3B", 12: "#3BFF6E"}
    CYAN = hexc("#18E4FF")
    MAGENTA = hexc("#FF3FD8")
    DIM = hexc("#2C2A66")

    def ntext(self, img, cx, cy, s, size, col, glow_r=8, white=0.8, anchor="mm"):
        f = font(self.fonts, size)
        text(img, cx, cy, s, f, lighten(col, white), glow_col=col, glow_r=glow_r, glow_a=235, anchor=anchor)
        text(img, cx, cy, s, f, lighten(col, white), glow_col=col, glow_r=max(1, glow_r * 0.3), glow_a=200,
             anchor=anchor)

    def background(self, img, win=False):
        w, h = img.size
        img.alpha_composite(grad_v(w, h, [(0, hexc("#07061A")), (0.6, hexc("#0D0A26")), (1, hexc("#160B30"))]))
        for (cx, cy, r, col, a) in ((0.05, 0.12, 0.7, self.MAGENTA, 50), (0.95, 0.55, 0.75, self.CYAN, 36),
                                    (0.3, 0.98, 0.8, hexc("#6A2BFF"), 60)):
            comp(img, grad_radial(w, h, w * cx, h * cy, w * r, [(0, rgba(col, a)), (1, rgba(col, 0))]), 0, 0)
        # сетка точек
        d = ImageDraw.Draw(dots := new_l(w, h))
        step = P(24)
        for y in range(step // 2, h, step):
            for x in range(step // 2, w, step):
                d.ellipse([x - P(1.1), y - P(1.1), x + P(1.1), y + P(1.1)], fill=255)
        comp(img, paint(scale_mask(dots, 0.13), hexc("#8C88FF")), 0, 0)
        # перспективная сетка у низа — «горизонт»
        g = new_l(w, h)
        d = ImageDraw.Draw(g)
        hy = P(1000)
        for k in range(-12, 13):
            d.line([P(360) + k * P(18), hy, P(360) + k * P(160), h], fill=255, width=P(1.2))
        yy = 0.0
        for k in range(1, 12):
            yy = hy + (h - hy) * (k / 11) ** 2
            d.line([0, yy, w, yy], fill=255, width=P(1.2))
        fade = grad_v(w, h, [(hy / h, (0, 0, 0, 0)), (1, (0, 0, 0, 255))]).getchannel("A")
        comp(img, paint(scale_mask(mul_mask(g, fade), 0.35), hexc("#7B3CFF")), 0, 0)

    def board(self, img, geo):
        pad, r = 18, 28
        x0, y0 = P(geo.x - pad), P(geo.y - pad)
        fw, fh = P(geo.w + 2 * pad), P(geo.h + 2 * pad)
        M = P(40)
        lw, lh = fw + 2 * M, fh + 2 * M
        panel = rr_mask(lw, lh, (M, M, M + fw, M + fh), P(r))
        comp(img, paint(scale_mask(panel, 0.88), hexc("#0B0A22")), x0 - M, y0 - M)
        comp(img, paint(panel, grad_v(lw, lh, [(0, (120, 110, 255, 26)), (0.5, (0, 0, 0, 0))])), x0 - M, y0 - M)
        edge = outline_rr(lw, lh, (M, M, M + fw, M + fh), P(r), P(3))
        grad = Image.new("RGBA", (lw, lh))
        grad = Image.fromarray(np.dstack([
            np.linspace(self.CYAN[i], self.MAGENTA[i], lw)[None, :].repeat(lh, 0) for i in range(3)
        ] + [np.full((lh, lw), 255)]).astype(np.uint8), "RGBA")
        glow(img, edge, x0 - M, y0 - M, P(12), hexc("#8A5CFF"), 0.8)
        comp(img, paint(edge, grad), x0 - M, y0 - M)
        C = P(geo.cell)
        ins = P(6)
        for cy in range(geo.rows):
            for cx in range(geo.cols):
                X, Y = P(geo.x) + cx * C, P(geo.y) + cy * C
                comp(img, paint(rr_mask(C, C, (ins, ins, C - ins, C - ins), P(14)), hexc("#12102E")), X, Y)
                comp(img, paint(outline_rr(C, C, (ins, ins, C - ins, C - ins), P(14), P(1.5)), self.DIM), X, Y)

    def block_layer(self, wc, hc, cell, area, num=None, lifted=False):
        C = P(cell)
        M = int(C * 0.42)
        Wb, Hb = int(wc * C), int(hc * C)
        lw, lh = Wb + 2 * M, Hb + 2 * M
        col = self.color(area)
        g = C * 0.07
        r = C * 0.18
        box = (M + g, M + g, M + Wb - g, M + Hb - g)
        im = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
        body = rr_mask(lw, lh, box, r)
        # поднятый блок непрозрачен: сквозь него не просвечивают числа соседей
        im.alpha_composite(paint(body, rgba(darken(col, 0.72), 255 if lifted else 235)))
        # внутреннее свечение от краёв
        core = rr_mask(lw, lh, (box[0] + C * 0.12, box[1] + C * 0.12, box[2] - C * 0.12, box[3] - C * 0.12), r)
        core = core.filter(ImageFilter.GaussianBlur(C * 0.1))
        im.alpha_composite(paint(scale_mask(mul_mask(body, ImageChops.invert(core)), 0.55), col))
        # деления на клетки
        d = ImageDraw.Draw(lines := new_l(lw, lh))
        for k in range(1, wc):
            X = M + k * C
            d.line([X, box[1] + C * 0.18, X, box[3] - C * 0.18], fill=255, width=P(1.5))
        for k in range(1, hc):
            Y = M + k * C
            d.line([box[0] + C * 0.18, Y, box[2] - C * 0.18, Y], fill=255, width=P(1.5))
        im.alpha_composite(paint(scale_mask(lines, 0.35), col))
        edge = outline_rr(lw, lh, box, r, P(3.2))
        coreline = outline_rr(lw, lh, (box[0] + P(1), box[1] + P(1), box[2] - P(1), box[3] - P(1)), r, P(1.2))
        neon(im, edge, 0, 0, col, P(9 if not lifted else 14), 0.85 if not lifted else 1.0, core=coreline)
        if num is not None:
            cx = (M + (num[0] + 0.5) * C) / SS
            cy = (M + (num[1] + 0.5) * C) / SS
            self.ntext(im, cx, cy, str(area), cell * 0.44, col, glow_r=cell * 0.07)
        return im, M

    def block_shadow(self, lifted):
        if lifted:
            return (6, 22, 14, (0, 0, 0), 0.7)
        return (0, 0, 0, (0, 0, 0), 0.0)

    def badge(self, img, cx, cy, n, cell, ring=False):
        col = self.color(n)
        D = P(cell * 0.6)
        M = P(cell * 0.35)
        lw = D + 2 * M
        im = Image.new("RGBA", (lw, lw), (0, 0, 0, 0))
        im.alpha_composite(paint(ellipse_mask(lw, lw, (M, M, M + D, M + D)), rgba(darken(col, 0.8), 230)))
        edge = outline_ellipse(lw, lw, (M, M, M + D, M + D), P(3))
        neon(im, edge, 0, 0, col, P(7), 0.8)
        self.ntext(im, lw / 2 / SS, lw / 2 / SS, str(n), cell * 0.32, col, glow_r=cell * 0.05)
        if ring:   # магнит: второе кольцо-импульс
            R = D * 0.78
            pr = outline_ellipse(lw, lw, (lw / 2 - R, lw / 2 - R, lw / 2 + R, lw / 2 + R), P(2))
            glow(im, pr, 0, 0, P(6), col, 0.8)
            comp(im, paint(scale_mask(pr, 0.8), lighten(col, 0.4)), 0, 0)
        comp(img, im, P(cx) - lw / 2, P(cy) - lw / 2)

    def ghost(self, img, x, y, wc, hc, cell, area):
        col = self.color(area)
        C = P(cell)
        g = C * 0.07
        M = P(30)
        w, h = int(wc * C) + 2 * M, int(hc * C) + 2 * M
        box = (M + g, M + g, w - M - g, h - M - g)
        comp(img, paint(scale_mask(rr_mask(w, h, box, C * 0.18), 0.14), col), P(x) - M, P(y) - M)
        dm = dashed_rr(w, h, box, P(3), P(20), P(11))
        neon(img, dm, P(x) - M, P(y) - M, col, P(7), 0.6)

    def button(self, img, cx, cy, icon, enabled=True, badge=None):
        col = self.CYAN if enabled else self.DIM
        D = P(88)
        M = P(30)
        lw = D + 2 * M
        im = Image.new("RGBA", (lw, lw), (0, 0, 0, 0))
        im.alpha_composite(paint(ellipse_mask(lw, lw, (M, M, M + D, M + D)), hexc("#0C0B24")))
        edge = outline_ellipse(lw, lw, (M, M, M + D, M + D), P(3))
        neon(im, edge, 0, 0, col, P(8), 0.7)
        ic = icon_mask(icon, P(50), P(5))
        if icon in ("bulb",):
            ic = ImageChops.subtract(ic, ImageChops.offset(icon_mask("bulb_glass", P(50), P(5)), 0, 0)
                                     .filter(ImageFilter.MinFilter(int(P(5)) | 1)))
        neon(im, ic, lw / 2 - ic.width / 2, lw / 2 - ic.height / 2, col, P(5), 0.8)
        comp(img, im, P(cx) - lw / 2, P(cy) - lw / 2)
        if badge:
            bl = P(76)
            b = Image.new("RGBA", (bl, bl), (0, 0, 0, 0))
            bx = (P(20), P(20), bl - P(20), bl - P(20))
            b.alpha_composite(paint(ellipse_mask(bl, bl, bx), hexc("#0C0B24")))
            neon(b, outline_ellipse(bl, bl, bx, P(2.5)), 0, 0, self.MAGENTA, P(5), 0.8)
            self.ntext(b, bl / 2 / SS, bl / 2 / SS, badge, 20, self.MAGENTA, glow_r=3)
            comp(img, b, P(cx + 34) - bl / 2, P(cy - 34) - bl / 2)

    def title(self, img, cx, cy, s, size=46):
        self.ntext(img, cx, cy, s, size * 0.95, self.CYAN, glow_r=10, white=0.85)

    def score(self, img, cx, cy, value):
        col = hexc("#FFE23B")
        f = font(self.fonts, 34)
        tw = ImageDraw.Draw(new_l(1, 1)).textlength(value, font=f) / SS
        sx = cx - (tw + 46) / 2
        st = P(40)
        m = new_l(st + P(20), st + P(20))
        ImageDraw.Draw(m).polygon(star_points(m.width / 2, m.height / 2 + P(1), st * 0.46, st * 0.2), outline=255,
                                  width=P(3))
        neon(img, m, P(sx) - P(10), P(cy - 20) - P(10), col, P(5), 0.8)
        self.ntext(img, sx + 46 + tw / 2, cy, value, 34, col, glow_r=6)

    def label(self, img, cx, cy, s, size=28):
        self.ntext(img, cx, cy, s, size * 0.9, hexc("#8C88FF"), glow_r=5, white=0.55)

    def slot(self, img, x, y, w, h, empty=False):
        lw, lh = P(w), P(h)
        M = P(20)
        box = (M, M, M + lw, M + lh)
        comp(img, paint(rr_mask(lw + 2 * M, lh + 2 * M, box, P(24)), rgba(hexc("#0C0B24"), 200)), P(x) - M, P(y) - M)
        if empty:
            e = dashed_rr(lw + 2 * M, lh + 2 * M, box, P(2), P(16), P(8))
            comp(img, paint(scale_mask(e, 0.8), self.DIM), P(x) - M, P(y) - M)
        else:
            e = outline_rr(lw + 2 * M, lh + 2 * M, box, P(24), P(2))
            glow(img, e, P(x) - M, P(y) - M, P(6), hexc("#5A4BFF"), 0.5)
            comp(img, paint(e, hexc("#3E3A8C")), P(x) - M, P(y) - M)

    def win_backdrop(self, img, geo):
        m = new_l(P(W), P(H))
        d = ImageDraw.Draw(m)
        rng = random.Random(3)
        for i in range(28):
            a = math.radians(i * 360 / 28 + rng.uniform(-3, 3))
            r0, r1 = P(rng.uniform(330, 380)), P(rng.uniform(420, 560))
            cx, cy = P(360), P(405)
            d.line([cx + r0 * math.cos(a), cy + r0 * math.sin(a), cx + r1 * math.cos(a), cy + r1 * math.sin(a)],
                   fill=255, width=P(2.5))
        glow(img, m, 0, 0, P(8), self.MAGENTA, 0.7)
        comp(img, paint(scale_mask(m, 0.8), lighten(self.MAGENTA, 0.4)), 0, 0)

    def _nstar(self, img, cx, cy, R, rot):
        col = hexc("#FFE23B")
        S = int(P(R) * 3)
        m = new_l(S, S)
        pts = star_points(S / 2, S / 2, P(R), P(R) * 0.5, rot=-90 + rot)
        ImageDraw.Draw(m).polygon(pts, fill=255)
        fillm = round_shape(m, P(R) * 0.05)
        comp(img, paint(scale_mask(fillm, 0.5), col), P(cx) - S / 2, P(cy) - S / 2)
        e = new_l(S, S)
        ImageDraw.Draw(e).line(pts + [pts[0]], fill=255, width=P(4), joint="curve")
        core = new_l(S, S)
        ImageDraw.Draw(core).line(pts + [pts[0]], fill=255, width=P(1.5), joint="curve")
        neon(img, e, P(cx) - S / 2, P(cy) - S / 2, col, P(12), 0.9, core=core)

    def win_panel(self, img):
        x0, y0, x1, y1 = 52, 740, 668, 1216
        M = P(40)
        lw, lh = P(x1 - x0) + 2 * M, P(y1 - y0) + 2 * M
        box = (M, M, lw - M, lh - M)
        comp(img, paint(rr_mask(lw, lh, box, P(30)), rgba(hexc("#0B0A22"), 235)), P(x0) - M, P(y0) - M)
        edge = outline_rr(lw, lh, box, P(30), P(3))
        grad = Image.fromarray(np.dstack([
            np.linspace(self.MAGENTA[i], self.CYAN[i], lw)[None, :].repeat(lh, 0) for i in range(3)
        ] + [np.full((lh, lw), 255)]).astype(np.uint8), "RGBA")
        glow(img, edge, P(x0) - M, P(y0) - M, P(12), hexc("#8A5CFF"), 0.9)
        comp(img, paint(edge, grad), P(x0) - M, P(y0) - M)
        self._nstar(img, 222, 790, 50, -12)
        self._nstar(img, 498, 790, 50, 12)
        self._nstar(img, 360, 760, 66, 0)
        self.ntext(img, 360, 884, "Новый рекорд! +120 к счёту", 29, self.MAGENTA, glow_r=6, white=0.7)
        self.ntext(img, 360, 930, "Всего очков: 2 460", 24, hexc("#8C88FF"), glow_r=4, white=0.55)
        col = hexc("#1FFFA5")
        bw, bh = P(380), P(100)
        m = P(40)
        bl, bhh = bw + 2 * m, bh + 2 * m
        bx = (m, m, m + bw, m + bh)
        X, Y = P(360) - bl / 2, P(1024) - bhh / 2
        comp(img, paint(rr_mask(bl, bhh, bx, bh / 2), rgba(darken(col, 0.8), 240)), X, Y)
        comp(img, paint(scale_mask(rr_mask(bl, bhh, bx, bh / 2), 0.12), col), X, Y)
        neon(img, outline_rr(bl, bhh, bx, bh / 2, P(3.5)), X, Y, col, P(12), 0.9,
             core=outline_rr(bl, bhh, (bx[0] + P(1), bx[1] + P(1), bx[2] - P(1), bx[3] - P(1)), bh / 2, P(1.2)))
        self.ntext(img, 360, 1024, "ДАЛЕЕ", 42, col, glow_r=8)
        ic = icon_mask("restart", P(36), P(3.5))
        tx, s = replay_link(img, 1134, font(self.fonts, 24), None,
                            lambda x, y: neon(img, ic, P(x) - ic.width / 2, P(y) - ic.height / 2, self.CYAN, P(3), 0.6))
        self.ntext(img, tx, 1134, s, 24, self.CYAN, glow_r=4, white=0.5)

    def fx_top(self, img, win=False):
        if not win:
            return
        rng = random.Random(9)
        cols = [self.color(a) for a in (2, 4, 5, 6, 8, 9)]
        for _ in range(55):
            col = cols[rng.randrange(len(cols))]
            s = P(rng.uniform(3, 7))
            m = new_l(s * 8, s * 8)
            d = ImageDraw.Draw(m)
            c = s * 4
            if rng.random() < 0.5:
                d.ellipse([c - s / 2, c - s / 2, c + s / 2, c + s / 2], fill=255)
            else:
                d.line([c - s, c, c + s, c], fill=255, width=max(2, s // 3))
                d.line([c, c - s, c, c + s], fill=255, width=max(2, s // 3))
            # искры — вокруг поля: на блоках «+» рядом с числом читается как «8+»
            px, py = free_point(rng, (0, 20, W, 720), [TITLE_BOX, WIN_BOARD_BOX])
            X, Y = P(px) - c, P(py) - c
            glow(img, m, X, Y, s * 0.8, col, 0.9)
            comp(img, paint(m, lighten(col, 0.6)), X, Y)


# ================================================================ запуск

LEVEL = load_level(LEVEL_N)
STYLES = {"A": Jelly, "B": Tabletop, "C": Neon}


def save(img, path):
    img.convert("RGB").resize((W, H), Image.LANCZOS).save(path, optimize=True)


SHEET_NOTES = [
    ("h", "Что смотреть"),
    ("b", "Сразу ли читаются число и размер блока?"),
    ("b", "Различимы ли соседи одного цвета (3 и 3)?"),
    ("b", "Видно ли, куда встанет несомый блок?"),
    ("b", "Хочется ли блок «потрогать»?"),
    ("b", "Не устанут ли глаза за 10 минут?"),
    ("b", "Подходит ли стиль к названию и к Яндекс Играм?"),
    ("n", "Шрифты — временные заменители, финальный выберем на этапе 13. Движение показано одним кадром."),
]


def wrap(d, s, fnt, width):
    lines, cur = [], ""
    for word in s.split():
        t = (cur + " " + word).strip()
        if cur and d.textlength(t, font=fnt) > width:
            lines.append(cur)
            cur = word
        else:
            cur = t
    return lines + [cur]


def notes(d, x, y, width, y_max):
    """Колонка «Что смотреть» на листе: переносы по ширине, кегль уменьшается, пока всё не влезет."""
    for size in range(26, 15, -1):
        fh = ImageFont.truetype(find_font(["NotoSans-Black.ttf"]), size + 4)
        fb = ImageFont.truetype(find_font(["NotoSans-SemiBold.ttf", "NotoSans-Bold.ttf"]), size)
        fn = ImageFont.truetype(find_font(["NotoSans-Regular.ttf", "NotoSans-Bold.ttf"]), size - 4)
        ops, cy = [], y
        for kind, s in SHEET_NOTES:
            if kind == "h":
                ops.append((x, cy, s, fh, (255, 255, 255)))
                cy += int((size + 4) * 1.9)
                continue
            if kind == "n":
                cy += int(size * 0.6)
            f, ind = (fb, 22) if kind == "b" else (fn, 0)
            col = (200, 200, 215) if kind == "b" else (140, 140, 158)
            if kind == "b":
                ops.append((x, cy, "•", fb, (150, 150, 255)))
            for line in wrap(d, s, f, width - ind):
                ops.append((x + ind, cy, line, f, col))
                cy += int(f.size * 1.3)
            cy += int(size * 0.75)
        if cy <= y_max:
            break
    for (tx, ty, s, f, col) in ops:
        d.text((tx, ty), s, font=f, fill=col)


def sheet(out, keys):
    """Лист сравнения: сверху — игра, снизу — победа; первый столбец — «Сейчас» (скриншот)."""
    fw, fh, gap, head, cap = 360, 640, 28, 120, 58
    cols = 1 + len(keys)
    sw, sh = cols * fw + (cols + 1) * gap, head + cap + 2 * fh + 3 * gap
    im = Image.new("RGB", (sw, sh), hexc("#1C1B22"))
    d = ImageDraw.Draw(im)
    fb = ImageFont.truetype(find_font(["NotoSans-Black.ttf"]), 44)
    fr = ImageFont.truetype(find_font(["NotoSans-Bold.ttf", "NotoSans-Black.ttf"]), 26)
    d.text((gap, 30), "Шикаку: Блоки — стиль-кадры (этап 12)", font=fb, fill=(255, 255, 255))
    d.text((gap, 84), "Уровень %d, поле 6×6. Сверху — игра (блок 4 несут к месту), снизу — победа." % LEVEL_N,
           font=fr, fill=(170, 170, 185))
    names = {"now": "Сейчас (уровень 2)"}
    for k in keys:
        names[k] = "%s. %s" % (k, STYLES[k].name)
    now = os.path.join(ROOT, "docs", "style_frames", "now_level2.png")
    for c, k in enumerate(["now"] + keys):
        x = gap + c * (fw + gap)
        for r, kind in enumerate(("game", "win")):
            y = head + gap + cap + r * (fh + gap)
            if r == 0:
                d.text((x, y - cap + 4), names[k], font=fr, fill=(255, 255, 255))
            if k == "now":
                if r == 0 and os.path.exists(now):
                    fr_im = Image.open(now).convert("RGB")
                    k2 = min(fw / fr_im.width, fh / fr_im.height)
                    fr_im = fr_im.resize((int(fr_im.width * k2), int(fr_im.height * k2)), Image.LANCZOS)
                    im.paste(fr_im, (x + (fw - fr_im.width) // 2, y))
                else:
                    d.rounded_rectangle([x, y, x + fw, y + fh], radius=18, outline=(70, 70, 85), width=2)
                    notes(d, x + 22, y + 20, fw - 40, y + fh - 16)
                continue
            fr_im = Image.open(os.path.join(out, "%s_%s.png" % (k, kind))).convert("RGB")
            fr_im = fr_im.resize((fw, fh), Image.LANCZOS)
            im.paste(fr_im, (x, y))
    im.save(os.path.join(out, "sheet.png"), optimize=True)


def main(argv):
    out = os.path.join(ROOT, "docs", "style_frames")
    only = list(STYLES)
    i = 0
    while i < len(argv):
        if argv[i] == "--out":
            out = argv[i + 1]
            i += 1
        elif argv[i] == "--only":
            only = argv[i + 1].split(",")
            i += 1
        i += 1
    os.makedirs(out, exist_ok=True)
    for k in only:
        st = STYLES[k]()
        save(st.render_game(), os.path.join(out, "%s_game.png" % k))
        save(st.render_win(), os.path.join(out, "%s_win.png" % k))
        print("стиль %s «%s»: готово" % (k, st.name))
    if all(os.path.exists(os.path.join(out, "%s_%s.png" % (k, t))) for k in STYLES for t in ("game", "win")):
        sheet(out, list(STYLES))
        print("лист сравнения: %s" % os.path.join(out, "sheet.png"))


if __name__ == "__main__":
    main(sys.argv[1:])
