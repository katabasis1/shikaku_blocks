#!/usr/bin/env python3
"""Этап 12.3g: лист проверки иконок docs/icons/icons_check.png — A2 (SVG) и новые PNG на фоне игры.

Ряды: A2 96 px | новые 96 px | новые 48 px | «в деле»: счётчик подсказок, значок рекламы 48 px на
кнопке подсказки, счёт, звёзды на карточке победы, рука 120 px с точкой нажатия (pivot), светлая панель.
Тень под новыми иконками рисует этот лист (в PNG её нет — её добавит игра, одинаковую у всех).

    python3 tools/icons_sheet.py          # ≈3 с, нужен assets/icons/*.png (tools/cut_icons.py)
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from svgrender import svg_to_image  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, "assets", "icons")
A2 = os.path.join(ROOT, "docs", "style_frames", "icons_a2")
CAND = os.path.join(ROOT, "docs", "fonts", "cand")
OUT = os.path.join(ROOT, "docs", "icons", "icons_check.png")

BG = (0x6A, 0x42, 0xE4)
BG2 = (0x8A, 0x5C, 0xF6)
SHADE = (0x34, 0x16, 0x8F)
DARK = (0x1C, 0x1B, 0x22)
ORDER = ["pause", "restart", "undo", "hint", "home", "settings", "music_on", "music_off", "sound_on",
         "sound_off", "vibration_on", "vibration_off", "star", "star_empty", "ad", "hand"]
HAND_PIVOT = (36, 2)     # кончик пальца в TextureRect 120×120 (tools/cut_icons.py)
A2_NAME = {"hint": "btn_bulb", "star": "star", "ad": "ad", "hand": "hand", "star_empty": None}


def fnt(bold, size):
    return ImageFont.truetype(os.path.join(CAND, "Nunito-ExtraBlack.ttf" if bold else "Nunito-ExtraBold.ttf"), size)


def png(name, px):
    return Image.open(os.path.join(ICONS, name + ".png")).convert("RGBA").resize((px, px), Image.LANCZOS)


def a2_svg(name, px):
    n = A2_NAME.get(name, "btn_" + name)
    if not n:
        return None
    with open(os.path.join(A2, n + ".svg"), "rb") as f:
        return svg_to_image(f.read(), px, px)


def with_shadow(icon, dy=None, blur=None, alpha=0.38):
    """Иконка + мягкая фиолетовая тень вниз (как будет в игре)."""
    px = icon.width
    dy = px * 0.045 if dy is None else dy
    blur = px * 0.04 if blur is None else blur
    pad = int(px * 0.2)
    out = Image.new("RGBA", (px + 2 * pad, px + 2 * pad), (0, 0, 0, 0))
    a = icon.getchannel("A").point(lambda v: int(v * alpha))
    sh = Image.new("RGBA", out.size, SHADE + (0,))
    m = Image.new("L", out.size, 0)
    m.paste(a, (pad, pad + int(round(dy))))
    sh.putalpha(m.filter(ImageFilter.GaussianBlur(blur)))
    out.alpha_composite(sh)
    out.alpha_composite(icon, (pad, pad))
    return out, pad


def put(dst, icon, cx, cy, shadow=True):
    if shadow:
        im, pad = with_shadow(icon)
        dst.alpha_composite(im, (int(cx - icon.width / 2 - pad), int(cy - icon.height / 2 - pad)))
    else:
        dst.alpha_composite(icon, (int(cx - icon.width / 2), int(cy - icon.height / 2)))


def ctext(d, cx, cy, s, f, fill, stroke=0, sfill=None):
    d.text((cx, cy), s, font=f, fill=fill, anchor="mm", stroke_width=stroke, stroke_fill=sfill)


def main():
    lab, step, top = 340, 124, 140
    rows = [("A2 — отклонены", 96, "a2"), ("Новые — кнопка 96 px", 96, "new"), ("Новые — 48 px", 48, "new")]
    rh = 150
    W = lab + len(ORDER) * step + 40
    live_h = 330
    H = top + len(rows) * rh + 70 + live_h + 40
    img = Image.new("RGBA", (W, H), DARK + (255,))
    d = ImageDraw.Draw(img)
    d.text((30, 26), "Шикаку: Блоки — иконки из нейросети (этап 12.3g)", font=fnt(True, 44), fill=(255, 255, 255))
    d.text((30, 84), "assets/icons/*.png 256×256, нарезаны tools/cut_icons.py. Фон — цвет игры #6A42E4. "
                     "Тень под новыми рисует игра (в PNG её нет).", font=fnt(False, 24), fill=(170, 170, 185))
    fs = fnt(False, 17)
    for i, n in enumerate(ORDER):
        ctext(d, lab + i * step + step / 2, top - 12, n, fs, (170, 170, 185))
    y = top
    for title, px, kind in rows:
        d.rounded_rectangle((lab - 14, y, W - 26, y + rh - 16), 22, fill=BG + (255,))
        d.text((30, y + rh / 2 - 24), title, font=fnt(False, 24), fill=(255, 255, 255))
        for i, n in enumerate(ORDER):
            cx, cy = lab + i * step + step / 2, y + (rh - 16) / 2
            if kind == "a2":
                ic = a2_svg(n, int(px * 128 / 104) if n.startswith(("pa", "re", "un", "hi", "ho", "se", "mu", "so", "vi")) else px)
                if ic is None:
                    ctext(d, cx, cy, "—", fnt(True, 30), (200, 190, 240))
                else:
                    put(img, ic, cx, cy, shadow=False)
            else:
                put(img, png(n, px), cx, cy)
        y += rh
    # ------------------------------------------------------------ в деле
    y += 54
    d.text((30, y - 40), "В деле", font=fnt(True, 30), fill=(255, 255, 255))
    d.rounded_rectangle((30, y, W - 26, y + live_h), 26, fill=BG + (255,))
    cy = y + 150
    cap = fnt(False, 20)
    x = 120
    # 1) подсказка со счётчиком
    put(img, png("hint", 96), x, cy)
    b = png("badge", 40)
    put(img, b, x + 35, cy - 35, shadow=False)
    ctext(d, x + 35, cy - 37, "3", fnt(True, 22), (255, 255, 255), 2, (0xA3, 0x16, 0x3A))
    ctext(d, x, cy + 100, "подсказки: 3", cap, (255, 255, 255))
    # 2) подсказка за рекламу: значок 48 px
    x += 210
    put(img, png("hint", 96), x, cy)
    put(img, png("ad", 48), x + 34, cy - 34)
    ctext(d, x, cy + 100, "реклама, значок 48", cap, (255, 255, 255))
    # 3) счёт
    x += 230
    put(img, png("star", 46), x - 52, cy)
    d.text((x - 24, cy), "2 340", font=fnt(True, 40), fill=(0xFF, 0xE4, 0x5C), anchor="lm", stroke_width=5,
           stroke_fill=(0x2E, 0x16, 0x78))
    ctext(d, x + 10, cy + 100, "счёт", cap, (255, 255, 255))
    # 4) карточка победы: 2 звезды из 3 над оранжевой шапкой
    x += 260
    d.rounded_rectangle((x - 150, cy - 40, x + 150, cy + 80), 28, fill=(255, 255, 255, 255))
    d.rounded_rectangle((x - 150, cy - 40, x + 150, cy + 10), 28, fill=(0xFF, 0x9A, 0x2E, 255))
    d.rectangle((x - 150, cy - 10, x + 150, cy + 10), fill=(0xFF, 0x9A, 0x2E, 255))
    for k, (n, s, dy) in enumerate((("star", 80, 8), ("star", 100, 0), ("star_empty", 80, 8))):
        put(img, png(n, s), x + (k - 1) * 96, cy - 48 + dy)
    ctext(d, x, cy + 45, "+120", fnt(True, 34), (0xFF, 0xC2, 0x1A), 4, (0xA8, 0x54, 0x00))
    ctext(d, x, cy + 100, "победа: 2 из 3", cap, (255, 255, 255))
    # 5) рука на клетке, точка нажатия
    x += 280
    cell = 92
    d.rounded_rectangle((x - cell / 2, cy - 90, x + cell / 2, cy - 90 + cell), 22, fill=(0xE9, 0xE2, 0xFF, 255))
    tx, ty = x, cy - 90 + cell / 2              # сюда «нажимает» рука
    hand = png("hand", 120)
    px_, py_ = HAND_PIVOT
    im, pad = with_shadow(hand)
    img.alpha_composite(im, (int(tx - px_ - pad), int(ty - py_ - pad)))
    d.ellipse((tx - 5, ty - 5, tx + 5, ty + 5), outline=(255, 60, 60), width=3)
    ctext(d, x, cy + 100, "рука 120, pivot (36, 2)", cap, (255, 255, 255))
    # 7) на светлом (панель настроек)
    x += 260
    d.rounded_rectangle((x - 110, cy - 80, x + 230, cy + 70), 28, fill=(0xF4, 0xF0, 0xFF, 255))
    for k, n in enumerate(("music_on", "sound_off", "vibration_on")):
        put(img, png(n, 84), x - 40 + k * 106, cy - 5)
    ctext(d, x + 60, cy + 100, "на светлой панели", cap, (255, 255, 255))
    img.convert("RGB").save(OUT, optimize=True)
    print(os.path.relpath(OUT, ROOT), img.size)


if __name__ == "__main__":
    main()
