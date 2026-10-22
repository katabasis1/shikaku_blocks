#!/usr/bin/env python3
"""Этап 12.3h: стиль-кадры A3 — правки пользователя к A2 (01.10 01:58).

- изогнутый блик по верхнему краю тише (был слишком ярким), искорок нет нигде;
- между клетками блока снова швы, как в A, но едва заметные (вместо вдавленных точек);
- одно скругление на всё: ячейка, блок, призрак — радиус RC·клетки при одинаковом зазоре GC;
  вложенные формы (гнездо в ячейке, лоток поля, бортик, гнёзда полки) — концентрически (r + отступ);
- звёзды — форма A (пухлая, скруглённая, без обводки) и в счёте, и в победе;
- конфетти — как в A: скруглённые полоски и кружки;
- компьютер: без блоков-декора по бокам; чтобы игра занимала ≥ 70 % кадра, поле на всю высоту,
  заголовок и счёт — в столбик справа, над лотком;
- палитры: A2 и вариант B «для всех» (один розовый вместо трёх) — лист palette.png.

Тень, фон, шрифт, карточка победы — как в A2. Иконки кнопок — пока icons_a2 (заменятся листами
из нейросети, docs/icons/PROMPTS.md).

    python3 tools/style_a3.py            # -> docs/style_frames/A3_*.png, sheet_a3.png, palette.png
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageChops, ImageDraw, ImageFilter  # noqa: E402

import style_frames as sf  # noqa: E402
import style_a2 as a2  # noqa: E402
from style_frames import (P, SS, W, H, hexc, lighten, darken, new_l, rr_mask, ellipse_mask, mul_mask,  # noqa: E402
                          scale_mask, paint, grad_v, text, font, comp, shadow, star_points, round_shape, Geo,
                          LEVEL, LEVEL_N)
from style_a2 import A2, inner_shadow, shift, INK, DEEP  # noqa: E402

RC = 0.24      # радиус скругления ячейки и блока, доля клетки
GC = 0.045     # зазор от края клетки до ячейки / блока / призрака, доля клетки

PAL_A2 = dict(A2.pal)
# B «для всех»: чистые цвета как у классических блок-пазлов, розовый один — на редком 12 (3 % блоков).
# 1, 7 и 11 в 500 уровнях не встречаются (1×7 и 1×11 не генерируются, 1 — не блок).
PAL_B = {1: "#B4C3FF", 2: "#FF4B3E", 3: "#FF9A2E", 4: "#FFD23F", 5: "#2FD67B", 6: "#2EC8F7",
         7: "#E552D6", 8: "#3F7BFF", 9: "#14CDB8", 10: "#A6E22E", 11: "#1FB26B", 12: "#FF5FA8"}
USED = [2, 3, 4, 5, 6, 8, 9, 10, 12]
SHARE = {2: 17.9, 3: 20.9, 4: 25.2, 5: 4.5, 6: 15.8, 8: 8.1, 9: 1.9, 10: 3.0, 12: 2.9}   # % всех блоков


class A3(A2):
    key = "A3"
    name = "Мармелад 3"

    def __init__(self, pal=None):
        if pal:
            self.pal = pal

    # ------------------------------------------------------------ материал: тише блик, без искорки
    def _candy(self, lw, lh, box, r, depth, col, gloss=True, k=None, spark=None):
        im = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
        x0, y0, x1, y1 = box
        k = k or min(x1 - x0, y1 - y0)
        fy1 = y1 - depth
        lip = rr_mask(lw, lh, (x0, y0 + depth, x1, y1), r)
        face = rr_mask(lw, lh, (x0, y0, x1, fy1), r)
        im.alpha_composite(paint(lip, grad_v(lw, lh, [(y0 / lh, darken(col, 0.34)), (y1 / lh, darken(col, 0.22))])))
        im.alpha_composite(paint(face, grad_v(lw, lh, [(y0 / lh, lighten(col, 0.3)),
                                                       ((y0 + 0.5 * (fy1 - y0)) / lh, col),
                                                       (fy1 / lh, darken(col, 0.07))])))
        core = rr_mask(lw, lh, (x0 + k * 0.1, y0 + k * 0.1, x1 - k * 0.1, fy1 - k * 0.1), r * 0.8)
        core = core.filter(ImageFilter.GaussianBlur(k * 0.08))
        im.alpha_composite(paint(scale_mask(mul_mask(face, ImageChops.invert(core)), 0.32), darken(col, 0.14)))
        band = rr_mask(lw, lh, (x0 + k * 0.16, fy1 - k * 0.2, x1 - k * 0.16, fy1 - k * 0.06), k * 0.07)
        band = band.filter(ImageFilter.GaussianBlur(k * 0.05))
        im.alpha_composite(paint(scale_mask(mul_mask(band, face), 0.5), lighten(col, 0.55)))
        if gloss:
            sheen = rr_mask(lw, lh, (x0 + k * 0.08, y0 + k * 0.06, x1 - k * 0.08, y0 + (fy1 - y0) * 0.5), r * 0.8)
            sheen = sheen.filter(ImageFilter.GaussianBlur(k * 0.06))
            im.alpha_composite(paint(mul_mask(mul_mask(sheen, face), grad_v(lw, lh, [
                (y0 / lh, (0, 0, 0, 80)), ((y0 + (fy1 - y0) * 0.55) / lh, (0, 0, 0, 0))]).getchannel("A")),
                (255, 255, 255)))
            # изогнутый блик: тоньше и примерно вдвое тише, чем в A2
            ins = k * 0.06
            inner = rr_mask(lw, lh, (x0 + ins, y0 + ins, x1 - ins, fy1 - ins), max(1, r - ins))
            t = min(k * 0.15, (fy1 - y0) * 0.28)
            cres = mul_mask(inner, ImageChops.invert(shift(inner, 0, t)))
            cres = cres.filter(ImageFilter.GaussianBlur(max(1.0, k * 0.014)))
            fade = grad_v(lw, lh, [(y0 / lh, (255, 255, 255, 135)), ((y0 + ins + t) / lh, (255, 255, 255, 95)),
                                   ((y0 + (fy1 - y0) * 0.5) / lh, (255, 255, 255, 12)), (1, (255, 255, 255, 0))])
            im.alpha_composite(paint(cres, fade))
        return im

    # ------------------------------------------------------------ блок: общий радиус, едва заметные швы
    def block_layer(self, wc, hc, cell, area, num=None, lifted=False):
        C = P(cell)
        M = int(C * 0.3)
        Wb, Hb = int(wc * C), int(hc * C)
        lw, lh = Wb + 2 * M, Hb + 2 * M
        col = self.color(area)
        g = C * GC
        depth = C * 0.075
        im = self._candy(lw, lh, (M + g, M + g, M + Wb - g, M + Hb - g), C * RC, depth, col, k=C)
        d = ImageDraw.Draw(seam := new_l(lw, lh))
        wdt = max(2, int(C * 0.02))
        for i in range(1, wc):
            X = M + i * C
            d.line([X, M + C * 0.24, X, M + Hb - depth - C * 0.22], fill=255, width=wdt)
        for j in range(1, hc):
            Y = M + j * C - depth * (j / hc)
            d.line([M + C * 0.24, Y, M + Wb - C * 0.24, Y], fill=255, width=wdt)
        if num is not None:
            cx = M + (num[0] + 0.5) * C
            cy = M + (num[1] + 0.5) * C - depth * 0.6
            # вокруг цифры шов не идёт: у блока 2×2 швы иначе пересекают число
            hole = ellipse_mask(lw, lh, (cx - C * 0.34, cy - C * 0.34, cx + C * 0.34, cy + C * 0.34))
            seam = mul_mask(seam, ImageChops.invert(hole.filter(ImageFilter.GaussianBlur(C * 0.03))))
        seam = seam.filter(ImageFilter.GaussianBlur(C * 0.006))
        im.alpha_composite(paint(scale_mask(seam, 0.13), darken(col, 0.35)))
        im.alpha_composite(paint(scale_mask(shift(seam, 0, max(2, C * 0.016)), 0.12), (255, 255, 255)))
        if num is not None:
            self.digit(im, cx / SS, cy / SS, area, cell, col)
        return im, M

    # ------------------------------------------------------------ поле: концентрические скругления
    def board(self, img, geo, pad=26, rim=15):
        depth = 12
        C = P(geo.cell)
        g = C * GC
        rw = C * RC                                   # ячейка
        rt = rw + P(pad - rim) + g                    # лоток поля: от края лотка до ячейки (pad − rim + g)
        rb = rt + P(rim)                              # бортик
        x0, y0 = P(geo.x - pad), P(geo.y - pad)
        fw, fh = P(geo.w + 2 * pad), P(geo.h + 2 * pad)
        lw, lh = fw, fh + P(depth)
        lip = rr_mask(lw, lh, (0, P(depth), fw, lh), rb)
        face = rr_mask(lw, lh, (0, 0, fw, fh), rb)
        shadow(img, lip, x0, y0, 0, P(16), P(22), hexc("#220E6E"), 0.5)
        comp(img, paint(lip, grad_v(lw, lh, [(0.6, hexc("#B7A2F6")), (1, hexc("#9D84EE"))])), x0, y0)
        comp(img, paint(face, grad_v(lw, lh, [(0, (255, 255, 255)), (1, hexc("#EDE6FF"))])), x0, y0)
        ins = P(rim)
        tray = rr_mask(lw, lh, (ins, ins, fw - ins, fh - ins), rt)
        comp(img, paint(tray, grad_v(lw, lh, [(0, hexc("#B8A5F6")), (1, hexc("#C6B6F9"))])), x0, y0)
        comp(img, inner_shadow(tray, 0, P(7), P(8), hexc("#4A2FB8"), 0.62), x0, y0)
        edge = mul_mask(shift(tray, 0, P(2)), ImageChops.invert(tray))
        comp(img, paint(scale_mask(edge, 0.9), (255, 255, 255)), x0, y0)
        for cy in range(geo.rows):
            for cx in range(geo.cols):
                X, Y = P(geo.x) + cx * C, P(geo.y) + cy * C
                well = rr_mask(C, C, (g, g, C - g, C - g), rw)
                comp(img, paint(well, grad_v(C, C, [(0, hexc("#DDD3FD")), (1, hexc("#E9E2FF"))])), X, Y)
                comp(img, inner_shadow(well, 0, P(3.5), P(3), hexc("#7A5EE0"), 0.5), X, Y)

    # ------------------------------------------------------------ число-«гнездо»: концентрично ячейке
    def badge(self, img, cx, cy, n, cell, ring=False):
        col = self.color(n)
        C = P(cell)
        s = cell * 0.7
        L = P(s * 1.8)
        c = L / 2
        k = 1.08 if ring else 1.0
        S = P(s * k)
        inset = (C * (1 - 2 * GC) - S) / 2
        rp = max(C * RC - inset, S * 0.14)
        pad = rr_mask(L, L, (c - S / 2, c - S / 2, c + S / 2, c + S / 2), rp)
        lift = P(4) if ring else 0
        X, Y = P(cx) - c, P(cy) - c - lift
        if ring:
            halo, hp = sf.blurred(pad, P(11))
            for _ in range(3):
                comp(img, paint(halo, col), X - hp, Y - hp)
            o, i = P(7), P(2.5)
            ringm = rr_mask(L, L, (c - S / 2 - o, c - S / 2 - o, c + S / 2 + o, c + S / 2 + o), rp + o)
            inner = rr_mask(L, L, (c - S / 2 - i, c - S / 2 - i, c + S / 2 + i, c + S / 2 + i), rp + i)
            comp(img, paint(mul_mask(ringm, ImageChops.invert(inner)), (255, 255, 255)), X, Y)
        comp(img, paint(pad, grad_v(L, L, [(0.2, lighten(col, 0.78)), (0.8, lighten(col, 0.6))])), X, Y)
        comp(img, inner_shadow(pad, 0, P(3), P(3), darken(col, 0.25), 0.55), X, Y)
        b = P(4)
        inner = rr_mask(L, L, (c - S / 2 + b, c - S / 2 + b, c + S / 2 - b, c + S / 2 - b), max(1, rp - b))
        comp(img, paint(mul_mask(pad, ImageChops.invert(inner)), col), X, Y)
        text(img, cx, cy - lift / SS, str(n), font(self.fonts, cell * 0.4 * k), col, stroke=cell * 0.035,
             stroke_fill=darken(col, 0.42), shadow_off=(0, cell * 0.022), shadow_col=darken(col, 0.5), shadow_a=90)

    def ghost(self, img, x, y, wc, hc, cell, area):
        col = self.color(area)
        C = P(cell)
        g = C * GC
        w, h = int(wc * C), int(hc * C)
        body = rr_mask(w, h, (g, g, w - g, h - g), C * RC)
        comp(img, paint(scale_mask(body, 0.35), col), P(x), P(y))
        b = P(5)
        inner = rr_mask(w, h, (g + b, g + b, w - g - b, h - g - b), C * RC - b)
        comp(img, paint(mul_mask(body, ImageChops.invert(inner)), (255, 255, 255)), P(x), P(y))

    # ------------------------------------------------------------ полка лотка: гнёзда концентричны полке
    def shelf(self, img, box, slots, empty):
        x0, y0, x1, y1 = box
        lw, lh = P(x1 - x0), P(y1 - y0)
        rs = P(30)
        inset = P(min(s[0] for s in slots) - x0)
        body = rr_mask(lw, lh, (0, 0, lw, lh), rs + inset)
        X, Y = P(x0), P(y0)
        comp(img, paint(body, grad_v(lw, lh, [(0, (34, 14, 120, 150)), (1, (52, 22, 150, 140))])), X, Y)
        comp(img, inner_shadow(body, 0, P(7), P(9), (14, 4, 60), 0.6), X, Y)
        edge = mul_mask(body, ImageChops.invert(shift(body, 0, -P(2.5))))
        comp(img, paint(scale_mask(edge, 0.45), (255, 255, 255)), X, Y)
        for k, (sx, sy, sw, sh) in enumerate(slots):
            w, h = P(sw), P(sh)
            well = rr_mask(w, h, (0, 0, w, h), rs)
            a = 38 if k not in empty else 22
            comp(img, paint(well, (160, 130, 255, a)), P(sx), P(sy))
            comp(img, inner_shadow(well, 0, P(4), P(5), (14, 4, 60), 0.45), P(sx), P(sy))
            if k in empty:
                dm = new_l(w, h)
                ImageDraw.Draw(dm).rounded_rectangle([P(10), P(10), w - P(10), h - P(10)], radius=rs - P(10),
                                                     outline=255, width=P(3))
                dash = new_l(w, h)
                dd = ImageDraw.Draw(dash)
                for i in range(0, w + h, P(22)):
                    dd.line([i, 0, i - h, h], fill=255, width=P(9))
                comp(img, paint(scale_mask(mul_mask(dm, dash), 0.22), (255, 255, 255)), P(sx), P(sy))

    # ------------------------------------------------------------ звезда — форма A
    def star_a(self, img, cx, cy, R, rot=0.0):
        S = int(P(R) * 2.6)
        m = new_l(S, S)
        ImageDraw.Draw(m).polygon(star_points(S / 2, S / 2, P(R), P(R) * 0.5, rot=-90 + rot), fill=255)
        m = round_shape(m, P(R) * 0.12)
        lip = shift(m, 0, P(R * 0.12))
        im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        im.alpha_composite(paint(lip, hexc("#E08A00")))
        im.alpha_composite(paint(m, grad_v(S, S, [(0.2, hexc("#FFF08A")), (0.75, hexc("#FFC21A"))])))
        hl = new_l(S, S)
        ImageDraw.Draw(hl).ellipse([S * 0.36, S * 0.26, S * 0.5, S * 0.36], fill=255)
        im.alpha_composite(paint(scale_mask(mul_mask(hl, m), 0.9), (255, 255, 255)))
        q = R / 56
        shadow(img, im.getchannel("A"), P(cx) - S / 2, P(cy) - S / 2, 0, P(8 * q), P(10 * q), hexc("#5A2A00"), 0.35)
        comp(img, im, P(cx) - S / 2, P(cy) - S / 2)

    def star(self, img, cx, cy, R, rot=0.0):
        # звёзды победы: форма A, чуть выше, чтобы меньше заходить на оранжевую шапку
        self.star_a(img, cx, cy - 16, R * 1.08, rot)

    def _score_row(self, img, cx, cy, value, f, st, gap, fill, stroke, stroke_fill, sh_col, sh_a, sh_off):
        tw = ImageDraw.Draw(new_l(1, 1)).textlength(value, font=f) / SS
        sx = cx - (tw + st + gap) / 2
        self.star_a(img, sx + st / 2, cy - st * 0.04, st * 0.5)
        text(img, sx + st + gap + tw / 2, cy, value, f, fill, stroke=stroke, stroke_fill=stroke_fill,
             shadow_off=sh_off, shadow_col=sh_col, shadow_a=sh_a, shadow_blur=1)

    def score(self, img, cx, cy, value, size=38):
        self._score_row(img, cx, cy, value, font(self.fonts, size), size * 1.2, size * 0.25, hexc("#FFE45C"),
                        size * 0.13, INK, DEEP, 150, (0, size * 0.1))

    def score_card(self, img, cx, cy, value):
        self._score_row(img, cx, cy, value, font(self.fonts, 48), 54, 12, hexc("#FFC21A"), 5.5, hexc("#A85400"),
                        hexc("#7A3A00"), 80, (0, 4))

    # ------------------------------------------------------------ конфетти — как в A
    def confetti(self, img, seed, n, area, avoid):
        cols = [self.color(a) for a in (2, 3, 4, 5, 6, 8, 9)] + [(255, 255, 255)]
        sf.confetti(img, cols, seed, 70, area, avoid=avoid)


# ---------------------------------------------------------------- компьютер без декора
# Окно 1920×1080 -> логический экран 2276×1280. Поле на всю высоту (клетка 186, на мониторе ≈157 px),
# столбик 560 справа: пауза | заголовок и счёт | заново; подпись; полка из 3 гнёзд; отмена, подсказка.
# Поле + столбик = 242…2034 из 2276 — 79 % ширины (в A2 было 67 %).
DESKTOP3 = dict(
    size=(2276, 1280), board_c=(826, 640), cell=186, btn=100,
    pause=(1524, 98), restart=(1984, 98), title=(1754, 78), score=(1754, 138), title_size=48, score_size=38,
    left=(1754, 226), label_size=29,
    shelf=(1474, 262, 2034, 1082), slots=[(1488, 276 + i * 268, 532, 256) for i in range(3)],
    undo=(1640, 1164), hint=(1868, 1164),
    tray=[None, (5, 1, 3), (6, 2, 2)], tray_cell=78, drag_off=(-125, 229), tilt=-4, cursor=True,
    caption=(1754, 1242, "ПКМ или R — повернуть блок"), seed=12)


def save(img, path, size):
    img.convert("RGB").resize(size, Image.LANCZOS).save(path, optimize=True)


def _fonts():
    fb = sf.ImageFont.truetype(os.path.join(a2.CAND, "Nunito-ExtraBlack.ttf"), 46)
    fr = sf.ImageFont.truetype(os.path.join(a2.CAND, "Nunito-ExtraBold.ttf"), 26)
    return fb, fr


def sheet_a3(out):
    """Сверху A2 и A3 (игра, победа), снизу A3 на компьютере 16:9."""
    fw, fh, gap, head, cap = 360, 640, 28, 124, 56
    sw = 4 * fw + 5 * gap
    dw = sw - 2 * gap
    dh = int(dw * 1080 / 1920)
    sh = head + cap + fh + gap + cap + dh + gap
    im = Image.new("RGB", (sw, sh), hexc("#1C1B22"))
    d = ImageDraw.Draw(im)
    fb, fr = _fonts()
    d.text((gap, 26), "Шикаку: Блоки — стиль A3 рядом с A2 (этап 12.3h)", font=fb, fill=(255, 255, 255))
    d.text((gap, 84), "Тише блик, без искорок, едва заметные швы, одно скругление, звёзды и конфетти из A. "
                      "Иконки — временные.", font=fr, fill=(170, 170, 185))
    items = [("A2_game", "A2 — было"), ("A3_game", "A3 — игра"), ("A2_win", "A2 — было"), ("A3_win", "A3 — победа")]
    for c, (f, name) in enumerate(items):
        x, y = gap + c * (fw + gap), head + cap
        d.text((x, y - cap + 8), name, font=fr, fill=(255, 255, 255))
        im.paste(Image.open(os.path.join(out, f + ".png")).convert("RGB").resize((fw, fh), Image.LANCZOS), (x, y))
    y = head + cap + fh + gap + cap
    d.text((gap, y - cap + 8), "A3 — компьютер, окно 1920×1080: без декора по бокам, поле на всю высоту, "
                               "игра — 79 % ширины", font=fr, fill=(255, 255, 255))
    im.paste(Image.open(os.path.join(out, "A3_desktop.png")).convert("RGB").resize((dw, dh), Image.LANCZOS), (gap, y))
    im.save(os.path.join(out, "sheet_a3.png"), optimize=True)


def palette_sheet(out):
    """Все цвета, которые бывают в уровнях: A2 и вариант B; снизу — кадр игры в каждой палитре."""
    fb, fr = _fonts()
    fs = sf.ImageFont.truetype(os.path.join(a2.CAND, "Nunito-ExtraBold.ttf"), 22)
    cell, gap = 116, 30
    lab = 250
    n = len(USED)
    row_w = n * cell + (n - 1) * gap + 2 * 36
    sw = lab + row_w + 28 * 2
    row_h = cell + 70
    fw, fh = 520, 924
    head = 150
    sh = head + 2 * (row_h + 24) + 60 + 44 + fh + 30
    im = Image.new("RGB", (sw, sh), hexc("#1C1B22"))
    d = ImageDraw.Draw(im)
    d.text((28, 24), "Шикаку: Блоки — все цвета блоков: A2 и вариант B", font=fb, fill=(255, 255, 255))
    d.text((28, 82), "В 500 уровнях бывают только блоки 2, 3, 4, 5, 6, 8, 9, 10 и 12. Под плиткой — доля "
                     "среди всех блоков.", font=fr, fill=(170, 170, 185))
    d.text((28, 114), "B: красный вместо малинового, синий вместо розового (8), лайм вместо мадженты (10), "
                      "один розовый — на редком 12.", font=fr, fill=(170, 170, 185))
    y = head
    for name, pal in (("A2 — сейчас", PAL_A2), ("B — для всех", PAL_B)):
        st = A3(pal)
        strip = Image.new("RGBA", (P(row_w), P(row_h)), (0, 0, 0, 255))
        st.background(strip, seed=3)
        for i, a in enumerate(USED):
            x = 36 + i * (cell + gap)
            st.place_block(strip, x, 14, 1, 1, cell, a, num=(0, 0))
        strip = strip.convert("RGB").resize((row_w, row_h), Image.LANCZOS)
        ds = ImageDraw.Draw(strip)
        for i, a in enumerate(USED):
            x = 36 + i * (cell + gap) + cell / 2
            s = ("%.1f %%" % SHARE[a]).replace(".", ",")
            tw = ds.textlength(s, font=fs)
            ds.text((x - tw / 2, 14 + cell + 16), s, font=fs, fill=(255, 255, 255))
        d.text((28, y + row_h / 2 - 16), name, font=fr, fill=(255, 255, 255))
        im.paste(strip, (28 + lab, y))
        y += row_h + 24
    y += 60
    total = 2 * fw + gap
    x0 = (sw - total) // 2
    for k, (name, f) in enumerate((("Кадр A3, палитра A2", "A3_game"), ("Кадр A3, палитра B", "A3_game_b"))):
        x = x0 + k * (fw + gap)
        d.text((x, y), name, font=fr, fill=(255, 255, 255))
        im.paste(Image.open(os.path.join(out, f + ".png")).convert("RGB").resize((fw, fh), Image.LANCZOS), (x, y + 44))
    im.save(os.path.join(out, "palette.png"), optimize=True)


def main(argv):
    out = os.path.join(sf.ROOT, "docs", "style_frames")
    if "--out" in argv:
        out = argv[argv.index("--out") + 1]
    os.makedirs(out, exist_ok=True)
    st = A3()
    save(st.render_game(a2.PORTRAIT), os.path.join(out, "A3_game.png"), (W, H))
    save(st.render_win(), os.path.join(out, "A3_win.png"), (W, H))
    save(st.render_game(DESKTOP3), os.path.join(out, "A3_desktop.png"), (1920, 1080))
    save(A3(PAL_B).render_game(a2.PORTRAIT), os.path.join(out, "A3_game_b.png"), (W, H))
    sheet_a3(out)
    palette_sheet(out)
    print("A3_game.png A3_win.png A3_desktop.png A3_game_b.png sheet_a3.png palette.png")


if __name__ == "__main__":
    main(sys.argv[1:])
