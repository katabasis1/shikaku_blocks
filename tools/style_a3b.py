#!/usr/bin/env python3
"""Этап 12.3g/12.4: кадры A3 с палитрой B (выбрана 01.10) и иконками из нейросети (assets/icons/*.png).

Всё остальное — как в A3 (tools/style_a3.py). Иконки подставляются вместо icons_a2 подменой
style_a2.svg_icon: PNG кладётся в ту же геометрию, что и SVG (кнопка Ø104 в поле 128, центр (64, 60)),
и получает мягкую фиолетовую тень — такую игра будет добавлять всем кнопкам.
Звёзды в счёте и в победе — star.png с листа 3 (вместо звезды формы A), счётчик подсказок — badge.png.

    python3 tools/style_a3b.py           # -> docs/style_frames/A3B_*.png, sheet_a3b.png (≈20 с)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw  # noqa: E402

import style_frames as sf  # noqa: E402
import style_a2 as a2  # noqa: E402
import style_a3 as a3  # noqa: E402
from style_frames import P, SS, W, H, hexc, comp, shadow, text, font  # noqa: E402
from style_a2 import SHADE  # noqa: E402

PNG_DIR = os.path.join(sf.ROOT, "assets", "icons")
BTN_IN_PNG = 240 / 256       # диаметр кнопки в PNG (tools/cut_icons.py, BTN_D / N)
FIT_IN_PNG = 240 / 256       # большая сторона предмета в PNG (FIT / N)
SVG_NAME = {"btn_bulb": "hint", "star": "star", "ad": "ad", "hand": "hand"}

_png_cache = {}


def png(name, px):
    key = (name, int(px))
    if key not in _png_cache:
        im = Image.open(os.path.join(PNG_DIR, name + ".png")).convert("RGBA")
        _png_cache[key] = im.resize((int(px), int(px)), Image.LANCZOS)
    return _png_cache[key]


def png_as_svg(name, px):
    """Замена style_a2.svg_icon: PNG в геометрии icons_a2 (кнопка Ø104 в поле 128, центр (64, 60)) + тень."""
    n = SVG_NAME.get(name, name[4:] if name.startswith("btn_") else name)
    px = int(px)
    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    d = px * 104 / 128
    s = int(round(d / BTN_IN_PNG))
    ic = png(n, s)
    x, y = px * 64 / 128 - s / 2, px * 60 / 128 - s / 2
    shadow(out, ic.getchannel("A"), x, y, 0, d * 0.045, d * 0.04, SHADE, 0.38)
    comp(out, ic, x, y)
    return out


a2.svg_icon = png_as_svg     # A2/A3 берут иконки через эту функцию по имени модуля


class A3B(a3.A3):
    key = "A3B"
    name = "Мармелад 3, палитра B, иконки из нейросети"

    def __init__(self, pal=None):
        super().__init__(pal or a3.PAL_B)

    def star_a(self, img, cx, cy, R, rot=0.0):
        """Звезда с листа 3 вместо формы A, центр тот же. Ширина 1,75R (у многоугольника A 1,9R, но его
        лучи скруглены, и на глаз он меньше; при 1,9R звёзды победы налезают на поле)."""
        s = int(round(P(R) * 1.75 / FIT_IN_PNG))
        im = png("star", s)
        if rot:
            im = im.rotate(-rot, resample=Image.BICUBIC)
        X, Y = P(cx) - s / 2, P(cy - 0.095 * R) - s / 2
        q = R / 56
        shadow(img, im.getchannel("A"), X, Y, 0, P(8 * q), P(10 * q), hexc("#5A2A00"), 0.35)
        comp(img, im, X, Y)

    def button(self, img, cx, cy, icon, enabled=True, badge=None, d=100):
        super().button(img, cx, cy, icon, enabled, None, d)
        if badge:
            bd = 52                                    # как у A2: Ø44 + белое кольцо
            s = int(round(P(bd) / FIT_IN_PNG))
            b = png("badge", s)
            bx, by = cx + d * 0.36, cy - d * 0.36
            X, Y = P(bx) - s / 2, P(by) - s / 2
            shadow(img, b.getchannel("A"), X, Y, 0, P(3), P(3), SHADE, 0.35)
            comp(img, b, X, Y)
            text(img, bx, by - 1.5, badge, font(self.fonts, 25), (255, 255, 255), stroke=2.5,
                 stroke_fill=hexc("#A3163A"))


def sheet_a3b(out):
    """Сверху A3 и A3B (игра, победа), снизу A3B на компьютере 16:9."""
    if not all(os.path.exists(os.path.join(out, f + ".png")) for f in ("A3_game", "A3_win")):
        # С 07.10 кадры A3 не хранятся (история этапа 12). Их рисует tools/style_a3.py — ему нужны
        # docs/style_frames/icons_a2/*.svg (пересобирает tools/make_icons_a2.py). Сохранённый лист не трогаем.
        print("sheet_a3b.png не пересобран: нет A3_game.png / A3_win.png (рисует tools/style_a3.py)")
        return False
    fw, fh, gap, head, cap = 360, 640, 28, 124, 56
    sw = 4 * fw + 5 * gap
    dw = sw - 2 * gap
    dh = int(dw * 1080 / 1920)
    sh = head + cap + fh + gap + cap + dh + gap
    im = Image.new("RGB", (sw, sh), hexc("#1C1B22"))
    d = ImageDraw.Draw(im)
    fb, fr = a3._fonts()
    d.text((gap, 26), "Шикаку: Блоки — A3, палитра B и иконки из нейросети", font=fb, fill=(255, 255, 255))
    d.text((gap, 84), "Палитра B выбрана 01.10. Иконки — assets/icons/*.png (этап 12.3g), звёзды — с листа 3.",
           font=fr, fill=(170, 170, 185))
    items = [("A3_game", "A3 — было"), ("A3B_game", "A3 + B + иконки"), ("A3_win", "A3 — было"),
             ("A3B_win", "A3 + B + иконки")]
    for c, (f, name) in enumerate(items):
        x, y = gap + c * (fw + gap), head + cap
        d.text((x, y - cap + 8), name, font=fr, fill=(255, 255, 255))
        im.paste(Image.open(os.path.join(out, f + ".png")).convert("RGB").resize((fw, fh), Image.LANCZOS), (x, y))
    y = head + cap + fh + gap + cap
    d.text((gap, y - cap + 8), "A3 + B + иконки — компьютер, окно 1920×1080", font=fr, fill=(255, 255, 255))
    im.paste(Image.open(os.path.join(out, "A3B_desktop.png")).convert("RGB").resize((dw, dh), Image.LANCZOS),
             (gap, y))
    im.save(os.path.join(out, "sheet_a3b.png"), optimize=True)
    return True


def main(argv):
    out = os.path.join(sf.ROOT, "docs", "style_frames")
    if "--out" in argv:
        out = argv[argv.index("--out") + 1]
    os.makedirs(out, exist_ok=True)
    st = A3B()
    a3.save(st.render_game(a2.PORTRAIT), os.path.join(out, "A3B_game.png"), (W, H))
    a3.save(st.render_win(), os.path.join(out, "A3B_win.png"), (W, H))
    a3.save(st.render_game(a3.DESKTOP3), os.path.join(out, "A3B_desktop.png"), (1920, 1080))
    print("A3B_game.png A3B_win.png A3B_desktop.png" + (" sheet_a3b.png" if sheet_a3b(out) else ""))


if __name__ == "__main__":
    main(sys.argv[1:])
