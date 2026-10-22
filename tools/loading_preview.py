#!/usr/bin/env python3
"""Кадр экрана загрузки (этап 16.4) без браузера: web/shell.html, нарисованный по его же CSS.

    python3 tools/loading_preview.py            # docs/style_frames/G16_4_loading.png
    python3 tools/loading_preview.py OUT.png

Четыре варианта: телефон 360×640 — полоса 60 %, размер неизвестен (бегущие полосы), ошибка «нет функций
браузера»; компьютер 16:9 (1138×640) — полоса 85 %. Масштаб — CSS-пиксели 1:1, сглаживание — рисунок ×3 и
уменьшение. Все размеры и цвета ниже — те же, что в web/shell.html; меняете там — поменяйте и здесь.

Шрифт сообщения на странице — системный (Nunito до старта игры не загружен): здесь Noto Sans ExtraBold как
замена Roboto / Segoe UI; если его нет — Nunito из assets/fonts.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "style_frames", "G16_4_loading.png")
SS = 3  # сверхвыборка

FONT_CANDIDATES = ["/usr/share/fonts/truetype/noto/NotoSans-ExtraBold.ttf",
                   "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
                   os.path.join(ROOT, "assets", "fonts", "nunito_extrabold.ttf")]

# --- web/shell.html ---------------------------------------------------------------------------------------
TOP, MID, BOTTOM = "#4A36E0", "#6A42E4", "#9A4CDB"
LIGHT = (0.5, 0.2, 0.75, 0.188)            # центр x, y (доли), радиус (vmax), сила
VIGNETTE = (0.5, 0.45, 0.71, 0.6, "#140646", 0.47)  # центр, радиус (vmax), начало, цвет, сила
BLOCK, GAP, RADIUS, LOGO_MARGIN = 64, 12, 16, 44
BLOCK_COLORS = ["#FF4B3E", "#FFD23F", "#3F7BFF", "#2FD67B"]  # b1 b2 b3 b4 (сетка 2×2 по строкам)
DELAYS = [0.0, 0.2, 0.6, 0.4]
HOP_PERIOD = 1.6
BAR_W, BAR_H, BAR_VW = 320, 22, 0.70
FILL, FILL_STRIPE, FILL_LIP = "#FFE45C", "#FFD23F", (176, 110, 0, 0.35)
NOTICE_MAX, NOTICE_VW, NOTICE_PAD, NOTICE_R, NOTICE_FS, NOTICE_LH, NOTICE_MT = 520, 0.86, (16, 22), 18, 18, 1.35, 28
INK = "#2E1678"

TEXT_RU = {"failed": "Не удалось запустить игру. Обновите страницу.",
           "missing": "Браузер не поддерживает нужные функции:",
           "browser": "Откройте игру в другом браузере или обновите этот."}


def rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def ease(x):
    """CSS ease-in-out = cubic-bezier(0.42, 0, 0.58, 1): x → y через параметр кривой."""
    lo, hi = 0.0, 1.0
    for _ in range(40):
        t = (lo + hi) / 2
        bx = 3 * (1 - t) ** 2 * t * 0.42 + 3 * (1 - t) * t ** 2 * 0.58 + t ** 3
        lo, hi = (t, hi) if bx < x else (lo, t)
    t = (lo + hi) / 2
    return 3 * (1 - t) * t ** 2 + t ** 3


def hop(t):
    """@keyframes hop: (translateY, scaleX, scaleY) в момент t секунд от начала цикла блока."""
    keys = [(0.0, 0, 1, 1), (0.2, -9, 0.96, 1.04), (0.4, 0, 1.06, 0.94), (0.6, 0, 1, 1), (1.0, 0, 1, 1)]
    if t < 0:
        return 0.0, 1.0, 1.0  # задержка ещё идёт: блок стоит
    p = (t % HOP_PERIOD) / HOP_PERIOD
    for a, b in zip(keys, keys[1:]):
        if a[0] <= p <= b[0]:
            k = ease((p - a[0]) / (b[0] - a[0]))
            return tuple(a[i] + (b[i] - a[i]) * k for i in (1, 2, 3))
    return 0.0, 1.0, 1.0


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.W, self.H = w * SS, h * SS
        self.px = np.zeros((self.H, self.W, 3))

    def mask(self, draw_fn):
        im = Image.new("L", (self.W, self.H), 0)
        draw_fn(ImageDraw.Draw(im))
        return np.asarray(im, dtype=np.float64) / 255.0

    def rrect(self, x0, y0, x1, y1, r):
        r = max(0.0, min(r, (x1 - x0) / 2, (y1 - y0) / 2))
        return self.mask(lambda d: d.rounded_rectangle([x0 * SS, y0 * SS, x1 * SS - 1, y1 * SS - 1],
                                                       radius=r * SS, fill=255))

    def over(self, m, color, alpha=1.0):
        a = (m * alpha)[..., None]
        self.px = self.px * (1 - a) + color[None, None, :] * a

    def image(self):
        im = Image.fromarray((np.clip(self.px, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
        return im.resize((self.w, self.h), Image.LANCZOS)


def background(cv):
    y, x = np.mgrid[0:cv.H, 0:cv.W]
    x = (x + 0.5) / SS
    y = (y + 0.5) / SS
    gy = y / cv.h
    top, mid, bot = rgb(TOP), rgb(MID), rgb(BOTTOM)
    a = np.clip(gy * 2, 0, 1)[..., None]
    b = np.clip(gy * 2 - 1, 0, 1)[..., None]
    col = (top * (1 - a) + mid * a) * (1 - b) + bot * b
    vmax = max(cv.w, cv.h)
    lx, ly, lr, ls = LIGHT
    ld = np.hypot(x - lx * cv.w, y - ly * cv.h) / (lr * vmax)
    k = (ls * (1 - np.clip(ld, 0, 1)))[..., None]
    col = col * (1 - k) + k
    vx, vy, vr, vs, vc, va = VIGNETTE
    d = np.hypot(x - vx * cv.w, y - vy * cv.h) / (vr * vmax)
    k = (va * np.clip((d - vs) / (1 - vs), 0, 1))[..., None]
    cv.px = col * (1 - k) + rgb(vc) * k


def block(cv, x0, y0, color, ty, sx, sy):
    cx, cy = x0 + BLOCK / 2, y0 + BLOCK / 2 + ty
    hw, hh = BLOCK / 2 * sx, BLOCK / 2 * sy
    r = RADIUS * min(sx, sy)
    body = cv.rrect(cx - hw, cy - hh, cx + hw, cy + hh, r)
    # box-shadow: 0 8px 14px rgba(20, 6, 70, 0.35) — размытие 14 px ≈ гаусс σ 7.
    sh = cv.rrect(cx - hw, cy - hh + 8 * sy, cx + hw, cy + hh + 8 * sy, r)
    sh = gaussian_filter(sh, 7 * SS)
    cv.over(sh * (1 - body), rgb("#140646"), 0.35)
    cv.over(body, rgb(color))
    # inset 0 -8px 0 rgba(0, 0, 0, 0.22): «губа» снизу.
    up = cv.rrect(cx - hw, cy - hh - 8 * sy, cx + hw, cy + hh - 8 * sy, r)
    cv.over(body * (1 - up), np.zeros(3), 0.22)
    # ::after — блик 22×10 в (10, 8), скругление 6, белый 45 %.
    bx, by = cx - hw + 10 * sx, cy - hh + 8 * sy
    cv.over(cv.rrect(bx, by, bx + 22 * sx, by + 10 * sy, 6 * min(sx, sy)), np.ones(3), 0.45)


def bar(cv, x0, y0, w, progress):
    tray = cv.rrect(x0, y0, x0 + w, y0 + BAR_H, BAR_H / 2)
    cv.over(tray, np.ones(3), 0.22)
    if progress is None:  # бегущие полосы: -45°, 14 px / 14 px
        fill = tray
        y, x = np.mgrid[0:cv.H, 0:cv.W]
        t = ((x + y) / SS / math.sqrt(2)) % 28
        stripe = (t >= 14).astype(np.float64)
        cv.over(fill, rgb(FILL))
        cv.over(fill * stripe, rgb(FILL_STRIPE))
    else:
        fw = w * progress
        fill = cv.rrect(x0, y0, x0 + fw, y0 + BAR_H, BAR_H / 2) * tray
        cv.over(fill, rgb(FILL))
    lip = cv.rrect(x0, y0 - 5, x0 + w, y0 + BAR_H - 5, BAR_H / 2)
    cv.over(fill * (1 - lip), np.array(FILL_LIP[:3]) / 255.0, FILL_LIP[3])
    # inset 0 3px 0 rgba(20, 6, 70, 0.25) — тень сверху жёлоба (поверх заливки, как inset у #bar).
    down = cv.rrect(x0, y0 + 3, x0 + w, y0 + BAR_H + 3, BAR_H / 2)
    cv.over(tray * (1 - down), rgb("#140646"), 0.25)


def wrap(text, font, max_w):
    lines = []
    for para in text.split("\n"):
        words, cur = para.split(" "), ""
        if para == "":
            lines.append("")
            continue
        for wd in words:
            cand = (cur + " " + wd).strip()
            if font.getlength(cand) <= max_w or not cur:
                cur = cand
            else:
                lines.append(cur)
                cur = wd
        lines.append(cur)
    return lines


def font_path():
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            return p
    raise SystemExit("нет шрифта: " + ", ".join(FONT_CANDIDATES))


def notice_box(cv, text):
    font = ImageFont.truetype(font_path(), NOTICE_FS)
    max_outer = min(NOTICE_MAX, NOTICE_VW * cv.w)
    lines = wrap(text, font, max_outer - 2 * NOTICE_PAD[1])
    inner_w = max(font.getlength(s) for s in lines)
    lh = NOTICE_FS * NOTICE_LH
    return lines, inner_w + 2 * NOTICE_PAD[1], len(lines) * lh + 2 * NOTICE_PAD[0], lh


def draw_notice(cv, x0, y0, w, h, lines, lh):
    cv.over(cv.rrect(x0, y0, x0 + w, y0 + h, NOTICE_R), np.ones(3), 0.95)
    font = ImageFont.truetype(font_path(), NOTICE_FS * SS)
    im = Image.new("L", (cv.W, cv.H), 0)
    d = ImageDraw.Draw(im)
    for i, s in enumerate(lines):
        cy = y0 + NOTICE_PAD[0] + (i + 0.5) * lh
        d.text(((x0 + w / 2) * SS, cy * SS), s, font=font, fill=255, anchor="mm")
    cv.over(np.asarray(im, dtype=np.float64) / 255.0, rgb(INK))


def render(w, h, progress=0.6, failed=None, t=0.32):
    cv = Canvas(w, h)
    background(cv)
    logo = 2 * BLOCK + GAP
    if failed:
        lines, nw, nh, lh = notice_box(cv, failed)
        total = logo + LOGO_MARGIN + NOTICE_MT + nh  # полоса скрыта (display: none)
    else:
        total = logo + LOGO_MARGIN + BAR_H
    y0 = (h - total) / 2
    x0 = (w - logo) / 2
    for i, color in enumerate(BLOCK_COLORS):
        ty, sx, sy = (0.0, 1.0, 1.0) if failed else hop(t + HOP_PERIOD - DELAYS[i])
        block(cv, x0 + (i % 2) * (BLOCK + GAP), y0 + (i // 2) * (BLOCK + GAP), color, ty, sx, sy)
    if failed:
        draw_notice(cv, (w - nw) / 2, y0 + logo + LOGO_MARGIN + NOTICE_MT, nw, nh, lines, lh)
    else:
        bw = min(BAR_W, BAR_VW * w)
        bar(cv, (w - bw) / 2, y0 + logo + LOGO_MARGIN, bw, progress)
    return cv.image()


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else OUT
    missing = TEXT_RU["missing"] + "\nWebGL2\n\n" + TEXT_RU["browser"]
    frames = [("Телефон 360×640 — загрузка 60 %", render(360, 640, 0.6)),
              ("Размер неизвестен — полосы", render(360, 640, None, t=0.9)),
              ("Нет функций браузера", render(360, 640, failed=missing)),
              ("Компьютер 16:9 (1138×640) — 85 %", render(1138, 640, 0.85, t=0.5))]
    pad, head = 24, 44
    cap = ImageFont.truetype(font_path(), 20)
    sheet_w = pad + sum(im.width + pad for _, im in frames)
    sheet = Image.new("RGB", (sheet_w, head + 640 + pad), (34, 22, 70))
    d = ImageDraw.Draw(sheet)
    x = pad
    for title, im in frames:
        d.text((x, head / 2 + 2), title, font=cap, fill=(235, 230, 255), anchor="lm")
        sheet.paste(im, (x, head))
        x += im.width + pad
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    sheet.save(out, optimize=True)
    print("кадр:", out, sheet.size)


if __name__ == "__main__":
    main()
