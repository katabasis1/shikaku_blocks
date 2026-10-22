#!/usr/bin/env python3
"""Python-копия глав (этап 19.5c): таблицы scripts/chapters.gd и счёт Chapters / MapPath без Godot.

table() — FIRST, NAMES, IDEAS, THEMES, LOOP_SPAN, VIGNETTE_ALPHA из chapters.gd; index_of, number_of, first_level,
is_start, starts_upto — как Chapters; rise, level_below — как MapPath (зазор CHAPTER_GAP перед главой);
shader_theme — тема → униформы shaders/background.gdshader; check — проблемы таблиц (то же — selftest; ещё —
тема главы 1 = цвета шейдера по умолчанию, shader_defaults); swirl_colors — цвета вихря (deep, cool, warm) из
градиента главы тем же сдвигом в Oklch, что у главы 1 (так выведены главы 2–10 в 19.7; python3
tools/chapters_model.py — напечатать их рядом с таблицей).
Пользуются tools/chapters_preview.py и tools/window_preview.py (карта).
"""
import math
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GD = os.path.join(ROOT, "scripts", "chapters.gd")
MAP_GD = os.path.join(ROOT, "scenes", "map", "map_path.gd")


def _const_block(src, name):
    """Содержимое [...] константы name: в одну строку или до строки «]» (многострочный список)."""
    m = re.search(r"^const %s\b[^=]*=\s*\[(.*)\]\s*$" % name, src, re.M)
    if m:
        return m.group(1)
    m = re.search(r"^const %s\b[^=]*=\s*\[\s*$(.*?)^\]" % name, src, re.M | re.S)
    return m.group(1)


def table():
    """FIRST, NAMES, IDEAS, THEMES, LOOP_SPAN, VIGNETTE_ALPHA из chapters.gd."""
    src = open(GD, encoding="utf-8").read()
    first = [int(x) for x in re.findall(r"\d+", _const_block(src, "FIRST"))]
    names = re.findall(r'"([^"]*)"', _const_block(src, "NAMES"))
    ideas = re.findall(r'"([^"]*)"', _const_block(src, "IDEAS"))
    themes = []
    for row in re.findall(r"\{([^}]*)\}", _const_block(src, "THEMES")):
        themes.append({k: v for k, v in re.findall(r'"(\w+)": Color\("#([0-9A-Fa-f]{6})"\)', row)})
    span = int(re.search(r"^const LOOP_SPAN := (\d+)", src, re.M).group(1))
    va = float(re.search(r"^const VIGNETTE_ALPHA := ([\d.]+)", src, re.M).group(1))
    return first, names, ideas, themes, span, va


THEME_KEYS = ("top", "mid", "bottom", "vignette", "deep", "cool", "warm")


def hex_rgba(h, a=1.0):
    return (int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, a)


def shader_theme(t, va):
    """Тема главы → униформы shaders/background.gdshader (как Background.set_chapter_theme)."""
    return {"top_color": hex_rgba(t["top"]), "mid_color": hex_rgba(t["mid"]),
            "bottom_color": hex_rgba(t["bottom"]), "vignette_color": hex_rgba(t["vignette"], va),
            "deep_color": hex_rgba(t["deep"]), "cool_color": hex_rgba(t["cool"]), "warm_color": hex_rgba(t["warm"])}


def shader_defaults():
    """Цвета темы по умолчанию (top, mid, bottom, vignette, deep, cool, warm) из shaders/background.gdshader."""
    src = open(os.path.join(ROOT, "shaders", "background.gdshader"), encoding="utf-8").read()
    out = {}
    for k in ("top_color", "mid_color", "bottom_color", "vignette_color", "deep_color", "cool_color", "warm_color"):
        m = re.search(r"uniform vec4 %s\b[^=]*=\s*vec4\(([^)]*)\)" % k, src)
        out[k] = tuple(float(x) for x in m.group(1).split(","))
    return out


def pack_info():
    src = open(os.path.join(ROOT, "scripts", "level_pack_data.gd"), encoding="utf-8").read()
    total = len(re.findall(r'"(\d\d:\d+:\d+(?::[a-z0-9]*)?)"', src))
    loop_from = int(re.search(r"LOOP_FROM := (\d+)", src).group(1))
    return total, loop_from


def index_of(level, first, total, loop_from):
    n = max(level, 1)
    if n > total:
        span = total - loop_from + 1
        n = loop_from + (n - total - 1) % span
    i = len(first) - 1
    while i > 0 and n < first[i]:
        i -= 1
    return i


def number_of(level, first, total, span):
    if level <= total:
        return None
    return len(first) + 1 + (level - total - 1) // span


def check(first, names, ideas, themes, span):
    """Проблемы таблиц (то же проверяет selftest в Godot)."""
    total, loop_from = pack_info()
    out = []
    n = len(first)
    if not (len(names) == len(ideas) == len(themes) == n):
        out.append("длины FIRST/NAMES/IDEAS/THEMES: %d/%d/%d/%d" % (n, len(names), len(ideas), len(themes)))
    if first[0] != 1 or any(b <= a for a, b in zip(first, first[1:])) or first[-1] > total:
        out.append("FIRST не возрастает с 1 в пределах 1..%d" % total)
    if loop_from not in first:
        out.append("LOOP_FROM %d — не начало главы" % loop_from)
    else:
        k = first.index(loop_from)
        ends = first[k:] + [total + 1]
        if any(b - a != span for a, b in zip(ends, ends[1:])):
            out.append("главы с LOOP_FROM не по LOOP_SPAN=%d уровней" % span)
    for t in themes:
        if set(t) != set(THEME_KEYS):
            out.append("тема без всех цветов: %s" % t)
    # Глава 1 — нынешний фон: цвета по умолчанию униформ shaders/background.gdshader (меню до темы, кадры 13.7).
    if themes:
        for k, v in shader_defaults().items():
            want = shader_theme(themes[0], 1.0)[k][:3]
            if any(abs(a - b) > 0.5 / 255 for a, b in zip(v[:3], want)):
                out.append("тема главы 1: %s %s, в шейдере %s" % (k, tuple(round(x, 4) for x in want), v[:3]))
    # Главы повтора: тема — у исходного уровня, номера идут подряд по span.
    prev = None
    for lv in range(total + 1, total + 3 * (total - loop_from + 1) + 1):
        num = number_of(lv, first, total, span)
        if prev is not None and num not in (prev, prev + 1):
            out.append("номер главы скачет на уровне %d" % lv)
            break
        if (lv - total - 1) % span == 0:
            base = index_of(lv, first, total, loop_from)
            if index_of(lv + span - 1, first, total, loop_from) != base:
                out.append("глава повтора %d смешивает темы" % num)
        prev = num
    return out


def first_level(level, first, total, span, loop_from):
    if level <= total:
        return first[index_of(max(level, 1), first, total, loop_from)]
    return total + 1 + (level - total - 1) // span * span


def is_start(level, first, total, span, loop_from):
    return level >= 1 and first_level(level, first, total, span, loop_from) == level


def starts_upto(level, first, total, span):
    k = sum(1 for f in first if 2 <= f <= min(level, total))
    if level > total:
        k += 1 + (level - total - 1) // span
    return k


class Model:
    """Главы и высоты карты для одного набора таблиц (как Chapters и MapPath.rise / level_below)."""

    def __init__(self):
        self.first, self.names, self.ideas, self.themes, self.span, self.va = table()
        self.total, self.loop_from = pack_info()
        src = open(MAP_GD, encoding="utf-8").read()
        self.step = float(re.search(r"^const STEP := ([\d.]+)", src, re.M).group(1))
        self.gap = float(re.search(r"^const CHAPTER_GAP := ([\d.]+)", src, re.M).group(1))

    def index(self, level):
        return index_of(level, self.first, self.total, self.loop_from)

    def number(self, level):
        n = number_of(level, self.first, self.total, self.span)
        return self.index(level) + 1 if n is None else n

    def is_start(self, level):
        return is_start(level, self.first, self.total, self.span, self.loop_from)

    def theme(self, level):
        return self.themes[self.index(level)]

    def shader(self, level):
        return shader_theme(self.theme(level), self.va)

    def rise(self, t):
        whole = math.floor(t)
        gaps = float(starts_upto(whole, self.first, self.total, self.span))
        if t > whole and self.is_start(whole + 1):
            gaps += t - whole
        return (t - 1.0) * self.step + gaps * self.gap

    def level_below(self, h, n_max):
        lo, hi = 1, max(1, n_max)
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if self.rise(mid) <= h:
                lo = mid
            else:
                hi = mid - 1
        return lo


# ---------------------------------------------------------------- цвета вихря (19.7)

def _s2l(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _l2s(c):
    c = min(max(c, 0.0), 1.0)
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def _oklch(h):
    r, g, b = (_s2l(x) for x in hex_rgba(h)[:3])
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(a, bb), math.atan2(bb, a)


def _hex_oklch(L, C, h):
    """Oklch → «RRGGBB»; вне sRGB — уменьшаем насыщенность (C), пока не войдёт."""
    for k in range(100, -1, -1):
        a, b = C * k / 100 * math.cos(h), C * k / 100 * math.sin(h)
        l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
        m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
        s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
        rgb = (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
               -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
               -0.0041960863 * l - 0.7034186147 * m + 1.7076949022 * s)
        if min(rgb) >= -1e-4 and max(rgb) <= 1 + 1e-4:
            break
    return "".join("%02X" % int(round(_l2s(x) * 255)) for x in rgb)


SWIRL_FROM = {"deep": "mid", "cool": "top", "warm": "bottom"}


def swirl_colors(t1, t):
    """Цвета вихря главы t ({"deep", "cool", "warm"}: «RRGGBB»): тот же сдвиг в Oklch (светлота, доля
    насыщенности, поворот тона) от mid / top / bottom, что у главы 1 (t1) — у неё результат совпадает с таблицей."""
    out = {}
    for k, src in SWIRL_FROM.items():
        a, b = _oklch(t1[src]), _oklch(t1[k])
        L, C, h = _oklch(t[src])
        out[k] = _hex_oklch(L + b[0] - a[0], C * b[1] / max(a[1], 1e-6), h + b[2] - a[2])
    return out


if __name__ == "__main__":
    _first, _names, _ideas, _themes, _span, _va = table()
    for _i, _t in enumerate(_themes):
        _want = swirl_colors(_themes[0], _t)
        print("%2d %-10s" % (_i + 1, _names[_i]), "  ".join("%s #%s (по сдвигу #%s)" % (k, _t.get(k, "—"), _want[k])
                                                    for k in SWIRL_FROM))
    print("\n".join(check(_first, _names, _ideas, _themes, _span)) or "таблицы глав: проблем нет")
