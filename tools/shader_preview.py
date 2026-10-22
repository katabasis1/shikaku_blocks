#!/usr/bin/env python3
"""Этап 13.1d: кадр поля и блоков «как в Godot» из настоящих шейдеров — рядом с эталоном A3B_game.png.

Godot в песочнице нет, поэтому шейдеры (shaders/*.gdshader, подмножество языка шейдеров Godot) переводятся
в Python + numpy и считаются на CPU попиксельно: тот же код, те же униформы, что ставят Board, Cell и Block.
Сцена — кадр A3B_game (уровень 20, поле 6×6, клетка 104 px: масштаб поля 1,04): стоят блоки 6, 8, 6, 3, 2,
блок 4 несут (×1,08, тень «поднят», без наклона — он в 14.2), под ним призрак, числа 4 — магнит,
остальные гнёзда приглушены (Board.emphasize_area). С 13.2a рисуется и полка лотка (shaders/shelf.gdshader,
униформы как в Tray.update_shelf): гнездо 0 пустое (из него несут 4), в гнёздах 1 и 2 — блоки 3 и 4 с клеткой
62 px (GameLayout.TRAY_SCALE_PORTRAIT). Фон с 13.7 — shaders/background.gdshader (функция background, TIME = 0);
кнопки крупно (G13_2b_*) — на столбце пикселей эталона у левого края.

Цифры рисует PIL шрифтом assets/fonts/nunito_black.ttf: обводка outline_size понимается как полная
ширина (по outline_size / 2 на сторону, как задумано в Block.DIGIT_OUTLINE). Это приближение Label Godot.

    python3 tools/shader_preview.py             # -> docs/style_frames/G13_1_game.png, G13_1_compare.png (поле),
                                                #    G13_2_compare.png (полка лотка), G13_2b_buttons.png
                                                #    (кнопки крупно), G13_2b_states.png (состояния кнопки)
    python3 tools/shader_preview.py --bad       # призрак «нельзя» (красный); блок в руке своего цвета
    python3 tools/shader_preview.py --py block  # показать Python-перевод шейдера (отладка переводчика)
"""
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHADERS = os.path.join(ROOT, "shaders")
FRAMES = os.path.join(ROOT, "docs", "style_frames")
DIGIT_FONT = os.path.join(ROOT, "assets", "fonts", "nunito_black.ttf")

# ================================================================ векторы GLSL поверх numpy

_SW = {}
for _set in ("xyzw", "rgba", "stpq"):
    for _i, _ch in enumerate(_set):
        _SW[_ch] = _i


class V:
    """vecN: список компонент (числа или массивы numpy одной формы), покомпонентная арифметика, свизлы."""
    __slots__ = ("c",)
    # «массив * V»: numpy отдаёт операцию V.__rmul__ (иначе получился бы массив объектов V).
    __array_ufunc__ = None

    def __init__(self, comps):
        object.__setattr__(self, "c", list(comps))

    def __getattr__(self, name):
        if name.startswith("_") or not all(ch in _SW for ch in name):
            raise AttributeError(name)
        idx = [_SW[ch] for ch in name]
        return self.c[idx[0]] if len(idx) == 1 else V(self.c[i] for i in idx)

    def __setattr__(self, name, val):
        idx = [_SW[ch] for ch in name]
        if len(idx) == 1:
            self.c[idx[0]] = val
        else:
            for k, i in enumerate(idx):
                self.c[i] = val.c[k] if isinstance(val, V) else val

    def _op(self, o, f):
        if isinstance(o, V):
            return V(f(a, b) for a, b in zip(self.c, o.c))
        return V(f(a, o) for a in self.c)

    def _rop(self, o, f):
        return V(f(o, a) for a in self.c)

    def __add__(self, o): return self._op(o, lambda a, b: a + b)
    def __radd__(self, o): return self._rop(o, lambda a, b: a + b)
    def __sub__(self, o): return self._op(o, lambda a, b: a - b)
    def __rsub__(self, o): return self._rop(o, lambda a, b: a - b)
    def __mul__(self, o): return self._op(o, lambda a, b: a * b)
    def __rmul__(self, o): return self._rop(o, lambda a, b: a * b)
    def __truediv__(self, o): return self._op(o, lambda a, b: a / b)
    def __rtruediv__(self, o): return self._rop(o, lambda a, b: a / b)
    def __neg__(self): return V(-a for a in self.c)
    def __repr__(self): return "V(%s)" % ", ".join("%.3g" % np.mean(a) for a in self.c)


def _map(f, *args):
    vs = [a for a in args if isinstance(a, V)]
    if not vs:
        return f(*args)
    n = len(vs[0].c)
    return V(f(*[(a.c[i] if isinstance(a, V) else a) for a in args]) for i in range(n))


def _vec(n):
    def make(*args):
        comps = []
        for a in args:
            comps.extend(a.c if isinstance(a, V) else [a])
        if len(comps) == 1:
            comps = comps * n
        if len(comps) != n:
            raise ValueError("vec%d из %d компонент" % (n, len(comps)))
        return V(comps)
    return make


def _cp(x):
    return V(x.c) if isinstance(x, V) else x


def _sel(c, a, b):
    if np.ndim(c) == 0:
        return a if bool(c) else b
    return _map(lambda x, y: np.where(c, x, y), a, b)


def _clamp(x, lo, hi):
    return _map(lambda v, a, b: np.minimum(np.maximum(v, a), b), x, lo, hi)


def _smoothstep(e0, e1, x):
    t = _clamp((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _fwidth(f):
    if np.ndim(f) < 2:
        return 0.0 * f
    return np.abs(np.gradient(f, axis=1)) + np.abs(np.gradient(f, axis=0))


def _texture(tex, uv):
    """texture(sampler2D, uv): tex — массив numpy (h, w, 3 или 4), значения 0..1, строка 0 — верх (UV.y = 0).
    Как filter_linear, repeat_disable: билинейно между центрами текселей, за краем — крайний тексель.
    Униформа без картинки (по умолчанию 0.0) — vec4(0): в Godot там была бы пустая текстура."""
    u, v = uv.c[0], uv.c[1]
    if np.ndim(tex) < 3:
        z = 0.0 * (u + v)
        return V([z, z, z, z])
    h, w = tex.shape[:2]
    tx = np.asarray(u, dtype=float) * w - 0.5
    ty = np.asarray(v, dtype=float) * h - 0.5
    x0, y0 = np.floor(tx), np.floor(ty)
    fx, fy = tx - x0, ty - y0
    x0, y0 = x0.astype(int), y0.astype(int)
    xa, xb = np.clip(x0, 0, w - 1), np.clip(x0 + 1, 0, w - 1)
    ya, yb = np.clip(y0, 0, h - 1), np.clip(y0 + 1, 0, h - 1)
    out = []
    for i in range(4):
        if i < tex.shape[2]:
            ch = tex[..., i]
            out.append((ch[ya, xa] * (1 - fx) + ch[ya, xb] * fx) * (1 - fy)
                       + (ch[yb, xa] * (1 - fx) + ch[yb, xb] * fx) * fy)
        else:
            out.append(1.0 + 0.0 * tx)
    return V(out)



LIB = {
    "V": V, "_cp": _cp, "_sel": _sel, "np": np, "math": math,
    "vec2": _vec(2), "vec3": _vec(3), "vec4": _vec(4),
    "g_max": lambda a, b: _map(np.maximum, a, b),
    "g_min": lambda a, b: _map(np.minimum, a, b),
    "g_abs": lambda a: _map(np.abs, a),
    "g_pow": lambda a, b: _map(np.power, a, b),
    "g_float": lambda x: x.astype(float) if isinstance(x, np.ndarray) else float(x),
    "g_int": lambda x: np.trunc(x) if isinstance(x, np.ndarray) else int(x),
    "g_mod": lambda a, b: _map(lambda x, y: x - y * np.floor(x / y), a, b),
    "floor": lambda a: _map(np.floor, a),
    "fract": lambda a: _map(lambda x: x - np.floor(x), a),
    "sqrt": lambda a: _map(np.sqrt, a),
    "sin": lambda a: _map(np.sin, a), "cos": lambda a: _map(np.cos, a),
    "step": lambda e, x: _map(lambda ee, xx: (xx >= ee) * 1.0, e, x),
    "clamp": _clamp, "smoothstep": _smoothstep, "fwidth": _fwidth, "texture": _texture,
    "mix": lambda a, b, t: a + (b - a) * t,
    "length": lambda v: np.sqrt(sum(c * c for c in v.c)) if isinstance(v, V) else np.abs(v),
    "dot": lambda a, b: sum(x * y for x, y in zip(a.c, b.c)),
    "atan": lambda y, x=None: _map(np.arctan, y) if x is None else _map(np.arctan2, y, x),
    "exp": lambda a: _map(np.exp, a), "log": lambda a: _map(np.log, a),
    "sign": lambda a: _map(np.sign, a),
    "TAU": 2.0 * math.pi, "PI": math.pi,
    "TIME": 0.0,   # кадр — в момент 0 (лучи win_rays на начальном повороте turn)
}

# ================================================================ перевод шейдера Godot -> Python

TYPES = r"(?:float|int|bool|vec[234]|ivec[234]|uvec[234]|mat[234])"
UTYPES = r"(?:float|int|bool|vec[234]|ivec[234]|uvec[234]|mat[234]|sampler2D)"   # униформы: ещё картинки
RENAME = {"max": "g_max", "min": "g_min", "abs": "g_abs", "pow": "g_pow", "float": "g_float",
          "int": "g_int", "mod": "g_mod"}


def _read(path, seen=None):
    seen = seen or set()
    src = open(path, encoding="utf-8").read()

    def inc(m):
        rel = m.group(1).replace("res://", "")
        p = os.path.join(ROOT, rel)
        if p in seen:
            return ""
        seen.add(p)
        return _read(p, seen)
    return re.sub(r'#include\s+"([^"]+)"', inc, src)


def _strip(src):
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    src = re.sub(r"^\s*(shader_type|render_mode)[^;]*;", "", src, flags=re.M)
    return src


def _items(src):
    """Поток: ("s", оператор) / ("{", заголовок) / ("}",)."""
    out, buf, depth = [], "", 0
    for ch in src:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if depth == 0 and ch == ";":
            if buf.strip():
                out.append(("s", " ".join(buf.split())))
            buf = ""
        elif depth == 0 and ch == "{":
            out.append(("{", " ".join(buf.split())))
            buf = ""
        elif depth == 0 and ch == "}":
            if buf.strip():
                out.append(("s", " ".join(buf.split())))
            out.append(("}",))
            buf = ""
        else:
            buf += ch
    return out


def _split_top(s, sep):
    parts, depth, i, start = [], 0, 0, 0
    while i < len(s):
        ch = s[i]
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        elif depth == 0 and s.startswith(sep, i):
            parts.append(s[start:i])
            i += len(sep)
            start = i
            continue
        i += 1
    parts.append(s[start:])
    return parts


def expr(s):
    s = s.strip()
    q = _split_top(s, "?")
    if len(q) > 1:
        cond, rest = q[0], "?".join(q[1:])
        ab = _split_top(rest, ":")
        return "_sel((%s), (%s), (%s))" % (expr(cond), expr(ab[0]), expr(":".join(ab[1:])))
    for op, py in (("||", "|"), ("&&", "&")):
        parts = _split_top(s, op)
        if len(parts) > 1:
            return (" %s " % py).join("(%s)" % expr(p) for p in parts)
    s = re.sub(r"\b(max|min|abs|pow|float|int|mod)\s*\(", lambda m: RENAME[m.group(1)] + "(", s)
    s = re.sub(r"\btrue\b", "True", s)
    s = re.sub(r"\bfalse\b", "False", s)
    if re.search(r"(?<![=!<>])!(?!=)", s):
        raise ValueError("«!» не поддержан: " + s)
    return s


def translate(path):
    """-> (код Python, {униформа: выражение по умолчанию}).

    if / else if / else: условие обычно своё у каждого пикселя (массив) — тогда тело считается для всех
    пикселей, а где условие ложно, переменным возвращаются прежние значения (_sel). Условие одно на весь
    кадр (униформа: use_baked) — ветка, которая не выполняется, не считается вовсе. COLOR (глобальный в
    fragment) сохраняется и возвращается так же, как локальные переменные."""
    items = _items(_strip(_read(path)))
    lines, uniforms, stack, n_if = [], {}, [], 0
    last_if = None   # номер только что закрытого if — к нему цепляется else
    ind = lambda: "    " * sum(1 for f in stack if f[0] in ("def", "for", "if"))

    def open_if(cond, chain):
        nonlocal n_if
        n_if += 1
        lines.append(ind() + "_c%d = %s" % (n_if, cond))
        lines.append(ind() + "_k%d = %s" % (n_if, chain.replace("@", "_c%d" % n_if)))
        lines.append(ind() + "_s%d = dict(globals(), **locals())" % n_if)
        lines.append(ind() + "if not (np.ndim(_c%d) == 0 and not _c%d):" % (n_if, n_if))
        stack.append(("if", n_if, set()))

    for it in items:
        prev_if, last_if = last_if, None
        if it[0] == "s":
            st = it[1]
            m = re.match(r"^uniform\s+" + UTYPES + r"\s+(\w+)\s*(?::[^=]*)?(?:=\s*(.+))?$", st)
            if m and not stack:
                uniforms[m.group(1)] = expr(m.group(2)) if m.group(2) else "0.0"
                continue
            if not stack:
                raise ValueError("непонятно вне функции: " + st)
            m = re.match(r"^(?:const\s+)?" + TYPES + r"\s+(\w+)\s*(?:=\s*(.+))?$", st)
            if m:
                lines.append(ind() + "%s = _cp(%s)" % (m.group(1), expr(m.group(2)) if m.group(2) else "0.0"))
                continue
            m = re.match(r"^return\b\s*(.*)$", st)
            if m:
                lines.append(ind() + "return " + expr(m.group(1)))
                continue
            m = re.match(r"^([A-Za-z_]\w*)((?:\.\w+)?)\s*(=|\+=|-=|\*=|/=)\s*(.+)$", st)
            if m:
                name, sw, op, rhs = m.groups()
                lhs = name + sw
                rhs = expr(rhs)
                if op != "=":
                    rhs = "%s %s (%s)" % (lhs, op[0], rhs)
                lines.append(ind() + "%s = %s" % (lhs, rhs))
                for f in stack:
                    if f[0] == "if":
                        f[2].add(name)
                continue
            raise ValueError("непонятный оператор: " + st)
        if it[0] == "{":
            h = it[1]
            m = re.match(r"^(?:void|" + TYPES + r")\s+(\w+)\s*\((.*)\)$", h)
            if m and not stack:
                params = [p.split()[-1] for p in m.group(2).split(",") if p.strip()]
                lines.append("def %s(%s):" % (m.group(1), ", ".join(params)))
                if m.group(1) == "fragment":
                    lines.append("    global COLOR")
                stack.append(("def",))
                continue
            m = re.match(r"^for\s*\(\s*int\s+(\w+)\s*=\s*(.+?);\s*\1\s*<\s*(.+?);\s*\1\s*\+\+\s*\)$", h)
            if m:
                lines.append(ind() + "for %s in range(int(%s), int(%s)):" % (m.group(1), expr(m.group(2)), expr(m.group(3))))
                stack.append(("for",))
                continue
            m = re.match(r"^if\s*\((.*)\)$", h)
            if m:
                open_if("(%s)" % expr(m.group(1)), "@")
                continue
            m = re.match(r"^else\s+if\s*\((.*)\)$", h)
            if m:
                if prev_if is None:
                    raise ValueError("else if без if: " + h)
                x = expr(m.group(1))
                open_if("np.logical_and(np.logical_not(_k%d), (%s))" % (prev_if, x),
                        "np.logical_or(_k%d, (%s))" % (prev_if, x))
                continue
            if h == "else":
                if prev_if is None:
                    raise ValueError("else без if")
                open_if("np.logical_not(_k%d)" % prev_if, "True")
                continue
            raise ValueError("непонятный блок: " + h)
        if it[0] == "}":
            f = stack.pop()
            if f[0] in ("for", "if") and not lines[-1].startswith(ind() + "    "):
                lines.append(ind() + "    pass")
            if f[0] == "if":
                # Где условие ложно — прежние значения (ветка не выполнялась бы).
                for name in sorted(f[2]):
                    lines.append(ind() + "if '%s' in _s%d: %s = _sel(_c%d, %s, _s%d['%s'])"
                                 % (name, f[1], name, f[1], name, f[1], name))
                last_if = f[1]
    return "\n".join(lines) + "\n", uniforms


class Shader:
    _cache = {}

    def __init__(self, name):
        self.name = name
        self.code, self.udef = translate(os.path.join(SHADERS, name + ".gdshader"))
        self.compiled = compile(self.code, name + ".gdshader.py", "exec")
        self.defaults = {k: eval(v, dict(LIB)) for k, v in self.udef.items()}

    @classmethod
    def get(cls, name):
        if name not in cls._cache:
            cls._cache[name] = Shader(name)
        return cls._cache[name]

    def run(self, uv, color, params, time=0.0):
        ns = dict(LIB)
        ns["TIME"] = time
        for k, v in self.defaults.items():
            ns[k] = _cp(v)
        for k, v in params.items():
            if k not in self.defaults:
                raise KeyError("%s: нет униформы %s" % (self.name, k))
            ns[k] = V(v) if isinstance(v, (tuple, list)) else v
        ns["UV"] = uv
        ns["COLOR"] = V(color)
        exec(self.compiled, ns)
        ns["fragment"]()
        return ns["COLOR"]


# ================================================================ холст и узлы

class Canvas:
    def __init__(self, bg):
        self.rgb = np.asarray(bg, dtype=float)[..., :3] / 255.0
        self.h, self.w = self.rgb.shape[:2]

    def over(self, x0, y0, rgba):
        """rgba — float (h, w, 4) без премультипликации, левый верхний угол (x0, y0) на холсте."""
        h, w = rgba.shape[:2]
        X0, Y0 = max(0, x0), max(0, y0)
        X1, Y1 = min(self.w, x0 + w), min(self.h, y0 + h)
        if X1 <= X0 or Y1 <= Y0:
            return
        src = rgba[Y0 - y0:Y1 - y0, X0 - x0:X1 - x0]
        a = src[..., 3:4]
        dst = self.rgb[Y0:Y1, X0:X1]
        self.rgb[Y0:Y1, X0:X1] = src[..., :3] * a + dst * (1.0 - a)

    def image(self):
        return Image.fromarray((np.clip(self.rgb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def draw_rect(cv, shader, gx, gy, w, h, s, color, params, time=0.0):
    """ColorRect с шейдером: локальный прямоугольник w×h, на экране — левый верх (gx, gy), масштаб s;
    time — TIME шейдера, с."""
    sw, sh = w * s, h * s
    x0, y0 = int(math.floor(gx)), int(math.floor(gy))
    x1, y1 = int(math.ceil(gx + sw)), int(math.ceil(gy + sh))
    xs = (np.arange(x0, x1) + 0.5 - gx) / sw
    ys = (np.arange(y0, y1) + 0.5 - gy) / sh
    u, v = np.meshgrid(xs, ys)
    col = Shader.get(shader).run(V([u, v]), color, params, time)
    out = np.zeros(u.shape + (4,))
    for i in range(4):
        out[..., i] = np.broadcast_to(col.c[i], u.shape)
    inside = (u >= 0) & (u <= 1) & (v >= 0) & (v <= 1)
    out[..., 3] = np.clip(out[..., 3], 0, 1) * inside
    out[..., :3] = np.clip(out[..., :3], 0, 1)
    cv.over(x0, y0, out)


def background(w, h, win=False, time=0.0, theme=None, speed=None, rect=None):
    """Холст w×h с фоном игры и меню (13.7, вихрь — 19.7): Background (scenes/ui/background.gd) на весь экран —
    shaders/background.gdshader, rect_size = (w, h), свет Background.LIGHT или LIGHT_WIN (победа).
    theme — тема главы (19.5c): {"top_color": (r, g, b, a), …} поверх униформ шейдера; None — по умолчанию.
    time — TIME шейдера, с; speed — темп вихря (None — Background.SPEED, как в игре без «Меньше движения»).
    rect — rect_size другого размера (видео в уменьшенном виде: w×h пикселей на rect виртуальных px)."""
    gd = "scenes/ui/background.gd"
    light = gd_value(gd_const(gd, "LIGHT_WIN" if win else "LIGHT"))
    if speed is None:
        speed = gd_value(gd_const(gd, "SPEED"))
    cv = Canvas(np.zeros((h, w, 3)))
    sh = Shader.get("background")
    band = max(16, 240000 // w)   # полосами по ≈ 240 000 пикселей: целиком 2276×1280 не влезает в память
    xs = (np.arange(w) + 0.5) / w
    for y0 in range(0, h, band):
        ys = (np.arange(y0, min(h, y0 + band)) + 0.5) / h
        u, v = np.meshgrid(xs, ys)
        col = sh.run(V([u, v]), (1, 1, 1, 1), dict({"rect_size": rect or (w, h), "light": light, "speed": speed},
                                                   **(theme or {})), time)
        for i in range(3):
            cv.rgb[y0:y0 + len(ys), :, i] = np.clip(np.broadcast_to(col.c[i], u.shape), 0, 1)
    return cv


_fonts = {}


def draw_digit(cv, text, cx, cy, size, fill, outline, outline_size, shadow, shadow_off, alpha=1.0, font_path=None):
    """Label Godot (по центру прямоугольника): тень (обведённый знак со сдвигом), обводка, заливка."""
    key = (font_path or DIGIT_FONT, int(round(size)))
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(key[0], key[1])
    f = _fonts[key]
    sw = int(round(outline_size / 2.0)) if font_path else max(1, int(round(outline_size / 2.0)))
    pad = int(size)
    H = int(size * 2 + pad * 2)
    W = max(H, int(f.getlength(text) + sw * 2 + pad * 2)) // 2 * 2
    for layer, (col, dx, dy) in enumerate(((shadow, shadow_off[0], shadow_off[1]), (fill, 0, 0))):
        im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        c = tuple(int(round(x * 255)) for x in col[:3])
        o = tuple(int(round(x * 255)) for x in (col if layer == 0 else outline)[:3])
        d.text((W / 2 + dx, H / 2 + dy), text, font=f, anchor="mm", fill=c + (255,), stroke_width=sw,
               stroke_fill=o + (255,))
        a = np.asarray(im, dtype=float) / 255.0
        a[..., 3] *= (col[3] if layer == 0 else 1.0) * alpha
        cv.over(int(round(cx - W / 2)), int(round(cy - H / 2)), a)


# ================================================================ палитра и константы из кода

def gd_const(path, name):
    src = open(os.path.join(ROOT, path), encoding="utf-8").read()
    m = re.search(r"const\s+%s\s*(?::=|:\s*\w+\s*=|=)\s*(.+)" % name, src)
    if not m:
        raise KeyError("%s: нет const %s" % (path, name))
    return m.group(1).strip()


def gd_value(text):
    text = text.split("#")[0].strip()
    m = re.match(r"^(Vector2i?|Vector4|Color|Rect2)\((.*)\)$", text)
    if m:
        return tuple(float(x) for x in m.group(2).split(","))
    if re.match(r"^[0-9.\s/*+()-]+$", text) and not re.match(r"^[0-9.]+$", text):
        return float(eval(text, {"__builtins__": {}}))   # простое выражение из чисел: «48.0 / 255.0»
    return float(text)


def palette():
    src = open(os.path.join(ROOT, "scripts", "palette.gd"), encoding="utf-8").read()
    body = src[src.index("BLOCK_COLORS"):]
    body = body[body.index("= ["):]          # после «Array[Color]» — у него своя «]»
    body = body[:body.index("\n]")]
    cols = [tuple(float(x) for x in m.split(",")) + (1.0,) for m in re.findall(r"Color\(([^)]*)\)", body)]
    return cols


PAL = palette()
GHOST_BAD = gd_value(gd_const("scripts/palette.gd", "GHOST_BAD")) + (1.0,)
SHADE = gd_value(gd_const("scripts/palette.gd", "SHADE"))
SHADE_LIFTED = gd_value(gd_const("scripts/palette.gd", "SHADE_LIFTED"))
B = {k: gd_value(gd_const("scenes/game/block.gd", k)) for k in
     ("CELL", "DEPTH", "MARGIN_REST", "MARGIN_LIFTED", "SHADOW_REST", "SHADOW_LIFTED", "BLUR_REST",
      "BLUR_LIFTED", "LIFT_SCALE", "DIGIT_OUTLINE")}
BD = {k: gd_value(gd_const("scenes/game/board.gd", k)) for k in ("PAD", "RIM", "FRAME_DEPTH", "FRAME_MARGIN")}
CL = {k: gd_value(gd_const("scenes/game/cell.gd", k)) for k in ("MAGNET_SCALE", "MAGNET_LIFT", "DIGIT_OUTLINE")}
DIM_A = gd_value(gd_const("scenes/game/cell.gd", "DIM_COLOR"))[3]
CELL = B["CELL"]
TRAY_SCALE = gd_value(gd_const("scripts/game_layout.gd", "TRAY_SCALE_PORTRAIT"))
SLOT_MARGIN = gd_value(gd_const("scenes/game/tray.gd", "SLOT_MARGIN"))


def color_for(area):
    return PAL[max(1, min(area, len(PAL))) - 1]


def darkened(c, t):
    return (c[0] * (1 - t), c[1] * (1 - t), c[2] * (1 - t), c[3])


# ================================================================ сцена: кадр A3B_game

def load_level(n):
    """Поле и прямоугольники решения уровня n списка. Метки механики (19.5e, четвёртая часть строки) не читаются —
    но строка с ними считается, иначе номера уровней после 150 сдвинулись бы (до сессии 98 так и было)."""
    src = open(os.path.join(ROOT, "scripts", "level_pack_data.gd"), encoding="utf-8").read()
    head, rs = re.findall(r'"(\d\d:\d+:\d+(?::[a-z0-9]*)?)"', src)[n - 1].split(":")[:2]
    rects = [tuple(int(ch) for ch in rs[i:i + 6]) for i in range(0, len(rs), 6)]
    return int(head[0]), int(head[1]), rects


LEVEL_N = 20
PLACED = [0, 1, 3, 4, 7]
DRAGGED = 2
DRAG_OFF = (-70, 128)
BOARD_C = (360, 520)
CELL_PX = 104
TRAY_BLOCKS = [None, (1, 3), (2, 2)]   # кадр A3B_game: гнездо 0 пусто, в 1 — блок 3, в 2 — блок 4
BTN_D = 96.0                           # custom_minimum_size кнопок в game.tscn (эталон рисует Ø 100)


def draw_block(cv, gx, gy, s, bw, bh, area, num_cell, lifted, tint=(1, 1, 1, 1)):
    """Block: узел Shape (поля под тень margin) + цифра. (gx, gy) — левый верх блока на экране, s — масштаб."""
    px = 1.0 / s
    m = (B["MARGIN_LIFTED"] if lifted else B["MARGIN_REST"]) * px
    w, h = bw * CELL, bh * CELL
    lift = B["DEPTH"] * CELL * 0.6
    if num_cell is not None:
        center = ((num_cell[0] + 0.5) * CELL, (num_cell[1] + 0.5) * CELL - lift)
    else:
        center = (w * 0.5, h * 0.5 - lift)
    col = tuple(a * b for a, b in zip(color_for(area), tint))
    draw_rect(cv, "block", gx - m * s, gy - m * s, w + 2 * m, h + 2 * m, s, col, {
        "rect_size": (w, h), "cells": (float(bw), float(bh)), "margin": m, "num_center": center, "px": px,
        "shadow_offset": B["SHADOW_LIFTED"] if lifted else B["SHADOW_REST"],
        "shadow_blur": B["BLUR_LIFTED"] if lifted else B["BLUR_REST"],
        "shadow_color": SHADE_LIFTED if lifted else SHADE})
    # Label: прямоугольник клетки с числом (или всего блока), поднят на lift; шрифт 46, тень вниз 4.
    fill = tuple(a * b for a, b in zip((1, 1, 1, 1), tint))
    draw_digit(cv, str(area), gx + center[0] * s, gy + center[1] * s, 46 * s, fill,
               darkened(color_for(area), 0.45), B["DIGIT_OUTLINE"] * s,
               darkened(color_for(area), 0.6)[:3] + (0.47,), (0, 4 * s))


def draw_tray(cv):
    """Tray: полка (_draw с shelf.gdshader) и блоки в гнёздах (Tray._place_in_slot) — раскладка портрета."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import layout_model
    L = layout_model.compute(720, 1280, False)
    shelf = L["shelf"]
    slots = layout_model.slots(L)
    params = {"shelf_size": (shelf[2], shelf[3]),
              "well_empty": tuple(1.0 if t is None else 0.0 for t in TRAY_BLOCKS)}
    for i, sr in enumerate(slots):
        params["well%d" % i] = (sr[0] - shelf[0], sr[1] - shelf[1], sr[2], sr[3])
    draw_rect(cv, "shelf", shelf[0], shelf[1], shelf[2], shelf[3], 1.0, (1, 1, 1, 1), params)
    for sr, t in zip(slots, TRAY_BLOCKS):
        if t is None:
            continue
        bw, bh = t
        k = min(TRAY_SCALE, (sr[2] - SLOT_MARGIN) / (bw * CELL), (sr[3] - SLOT_MARGIN) / (bh * CELL))
        draw_block(cv, sr[0] + (sr[2] - bw * CELL * k) / 2, sr[1] + (sr[3] - bh * CELL * k) / 2, k, bw, bh,
                   bw * bh, None, False)


# ---------------------------------------------------------------- кнопки (13.2b): CandyButton + SoftShadow

ICONS = os.path.join(ROOT, "assets", "icons")
CB = {k: gd_value(gd_const("scripts/candy_button.gd", k)) for k in
      ("SHADOW_OFFSET", "SHADOW_BLUR", "SHADOW_STRENGTH", "BADGE_SHIFT", "BADGE_SHADOW_OFFSET",
       "BADGE_SHADOW_BLUR", "BADGE_SHADOW_STRENGTH", "PRESS_SCALE", "PRESS_NEAR", "DISABLED_ALPHA")}
FACE_OVERSCAN = 256.0 / 240.0
FACE_SHAPE = (236.0 / 256.0, 240.0 / 256.0)
_png = {}


def draw_png(cv, name, x, y, w, h, alpha=1.0):
    """TextureRect (STRETCH_SCALE, линейный фильтр с mipmaps): PNG w×h с левым верхом (x, y)."""
    if name not in _png:
        _png[name] = Image.open(os.path.join(ICONS, name + ".png")).convert("RGBA")
    src = _png[name]
    x0, y0 = int(math.floor(x)), int(math.floor(y))
    # Сдвиг на дробную часть: рисуем в 4× и уменьшаем (как билинейный фильтр с mipmaps — без «ступенек»).
    W4, H4 = int(math.ceil((x + w - x0) * 4)), int(math.ceil((y + h - y0) * 4))
    big = Image.new("RGBA", (W4, H4), (0, 0, 0, 0))
    big.alpha_composite(src.resize((int(round(w * 4)), int(round(h * 4))), Image.LANCZOS),
                        (int(round((x - x0) * 4)), int(round((y - y0) * 4))))
    im = big.resize((W4 // 4 or 1, H4 // 4 or 1), Image.BOX)
    a = np.asarray(im, dtype=float) / 255.0     # resize у PIL для RGBA — с премультипликацией
    a[..., 3] *= alpha
    cv.over(x0, y0, a)


def draw_soft_shadow(cv, px, py, pw, ph, shape, round_k, offset, blur, strength, k=1.0, near=1.0):
    """SoftShadow.refresh под родителем (px, py, pw×ph) в масштабе k вокруг центра родителя."""
    m = (math.ceil(blur * 3.0 + abs(offset[0])), math.ceil(blur * 3.0 + abs(offset[1])))
    w, h = pw + 2 * m[0], ph + 2 * m[1]
    sz = (pw * shape[0], ph * shape[1])
    lo = (m[0] + (pw - sz[0]) * 0.5, m[1] + (ph - sz[1]) * 0.5)
    cx, cy = px + pw / 2, py + ph / 2
    draw_rect(cv, "soft_shadow", cx - (pw / 2 + m[0]) * k, cy - (ph / 2 + m[1]) * k, w, h, k, (1, 1, 1, 1), {
        "rect_size": (w, h), "shape_lo": lo, "shape_hi": (lo[0] + sz[0], lo[1] + sz[1]),
        "radius": min(sz) * 0.5 * round_k, "offset": (offset[0] * near, offset[1] * near), "blur": blur,
        "shade": SHADE + (1.0,), "strength": strength})


def draw_button(cv, cx, cy, d, icon, badge=None, pressed=False, disabled=False):
    """CandyButton Ø d с центром (cx, cy): тень и лицо (×PRESS_SCALE у нажатой), значок-счётчик badge."""
    t = d * FACE_OVERSCAN
    k = CB["PRESS_SCALE"] if pressed else 1.0
    if not disabled:
        draw_soft_shadow(cv, cx - t / 2, cy - t / 2, t, t, FACE_SHAPE, 1.0, (0.0, d * CB["SHADOW_OFFSET"]),
                         d * CB["SHADOW_BLUR"], CB["SHADOW_STRENGTH"], k, CB["PRESS_NEAR"] if pressed else 1.0)
    draw_png(cv, icon, cx - t * k / 2, cy - t * k / 2, t * k, t * k, CB["DISABLED_ALPHA"] if disabled else 1.0)
    if badge is None:
        return
    # HintCounter: badge.png Ø 52 (метаданные badge_d), центр на (0,36·Ø; −0,36·Ø); тень своя; число Nunito 25.
    # У нажатой значок сжат вместе с лицом вокруг центра кнопки (pivot_offset в CandyButton._layout).
    bd = 52.0
    bs = bd * FACE_OVERSCAN * k
    bx, by = cx + d * CB["BADGE_SHIFT"] * k, cy - d * CB["BADGE_SHIFT"] * k
    draw_soft_shadow(cv, bx - bs / 2 / k, by - bs / 2 / k, bs / k, bs / k, (240 / 256, 240 / 256), 1.0,
                     (0.0, CB["BADGE_SHADOW_OFFSET"]), CB["BADGE_SHADOW_BLUR"], CB["BADGE_SHADOW_STRENGTH"], k)
    draw_png(cv, "badge", bx - bs / 2, by - bs / 2, bs, bs)
    ink = (0xA3 / 255, 0x16 / 255, 0x3A / 255, 1.0)
    draw_digit(cv, badge, bx, by - 1.5 * k, 25 * k, (1, 1, 1, 1), ink, 5.0 * k, (0, 0, 0, 0), (0, 0))


def draw_buttons(cv, badge="3", pressed=(), disabled=()):
    """Кнопки портрета на местах из GameLayout (layout_model): TopBar и ActionsBar, Ø 96 из game.tscn."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import layout_model
    L = layout_model.compute(720, 1280, False)
    d = BTN_D
    tx, ty, tw, th = L["top_bar"]
    ax, ay, aw, ah = L["actions"]
    places = {"pause": (tx + d / 2, ty + th / 2), "restart": (tx + tw - d / 2, ty + th / 2),
              "undo": (ax + d / 2, ay + ah / 2), "hint": (ax + aw - d / 2, ay + ah / 2)}
    for name, (cx, cy) in places.items():
        draw_button(cv, cx, cy, d, name, badge if name == "hint" else None, name in pressed, name in disabled)


# ---------------------------------------------------------------- шапка и плашка (13.2c): HudHeader + PillLabel

HH = {k: gd_value(gd_const("scenes/game/hud_header.gd", k)) for k in
      ("TITLE_OUTLINE", "TITLE_SHADOW", "TITLE_SHADOW_ALPHA", "SCORE_OUTLINE", "SCORE_SHADOW", "SCORE_SHADOW_ALPHA",
       "STAR_W", "STAR_X", "TEXT_X", "STAR_RISE", "STAR_R", "STAR_SHADOW_ALPHA")}
HH["STAR_FIT"] = 240.0 / 256.0
HH["STAR_SHADOW"] = gd_value(gd_const("scenes/game/hud_header.gd", "STAR_SHADOW"))
PL = {k: gd_value(gd_const("scripts/pill_label.gd", k)) for k in ("PAD_X", "HEIGHT_K", "TEXT_RISE")}
INK = gd_value(gd_const("scripts/palette.gd", "INK"))
DEEP = gd_value(gd_const("scripts/palette.gd", "DEEP"))
SCORE = gd_value(gd_const("scripts/palette.gd", "SCORE"))
UI_FONT = os.path.join(ROOT, "assets", "fonts", "nunito_extrabold.ttf")   # тема: Nunito 800 (13.3)


def _font(path, size):
    key = (path, int(round(size)))
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(path, key[1])
    return _fonts[key]


def draw_label(cv, text, cx, cy, size, fill, outline, frac_outline, shadow, shadow_alpha, frac_shadow, path=DIGIT_FONT):
    """Label HudHeader._style: обводка 2·доля·размер (полная), тень вниз доля·размер — обведённый текст DEEP."""
    o = round(2.0 * frac_outline * size)
    draw_digit(cv, text, cx, cy, size, fill + (1.0,), outline, o, shadow + (shadow_alpha,),
               (0, round(frac_shadow * size)), font_path=path)


def draw_star(cv, x, y, box, r):
    """StarIcon (STRETCH_SCALE) и TexShadow: альфа star.png, размытая (σ = 0,18 R) и сдвинутая вниз на 0,14 R."""
    from scipy.ndimage import gaussian_filter
    src = Image.open(os.path.join(ICONS, "star.png")).convert("RGBA")
    blur, off = 0.18 * r, 0.14 * r
    m = int(math.ceil(blur * 3 + off))
    n = int(round(box))
    a = np.zeros((n + 2 * m, n + 2 * m))
    a[m:m + n, m:m + n] = np.asarray(src.resize((n, n), Image.LANCZOS), dtype=float)[..., 3] / 255.0
    a = gaussian_filter(a, blur)
    a = np.roll(a, int(round(off)), axis=0)
    sh = np.zeros(a.shape + (4,))
    sh[..., :3] = HH["STAR_SHADOW"]
    sh[..., 3] = a * HH["STAR_SHADOW_ALPHA"]
    cv.over(int(round(x)) - m, int(round(y)) - m, sh)
    draw_png(cv, "star", x, y, box, box)


def draw_header(cv, L, level=20, score=2340):
    """HudHeader.relayout в TopBar раскладки L: заголовок, звезда, счёт (места строк — L)."""
    tx, ty, tw, th = L["top_bar"]
    cx = tx + tw / 2
    ts, ss = L["title_size"], L["score_size"]
    draw_label(cv, "УРОВЕНЬ %d" % level, cx, ty + L["title_y"], ts, (1.0, 1.0, 1.0), INK, HH["TITLE_OUTLINE"],
               DEEP, HH["TITLE_SHADOW_ALPHA"], HH["TITLE_SHADOW"])
    text = "{:,}".format(score).replace(",", "\u00a0")
    f = _font(DIGIT_FONT, ss)
    w = f.getlength(text)
    x0 = cx - (HH["TEXT_X"] * ss + w) / 2
    box = HH["STAR_W"] * ss / HH["STAR_FIT"]
    sy = ty + L["score_y"]
    draw_star(cv, x0 + HH["STAR_X"] * ss, sy - HH["STAR_RISE"] * ss - box / 2, box, HH["STAR_R"] * ss)
    draw_label(cv, text, x0 + HH["TEXT_X"] * ss + w / 2, sy, ss, SCORE, INK, HH["SCORE_OUTLINE"],
               DEEP, HH["SCORE_SHADOW_ALPHA"], HH["SCORE_SHADOW"])


def draw_pill(cv, L, text="Осталось блоков: 2"):
    """PillLabel: таблетка (pill.gdshader) шириной в текст + PAD_X, текст 800 белый, тень DEEP 55 % вниз 3."""
    rx, ry, rw, rh = L["remaining"]
    fs = L["remaining_size"]
    tw = _font(UI_FONT, fs).getlength(text)
    pw, ph = math.ceil(tw + 2 * PL["PAD_X"]), round(fs * PL["HEIGHT_K"])
    px, py = round(rx + (rw - pw) / 2), round(ry + (rh - ph) / 2 + PL["TEXT_RISE"])
    draw_rect(cv, "pill", px, py, pw, ph, 1.0, (1, 1, 1, 1), {"rect_size": (pw, ph)})
    draw_digit(cv, text, rx + rw / 2, ry + rh / 2, fs, (1, 1, 1, 1), (1, 1, 1), 0, DEEP + (0.55,), (0, 3),
               font_path=UI_FONT)


def render(bad=False):
    cols, rows, rects = load_level(LEVEL_N)
    ref = Image.open(os.path.join(FRAMES, "A3B_game.png")).convert("RGB")
    W, H = ref.size
    cv = background(W, H)   # Background (13.7) — фон шейдером, TIME = 0
    s = CELL_PX / CELL
    px = 1.0 / s
    ox, oy = BOARD_C[0] - cols * CELL_PX / 2, BOARD_C[1] - rows * CELL_PX / 2   # левый верх сетки на экране

    # Board/Frame
    m = (BD["FRAME_MARGIN"] + BD["PAD"]) * px
    fw, fh = cols * CELL + 2 * m, rows * CELL + 2 * m + BD["FRAME_DEPTH"] * px
    draw_rect(cv, "board", ox - m * s, oy - m * s, fw, fh, s, (1, 1, 1, 1), {
        "frame_size": (fw, fh), "grid": (float(cols), float(rows)), "px": px, "margin": BD["FRAME_MARGIN"],
        "pad": BD["PAD"], "rim": BD["RIM"], "lip": BD["FRAME_DEPTH"]})

    # Cells: гнёзда на числах, не закрытых блоками; магнит — числа площади несомого блока.
    x, y, bw, bh, nx, ny = rects[DRAGGED]
    drag_area = bw * bh
    covered = set()
    for i in PLACED:
        rx, ry, rw, rh, _, _ = rects[i]
        covered |= {(cx, cy) for cx in range(rx, rx + rw) for cy in range(ry, ry + rh)}
    for i, (rx, ry, rw, rh, nnx, nny) in enumerate(rects):
        if (nnx, nny) in covered:
            continue
        area = rw * rh
        on = area == drag_area
        k = CL["MAGNET_SCALE"] if on else 1.0
        alpha = 1.0 if on else DIM_A
        # Badge: pivot (50, 50), масштаб k, подъём MAGNET_LIFT логических px; Nest шире клетки на 48.
        bx, by = nnx * CELL, nny * CELL - (CL["MAGNET_LIFT"] * px if on else 0.0)
        nest_x = bx + 50 - 50 * k - 48 * k
        nest_y = by + 50 - 50 * k - 48 * k
        col = color_for(area)[:3] + (alpha,)
        draw_rect(cv, "nest", ox + nest_x * s, oy + nest_y * s, CELL + 96, CELL + 96, s * k, col,
                  {"px": px, "ring": 1.0 if on else 0.0, "margin": 48.0})
        draw_digit(cv, str(area), ox + (bx + 50) * s, oy + (by + 50) * s, 40 * s * k, color_for(area),
                   darkened(color_for(area), 0.42), CL["DIGIT_OUTLINE"] * s * k,
                   darkened(color_for(area), 0.5)[:3] + (0.35,), (0, 2 * s * k), alpha)

    # Board/Ghost — место несомого блока.
    gcol = GHOST_BAD if bad else color_for(drag_area)
    draw_rect(cv, "ghost", ox + x * CELL_PX, oy + y * CELL_PX, bw * CELL, bh * CELL, s, gcol,
              {"rect_size": (bw * CELL, bh * CELL), "px": px, "frame_alpha": 0.6 if bad else 1.0})

    # Блоки на поле — по рядам (Board._sort_block).
    for i in sorted(PLACED, key=lambda j: (rects[j][1], rects[j][0])):
        rx, ry, rw, rh, nnx, nny = rects[i]
        draw_block(cv, ox + rx * CELL_PX, oy + ry * CELL_PX, s, rw, rh, rw * rh, (nnx - rx, nny - ry), False)

    # Content/Tray — после поля, под слоем перетаскивания; кнопки TopBar и ActionsBar (13.2b).
    draw_tray(cv)
    draw_buttons(cv)
    import layout_model
    LP = layout_model.compute(720, 1280, False)
    draw_header(cv, LP)
    draw_pill(cv, LP)

    # Несомый блок: ×LIFT_SCALE от поля, цифра по центру; своего цвета и в --bad (DRAG_TINT_BAD убран 02.10).
    sl = s * B["LIFT_SCALE"]
    draw_block(cv, ox + x * CELL_PX + DRAG_OFF[0], oy + y * CELL_PX + DRAG_OFF[1], sl, bw, bh, drag_area, None, True,
               (1, 1, 1, 1))
    return cv.image(), ref


def main(argv):
    if "--py" in argv:
        name = argv[argv.index("--py") + 1]
        code, uni = translate(os.path.join(SHADERS, name + ".gdshader"))
        print("\n".join("%s = %s" % kv for kv in uni.items()))
        print(code)
        return
    bad = "--bad" in argv
    img, ref = render(bad)
    suffix = "_bad" if bad else ""
    out = os.path.join(FRAMES, "G13_1_game%s.png" % suffix)
    img.save(out, optimize=True)
    print(out)
    # Сравнение: эталон | Godot — поле (13.1) и полка лотка (13.2).
    title = " — «нельзя»" if bad else ""
    print(compare(ref, img, (0, 150, 720, 900), "Шейдеры Godot (13.1)" + title, "G13_1_compare%s.png" % suffix))
    if not bad:
        print(compare(ref, img, (0, 960, 720, 1280), "Шейдеры Godot (13.2)", "G13_2_compare.png"))
        print(compare_buttons(ref, img))
        print(compare_header(ref, img))
        print(render_states())


def render_states():
    """13.2b: состояния кнопки (раздел 8 STYLE) — обычная, наведение ×1,05, нажата, выключена; ×2."""
    ref = Image.open(os.path.join(FRAMES, "A3B_game.png")).convert("RGB")
    edge = np.asarray(ref, dtype=float)[870:1000, 3:4, :]
    labels = ("обычная", "наведение ×1,05", "нажата ×0,92", "выключена 45 %")
    cv = Canvas(np.repeat(edge, 4 * 150, axis=1))
    for i in range(4):
        cx, cy = 75 + 150 * i, 62
        d = BTN_D * (1.05 if i == 1 else 1.0)    # наведение масштабирует всю кнопку (Desktop.add_hover)
        # Выключенной бывает «Отмена» (нет ходов); подсказка выключена только после победы — без значков.
        draw_button(cv, cx, cy, d, "undo" if i == 3 else "hint", "1" if i < 3 else None, pressed=(i == 2),
                    disabled=(i == 3))
    img = cv.image()
    img = img.resize((img.width * 2, img.height * 2), Image.LANCZOS)
    out = Image.new("RGB", (img.width, img.height + 52), (30, 20, 70))
    out.paste(img, (0, 52))
    d = ImageDraw.Draw(out)
    f = ImageFont.truetype(DIGIT_FONT, 26)
    for i, lab in enumerate(labels):
        d.text((150 + 300 * i, 26), lab, font=f, fill=(255, 255, 255), anchor="mm")
    path = os.path.join(FRAMES, "G13_2b_states.png")
    out.save(path, optimize=True)
    return path


def compare_buttons(ref, img):
    """13.2b: кнопки крупно (×2) — эталон сверху, игра снизу; шапка и ряд «Отмена — подсказка»."""
    rows = [(0, 20, 720, 150), (0, 870, 720, 1000)]
    z = 2
    parts = []
    for src in (ref, img):
        for box in rows:
            c = src.crop(box)
            parts.append(c.resize((c.width * z, c.height * z), Image.LANCZOS))
    w = parts[0].width
    hh = [p.height for p in parts]
    cmp_im = Image.new("RGB", (w, sum(hh) + 56 * 2 + 12), (30, 20, 70))
    d = ImageDraw.Draw(cmp_im)
    f = ImageFont.truetype(DIGIT_FONT, 30)
    y = 0
    for i, lab in enumerate(("Эталон A3B_game (кнопки Ø 100)", "Игра: CandyButton + SoftShadow (Ø 96, game.tscn)")):
        d.text((16, y + 12), lab, font=f, fill=(255, 255, 255))
        y += 56
        for p in parts[i * 2:i * 2 + 2]:
            cmp_im.paste(p, (0, y))
            y += p.height
        y += 12
    out = os.path.join(FRAMES, "G13_2b_buttons.png")
    cmp_im.save(out, optimize=True)
    return out


def compare_header(ref, img):
    """13.2c: шапка и плашка «Осталось блоков» крупно (×2): эталон сверху, игра снизу."""
    rows = [(120, 20, 600, 150), (150, 905, 570, 972)]
    z = 2
    parts = [src.crop(b).resize(((b[2] - b[0]) * z, (b[3] - b[1]) * z), Image.LANCZOS) for src in (ref, img) for b in rows]
    w = max(p.width for p in parts)
    cmp_im = Image.new("RGB", (w, sum(p.height for p in parts) + 56 * 2 + 12), (30, 20, 70))
    d = ImageDraw.Draw(cmp_im)
    f = ImageFont.truetype(DIGIT_FONT, 30)
    y = 0
    for i, lab in enumerate(("Эталон A3B_game", "Godot (13.2c): HudHeader, PillLabel")):
        d.text((16, y + 12), lab, font=f, fill=(255, 255, 255))
        y += 56
        for p in parts[i * 2:i * 2 + 2]:
            cmp_im.paste(p, ((w - p.width) // 2, y))
            y += p.height
        y += 12
    out = os.path.join(FRAMES, "G13_2c_header.png")
    cmp_im.save(out, optimize=True)
    return out


def compare(ref, img, box, label, name):
    a, b = ref.crop(box), img.crop(box)
    cmp_im = Image.new("RGB", (a.width * 2 + 24, a.height + 56), (30, 20, 70))
    cmp_im.paste(a, (0, 56))
    cmp_im.paste(b, (a.width + 24, 56))
    d = ImageDraw.Draw(cmp_im)
    f = ImageFont.truetype(DIGIT_FONT, 30)
    d.text((16, 12), "Эталон A3B_game", font=f, fill=(255, 255, 255))
    d.text((a.width + 40, 12), label, font=f, fill=(255, 255, 255))
    out = os.path.join(FRAMES, name)
    cmp_im.save(out, optimize=True)
    return out


if __name__ == "__main__":
    main(sys.argv[1:])
