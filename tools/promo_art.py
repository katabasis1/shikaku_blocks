#!/usr/bin/env python3
"""Иконка и обложка страницы игры (этап 16.5b) — из того же, что в игре: фон (background.gdshader) с лучами победы
(win_rays), поле (board / nest), блоки (block.gdshader), рука обучения (hand.png), искры, шрифт Nunito 1000 и стиль
заголовка HudHeader. Рисует window_preview / shader_preview («как в Godot»), без Godot.

Сюжет (11.10, по обложкам лидеров каталога «Головоломки»: крупно сам геймплей, рука показывает действие, яркий фон
с лучами): поле почти собрано, красная двойка поднята над своим гнездом, рука её тащит. Обложка — поле 6×4
(COVER_RECTS, пять цветов: 6, 2, 9, 4, 3), иконка — поле 3×3 (ICON_RECTS: 3, 4, 2) — читается и в 64 px.

  python3 tools/promo_art.py           всё: иконка и обложки ru / en / tr и без текста
  python3 tools/promo_art.py --icon    только иконка

Файлы (docs/promo/, в сборку не попадают — docs/.gdignore):
  icon_512.png                иконка 512×512, без текста
  cover_800x470_{ru,en,tr}.png обложка 800×470: поле слева, название справа в 1–3 строки (тексты — TITLES,
                              строка про числа — жёлтая, ACCENT)
  cover_800x470_notext.png    обложка без текста: поле по центру, крупнее
  SOURCES.txt                 отпечаток (sha1) источников ART_SOURCES и самих картинок — по нему promo_check
                              узнаёт, что картинки устарели (поменялись блок, поле, фон, рука, шрифт, TITLES…)
Размеры — как в консоли Яндекс Игр (11.10: иконка PNG 512×512, обложка PNG 800×470).
Рисуется крупнее (иконка 660, обложка 1200×705) и уменьшается LANCZOS — края блоков и текста ровнее.
"""
import hashlib
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_preview as sp      # noqa: E402
import window_preview as wp      # noqa: E402

OUT = os.path.join(sp.ROOT, "docs", "promo")
ICON = 512
COVER = (800, 470)
# Название на обложке: строки на язык (1–3) — слова поля «Название» из docs/PROMO.md прописными, по порядку
# (турецкие правила: i → İ, ı → I, как SEVİYE в игре); сверяет promo_check. Название решено 11.10.
TITLES = {"ru": ("РАССТАВЬ", "БЛОКИ", "ПО ЧИСЛАМ"), "en": ("BLOCKS", "BY NUMBERS"),
          "tr": ("BLOKLARI", "SAYILARLA", "YERLEŞTİR")}
# Строка названия про числа — жёлтая (цвет блока 4), остальные белые.
ACCENT = {"ru": 2, "en": 1, "tr": 1}
# Из чего рисуются картинки (кроме рисовалок tools/shader_preview.py и window_preview.py — их правят часто и не
# только ради промо). Поменялся файл — promo_check скажет «картинки устарели». Добавили источник — впишите сюда.
ART_SOURCES = [
    "tools/promo_art.py", "scenes/game/block.gd", "scenes/game/board.gd", "scenes/game/hud_header.gd",
    "scenes/ui/background.gd", "scenes/ui/tutorial_hand.tscn", "scripts/palette.gd",
    "shaders/background.gdshader", "shaders/block.gdshader", "shaders/board.gdshader", "shaders/nest.gdshader",
    "shaders/win_rays.gdshader", "shaders/sdf.gdshaderinc",
    "assets/icons/sparkle.png", "assets/icons/hand.png", "assets/fonts/nunito_black.ttf",
]
SOURCES_TXT = "SOURCES.txt"

# Поля: (x, y, w, h, x числа, y числа) в клетках. Площадь = число, цвет — по площади (palette.gd).
COVER_RECTS = [(0, 0, 2, 3, 0, 1), (0, 3, 2, 1, 1, 3), (2, 0, 3, 3, 3, 1), (5, 0, 1, 4, 5, 2), (2, 3, 3, 1, 3, 3)]
ICON_RECTS = [(0, 0, 1, 3, 0, 1), (1, 0, 2, 2, 2, 0), (1, 2, 2, 1, 2, 2)]
LIFTED = {"cover": 1, "icon": 2}           # какой блок поднят (красная двойка)
HAND_PNG = os.path.join(sp.ROOT, "assets", "icons", "hand.png")
HAND_TIP = (75.0, 6.0)                     # кончик пальца в hand.png (256×256)
SPARK_PNG = os.path.join(sp.ROOT, "assets", "icons", "sparkle.png")


def board_layer(cols, rows, rects, placed, cell_px):
    """Поле на прозрачном слое: рамка и клетки (board), блоки placed, гнёзда остальных (nest + число), как
    shader_preview.draw_board_partial. -> (слой PIL RGBA, (ox, oy) — клетка 0,0 на слое)."""
    s = cell_px / sp.CELL
    px = 1.0 / s
    M = int(sp.BD["FRAME_MARGIN"] + sp.BD["PAD"] + 10)
    L = wp.Layer(int(cols * cell_px + 2 * M), int(rows * cell_px + 2 * M + sp.BD["FRAME_DEPTH"]))
    ox, oy = M, M
    m = (sp.BD["FRAME_MARGIN"] + sp.BD["PAD"]) * px
    fw, fh = cols * sp.CELL + 2 * m, rows * sp.CELL + 2 * m + sp.BD["FRAME_DEPTH"] * px
    sp.draw_rect(L, "board", ox - m * s, oy - m * s, fw, fh, s, (1, 1, 1, 1), {
        "frame_size": (fw, fh), "grid": (float(cols), float(rows)), "px": px, "margin": sp.BD["FRAME_MARGIN"],
        "pad": sp.BD["PAD"], "rim": sp.BD["RIM"], "lip": sp.BD["FRAME_DEPTH"]})
    for i, (rx, ry, rw, rh, nx, ny) in enumerate(rects):
        if i in placed:
            continue
        area, bx, by = rw * rh, nx * sp.CELL, ny * sp.CELL
        col = sp.color_for(area)
        sp.draw_rect(L, "nest", ox + (bx - 48) * s, oy + (by - 48) * s, sp.CELL + 96, sp.CELL + 96, s, col,
                     {"px": px, "ring": 0.0, "margin": 48.0})
        sp.draw_digit(L, str(area), ox + (bx + 50) * s, oy + (by + 50) * s, 40 * s, col, sp.darkened(col, 0.42),
                      sp.CL["DIGIT_OUTLINE"] * s, sp.darkened(col, 0.5)[:3] + (0.35,), (0, 2 * s))
    for i in sorted(placed, key=lambda j: (rects[j][1], rects[j][0])):
        rx, ry, rw, rh, nx, ny = rects[i]
        sp.draw_block(L, ox + rx * cell_px, oy + ry * cell_px, s, rw, rh, rw * rh, (nx - rx, ny - ry), False)
    return L.pil(), (ox, oy)


def block_layer(rw, rh, num, cell_px):
    """Поднятый блок (как при перетаскивании: LIFT_SCALE, высокая тень) на прозрачном слое."""
    s = cell_px / sp.CELL * sp.B["LIFT_SCALE"]
    pad = int(sp.B["MARGIN_LIFTED"] * s * 1.2 + 30)
    L = wp.Layer(int(rw * sp.CELL * s) + 2 * pad, int(rh * sp.CELL * s) + 2 * pad)
    sp.draw_block(L, pad, pad, s, rw, rh, rw * rh, num, True)
    return L.pil()


def over(cv, im, x, y):
    cv.over(int(round(x)), int(round(y)), np.asarray(im).astype(float) / 255)


def paste_rot(cv, im, cx, cy, deg):
    """Слой im, повёрнутый на deg° против часовой, центром в (cx, cy)."""
    r = im.rotate(deg, resample=Image.BICUBIC, expand=True)
    over(cv, r, cx - r.width / 2, cy - r.height / 2)


def to_canvas(im, ox, oy, bx, by, deg, ux, uy):
    """Точка (ux, uy) px слоя от клетки 0,0 → холст (слой центром в (bx, by), повёрнут на deg° против часовой)."""
    sx, sy = ox + ux - im.width / 2, oy + uy - im.height / 2
    a = math.radians(deg)
    return bx + sx * math.cos(a) + sy * math.sin(a), by - sx * math.sin(a) + sy * math.cos(a)


def hand(cv, tipx, tipy, size, deg):
    """Рука обучения: кончик пальца в (tipx, tipy), ширина size, поворот deg° вокруг кончика; мягкая тень."""
    src = Image.open(HAND_PNG).convert("RGBA")
    k = size / src.width
    im = src.resize((round(src.width * k), round(src.height * k)), Image.LANCZOS)
    pad = int(size * 0.25)
    big = Image.new("RGBA", (im.width + 2 * pad, im.height + 2 * pad), (0, 0, 0, 0))
    big.paste(im, (pad, pad), im)
    shadow = Image.new("RGBA", big.size, tuple(round(v * 255) for v in wp.DEEP[:3]) + (0,))
    shadow.putalpha(big.split()[3].filter(ImageFilter.GaussianBlur(size * 0.045)).point(lambda v: int(v * 0.35)))
    tx, ty = pad + HAND_TIP[0] * k, pad + HAND_TIP[1] * k
    R = int(math.hypot(big.width, big.height)) + 4
    for img, off in ((shadow, (size * 0.05, size * 0.08)), (big, (0, 0))):
        c = Image.new("RGBA", (2 * R, 2 * R), (0, 0, 0, 0))
        c.paste(img, (int(R - tx + off[0]), int(R - ty + off[1])), img)
        over(cv, c.rotate(deg, resample=Image.BICUBIC), tipx - R, tipy - R)


def rays(cv, cx, cy, r, n, alpha, glow, blur):
    """Лучи и свечение экрана победы (win_rays.gdshader) с центром (cx, cy)."""
    hw, hh = max(r, glow[0] + 2 * blur), max(r, glow[1] + 2 * blur)
    sp.draw_rect(cv, "win_rays", cx - hw, cy - hh, 2 * hw, 2 * hh, 1.0, (1, 1, 1, 1), {
        "rect_size": (2 * hw, 2 * hh), "center": (hw, hh), "radius": r, "rays": float(n), "ray_alpha": alpha,
        "glow_radius": glow, "glow_blur": blur, "glow_color": (1.0, 0.9, 1.0, 0.45)})


def sparkles(cv, spots):
    src = Image.open(SPARK_PNG).convert("RGBA")
    for x, y, d in spots:
        arr = np.asarray(src.resize((int(d), int(d)), Image.LANCZOS)).astype(float) / 255
        arr[..., :3] = 1.0
        cv.over(int(round(x - d / 2)), int(round(y - d / 2)), arr)


def scene(cv, cols, rows, rects, lifted, bx, by, cell, tilt, lift, hand_k):
    """Поле центром в (bx, by) с наклоном tilt°; блок lifted поднят над своим гнездом (сдвиг lift, наклон 7°), рука
    держит его за правую часть."""
    placed = [i for i in range(len(rects)) if i != lifted]
    im, (ox, oy) = board_layer(cols, rows, rects, placed, cell)
    paste_rot(cv, im, bx, by, tilt)
    rx, ry, rw, rh, nx, ny = rects[lifted]
    gx, gy = to_canvas(im, ox, oy, bx, by, tilt, (rx + rw / 2) * cell, (ry + rh / 2) * cell)
    cx, cy = gx + lift[0], gy + lift[1]
    paste_rot(cv, block_layer(rw, rh, (nx - rx, ny - ry), cell), cx, cy, 7)
    hand(cv, cx + 0.58 * cell, cy + 0.2 * cell, cell * hand_k, 12)


def icon():
    """Холст 660×660: фон с лучами, поле 3×3 (ICON_RECTS) с поднятой двойкой и рукой, искры; затем 512×512."""
    S = 660
    cv = wp.game_background(S, S)
    rays(cv, S / 2, S / 2, 520, 16, 0.13, (250, 250), 70)
    scene(cv, 3, 3, ICON_RECTS, LIFTED["icon"], S / 2 - 22, S / 2 - 8, 132, -5, (38, -48), 1.6)
    sparkles(cv, [(70, 80, 60), (600, 70, 40), (70, 600, 34)])
    return cv.image().resize((ICON, ICON), Image.LANCZOS)


def cover(lang=None):
    """Холст 1200×705 (×1,5 к 800×470): фон с лучами, поле 6×4 с поднятой двойкой и рукой (слева, а без текста —
    по центру и крупнее), искры, название справа (строка ACCENT — жёлтая)."""
    W, H = 1200, 705
    cv = wp.game_background(W, H)
    if lang:
        rays(cv, 400, 350, 950, 20, 0.11, (330, 300), 90)
        scene(cv, 6, 4, COVER_RECTS, LIFTED["cover"], 345, 365, 100, 4, (55, -100), 1.85)
        sparkles(cv, [(95, 60, 48), (660, 80, 36), (690, 620, 30), (50, 650, 26), (1140, 80, 30), (1150, 640, 36)])
        lines = TITLES[lang]
        x0, x1 = 715, W - 25
        size = 150
        while max(wp.text_w(t, wp.BLACK, size) for t in lines) > x1 - x0 and size > 50:
            size -= 2
        for i, t in enumerate(lines):
            cy = H / 2 - 5 + (i - (len(lines) - 1) / 2) * size * 1.06
            fill = tuple(sp.color_for(4)[:3]) if i == ACCENT[lang] else (1.0, 1.0, 1.0)
            sp.draw_label(cv, t, (x0 + x1) / 2, cy, size, fill, wp.INK, sp.HH["TITLE_OUTLINE"], wp.DEEP,
                          sp.HH["TITLE_SHADOW_ALPHA"], sp.HH["TITLE_SHADOW"])
    else:
        rays(cv, W / 2, H / 2, 950, 20, 0.11, (330, 300), 90)
        scene(cv, 6, 4, COVER_RECTS, LIFTED["cover"], W / 2, H / 2 - 5, 120, 3, (65, -120), 1.85)
        sparkles(cv, [(110, 90, 50), (1090, 110, 40), (1110, 600, 34), (90, 600, 30), (240, 640, 22), (980, 60, 24)])
    return cv.image().resize(COVER, Image.LANCZOS)


def sha1(path):
    """sha1 файла; текст — с переводами строк \\n (git на Windows может отдать \\r\\n — это не изменение)."""
    data = open(path, "rb").read()
    if not path.endswith((".png", ".ttf")):
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha1(data).hexdigest()


def icon_name():
    return "icon_%d.png" % ICON


def cover_name(lang):
    return "cover_%dx%d_%s.png" % (COVER + (lang or "notext",))


def write_sources(names):
    """docs/promo/SOURCES.txt: «sha1  путь» источников (от корня проекта) и картинок (от docs/promo)."""
    lines = ["# Отпечаток картинок docs/promo: пишет tools/promo_art.py, сверяет tools/promo_check.py. Не править руками.",
             "# источники"]
    lines += ["%s  %s" % (sha1(os.path.join(sp.ROOT, rel)), rel) for rel in ART_SOURCES]
    lines += ["# картинки"]
    lines += ["%s  %s" % (sha1(os.path.join(OUT, n)), n) for n in names]
    open(os.path.join(OUT, SOURCES_TXT), "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


def main(args):
    os.makedirs(OUT, exist_ok=True)
    im = icon()
    im.save(os.path.join(OUT, icon_name()), optimize=True)
    print(icon_name(), im.size)
    if "--icon" in args:
        print("--icon: обложки и %s не тронуты — для проверки promo_check запустите без --icon" % SOURCES_TXT)
        return
    names = [icon_name()]
    for lang in list(TITLES) + [None]:
        im = cover(lang)
        im.save(os.path.join(OUT, cover_name(lang)), optimize=True)
        names.append(cover_name(lang))
        print(cover_name(lang), im.size)
    write_sources(names)
    print(SOURCES_TXT, "—", len(ART_SOURCES), "источников,", len(names), "картинок")


if __name__ == "__main__":
    main(sys.argv[1:])
