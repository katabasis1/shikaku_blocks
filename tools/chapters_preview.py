#!/usr/bin/env python3
"""Кадры глав (этапы 19.5c–d, docs/STYLE.md 11.6): темы фона десяти глав на экране игры (первый уровень главы)
и карточка начала главы (ChapterCard, scenes/game/chapter_card.gd) над полем на ru / en / tr и в альбоме.

Таблицы глав и проверка — tools/chapters_model.py (из scripts/chapters.gd), фон — shaders/background.gdshader
через tools/shader_preview.py, экран игры — tools/window_preview.py (render_game).

Запуск из корня проекта:  python3 tools/chapters_preview.py   → docs/style_frames/G19_5_chapters.png и G19_5d_card.png
                          python3 tools/chapters_preview.py --card   → только G19_5d_card.png
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import window_preview as wp  # noqa: E402
import chapters_model as cm  # noqa: E402
from chapters_model import check, pack_info, shader_theme, table  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAMES = os.path.join(ROOT, "docs", "style_frames")


def render_themes(first, names, ideas, themes, va, scale=0.36):
    items = []
    for i, (lv, name, t) in enumerate(zip(first, names, themes)):
        img, _ = wp.render_game(720, 1280, level=lv, placed=[], theme=shader_theme(t, va))
        im = img.image() if hasattr(img, "image") else img
        items.append(("%d · %s" % (i + 1, name.capitalize()), im))
    return items


CARD_GD = "scenes/game/chapter_card.gd"
MAP_GD = "scenes/map/map_path.gd"


def card_consts():
    k = ("W", "SIDE", "PAD", "RADIUS", "DEPTH", "SHADOW", "RIM_W", "HEAD_FONT", "NAME_FONT", "IDEA_FONT", "HEAD_ALPHA",
         "TOP", "HEAD_ROW", "GAP", "NAME_ROW", "IDEA_GAP", "IDEA_ROW", "BOTTOM")
    C = {n: wp.gd(CARD_GD, n) for n in k}
    C["RIM"] = wp.gd_color(CARD_GD, "RIM")
    C["HEAD"] = wp.gd_str(CARD_GD, "HEAD")
    for n in ("LIP_DARK", "DIGIT_BASE_K", "DIGIT_OUTLINE_K"):
        C[n] = wp.gd(MAP_GD, n)
    C["SHADE"] = wp.gd_color("scripts/palette.gd", "SHADE")
    return C


def card_texts(level, locale, C, model):
    """«ГЛАВА N», название, идея (ChapterCard._set_texts) на языке locale."""
    tr_ = wp.po(locale) if locale != "ru" else {}
    head = tr_.get(C["HEAD"], C["HEAD"]).replace("%d", str(model.number(level)), 1)
    name = model.names[model.index(level)]
    idea = model.ideas[model.index(level)] if level <= model.total else ""
    return head, tr_.get(name, name), (tr_.get(idea, idea) if idea else "")


def draw_card(im, area, level, locale, C, model, alpha=1.0, scale=1.0, lift=0.0):
    """ChapterCard._draw поверх im (PIL RGBA): лицо по центру места поля area (x, y, w, h), губа, тень, рамка,
    три строки Nunito 1000 с обводкой темнее(цвет, 0,45). Возвращает (рамка лица, размеры шрифтов, тексты)."""
    head, name, idea = card_texts(level, locale, C, model)
    ax, ay, aw, ah = area
    w = min(max(aw - 2 * C["SIDE"], 0.0), C["W"])
    h = C["TOP"] + C["HEAD_ROW"] + C["GAP"] + C["NAME_ROW"] + C["BOTTOM"]
    if idea:
        h += C["IDEA_GAP"] + C["IDEA_ROW"]
    x0 = ax + aw / 2 - w / 2
    y0 = ay + ah / 2 - (h + C["DEPTH"]) / 2 - lift
    col = cm.hex_rgba(model.theme(level)["top"])
    SS = 3
    pad = 8
    lw, lh = int(math.ceil(w + 2 * pad)), int(math.ceil(h + C["DEPTH"] + C["SHADOW"] + 2 * pad))
    lay = Image.new("RGBA", (lw * SS, lh * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)

    def P(x, y):
        return (x + pad) * SS, (y + pad) * SS

    def px(c, a=1.0):
        return tuple(int(round(v * 255)) for v in c[:3]) + (int(round(255 * c[3] * a)),)

    r = C["RADIUS"] * SS
    dk = 1 - C["LIP_DARK"]
    d.rounded_rectangle([*P(0, C["DEPTH"] + C["SHADOW"]), *P(w, C["DEPTH"] + C["SHADOW"] + h)], radius=r, fill=px(C["SHADE"]))
    d.rounded_rectangle([*P(0, C["DEPTH"]), *P(w, C["DEPTH"] + h)], radius=r,
                        fill=px((col[0] * dk, col[1] * dk, col[2] * dk, 1.0)))
    d.rounded_rectangle([*P(0, 0), *P(w, h)], radius=r, fill=px(C["RIM"]))
    rw = C["RIM_W"]
    d.rounded_rectangle([*P(rw, rw), *P(w - rw, h - rw)], radius=r - rw * SS, fill=px(col))
    ink = (col[0] * 0.55, col[1] * 0.55, col[2] * 0.55, 1.0)
    sizes = []
    rows = [(head, C["HEAD_FONT"], C["TOP"] + C["HEAD_ROW"] / 2, C["HEAD_ALPHA"]),
            (name, C["NAME_FONT"], C["TOP"] + C["HEAD_ROW"] + C["GAP"] + C["NAME_ROW"] / 2, 1.0)]
    if idea:
        rows.append((idea, C["IDEA_FONT"], C["TOP"] + C["HEAD_ROW"] + C["GAP"] + C["NAME_ROW"] + C["IDEA_GAP"]
                     + C["IDEA_ROW"] / 2, 1.0))
    room = w - 2 * C["PAD"]
    for text, fs0, cy, a in rows:
        fs = int(fs0)
        tw = ImageFont.truetype(wp.BLACK, fs).getlength(text)
        if tw > room:
            fs = math.floor(fs0 * room / tw)
        sizes.append(fs)
        f = ImageFont.truetype(wp.BLACK, fs * SS)
        o = round(fs * C["DIGIT_OUTLINE_K"])
        d.text(P(w / 2, cy + fs * C["DIGIT_BASE_K"]), text, font=f, fill=(255, 255, 255, int(round(255 * a))),
               anchor="ms", stroke_width=int(round(o * SS / 2)), stroke_fill=px(ink, a))
    lay = lay.resize((lw, lh), Image.LANCZOS)
    if scale != 1.0:   # толчок: масштаб от центра лица
        nw, nh = max(1, round(lw * scale)), max(1, round(lh * scale))
        lay = lay.resize((nw, nh), Image.LANCZOS)
        cx, cy_ = x0 + w / 2, y0 + h / 2
        dx, dy = round(cx - (w / 2 + pad) * scale), round(cy_ - (h / 2 + pad) * scale)
    else:
        dx, dy = round(x0 - pad), round(y0 - pad)
    if alpha < 1.0:
        lay.putalpha(lay.getchannel("A").point(lambda v: int(v * alpha)))
    im.alpha_composite(lay, dest=(dx, dy))
    return (x0, y0, w, h), sizes, (head, name, idea)


def render_cards(model, C):
    """Кадр G19_5d_card: глава 2 (ru), 3 (en), 2 (tr — самое длинное название), 4 (en, механика — 19.5e),
    9 (ru, без идеи), фазы появления и ухода (ru, глава 2) и альбом 16:9 (en, глава 5). Возвращает
    [(подпись, картинка)] и проблемы."""
    va = model.va
    items, problems = [], []
    phases = [(61, "ru", 720, 1280, "2 · ru"), (101, "en", 720, 1280, "3 · en"), (61, "tr", 720, 1280, "2 · tr"),
              (151, "en", 720, 1280, "4 · en"), (401, "ru", 720, 1280, "9 · ru, без идеи")]
    for lv, loc, w, h, title in phases:
        cv, L = wp.render_game(w, h, level=lv, placed=[], theme=shader_theme(model.themes[model.index(lv)], va))
        im = to_image(cv).convert("RGBA")
        face, sizes, texts = draw_card(im, L["board"], lv, loc, C, model)
        want = [int(C["HEAD_FONT"]), int(C["NAME_FONT"])] + ([int(C["IDEA_FONT"])] if texts[2] else [])
        if sizes != want:
            problems.append("глава %d (%s): текст ужат %s → %s" % (model.number(lv), loc, want, sizes))
        items.append((title, im))
    # Фазы на главе 2 (ru): толчок (×0,85 и 60 %), стоит, уходит (подъём 20, 50 %).
    cv, L = wp.render_game(720, 1280, level=61, placed=[], theme=shader_theme(model.themes[1], va))
    base = to_image(cv).convert("RGBA")
    strip = []
    for title, kw in (("появление", dict(alpha=0.6, scale=0.85)), ("уход", dict(alpha=0.5, lift=C_RISE()))):
        im = base.copy()
        draw_card(im, L["board"], 61, "ru", C, model, **kw)
        strip.append((title, im))
    items += strip
    cv, L = wp.render_game(1280 * 16 // 9, 1280, level=201, placed=[],
                           theme=shader_theme(model.themes[model.index(201)], va))
    im = to_image(cv).convert("RGBA")
    draw_card(im, L["board"], 201, "en", C, model)
    items.append(("5 · en, альбом", im))
    return items, problems


def C_RISE():
    return wp.gd(CARD_GD, "RISE") * 0.5


def to_image(cv):
    if isinstance(cv, Image.Image):
        return cv
    return cv.image() if hasattr(cv, "image") else Image.fromarray(cv)


def grid(items, cols, name, scale):
    ims = [to_image(im).convert("RGB") for _, im in items]
    ims = [im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS) for im in ims]
    cw, ch = ims[0].width, ims[0].height + 46
    rows = (len(ims) + cols - 1) // cols
    out = Image.new("RGB", (cols * cw + (cols - 1) * 16, rows * ch + (rows - 1) * 16), (30, 20, 70))
    d = ImageDraw.Draw(out)
    f = ImageFont.truetype(wp.BLACK, 26)
    for k, ((title, _), im) in enumerate(zip(items, ims)):
        x, y = (k % cols) * (cw + 16), (k // cols) * (ch + 16)
        d.text((x + 8, y + 8), title, font=f, fill=(255, 255, 255))
        out.paste(im, (x, y + 46))
    path = os.path.join(FRAMES, name)
    out.save(path, optimize=True)
    return path


def card_grid(items, name, scale):
    """Портреты в ряд, альбом — отдельной строкой во всю ширину."""
    port = [(t, to_image(im).convert("RGB")) for t, im in items if to_image(im).width < to_image(im).height]
    land = [(t, to_image(im).convert("RGB")) for t, im in items if to_image(im).width >= to_image(im).height]
    ims = [im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS) for _, im in port]
    cw, ch = ims[0].width, ims[0].height + 46
    width = len(ims) * cw + (len(ims) - 1) * 16
    lands = []
    for _, im in land:
        k = width / im.width
        lands.append(im.resize((width, round(im.height * k)), Image.LANCZOS))
    height = ch + sum(16 + 46 + im.height for im in lands)
    out = Image.new("RGB", (width, height), (30, 20, 70))
    d = ImageDraw.Draw(out)
    f = ImageFont.truetype(wp.BLACK, 26)
    for k, ((title, _), im) in enumerate(zip(port, ims)):
        x = k * (cw + 16)
        d.text((x + 8, 8), title, font=f, fill=(255, 255, 255))
        out.paste(im, (x, 46))
    y = ch
    for (title, _), im in zip(land, lands):
        d.text((8, y + 16 + 8), title, font=f, fill=(255, 255, 255))
        out.paste(im, (0, y + 16 + 46))
        y += 16 + 46 + im.height
    path = os.path.join(FRAMES, name)
    out.save(path, optimize=True)
    return path


def main(argv):
    first, names, ideas, themes, span, va = table()
    problems = check(first, names, ideas, themes, span)
    for p in problems:
        print("ПРОБЛЕМА: " + p)
    total, loop_from = pack_info()
    print("глав: %d, уровней: %d, повтор с %d по %d уровней на главу" % (len(first), total, loop_from, span))
    if "--card" not in argv:
        items = render_themes(first, names, ideas, themes, va)
        print(grid(items, 5, "G19_5_chapters.png", 0.36))
    items, card_problems = render_cards(cm.Model(), card_consts())
    problems += card_problems
    for p in card_problems:
        print("ПРОБЛЕМА: " + p)
    print(card_grid(items, "G19_5d_card.png", 0.5))
    print("проблем: %d" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
