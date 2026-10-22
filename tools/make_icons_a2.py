#!/usr/bin/env python3
"""Этап 12.3e: «сочные» иконки стиля A2 — SVG, которые Godot импортирует без изменений.

    python3 tools/make_icons_a2.py     # -> docs/style_frames/icons_a2/*.svg + icons_a2.png (лист)

Что внутри. Кнопка — круглая «конфета»: мягкая тень (радиальный градиент — ThorVG в Godot
фильтры SVG не умеет, а градиенты умеет), нижняя грань, тело с градиентом, блик-полумесяц,
искорка. Знак — белый (или цветной на белой кнопке) с толстой тёмной обводкой: сначала рисуется
обводка, поверх — заливка (paint-order не нужен). Отдельно: звезда, значок рекламы, рука обучения.
Никаких <filter>, <mask>, <text> — только path/circle/ellipse/rect и градиенты.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "style_frames", "icons_a2")

# ---------------------------------------------------------------- палитра кнопок
BUTTONS = {
    # имя: (верх тела, низ тела, грань, цвет знака-верх, знак-низ, обводка знака)
    "white":  ("#FFFFFF", "#E6DDFF", "#B49CF5", "#8F72FF", "#5B3FD9", "#2E1678"),
    "blue":   ("#6FD8FF", "#1E9BEF", "#1170C4", "#FFFFFF", "#DDF3FF", "#0B4F8F"),
    "yellow": ("#FFE36B", "#FFB01F", "#E07F00", "#FFFFFF", "#FFF3D1", "#A85400"),
    "green":  ("#7BEFA6", "#25C46C", "#15924C", "#FFFFFF", "#E1FFEC", "#0E6636"),
    "pink":   ("#FF9BB0", "#FF4F6D", "#D12A4B", "#FFFFFF", "#FFE3E9", "#8E1530"),
}

# ---------------------------------------------------------------- знаки (поле 64×64, центр 32,32)
# Каждый знак — список элементов: ("fill", d) — залитая фигура; ("line", d, w) — линия толщиной w.
GLYPHS = {
    "pause": [("fill", "M19 13 h6 a4.5 4.5 0 0 1 4.5 4.5 v29 a4.5 4.5 0 0 1 -4.5 4.5 h-6 a4.5 4.5 0 0 1 -4.5 -4.5 v-29 "
                       "a4.5 4.5 0 0 1 4.5 -4.5 Z"),
              ("fill", "M39 13 h6 a4.5 4.5 0 0 1 4.5 4.5 v29 a4.5 4.5 0 0 1 -4.5 4.5 h-6 a4.5 4.5 0 0 1 -4.5 -4.5 v-29 "
                       "a4.5 4.5 0 0 1 4.5 -4.5 Z")],
    "restart": [("line", "M40.0 20.1 A16 16 0 1 1 21.3 22.1", 8.5),
                ("fill", "M29.5 14.7 L26.6 29.5 L14.5 16.1 Z")],
    "undo": [("line", "M22 22 H38 A12.5 12.5 0 0 1 38 47 H24", 8.5),
             ("fill", "M9.5 22 L25 10.5 L25 33.5 Z")],
    "home": [("fill", "M32 9.5 L55 29 a3 3 0 0 1 -2 5.2 H49 V50 a4 4 0 0 1 -4 4 H38 V41 a3 3 0 0 0 -3 -3 H29 "
                      "a3 3 0 0 0 -3 3 V54 H19 a4 4 0 0 1 -4 -4 V34.2 H11 a3 3 0 0 1 -2 -5.2 Z")],
    "bulb": [("fill", "M32 7 C20.5 7 13.5 15.5 13.5 25 C13.5 31.5 17 35.5 20.5 39 C22 40.5 22.8 42 22.8 44 "
                      "H41.2 C41.2 42 42 40.5 43.5 39 C47 35.5 50.5 31.5 50.5 25 C50.5 15.5 43.5 7 32 7 Z"),
             ("fill", "M23.5 48 H40.5 a3 3 0 0 1 0 6 H23.5 a3 3 0 0 1 0 -6 Z"),
             ("fill", "M27 56.5 H37 a2.6 2.6 0 0 1 0 5.2 H27 a2.6 2.6 0 0 1 0 -5.2 Z")],
    "music_on": [("line", "M25 44 V16 L49 10.5 V38", 6.5),
                 ("fill", "M9.5 45 a8.5 7.2 0 1 0 17 0 a8.5 7.2 0 1 0 -17 0 Z"),
                 ("fill", "M33.5 39 a8.5 7.2 0 1 0 17 0 a8.5 7.2 0 1 0 -17 0 Z")],
    "sound_on": [("fill", "M9 25 H19 L31 14 V50 L19 39 H9 Z"),
                 ("line", "M39.5 25 A9 9 0 0 1 39.5 39", 6),
                 ("line", "M46 17.5 A19 19 0 0 1 46 46.5", 6)],
    "vibration_on": [("fill", "M26 8 H38 a5 5 0 0 1 5 5 V51 a5 5 0 0 1 -5 5 H26 a5 5 0 0 1 -5 -5 V13 a5 5 0 0 1 5 -5 Z"),
                     ("line", "M13 24 Q9 32 13 40", 5.5), ("line", "M51 24 Q55 32 51 40", 5.5)],
    "settings": [("fill", "M28.4 6.5 H35.6 L37 13.2 L41.4 15 L47.1 11.3 L52.2 16.4 L48.5 22.1 L50.3 26.5 L57 27.9 V35.1 "
                          "L50.3 36.5 L48.5 40.9 L52.2 46.6 L47.1 51.7 L41.4 48 L37 49.8 L35.6 56.5 H28.4 L27 49.8 "
                          "L22.6 48 L16.9 51.7 L11.8 46.6 L15.5 40.9 L13.7 36.5 L7 35.1 V27.9 L13.7 26.5 L15.5 22.1 "
                          "L11.8 16.4 L16.9 11.3 L22.6 15 L27 13.2 Z")],
}
# вырез (отверстие) — рисуется цветом кнопки поверх знака
HOLES = {"settings": "M32 23.5 a8 8 0 1 0 0.01 0 Z",
         "vibration_on": "M29 49 h6 a2 2 0 0 1 0 4 h-6 a2 2 0 0 1 0 -4 Z"}
# «выключено»: тот же знак бледнее + перечёркивание
OFF_OF = {"music_off": "music_on", "sound_off": "sound_on", "vibration_off": "vibration_on"}

ICON_BUTTON = {  # какой кнопке какой цвет
    "pause": "white", "restart": "white", "home": "white", "settings": "white",
    "music_on": "white", "music_off": "white", "sound_on": "white", "sound_off": "white",
    "vibration_on": "white", "vibration_off": "white",
    "undo": "blue", "bulb": "yellow",
}


def grad(id_, c0, c1, x1=0, y1=0, x2=0, y2=1, o0=1.0, o1=1.0):
    return ('<linearGradient id="%s" x1="%s" y1="%s" x2="%s" y2="%s">'
            '<stop offset="0" stop-color="%s" stop-opacity="%s"/><stop offset="1" stop-color="%s" stop-opacity="%s"/>'
            '</linearGradient>' % (id_, x1, y1, x2, y2, c0, o0, c1, o1))


def rgrad(id_, c, o0, cx=0.5, cy=0.5, r=0.5):
    return ('<radialGradient id="%s" cx="%s" cy="%s" r="%s"><stop offset="0" stop-color="%s" stop-opacity="%s"/>'
            '<stop offset="0.55" stop-color="%s" stop-opacity="%s"/><stop offset="1" stop-color="%s" stop-opacity="0"/>'
            '</radialGradient>' % (id_, cx, cy, r, c, o0, c, o0 * 0.45, c))


def glyph_svg(name, fill_ref, outline, ow, face_ref=None, faded=False):
    """Знак в поле 64×64: обводка снизу, заливка сверху, блик."""
    items = GLYPHS[name]
    op = ' opacity="0.45"' if faded else ""
    out = ['<g%s>' % op]
    for it in items:   # 1) обводка
        if it[0] == "fill":
            out.append('<path d="%s" fill="%s" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>'
                       % (it[1], outline, outline, ow * 2))
        else:
            out.append('<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" '
                       'stroke-linejoin="round"/>' % (it[1], outline, it[2] + ow * 2))
    for it in items:   # 2) заливка
        if it[0] == "fill":
            out.append('<path d="%s" fill="%s"/>' % (it[1], fill_ref))
        else:
            out.append('<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" '
                       'stroke-linejoin="round"/>' % (it[1], fill_ref, it[2]))
    if name in HOLES and face_ref:
        out.append('<path d="%s" fill="%s" stroke="%s" stroke-width="%s"/>' % (HOLES[name], face_ref, outline, ow * 1.6))
    out.append('</g>')
    return "".join(out)


def slash(outline, color):
    return ('<path d="M13 13 L51 51" stroke="%s" stroke-width="15" stroke-linecap="round"/>'
            '<path d="M13 13 L51 51" stroke="%s" stroke-width="8" stroke-linecap="round"/>' % (outline, color))


def button_svg(icon, size=128):
    """Круглая кнопка-конфета со знаком. viewBox 128×128: кнопка Ø104, тень снизу."""
    base = OFF_OF.get(icon, icon)
    top, bot, lip, g0, g1, ol = BUTTONS[ICON_BUTTON[icon]]
    defs = [rgrad("sh", "#1A0A55", 0.42), grad("face", top, bot), grad("gl", "#FFFFFF", "#FFFFFF", o0=0.85, o1=0.0),
            grad("gf", g0, g1), grad("rim", "#FFFFFF", "#FFFFFF", o0=0.55, o1=0.0)]
    body = [
        '<ellipse cx="64" cy="112" rx="50" ry="12" fill="url(#sh)"/>',
        '<circle cx="64" cy="67" r="52" fill="%s"/>' % lip,
        '<circle cx="64" cy="60" r="52" fill="url(#face)"/>',
        '<circle cx="64" cy="60" r="49.5" fill="none" stroke="url(#rim)" stroke-width="3"/>',
        # блик-полумесяц по верхнему краю
        '<path d="M26 44 C30 24 46 13 64 13 C82 13 98 24 102 44 C92 34 80 30 64 30 C48 30 36 34 26 44 Z" fill="url(#gl)"/>',
        '<ellipse cx="36" cy="33" rx="6" ry="4" transform="rotate(-35 36 33)" fill="#FFFFFF" opacity="0.95"/>',
    ]
    faded = icon in OFF_OF
    g = glyph_svg(base, "url(#gf)", ol, 2.6, face_ref=bot if ICON_BUTTON[icon] != "white" else "#EFE9FF", faded=faded)
    body.append('<g transform="translate(64 60) scale(1.14) translate(-32 -32)">%s%s</g>'
                % (g, slash(ol, "#FF4F6D") if faded else ""))
    if base == "bulb":   # лучики у лампочки
        rays = ['<path d="M%s" stroke="#FFFFFF" stroke-width="4.5" stroke-linecap="round" opacity="0.9"/>' % d
                for d in ("21 31 L16 29", "107 31 L112 29", "31 17 L28 12", "97 17 L100 12")]
        body[5:5] = rays
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 128 128"><defs>%s</defs>%s</svg>'
            % (size, size, "".join(defs), "".join(body)))


def star_svg(size=128):
    import math
    pts = []
    for i in range(10):
        a = math.radians(-90 + i * 36)
        r = 54 if i % 2 == 0 else 25
        pts.append((64 + r * math.cos(a), 68 + r * math.sin(a)))
    d = "M" + " L".join("%.1f %.1f" % p for p in pts) + " Z"
    defs = grad("sf", "#FFF27A", "#FFB300") + rgrad("sh", "#5A2A00", 0.35)
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 128 128"><defs>%s</defs>'
            '<ellipse cx="64" cy="118" rx="40" ry="8" fill="url(#sh)"/>'
            '<path d="%s" transform="translate(0 5)" fill="#D97A00" stroke="#D97A00" stroke-width="12" stroke-linejoin="round"/>'
            '<path d="%s" fill="#A85400" stroke="#A85400" stroke-width="12" stroke-linejoin="round"/>'
            '<path d="%s" fill="url(#sf)" stroke="url(#sf)" stroke-width="4" stroke-linejoin="round"/>'
            '<path d="M44 52 L55 36" stroke="#FFFFFF" stroke-width="7" stroke-linecap="round" opacity="0.9"/>'
            '<circle cx="60" cy="30" r="3.5" fill="#FFFFFF"/></svg>' % (size, size, defs, d, d, d))


def ad_svg(size=96):
    defs = grad("af", "#7BEFA6", "#25C46C") + grad("gl", "#FFFFFF", "#FFFFFF", o0=0.8, o1=0.0)
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 64 64"><defs>%s</defs>'
            '<rect x="4" y="13" width="56" height="42" rx="14" fill="#15924C"/>'
            '<rect x="4" y="9" width="56" height="42" rx="14" fill="url(#af)" stroke="#0E6636" stroke-width="3"/>'
            '<path d="M12 22 C14 15 20 12 32 12 C44 12 50 15 52 22 C46 18 40 17 32 17 C24 17 18 18 12 22 Z" fill="url(#gl)"/>'
            '<path d="M26 20 L44 30 L26 40 Z" fill="#0E6636" stroke="#0E6636" stroke-width="6" stroke-linejoin="round"/>'
            '<path d="M26 20 L44 30 L26 40 Z" fill="#FFFFFF" stroke="#FFFFFF" stroke-width="2" stroke-linejoin="round"/>'
            '</svg>' % (size, size, defs))


# Рука обучения: мультяшная перчатка (тыльная сторона), указательный палец вверх.
# Кончик пальца — точка (57, 7) в поле 128×128: в Godot смещаем текстуру так, чтобы «нажимал» кончик.
HAND_TIP = (57, 7)
HAND_BACK = [  # одна общая обводка: палец + костяшки + кисть
    "M46 64 V18 a11 11 0 0 1 22 0 V56 Z",                 # указательный
    "M66 58 V52 a10 10 0 0 1 20 0 V60 Z",                 # средний (согнут, видна костяшка)
    "M84 62 V58 a9 9 0 0 1 18 0 V66 Z",                   # безымянный
    "M99 68 V66 a7.5 7.5 0 0 1 15 0 V74 Z",               # мизинец
    "M42 58 H106 a8 8 0 0 1 8 8 V84 C114 102 102 114 84 114 H66 C52 114 42 104 42 90 Z",   # кисть
]
HAND_THUMB = "M31 76 a9 9 0 0 1 15 -9 L60 84 a9 9 0 0 1 -12 13 Z"
HAND_CUFF = "M52 106 H100 a6 6 0 0 1 6 6 V116 a6 6 0 0 1 -6 6 H52 a6 6 0 0 1 -6 -6 V112 a6 6 0 0 1 6 -6 Z"


def hand_svg(size=160):
    ol = "#2E1678"
    # заливка кисти — один градиент на всю руку (userSpaceOnUse), иначе на стыках частей видны полосы
    defs = ('<linearGradient id="hf" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="120">'
            '<stop offset="0" stop-color="#FFFFFF"/><stop offset="0.55" stop-color="#F6F2FF"/>'
            '<stop offset="1" stop-color="#E2D8FF"/></linearGradient>'
            + grad("cf", "#A58CFF", "#6A4BF0") + grad("gl", "#FFFFFF", "#FFFFFF", o0=0.95, o1=0.0)
            + grad("sd", "#D6CAFF", "#C2B2FA", o0=0.0, o1=1.0))
    s = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 128 128"><defs>%s</defs>'
         % (size, size, defs)]
    for d in HAND_BACK:
        s.append('<path d="%s" fill="%s" stroke="%s" stroke-width="8" stroke-linejoin="round"/>' % (d, ol, ol))
    for d in HAND_BACK:
        s.append('<path d="%s" fill="url(#hf)"/>' % d)
    # тень по правому краю кисти и складки между пальцами
    s.append('<path d="M114 66 V84 C114 102 102 114 84 114 H78 C96 108 106 98 107 82 V66 Z" fill="url(#sd)"/>')
    for x, y0, y1 in ((67, 58, 66), (85, 62, 70), (100, 67, 74)):
        s.append('<path d="M%s %s V%s" stroke="#BFB0F2" stroke-width="3.2" stroke-linecap="round"/>' % (x, y0, y1))
    # большой палец — поверх, со своей обводкой
    s.append('<path d="%s" fill="%s" stroke="%s" stroke-width="8" stroke-linejoin="round"/>' % (HAND_THUMB, ol, ol))
    s.append('<path d="%s" fill="url(#hf)"/>' % HAND_THUMB)
    # блики
    s.append('<path d="M52 20 V44" stroke="url(#gl)" stroke-width="5.5" stroke-linecap="round"/>')
    s.append('<circle cx="53" cy="13.5" r="2.6" fill="#FFFFFF"/>')
    # манжета
    s.append('<path d="%s" fill="%s" stroke="%s" stroke-width="8" stroke-linejoin="round"/>' % (HAND_CUFF, ol, ol))
    s.append('<path d="%s" fill="url(#cf)"/>' % HAND_CUFF)
    s.append('<path d="M54 110.5 H98" stroke="#FFFFFF" stroke-width="2.6" stroke-linecap="round" opacity="0.65"/>')
    s.append('</svg>')
    return "".join(s)


ALL_BUTTONS = ["pause", "restart", "undo", "bulb", "home", "settings", "music_on", "music_off",
               "sound_on", "sound_off", "vibration_on", "vibration_off"]


def build():
    os.makedirs(OUT, exist_ok=True)
    files = {}
    for ic in ALL_BUTTONS:
        files["btn_%s.svg" % ic] = button_svg(ic)
    files["star.svg"] = star_svg()
    files["ad.svg"] = ad_svg()
    files["hand.svg"] = hand_svg()
    for name, svg in files.items():
        with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
            f.write(svg + "\n")
    return files


def sheet(files):
    """Лист иконок: старые (assets/icons) — сверху, новые A2 — снизу."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from PIL import Image, ImageDraw, ImageFont
    from svgrender import svg_to_image
    import style_frames as sf
    fnt = lambda n, s: ImageFont.truetype(os.path.join(ROOT, "docs", "fonts", "cand", n + ".ttf"), s)
    old = ["pause", "restart", "undo", "hint", "home", "settings", "music_on", "music_off", "sound_on", "sound_off",
           "vibration_on", "vibration_off", "star", "ad", "hand"]
    new = ["btn_%s" % n for n in ALL_BUTTONS] + ["star", "ad", "hand"]
    cell, gap, left, top = 150, 18, 130, 170
    Wd = left + len(new) * (cell + gap) + 40
    Hd = top + 2 * (cell + 90) + 60
    im = Image.new("RGBA", (Wd, Hd))
    im.alpha_composite(sf.grad_v(Wd, Hd, [(0, sf.hexc("#4A34C9")), (1, sf.hexc("#7B46DE"))]))
    d = ImageDraw.Draw(im)
    d.text((left, 36), "Иконки: сейчас и A2", font=fnt("Nunito-ExtraBlack", 50), fill=(255, 255, 255))
    d.text((left, 100), "Кнопки-«конфеты»: навигация — белые, отмена — голубая, подсказка — жёлтая. Всё — SVG без "
           "фильтров: Godot импортирует как есть.", font=fnt("Nunito-Bold", 26), fill=(222, 212, 255))
    rows = [("сейчас", [os.path.join(ROOT, "docs", "icons", "svg_old", n + ".svg") for n in old]),
            ("A2", [os.path.join(OUT, n + ".svg") for n in new])]
    for r, (label, paths) in enumerate(rows):
        y = top + r * (cell + 90)
        d.text((left - 60, y + cell / 2), label, font=fnt("Nunito-ExtraBold", 24), fill=(255, 255, 255), anchor="mm")
        for i, pth in enumerate(paths):
            x = left + 30 + i * (cell + gap)
            svg = open(pth, encoding="utf-8").read()
            k = 0.62 if r == 0 else 1.0
            if r == 0 and not pth.endswith(("star.svg", "ad.svg", "hand.svg")):
                d.ellipse([x + 22, y + 22, x + cell - 22, y + cell - 22], fill=(255, 255, 255))
            icon = svg_to_image(svg, int(cell * k), int(cell * k))
            im.alpha_composite(icon, (int(x + (cell - icon.width) / 2), int(y + (cell - icon.height) / 2)))
            if r == 1:
                nm = os.path.basename(pth)[:-4].replace("btn_", "")
                d.text((x + cell / 2, y + cell + 22), nm, font=fnt("Nunito-Bold", 19), fill=(230, 222, 255), anchor="mm")
    im.convert("RGB").save(os.path.join(ROOT, "docs", "style_frames", "icons_a2.png"), optimize=True)


if __name__ == "__main__":
    fs = build()
    sheet(fs)
    print("%d SVG -> %s, лист: docs/style_frames/icons_a2.png" % (len(fs), OUT))
