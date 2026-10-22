#!/usr/bin/env python3
"""Этап 12.3c: сравнение шрифтов-кандидатов и шрифтовых пар для стиля A2.

    python3 tools/font_specimens.py      # -> docs/fonts/specimens.png, docs/fonts/pairs.png

Кандидаты лежат в docs/fonts/cand/ — это подмножества (латиница, Latin Extended-A, кириллица,
знаки) шрифтов с Google Fonts под OFL; переменные шрифты заранее «заморожены» на нужном весе.
Откуда и как собраны — docs/fonts/README.md. Детерминирован.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import style_frames as sf  # noqa: E402

ROOT = sf.ROOT
CAND = os.path.join(ROOT, "docs", "fonts", "cand")
OUT = os.path.join(ROOT, "docs", "fonts")
SS = sf.SS
P = sf.P
hexc, darken, lighten = sf.hexc, sf.darken, sf.lighten

BG_TOP, BG_BOT = hexc("#4A34C9"), hexc("#7B46DE")
INK = hexc("#2E1678")
_cache = {}


def F(name, size):
    key = (name, size)
    if key not in _cache:
        _cache[key] = ImageFont.truetype(os.path.join(CAND, name + ".ttf"), P(size))
    return _cache[key]


def covers(name, s):
    from fontTools.ttLib import TTFont
    cmap = TTFont(os.path.join(CAND, name + ".ttf")).getBestCmap()
    return all(ord(c) in cmap or c == " " for c in s)


JELLY = sf.Jelly()
TILE_COLS = {2: "#FF4F6D", 4: "#FFC928", 6: "#27C2F2", 8: "#3E7BFF", 9: "#F25BCF", 12: "#3CCB6C"}


def title(img, x, y, s, fnt, size, anchor="lm"):
    sf.text(img, x, y, s, fnt, (255, 255, 255), anchor=anchor, stroke=size * 0.13, stroke_fill=INK,
            shadow_off=(0, size * 0.1), shadow_col=hexc("#1A0A55"), shadow_a=150)


def tile(img, x, y, n, fnt, D=74):
    col = hexc(TILE_COLS[n])
    m = P(10)
    lw = P(D) + 2 * m
    im = JELLY._gummy(lw, lw, (m, m, m + P(D), m + P(D)), P(D * 0.27), P(D * 0.08), col)
    sf.text(im, lw / 2 / SS, (lw / 2 - P(D * 0.04)) / SS, str(n), fnt, (255, 255, 255),
            stroke=D * 0.045, stroke_fill=darken(col, 0.42), shadow_off=(0, D * 0.03),
            shadow_col=darken(col, 0.55), shadow_a=120)
    sf.shadow(img, im.getchannel("A"), P(x) - m, P(y) - m, 0, P(5), P(6), hexc("#24106B"), 0.3)
    sf.comp(img, im, P(x) - m, P(y) - m)


def candy_button(img, cx, cy, w, h, s, fnt, col="#2FCF78", ink="#137A43", size=40):
    col = hexc(col)
    m = P(10)
    bw, bh = P(w), P(h)
    b = JELLY._gummy(bw + 2 * m, bh + 2 * m, (m, m, m + bw, m + bh), bh / 2, P(h * 0.09), col)
    sf.text(b, (bw / 2 + m) / SS, (bh / 2 + m - P(h * 0.05)) / SS, s, fnt, (255, 255, 255),
            stroke=size * 0.12, stroke_fill=hexc(ink))
    X, Y = P(cx) - b.width / 2, P(cy) - b.height / 2
    sf.shadow(img, b.getchannel("A"), X, Y, 0, P(6), P(8), hexc("#1A0A55"), 0.3)
    sf.comp(img, b, X, Y)


def background(w, h):
    img = Image.new("RGBA", (P(w), P(h)), (0, 0, 0, 255))
    img.alpha_composite(sf.grad_v(P(w), P(h), [(0, BG_TOP), (1, BG_BOT)]))
    return img


# ---------------------------------------------------------------- лист 1: кандидаты

ROWS = [
    # (файл, подпись, заметка, для цифр/заголовков, статус)
    ("Fredoka-Bold", "Fredoka Bold", "нравится вам; НЕТ кириллицы и турецких Ğ İ Ş — для ru/tr не подходит", "no"),
    ("Nunito-ExtraBlack", "Nunito ExtraBlack 1000", "скруглённые концы, как у Fredoka; ru + tr; один файл на все веса", "yes"),
    ("MPLUSRounded1c-ExtraBold", "M PLUS Rounded 1c ExtraBold", "самый «мармеладный»: круглые концы, мягкие цифры; ru + tr", "yes"),
    ("Rubik-ExtraBold", "Rubik ExtraBold", "буквы как скруглённые прямоугольники — рифма с блоками; ru + tr", "yes"),
    ("Unbounded-Black", "Unbounded Black", "широкий, с характером, только для логотипа и крупных заголовков", "yes"),
    ("SeymourOne-Regular", "Seymour One", "очень тяжёлый и широкий; длинные ru-строки не влезут", "meh"),
    ("BalsamiqSans-Bold", "Balsamiq Sans Bold", "«нарисован от руки»: мило, но похоже на макет", "meh"),
    ("Comfortaa-Bold", "Comfortaa Bold", "круглый, но тонкий даже в Bold — на телефоне слабо", "meh"),
    ("NotoSans-ExtraBold_now", "Noto Sans ExtraBold (сейчас)", "нейтральный, «офисный»", "now"),
]
RU = "УРОВЕНЬ 20"
TR = "SEVİYE 20 · İpucu · Güzel iş!"
BODY = "Осталось блоков: 3"
STATUS = {"yes": ("#3CCB6C", "подходит"), "no": ("#FF4F6D", "не подходит"), "meh": ("#FFB02E", "с оговорками"),
          "now": ("#A9A3C9", "сейчас")}


def specimens():
    W, rowh, top = 2200, 176, 150
    H = top + rowh * len(ROWS) + 40
    img = background(W, H)
    d = ImageDraw.Draw(img)
    hdr = F("Nunito-ExtraBlack", 44)
    sub = F("Nunito-Bold", 24)
    d.text((P(40), P(34)), "Шрифты-кандидаты для A2 (все — OFL, бесплатно для коммерции)", font=hdr, fill=(255, 255, 255))
    d.text((P(40), P(96)), "Заголовок · цифры на блоках · кнопка · текст интерфейса · турецкий. Проверено покрытие: "
           "кириллица (66 букв), турецкие Ç Ğ İ ı Ö Ş Ü.", font=sub, fill=(220, 210, 255))
    for i, (name, label, note, st) in enumerate(ROWS):
        y0 = top + i * rowh
        band = Image.new("RGBA", (P(W - 40), P(rowh - 14)), (255, 255, 255, 22 if i % 2 == 0 else 12))
        sf.comp(img, band, P(20), P(y0))
        cy = y0 + (rowh - 14) / 2
        col, stxt = STATUS[st]
        d.text((P(40), P(y0 + 16)), label, font=F("Nunito-ExtraBold", 27), fill=(255, 255, 255))
        d.rounded_rectangle([P(40), P(y0 + 58), P(40) + P(150), P(y0 + 90)], radius=P(16), fill=hexc(col))
        d.text((P(115), P(y0 + 74)), stxt, font=F("Nunito-ExtraBold", 19), fill=(255, 255, 255), anchor="mm")
        # заметка — в две строки по ширине 380
        words, lines, cur = note.split(), [], ""
        fn = F("Nunito-Bold", 19)
        for w_ in words:
            t = (cur + " " + w_).strip()
            if cur and d.textlength(t, font=fn) > P(390):
                lines.append(cur)
                cur = w_
            else:
                cur = t
        lines.append(cur)
        for k, ln in enumerate(lines[:3]):
            d.text((P(40), P(y0 + 100 + k * 22)), ln, font=fn, fill=(215, 205, 250))
        # образцы
        ok_ru = covers(name, RU)
        ts = RU if ok_ru else "LEVEL 20"
        size = 50
        while ImageDraw.Draw(img).textlength(ts, font=F(name, size)) > P(330) and size > 20:
            size -= 2
        title(img, 470, cy - 4, ts, F(name, size), size)
        if not ok_ru:
            sf.text(img, 470, cy + 46, "кириллицы нет", F("Nunito-ExtraBold", 20), hexc("#FFD0D8"), anchor="lm")
        for k, n in enumerate((2, 4, 8, 12)):
            tile(img, 830 + k * 88, cy - 37, n, F(name, 36))
        candy_button(img, 1350, cy, 250, 92, "ДАЛЕЕ" if ok_ru else "NEXT", F(name, 38), size=38)
        sf.text(img, 1510, cy - 24, BODY if ok_ru else "Blocks left: 3", F(name, 30), (255, 255, 255),
                anchor="lm", shadow_off=(0, 3), shadow_col=hexc("#1A0A55"), shadow_a=110)
        tr_ok = covers(name, TR)
        sf.text(img, 1510, cy + 28, TR, F(name, 26), hexc("#FFE680") if tr_ok else hexc("#FFB3C0"), anchor="lm")
        if not tr_ok:
            sf.text(img, 1510, cy + 60, "нет Ğ İ Ş — видны пустые квадраты", F("Nunito-Bold", 18), hexc("#FFD0D8"), anchor="lm")
    img.convert("RGB").resize((W, H), Image.LANCZOS).save(os.path.join(OUT, "specimens.png"), optimize=True)


# ---------------------------------------------------------------- лист 2: пары

PAIRS = [
    ("1. Nunito + Nunito", "Nunito-ExtraBlack", "Nunito-ExtraBold", "Одна семья, один файл (переменный, ~60 КБ после урезки). "
     "Гармония гарантирована, ближе всего к Fredoka. Минус: Nunito встречается часто.", True),
    ("2. M PLUS Rounded + Nunito", "MPLUSRounded1c-ExtraBold", "Nunito-Bold", "Заголовки и цифры — круглые, «конфетные», "
     "текст — спокойный Nunito с теми же круглыми концами. Больше характера, 2 файла.", False),
    ("3. Rubik + Nunito", "Rubik-ExtraBold", "Nunito-Bold", "Rubik — буквы-«блоки» со скруглёнными углами, рифмуются с игрой. "
     "Цифры плотные и чёткие. Чуть строже, чем 1 и 2.", False),
    ("4. Unbounded + Nunito", "Unbounded-Black", "Nunito-ExtraBold", "Unbounded только для логотипа и заголовков экранов, "
     "всё остальное — Nunito. Заметнее всего, но широкий: длинные строки не влезут.", False),
]


def pair_card(img, x, y, w, h, name, disp, body, note, rec):
    lw, lh = P(w), P(h)
    card = sf.rr_mask(lw, lh, (0, 0, lw, lh), P(36))
    sf.shadow(img, card, P(x), P(y), 0, P(10), P(16), hexc("#1A0A55"), 0.35)
    sf.comp(img, sf.paint(card, sf.grad_v(lw, lh, [(0, hexc("#6A48E6")), (1, hexc("#8E55E8"))])), P(x), P(y))
    cx = x + w / 2
    d = ImageDraw.Draw(img)
    d.text((P(x + 28), P(y + 22)), name, font=F("Nunito-ExtraBlack", 30), fill=(255, 255, 255))
    if rec:
        d.rounded_rectangle([P(x + w - 196), P(y + 64), P(x + w - 26), P(y + 96)], radius=P(16), fill=hexc("#3CCB6C"))
        d.text((P(x + w - 111), P(y + 80)), "рекомендую", font=F("Nunito-ExtraBold", 20), fill=(255, 255, 255), anchor="mm")
    title(img, cx, y + 134, "УРОВЕНЬ 20", F(disp, 54), 54, anchor="mm")
    fs = F(disp, 34)
    tw = ImageDraw.Draw(img).textlength("2 340", font=fs) / SS
    sx = cx - (tw + 44) / 2
    st = sf.round_shape(sf.icon_mask("star", P(38), 1), P(2))
    sf.comp(img, sf.paint(st, darken(hexc("#FFB800"), 0.3)), P(sx), P(y + 164))
    sf.comp(img, sf.paint(st, sf.grad_v(P(38), P(38), [(0, hexc("#FFF3A0")), (1, hexc("#FFB800"))])), P(sx), P(y + 161))
    sf.text(img, sx + 44 + tw / 2, y + 182, "2 340", fs, hexc("#FFE066"), anchor="mm", stroke=4, stroke_fill=INK)
    for k, n in enumerate((2, 6, 9, 12)):
        tile(img, cx - 190 + k * 98, y + 222, n, F(disp, 40), D=82)
    sf.text(img, cx, y + 350, "Осталось блоков: 3", F(body, 30), (255, 255, 255), anchor="mm",
            shadow_off=(0, 3), shadow_col=hexc("#1A0A55"), shadow_a=110)
    # облачко обучения
    bw, bh = w - 70, 96
    bx, by = x + 35, y + 388
    bub = sf.rr_mask(P(bw), P(bh), (0, 0, P(bw), P(bh)), P(28))
    sf.shadow(img, bub, P(bx), P(by), 0, P(5), P(8), hexc("#1A0A55"), 0.25)
    sf.comp(img, sf.paint(bub, (255, 255, 255)), P(bx), P(by))
    sf.text(img, cx, by + bh / 2, "Перетащи блок на число\nтакой же площади", F(body, 26), INK, anchor="mm", spacing=4)
    candy_button(img, cx, y + 560, 300, 96, "ИГРАТЬ", F(disp, 42), size=42)
    sf.text(img, cx, y + 640, "Музыка · Звуки · Вибрация", F(body, 24), hexc("#E6DDFF"), anchor="mm")
    sf.text(img, cx, y + 676, "SEVİYE 20 · Kalan blok: 3 · Harika!", F(body, 22), hexc("#FFE680"), anchor="mm")
    # заметка
    fn = F("Nunito-Bold", 21)
    words, lines, cur = note.split(), [], ""
    for w_ in words:
        t = (cur + " " + w_).strip()
        if cur and d.textlength(t, font=fn) > P(w - 60):
            lines.append(cur)
            cur = w_
        else:
            cur = t
    lines.append(cur)
    for k, ln in enumerate(lines):
        d.text((P(x + 30), P(y + 716 + k * 27)), ln, font=fn, fill=(235, 228, 255))
    nice = {"Nunito-ExtraBlack": "Nunito 1000", "Nunito-ExtraBold": "Nunito 800", "Nunito-Bold": "Nunito 700",
            "MPLUSRounded1c-ExtraBold": "M PLUS Rounded 800", "Rubik-ExtraBold": "Rubik 800",
            "Unbounded-Black": "Unbounded 900"}
    sub = "Заголовки и цифры: %s · текст: %s" % (nice[disp], nice[body])
    d.text((P(x + 30), P(y + h - 40)), sub, font=F("Nunito-Bold", 17), fill=(200, 188, 245))


def pairs():
    cw, ch, gap, top = 520, 880, 28, 120
    W = gap + len(PAIRS) * (cw + gap)
    H = top + ch + 40
    img = background(W, H)
    d = ImageDraw.Draw(img)
    d.text((P(gap), P(30)), "Шрифтовые пары: заголовки и цифры + текст интерфейса", font=F("Nunito-ExtraBlack", 44),
           fill=(255, 255, 255))
    d.text((P(gap), P(84)), "Все пары — с кириллицей и турецкими буквами. Цифры на блоках — шрифтом заголовков.",
           font=F("Nunito-Bold", 24), fill=(220, 210, 255))
    for i, (name, disp, body, note, rec) in enumerate(PAIRS):
        pair_card(img, gap + i * (cw + gap), top, cw, ch, name, disp, body, note, rec)
    img.convert("RGB").resize((W, H), Image.LANCZOS).save(os.path.join(OUT, "pairs.png"), optimize=True)


if __name__ == "__main__":
    specimens()
    pairs()
    print("docs/fonts/specimens.png, docs/fonts/pairs.png")
