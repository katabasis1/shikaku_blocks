#!/usr/bin/env python3
"""Этап 12.3d: стиль-кадры A2 — «Мармелад», доведённый до polished casual.

Пожелания пользователя (01.10): скруглённые формы, насыщенные цвета, мягкие тени, глянец,
polished casual game aesthetic, playful cartoon style. Исправлены 13 слабых мест A (PROGRESS.md, 12.3b):
глянец внутри формы, вдавленные точки вместо швов, мягкая цветная тень, один стиль цифр, утопленный
лавандовый лоток поля, призрак «цвет 35 % + белая рамка», числа-«гнёзда» вместо монет, плотная полка
лотка с крупными блоками, иконки из icons_a2 (12.3e), чёткий фон с виньеткой, палитра без фиолетового,
компактная карточка победы, шрифтовая пара Nunito 1000 (заголовки, цифры) + Nunito 800 (текст).

Общие примитивы (маски, градиенты, текст, уровень 20, геометрия поля) — из tools/style_frames.py.

    python3 tools/style_a2.py            # -> docs/style_frames/A2_game.png, A2_win.png, A2_desktop.png, sheet_a2.png
    python3 tools/style_a2.py --out DIR

A2_desktop.png — альбомная раскладка (docs/DESKTOP.md) в окне 1920×1080: логический экран 2276×1280.
Детерминирован: вся случайность — с фиксированным зерном.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageChops, ImageDraw, ImageFilter  # noqa: E402

import style_frames as sf  # noqa: E402
from style_frames import (P, SS, W, H, hexc, mix, lighten, darken, new_l, rr_mask, ellipse_mask,  # noqa: E402
                          mul_mask, scale_mask, paint, blurred, shadow, grad_v, grad_radial, text, font, comp,
                          Geo, star_points, round_shape, Jelly, LEVEL, LEVEL_N, PLACED, DRAGGED, MAGNET, LEFT_N)
from svgrender import svg_to_image  # noqa: E402

ROOT = sf.ROOT
CAND = os.path.join(ROOT, "docs", "fonts", "cand")
ICONS = os.path.join(ROOT, "docs", "style_frames", "icons_a2")
sf.FONT_DIRS.insert(0, CAND)

INK = hexc("#2E1678")        # обводка заголовков и знаков (как в icons_a2)
DEEP = hexc("#1E0B5C")       # тени текста
SHADE = hexc("#34168F")      # цветная (фиолетовая) тень блоков и кнопок


def shift(m, dx, dy):
    """Сдвиг маски без заворачивания краёв (ImageChops.offset заворачивает)."""
    out = new_l(m.width, m.height)
    out.paste(m, (int(round(dx)), int(round(dy))))
    return out


def inner_shadow(shape, dx, dy, radius, color, alpha):
    """Внутренняя тень формы: размытая инверсия, сдвинутая и обрезанная формой."""
    inv, pad = blurred(ImageChops.invert(shape), radius, pad=int(radius * 3) + 2)
    inv = inv.crop((pad - int(dx), pad - int(dy), pad - int(dx) + shape.width, pad - int(dy) + shape.height))
    return paint(scale_mask(mul_mask(inv, shape), alpha), color)


def twinkle(w, h, cx, cy, r):
    """Искорка: четырёхлучевая звёздочка."""
    m = new_l(w, h)
    k = r * 0.22
    pts = [(cx, cy - r), (cx + k, cy - k), (cx + r, cy), (cx + k, cy + k),
           (cx, cy + r), (cx - k, cy + k), (cx - r, cy), (cx - k, cy - k)]
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


_svg_cache = {}


def svg_icon(name, px):
    key = (name, int(px))
    if key not in _svg_cache:
        with open(os.path.join(ICONS, name + ".svg"), "rb") as f:
            _svg_cache[key] = svg_to_image(f.read(), int(px), int(px))
    return _svg_cache[key]


class A2(Jelly):
    key = "A2"
    name = "Мармелад 2.0"
    fonts = ["Nunito-ExtraBlack.ttf"]          # заголовки и цифры (вес 1000)
    tfonts = ["Nunito-ExtraBold.ttf"]          # текст интерфейса (вес 800)
    # палитра без фиолетового (п. 11): 8 — «жвачка», 9 — бирюза, 10 — маджента
    pal = {1: "#B4C3FF", 2: "#FF4D6D", 3: "#FF9A2E", 4: "#FFD23F", 5: "#2FD67B", 6: "#2EC8F7",
           7: "#3F7BFF", 8: "#FF6FB5", 9: "#14CDB8", 10: "#E552D6", 11: "#A6E22E", 12: "#1FB26B"}

    # ------------------------------------------------------------ фон (п. 10)
    def background(self, img, win=False, seed=7):
        w, h = img.size
        g = grad_v(w, h, [(0, hexc("#4A36E0")), (0.5, hexc("#6A42E4")), (1, hexc("#9A4CDB"))])
        img.alpha_composite(g)
        comp(img, grad_radial(w, h, w * 0.5, h * 0.2, max(w, h) * 0.75,
                              [(0, (255, 255, 255, 70 if win else 48)), (1, (255, 255, 255, 0))]), 0, 0)
        # чёткие скруглённые фигуры низкого контраста — «конфетти» из формы блоков
        rng = random.Random(seed)
        dw, dh = w / SS, h / SS
        n = int(dw * dh / 26000)
        for _ in range(n):
            kind = rng.random()
            s = rng.uniform(34, 96)
            S = P(s * 1.6)
            m = new_l(S, S)
            d = ImageDraw.Draw(m)
            c = S / 2
            if kind < 0.45:
                d.rounded_rectangle([c - P(s) / 2, c - P(s) / 2, c + P(s) / 2, c + P(s) / 2], radius=P(s * 0.3), fill=255)
            elif kind < 0.7:
                d.ellipse([c - P(s) * 0.4, c - P(s) * 0.4, c + P(s) * 0.4, c + P(s) * 0.4], fill=255)
            elif kind < 0.88:
                a, b = P(s) * 0.45, P(s) * 0.15
                d.rounded_rectangle([c - a, c - b, c + a, c + b], radius=b, fill=255)
                d.rounded_rectangle([c - b, c - a, c + b, c + a], radius=b, fill=255)
            else:
                d.polygon(star_points(c, c, P(s) * 0.5, P(s) * 0.25), fill=255)
                m = round_shape(m, P(3))
            m = m.rotate(rng.uniform(-25, 25), resample=Image.BICUBIC)
            a = rng.uniform(0.045, 0.085)
            comp(img, paint(scale_mask(m, a), (255, 255, 255)), P(rng.uniform(0, dw)) - S / 2, P(rng.uniform(0, dh)) - S / 2)
        # виньетка
        comp(img, grad_radial(w, h, w * 0.5, h * 0.45, math.hypot(w, h) * 0.62,
                              [(0, (20, 6, 70, 0)), (0.6, (20, 6, 70, 0)), (1, (20, 6, 70, 120))]), 0, 0)

    # ------------------------------------------------------------ материал «конфета» (п. 1–3)
    def _candy(self, lw, lh, box, r, depth, col, gloss=True, k=None, spark="l"):
        im = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
        x0, y0, x1, y1 = box
        k = k or min(x1 - x0, y1 - y0)
        fy1 = y1 - depth
        lip = rr_mask(lw, lh, (x0, y0 + depth, x1, y1), r)
        face = rr_mask(lw, lh, (x0, y0, x1, fy1), r)
        im.alpha_composite(paint(lip, grad_v(lw, lh, [(y0 / lh, darken(col, 0.34)), (y1 / lh, darken(col, 0.22))])))
        im.alpha_composite(paint(face, grad_v(lw, lh, [(y0 / lh, lighten(col, 0.34)),
                                                       ((y0 + 0.5 * (fy1 - y0)) / lh, col),
                                                       (fy1 / lh, darken(col, 0.07))])))
        # мягкий край: к кромке чуть темнее
        core = rr_mask(lw, lh, (x0 + k * 0.1, y0 + k * 0.1, x1 - k * 0.1, fy1 - k * 0.1), r * 0.8)
        core = core.filter(ImageFilter.GaussianBlur(k * 0.08))
        im.alpha_composite(paint(scale_mask(mul_mask(face, ImageChops.invert(core)), 0.32), darken(col, 0.14)))
        # отражённый свет снизу — «желе» светится изнутри
        band = rr_mask(lw, lh, (x0 + k * 0.16, fy1 - k * 0.2, x1 - k * 0.16, fy1 - k * 0.06), k * 0.07)
        band = band.filter(ImageFilter.GaussianBlur(k * 0.05))
        im.alpha_composite(paint(scale_mask(mul_mask(band, face), 0.6), lighten(col, 0.55)))
        if gloss:
            # широкий мягкий глянец на верхней половине
            sheen = rr_mask(lw, lh, (x0 + k * 0.08, y0 + k * 0.06, x1 - k * 0.08, y0 + (fy1 - y0) * 0.5), r * 0.8)
            sheen = sheen.filter(ImageFilter.GaussianBlur(k * 0.06))
            im.alpha_composite(paint(mul_mask(mul_mask(sheen, face), grad_v(lw, lh, [
                (y0 / lh, (0, 0, 0, 95)), ((y0 + (fy1 - y0) * 0.55) / lh, (0, 0, 0, 0))]).getchannel("A")),
                (255, 255, 255)))
            # изогнутый блик по верхнему краю: форма минус та же форма, сдвинутая вниз
            ins = k * 0.06
            inner = rr_mask(lw, lh, (x0 + ins, y0 + ins, x1 - ins, fy1 - ins), max(1, r - ins))
            t = min(k * 0.19, (fy1 - y0) * 0.32)
            cres = mul_mask(inner, ImageChops.invert(shift(inner, 0, t)))
            cres = cres.filter(ImageFilter.GaussianBlur(max(1.0, k * 0.012)))
            fade = grad_v(lw, lh, [(y0 / lh, (255, 255, 255, 245)), ((y0 + ins + t) / lh, (255, 255, 255, 190)),
                                   ((y0 + (fy1 - y0) * 0.55) / lh, (255, 255, 255, 30)), (1, (255, 255, 255, 0))])
            im.alpha_composite(paint(cres, fade))
            # искорка
            if spark:   # искорка в верхнем углу; в угол с цифрой не ставим
                sr = k * 0.065
                dx = max(r * 0.42, k * 0.1) + sr * 0.2
                sx = x0 + ins + dx if spark == "l" else x1 - ins - dx
                sy = y0 + ins + t + sr * 0.9
                im.alpha_composite(paint(twinkle(lw, lh, sx, sy, sr), (255, 255, 255, 240)))
                ex = sx + sr * 1.0 if spark == "l" else sx - sr * 1.5
                im.alpha_composite(paint(ellipse_mask(lw, lh, (ex, sy + sr * 0.7, ex + sr * 0.5, sy + sr * 1.2)),
                                         (255, 255, 255, 200)))
        return im

    def block_layer(self, wc, hc, cell, area, num=None, lifted=False):
        C = P(cell)
        M = int(C * 0.3)
        Wb, Hb = int(wc * C), int(hc * C)
        lw, lh = Wb + 2 * M, Hb + 2 * M
        col = self.color(area)
        g = C * 0.04
        depth = C * 0.075
        spark = "l"
        if num is not None and num[1] < 0.75:          # цифра в верхнем ряду
            if num[0] < 0.75:
                spark = "r" if wc > 1 else None
            elif num[0] > wc - 1.75:
                spark = "l" if wc > 1 else None
        im = self._candy(lw, lh, (M + g, M + g, M + Wb - g, M + Hb - g), C * 0.28, depth, col, k=C, spark=spark)
        # вдавленные точки на стыках клеток (п. 2): видно, из скольких клеток блок, но без «царапин»
        pts = []
        if wc > 1 and hc > 1:
            pts = [(i, j) for i in range(1, wc) for j in range(1, hc)]
        elif wc > 1:
            pts = [(i, 0.5) for i in range(1, wc)]
        elif hc > 1:
            pts = [(0.5, j) for j in range(1, hc)]
        dr = C * 0.05
        for (i, j) in pts:
            px, py = M + i * C, M + j * C - depth * (j / hc)
            hole = ellipse_mask(lw, lh, (px - dr, py - dr, px + dr, py + dr))
            im.alpha_composite(paint(scale_mask(shift(hole, 0, P(1.5)), 0.55), lighten(col, 0.55)))
            im.alpha_composite(paint(scale_mask(hole, 0.42), darken(col, 0.3)))
        if num is not None:
            cx = M + (num[0] + 0.5) * C
            cy = M + (num[1] + 0.5) * C - depth * 0.6
            self.digit(im, cx / SS, cy / SS, area, cell, col)
        return im, M

    def digit(self, im, cx, cy, n, cell, col, size=0.46):
        """Один стиль цифр (п. 4): белая, обводка — тёмный оттенок цвета блока, мягкая тень."""
        text(im, cx, cy, str(n), font(self.fonts, cell * size), (255, 255, 255), stroke=cell * 0.042,
             stroke_fill=darken(col, 0.45), shadow_off=(0, cell * 0.04), shadow_col=darken(col, 0.6),
             shadow_a=120, shadow_blur=cell * 0.01)

    def block_shadow(self, lifted):
        if lifted:
            return (10, 34, 20, hexc("#26107A"), 0.42)
        return (0, 7, 7, SHADE, 0.34)

    # ------------------------------------------------------------ поле (п. 5)
    def board(self, img, geo, pad=26, rim=15):
        depth, r = 12, 46
        x0, y0 = P(geo.x - pad), P(geo.y - pad)
        fw, fh = P(geo.w + 2 * pad), P(geo.h + 2 * pad)
        lw, lh = fw, fh + P(depth)
        lip = rr_mask(lw, lh, (0, P(depth), fw, lh), P(r))
        face = rr_mask(lw, lh, (0, 0, fw, fh), P(r))
        shadow(img, lip, x0, y0, 0, P(16), P(22), hexc("#220E6E"), 0.5)
        comp(img, paint(lip, grad_v(lw, lh, [(0.6, hexc("#B7A2F6")), (1, hexc("#9D84EE"))])), x0, y0)
        comp(img, paint(face, grad_v(lw, lh, [(0, (255, 255, 255)), (1, hexc("#EDE6FF"))])), x0, y0)
        # утопленный лавандовый лоток с внутренней тенью
        R, ins = P(r - rim * 0.7), P(rim)
        tray = rr_mask(lw, lh, (ins, ins, fw - ins, fh - ins), R)
        comp(img, paint(tray, grad_v(lw, lh, [(0, hexc("#B8A5F6")), (1, hexc("#C6B6F9"))])), x0, y0)
        comp(img, inner_shadow(tray, 0, P(7), P(8), hexc("#4A2FB8"), 0.62), x0, y0)
        # кромка бортика под лотком — светлая линия
        edge = mul_mask(shift(tray, 0, P(2)), ImageChops.invert(tray))
        comp(img, paint(scale_mask(edge, 0.9), (255, 255, 255)), x0, y0)
        # ячейки: скруглённые, чуть светлее лотка, слегка вдавлены
        C = P(geo.cell)
        g = P(4.5)
        for cy in range(geo.rows):
            for cx in range(geo.cols):
                X, Y = P(geo.x) + cx * C, P(geo.y) + cy * C
                well = rr_mask(C, C, (g, g, C - g, C - g), C * 0.24)
                comp(img, paint(well, grad_v(C, C, [(0, hexc("#DDD3FD")), (1, hexc("#E9E2FF"))])), X, Y)
                comp(img, inner_shadow(well, 0, P(3.5), P(3), hexc("#7A5EE0"), 0.5), X, Y)

    # ------------------------------------------------------------ число на пустой клетке — «гнездо» (п. 7)
    def badge(self, img, cx, cy, n, cell, ring=False):
        col = self.color(n)
        s = cell * 0.7
        L = P(s * 1.8)
        c = L / 2
        k = 1.08 if ring else 1.0
        S = P(s * k)
        pad = rr_mask(L, L, (c - S / 2, c - S / 2, c + S / 2, c + S / 2), S * 0.3)
        lift = P(4) if ring else 0
        X, Y = P(cx) - c, P(cy) - c - lift
        if ring:   # магнит: пульсирующий ореол цвета числа + белое кольцо
            halo, hp = blurred(pad, P(11))
            for _ in range(3):
                comp(img, paint(halo, col), X - hp, Y - hp)
            ringm = rr_mask(L, L, (c - S / 2 - P(7), c - S / 2 - P(7), c + S / 2 + P(7), c + S / 2 + P(7)), S * 0.36)
            inner = rr_mask(L, L, (c - S / 2 - P(2.5), c - S / 2 - P(2.5), c + S / 2 + P(2.5), c + S / 2 + P(2.5)), S * 0.32)
            comp(img, paint(mul_mask(ringm, ImageChops.invert(inner)), (255, 255, 255)), X, Y)
        comp(img, paint(pad, grad_v(L, L, [(0.2, lighten(col, 0.78)), (0.8, lighten(col, 0.6))])), X, Y)
        comp(img, inner_shadow(pad, 0, P(3), P(3), darken(col, 0.25), 0.55), X, Y)
        inner = rr_mask(L, L, (c - S / 2 + P(4), c - S / 2 + P(4), c + S / 2 - P(4), c + S / 2 - P(4)), S * 0.26)
        comp(img, paint(mul_mask(pad, ImageChops.invert(inner)), col), X, Y)   # цветной ободок
        text(img, cx, cy - lift / SS, str(n), font(self.fonts, cell * 0.4 * k), col, stroke=cell * 0.035,
             stroke_fill=darken(col, 0.42), shadow_off=(0, cell * 0.022), shadow_col=darken(col, 0.5), shadow_a=90)

    # ------------------------------------------------------------ призрак места (п. 6)
    def ghost(self, img, x, y, wc, hc, cell, area):
        col = self.color(area)
        C = P(cell)
        g = C * 0.04
        w, h = int(wc * C), int(hc * C)
        body = rr_mask(w, h, (g, g, w - g, h - g), C * 0.28)
        comp(img, paint(scale_mask(body, 0.35), col), P(x), P(y))
        inner = rr_mask(w, h, (g + P(5), g + P(5), w - g - P(5), h - g - P(5)), C * 0.24)
        comp(img, paint(mul_mask(body, ImageChops.invert(inner)), (255, 255, 255)), P(x), P(y))

    # ------------------------------------------------------------ кнопки — icons_a2 (п. 9)
    BTN = {"pause": "btn_pause", "restart": "btn_restart", "undo": "btn_undo", "bulb": "btn_bulb"}

    def button(self, img, cx, cy, icon, enabled=True, badge=None, d=100):
        px = P(d * 128 / 104)          # в SVG кнопка Ø104 в поле 128, центр (64, 60)
        im = svg_icon(self.BTN.get(icon, icon), px)
        comp(img, im, P(cx) - px * 64 / 128, P(cy) - px * 60 / 128)
        if badge:
            bd = P(44)
            bm = P(10)
            bl = bd + 2 * bm
            ring = ellipse_mask(bl, bl, (bm - P(3), bm - P(3), bm + bd + P(3), bm + bd + P(3)))
            b = Image.new("RGBA", (bl, bl), (0, 0, 0, 0))
            b.alpha_composite(paint(ring, (255, 255, 255)))
            b.alpha_composite(self._candy(bl, bl, (bm, bm, bm + bd, bm + bd), bd / 2, P(4), hexc("#FF4D6D"), k=bd))
            text(b, bl / 2 / SS, (bl / 2 - P(2.5)) / SS, badge, font(self.fonts, 25), (255, 255, 255),
                 stroke=2.5, stroke_fill=hexc("#A3163A"))
            X, Y = P(cx + d * 0.36) - bl / 2, P(cy - d * 0.36) - bl / 2
            shadow(img, b.getchannel("A"), X, Y, 0, P(3), P(3), SHADE, 0.35)
            comp(img, b, X, Y)

    # ------------------------------------------------------------ текст (п. 13)
    def title(self, img, cx, cy, s, size=50):
        text(img, cx, cy, s, font(self.fonts, size), (255, 255, 255), stroke=size * 0.13, stroke_fill=INK,
             shadow_off=(0, size * 0.12), shadow_col=DEEP, shadow_a=170, shadow_blur=1.5)

    def score(self, img, cx, cy, value, size=38):
        f = font(self.fonts, size)
        tw = ImageDraw.Draw(new_l(1, 1)).textlength(value, font=f) / SS
        st = size * 1.45
        sx = cx - (tw + st * 0.9) / 2
        im = svg_icon("star", P(st))
        comp(img, im, P(sx + st * 0.3) - im.width / 2, P(cy) - im.height * 0.53)
        text(img, sx + st * 0.9 + tw / 2, cy, value, f, hexc("#FFE45C"), stroke=size * 0.13, stroke_fill=INK,
             shadow_off=(0, size * 0.1), shadow_col=DEEP, shadow_a=150, shadow_blur=1)

    def label(self, img, cx, cy, s, size=27):
        f = font(self.tfonts, size)
        tw = ImageDraw.Draw(new_l(1, 1)).textlength(s, font=f) / SS
        w, h = tw + 48, size * 1.9
        m = rr_mask(P(w), P(h), (0, 0, P(w), P(h)), P(h / 2))
        X, Y = P(cx - w / 2), P(cy - h / 2)
        comp(img, paint(m, (24, 8, 96, 70)), X, Y)
        comp(img, inner_shadow(m, 0, P(2), P(3), (16, 4, 70), 0.35), X, Y)
        text(img, cx, cy - 1, s, f, (255, 255, 255), shadow_off=(0, 2.5), shadow_col=DEEP, shadow_a=140)

    # ------------------------------------------------------------ лоток — плотная полка (п. 8)
    def shelf(self, img, box, slots, empty):
        x0, y0, x1, y1 = box
        lw, lh = P(x1 - x0), P(y1 - y0)
        body = rr_mask(lw, lh, (0, 0, lw, lh), P(40))
        X, Y = P(x0), P(y0)
        comp(img, paint(body, grad_v(lw, lh, [(0, (34, 14, 120, 150)), (1, (52, 22, 150, 140))])), X, Y)
        comp(img, inner_shadow(body, 0, P(7), P(9), (14, 4, 60), 0.6), X, Y)
        edge = mul_mask(body, ImageChops.invert(shift(body, 0, -P(2.5))))
        comp(img, paint(scale_mask(edge, 0.45), (255, 255, 255)), X, Y)   # светлая кромка снизу
        for k, (sx, sy, sw, sh) in enumerate(slots):
            w, h = P(sw), P(sh)
            well = rr_mask(w, h, (0, 0, w, h), P(30))
            a = 38 if k not in empty else 22
            comp(img, paint(well, (160, 130, 255, a)), P(sx), P(sy))
            comp(img, inner_shadow(well, 0, P(4), P(5), (14, 4, 60), 0.45), P(sx), P(sy))
            if k in empty:   # пустое гнездо: пунктирный контур
                d = ImageDraw.Draw(dm := new_l(w, h))
                d.rounded_rectangle([P(10), P(10), w - P(10), h - P(10)], radius=P(22), outline=255, width=P(3))
                dash = new_l(w, h)
                dd = ImageDraw.Draw(dash)
                step = P(22)
                for i in range(0, w + h, step):
                    dd.line([i, 0, i - h, h], fill=255, width=P(9))
                comp(img, paint(scale_mask(mul_mask(dm, dash), 0.22), (255, 255, 255)), P(sx), P(sy))

    # ------------------------------------------------------------ победа (п. 12)
    def star(self, img, cx, cy, R, rot=0.0):
        px = P(R * 128 / 54)             # в star.svg лучи R=54 в поле 128, центр (64, 68)
        im = svg_icon("star", px)
        if rot:
            im = im.rotate(-rot, resample=Image.BICUBIC, center=(px * 64 / 128, px * 68 / 128))
        comp(img, im, P(cx) - px * 64 / 128, P(cy) - px * 68 / 128)

    def win_card(self, img, x0, y0, x1, y1):
        lw, lh = P(x1 - x0), P(y1 - y0 + 14)
        r = P(46)
        lip = rr_mask(lw, lh, (0, P(14), lw, lh), r)
        face = rr_mask(lw, lh, (0, 0, lw, lh - P(14)), r)
        X, Y = P(x0), P(y0)
        shadow(img, lip, X, Y, 0, P(18), P(26), DEEP, 0.55)
        comp(img, paint(lip, hexc("#C4B0FF")), X, Y)
        comp(img, paint(face, grad_v(lw, lh, [(0, (255, 255, 255)), (1, hexc("#F2ECFF"))])), X, Y)
        # цветная шапка
        hh = P(104)
        head = mul_mask(face, rr_mask(lw, lh, (0, 0, lw, hh), 0))
        comp(img, paint(head, grad_v(lw, lh, [(0, hexc("#FFC247")), (hh / lh, hexc("#FF7B3A"))])), X, Y)
        gl = mul_mask(head, rr_mask(lw, lh, (P(14), P(8), lw - P(14), P(40)), P(16)))
        comp(img, paint(gl, grad_v(lw, lh, [(0, (255, 255, 255, 150)), (P(40) / lh, (255, 255, 255, 0))])), X, Y)
        comp(img, paint(mul_mask(face, rr_mask(lw, lh, (0, hh, lw, hh + P(5)), 0)), hexc("#E0602A")), X, Y)

    def render_win(self):
        img = Image.new("RGBA", (P(W), P(H)), (0, 0, 0, 255))
        self.background(img, win=True)
        cols, rows, rects = LEVEL
        geo = Geo(cols, rows, 80, 360, 405)
        sf.rays(img, 360, 405, 20, 760, (255, 255, 255), 0.09, rot=6)
        m = ellipse_mask(P(W), P(H), (P(30), P(70), P(690), P(740))).filter(ImageFilter.GaussianBlur(P(70)))
        comp(img, paint(scale_mask(m, 0.4), (255, 225, 255)), 0, 0)
        self.board(img, geo, pad=20, rim=11)
        for (x, y, w, h, nx, ny) in rects:
            X, Y = geo.cell_xy(x, y)
            self.place_block(img, X, Y, w, h, 80, w * h, num=(nx - x, ny - y))
        self.title(img, 360, 94, "УРОВЕНЬ %d ПРОЙДЕН!" % LEVEL_N, size=46)
        x0, y0, x1, y1 = 104, 786, 616, 1214
        self.win_card(img, x0, y0, x1, y1)
        self.star(img, 212, y0 - 4, 50, -14)
        self.star(img, 508, y0 - 4, 50, 14)
        self.star(img, 360, y0 - 26, 68, 0)
        text(img, 360, y0 + 66, "НОВЫЙ РЕКОРД!", font(self.fonts, 34), (255, 255, 255), stroke=4.5,
             stroke_fill=hexc("#B8420F"), shadow_off=(0, 3), shadow_col=hexc("#8A2E05"), shadow_a=110)
        self.score_card(img, 360, y0 + 158, "+120")
        text(img, 360, y0 + 212, "Всего очков: 2 460", font(self.tfonts, 27), hexc("#8573C4"))
        self.pill_button(img, 360, y0 + 300, 380, 110, "ДАЛЕЕ", hexc("#2FCF78"), hexc("#12733F"))
        f = font(self.tfonts, 26)
        ic = svg_icon("btn_restart", P(64))
        tx, s = sf.replay_link(img, y0 + 392, f, None, lambda x, y: None)
        comp(img, ic.crop((P(8), P(4), P(56), P(52))).resize((P(34), P(34)), Image.LANCZOS),
             P(tx - (ImageDraw.Draw(new_l(1, 1)).textlength(s, font=f) / SS) / 2 - 44), P(y0 + 392 - 17))
        text(img, tx, y0 + 392, s, f, hexc("#7A68B5"))
        self.confetti(img, 11, 60, (0, 16, W, 770), [(56, 48, 664, 140), (84, 136, 636, 684), (140, 660, 580, 800)])
        return img

    def score_card(self, img, cx, cy, value):
        f = font(self.fonts, 48)
        tw = ImageDraw.Draw(new_l(1, 1)).textlength(value, font=f) / SS
        st = 58
        sx = cx - (tw + st * 0.95) / 2
        im = svg_icon("star", P(st))
        comp(img, im, P(sx + st * 0.3) - im.width / 2, P(cy) - im.height * 0.53)
        text(img, sx + st * 0.95 + tw / 2, cy, value, f, hexc("#FFC21A"), stroke=5.5, stroke_fill=hexc("#A85400"),
             shadow_off=(0, 4), shadow_col=hexc("#7A3A00"), shadow_a=80)

    def pill_button(self, img, cx, cy, bw, bh, s, col, ink, size=46):
        m = P(12)
        b = self._candy(P(bw) + 2 * m, P(bh) + 2 * m, (m, m, m + P(bw), m + P(bh)), P(bh) / 2, P(11), col, k=P(bh))
        text(b, (P(bw) / 2 + m) / SS, (P(bh) / 2 + m - P(6)) / SS, s, font(self.fonts, size), (255, 255, 255),
             stroke=size * 0.12, stroke_fill=ink, shadow_off=(0, 3), shadow_col=ink, shadow_a=120)
        X, Y = P(cx) - b.width / 2, P(cy) - b.height / 2
        shadow(img, b.getchannel("A"), X, Y, 0, P(9), P(10), darken(col, 0.6), 0.35)
        comp(img, b, X, Y)

    def confetti(self, img, seed, n, area, avoid):
        """Глянцевые ленточки, завитки, звёздочки и шарики; часть — размыта (глубина)."""
        rng = random.Random(seed)
        cols = [self.color(a) for a in (2, 3, 4, 5, 6, 8, 9)] + [(255, 255, 255)]
        for _ in range(n):
            col = cols[rng.randrange(len(cols))]
            kind = rng.random()
            s = rng.uniform(0.85, 1.3)
            L = P(60 * s)
            im = Image.new("RGBA", (L, L), (0, 0, 0, 0))
            c = L / 2
            if kind < 0.4:        # ленточка с бликом
                w, h = P(11 * s), P(28 * s)
                m = rr_mask(L, L, (c - w / 2, c - h / 2, c + w / 2, c + h / 2), w * 0.4)
                im.alpha_composite(paint(m, grad_v(L, L, [((c - h / 2) / L, lighten(col, 0.35)),
                                                          ((c + h / 2) / L, darken(col, 0.15))])))
                hl = rr_mask(L, L, (c - w * 0.28, c - h * 0.38, c - w * 0.02, c + h * 0.1), w * 0.2)
                im.alpha_composite(paint(scale_mask(hl, 0.8), (255, 255, 255)))
            elif kind < 0.6:      # завиток
                m = new_l(L, L)
                R = P(14 * s)
                ImageDraw.Draw(m).arc([c - R, c - R, c + R, c + R], 200, 340, fill=255, width=P(7 * s))
                ImageDraw.Draw(m).arc([c - R * 0.2, c - R * 1.1 + R * 1.9, c + R * 1.8, c + R * 0.9 + R * 1.9],
                                      20, 160, fill=0, width=1)
                im.alpha_composite(paint(m, col))
                im.alpha_composite(paint(scale_mask(shift(m, 0, -P(2)), 0.45), lighten(col, 0.6)))
            elif kind < 0.82:     # звёздочка-мармелад
                m = new_l(L, L)
                ImageDraw.Draw(m).polygon(star_points(c, c, P(14 * s), P(7 * s)), fill=255)
                m = round_shape(m, P(1.6))
                im.alpha_composite(paint(m, grad_v(L, L, [(0.3, lighten(col, 0.4)), (0.7, col)])))
                im.alpha_composite(paint(scale_mask(ellipse_mask(L, L, (c - P(5 * s), c - P(6 * s), c - P(1 * s),
                                                                         c - P(3 * s))), 0.9), (255, 255, 255)))
            else:                 # шарик
                R = P(8 * s)
                m = ellipse_mask(L, L, (c - R, c - R, c + R, c + R))
                im.alpha_composite(paint(m, grad_v(L, L, [((c - R) / L, lighten(col, 0.4)), ((c + R) / L, darken(col, 0.1))])))
                im.alpha_composite(paint(ellipse_mask(L, L, (c - R * 0.55, c - R * 0.6, c - R * 0.05, c - R * 0.25)),
                                         (255, 255, 255, 220)))
            im = im.rotate(rng.uniform(0, 360), resample=Image.BICUBIC)
            if rng.random() < 0.25:
                im = im.filter(ImageFilter.GaussianBlur(P(rng.uniform(1.5, 3))))
            px, py = sf.free_point(rng, area, avoid)
            comp(img, im, P(px) - L / 2, P(py) - L / 2)

    # ------------------------------------------------------------ экран игры (обе раскладки)
    def cursor(self, img, x, y, k=1.6):
        pts = [(0, 0), (0, 26), (6.5, 20.5), (11, 30.5), (15.8, 28.6), (11.4, 18.8), (19.8, 18.8)]
        S = P(40 * k)
        m = new_l(S, S)
        o = P(4)
        ImageDraw.Draw(m).polygon([(o + P(px * k), o + P(py * k)) for px, py in pts], fill=255)
        ol = m.filter(ImageFilter.MaxFilter(2 * (P(1.6 * k) // 2) + 1))
        shadow(img, ol, P(x) - o, P(y) - o, P(2), P(4), P(3), (10, 0, 40), 0.4)
        comp(img, paint(ol, (20, 10, 40)), P(x) - o, P(y) - o)
        comp(img, paint(m, (255, 255, 255)), P(x) - o, P(y) - o)

    def render_game(self, L=None):
        L = L or PORTRAIT
        w, h = L["size"]
        img = Image.new("RGBA", (P(w), P(h)), (0, 0, 0, 255))
        self.background(img, seed=L.get("seed", 7))
        if L.get("decor"):
            self.decor(img, L["decor"])
        cols, rows, rects = LEVEL
        cell = L["cell"]
        geo = Geo(cols, rows, cell, *L["board_c"])
        self.board(img, geo)
        for i, (x, y, bw, bh, nx, ny) in enumerate(rects):
            if i not in PLACED:
                cx, cy = geo.cell_xy(nx + 0.5, ny + 0.5)
                self.badge(img, cx, cy, bw * bh, cell, ring=(i in MAGNET))
        for i in PLACED:
            x, y, bw, bh, nx, ny = rects[i]
            X, Y = geo.cell_xy(x, y)
            self.place_block(img, X, Y, bw, bh, cell, bw * bh, num=(nx - x, ny - y))
        x, y, bw, bh, nx, ny = rects[DRAGGED]
        DX, DY = geo.cell_xy(x, y)
        self.ghost(img, DX, DY, bw, bh, cell, bw * bh)
        d = L.get("btn", 100)
        self.button(img, *L["pause"], "pause", d=d)
        self.button(img, *L["restart"], "restart", d=d)
        self.title(img, *L["title"], "УРОВЕНЬ %d" % LEVEL_N, size=L.get("title_size", 50))
        self.score(img, *L["score"], "2 340", size=L.get("score_size", 38))
        self.button(img, *L["undo"], "undo", d=d)
        self.label(img, *L["left"], "Осталось блоков: %d" % LEFT_N, size=L.get("label_size", 27))
        self.button(img, *L["hint"], "bulb", badge="3", d=d)
        empty = [k for k, t in enumerate(L["tray"]) if t is None]
        self.shelf(img, L["shelf"], L["slots"], empty)
        tc = L["tray_cell"]
        for k, (sx, sy, sw, sh) in enumerate(L["slots"]):
            t = L["tray"][k]
            if t is None:
                continue
            idx, tw, th = t
            bx, by = sx + sw / 2 - tw * tc / 2, sy + sh / 2 - th * tc / 2
            self.place_block(img, bx, by, tw, th, tc, tw * th, num=((tw - 1) / 2, (th - 1) / 2))
        ox, oy = L["drag_off"]
        self.place_block(img, DX + ox, DY + oy, bw, bh, cell, bw * bh, num=((bw - 1) / 2, (bh - 1) / 2),
                         lifted=True, scale=1.08, tilt=L.get("tilt", -5))
        if L.get("cursor"):
            self.cursor(img, DX + ox + bw * cell * 0.62, DY + oy + bh * cell * 0.6)
        if L.get("caption"):
            text(img, *L["caption"], font(self.tfonts, 24), (255, 255, 255, 190), shadow_off=(0, 2),
                 shadow_col=DEEP, shadow_a=110)
        return img

    def decor(self, img, items):
        """Крупные глянцевые блоки по бокам широкого экрана, без цифр: (x, y, клеток по ш., по в., цвет по площади,
        клетка, наклон, размытие, приглушение к фону)."""
        for (x, y, wc, hc, area, cell, tilt, blur, dim) in items:
            im, M = self.block_layer(wc, hc, cell, area)
            a = im.getchannel("A")    # непрозрачный, но приглушён к цвету фона — не «грязнит» просвечиванием
            im = Image.blend(im.convert("RGB"), Image.new("RGB", im.size, hexc("#6A44E2")), dim).convert("RGBA")
            im.putalpha(a)
            im = im.rotate(tilt, resample=Image.BICUBIC, expand=True)
            if blur:
                im = im.filter(ImageFilter.GaussianBlur(P(blur)))
            X, Y = P(x) - im.width / 2, P(y) - im.height / 2
            shadow(img, im.getchannel("A"), X, Y, 0, P(14), P(16), hexc("#1A0860"), 0.35)
            comp(img, im, X, Y)


# ---------------------------------------------------------------- раскладки
# Портрет 720×1280 — места из scenes/game/game.tscn (как у A, чтобы сравнение было честным);
# лоток крупнее: клетка 62 вместо 50 (Tray.BLOCK_SCALE ≈ 0.6).
PORTRAIT = dict(
    size=(720, 1280), board_c=(360, 520), cell=104,
    pause=(72, 84), restart=(648, 84), title=(360, 62), score=(360, 116),
    undo=(76, 938), left=(360, 938), hint=(644, 938),
    shelf=(12, 1000, 708, 1256), slots=[(24 + i * 228, 1012, 216, 232) for i in range(3)],
    tray=[None, (5, 1, 3), (6, 2, 2)], tray_cell=62, drag_off=(-70, 128))

# Альбом: окно 1920×1080 -> логический экран 2276×1280 (высота 1280, aspect = expand).
# Поле слева (клетка 164, в 1,6 раза крупнее портрета на мониторе), справа столбик: подпись, 3 гнезда, кнопки.
DESK_W = 2276
DESKTOP = dict(
    size=(DESK_W, 1280), board_c=(896, 684), cell=164, btn=110,
    pause=(436, 86), restart=(1840, 86), title=(1138, 66), score=(1138, 124), title_size=56, score_size=40,
    left=(1686, 226), label_size=29,
    shelf=(1476, 268, 1896, 1066), slots=[(1492, 284 + i * 258, 388, 246) for i in range(3)],
    undo=(1590, 1150), hint=(1782, 1150),
    tray=[None, (5, 1, 3), (6, 2, 2)], tray_cell=76, drag_off=(196, 92), tilt=4, cursor=True,
    caption=(1686, 1240, "ПКМ или R — повернуть блок"), seed=12,
    # декор — холодные цвета палитры: тёплые (жёлтый, оранжевый) при приглушении к фиолетовому «грязнятся»
    decor=[(150, 250, 2, 2, 7, 120, 14, 3, 0.35), (215, 760, 1, 3, 8, 110, -10, 1.2, 0.25),
           (110, 1150, 2, 1, 9, 130, 8, 3.5, 0.38), (2140, 330, 2, 3, 6, 100, -12, 1.2, 0.25),
           (2170, 900, 2, 2, 10, 120, 10, 3, 0.35), (2040, 1220, 3, 1, 7, 100, -6, 3.5, 0.38)],
)


def save(img, path, size):
    img.convert("RGB").resize(size, Image.LANCZOS).save(path, optimize=True)


def sheet_a2(out):
    """Лист «A и A2» (стрелки нет в подмножестве Nunito): сверху четыре портретных кадра, снизу — альбомный 16:9."""
    fw, fh, gap, head, cap = 360, 640, 28, 124, 56
    sw = 4 * fw + 5 * gap
    dw = sw - 2 * gap
    dh = int(dw * 1080 / 1920)
    sh = head + cap + fh + gap + cap + dh + gap
    im = Image.new("RGB", (sw, sh), hexc("#1C1B22"))
    d = ImageDraw.Draw(im)
    fb = sf.ImageFont.truetype(os.path.join(CAND, "Nunito-ExtraBlack.ttf"), 46)
    fr = sf.ImageFont.truetype(os.path.join(CAND, "Nunito-ExtraBold.ttf"), 26)
    d.text((gap, 26), "Шикаку: Блоки — стиль A2 рядом с A (этап 12.3)", font=fb, fill=(255, 255, 255))
    d.text((gap, 84), "Уровень %d, поле 6×6. Шрифты: Nunito 1000 (заголовки, цифры) + Nunito 800 (текст)." % LEVEL_N,
           font=fr, fill=(170, 170, 185))
    items = [("A_game", "A — было"), ("A2_game", "A2 — игра"), ("A_win", "A — было"), ("A2_win", "A2 — победа")]
    for c, (f, name) in enumerate(items):
        x, y = gap + c * (fw + gap), head + cap
        d.text((x, y - cap + 8), name, font=fr, fill=(255, 255, 255))
        fr_im = Image.open(os.path.join(out, f + ".png")).convert("RGB").resize((fw, fh), Image.LANCZOS)
        im.paste(fr_im, (x, y))
    y = head + cap + fh + gap + cap
    d.text((gap, y - cap + 8), "A2 — компьютер, окно 1920×1080: альбомная раскладка (docs/DESKTOP.md)", font=fr,
           fill=(255, 255, 255))
    im.paste(Image.open(os.path.join(out, "A2_desktop.png")).convert("RGB").resize((dw, dh), Image.LANCZOS), (gap, y))
    im.save(os.path.join(out, "sheet_a2.png"), optimize=True)


def main(argv):
    out = os.path.join(ROOT, "docs", "style_frames")
    only = {"game", "win", "desktop"}
    i = 0
    while i < len(argv):
        if argv[i] == "--out":
            out = argv[i + 1]
            i += 1
        elif argv[i] == "--only":
            only = set(argv[i + 1].split(","))
            i += 1
        i += 1
    os.makedirs(out, exist_ok=True)
    st = A2()
    if "game" in only:
        save(st.render_game(PORTRAIT), os.path.join(out, "A2_game.png"), (W, H))
        print("A2_game.png")
    if "win" in only:
        save(st.render_win(), os.path.join(out, "A2_win.png"), (W, H))
        print("A2_win.png")
    if "desktop" in only:
        save(st.render_game(DESKTOP), os.path.join(out, "A2_desktop.png"), (1920, 1080))
        print("A2_desktop.png")
    need = ["A_game", "A_win", "A2_game", "A2_win", "A2_desktop"]
    if all(os.path.exists(os.path.join(out, n + ".png")) for n in need):
        sheet_a2(out)
        print("sheet_a2.png")


if __name__ == "__main__":
    main(sys.argv[1:])
