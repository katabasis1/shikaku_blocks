#!/usr/bin/env python3
"""Кадры окон «как в Godot» без Godot (13.5e): те же шейдеры (через переводчик shader_preview), места из
сцен и кода, шрифты и иконки проекта. Чтобы сверить окна со стиль-кадрами до проверки в Godot.

  python3 tools/window_preview.py            все кадры
  python3 tools/window_preview.py --win      только победа (--panels — окна настроек, --toasts — сообщения,
                                             --menu — меню, --map — карта уровней, --leaders — экран лидеров, --lab —
                                             «Лаборатория», --background — фон)

Кадры (docs/style_frames/):
  G13_5_win.png          окно победы на 720×1280: поле уровня 20 на месте победы (GameLayout.win_board),
                         лучи и свечение (win_rays.gdshader), конфетти (физика Confetti, 1,3 с после залпа),
                         заголовок, карточка (card.gdshader), звёзды с тенью, «+очки», «ДАЛЕЕ», «Переиграть»
  G13_5_win_compare.png  эталон A3B_win | G13_5_win
  G13_5_panels.png       SettingsPanel 720×1280: настройки (меню), подтверждение сброса, пауза (поверх игры) —
                         карточка с фиолетовой шапкой, кнопки-переключатели, таблетки, ссылка «В меню»
  G13_6_menu.png         меню (13.6, STYLE 11.1; логотип 07.10): портрет ru, en, tr (уровень 500 — самая длинная
                         вторая строка), альбом 16:9 — логотип MenuLogo (свечение и лучи, поле 4×3 из блоков,
                         двойка парит над местом, искры; надписей нет), «ИГРАТЬ» с уровнем, светлые «ЗАДАЧА ДНЯ»
                         с серией (18.1) и «УРОВНИ» (18.2), счёт и шестерёнка
  G18_2_map.png          карта уровней (18.2, STYLE 11.2): уровень 12, новый игрок, уровень 1000 (четыре цифры
                         ужимаются), альбом 16:9 — дорога-волна MapPath (пройденная часть ярче), кружки-«конфеты»
                         (пройденные — палитра блоков, звёзды; текущий — зелёный, кольцо на PULSE_SHOT; закрытые —
                         с замком), «потолок», счёт и «домой»; текущий — на FOCUS_AT высоты окна
  G19_3_lab.png          «Лаборатория» (19.3b, STYLE 11.5; только отладочная сборка): экран без отметок (ru), с
                         отметками и звёздами (en, tr — правила переведены, названия нет), меню с таблеткой
                         «ЛАБОРАТОРИЯ» под «УРОВНЯМИ» — карточки механик (шапка, правило, ряд LabRow), пояснение,
                         «домой»
  G13_5_toasts.png       Toast: одна строка, две строки (портрет 720×1280), альбом 16:9 (2276×1280 — виртуальный
                         экран Godot при окне 16:9, высота всегда 1280) — капсула StyleBoxFlat «toast»

  G13_7_background.png   фон (13.7, Background + background.gdshader; с 19.7 — «шёлковый вихрь»): эталон
                         A2.background (фигуры) | вихрь при TIME 0 и 30 с | победа (свет ярче) | альбом 16:9; в
                         консоли — сверка средних цветов, скорость витков при SPEED и SPEED_CALM, скачок на стыке
                         TIME (должен быть ≈ 0)

Фон всех кадров — шейдер фона при TIME = 0 (до 13.7 был столбец пикселей эталона).
Чего нет: TIME у лучей = 0 (начальный поворот), конфетти — один случайный залп с постоянным зерном.
Места внутри карточки — константы WinPanel и узлы win_panel.tscn (читаются из файлов, не переписаны).
"""
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layout_model as lm      # noqa: E402
import shader_preview as sp    # noqa: E402

ROOT = sp.ROOT
FRAMES = sp.FRAMES
BLACK = sp.DIGIT_FONT                    # Nunito 1000
XBOLD = sp.UI_FONT                       # Nunito 800 (шрифт темы по умолчанию)
WIN_GD = "scenes/ui/win_panel.gd"
INK = sp.INK
DEEP = sp.DEEP


# ---------------------------------------------------------------- чтение сцен, темы и констант

def gd(path, name):
    """Значение const: число, Vector2 / Color или простое выражение из чисел («9.0 / 110.0»)."""
    raw = sp.gd_const(path, name)
    try:
        return sp.gd_value(raw)
    except ValueError:
        expr = raw.split("#")[0].strip()
        if not re.fullmatch(r"[\d.\s+\-*/()]+", expr):
            raise
        return float(eval(expr))


def gd_tex(path, name):
    """const NAME: Texture2D = preload(…) или Array[Texture2D] = [preload(…), …] -> пути PNG от корня проекта."""
    src = open(os.path.join(ROOT, path), encoding="utf-8").read()
    m = re.search(r"const\s+%s\s*:\s*(Array\[Texture2D\]\s*=\s*\[.*?\n\]|Texture2D\s*=\s*preload\([^)]*\))" % name, src, re.S)
    return [os.path.join(ROOT, p_) for p_ in re.findall(r'preload\("res://([^"]+)"\)', m.group(1))]


_PNG_CACHE = {}


def png_rgba(path):
    if path not in _PNG_CACHE:
        _PNG_CACHE[path] = Image.open(path).convert("RGBA")
    return _PNG_CACHE[path]


def gd_list(path, name):
    """const NAME: Array[...] = [ ... ] — числа или Vector2(…)."""
    src = open(os.path.join(ROOT, path), encoding="utf-8").read()
    raw = re.search(r"const\s+%s\s*:\s*Array\[\w+\]\s*=\s*(\[.*?\])" % name, src, re.S).group(1)
    body = raw[raw.index("[") + 1:raw.rindex("]")]
    vecs = re.findall(r"Vector2\(([^)]*)\)", body)
    if vecs:
        return [tuple(float(x) for x in v.split(",")) for v in vecs]
    return [float(x) for x in body.split(",") if x.strip()]


def tscn_nodes(path):
    """Узлы .tscn: имя -> словарь свойств (строки как в файле)."""
    out, cur = {}, None
    for line in open(os.path.join(ROOT, path), encoding="utf-8"):
        line = line.rstrip("\n")
        m = re.match(r'\[node name="([^"]+)"', line)
        if m:
            cur = out.setdefault(m.group(1), {})
            pm = re.search(r'parent="([^"]*)"', line)
            cur["_parent"] = pm.group(1) if pm else ""
            continue
        if line.startswith("["):
            cur = None
            continue
        if cur is not None and " = " in line:
            k, v = line.split(" = ", 1)
            cur[k] = v
    return out


def node_rect(n):
    l, t = float(n.get("offset_left", 0)), float(n.get("offset_top", 0))
    return (l, t, float(n.get("offset_right", 0)) - l, float(n.get("offset_bottom", 0)) - t)


def theme():
    """main_theme.tres: «Тип/раздел/имя» -> значение (Color — кортеж, числа — float, шрифт — путь)."""
    src = open(os.path.join(ROOT, "theme", "main_theme.tres"), encoding="utf-8").read()
    fonts = dict((i, p) for p, i in re.findall(r'\[ext_resource type="FontFile" path="res://([^"]+)" id="([^"]+)"\]', src))
    out = {}
    for k, v in re.findall(r"^([A-Za-z]+/[a-z_]+/[a-z_]+) = (.+)$", src[src.index("[resource]"):], re.M):
        m = re.match(r"Color\((.*)\)", v)
        if m:
            out[k] = tuple(float(x) for x in m.group(1).split(","))
            continue
        m = re.match(r'ExtResource\("([^"]+)"\)', v)
        if m and m.group(1) in fonts:
            out[k] = os.path.join(ROOT, fonts[m.group(1)])
            continue
        try:
            out[k] = float(v)
        except ValueError:
            out[k] = v
    return out


TH = theme()


def th(type_, kind, name, default=None):
    return TH.get("%s/%s/%s" % (type_, kind, name), default)


def font_of(type_):
    return th(type_, "fonts", "font", XBOLD)


def text_w(text, path, size):
    return sp._font(path, size).getlength(text)


def label(cv, text, cx, cy, type_, size=None, outline=None, shadow_y=None, color=None, alpha=1.0):
    """Label типа темы type_ по центру (cx, cy): заливка, обводка (полная толщина), тень (обведённая)."""
    fs = size or int(th(type_, "font_sizes", "font_size", 30))
    o = th(type_, "constants", "outline_size", 0) if outline is None else outline
    sy = th(type_, "constants", "shadow_offset_y", 1) if shadow_y is None else shadow_y
    fill = color or th(type_, "colors", "font_color", (1, 1, 1, 1))
    oc = th(type_, "colors", "font_outline_color", (0, 0, 0, 1))[:3]
    sh = th(type_, "colors", "font_shadow_color", (0, 0, 0, 0))
    sp.draw_digit(cv, text, cx, cy, fs, fill, oc, o, sh, (0, sy), alpha, font_path=font_of(type_))


# ---------------------------------------------------------------- картинки: поворот, тень по альфе

def png_layer(name, box, scale=4):
    """PNG иконки размером box×box (как TextureRect STRETCH_SCALE), float RGBA с премультипликацией, ×scale."""
    n = int(round(box * scale))
    src = Image.open(os.path.join(sp.ICONS, name + ".png")).convert("RGBA").resize((n, n), Image.LANCZOS)
    a = np.asarray(src, dtype=float) / 255.0
    a[..., :3] *= a[..., 3:4]
    return a


def blit(cv, layer, scale, pivot, at, angle_deg=0.0):
    """Слой (премультипликация, ×scale) с точкой pivot (px слоя /scale) — в точку at холста, поворот angle
    (по часовой, как rotation_degrees в Godot)."""
    from scipy.ndimage import affine_transform
    h, w = layer.shape[:2]
    th_ = math.radians(angle_deg)
    c, s = math.cos(th_), math.sin(th_)
    R = max(w, h)
    # Холст-участок вокруг at, ×scale; обратное отображение: участок -> слой.
    half = int(math.ceil(R / scale)) + 2
    X0, Y0 = int(math.floor(at[0])) - half, int(math.floor(at[1])) - half
    N = 2 * half * scale
    px, py = pivot[0] * scale, pivot[1] * scale
    ox, oy = (at[0] - X0) * scale, (at[1] - Y0) * scale
    # точка участка (row=y, col=x) -> слой: q = Rot(−θ)·(p − o) + pivot
    # dx, dy — смещение от o на участке; в слое (обратный поворот): lx = c·dx + s·dy, ly = −s·dx + c·dy.
    mat = np.array([[c, -s], [s, c]])          # (ly, lx) = mat · (dy, dx)
    offset = np.array([py, px]) - mat @ np.array([oy, ox])
    out = np.zeros((N, N, 4))
    for i in range(4):
        out[..., i] = affine_transform(layer[..., i], mat, offset=offset, output_shape=(N, N), order=1,
                                       mode="constant", cval=0.0)
    small = out.reshape(N // scale, scale, N // scale, scale, 4).mean(axis=(1, 3))
    a = small[..., 3:4]
    rgba = np.concatenate([np.where(a > 1e-6, small[..., :3] / np.maximum(a, 1e-6), 0.0), a], axis=2)
    cv.over(X0, Y0, rgba)


def with_tex_shadow(layer, scale, offset, blur, shade, strength):
    """TexShadow под картинкой: альфа, размытая (σ blur) и сдвинутая на offset (px родителя), цвет shade.
    Возвращает слой с полями под тень (премультипликация) и сдвиг начала (px /scale)."""
    from scipy.ndimage import gaussian_filter, shift
    m = int(math.ceil((blur * 3 + max(abs(offset[0]), abs(offset[1]))) * scale))
    h, w = layer.shape[:2]
    big = np.zeros((h + 2 * m, w + 2 * m, 4))
    big[m:m + h, m:m + w] = layer
    a = gaussian_filter(big[..., 3], blur * scale)
    a = shift(a, (offset[1] * scale, offset[0] * scale), order=1)
    sa = a * strength
    out = np.zeros_like(big)
    out[..., :3] = np.asarray(shade[:3]) * sa[..., None]
    out[..., 3] = sa
    # картинка поверх тени (премультипликация)
    out = big + out * (1.0 - big[..., 3:4])
    return out, m / scale


# ---------------------------------------------------------------- поле на месте победы

def draw_board_solved(cv, frame, cell_px, n):
    """Board уровня n целиком решённый (все блоки на месте), рамка frame (с губой) и клетка cell_px."""
    cols, rows, rects = sp.load_level(n)
    s = cell_px / sp.CELL
    px = 1.0 / s
    ox, oy = frame[0] + sp.BD["PAD"], frame[1] + sp.BD["PAD"]
    m = (sp.BD["FRAME_MARGIN"] + sp.BD["PAD"]) * px
    fw, fh = cols * sp.CELL + 2 * m, rows * sp.CELL + 2 * m + sp.BD["FRAME_DEPTH"] * px
    sp.draw_rect(cv, "board", ox - m * s, oy - m * s, fw, fh, s, (1, 1, 1, 1), {
        "frame_size": (fw, fh), "grid": (float(cols), float(rows)), "px": px, "margin": sp.BD["FRAME_MARGIN"],
        "pad": sp.BD["PAD"], "rim": sp.BD["RIM"], "lip": sp.BD["FRAME_DEPTH"]})
    for i in sorted(range(len(rects)), key=lambda j: (rects[j][1], rects[j][0])):
        rx, ry, rw, rh, nnx, nny = rects[i]
        sp.draw_block(cv, ox + rx * cell_px, oy + ry * cell_px, s, rw, rh, rw * rh, (nnx - rx, nny - ry), False)
    return cols, rows


# ---------------------------------------------------------------- конфетти (Confetti.burst + step)

CF = {k: gd("scripts/confetti.gd", k) for k in
      ("COUNT", "DOT_SHARE", "SOFT_SHARE", "ALPHA", "STRIP", "DOT", "SIZE_K", "SPEED", "DRAG", "GRAVITY", "SWAY",
       "SWAY_FREQ", "SPIN", "FLIP", "LIFE", "FADE")}
CF_AREAS = [int(x) for x in gd_list("scripts/confetti.gd", "AREAS")]


def draw_confetti(cv, origin, age, seed=7):
    rng = np.random.default_rng(seed)
    u = lambda a, b: float(rng.uniform(a, b))   # noqa: E731
    parts = []
    for i in range(int(CF["COUNT"])):
        dot = rng.random() < CF["DOT_SHARE"]
        soft = rng.random() < CF["SOFT_SHARE"]
        k = u(*CF["SIZE_K"])
        sz = (CF["DOT"] * k, CF["DOT"] * k) if dot else (CF["STRIP"][0] * u(*CF["SIZE_K"]), CF["STRIP"][1] * k)
        a = u(-math.pi * 1.08, math.pi * 0.08)
        col = (1.0, 1.0, 1.0) if i % 8 == 7 else sp.color_for(CF_AREAS[int(rng.integers(len(CF_AREAS)))])[:3]
        v = u(*CF["SPEED"])
        parts.append(dict(pos=np.array(origin, float), vel=np.array([math.cos(a), math.sin(a)]) * v,
                          angle=u(0, math.tau), spin=u(-CF["SPIN"], CF["SPIN"]), flip=u(0, math.tau),
                          flip_speed=0.0 if dot else u(*CF["FLIP"]), sway=u(*CF["SWAY"]),
                          sway_freq=u(*CF["SWAY_FREQ"]), phase=u(0, math.tau), size=sz, color=col,
                          soft=soft, dot=dot, life=u(*CF["LIFE"])))
    dt = 1.0 / 60.0
    for _ in range(int(round(age / dt))):
        damp = math.exp(-CF["DRAG"] * dt)
        for p in parts:
            p["vel"] = p["vel"] * damp + np.array([0.0, CF["GRAVITY"] * dt])
            p["pos"] = p["pos"] + p["vel"] * dt
            p["angle"] += p["spin"] * dt
            p["flip"] += p["flip_speed"] * dt
    for p in parts:
        if age >= p["life"] or p["pos"][1] > cv.h + 60:
            continue
        alpha = CF["ALPHA"] * min(max((p["life"] - age) / CF["FADE"], 0.0), 1.0)
        sway = p["sway"] * (1 - math.exp(-2 * age)) * math.sin(age * p["sway_freq"] + p["phase"])
        flip = max(abs(math.cos(p["flip"])), 0.18) if p["flip_speed"] > 0 else 1.0
        cx, cy = p["pos"][0] + sway, p["pos"][1]
        w, h = p["size"][0] * flip, p["size"][1]
        r = (w / 3.0) if not p["dot"] else w / 2.0
        edge = 2.0 if p["soft"] else 0.4                       # текстура вдвое крупнее кусочка: 4 / 2, 0,75 / 2
        R = int(math.ceil(max(w, h) / 2 + edge * 2 + 2))
        xs, ys = np.meshgrid(np.arange(-R, R) + 0.5 + math.floor(cx) - cx, np.arange(-R, R) + 0.5 + math.floor(cy) - cy)
        c, s = math.cos(p["angle"]), math.sin(p["angle"])
        lx, ly = c * xs + s * ys, -s * xs + c * ys
        qx, qy = np.abs(lx) - w / 2 + r, np.abs(ly) - h / 2 + r
        d = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r
        cov = 1.0 - np.clip((d + edge) / (2 * edge), 0, 1) ** 2 * (3 - 2 * np.clip((d + edge) / (2 * edge), 0, 1))
        rgba = np.zeros(cov.shape + (4,))
        rgba[..., :3] = p["color"]
        rgba[..., 3] = cov * alpha
        cv.over(int(math.floor(cx)) - R, int(math.floor(cy)) - R, rgba)


# ---------------------------------------------------------------- карточка CandyCard и кнопки

CC = {k: gd("scripts/candy_card.gd", k) for k in ("RADIUS", "LIP", "LINE", "SHADOW_OFFSET", "SHADOW_BLUR", "SHADOW_ALPHA")}
HEADS = {"orange": ("#FFC247", "#FF7B3A", "#E0602A"), "violet": ("#8B6CF6", "#6A42E4", "#5530C8"), "none": None}


def hex_rgba(h, a=1.0):
    """"RRGGBB" → (r, g, b, a) 0..1."""
    return (int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, a)


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)) + (1.0,)


def draw_card(cv, rect, head="violet", head_h=104.0):
    """CandyCard: узел Body с card.gdshader на поля body_margin вокруг лица rect (x, y, w, h)."""
    mx = math.ceil(CC["SHADOW_BLUR"] * 3 + abs(CC["SHADOW_OFFSET"][0]))
    my = math.ceil(CC["SHADOW_BLUR"] * 3 + CC["SHADOW_OFFSET"][1] + CC["LIP"])
    x, y, w, h = rect
    bw, bh = w + 2 * mx, h + 2 * my
    params = {"rect_size": (bw, bh), "face_lo": (mx, my), "face_hi": (mx + w, my + h), "radius": CC["RADIUS"],
              "lip": CC["LIP"], "line": CC["LINE"], "shadow_offset": CC["SHADOW_OFFSET"],
              "shadow_blur": CC["SHADOW_BLUR"], "shadow_color": DEEP + (CC["SHADOW_ALPHA"],)}
    cols = HEADS[head]
    if cols is None:
        params["head"] = 0.0
    else:
        params.update(head=head_h, head_top=hexc(cols[0]), head_bottom=hexc(cols[1]), head_line=hexc(cols[2]))
    sp.draw_rect(cv, "card", x - mx, y - my, bw, bh, 1.0, (1, 1, 1, 1), params)


PB = {k: gd("scripts/pill_button.gd", k) for k in
      ("DEPTH_K", "SHADOW_K", "BLUR_K", "SHADOW_ALPHA", "SHADOW_DARK", "OUTLINE_K", "TEXT_SHADOW_Y", "TEXT_SHADOW_ALPHA",
       "FIT_PAD_K", "MIN_FONT_K", "SUB_K", "TWO_LINE_Y")}
TONES = {"green": ("#2FCF78", "#12733F", (1, 1, 1)), "red": ("#FF5A4E", "#A3163A", (1, 1, 1)),
         "light": ("#EEE8FF", "#6A42E4", hexc("#6A42E4")[:3]), "gold": ("#FFC21A", "#A85400", (1, 1, 1))}


def pill_caption_size(text, fs, light, w, h):
    """PillButton.caption_size: fs, а не влезает в w без FIT_PAD_K·h с каждой стороны (с обводкой) — меньше
    шагом 2, не меньше MIN_FONT_K·fs."""
    room = w - 2 * PB["FIT_PAD_K"] * h
    lo = math.ceil(fs * PB["MIN_FONT_K"])
    while fs - 2 >= lo and text_w(text, font_of("PillButton"), fs) + (0 if light else round(2 * PB["OUTLINE_K"] * fs)) > room:
        fs -= 2
    return fs


def draw_pill_button(cv, rect, text, tone="green", font_size=None, subtitle=""):
    """PillButton: тело block.gdshader (одна клетка высотой с кнопку, скругление ½) и подпись над губой;
    subtitle — вторая строка (PillButton.subtitle: размер SUB_K, центры строк TWO_LINE_Y высоты лица)."""
    x, y, w, h = rect
    col, ink, txt = TONES[tone]
    col = hexc(col)
    m = math.ceil(h * (PB["BLUR_K"] * 3 + PB["SHADOW_K"]))
    sh = tuple(c * (1 - PB["SHADOW_DARK"]) for c in col[:3]) + (PB["SHADOW_ALPHA"],)
    sp.draw_rect(cv, "block", x - m, y - m, w + 2 * m, h + 2 * m, 1.0, col, {
        "rect_size": (w, h), "cells": (1.0, 1.0), "margin": float(m), "cell": float(h), "radius": 0.5, "gap": 0.0,
        "depth": PB["DEPTH_K"], "num_center": (w / 2, h / 2), "seams": 0.0, "flash": 0.0, "px": 1.0,
        "shadow_offset": (0.0, PB["SHADOW_K"] * h), "shadow_blur": PB["BLUR_K"] * h, "shadow_color": sh})
    base = font_size or int(th("PillButton", "font_sizes", "font_size", 46))
    inkc = hexc(ink)
    tsh = inkc[:3] + ((PB["TEXT_SHADOW_ALPHA"] if tone != "light" else 0.0),)
    fh = h * (1 - PB["DEPTH_K"])
    lines = [(text, base, fh / 2)] if not subtitle else \
        [(text, base, PB["TWO_LINE_Y"][0] * fh), (subtitle, round(base * PB["SUB_K"]), PB["TWO_LINE_Y"][1] * fh)]
    for t, b, cy in lines:
        fs = pill_caption_size(t, b, tone == "light", w, h)
        o = 0 if tone == "light" else round(2 * PB["OUTLINE_K"] * fs)
        sp.draw_digit(cv, t, x + w / 2, y + cy, fs, tuple(txt) + (1.0,), inkc[:3], o, tsh,
                      (0, PB["TEXT_SHADOW_Y"]), font_path=font_of("PillButton"))


def link_width(text, type_="CardLink"):
    """Ширина ссылки CardLink по содержимому: иконка icon_max_width + h_separation + текст."""
    fs = int(th(type_, "font_sizes", "font_size", 26))
    return th(type_, "constants", "icon_max_width", 34) + th(type_, "constants", "h_separation", 10) + \
        text_w(text, font_of(type_), fs)


def draw_link(cv, cx, cy, h, text, icon, type_="CardLink"):
    """CardLink шириной по содержимому (WinPanel / SettingsPanel), по центру cx: иконка слева, текст за ней."""
    fs = int(th(type_, "font_sizes", "font_size", 26))
    ic = th(type_, "constants", "icon_max_width", 34)
    sep = th(type_, "constants", "h_separation", 10)
    w = link_width(text, type_)
    x0 = cx - w / 2
    sp.draw_png(cv, icon, x0, cy - ic / 2, ic, ic)
    tw = text_w(text, font_of(type_), fs)
    sp.draw_digit(cv, text, x0 + ic + sep + tw / 2, cy, fs, th(type_, "colors", "font_color"), (0, 0, 0), 0,
                  (0, 0, 0, 0), (0, 0), font_path=font_of(type_))


# ---------------------------------------------------------------- окно победы

def win_title(text, size, room_w):
    """WinPanel._layout_title (портрет — одна строка): размер, при котором строка влезает."""
    fs = size
    mn = int(gd(WIN_GD, "TITLE_MIN_SIZE"))
    while fs > mn and text_w(text, BLACK, fs) > room_w - 2 * sp.HH["TITLE_OUTLINE"] * fs:
        fs -= 2
    return fs


def render_win(level=20, stars=3, points=120, total=2460, head="НОВЫЙ РЕКОРД!", w=720, h=1280):
    cv = sp.background(w, h, win=True)   # Background на победе: свет ярче (Background.set_win)
    L = lm.compute(w, h, lm.pick(w, h, False))
    cols, rows, _ = sp.load_level(level)
    frame, cell_px = lm.board_fit(L, cols, rows, win=True)

    # WinBackdrop: лучи и свечение от центра рамки поля, размер — от большей стороны (WinBackdrop.set_center).
    c = (frame[0] + frame[2] / 2, frame[1] + frame[3] / 2)
    k = max(1.0, max(frame[2], frame[3]) / gd("scenes/game/win_backdrop.gd", "FRAME_BOARD"))
    gr = gd("scenes/game/win_backdrop.gd", "GLOW_RADIUS")
    sp.draw_rect(cv, "win_rays", 0, 0, w, h, 1.0, (1, 1, 1, 1), {
        "rect_size": (w, h), "center": c, "radius": gd("scenes/game/win_backdrop.gd", "RAYS_RADIUS") * k,
        "glow_radius": (gr[0] * k, gr[1] * k)})
    # Конфетти: залп через CONFETTI_DELAY после показа; кадр — когда всё окно уже проявилось (~1,4 с).
    draw_confetti(cv, c, 1.4 - gd("scenes/game/win_backdrop.gd", "CONFETTI_DELAY"))

    # Content: поле (панели и лоток уехали).
    draw_board_solved(cv, frame, cell_px, level)

    # WinPanel: заголовок по центру win_title.
    tr = L["win_title"]
    text = "УРОВЕНЬ %d ПРОЙДЕН!" % level
    fs = win_title(text, L["win_title_size"], tr[2])
    sp.draw_label(cv, text, tr[0] + tr[2] / 2, tr[1] + tr[3] / 2, fs, (1.0, 1.0, 1.0), INK, sp.HH["TITLE_OUTLINE"],
                  DEEP, sp.HH["TITLE_SHADOW_ALPHA"], sp.HH["TITLE_SHADOW"])

    # Карточка и её содержимое (места — win_panel.tscn и константы WinPanel, от верха-левого угла лица).
    card = L["win_card"]
    cx0, cy0 = card[0], card[1]
    draw_card(cv, card, "orange")
    N = tscn_nodes("scenes/ui/win_panel.tscn")
    hx, hy, hw, hh = node_rect(N["Head"])
    label(cv, head, cx0 + hx + hw / 2, cy0 + hy + hh / 2, "WinHead")

    # Строка очков: звезда SCORE_STAR и «+N» (WinPanel._place_score_row).
    score_y, score_star, gap = gd(WIN_GD, "SCORE_Y"), gd(WIN_GD, "SCORE_STAR"), gd(WIN_GD, "SCORE_GAP")
    fit, star_cy = gd(WIN_GD, "STAR_FIT"), gd(WIN_GD, "STAR_CY")
    sh_col, sh_a = gd(WIN_GD, "STAR_SHADOW"), gd(WIN_GD, "STAR_SHADOW_ALPHA")
    st = "+" + "{:,}".format(points).replace(",", "\u00a0")
    sfs = int(th("WinScore", "font_sizes", "font_size", 48))
    tw = text_w(st, font_of("WinScore"), sfs)
    x0 = (card[2] - (score_star + gap + tw)) / 2
    box = 1.75 * score_star * 0.5 / fit
    q = score_star * 0.5 / 56.0
    lay = png_layer("star", box)
    lay, mpad = with_tex_shadow(lay, 4, (0.0, 8 * q), 10 * q, sh_col, sh_a)
    scy = score_y - score_star * 0.04
    blit(cv, lay, 4, (mpad + box / 2, mpad + box * star_cy), (cx0 + x0 + score_star / 2, cy0 + scy))
    label(cv, st, cx0 + x0 + score_star + gap + tw / 2, cy0 + score_y, "WinScore")

    total_txt = "Всего очков: " + "{:,}".format(total).replace(",", "\u00a0")
    tx, ty, tw_, th_ = node_rect(N["TotalLabel"])
    fs_total = int(N["TotalLabel"].get("theme_override_font_sizes/font_size", th("CardText", "font_sizes", "font_size")))
    label(cv, total_txt, cx0 + tx + tw_ / 2, cy0 + ty + th_ / 2, "CardText", size=fs_total)

    nx, ny, nw, nh = node_rect(N["NextButton"])
    draw_pill_button(cv, (cx0 + nx, cy0 + ny, nw, nh), "ДАЛЕЕ", "green")
    rx, ry, rw, rh = node_rect(N["ReplayButton"])
    draw_link(cv, cx0 + card[2] / 2, cy0 + ry + rh / 2, rh, "Переиграть уровень", "restart")

    # Звёзды на кромке: TextureRect со своей тенью (TexShadow — внутри, поворачивается со звездой).
    centers, radii, tilts = gd_list(WIN_GD, "STAR_CENTERS"), gd_list(WIN_GD, "STAR_R"), gd_list(WIN_GD, "STAR_TILT")
    for i in range(3):
        r = radii[i]
        box = 1.75 * r / fit
        q = r / 56.0
        lay = png_layer("star" if i < stars else "star_empty", box)
        lay, mpad = with_tex_shadow(lay, 4, (0.0, 8 * q), 10 * q, sh_col, sh_a)
        blit(cv, lay, 4, (mpad + box / 2, mpad + box * star_cy), (cx0 + centers[i][0], cy0 + centers[i][1]), tilts[i])
    return cv.image(), L


# ---------------------------------------------------------------- игра под окнами (пауза, сообщения)

def game_background(w, h, theme=None):
    """Фон игры и меню (13.7): Background — shaders/background.gdshader на весь экран, TIME = 0; theme — тема
    главы (19.5c, униформы шейдера), None — фон по умолчанию."""
    return sp.background(w, h, theme=theme)


def draw_board_partial(cv, frame, cell_px, n, placed):
    """Board уровня n: блоки placed стоят, на остальных числах — гнёзда (без магнита: ничего не несут)."""
    cols, rows, rects = sp.load_level(n)
    s = cell_px / sp.CELL
    px = 1.0 / s
    ox, oy = frame[0] + sp.BD["PAD"], frame[1] + sp.BD["PAD"]
    m = (sp.BD["FRAME_MARGIN"] + sp.BD["PAD"]) * px
    fw, fh = cols * sp.CELL + 2 * m, rows * sp.CELL + 2 * m + sp.BD["FRAME_DEPTH"] * px
    sp.draw_rect(cv, "board", ox - m * s, oy - m * s, fw, fh, s, (1, 1, 1, 1), {
        "frame_size": (fw, fh), "grid": (float(cols), float(rows)), "px": px, "margin": sp.BD["FRAME_MARGIN"],
        "pad": sp.BD["PAD"], "rim": sp.BD["RIM"], "lip": sp.BD["FRAME_DEPTH"]})
    covered = set()
    for i in placed:
        rx, ry, rw, rh, _, _ = rects[i]
        covered |= {(cx, cy) for cx in range(rx, rx + rw) for cy in range(ry, ry + rh)}
    for rx, ry, rw, rh, nnx, nny in rects:
        if (nnx, nny) in covered:
            continue
        area = rw * rh
        bx, by = nnx * sp.CELL, nny * sp.CELL
        sp.draw_rect(cv, "nest", ox + (bx - 48) * s, oy + (by - 48) * s, sp.CELL + 96, sp.CELL + 96, s,
                     sp.color_for(area), {"px": px, "ring": 0.0, "margin": 48.0})
        sp.draw_digit(cv, str(area), ox + (bx + 50) * s, oy + (by + 50) * s, 40 * s, sp.color_for(area),
                      sp.darkened(sp.color_for(area), 0.42), sp.CL["DIGIT_OUTLINE"] * s,
                      sp.darkened(sp.color_for(area), 0.5)[:3] + (0.35,), (0, 2 * s))
    for i in sorted(placed, key=lambda j: (rects[j][1], rects[j][0])):
        rx, ry, rw, rh, nnx, nny = rects[i]
        sp.draw_block(cv, ox + rx * cell_px, oy + ry * cell_px, s, rw, rh, rw * rh, (nnx - rx, nny - ry), False)


def render_game(w=720, h=1280, level=20, placed=None, theme=None):
    """Экран игры без несомого блока: поле (часть блоков стоит), шапка, плашка, кнопки; лоток — только портрет
    720×1280 (sp.draw_tray рисует места портрета)."""
    land = lm.pick(w, h, False)
    L = lm.compute(w, h, land)
    cv = game_background(w, h, theme)
    cols, rows, _ = sp.load_level(level)
    frame, cell_px = lm.board_fit(L, cols, rows)
    draw_board_partial(cv, frame, cell_px, level, sp.PLACED if placed is None else placed)
    if not land and (w, h) == (720, 1280):
        sp.draw_tray(cv)
        sp.draw_buttons(cv)
    else:
        d = sp.BTN_D
        tx, ty, tw, th_ = L["top_bar"]
        ax, ay, aw, ah = L["actions"]
        for name, cx, cy in (("pause", tx + d / 2, ty + th_ / 2), ("restart", tx + tw - d / 2, ty + th_ / 2),
                             ("undo", ax + d / 2, ay + ah / 2), ("hint", ax + aw - d / 2, ay + ah / 2)):
            sp.draw_button(cv, cx, cy, d, name, "3" if name == "hint" else None)
    sp.draw_header(cv, L, level=level)
    sp.draw_pill(cv, L)
    return cv, L


# ---------------------------------------------------------------- меню (13.6, STYLE 11.1)

MENU_GD = "scenes/menu/menu.gd"
MENU_TSCN = "scenes/menu/menu.tscn"


def po(locale):
    """locale/<locale>.po: msgid -> msgstr (однострочные записи; ru — без файла, строки как в коде)."""
    path = os.path.join(ROOT, "locale", locale + ".po")
    if not os.path.exists(path):
        return {}
    src = open(path, encoding="utf-8").read()
    return {a: b for a, b in re.findall(r'^msgid "(.+)"\nmsgstr "(.*)"$', src, re.M) if b}


def tscn_vec(n, key, default=(0.0, 0.0)):
    m = re.match(r"Vector2i?\(([^,]+),\s*([^)]+)\)", n.get(key, ""))
    return (float(m.group(1)), float(m.group(2))) if m else default


LOGO_GD = "scenes/menu/menu_logo.gd"
SPARKS_GD = "scenes/menu/logo_sparkles.gd"


class Layer:
    """Прозрачный слой (RGBA, без премультипликации на выходе): блок рисуется на нём, потом поворачивается."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3))
        self.a = np.zeros((h, w, 1))

    def over(self, x0, y0, rgba):
        h, w = rgba.shape[:2]
        X0, Y0 = max(0, x0), max(0, y0)
        X1, Y1 = min(self.w, x0 + w), min(self.h, y0 + h)
        if X1 <= X0 or Y1 <= Y0:
            return
        src = rgba[Y0 - y0:Y1 - y0, X0 - x0:X1 - x0]
        a = src[..., 3:4]
        self.rgb[Y0:Y1, X0:X1] = src[..., :3] * a + self.rgb[Y0:Y1, X0:X1] * (1.0 - a)
        self.a[Y0:Y1, X0:X1] = a + self.a[Y0:Y1, X0:X1] * (1.0 - a)

    def pil(self):
        a = np.clip(self.a, 1e-6, 1.0)
        rgb = np.where(self.a > 1e-6, self.rgb / a, 0.0)
        return Image.fromarray((np.concatenate([np.clip(rgb, 0, 1), np.clip(self.a, 0, 1)], 2) * 255 + 0.5)
                               .astype(np.uint8), "RGBA")


def sparkle_points():
    """LogoSparkles.POINTS: (x, y, радиус, фаза) в координатах логотипа."""
    src = open(os.path.join(ROOT, SPARKS_GD), encoding="utf-8").read()
    body = re.search(r"const POINTS: Array\[Vector4\] = \[(.*?)\n\]", src, re.S).group(1)
    return [tuple(float(x) for x in v.split(",")) for v in re.findall(r"Vector4\(([^)]*)\)", body)]


def draw_menu_logo(cv, x0, y0, N):
    """MenuLogo в кадре: левый верх логотипа (x0, y0) на экране. Свечение и лучи (узел Halo, TIME 0), блоки
    LogoBlocks на местах, двойка (Block2) — над своим местом «в руке»: выше на HOVER_UP, ×LIFT_SCALE, наклон
    HOVER_TILT, тень «поднят» (кадр — середина парения, без покачивания); искры LogoSparkles при t = 0."""
    lw, lh = (gd(LOGO_GD, "CELL") * v for v in gd(LOGO_GD, "GRID"))
    glow, blur, r = gd(LOGO_GD, "HALO_GLOW"), gd(LOGO_GD, "HALO_BLUR"), gd(LOGO_GD, "HALO_R")
    half = (max(r, glow[0] + 2 * blur), max(r, glow[1] + 2 * blur))
    shift = gd(LOGO_GD, "HALO_SHIFT")
    cx, cy = x0 + lw / 2 + shift[0], y0 + lh / 2 + shift[1]
    sp.draw_rect(cv, "win_rays", cx - half[0], cy - half[1], 2 * half[0], 2 * half[1], 1.0, (1, 1, 1, 1), {
        "rect_size": (2 * half[0], 2 * half[1]), "center": half, "radius": r, "rays": gd(LOGO_GD, "HALO_RAYS"),
        "ray_alpha": gd(LOGO_GD, "HALO_RAY_ALPHA"), "glow_radius": glow, "glow_blur": blur,
        "glow_color": gd(LOGO_GD, "HALO_COLOR")})
    k = tscn_vec(N["LogoBlocks"], "scale", (1.0, 1.0))[0]
    for name in ("Block3L", "Block4", "Block3R", "Block2"):    # порядок детей LogoBlocks в menu.tscn
        bx, by, _, _ = node_rect(N[name])
        bw, bh = (int(v) for v in tscn_vec(N[name], "cells"))
        if name != "Block2":
            sp.draw_block(cv, x0 + bx * k, y0 + by * k, k, bw, bh, bw * bh, None, False)
            continue
        s = k * sp.B["LIFT_SCALE"]
        pad = int(sp.B["MARGIN_LIFTED"] * 2 + 40)
        layer = Layer(int(bw * sp.CELL * s) + 2 * pad, int(bh * sp.CELL * s) + 2 * pad)
        sp.draw_block(layer, pad, pad, s, bw, bh, bw * bh, None, True)
        im = layer.pil().rotate(-math.degrees(gd(LOGO_GD, "HOVER_TILT")), resample=Image.BICUBIC, expand=True)
        hx = x0 + (bx + bw * sp.CELL / 2) * k
        hy = y0 + (by - gd(LOGO_GD, "HOVER_UP") + bh * sp.CELL / 2) * k
        cv.over(int(round(hx - im.width / 2)), int(round(hy - im.height / 2)), np.asarray(im).astype(float) / 255)
    tex = Image.open(os.path.join(ROOT, "assets", "icons", "sparkle.png")).convert("RGBA")
    col = gd(SPARKS_GD, "COLOR")
    tw_k, a_min = gd(SPARKS_GD, "TWINKLE"), gd(SPARKS_GD, "ALPHA_MIN")
    for x, y, rad, ph in sparkle_points():
        tw = 0.5 + 0.5 * math.sin(ph)
        rr = rad * (1.0 - tw_k * (1.0 - tw))
        d = max(2, int(round(2 * rr)))
        arr = np.asarray(tex.resize((d, d), Image.LANCZOS)).astype(float) / 255
        arr[..., :3] = np.array(col[:3])
        arr[..., 3] *= a_min + (1.0 - a_min) * tw
        cv.over(int(round(x0 + x - d / 2)), int(round(y0 + y - d / 2)), arr)
    return (x0, y0, lw, lh)


def render_menu(w=720, h=1280, level=12, score=2340, locale="ru", streak=4, lab=False):
    """Меню: колонна Content 720×1280 по центру экрана (логотип MenuLogo — только графика, «ИГРАТЬ» в две строки),
    у краёв экрана — счёт со звездой и шестерёнка. Места — узлы menu.tscn и константы menu_logo.gd; кадр — после
    появления: двойка парит над местом, «ИГРАТЬ» ×1."""
    N = tscn_nodes(MENU_TSCN)
    T = po(locale)
    tr = lambda t: T.get(t, t)    # noqa: E731
    cv = game_background(w, h)
    c = N["Content"]
    ox, oy = w / 2 + float(c["offset_left"]), h / 2 + float(c["offset_top"])
    lx, ly, _, _ = node_rect(N["Logo"])
    logo = draw_menu_logo(cv, ox + lx, oy + ly, N)
    pb = N["PlayButton"]
    x, y, rw, rh = node_rect(pb)
    draw_pill_button(cv, (ox + x, oy + y, rw, rh), tr(pb["text"].strip('"')), "green",
                     tscn_int(pb, "theme_override_font_sizes/font_size", 46), tr("УРОВЕНЬ %d").replace("%d", str(level)))
    # 18.1 и 18.2b: светлые «ЗАДАЧА ДНЯ» (вторая строка — серия) и «УРОВНИ» (tone = 2 — PillButton.Tone.LIGHT).
    for name, sub in (("DailyButton", tr("СЕРИЯ %d").replace("%d", str(streak))), ("LevelsButton", "")):
        b = N[name]
        x, y, rw, rh = node_rect(b)
        tone = ("green", "red", "light")[tscn_int(b, "tone", 0)]
        draw_pill_button(cv, (ox + x, oy + y, rw, rh), tr(b["text"].strip('"')), tone,
                         tscn_int(b, "theme_override_font_sizes/font_size", 46), sub)
    if lab:   # 19.3b: отладочная сборка — светлая таблетка «ЛАБОРАТОРИЯ» (menu.gd: LAB_RECT, LAB_FONT; без перевода)
        r = gd(MENU_GD, "LAB_RECT")
        draw_pill_button(cv, (ox + r[0], oy + r[1], r[2], r[3]), gd_str(LAB_GD, "NAME"), "light", int(gd(MENU_GD, "LAB_FONT")))
    sy = draw_score_row(cv, N["ScoreRow"], w, score, int(gd(MENU_GD, "SCORE_SIZE")), locale)
    g = N["SettingsButton"]
    gx = w + (float(g["offset_left"]) + float(g["offset_right"])) / 2
    gy = (float(g["offset_top"]) + float(g["offset_bottom"])) / 2
    sp.draw_button(cv, gx, gy, float(g["offset_right"]) - float(g["offset_left"]), "settings")
    lb = N["LeadersButton"]   # 18.3: «лидеры» в левом верхнем углу (trophy.png — лист 5, 10.10)
    sp.draw_button(cv, (float(lb["offset_left"]) + float(lb["offset_right"])) / 2,
                   (float(lb["offset_top"]) + float(lb["offset_bottom"])) / 2,
                   float(lb["offset_right"]) - float(lb["offset_left"]), "trophy")
    return cv.image(), {"logo": tuple(round(v) for v in logo), "logo_cx": round(logo[0] + logo[2] / 2, 1),
                        "gear": (gx, gy), "score_y": sy}


def draw_score_row(cv, r, w, score, ss, locale):
    """Верхний ряд (ScoreRow — верх экрана во всю ширину): счёт со звездой по центру, как
    HudHeader.layout_score_row. Возвращает высоту середины строки."""
    sy = (float(r["offset_top"]) + float(r["offset_bottom"])) / 2
    text = "{:,}".format(score).replace(",", "\u00a0" if locale == "ru" else ("." if locale == "tr" else ","))
    tw = text_w(text, BLACK, ss)
    x0 = w / 2 - (sp.HH["TEXT_X"] * ss + tw) / 2
    box = sp.HH["STAR_W"] * ss / sp.HH["STAR_FIT"]
    sp.draw_star(cv, x0 + sp.HH["STAR_X"] * ss, sy - sp.HH["STAR_RISE"] * ss - box / 2, box, sp.HH["STAR_R"] * ss)
    sp.draw_label(cv, text, x0 + sp.HH["TEXT_X"] * ss + tw / 2, sy, ss, sp.SCORE, INK, sp.HH["SCORE_OUTLINE"],
                  DEEP, sp.HH["SCORE_SHADOW_ALPHA"], sp.HH["SCORE_SHADOW"])
    return sy


# ---------------------------------------------------------------- карта уровней (18.2)

MAP_GD = "scenes/map/map_path.gd"
LEVEL_MAP_GD = "scenes/map/level_map.gd"
LEVEL_MAP_TSCN = "scenes/map/level_map.tscn"
PULSE_SHOT = 0.3     # кольцо текущего в кадре — на 0,3 цикла (в игре расходится непрерывно)


def gd_color(path, name):
    """const NAME := Color("#RRGGBB") или Color(r, g, b[, a]) — (r, g, b, a) 0…1."""
    raw = sp.gd_const(path, name).split("#")[0] if '"#' not in sp.gd_const(path, name) else sp.gd_const(path, name)
    m = re.search(r'Color\("#([0-9A-Fa-f]{6})"\)', raw)
    if m:
        return hexc("#" + m.group(1))[:3] + (1.0,)
    v = sp.gd_value(raw)
    return tuple(v) + ((1.0,) if len(v) == 3 else ())


def block_colors():
    src = open(os.path.join(ROOT, "scripts/palette.gd"), encoding="utf-8").read()
    body = re.search(r"const BLOCK_COLORS: Array\[Color\] = \[(.*?)\n\]", src, re.S).group(1)
    return [tuple(float(x) for x in c.split(",")) + (1.0,) for c in re.findall(r"Color\(([^)]*)\)", body)]


def render_map(w=720, h=1280, current=12, score=2340, locale="ru", stars=None):
    """LevelMap: фон, MapPath в прокрутке (текущий на FOCUS_AT высоты окна, прокрутка в пределах карты), «потолок»
    Ceiling, счёт по центру верхнего ряда, «домой» — CandyButton в левом верхнем углу. MapPath._draw: дорога
    (пройденная часть ROAD_DONE, впереди ROAD_AHEAD), кружки сверху вниз — тень, губа, лицо, блик, число с
    обводкой; под пройденными — звёзды; закрытые — светлые с замком. Сглаживание — рисунок ×SS и уменьшение.
    Главы (19.5c, tools/chapters_model.py): зазор CHAPTER_GAP перед первым уровнем главы (MapPath.rise), плашка
    главы между дорогой и кружками (MapPath._draw_banner), фон — тема главы посреди экрана (LevelMap.update_theme)."""
    import chapters_model
    cm = chapters_model.Model()
    B = {k: gd(MAP_GD, k) for k in ("BANNER_H", "BANNER_FONT", "BANNER_PAD", "BANNER_MIN_W", "BANNER_DEPTH",
                                    "BANNER_SHADOW", "BANNER_RIM_W", "BANNER_LOCKED_ALPHA", "FIRST_BANNER_DROP")}
    rim = gd_color(MAP_GD, "BANNER_RIM")
    tr_ = po(locale)
    head_fmt = gd_str("scripts/chapters.gd", "HEAD")
    M = {k: gd(MAP_GD, k) for k in ("STEP", "AMP", "PERIOD", "PAD_TOP", "PAD_BOTTOM", "AHEAD", "NODE_D", "CURRENT_D",
                                    "LIP_DARK", "SHADOW_K", "FACE_Y_K", "NODE_PNG_K", "LOCKED_ALPHA", "DIGIT_K",
                                    "DIGIT_OUTLINE_K", "DIGIT_BASE_K", "DIGIT_ROOM_K", "ROAD_W", "ROAD_SAMPLES",
                                    "STAR_SIZE", "STAR_DX", "STAR_LIFT", "STAR_DROP", "PULSE_GROW", "PULSE_W",
                                    "PULSE_ALPHA", "LOCK_K", "LOCK_ALPHA")}
    C = {k: gd_color(MAP_GD, k) for k in ("ROAD_DONE", "ROAD_AHEAD", "CURRENT_COLOR")}
    # Кружки — картинки листа 6 (MapPath.PASSED_TEX, CURRENT_TEX, LOCKED_TEX).
    passed_tex = [png_rgba(p_) for p_ in gd_tex(MAP_GD, "PASSED_TEX")]
    current_tex = png_rgba(gd_tex(MAP_GD, "CURRENT_TEX")[0])
    locked_tex = png_rgba(gd_tex(MAP_GD, "LOCKED_TEX")[0])
    shade = gd_color("scripts/palette.gd", "SHADE")
    palette = block_colors()
    passed = gd_list(MAP_GD, "PASSED_AREAS")
    stars = stars or {}
    count = current + int(M["AHEAD"])
    total = M["PAD_TOP"] + M["PAD_BOTTOM"] + cm.rise(count)
    mh = max(float(h), total)
    focus = gd(LEVEL_MAP_GD, "FOCUS_AT")

    def road(t):
        k = t - 1.0
        return (w * 0.5 + M["AMP"] * math.sin(k * 2 * math.pi / M["PERIOD"]), mh - M["PAD_BOTTOM"] - cm.rise(t))

    scroll = min(max(0.0, round(road(current)[1] - h * focus)), mh - h)
    SS = 3
    over = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))

    def to_px(c):
        return tuple(int(round(v * 255)) for v in c)

    def put(draw_fn, box):
        """Фигура на своём прозрачном слое (box — x0, y0, x1, y1 в px экрана), смешивание поверх."""
        x0, y0 = int(math.floor(box[0])) - 2, int(math.floor(box[1])) - 2
        x1, y1 = int(math.ceil(box[2])) + 2, int(math.ceil(box[3])) + 2
        if x1 <= 0 or y1 <= 0 or x0 >= w or y0 >= h:
            return
        lay = Image.new("RGBA", ((x1 - x0) * SS, (y1 - y0) * SS), (0, 0, 0, 0))
        draw_fn(ImageDraw.Draw(lay), lambda x, y: ((x - x0) * SS, (y - y0) * SS))
        dx, dy = x0 * SS, y0 * SS
        src = (max(0, -dx), max(0, -dy))
        over.alpha_composite(lay, dest=(max(0, dx), max(0, dy)), source=src)

    def circle(c, r, col):
        put(lambda d, P: d.ellipse([*P(c[0] - r, c[1] - r), *P(c[0] + r, c[1] + r)], fill=to_px(col)),
            (c[0] - r, c[1] - r, c[0] + r, c[1] + r))

    lock_src = Image.open(os.path.join(sp.ICONS, "lock.png")).convert("RGBA")

    def png_over(src, c, side, alpha=1.0):
        """Картинка side×side с центром c (draw_texture_rect, modulate.a = alpha) — на слой over."""
        n_ = int(round(side * SS))
        im = src.resize((n_, n_), Image.LANCZOS)
        if alpha < 1.0:
            im.putalpha(im.getchannel("A").point(lambda v: int(round(v * alpha))))
        x0, y0 = int(round((c[0] - side / 2) * SS)), int(round((c[1] - side / 2) * SS))
        if x0 + n_ <= 0 or y0 + n_ <= 0 or x0 >= w * SS or y0 >= h * SS:
            return
        sx, sy = max(0, -x0), max(0, -y0)
        im = im.crop((sx, sy, min(n_, w * SS - x0), min(n_, h * SS - y0)))
        over.alpha_composite(im, dest=(max(0, x0), max(0, y0)))

    def darkened(col, a):
        return tuple(v * (1 - a) for v in col[:3]) + (col[3],)

    # Видимые уровни (MapPath.visible_range) и дорога на один шаг за край.
    base = mh - M["PAD_BOTTOM"]
    hi = min(count, max(1, cm.level_below(base - scroll + M["CURRENT_D"], count) + 1))
    lo = min(count, max(1, cm.level_below(base - (scroll + h) - M["CURRENT_D"], count)))
    a, b = max(1, lo - 1), min(count, hi + 1)
    done, ahead = [], []
    n_s = int(M["ROAD_SAMPLES"])
    for i in range((b - a) * n_s + 1):
        t = a + i / n_s
        x, y = road(t)
        if t <= current + 0.001:
            done.append((x, y - scroll))
        if t >= current - 0.001:
            ahead.append((x, y - scroll))
    for pts, col in ((done, C["ROAD_DONE"]), (ahead, C["ROAD_AHEAD"])):
        if len(pts) >= 2:
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            rw = M["ROAD_W"]
            put(lambda d, P, pts=pts, col=col: d.line([P(*p) for p in pts], fill=to_px(col), width=int(rw * SS),
                                                      joint="curve"),
                (min(xs) - rw, min(ys) - rw, max(xs) + rw, max(ys) + rw))
    # Плашки глав (MapPath._draw_banners): глава начинается на видимом уровне или на следующем за верхним.
    bf = ImageFont.truetype(BLACK, int(B["BANNER_FONT"]))
    banners = []
    for n in range(lo, min(count, hi + 1) + 1):
        if not cm.is_start(n):
            continue
        name = cm.names[cm.index(n)]
        text = tr_.get(head_fmt, head_fmt).replace("%d", str(cm.number(n)), 1).replace("%s", tr_.get(name, name), 1)
        tw = bf.getlength(text)
        bw = min(max(tw + 2 * B["BANNER_PAD"], B["BANNER_MIN_W"]), max(B["BANNER_MIN_W"], w - 40.0))
        if n <= 1:
            cy = base + B["FIRST_BANNER_DROP"] - scroll
        else:
            cy = base - (cm.rise(n - 1) + cm.rise(n)) * 0.5 - scroll
        col = hex_rgba(cm.theme(n)["top"])
        al = B["BANNER_LOCKED_ALPHA"] if n > current else 1.0
        bh, dp = B["BANNER_H"], B["BANNER_DEPTH"]
        fx0, fy0 = w * 0.5 - bw / 2, cy - bh / 2 - dp / 2
        fs = int(B["BANNER_FONT"])
        if tw > bw - 2 * B["BANNER_PAD"]:
            fs = math.floor(B["BANNER_FONT"] * (bw - 2 * B["BANNER_PAD"]) / tw)
        banners.append((n, text, round(bw)))

        def banner(dr, P, fx0=fx0, fy0=fy0, bw=bw, bh=bh, dp=dp, col=col, al=al, text=text, fs=fs):
            rr = bh / 2 * SS
            sh = shade[:3] + (shade[3] * al,)
            dr.rounded_rectangle([*P(fx0, fy0 + dp + B["BANNER_SHADOW"]), *P(fx0 + bw, fy0 + dp + B["BANNER_SHADOW"] + bh)],
                                 radius=rr, fill=to_px(sh))
            dr.rounded_rectangle([*P(fx0, fy0 + dp), *P(fx0 + bw, fy0 + dp + bh)], radius=rr,
                                 fill=to_px(darkened(col, M["LIP_DARK"])[:3] + (al,)))
            rw_ = B["BANNER_RIM_W"]
            dr.rounded_rectangle([*P(fx0, fy0), *P(fx0 + bw, fy0 + bh)], radius=rr, fill=to_px(rim[:3] + (rim[3] * al,)))
            dr.rounded_rectangle([*P(fx0 + rw_, fy0 + rw_), *P(fx0 + bw - rw_, fy0 + bh - rw_)], radius=rr - rw_ * SS,
                                 fill=to_px(col[:3] + (al,)))
            f = ImageFont.truetype(BLACK, fs * SS)
            o = round(fs * M["DIGIT_OUTLINE_K"])
            dr.text(P(fx0 + bw / 2, fy0 + bh / 2 + fs * M["DIGIT_BASE_K"]), text, font=f,
                    fill=(255, 255, 255, int(round(255 * al))), anchor="ms", stroke_width=int(round(o * SS / 2)),
                    stroke_fill=to_px(darkened(col, 0.45)[:3] + (al,)))
        put(banner, (fx0 - 4, fy0 - 4, fx0 + bw + 4, fy0 + dp + B["BANNER_SHADOW"] + bh + 4))
    star_marks = []
    for n in range(hi, lo - 1, -1):
        x, y = road(n)
        c = (x, y - scroll)
        d = M["CURRENT_D"] if n == current else M["NODE_D"]
        rad = d / 2
        if n > current:
            # MapPath.draw_node_png: белый кружок LOCKED_ALPHA; _draw_lock: lock.png (замок — 240 из 256 по высоте)
            # высотой LOCK_K диаметра.
            png_over(locked_tex, c, d * M["NODE_PNG_K"], M["LOCKED_ALPHA"])
            png_over(lock_src, c, d * M["LOCK_K"] * 256 / 240, M["LOCK_ALPHA"])
            continue
        col = C["CURRENT_COLOR"] if n == current else palette[int(passed[(n - 1) % len(passed)]) - 1]
        if n == current:
            g = M["PULSE_GROW"] * PULSE_SHOT
            ra = rad + g
            pw = M["PULSE_W"]
            ring = to_px((1, 1, 1, M["PULSE_ALPHA"] * (1 - PULSE_SHOT)))
            put(lambda dr, P, c=c, ra=ra, pw=pw, ring=ring: dr.ellipse(
                [*P(c[0] - ra - pw / 2, c[1] - ra - pw / 2), *P(c[0] + ra + pw / 2, c[1] + ra + pw / 2)],
                outline=ring, width=int(round(pw * SS))), (c[0] - ra - pw, c[1] - ra - pw, c[0] + ra + pw, c[1] + ra + pw))
        # Тень — круг SHADE ниже на SHADOW_K·Ø, кружок — картинка (диск 240/256 стороны), лицо выше на FACE_Y_K·Ø.
        circle((c[0], c[1] + d * M["SHADOW_K"]), rad, shade)
        tex = current_tex if n == current else passed_tex[(n - 1) % len(passed_tex)]
        png_over(tex, c, d * M["NODE_PNG_K"])
        face = (c[0], c[1] - d * M["FACE_Y_K"])
        # Число: Nunito 1000, ужатие по DIGIT_ROOM_K, базовая линия ниже центра лица на DIGIT_BASE_K·размер.
        text = str(n)
        fs = round(d * M["DIGIT_K"])
        tw = ImageFont.truetype(BLACK, fs).getlength(text)
        if tw > d * M["DIGIT_ROOM_K"]:
            fs = math.floor(fs * d * M["DIGIT_ROOM_K"] / tw)
        f = ImageFont.truetype(BLACK, fs * SS)
        ink = to_px(darkened(col, 0.45)[:3] + (1.0,))
        o = round(fs * M["DIGIT_OUTLINE_K"])
        put(lambda dr, P, face=face, f=f, fs=fs, ink=ink, o=o, text=text: dr.text(
            P(face[0], face[1] + fs * M["DIGIT_BASE_K"]), text, font=f, fill=(255, 255, 255, 255), anchor="ms",
            stroke_width=int(round(o * SS / 2)), stroke_fill=ink), (face[0] - d, face[1] - d, face[0] + d, face[1] + d))
        if n < current:
            star_marks.append((c, rad, int(stars.get(n, 0))))
    small = over.resize((w, h), Image.LANCZOS)
    # Фон — тема главы уровня, чей кружок ближе всех к середине экрана (MapPath.level_near).
    mid_h = base - (scroll + h * 0.5)
    near = cm.level_below(mid_h, count)
    if near < count and abs(cm.rise(near + 1) - mid_h) < abs(cm.rise(near) - mid_h):
        near += 1
    cv = game_background(w, h, cm.shader(near))
    cv.over(0, 0, np.asarray(small).astype(float) / 255)
    sz = M["STAR_SIZE"]
    for c, rad, got in star_marks:
        for i in range(3):
            sp.draw_png(cv, "star" if i < got else "star_empty", c[0] + (i - 1) * M["STAR_DX"] - sz / 2,
                        c[1] + rad + M["STAR_DROP"] * sz - (M["STAR_LIFT"] if i == 1 else 0.0), sz, sz)
    # «Потолок» (Ceiling): градиент сверху вниз, высота offset_bottom.
    N = tscn_nodes(LEVEL_MAP_TSCN)
    src = open(os.path.join(ROOT, LEVEL_MAP_TSCN), encoding="utf-8").read()
    gc = [float(v) for v in re.search(r"colors = PackedColorArray\(([^)]*)\)", src).group(1).split(",")]
    ch = int(float(N["Ceiling"]["offset_bottom"]))
    t = np.linspace(0.0, 1.0, ch)[:, None]
    grad = np.zeros((ch, w, 4))
    for j in range(4):
        grad[..., j] = (gc[j] * (1 - t) + gc[4 + j] * t)
    cv.over(0, 0, grad)
    draw_score_row(cv, N["ScoreRow"], w, score, int(gd(LEVEL_MAP_GD, "SCORE_SIZE")), locale)
    hb = N["HomeButton"]
    hx = (float(hb["offset_left"]) + float(hb["offset_right"])) / 2
    hy = (float(hb["offset_top"]) + float(hb["offset_bottom"])) / 2
    sp.draw_button(cv, hx, hy, float(hb["offset_right"]) - float(hb["offset_left"]), "home")
    cur_y = road(current)[1] - scroll
    return cv.image(), {"levels": (lo, hi), "scroll": scroll, "current_y": round(cur_y), "focus": round(cur_y / h, 3),
                        "theme": cm.number(near), "banners": banners}


# ---------------------------------------------------------------- экран лидеров (18.3)

LEADERS_TSCN = "scenes/leaders/leaders.tscn"
ROWS_GD = "scenes/leaders/leader_rows.gd"
MEDAL_PNG = ("medal_gold", "medal_silver", "medal_bronze")   # LeaderRows.MEDAL_TEX
LB_GD = "scripts/leaderboard_data.gd"

# Состояния кадра G18_3 (строки — как отдаёт LeaderboardData.rows после fit_ranks; (0, …) — разрыв «…»).
_TOP_NAMES = ["Мария", "Alex_Pro", "", "Котик-Мурлыкин Великолепный", "Сергей В.", "Лиза", "Puzzle Fox",
              "Дмитрий", "Оля К.", "Нурлан"]
_TOP_SCORES = [48720, 45310, 41990, 39050, 36400, 33870, 31220, 29880, 27410, 25960]


def leaders_state(kind):
    """kind: player40 — вошёл, 40-е место (10 первых, разрыв, 39–41); guest — гость (10 первых, «Войдите», «ВОЙТИ»);
    streak — вкладка «СЕРИЯ», игрок на 10-м; local — вне Яндекса (своя строка «—», местный счёт)."""
    top = [(i + 1, n, sc, False) for i, (n, sc) in enumerate(zip(_TOP_NAMES, _TOP_SCORES))]
    if kind == "player40":
        return {"tab": "score", "rows": top + [(0, "", 0, False), (39, "Игорь К.", 12510, False),
                                             (40, "Анна", 12480, True), (41, "Bulut", 12400, False)],
                "status": "", "login": False}
    if kind == "guest":
        return {"tab": "score", "rows": top, "status": "Войдите, чтобы попасть в таблицу", "login": True}
    if kind == "streak":
        days = [(1, "Мария", 41), (2, "Alex_Pro", 37), (3, "Лиза", 30), (0, "", 0), (10, "Анна", 9),
                (11, "Puzzle Fox", 8), (12, "", 8), (13, "Оля К.", 7)]
        return {"tab": "streak", "rows": [(r, n, sc, r == 10) for r, n, sc in days], "status": "", "login": False}
    return {"tab": "score", "rows": [(0, "Вы", 321, True)], "status": "Таблица лидеров — в Яндекс Играх",
            "login": False}


def _hex_colors(path, name):
    src = open(os.path.join(ROOT, path), encoding="utf-8").read()
    line = re.search(r"const %s\b[^\n]*" % name, src).group(0)
    return [tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)) for h in re.findall(r'Color\("#([0-9A-Fa-f]{6})"\)', line)]


def render_leaders(w=720, h=1280, locale="ru", kind="player40"):
    """Экран лидеров (LeadersScreen + LeaderRows._draw): вкладки, карточка «ЛИДЕРЫ», строки по константам
    leader_rows.gd внутри полей CandyCard (тема), строка состояния и «ВОЙТИ» — по состоянию kind (leaders_state)."""
    N = tscn_nodes(LEADERS_TSCN)
    T = po(locale)
    tr = lambda text: T.get(text, text)  # noqa: E731
    st = leaders_state(kind)
    cv = game_background(w, h)
    content = N["Content"]
    ox, oy = w / 2 + float(content["offset_left"]), h / 2 + float(content["offset_top"])

    def rect(name):
        x, y, rw, rh = node_rect(N[name])
        return ox + x, oy + y, rw, rh

    tabs = (("ScoreTab", "ОЧКИ", "score"), ("StreakTab", "СЕРИЯ", "streak"))
    for node, text, key in tabs:
        draw_pill_button(cv, rect(node), tr(text), "green" if st["tab"] == key else "light",
                         tscn_int(N[node], "theme_override_font_sizes/font_size", 40))

    card = rect("Card")
    title_h = tscn_size(N["Title"])[1]
    draw_card(cv, card, "violet", title_h)
    label(cv, tr("ЛИДЕРЫ"), card[0] + card[2] / 2, card[1] + title_h / 2, "CardTitle")

    # Rows: внутри полей CandyCard (StyleBoxEmpty темы), под заголовком (VBox separation 0).
    src = open(os.path.join(ROOT, "theme", "main_theme.tres"), encoding="utf-8").read()
    box = re.search(r'id="candy_card"\]\n(.*?)\n\n', src, re.S).group(1)
    marg = {k: float(v) for k, v in re.findall(r"content_margin_(\w+) = ([\d.]+)", box)}
    rx = card[0] + marg.get("left", 0.0)
    rw = card[2] - marg.get("left", 0.0) - marg.get("right", 0.0)
    ry = card[1] + marg.get("top", 0.0) + title_h
    C = {k: gd(ROWS_GD, k) for k in ("ROW_H", "PAD_Y", "RANK_W", "MEDAL_D", "SCORE_W", "NAME_GAP", "FONT_SIZE",
                                     "RANK_SIZE", "MEDAL_FACE_Y", "ME_BLEED", "ME_RADIUS", "MUTED_ALPHA")}
    fs, rs = int(C["FONT_SIZE"]), int(C["RANK_SIZE"])
    ink = sp.gd_value(sp.gd_const("scripts/palette.gd", "INK"))[:3]
    me_col = sp.gd_value(sp.gd_const("scripts/palette.gd", "SCORE"))[:3]
    medals = _hex_colors(ROWS_GD, "MEDALS")
    name_w = max(0.0, rw - C["RANK_W"] - C["NAME_GAP"] * 2 - C["SCORE_W"])
    sep = "," if locale == "en" else ("." if locale == "tr" else "\u00a0")

    # Плашка игрока и медали — геометрия с суперсэмплингом ×3.
    S = 3
    overlay = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    z = lambda v: int(round(v * S))  # noqa: E731
    rgba = lambda c, a=1.0: tuple(int(round(v * 255)) for v in c) + (int(round(a * 255)),)  # noqa: E731
    row_y = lambda i: ry + C["PAD_Y"] + C["ROW_H"] * i  # noqa: E731
    for i, (rank, _n, _sc, me) in enumerate(st["rows"]):
        y = row_y(i)
        if me:
            d.rounded_rectangle([z(rx - C["ME_BLEED"]), z(y + 2), z(rx + rw + C["ME_BLEED"]), z(y + C["ROW_H"] - 2)],
                                radius=z(C["ME_RADIUS"]), fill=rgba(me_col))
        if 1 <= rank <= len(medals):
            # LeaderRows._draw_rank: medal_*.png, видимый диаметр MEDAL_D (в PNG — 240 из 256).
            cx, cy = rx + C["RANK_W"] / 2, y + C["ROW_H"] / 2
            side = C["MEDAL_D"] * 256 / 240
            med = Image.open(os.path.join(sp.ICONS, MEDAL_PNG[rank - 1] + ".png")).convert("RGBA")
            med = med.resize((z(side), z(side)), Image.LANCZOS)
            overlay.alpha_composite(med, dest=(z(cx - side / 2), z(cy - side / 2)))
    cv.over(0, 0, np.asarray(overlay.resize((w, h), Image.Resampling.LANCZOS)).astype(float) / 255.0)

    muted = ink + (C["MUTED_ALPHA"],)
    for i, (rank, name, points, me) in enumerate(st["rows"]):
        y = row_y(i)
        cy = y + C["ROW_H"] / 2
        if rank == 0 and not me:
            sp.draw_label(cv, "…", rx + rw / 2, cy, fs, muted, (0, 0, 0), 0, (0, 0, 0), 0, 0, path=BLACK)
            continue
        rank_cx = rx + C["RANK_W"] / 2
        if 1 <= rank <= len(medals):
            dark = tuple(v * 0.55 for v in medals[rank - 1])
            sp.draw_label(cv, str(rank), rank_cx, cy + C["MEDAL_D"] * 256 / 240 * C["MEDAL_FACE_Y"], rs, (1, 1, 1, 1), dark, 6.0 / (2 * rs), (0, 0, 0), 0, 0,
                          path=BLACK)
        else:
            sp.draw_label(cv, str(rank) if rank > 0 else "—", rank_cx, cy, rs, ink + (0.7,), (0, 0, 0), 0,
                          (0, 0, 0), 0, 0, path=BLACK)
        shown = name.strip() or "Игрок"
        if shown in ("Игрок", "Вы"):
            shown = tr(shown)
        if text_w(shown, XBOLD, fs) > name_w:   # TextLine OVERRUN_TRIM_ELLIPSIS
            while shown and text_w(shown.rstrip() + "…", XBOLD, fs) > name_w:
                shown = shown[:-1]
            shown = shown.rstrip() + "…"
        nx = rx + C["RANK_W"] + C["NAME_GAP"]
        sp.draw_label(cv, shown, nx + text_w(shown, XBOLD, fs) / 2, cy, fs, ink + (1.0,), (0, 0, 0), 0,
                      (0, 0, 0), 0, 0, path=XBOLD)
        digits = str(points)
        groups = []
        while len(digits) > 3:
            groups.insert(0, digits[-3:])
            digits = digits[:-3]
        formatted = sep.join([digits] + groups)
        sp.draw_label(cv, formatted, rx + rw - text_w(formatted, BLACK, fs) / 2, cy, fs, ink + (1.0,), (0, 0, 0), 0,
                      (0, 0, 0), 0, 0, path=BLACK)

    status = tr(st["status"]) if st["status"] else ""
    sl = rect("StatusLabel")
    if status:
        label(cv, status, sl[0] + sl[2] / 2, sl[1] + sl[3] / 2, "CardText", size=28, color=(1, 1, 1, 1))
    if st["login"]:
        login = rect("LoginButton")
        draw_pill_button(cv, login, tr("ВОЙТИ"), "light",
                         tscn_int(N["LoginButton"], "theme_override_font_sizes/font_size", 44))
    home = N["HomeButton"]
    hx = (float(home["offset_left"]) + float(home["offset_right"])) / 2
    hy = (float(home["offset_top"]) + float(home["offset_bottom"])) / 2
    sp.draw_button(cv, hx, hy, float(home["offset_right"]) - float(home["offset_left"]), "home")
    last = row_y(len(st["rows"]))
    return cv.image(), {"card": tuple(round(v) for v in card), "rows": len(st["rows"]),
                        "rows_box": (round(rx), round(ry), round(rw), round(last - ry + C["PAD_Y"])),
                        "name_w": round(name_w), "status": status}


# ---------------------------------------------------------------- «Лаборатория» (19.3b)

LAB_GD = "scripts/lab_levels.gd"
LAB_DATA_GD = "scripts/lab_levels_data.gd"
LAB_SCREEN_GD = "scenes/lab/lab.gd"
LAB_TSCN = "scenes/lab/lab.tscn"
LAB_ROW_GD = "scenes/lab/lab_row.gd"


def gd_str(path, name):
    """Строковая константа: const NAME := "…"."""
    src = open(os.path.join(ROOT, path), encoding="utf-8").read()
    return re.search(r'const %s\b[^=]*=\s*"((?:[^"\\]|\\.)*)"' % name, src).group(1).replace("\\n", "\n")


def lab_mechanics():
    """[(ключ, название, правило-msgid, уровней)] в порядке LabLevels.mechanics() (DATA.ORDER)."""
    src = open(os.path.join(ROOT, LAB_GD), encoding="utf-8").read()
    titles = dict(re.findall(r'^\t"(\w+)": "([^"]+)",$', src[src.index("const TITLES"):], re.M))
    body = src[src.index("static func rule("):]
    rules = dict(re.findall(r'"(\w+)":\s*\n\s*return "([^"]+)"', body))
    data = open(os.path.join(ROOT, LAB_DATA_GD), encoding="utf-8").read()
    order = re.findall(r'"(\w+)"', re.search(r"const ORDER[^=]*=\s*\[([^\]]*)\]", data).group(1))
    out = []
    for m in order:
        block = re.search(r'"%s":\s*\[(.*?)\]' % m, data[data.index("const LEVELS"):], re.S)
        out.append((m, titles.get(m, m), rules.get(m, ""), len(re.findall(r'"[^"]+"', block.group(1))) if block else 0))
    return out


def render_lab(w=720, h=1280, locale="ru", done=None):
    """LabScreen: фон, заголовок LabLevels.NAME, карточки механик в VBox Cards (CandyCard: шапка HEAD_H с названием,
    поля PAD_X / PAD_BOTTOM; правило CardText RULE_SIZE по центру места RULE_H; ряд LabRow — кружки-«конфеты»
    как MapPath, пройденные зелёные со звёздами), пояснение NOTE, «домой». done — {(механика, номер): звёзды}."""
    N = tscn_nodes(LAB_TSCN)
    T = po(locale)
    tr = lambda text: T.get(text, text)  # noqa: E731
    done = done or {}
    L = {k: gd(LAB_SCREEN_GD, k) for k in ("HEAD_H", "TITLE_SIZE", "PAD_X", "PAD_BOTTOM", "RULE_SIZE", "RULE_H")}
    R = {k: gd(LAB_ROW_GD, k) for k in ("NODE_D", "NODE_Y", "ROW_H", "STAR_SIZE", "STAR_DX", "STAR_LIFT")}
    M = {k: gd(MAP_GD, k) for k in ("SHADOW_K", "FACE_Y_K", "NODE_PNG_K", "DIGIT_K", "DIGIT_OUTLINE_K",
                                    "DIGIT_BASE_K", "DIGIT_ROOM_K", "STAR_DROP")}
    open_tex = png_rgba(gd_tex(LAB_ROW_GD, "OPEN_TEX")[0])
    done_tex = png_rgba(gd_tex(LAB_ROW_GD, "DONE_TEX")[0])
    open_col = _hex_colors(LAB_ROW_GD, "OPEN_COLOR")[0] + (1.0,)
    done_col = _hex_colors(LAB_ROW_GD, "DONE_COLOR")[0] + (1.0,)
    shade = gd_color("scripts/palette.gd", "SHADE")
    cv = game_background(w, h)
    content = N["Content"]
    ox, oy = w / 2 + float(content["offset_left"]), h / 2 + float(content["offset_top"])
    tl = node_rect(N["TitleLabel"])
    label(cv, gd_str(LAB_GD, "NAME"), ox + tl[0] + tl[2] / 2, oy + tl[1] + tl[3] / 2, "CardTitle",
          size=tscn_int(N["TitleLabel"], "theme_override_font_sizes/font_size", 48))
    cb = node_rect(N["Cards"])
    sep = tscn_int(N["Cards"], "theme_override_constants/separation", 4)
    card_h = L["HEAD_H"] + L["RULE_H"] + R["ROW_H"] + L["PAD_BOTTOM"]
    rule_fs = int(L["RULE_SIZE"])
    room = cb[2] - 2 * L["PAD_X"]
    cards, nodes, rule_lines = [], [], {}
    y = oy + cb[1]
    for m, title, rule, count in lab_mechanics():
        card = (ox + cb[0], y, cb[2], card_h)
        draw_card(cv, card, "violet", L["HEAD_H"])
        label(cv, title.upper(), card[0] + card[2] / 2, y + L["HEAD_H"] / 2, "CardTitle", size=int(L["TITLE_SIZE"]))
        lines = wrap_greedy(tr(rule), XBOLD, rule_fs, room)
        rule_lines[m] = len(lines)
        lh = line_h(rule_fs) + LABEL_SPACING
        top = y + L["HEAD_H"] + (L["RULE_H"] - (len(lines) * lh - LABEL_SPACING)) / 2
        for i, ln in enumerate(lines):
            label(cv, ln, card[0] + card[2] / 2, top + i * lh + line_h(rule_fs) / 2, "CardText", size=rule_fs)
        row_y = y + L["HEAD_H"] + L["RULE_H"]
        pitch = room / max(1, count)
        for i in range(1, count + 1):
            nodes.append(((card[0] + L["PAD_X"] + pitch * (i - 0.5), row_y + R["NODE_Y"]), i, int(done.get((m, i), 0))))
        cards.append(tuple(round(v) for v in card))
        y += card_h + sep
    # Кружки (как render_map): слой ×SS, тень, картинка листа 6, число с обводкой; звёзды — после.
    SS = 3
    over = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    dr = ImageDraw.Draw(over)
    to_px = lambda c: tuple(int(round(v * 255)) for v in c)  # noqa: E731
    P = lambda x, y_: (x * SS, y_ * SS)  # noqa: E731
    d = R["NODE_D"]
    rad = d / 2
    for (cx, cy), n, got in nodes:
        col = done_col if got else open_col
        layer = Image.new("RGBA", over.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).ellipse([*P(cx - rad, cy + d * M["SHADOW_K"] - rad), *P(cx + rad, cy + d * M["SHADOW_K"] + rad)],
                                      fill=to_px(shade))
        over = Image.alpha_composite(over, layer)
        side = int(round(d * M["NODE_PNG_K"] * SS))
        over.alpha_composite((done_tex if got else open_tex).resize((side, side), Image.LANCZOS),
                             dest=(int(round(cx * SS - side / 2)), int(round(cy * SS - side / 2))))
        fy = cy - d * M["FACE_Y_K"]
        text = str(n)
        fs = round(d * M["DIGIT_K"])
        tw = ImageFont.truetype(BLACK, fs).getlength(text)
        if tw > d * M["DIGIT_ROOM_K"]:
            fs = math.floor(fs * d * M["DIGIT_ROOM_K"] / tw)
        ink = to_px(tuple(v * 0.55 for v in col[:3]) + (1.0,))
        tx = Image.new("RGBA", over.size, (0, 0, 0, 0))
        ImageDraw.Draw(tx).text(P(cx, fy + fs * M["DIGIT_BASE_K"]), text, font=ImageFont.truetype(BLACK, fs * SS),
                                fill=(255, 255, 255, 255), anchor="ms",
                                stroke_width=int(round(round(fs * M["DIGIT_OUTLINE_K"]) * SS / 2)), stroke_fill=ink)
        over = Image.alpha_composite(over, tx)
    cv.over(0, 0, np.asarray(over.resize((w, h), Image.LANCZOS)).astype(float) / 255)
    sz = R["STAR_SIZE"]
    for (cx, cy), n, got in nodes:
        if got:
            for i in range(3):
                sp.draw_png(cv, "star" if i < got else "star_empty", cx + (i - 1) * R["STAR_DX"] - sz / 2,
                            cy + rad + M["STAR_DROP"] * sz - (R["STAR_LIFT"] if i == 1 else 0.0), sz, sz)
    nl = node_rect(N["NoteLabel"])
    note = gd_str(LAB_SCREEN_GD, "NOTE").split("\n")
    nfs = tscn_int(N["NoteLabel"], "theme_override_font_sizes/font_size", 26)
    nlh = line_h(nfs) + LABEL_SPACING
    ntop = oy + nl[1] + (nl[3] - (len(note) * nlh - LABEL_SPACING)) / 2
    note_w = 0.0
    for i, ln in enumerate(note):
        note_w = max(note_w, text_w(ln, XBOLD, nfs))
        sp.draw_digit(cv, ln, ox + nl[0] + nl[2] / 2, ntop + i * nlh + line_h(nfs) / 2, nfs, (1, 1, 1, 1), INK,
                      tscn_int(N["NoteLabel"], "theme_override_constants/outline_size", 8), (0, 0, 0, 0), (0, 0),
                      font_path=XBOLD)
    hb = N["HomeButton"]
    hx = (float(hb["offset_left"]) + float(hb["offset_right"])) / 2
    hy = (float(hb["offset_top"]) + float(hb["offset_bottom"])) / 2
    sp.draw_button(cv, hx, hy, float(hb["offset_right"]) - float(hb["offset_left"]), "home")
    last = cards[-1]
    return cv.image(), {"cards": cards, "bottom": last[1] + last[3], "cards_box_bottom": round(oy + cb[1] + cb[3]),
                        "rule_lines": rule_lines, "note": (round(ntop), round(note_w), round(nl[2])),
                        "pitch": round(room / 10, 1)}


# ---------------------------------------------------------------- пауза, настройки, подтверждение (13.5c)

SET_GD = "scenes/ui/settings_panel.gd"
SET_TSCN = "scenes/ui/settings_panel.tscn"
LINE_K = lm.LINE_K           # высота строки Nunito / размер (ascent + descent, typo-метрики)
LABEL_SPACING = 3.0          # Label line_spacing по умолчанию (Godot 4), у CardText в теме не задан


def line_h(size):
    return LINE_K * size


def wrap_greedy(text, path, size, room):
    """Label autowrap WORD_SMART: жадно по словам."""
    lines, cur = [], ""
    for word in text.split():
        probe = word if not cur else cur + " " + word
        if not cur or text_w(probe, path, size) <= room:
            cur = probe
        else:
            lines.append(cur)
            cur = word
    lines.append(cur)
    return lines


def panel_title_size(text):
    """SettingsPanel.title_size: от TITLE_SIZE шагом 2, пока не влезет в CARD_W − 2·CARD_PAD (с обводкой)."""
    room = gd(SET_GD, "CARD_W") - 2 * gd(SET_GD, "CARD_PAD")
    fs, mn = int(gd(SET_GD, "TITLE_SIZE")), int(gd(SET_GD, "TITLE_MIN_SIZE"))
    while fs > mn and text_w(text, font_of("CardTitle"), fs) + gd(SET_GD, "TITLE_OUTLINE") > room:
        fs -= 2
    return fs


def tscn_size(n):
    m = re.match(r"Vector2\(([^,]+),\s*([^)]+)\)", n.get("custom_minimum_size", "Vector2(0, 0)"))
    return float(m.group(1)), float(m.group(2))


def tscn_int(n, key, default):
    return int(float(n.get(key, default)))


def render_panel(mode="settings", w=720, h=1280, vibration=True, off=(), dev=True, rate=False):
    """SettingsPanel поверх экрана: mode — settings (меню), pause (игра) или confirm (подтверждение сброса).
    dev — таблетки разработчика (отладочная сборка, SettingsPanel.dev_tools); rate — «Оценить игру» (12.10b: в
    настройках после обучения, пока Яндекс разрешает оценку): золотая таблетка RateButton у низа RateBox, звёзды
    RateStars/Star* — от середины верха RateBox (offset из сцены).
    Места — контейнеры сцены (VBox / HBox, separation, custom_minimum_size), поля CandyCard из темы;
    высота карточки — по содержимому, от середины экрана (offset ±200, grow both)."""
    N = tscn_nodes(SET_TSCN)
    if mode == "pause":
        cv, _ = render_game(w, h)
    else:
        cv = game_background(w, h)   # меню в новом стиле — 13.6; под затемнением видно только фон
    dim = tuple(float(x) for x in re.match(r"Color\((.*)\)", N["Dim"]["color"]).group(1).split(","))
    cv.rgb = cv.rgb * (1 - dim[3]) + np.asarray(dim[:3]) * dim[3]

    src = open(os.path.join(ROOT, "theme", "main_theme.tres"), encoding="utf-8").read()
    box = re.search(r'id="candy_card"\]\n(.*?)\n\n', src, re.S).group(1)
    marg = {k: float(v) for k, v in re.findall(r"content_margin_(\w+) = ([\d.]+)", box)}
    pad_l, pad_r, pad_t, pad_b = (marg.get(k, 0.0) for k in ("left", "right", "top", "bottom"))
    sep_box = tscn_int(N["Box"], "theme_override_constants/separation", 4)
    sep_main = tscn_int(N["MainBox"], "theme_override_constants/separation", 4)
    sep_conf = tscn_int(N["ConfirmBox"], "theme_override_constants/separation", 4)
    sep_tog = tscn_int(N["Toggles"], "theme_override_constants/separation", 4)
    sep_lbl = tscn_int(N["MusicToggle"], "theme_override_constants/separation", 4)
    head_h = tscn_size(N["Title"])[1]
    card_w = max(gd(SET_GD, "CARD_W"), -2 * float(N["Card"]["offset_left"]))
    inner = card_w - pad_l - pad_r
    text_font = font_of("CardText")

    toggles = [("music_on", "Музыка"), ("sound_on", "Звуки")] + ([("vibration_on", "Вибрация")] if vibration else [])
    tfs = tscn_int(N["MusicLabel"], "theme_override_font_sizes/font_size", 30)
    bw, bh = tscn_size(N["MusicButton"])
    col_w = [max(bw, text_w(t, text_font, tfs)) for _, t in toggles]
    tog_h = bh + sep_lbl + line_h(tfs)

    close_w, close_h = tscn_size(N["CloseButton"])
    second_w, second_h = tscn_size(N["ResetButton"])
    motion_w, motion_h = tscn_size(N["MotionButton"])   # «Меньше движения» (этап 14)
    rate_w, rate_h = tscn_size(N["RateBox"])
    rbw, rbh = tscn_size(N["RateButton"])
    rate = rate and mode == "settings"
    home_h = max(tscn_size(N["HomeButton"])[1], line_h(th("CardLink", "font_sizes", "font_size", 26)))
    cfs = int(th("CardText", "font_sizes", "font_size", 30))
    conf_room = max(tscn_size(N["ConfirmText"])[0], inner)
    conf_text = "Уровни, звёзды и очки начнутся с нуля. Вернуть их будет нельзя."
    conf_lines = wrap_greedy(conf_text, text_font, cfs, conf_room)
    conf_h = len(conf_lines) * line_h(cfs) + (len(conf_lines) - 1) * LABEL_SPACING

    if mode == "confirm":
        rows = [conf_h, close_h, second_h]
        sep = sep_conf
    else:
        rows = [tog_h] + ([rate_h] if rate else []) + ([motion_h] if dev else []) + [close_h] + \
            ([home_h] if mode == "pause" else [second_h] if dev else [])
        sep = sep_main
    content_h = head_h + sep_box + sum(rows) + sep * (len(rows) - 1)
    card_h = max(-2 * float(N["Card"]["offset_top"]), pad_t + content_h + pad_b)
    cx0, cy0 = w / 2 - card_w / 2, h / 2 - card_h / 2
    card = (cx0, cy0, card_w, card_h)
    draw_card(cv, card, "violet", head_h)

    title = {"settings": "НАСТРОЙКИ", "pause": "ПАУЗА", "confirm": "СБРОСИТЬ ПРОГРЕСС?"}[mode]
    mid = cx0 + pad_l + inner / 2
    label(cv, title, mid, cy0 + pad_t + head_h / 2, "CardTitle", size=panel_title_size(title))
    y = cy0 + pad_t + head_h + sep_box
    if mode == "confirm":
        for i, s in enumerate(conf_lines):
            label(cv, s, mid, y + i * (line_h(cfs) + LABEL_SPACING) + line_h(cfs) / 2, "CardText")
        y += conf_h + sep
        draw_pill_button(cv, (mid - close_w / 2, y, close_w, close_h), "СБРОСИТЬ", "red")
        y += close_h + sep
        draw_pill_button(cv, (mid - second_w / 2, y, second_w, second_h), "ОТМЕНА", "light",
                         tscn_int(N["CancelResetButton"], "theme_override_font_sizes/font_size", 46))
        return cv.image(), card
    total = sum(col_w) + sep_tog * (len(col_w) - 1)
    x = mid - total / 2
    for (icon, text), cw in zip(toggles, col_w):
        sp.draw_button(cv, x + cw / 2, y + bh / 2, bw, icon.replace("_on", "_off") if icon in off else icon)
        label(cv, text, x + cw / 2, y + bh + sep_lbl + line_h(tfs) / 2, "CardText", size=tfs)
        x += cw + sep_tog
    y += tog_h + sep
    if rate:
        draw_pill_button(cv, (mid - rbw / 2, y + rate_h - rbh, rbw, rbh), "ОЦЕНИТЬ ИГРУ", "gold",
                         tscn_int(N["RateButton"], "theme_override_font_sizes/font_size", 46))
        for name, n in N.items():
            if name.startswith("Star") and "RateStars" in n.get("_parent", ""):
                sx, sy, sw, sh = node_rect(n)
                sp.draw_png(cv, "star", mid + sx, y + sy, sw, sh)
        y += rate_h + sep
    if dev:
        draw_pill_button(cv, (mid - motion_w / 2, y, motion_w, motion_h), "Меньше движения: выкл", "light",
                         tscn_int(N["MotionButton"], "theme_override_font_sizes/font_size", 46))
        y += motion_h + sep
    draw_pill_button(cv, (mid - close_w / 2, y, close_w, close_h), "ПРОДОЛЖИТЬ" if mode == "pause" else "ГОТОВО",
                     "green")
    y += close_h + sep
    if mode == "pause":
        draw_link(cv, mid, y + home_h / 2, home_h, "В меню", "home")
    elif dev:
        draw_pill_button(cv, (mid - second_w / 2, y, second_w, second_h), "Сбросить прогресс", "light",
                         tscn_int(N["ResetButton"], "theme_override_font_sizes/font_size", 46))
    return cv.image(), card


# ---------------------------------------------------------------- всплывающие сообщения (13.5d)

def toast_style():
    """StyleBoxFlat «toast» из темы: поля, цвета, кромка, тень, радиус."""
    src = open(os.path.join(ROOT, "theme", "main_theme.tres"), encoding="utf-8").read()
    box = re.search(r'id="toast"\]\n(.*?)\n\n', src, re.S).group(1)
    out = {}
    for k, v in re.findall(r"^(\w+) = (.+)$", box, re.M):
        m = re.match(r"(Color|Vector2)\((.*)\)", v)
        out[k] = tuple(float(x) for x in m.group(2).split(",")) if m else float(v)
    return out


def rrect_sdf(X, Y, x, y, w, h, r):
    qx = np.abs(X - (x + w / 2)) - (w / 2 - r)
    qy = np.abs(Y - (y + h / 2)) - (h / 2 - r)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r


def draw_stylebox_flat(cv, rect, st):
    """StyleBoxFlat: тень (скруглённый прямоугольник, сдвиг shadow_offset, спад к нулю за shadow_size),
    кромка border_width_top (между внешним и внутренним прямоугольником), заливка; сглаживание 1 px."""
    x, y, w, h = rect
    r = min(st.get("corner_radius_top_left", 0.0), w / 2, h / 2)
    ss = st.get("shadow_size", 0.0)
    so = st.get("shadow_offset", (0.0, 0.0))
    m = int(ss + max(abs(so[0]), abs(so[1])) + 3)
    X0, Y0 = int(math.floor(x)) - m, int(math.floor(y)) - m
    X1, Y1 = int(math.ceil(x + w)) + m, int(math.ceil(y + h)) + m
    X, Y = np.meshgrid(np.arange(X0, X1) + 0.5, np.arange(Y0, Y1) + 0.5)
    out = np.zeros(X.shape + (4,))
    if ss > 0:
        d = rrect_sdf(X, Y, x + so[0], y + so[1], w, h, r)
        sc = st["shadow_color"]
        out[..., :3] = sc[:3]
        out[..., 3] = sc[3] * np.clip(1.0 - d / ss, 0.0, 1.0)
        cv.over(X0, Y0, out.copy())
    bt = st.get("border_width_top", 0.0)
    cov_out = np.clip(0.5 - rrect_sdf(X, Y, x, y, w, h, r), 0, 1)
    if bt > 0:
        cov_in = np.clip(0.5 - rrect_sdf(X, Y, x, y + bt, w, h - bt, max(r - bt, 0.0)), 0, 1)
    else:
        cov_in = cov_out
    # Кромка и заливка лежат рядом (Godot не рисует одну поверх другой): доля заливки в покрытии — cov_in.
    bg = np.asarray(st["bg_color"])
    bc = np.asarray(st.get("border_color", st["bg_color"]))
    t = np.where(cov_out > 1e-6, np.minimum(cov_in, cov_out) / np.maximum(cov_out, 1e-6), 1.0)[..., None]
    col = bc * (1 - t) + bg * t
    layer = np.zeros(X.shape + (4,))
    layer[..., :3] = col[..., :3]
    layer[..., 3] = col[..., 3] * cov_out
    cv.over(X0, Y0, layer)


def render_toast(text, w=720, h=1280):
    """Toast на месте раскладки: строки Toast.balance_lines (layout_model.toast_lines), капсула по тексту."""
    cv, L = render_game(w, h)
    st = toast_style()
    fs = int(th("ToastText", "font_sizes", "font_size", 30))
    spc = th("ToastText", "constants", "line_spacing", 3.0)
    area = L["toast"]
    pad_x, pad_y = st["content_margin_left"], st["content_margin_top"]
    f = sp._font(font_of("ToastText"), fs)
    lines = lm.toast_lines(text, f, area[2] - 2 * pad_x)
    tw = max(f.getlength(s) for s in lines)
    lh = line_h(fs)
    bw, bh = math.ceil(tw) + 2 * pad_x, len(lines) * lh + (len(lines) - 1) * spc + 2 * pad_y
    bx, by = round(area[0] + area[2] / 2 - bw / 2), round(area[1] + area[3] - bh)
    draw_stylebox_flat(cv, (bx, by, bw, bh), st)
    for i, s in enumerate(lines):
        label(cv, s, bx + bw / 2, by + pad_y + i * (lh + spc) + lh / 2, "ToastText")
    return cv.image(), (bx, by, bw, bh), area


def sheet(items, name, scale=1.0):
    """Кадры рядом (каждый со своей подписью сверху), фон — тёмно-фиолетовый, как у compare_pair."""
    ims = [im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS) if scale != 1 else im
           for _, im in items]
    W = sum(im.width for im in ims) + 24 * (len(ims) - 1)
    H = max(im.height for im in ims) + 56
    out = Image.new("RGB", (W, H), (30, 20, 70))
    d = ImageDraw.Draw(out)
    f = ImageFont.truetype(BLACK, 30)
    x = 0
    for (title, _), im in zip(items, ims):
        out.paste(im, (x, 56))
        d.text((x + 16, 12), title, font=f, fill=(255, 255, 255))
        x += im.width + 24
    path = os.path.join(FRAMES, name)
    out.save(path, optimize=True)
    return path


def compare_pair(ref, img, left, right, name):
    out = Image.new("RGB", (ref.width + img.width + 24, max(ref.height, img.height) + 56), (30, 20, 70))
    out.paste(ref, (0, 56))
    out.paste(img, (ref.width + 24, 56))
    d = ImageDraw.Draw(out)
    f = ImageFont.truetype(BLACK, 30)
    d.text((16, 12), left, font=f, fill=(255, 255, 255))
    d.text((ref.width + 40, 12), right, font=f, fill=(255, 255, 255))
    path = os.path.join(FRAMES, name)
    out.save(path, optimize=True)
    return path


def reference_background(w, h, win=False):
    """Фон эталона без интерфейса: style_a2 A2.background (A3B берёт его без изменений) на холсте w×h."""
    import style_a2
    import style_frames as sf
    img = Image.new("RGBA", (w * sf.SS, h * sf.SS), (0, 0, 0, 255))
    style_a2.A2.background(None, img, win=win)
    return img.convert("RGB").resize((w, h), Image.LANCZOS)


def swirl_speed(u, speed, w=720, h=1280, t=100.0):
    """Скорость витков вихря (19.7), px/с: |∂φ/∂t| / |∇φ| — насколько за секунду сдвигается полоса витка поперёк
    себя (формулы φ — как в shaders/background.gdshader). Вне ядра (r > 180 px). -> (средняя, медиана, 99 %)."""
    y, x = np.mgrid[0:h, 0:w] + 0.5

    def phi(tt):
        ph = 2 * math.pi * ((tt % 3600.0) * speed / 3600.0 % 1.0)
        dx, dy = x - float(u["swirl_center"].x) * w, y - float(u["swirl_center"].y) * h
        ddx = dx + u["warp"] * (np.sin(dy / 230 + ph * 4) + 0.5 * np.sin(dx / 130 - ph * 7))
        ddy = dy + u["warp"] * (np.cos(dx / 210 - ph * 5) + 0.5 * np.cos(dy / 150 + ph * 6))
        r = np.maximum(np.hypot(ddx, ddy), 1e-3)
        return u["arms"] * (np.arctan2(ddy, ddx) + ph * u["spin_turns"]) \
            - u["wind"] * 2 * math.pi * np.log(1 + r / u["core"]), r
    wrap = lambda d: (d + math.pi) % (2 * math.pi) - math.pi
    dt = 0.05
    p0, r = phi(t)
    p1, _ = phi(t + dt)
    gy, gx = np.gradient(p0)
    v = np.abs(wrap(p1 - p0) / dt) / np.maximum(np.hypot(wrap(gx), wrap(gy)), 1e-6)
    v = v[r > 180]
    return v.mean(), np.median(v), np.percentile(v, 99)


def background_checks():
    """Числа фона (13.7, вихрь — 19.7): средний цвет против эталона, скорость витков, стык TIME. -> (строки, кадры)."""
    from PIL import ImageFilter
    u = sp.Shader.get("background").defaults
    gd = "scenes/ui/background.gd"
    fast, calm = (sp.gd_value(sp.gd_const(gd, k)) for k in ("SPEED", "SPEED_CALM"))
    out, ims = [], []
    ref = reference_background(720, 1280)
    img = sp.background(720, 1280).image()
    a, b = np.asarray(ref, dtype=float), np.asarray(img, dtype=float)
    blur = lambda im: np.asarray(im.filter(ImageFilter.GaussianBlur(40)), dtype=float)
    out.append("средний цвет: эталон %s, шейдер %s; разница после размытия 40 px: средняя %.1f, наибольшая %.1f"
               % (tuple(int(round(x)) for x in a.mean((0, 1))), tuple(int(round(x)) for x in b.mean((0, 1))),
                  np.abs(blur(ref) - blur(img)).mean(), np.abs(blur(ref) - blur(img)).max()))
    ims += [("Эталон A2 (фигуры)", ref), ("Вихрь, TIME 0", img)]
    for spd, what in ((fast, "SPEED"), (calm, "SPEED_CALM, «Меньше движения»")):
        v = np.array([swirl_speed(u, spd, t=t) for t in (0.0, 37.0, 100.0, 211.0, 333.0, 901.0)])
        out.append("темп %g (%s): оборот вихря за %.0f с; витки смещаются в среднем на %.1f px/с (в разные моменты "
                   "%.1f–%.1f), у 99 %% экрана — до %.0f (наибольшее %.0f)" % (spd, what, 3600.0 / (u["spin_turns"] * spd),
                   v[:, 0].mean(), v[:, 0].min(), v[:, 0].max(), v[:, 2].mean(), v[:, 2].max()))
    t = 30.0
    ims.append(("TIME %.0f с (темп %g)" % (t, fast), sp.background(720, 1280, time=t).image()))
    ims.append(("Победа", sp.background(720, 1280, win=True).image()))
    d = np.abs(np.asarray(sp.background(720, 1280, time=3599.999).image(), dtype=float)
               - np.asarray(sp.background(720, 1280, time=0.0).image(), dtype=float))
    out.append("скачок на стыке (сброс TIME Godot, 3600 с): средний %.3f, наибольший %.0f из 255" % (d.mean(), d.max()))
    land = sp.background(2276, 1280).image()
    ims.append(("Альбом 16:9 (2276×1280), TIME 0", land))
    return out, ims


def main(argv):
    every = not any(a in argv for a in ("--win", "--panels", "--toasts", "--menu", "--map", "--leaders", "--lab",
                                        "--background"))
    if every or "--background" in argv:
        lines, items = background_checks()
        for x in lines:
            print("фон: " + x)
        print(sheet(items, "G13_7_background.png", scale=0.5))
    if every or "--win" in argv:
        img, _ = render_win()
        p = os.path.join(FRAMES, "G13_5_win.png")
        img.save(p, optimize=True)
        print(p)
        ref = Image.open(os.path.join(FRAMES, "A3B_win.png")).convert("RGB")
        print(compare_pair(ref, img, "Эталон A3B_win", "Godot (13.5b): WinPanel", "G13_5_win_compare.png"))
    if every or "--panels" in argv:
        items = []
        for mode, title, kw in (("settings", "Настройки (меню)", {}), ("confirm", "Сброс прогресса", {}),
                                ("pause", "Пауза (музыка выключена)", {"off": ("music_on",)}),
                                ("settings", "Настройки у игрока после обучения (12.10b)", {"dev": False, "rate": True})):
            img, card = render_panel(mode, **kw)
            items.append((title, img))
            print("%s: карточка %.0f×%.0f, верх %.1f" % (title, card[2], card[3], card[1]))
        print(sheet(items, "G13_5_panels.png"))
    if every or "--toasts" in argv:
        items = []
        for text, w, h, title in (("Сначала отмени ошибочный ход", 720, 1280, "Одна строка"),
                                  ("Тупик: так поле не заполнить. Отмени ход", 720, 1280, "Две строки"),
                                  ("Подсказка откроется после просмотра рекламы", 2276, 1280, "Альбом 16:9 (лоток в кадре не рисуется)")):
            img, box, area = render_toast(text, w, h)
            items.append((title, img))
            print("«%s» %d×%d: капсула %s, место %s" % (text, w, h, tuple(round(v) for v in box),
                                                       tuple(round(v) for v in area)))
        print(sheet(items, "G13_5_toasts.png"))
    if every or "--menu" in argv:
        items = []
        for w, h, loc, lv, title in ((720, 1280, "ru", 12, "Портрет 720×1280"), (720, 1280, "en", 12, "English"),
                                     (720, 1280, "tr", 500, "Türkçe, уровень 500"),
                                     (2276, 1280, "ru", 12, "Альбом 16:9 (2276×1280)")):
            img, info = render_menu(w, h, level=lv, locale=loc)
            items.append((title, img))
            print("меню %d×%d %s: %s" % (w, h, loc, info))
        print(sheet(items, "G13_6_menu.png"))
    if every or "--map" in argv:
        items = []
        for w, h, cur, loc, title in ((720, 1280, 12, "ru", "Уровень 12"), (720, 1280, 1, "ru", "Новый игрок"),
                                      (720, 1280, 58, "ru", "Уровень 58: впереди глава 2"),
                                      (720, 1280, 1000, "en", "Level 1000 (en)"),
                                      (2276, 1280, 12, "tr", "Альбом 16:9 (2276×1280), tr")):
            st = {n: 1 + (n * 7) % 3 for n in range(1, cur)}
            img, info = render_map(w, h, current=cur, score=150 * (cur - 1) + 90, locale=loc, stars=st)
            items.append((title, img))
            print("карта %d×%d уровень %d: %s" % (w, h, cur, info))
        print(sheet(items, "G18_2_map.png"))
    if every or "--leaders" in argv:
        items = []
        for w, h, loc, kind, title in ((720, 1280, "ru", "player40", "Вошёл, 40-е место: 14 строк"),
                                       (720, 1280, "en", "guest", "Guest (en)"),
                                       (720, 1280, "tr", "streak", "Seri (tr)"),
                                       (2276, 1280, "ru", "local", "Вне Яндекса, альбом 16:9")):
            img, info = render_leaders(w, h, locale=loc, kind=kind)
            items.append((title, img))
            print("лидеры %d×%d %s: %s" % (w, h, loc, info))
        print(sheet(items, "G18_3_leaders.png", scale=0.5))
    if every or "--lab" in argv:
        mix = {("unknown", 1): 3, ("unknown", 2): 2, ("unknown", 3): 3, ("holes", 1): 1, ("tints", 1): 3,
               ("tints", 2): 3, ("tints", 3): 2, ("tints", 4): 3, ("pinned", 10): 2}
        items = []
        for loc, done, title in (("ru", None, "Без отметок"), ("en", mix, "Отметки и звёзды (en)"),
                                 ("tr", mix, "Türkçe")):
            img, info = render_lab(720, 1280, locale=loc, done=done)
            items.append((title, img))
            print("лаборатория %s: %s" % (loc, info))
        img, info = render_menu(720, 1280, level=12, locale="ru", lab=True)
        items.append(("Меню, отладочная сборка", img))
        print(sheet(items, "G19_3_lab.png"))


if __name__ == "__main__":
    main(sys.argv[1:])
