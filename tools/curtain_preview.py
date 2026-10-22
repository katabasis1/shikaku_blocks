"""Раскадровка шторки перехода (14.6c): numpy-повтор shaders/transition.gdshader поверх стиль-кадров.

Запуск: python3 tools/curtain_preview.py  ->  docs/style_frames/G14_6_curtain.png
Числа — как в theme/juice.tres (группа «Появление и переходы»): curtain_cell 0,11 короткой стороны,
curtain_radius 0,24, curtain_spread 0,5. Проверяет и швы: в конце закрытия экран залит целиком, в конце
открытия — пуст.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COLOR = np.array([0.482, 0.325, 0.878]) * 255
CELL_K, RADIUS, SPREAD = 0.11, 0.24, 0.5


def sd_box(px, py, cx, cy, h, r):
    rr = np.minimum(r, h)
    qx = np.abs(px - cx) - h + rr
    qy = np.abs(py - cy) - h + rr
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - rr


def grow(diag, progress, opening):
    w = np.clip((progress - diag * SPREAD) / max(1 - SPREAD, 1e-3), 0, 1)
    k = 1 - w if opening else w
    return k * k * (3 - 2 * k)


def coverage(w, h, progress, opening):
    cell = max(CELL_K * min(w, h), 8.0)
    py, px = np.mgrid[0:h, 0:w].astype(np.float64) + 0.5
    n = np.maximum(np.ceil(np.array([w, h]) / cell), 1)
    ox, oy = (np.array([w, h]) - n * cell) * 0.5
    qx, qy = px - ox, py - oy
    own_x, own_y = np.floor(qx / cell), np.floor(qy / cell)
    r = RADIUS * cell
    diag_max = max(n[0] + n[1] - 2, 1)
    hx, hy = np.clip(own_x, 0, n[0] - 1), np.clip(own_y, 0, n[1] - 1)
    m = (grow((hx + hy) / diag_max, progress, opening) >= 1.0).astype(np.float64)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ix = np.clip(own_x + dx, 0, n[0] - 1)
            iy = np.clip(own_y + dy, 0, n[1] - 1)
            k = grow((ix + iy) / diag_max, progress, opening)
            cx, cy = (ix + 0.5) * cell, (iy + 0.5) * cell
            hh = k * (0.5 * cell + r)
            d = sd_box(qx, qy, cx, cy, hh, r)
            m = np.maximum(m, np.where(k > 0, np.clip(0.5 - d, 0, 1), 0))
    return m


def frame(scene, progress, opening):
    a = np.asarray(scene.convert("RGB"), dtype=np.float64)
    m = coverage(a.shape[1], a.shape[0], progress, opening)[..., None]
    return Image.fromarray((a * (1 - m) + COLOR * m).astype(np.uint8)), m


def main():
    sf = os.path.join(ROOT, "docs", "style_frames")
    # Сцена «до» — окно победы (оттуда «В меню»), «после» — игра; оба кадра 720×1280.
    menu = Image.open(os.path.join(sf, "A3B_win.png")).convert("RGB")
    game = Image.open(os.path.join(sf, "A3B_game.png")).convert("RGB").resize(menu.size)
    steps = [(menu, 0.25, False, "закрытие 25 %"), (menu, 0.5, False, "закрытие 50 %"),
             (menu, 0.75, False, "закрытие 75 %"), (game, 0.3, True, "открытие 30 %"),
             (game, 0.6, True, "открытие 60 %"), (game, 0.85, True, "открытие 85 %")]
    w, h = 360, 640
    sheet = Image.new("RGB", (w * 3 + 40, (h + 50) * 2 + 20), (40, 24, 90))
    dr = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "nunito_extrabold.ttf"), 26)
    except OSError:
        font = ImageFont.load_default()
    for i, (scene, p, opening, title) in enumerate(steps):
        im, _ = frame(scene, p, opening)
        x, y = 10 + (i % 3) * (w + 10), 10 + (i // 3) * (h + 50)
        sheet.paste(im.resize((w, h), Image.LANCZOS), (x, y + 40))
        dr.text((x + 6, y + 4), title, font=font, fill=(240, 232, 255))
    out = os.path.join(sf, "G14_6_curtain.png")
    sheet.save(out)
    full = coverage(720, 1280, 1.0, False).min()
    empty = coverage(720, 1280, 1.0, True).max()
    land_full = coverage(1280, 720, 1.0, False).min()
    print(f"{out}: конец закрытия — покрытие от {full:.3f}, альбом {land_full:.3f}; конец открытия — до {empty:.3f}")


if __name__ == "__main__":
    main()
