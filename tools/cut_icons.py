#!/usr/bin/env python3
"""Этап 12.3g: нарезка листов иконок из нейросети (docs/icons/raw) в assets/icons/*.png 256×256.

Листы — ChatGPT Image, 1536×1024, сетка 3×2 (листы 1–3), 4×2 (лист 5) и 5×2 (лист 6), docs/icons/PROMPTS.md:
  sheet1_game.png      pause, restart, undo / hint, home, settings
  sheet2_settings.png  music_on, sound_on, vibration_on / music_off, sound_off, vibration_off
  sheet3_items.png     star, star_empty, ad / hand, badge, slash
  sheet5_marks.png     trophy, lock, medal_gold, medal_silver / medal_bronze, obstacle, tint_frame, rivet
                       (10.10, белый фон; этапы 18–19: меню, карта, лидеры, механики на поле)
  sheet6_nodes.png     node_red, node_orange, node_yellow, node_sky, node_blue /
                       node_pink, node_magenta, node_green, node_violet, node_white
                       (10.10, белый фон; пустые кружки уровней карты и «Лаборатории», ячейка 307 × 512)

Что делает с каждой ячейкой (512×512, у листа 6 — 307×512):
  1. альфа < 8 -> 0 (у ChatGPT вокруг иконок «дымка» с альфой 1–4, глазом не видна, но мешает);
  2. оставляет только самую крупную деталь (альфа ≥ 128) с дырками и каймой 3 px, остальное — 0;
  3. альфа ≥ 240 -> 255 (внутри иконок у ChatGPT 253, иконка чуть просвечивала бы);
  4. цвет прозрачных пикселей = цвет ближайшего непрозрачного (нет тёмной каймы при фильтрации);
  5. масштаб и центр: кнопки и диски (медали, заклёпка) — по кругу (диаметр BTN_D), предметы — по рамке (FIT),
     плитки (obstacle, tint_frame) — рамка растягивается в квадрат FIT × FIT (на листе они 320 × 319 и 327 × 318:
     в игре обе ложатся в одну клетку), рука — по высоте, кончик пальца у верхнего края (HAND_TOP).
Лист без альфы (белый фон, Nano Banana, лист 5 из ChatGPT) тоже годится: фон вырезается заливкой от краёв ячейки.
Дырки, которые заливка от краёв не достаёт, вырезаются по точке (HOLES): дужка замка (там ChatGPT нарисовал
«шахматку» прозрачности) и середина рамки цветной клетки — заливка светлых пикселей до тёмной обводки.

Печатает: размеры, сдвиг знака OFF относительно ON (должен быть ≤ 3 px), кончик пальца руки и
pivot для scenes/ui/tutorial_hand.tscn (TextureRect 120×120), а для листа 5 — числа для кода: центр лица медали
(LeaderRows.MEDAL_FACE_Y) и дырку рамки (от неё — CellMark.TINT_FILL_K); для листа 6 — лицо кружка над губой
(MapPath.FACE_Y_K, FACE_K) и одинаковость кружков (размер, середина лица — разброс должен быть ≤ 2 px).

    python3 tools/cut_icons.py            # -> assets/icons/*.png
    python3 tools/cut_icons.py --out DIR
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as nd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "docs", "icons", "raw")
OUT = os.path.join(ROOT, "assets", "icons")

N = 256          # сторона PNG
BTN_D = 240      # диаметр кнопки с обводкой (8 px поля: под тень и «пружину» при нажатии)
FIT = 240        # предметы: большая сторона рамки
HAND_TOP = 4     # рука: кончик пальца на 4 px ниже верхнего края, низ манжеты — у нижнего
HAND_RECT = 120  # сторона TextureRect руки в tutorial_hand.tscn

SHEETS = [
    ("sheet1_game.png", 3, ["pause", "restart", "undo", "hint", "home", "settings"]),
    ("sheet2_settings.png", 3, ["music_on", "sound_on", "vibration_on", "music_off", "sound_off", "vibration_off"]),
    ("sheet3_items.png", 3, ["star", "star_empty", "ad", "hand", "badge", "slash"]),
    ("sheet5_marks.png", 4, ["trophy", "lock", "medal_gold", "medal_silver",
                             "medal_bronze", "obstacle", "tint_frame", "rivet"]),
    ("sheet6_nodes.png", 5, ["node_red", "node_orange", "node_yellow", "node_sky", "node_blue",
                             "node_pink", "node_magenta", "node_green", "node_violet", "node_white"]),
]
NODES = ["node_red", "node_orange", "node_yellow", "node_sky", "node_blue",
         "node_pink", "node_magenta", "node_green", "node_violet", "node_white"]
BUTTONS = {"pause", "restart", "undo", "hint", "home", "settings",
           "music_on", "sound_on", "vibration_on", "music_off", "sound_off", "vibration_off",
           "trophy", "medal_gold", "medal_silver", "medal_bronze", "rivet"} | set(NODES)
SQUARES = {"obstacle", "tint_frame"}
## Мелкие в игре — PNG меньше (вид тот же, всё в долях стороны): заклёпка Ø ≈ 16 px, медаль 40, замок 56.
## Кружки уровней (лист 6) — 192: в игре Ø 52–140 px, а градиенты сжимаются плохо (256 — ≈58 КБ на кружок, 192 — ≈38).
SMALL = {"rivet": 64, "medal_gold": 128, "medal_silver": 128, "medal_bronze": 128, "lock": 128}
SMALL.update({name: 192 for name in NODES})
## Дырки внутри обводки (лист без альфы): точка в ячейке (x, y), откуда заливаются светлые пиксели.
HOLES = {"lock": [(197, 222)], "tint_frame": [(200, 212)]}
HOLE_LIGHT = 190   # «светлый» пиксель дырки: min(R, G, B) больше этого (белый и серая «шахматка» 221–235)
PAIRS = [("music_on", "music_off"), ("sound_on", "sound_off"), ("vibration_on", "vibration_off")]


def alpha_from_white(rgb):
    """Лист на белом фоне: фон = почти белые пиксели, связанные с краем; альфа каймы — по затемнению."""
    near = rgb.min(-1) > 232
    lab, _ = nd.label(near)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    inside = ~np.isin(lab, list(edge))
    a = np.where(inside, 255.0, 0.0)
    ring = nd.binary_dilation(inside, iterations=2) & ~nd.binary_erosion(inside, iterations=2)
    _, (iy, ix) = nd.distance_transform_edt(~nd.binary_erosion(inside, iterations=3), return_indices=True)
    f = rgb[iy, ix].astype(np.float64)
    k = ((255.0 - rgb) / np.clip(255.0 - f, 1, None)).max(-1)
    a[ring] = np.clip(k[ring], 0, 1) * 255
    out = np.where(ring[..., None], f, rgb)
    return out.astype(np.uint8), a.astype(np.int32)


def punch(rgb, a, seeds):
    """Дырки по точкам seeds: светлые пиксели, связанные с точкой, -> альфа 0; кайма 2 px — альфа по затемнению
    относительно белого, цвет — ближайшей обводки (как alpha_from_white)."""
    light = rgb.min(-1) > HOLE_LIGHT
    lab, _ = nd.label(light)
    hole = np.zeros_like(light)
    for x, y in seeds:
        if not light[y, x]:
            raise SystemExit("точка дырки (%d, %d) не светлая — сдвиньте её в HOLES" % (x, y))
        hole |= lab == lab[y, x]
    if hole.sum() > 0.2 * hole.size:
        raise SystemExit("дырка вытекла наружу (обводка не замкнута?)")
    ring = nd.binary_dilation(hole, iterations=2) & ~hole
    _, (iy, ix) = nd.distance_transform_edt(nd.binary_dilation(hole, iterations=3), return_indices=True)
    f = rgb[iy, ix].astype(np.float64)
    k = ((255.0 - rgb) / np.clip(255.0 - f, 1, None)).max(-1)
    a = a.copy()
    a[hole] = 0
    a[ring] = np.minimum(a[ring], (np.clip(k[ring], 0, 1) * 255).astype(np.int32))
    rgb = np.where(ring[..., None], f, rgb).astype(np.uint8)
    return rgb, a, int(hole.sum())


def clean(cell, holes=()):
    """RGBA-ячейка -> очищенная RGBA (numpy uint8), маска основной детали, касается ли края."""
    rgb = cell[..., :3].copy()
    a = cell[..., 3].astype(np.int32)
    if a.max() == 0 or a.min() == 255:
        rgb, a = alpha_from_white(rgb)
    if holes:
        rgb, a, _ = punch(rgb, a, holes)
    a[a < 8] = 0
    lab, n = nd.label(a >= 128)
    if n == 0:
        raise SystemExit("пустая ячейка")
    sizes = nd.sum(np.ones_like(a), lab, range(1, n + 1))
    main = nd.binary_fill_holes(lab == (1 + int(np.argmax(sizes))))
    a[~nd.binary_dilation(main, iterations=3)] = 0
    a[a >= 240] = 255
    _, (iy, ix) = nd.distance_transform_edt(a < 128, return_indices=True)
    rgb = np.where((a == 0)[..., None], rgb[iy, ix], rgb)
    touches = bool(main[0].any() or main[-1].any() or main[:, 0].any() or main[:, -1].any())
    return np.dstack([rgb, a.astype(np.uint8)]), main, touches


def place(img, src_box, dst_box):
    """Кусок src_box (x0, y0, x1, y1, дробные) -> прямоугольник dst_box на прозрачном холсте N×N."""
    pad = 128
    big = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad), (0, 0, 0, 0))
    big.paste(img, (pad, pad))
    x0, y0, x1, y1 = src_box
    dx0, dy0, dx1, dy1 = dst_box
    sx, sy = (x1 - x0) / (dx1 - dx0), (y1 - y0) / (dy1 - dy0)
    box = (x0 - dx0 * sx + pad, y0 - dy0 * sy + pad, x0 + (N - dx0) * sx + pad, y0 + (N - dy0) * sy + pad)
    return big.resize((N, N), Image.LANCZOS, box=box)


def bbox(mask):
    ys, xs = np.where(mask)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def normalize(name, rgba, main):
    img = Image.fromarray(rgba, "RGBA")
    x0, y0, x1, y1 = bbox(main)
    w, h = x1 - x0, y1 - y0
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    info = {"src": (int(w), int(h))}
    if name in BUTTONS:
        d = max(w, h)
        info["round"] = round(min(w, h) / d, 3)
        dst = (N / 2 - BTN_D / 2, N / 2 - BTN_D / 2, N / 2 + BTN_D / 2, N / 2 + BTN_D / 2)
        out = place(img, (cx - d / 2, cy - d / 2, cx + d / 2, cy + d / 2), dst)
    elif name in SQUARES:
        info["stretch"] = round(max(w, h) / min(w, h), 3)
        dst = (N / 2 - FIT / 2, N / 2 - FIT / 2, N / 2 + FIT / 2, N / 2 + FIT / 2)
        out = place(img, (x0, y0, x1, y1), dst)
    elif name == "hand":
        s = (N - HAND_TOP - 2) / h
        dst = (N / 2 - w * s / 2, HAND_TOP, N / 2 + w * s / 2, HAND_TOP + h * s)
        out = place(img, (x0, y0, x1, y1), dst)
        _, xs = np.where(main[y0:y0 + 6])
        tip_x = dst[0] + (xs.mean() + 0.5 - x0) * s
        info["tip"] = (round(float(tip_x), 1), HAND_TOP)
        k = HAND_RECT / N
        info["pivot120"] = (round(float(tip_x) * k), round(HAND_TOP * k))
    else:
        s = FIT / max(w, h)
        dst = (N / 2 - w * s / 2, N / 2 - h * s / 2, N / 2 + w * s / 2, N / 2 + h * s / 2)
        out = place(img, (x0, y0, x1, y1), dst)
    return out, info


def off_shift(on, off):
    """Сдвиг знака OFF относительно ON, px холста N (полоса и внешнее кольцо кнопки не учитываются)."""
    def feat(im):
        a = np.asarray(im).astype(np.float64)
        lum = (a[..., :3] @ [0.299, 0.587, 0.114]) * (a[..., 3] / 255)
        gy, gx = np.gradient(lum)
        return np.hypot(gx, gy), a
    f_on, _ = feat(on)
    f_off, a_off = feat(off)
    r, g, b = a_off[..., 0], a_off[..., 1], a_off[..., 2]
    slash = nd.binary_dilation((r > 200) & (r - g > 60) & (r - b > 20), iterations=10)
    yy, xx = np.mgrid[0:N, 0:N]
    m = (np.hypot(xx - N / 2 + 0.5, yy - N / 2 + 0.5) < BTN_D / 2 * 0.78) & ~slash
    best = (-1.0, 0, 0)
    for dy in range(-12, 13):
        for dx in range(-12, 13):
            s = np.roll(np.roll(f_on, dy, 0), dx, 1)[m]
            c = (s * f_off[m]).sum() / (np.sqrt((s ** 2).sum() * (f_off[m] ** 2).sum()) + 1e-9)
            if c > best[0]:
                best = (c, dx, dy)
    return best


def sheet5_numbers(made):
    """Числа для кода из нарезанного листа 5 (px холста N): лицо медали и дырка рамки."""
    out = {}
    for name in ("medal_gold", "medal_silver", "medal_bronze"):
        a = np.asarray(made[name]).astype(np.int32)
        rgb, al = a[..., :3], a[..., 3]
        sat = rgb.max(-1) - rgb.min(-1)
        # Лицо медали — цветной круг внутри белого кольца: насыщенные пиксели (золото, бронза) или
        # голубовато-серые (серебро) в пределах 0,7 радиуса кнопки от центра.
        yy, xx = np.mgrid[0:N, 0:N]
        near = np.hypot(xx - N / 2, yy - N / 2) < BTN_D / 2 * 0.72
        face = near & (al > 250) & ((sat > 40) | (rgb.min(-1) < 215))
        lab, n = nd.label(face)
        sizes = nd.sum(np.ones_like(lab), lab, range(1, n + 1))
        m = lab == 1 + int(np.argmax(sizes))
        m = nd.binary_fill_holes(m)
        ys, xs = np.where(m)
        out[name] = {"face_c": (round(float(xs.mean()) + 0.5, 1), round(float(ys.mean()) + 0.5, 1)),
                     "face_d": round(float(2 * np.sqrt(m.sum() / np.pi)), 1)}
    a = np.asarray(made["tint_frame"])[..., 3]
    hole = (a < 128) & nd.binary_fill_holes(a >= 128)
    ys, xs = np.where(hole)
    out["tint_frame"] = {"hole": (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)}
    return out


def sheet6_numbers(made):
    """Лицо кружков листа 6 (px холста N): по средним столбцам (±10 px от середины) сверху — конец обводки, снизу —
    начало губы (яркость падает больше чем на 25 за 2 px в нижней трети). Лицо — между ними; его середина выше
    середины PNG (губа снизу) — от неё число на кружке (MapPath.FACE_Y_K: доля диаметра кружка BTN_D)."""
    rows = {}
    for name in NODES:
        if name not in made:
            continue
        a = np.asarray(made[name]).astype(np.float64)
        lum = a[..., :3] @ [0.299, 0.587, 0.114]
        tops, lips = [], []
        for x in range(N // 2 - 10, N // 2 + 11):
            col, al = lum[:, x], a[:, x, 3]
            y = int(np.argmax(al >= 128))
            while y < N // 2 and col[y] < 70:
                y += 1
            tops.append(y)
            for yy in range(N * 2 // 3, N - 2):
                if al[yy + 2] >= 128 and col[yy] - col[yy + 2] > 25:
                    lips.append(yy + 2)
                    break
        top, lip = float(np.median(tops)), float(np.median(lips)) if lips else float("nan")
        mid = (top + lip) / 2
        rows[name] = {"face_top": top, "lip": lip, "face_mid": mid,
                      "FACE_Y_K": round((N / 2 - mid) / BTN_D, 4), "FACE_H_K": round((lip - top) / BTN_D, 3)}
    if rows:
        mids = [r["face_mid"] for r in rows.values()]
        rows["разброс середины лица, px"] = round(max(mids) - min(mids), 1)
        rows["FACE_Y_K (среднее)"] = round(float(np.mean([r["FACE_Y_K"] for r in rows.values()
                                                            if isinstance(r, dict)])), 4)
    return rows


def main(argv):
    out_dir = argv[argv.index("--out") + 1] if "--out" in argv else OUT
    os.makedirs(out_dir, exist_ok=True)
    made = {}
    for sheet, cols, names in SHEETS:
        path = os.path.join(RAW, sheet)
        if not os.path.exists(path):
            print("нет %s — пропущен" % os.path.relpath(path, ROOT))
            continue
        src = Image.open(path).convert("RGBA")
        arr = np.asarray(src)
        cw, ch = src.width // cols, src.height // 2
        for i, name in enumerate(names):
            r, c = divmod(i, cols)
            rgba, main_mask, touches = clean(arr[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw], HOLES.get(name, ()))
            im, info = normalize(name, rgba, main_mask)
            side = SMALL.get(name, N)
            out = im if side == N else im.resize((side, side), Image.LANCZOS)
            out.save(os.path.join(out_dir, name + ".png"), optimize=True)
            if side != N:
                info["png"] = side
            made[name] = im
            print("%-14s %-20s %s%s" % (name, sheet, info, "  ВНИМАНИЕ: касается края ячейки" if touches else ""))
    print()
    for a, b in PAIRS:
        if a not in made or b not in made:
            continue
        c, dx, dy = off_shift(made[a], made[b])
        ok = "ок" if max(abs(dx), abs(dy)) <= 3 else "СДВИГ — собрать OFF из ON + slash.png"
        print("OFF %-14s сдвиг знака dx=%+d dy=%+d px из %d (корреляция %.2f) — %s" % (b, dx, dy, N, c, ok))
    if "tint_frame" in made:
        for k, v in sheet5_numbers(made).items():
            print("лист 5: %-12s %s" % (k, v))
    if "node_white" in made:
        for k, v in sheet6_numbers(made).items():
            print("лист 6: %-14s %s" % (k, v))
    print("\n%d PNG -> %s" % (len(made), os.path.relpath(out_dir, ROOT)))


if __name__ == "__main__":
    main(sys.argv[1:])
