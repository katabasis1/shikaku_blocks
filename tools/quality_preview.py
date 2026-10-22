#!/usr/bin/env python3
"""Этап 14.7e: кадр сравнения уровней качества — «высокое» | «среднее» | «низкое» | разница (низкое − высокое).

Godot в песочнице нет, поэтому то, что меняют уровни, считается здесь тем же способом, что в игре
(числа — из juice_config.gd, background.gd, tex_shadow.gd, win_panel.gd, hud_header.gd):

  ряд «Фон»   — shaders/background.gdshader (перевод tools/shader_preview.py) на телефоне 1080×1920
                (720×1280 ×1,5), кусок 320×320 px экрана 1:1. Высокое — шейдер на каждый пиксель; среднее —
                SubViewport Bake в quality_bg_scale экрана (540×960), на экран — та же ветка шейдера, что в игре
                (use_baked: texture(baked, UV), filter_linear); низкое — весь 2D в базовом 720×1280
                (content_scale_mode VIEWPORT): Bake 360×640 → ветка use_baked в 720×1280 → растяжение окна до
                1080×1920 (линейное — допущение кадра).
  ряд «Тень звезды» — TexShadow средней звезды окна победы (R 73: σ 13, сдвиг 10,4, box 136) по формуле
                shaders/tex_shadow.gdshader: textureLod по цепочке mip (2×2 среднее, трилинейно). Высокое и
                среднее — 7×7 отсчётов с шагом 0,75σ; низкое — 3×3 с шагом 1,25σ по mip на log2(σ) − 0,5 выше
                и весь 2D в 720 → ×1,5.
  ряд «Текст» — «УРОВЕНЬ 12» шапки (Nunito 1000, 50, обводка и тень как HudHeader): на низком нарисован в
                720 и растянут ×1,5; кусок 160×160 увеличен ×2 (по пикселям).
  ряд «Конфетти» — залп победы через 0,45 с (tools/window_preview.py draw_confetti): 70 / 35 / 21 кусочков
                (Confetti.COUNT × quality_particles_*); экран 720×900, уменьшен вдвое. В последнем столбце —
                таблица остальных чисел уровня.

    python3 tools/quality_preview.py     # -> docs/style_frames/G14_7_quality.png (≈ 5 с)

Поменяли числа группы «Качество», Background, TexShadow или их шейдеры — пересоберите кадр.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_preview as sp  # noqa: E402
import window_preview as wp  # noqa: E402
import close_preview as cp   # noqa: E402

ROOT = sp.ROOT
OUT = os.path.join(sp.FRAMES, "G14_7_quality.png")
_JC = cp.juice_config()   # @export var группы «Качество» и др. (theme/juice.tres их не меняет)


def jc(name):
    return _JC[name]


def gdc(path, name):
    return sp.gd_value(sp.gd_const(path, name))


BG_SCALE = jc("quality_bg_scale")          # 0,5
P_MID, P_LOW = jc("quality_particles_mid"), jc("quality_particles_low")
DPR = 1.5                                  # телефон 1080×1920 при базе 720×1280
SW, SH = 1080, 1920
BW, BH = 720, 1280
CELL = 320                                 # клетка кадра
BG_CROP = (380, 300)                       # левый верх куска фона, px экрана телефона
BG_MID = (0.416, 0.259, 0.894)             # #6A42E4 — середина градиента фона (STYLE 9)
CARD_BG = (0.957, 0.933, 1.0)              # светлая подложка под звездой (видно тень)


# ================================================================ общее

def bilinear(img, out_w, out_h):
    """Растяжение как у GPU (filter_linear, clamp): центр выходного пикселя → UV → тексель − 0,5."""
    h, w = img.shape[:2]
    tx = (np.arange(out_w) + 0.5) / out_w * w - 0.5
    ty = (np.arange(out_h) + 0.5) / out_h * h - 0.5
    x0 = np.floor(tx).astype(int)
    y0 = np.floor(ty).astype(int)
    fx = (tx - x0)[None, :, None]
    fy = (ty - y0)[:, None, None]
    x0c, x1c = np.clip(x0, 0, w - 1), np.clip(x0 + 1, 0, w - 1)
    y0c, y1c = np.clip(y0, 0, h - 1), np.clip(y0 + 1, 0, h - 1)
    a = img[y0c][:, x0c]
    b = img[y0c][:, x1c]
    c = img[y1c][:, x0c]
    d = img[y1c][:, x1c]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def nearest_up(img, k):
    return np.repeat(np.repeat(img, k, axis=0), k, axis=1)


def diff_img(a, b, gain):
    d = np.abs(a - b).max(axis=2) * gain
    return np.repeat(np.clip(d, 0, 1)[..., None], 3, axis=2)


def stats(a, b):
    d = np.abs(a - b) * 255.0
    return d.mean(), d.max()


# ================================================================ фон

def bg_pixels(w, h, x0=0, y0=0, cw=None, ch=None, time=0.0, baked=None):
    """Background на цели w×h (rect_size 720×1280 — размер узла в виртуальных px), кусок cw×ch с (x0, y0).
    baked — картинка SubViewport Bake (массив h×w×3): тогда ветка use_baked шейдера (как на среднем и низком)."""
    cw = w if cw is None else cw
    ch = h if ch is None else ch
    light = gdc("scenes/ui/background.gd", "LIGHT")
    sh = sp.Shader.get("background")
    out = np.zeros((ch, cw, 3))
    band = max(16, 240000 // cw)
    xs = (np.arange(x0, x0 + cw) + 0.5) / w
    for b0 in range(0, ch, band):
        ys = (np.arange(y0 + b0, y0 + min(ch, b0 + band)) + 0.5) / h
        u, v = np.meshgrid(xs, ys)
        prm = {"rect_size": (BW, BH), "light": light}
        if baked is not None:
            prm.update(use_baked=True, baked=baked)
        col = sh.run(sp.V([u, v]), (1, 1, 1, 1), prm, time)
        for i in range(3):
            out[b0:b0 + len(ys), :, i] = np.clip(np.broadcast_to(col.c[i], u.shape), 0, 1)
    return out


def row_background():
    x, y = BG_CROP
    hi = bg_pixels(SW, SH, x, y, CELL, CELL)
    # среднее: Bake = ceil(720 · 0,5 · 1,5) × ceil(1280 · 0,5 · 1,5), растянут на экран
    mw, mh = math.ceil(BW * BG_SCALE * DPR), math.ceil(BH * BG_SCALE * DPR)
    mid = bg_pixels(SW, SH, x, y, CELL, CELL, baked=bg_pixels(mw, mh))
    # низкое: весь 2D в 720×1280, Bake = 0,5 от него, потом окно растягивает 720 → 1080
    lw, lh = math.ceil(BW * BG_SCALE), math.ceil(BH * BG_SCALE)
    fb = bg_pixels(BW, BH, baked=bg_pixels(lw, lh))
    low = bilinear(fb, SW, SH)[y:y + CELL, x:x + CELL]
    # проверка ветки use_baked: тот же кусок, что дало бы растяжение формулой (bilinear) — до округления
    ref = bilinear(bg_pixels(mw, mh), SW, SH)[y:y + CELL, x:x + CELL]
    assert np.abs(ref - mid).max() < 1e-9, "ветка use_baked ≠ линейному растяжению"
    return hi, mid, low, (mw, mh), (lw, lh)


# ================================================================ тень звезды (TexShadow)

def mip_chain(a):
    levels = [a]
    while levels[-1].shape[0] > 1:
        m = levels[-1]
        levels.append((m[0::2, 0::2] + m[1::2, 0::2] + m[0::2, 1::2] + m[1::2, 1::2]) / 4.0)
    return levels


def tex_bil(img, u, v):
    n = img.shape[0]
    tx, ty = u * n - 0.5, v * n - 0.5
    x0, y0 = np.floor(tx).astype(int), np.floor(ty).astype(int)
    fx, fy = tx - x0, ty - y0
    x0c, x1c = np.clip(x0, 0, n - 1), np.clip(x0 + 1, 0, n - 1)
    y0c, y1c = np.clip(y0, 0, n - 1), np.clip(y0 + 1, 0, n - 1)
    return ((img[y0c, x0c] * (1 - fx) + img[y0c, x1c] * fx) * (1 - fy)
            + (img[y1c, x0c] * (1 - fx) + img[y1c, x1c] * fx) * fy)


def texture_lod(levels, u, v, lod):
    lod = min(max(lod, 0.0), len(levels) - 1.0)
    l0 = int(math.floor(lod))
    f = lod - l0
    s = tex_bil(levels[l0], u, v)
    if f > 0 and l0 + 1 < len(levels):
        s = s * (1 - f) + tex_bil(levels[l0 + 1], u, v) * f
    return s


def tex_shadow_alpha(levels, n_px, rect, tex_lo, tex_size, offset, blur, reach, step_k, lod_bias, strength):
    """tex_shadow.gdshader на сетке n_px × n_px пикселей экрана узла rect × rect (виртуальные px)."""
    c = (np.arange(n_px) + 0.5) / n_px
    u, v = np.meshgrid(c, c)
    px = u * rect - tex_lo - offset[0]
    py = v * rect - tex_lo - offset[1]
    ts = levels[0].shape[0]
    lod = math.log2(max(ts / max(tex_size, 1.0), 1.0)) + lod_bias
    step_px = max(blur, 0.001) * step_k
    wk = step_k * step_k * 0.5
    a = np.zeros_like(px)
    wsum = 0.0
    for j in range(-reach, reach + 1):
        for i in range(-reach, reach + 1):
            w = math.exp(-(i * i + j * j) * wk)
            qx, qy = (px + i * step_px) / tex_size, (py + j * step_px) / tex_size
            inside = (qx >= 0) & (qy >= 0) & (qx <= 1) & (qy <= 1)
            a += np.where(inside, texture_lod(levels, np.clip(qx, 0, 1), np.clip(qy, 0, 1), lod), 0.0) * w
            wsum += w
    return strength * a / wsum


def star_scene(scale, low):
    """Звезда окна победы с тенью на светлом, в пикселях экрана (scale px на виртуальный px)."""
    wpg = "scenes/ui/win_panel.gd"
    r = wp.gd_list(wpg, "STAR_R")[1]
    q = r / 56.0
    blur, off = 10.0 * q, (0.0, 8.0 * q)
    box = 1.75 * r / wp.gd(wpg, "STAR_FIT")
    m = math.ceil(blur * 3 + max(abs(off[0]), abs(off[1])))
    rect = box + 2 * m
    tsg = "scripts/tex_shadow.gd"
    if low:
        reach, step_k = int(round(gdc(tsg, "LOW_REACH"))), gdc(tsg, "LOW_STEP")
        bias = max(math.log2(max(blur, 1.0)) + gdc(tsg, "LOW_LOD_SHIFT"), 0.0)
    else:
        reach, step_k, bias = int(round(gdc(tsg, "REACH"))), gdc(tsg, "STEP"), 0.0
    src = Image.open(os.path.join(ROOT, "assets", "icons", "star.png")).convert("RGBA")
    alpha = np.asarray(src, dtype=float)[..., 3] / 255.0
    n_px = int(round(rect * scale))
    a = tex_shadow_alpha(mip_chain(alpha), n_px, rect, m, box, off, blur, reach, step_k, bias,
                         gdc(wpg, "STAR_SHADOW_ALPHA"))
    shade = np.asarray(gdc(wpg, "STAR_SHADOW")[:3])
    base = np.asarray(CARD_BG)
    img = base[None, None, :] * (1 - a[..., None]) + shade[None, None, :] * a[..., None]
    only = img.copy()   # одна тень, без звезды: разница уровней — по ней (края самой звезды мягче из-за 720)
    sb = int(round(box * scale))
    star = np.asarray(src.resize((sb, sb), Image.LANCZOS), dtype=float) / 255.0
    o = int(round(m * scale))
    sa = star[..., 3:4]
    img[o:o + sb, o:o + sb] = star[..., :3] * sa + img[o:o + sb, o:o + sb] * (1 - sa)
    return img, only, (2 * reach + 1) ** 2, blur


def row_shadow():
    hi, hi_only, n_hi, blur = star_scene(DPR, False)
    lo720, lo720_only, n_lo, _ = star_scene(1.0, True)
    n = hi.shape[0]
    lo = bilinear(lo720, n, n)
    lo_only = bilinear(lo720_only, n, n)
    c0 = (n - CELL) // 2

    def crop(img):
        return img[c0:c0 + CELL, c0:c0 + CELL]
    return crop(hi), crop(hi), crop(lo), crop(hi_only), crop(lo_only), n_hi, n_lo, blur


# ================================================================ текст шапки

def title_canvas(scale):
    size = 50.0 * scale
    w, h = int(round(420 * scale)), int(round(170 * scale))
    cv = sp.Canvas(np.ones((h, w, 3)) * np.asarray(BG_MID) * 255.0)
    sp.draw_label(cv, "УРОВЕНЬ 12", w / 2, h / 2, size, (1.0, 1.0, 1.0), sp.INK, sp.HH["TITLE_OUTLINE"],
                  sp.DEEP, sp.HH["TITLE_SHADOW_ALPHA"], sp.HH["TITLE_SHADOW"])
    return cv.rgb


def row_text():
    hi = title_canvas(DPR)
    lo = bilinear(title_canvas(1.0), hi.shape[1], hi.shape[0])
    half = CELL // 2
    y0 = (hi.shape[0] - half) // 2
    ink = np.abs(hi - np.asarray(BG_MID)[None, None, :]).max(axis=2).max(axis=0) > 0.05
    x0 = max(0, int(np.argmax(ink)) - 8)     # кусок — с левого края первой буквы

    def crop(img):
        return nearest_up(img[y0:y0 + half, x0:x0 + half], 2)
    return crop(hi), crop(hi), crop(lo)


# ================================================================ конфетти

def confetti_panel(share):
    count0 = wp.CF["COUNT"]
    n = int(math.floor(count0 * share + 0.5))
    wp.CF["COUNT"] = n
    try:
        cv = sp.Canvas(np.ones((900, 720, 3)) * np.asarray(BG_MID) * 255.0)
        wp.draw_confetti(cv, (360.0, 520.0), 0.45)
    finally:
        wp.CF["COUNT"] = count0
    img = Image.fromarray((np.clip(cv.rgb, 0, 1) * 255 + 0.5).astype(np.uint8)).resize((360, 450), Image.LANCZOS)
    return np.asarray(img, dtype=float)[:450 * CELL // 360, 20:20 + CELL] / 255.0, n


# ================================================================ сборка

def to_img(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def ru(x, f="%.1f"):
    return (f % x).replace(".", ",")


def main():
    font = sp._font(sp.UI_FONT, 22)
    small = sp._font(sp.UI_FONT, 17)
    left, top, gap = 230, 96, 12
    rows = []
    print("фон…")
    bg_hi, bg_mid, bg_low, mid_sz, low_sz = row_background()
    m_mean, m_max = stats(bg_mid, bg_hi)
    l_mean, l_max = stats(bg_low, bg_hi)
    rows.append(("Фон", ["шейдер на каждый", "пиксель, 1080×1920;",
                         "среднее: Bake %d×%d," % mid_sz, "20 раз/с, разница", "ср. %s, макс. %.0f;" % (ru(m_mean, "%.2f"), m_max),
                         "низкое: Bake %d×%d" % low_sz, "в 720×1280, 5 раз/с,", "разница ср. %s," % ru(l_mean, "%.2f"),
                         "макс. %.0f из 255" % l_max],
                 [bg_hi, bg_mid, bg_low, diff_img(bg_low, bg_hi, 8.0)], CELL))
    print("тень…")
    s_hi, s_mid, s_low, sh_hi, sh_low, n_hi, n_lo, blur = row_shadow()
    s_mean, s_max = stats(sh_low, sh_hi)
    rows.append(("Тень звезды", ["звезда окна победы,", "размытие %.0f px;" % blur, "отсчётов %d / %d / %d;" % (n_hi, n_hi, n_lo),
                                 "разница одной тени:", "ср. %s, макс. %.0f" % (ru(s_mean), s_max),
                                 "(край звезды на", "низком мягче — 720)"],
                 [s_hi, s_mid, s_low, diff_img(sh_low, sh_hi, 8.0)], CELL))
    print("текст…")
    t_hi, t_mid, t_low = row_text()
    t_mean, t_max = stats(t_low, t_hi)
    rows.append(("Текст", ["«УРОВЕНЬ 12», ×2", "по пикселям; низкое —", "весь 2D в 720,", "растянут до 1080", "(мягче)"],
                 [t_hi, t_mid, t_low, diff_img(t_low, t_hi, 2.0)], CELL))
    print("конфетти…")
    panels = [confetti_panel(k) for k in (1.0, P_MID, P_LOW)]
    rows.append(("Конфетти", ["залп победы", "через 0,45 с:", "%d / %d / %d" % tuple(p[1] for p in panels),
                              "кусочков"], [p[0] for p in panels] + [None], panels[0][0].shape[0]))

    H = top + sum(r[3] + gap for r in rows) + 10
    W = left + 4 * (CELL + gap) + 10
    img = Image.new("RGB", (W, H), (30, 22, 60))
    d = ImageDraw.Draw(img)
    heads = ["высокое", "среднее", "низкое", "|низкое − высокое|"]
    sub = ["", "", "", "×8 (текст ×2)"]
    d.text((12, 12), "G14_7: уровни качества (14.7) — телефон 1080×1920, база 720×1280", font=font, fill=(255, 228, 92))
    for c, t in enumerate(heads):
        x = left + c * (CELL + gap)
        d.text((x + 4, 48), t, font=font, fill=(255, 255, 255))
        if sub[c]:
            d.text((x + 4, 72), sub[c], font=small, fill=(200, 190, 240))
    y = top
    for name, notes, cells, hh in rows:
        d.text((12, y + 4), name, font=font, fill=(255, 255, 255))
        for i, line in enumerate(notes):
            d.text((12, y + 36 + i * 22), line, font=small, fill=(210, 200, 245))
        for c, a in enumerate(cells):
            x = left + c * (CELL + gap)
            if a is None:
                continue
            img.paste(to_img(a), (x, y))
        y += hh + gap
    # таблица остальных чисел — в пустой клетке ряда «Конфетти»
    x = left + 3 * (CELL + gap)
    y = H - 10 - rows[-1][3]
    pmax = jc("particles_max")
    lines = ["Остальное (STYLE 12):",
             "частиц во вспышке: 100 / %d / %d %%" % (round(P_MID * 100), round(P_LOW * 100)),
             "предел в воздухе: %d / %d / %d" % (pmax, round(pmax * P_MID), round(pmax * P_LOW)),
             "искры звезды окна: %d / %d / %d" % tuple(int(math.floor(jc("star_sparks") * k + 0.5)) for k in (1, P_MID, P_LOW)),
             "след искры подсказки: 12 / 6 / 4",
             "фон: каждый кадр / %g / %g раз/с" % (jc("quality_bg_fps_mid"), jc("quality_bg_fps_low")),
             "«Меньше движения» — ×%s к доле" % ru(jc("reduced_particles"), "%g"),
             "темп и тайминги анимаций —", "одинаковые на всех уровнях"]
    for i, line in enumerate(lines):
        d.text((x + 4, y + 4 + i * 24), line, font=small if i else font, fill=(230, 225, 255) if i else (255, 228, 92))
    img.save(OUT, optimize=True)
    print("фон: среднее |Δ| %.2f (max %.0f), низкое |Δ| %.2f (max %.0f); тень |Δ| %.2f (max %.0f); текст |Δ| %.2f (max %.0f)"
          % (m_mean, m_max, l_mean, l_max, s_mean, s_max, t_mean, t_max))
    print("->", os.path.relpath(OUT, ROOT), img.size)


if __name__ == "__main__":
    main()
