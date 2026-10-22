#!/usr/bin/env python3
"""Лаборатория механик этапа 19 (19.1): модель без Godot, по 10 уровней на механику.

    python3 tools/mechanics_lab.py            # уровни, отчёт, кадр
    python3 tools/mechanics_lab.py --quick    # по 3 уровня — проверить, что всё работает

Механики (PLAN, этап 19):
  base     — обычный шикаку на тех же размерах, для сравнения;
  holes    — препятствия: клетки, которые нельзя занимать (поле не прямоугольное);
  pinned   — закреплённый блок: одна фигура уже стоит, номера у неё нет;
  unknown  — число «?»: площадь неизвестна, её нужно вывести (1–3 таких числа на уровне);
  tints    — цветные клетки: клетка без числа окрашена цветом площади, её накрывает блок этой площади;
             числа стоят «неудобно», единственность решения дают окрашенные клетки (1–4 штуки).
«Узкий лоток» и «лимит отмен» на устройство уровня не влияют (решение то же) — их пробуем сразу в Godot.

Для каждого уровня проверяется:
  1) единственное решение по правилам механики (числа + препятствия / «?» / цвета, без учёта блоков —
     строже, чем в игре, как в tools/level_design.py);
  2) оценка «как человек» — правила 1–5 из level_design (без правила 6 — не решается логикой);
  3) игровой решатель (как scripts/shikaku_solver.gd, с учётом блоков) решает уровень с пустого поля
     не дольше 4000 шагов — значит подсказки и поиск тупиков в игре будут работать.

Выход: tools/mechanics_levels.json (уровни), tools/mechanics_report.txt (сводка),
docs/style_frames/G19_1_mechanics.png (по 4 уровня каждой механики + решение первого).
"""
import json
import math
import os
import random
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import level_design as LD  # noqa: E402

OUT_JSON = os.path.join(ROOT, "tools", "mechanics_levels.json")
OUT_REPORT = os.path.join(ROOT, "tools", "mechanics_report.txt")
OUT_PNG = os.path.join(ROOT, "docs", "style_frames", "G19_1_mechanics.png")

MECHANICS = ["base", "holes", "pinned", "unknown", "tints"]
TITLES = {"base": "Обычные (для сравнения)", "holes": "Препятствия", "pinned": "Закреплённый блок",
          "unknown": "Число «?»", "tints": "Цветные клетки"}
# Уровни лаборатории 1..10: размер поля и наибольшая площадь — как у уровней 26–100 основной игры.
SIZES = [(6, 6)] * 3 + [(6, 7)] * 3 + [(7, 7)] * 2 + [(7, 8)] * 2
MAX_AREA, MAX_SIDE = 9, 4
CANDIDATES = 16          # кандидатов на уровень, берём со сложностью ближе к цели
MAX_RULE = 4             # «проба» (правило 5) не нужна — как у уровней 11–100 основной игры
TUNE_ITERS = 120         # base / holes / pinned: числа двигаются внутри своих прямоугольников к цели
TARGET = [4, 5, 6, 7, 8, 9, 10, 11, 12, 14]  # целевая оценка (как кривая основной игры на 26–100)
GAME_STEP_LIMIT = 4000
SEED = 19


# --- Головоломка с механиками ---------------------------------------------------------------------------
class MechPuzzle(LD.Puzzle):
    """numbers: [((x, y), площадь или None — «?»)]. holes — клетки вне игры (препятствия и закреплённый
    блок), tints — {клетка (x, y): площадь}."""

    def __init__(self, cols, rows, numbers, holes=frozenset(), tints=None, max_area=MAX_AREA, max_side=MAX_SIDE):
        self.cols, self.rows = cols, rows
        self.numbers = list(numbers)
        self.n_cells = cols * rows
        hole_mask = 0
        for (x, y) in holes:
            hole_mask |= 1 << (y * cols + x)
        self.full = ((1 << self.n_cells) - 1) & ~hole_mask
        tints = tints or {}
        num_at = {p: i for i, (p, _) in enumerate(self.numbers)}
        self.masks, self.owner, self.rects = [], [], []
        self.by_num = [[] for _ in self.numbers]
        self.by_cell = [[] for _ in range(self.n_cells)]
        for i, ((px, py), v) in enumerate(self.numbers):
            areas = [v] if v else [a for a in range(2, max_area + 1)]
            for a in areas:
                for w in range(1, a + 1):
                    if a % w:
                        continue
                    h = a // w
                    if w > cols or h > rows or (v is None and max(w, h) > max_side):
                        continue
                    for y0 in range(max(0, py - h + 1), min(py, rows - h) + 1):
                        for x0 in range(max(0, px - w + 1), min(px, cols - w) + 1):
                            m, ok = 0, True
                            for yy in range(y0, y0 + h):
                                for xx in range(x0, x0 + w):
                                    j = num_at.get((xx, yy))
                                    t = tints.get((xx, yy))
                                    if (j is not None and j != i) or (t is not None and t != a):
                                        ok = False
                                    m |= 1 << (yy * cols + xx)
                            if not ok or m & hole_mask:
                                continue
                            ci = len(self.masks)
                            self.masks.append(m)
                            self.owner.append(i)
                            self.rects.append((x0, y0, w, h))
                            self.by_num[i].append(ci)
                            for c in LD._bits(m):
                                self.by_cell[c].append(ci)

    def count_solutions(self, limit=2):
        if all(v for _, v in self.numbers) and sum(v for _, v in self.numbers) != bin(self.full).count("1"):
            return 0, []
        saved = self.numbers
        # Проверку суммы в базовом классе обходим: подставляем «площадь клеток» как одно число.
        self.numbers = [((0, 0), bin(self.full).count("1"))]
        try:
            n_cells_saved = self.n_cells
            self.n_cells = bin(self.full).count("1")
            return LD.Puzzle.count_solutions(self, limit)
        finally:
            self.numbers = saved
            self.n_cells = n_cells_saved


# --- Игровой решатель (как scripts/shikaku_solver.gd), с препятствиями и «?» ----------------------------
def game_solve(lv, step_limit=GAME_STEP_LIMIT):
    cols, rows = lv["cols"], lv["rows"]
    occ = 0
    for (x, y) in lv["holes"]:
        occ |= 1 << (y * cols + x)
    left, kidx = {}, {}
    for (w, h) in lv["pieces"]:
        k = (min(w, h), max(w, h))
        if k not in kidx:
            kidx[k] = len(kidx)
            left[kidx[k]] = 0
        left[kidx[k]] += 1
    nums = [((x, y), v) for x, y, v in lv["numbers"]]
    allnum = {p for p, _ in nums}
    tints = {(x, y): a for x, y, a in lv["tints"]}
    cand = []
    for p, v in nums:
        lst = []
        for k, ki in kidx.items():
            if v is not None and k[0] * k[1] != v:
                continue
            for (w, h) in {(k[0], k[1]), (k[1], k[0])}:
                if w > cols or h > rows:
                    continue
                for y0 in range(max(0, p[1] - h + 1), min(p[1], rows - h) + 1):
                    for x0 in range(max(0, p[0] - w + 1), min(p[0], cols - w) + 1):
                        m, ok = 0, True
                        for yy in range(y0, y0 + h):
                            for xx in range(x0, x0 + w):
                                if ((xx, yy) in allnum and (xx, yy) != p) or tints.get((xx, yy), w * h) != w * h:
                                    ok = False
                                m |= 1 << (yy * cols + xx)
                        if ok and not m & occ:
                            lst.append((m, ki))
        cand.append(lst)
    st = {"occ": occ, "steps": 0, "aborted": False}

    def search(todo):
        if not todo:
            return True
        st["steps"] += 1
        if st["steps"] > step_limit:
            st["aborted"] = True
            return False
        best_t, best_cnt = -1, 0
        for t, i in enumerate(todo):
            cnt = sum(1 for m, k in cand[i] if not m & st["occ"] and left[k] > 0)
            if cnt == 0:
                return False
            if best_t < 0 or cnt < best_cnt:
                best_t, best_cnt = t, cnt
        i = todo[best_t]
        rest = todo[:best_t] + todo[best_t + 1:]
        for m, k in cand[i]:
            if m & st["occ"] or left[k] <= 0:
                continue
            left[k] -= 1
            st["occ"] |= m
            if search(rest):
                return True
            st["occ"] &= ~m
            left[k] += 1
            if st["aborted"]:
                return False
        return False

    ok = search(list(range(len(nums))))
    return ("unknown" if st["aborted"] else "solved" if ok else "unsolvable"), st["steps"]


# --- Разбиение с препятствиями и подбор чисел ------------------------------------------------------------
def partition(cols, rows, holes, rng):
    used = [0] * (cols * rows)
    for (x, y) in holes:
        used[y * cols + x] = 1
    rects = []
    for i in range(cols * rows):
        if used[i]:
            continue
        x, y = i % cols, i // cols
        mw = 0
        while x + mw < cols and mw < MAX_SIDE and not used[y * cols + x + mw]:
            mw += 1
        opts, ws = [], []
        for w in range(1, mw + 1):
            for h in range(1, MAX_SIDE + 1):
                if y + h > rows or any(used[(y + h - 1) * cols + xx] for xx in range(x, x + w)):
                    break
                a = w * h
                if a < 2 or a > MAX_AREA or a not in LD.AREA_WEIGHT:
                    continue
                g = LD.AREA_WEIGHT[a] * (0.6 if min(w, h) == 1 and max(w, h) >= 4 else 1.0)
                opts.append((w, h))
                ws.append(g)
        if not opts:
            return []
        w, h = rng.choices(opts, weights=ws)[0]
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                used[yy * cols + xx] = 1
        rects.append((x, y, w, h))
    return rects


def inside(r, p):
    return r[0] <= p[0] < r[0] + r[2] and r[1] <= p[1] < r[1] + r[3]


def make_unique(build, rects, rng, pos=None, max_iter=80):
    """Как level_design.make_unique, но головоломку собирает build(pos) — с механикой."""
    pos = list(pos) if pos else [(x + rng.randrange(w), y + rng.randrange(h)) for x, y, w, h in rects]
    ref = frozenset(rects)
    for _ in range(max_iter):
        n, sols = build(pos).count_solutions(limit=2)
        if n == 1:
            return pos
        alt = next((s for s in sols if s != ref), None)
        if alt is None:
            return None
        alt_of = {i: ar for ar in alt for i, p in enumerate(pos) if inside(ar, p)}
        moves = []
        for i, r in enumerate(rects):
            if r in alt:
                continue
            for yy in range(r[1], r[1] + r[3]):
                for xx in range(r[0], r[0] + r[2]):
                    if (xx, yy) != pos[i]:
                        ar = alt_of.get(i)
                        moves.append((1 if ar and inside(ar, (xx, yy)) else 0, i, (xx, yy)))
        if not moves:
            return None
        best = [m for m in moves if m[0] == 0] or moves
        _, i, p = rng.choice(best)
        pos[i] = p
    return None


# --- Узоры препятствий -----------------------------------------------------------------------------------
def hole_pattern(cols, rows, rng):
    kind = rng.choice(["corners", "center", "symmetric", "notch"])
    holes = set()
    if kind == "corners":  # срезанные углы: 1 или 3 клетки в каждом из 2–4 углов
        corners = rng.sample([(0, 0), (cols - 1, 0), (0, rows - 1), (cols - 1, rows - 1)], rng.choice([2, 4]))
        big = rng.random() < 0.5
        for cx, cy in corners:
            dx, dy = (1 if cx == 0 else -1), (1 if cy == 0 else -1)
            holes.add((cx, cy))
            if big:
                holes.update({(cx + dx, cy), (cx, cy + dy)})
    elif kind == "center":  # дыра в середине 1×1, 2×1 или 2×2
        w, h = rng.choice([(1, 1), (2, 1), (1, 2), (2, 2)])
        x0, y0 = (cols - w) // 2, (rows - h) // 2
        holes.update((x, y) for x in range(x0, x0 + w) for y in range(y0, y0 + h))
    elif kind == "symmetric":  # 2–3 пары клеток, симметричных относительно центра
        for _ in range(rng.choice([2, 3])):
            x, y = rng.randrange(cols), rng.randrange(rows)
            holes.update({(x, y), (cols - 1 - x, rows - 1 - y)})
    else:  # вырез с края: 2–3 клетки внутрь с середины стороны
        side = rng.choice("tblr")
        depth = rng.choice([2, 3])
        if side in "tb":
            x = cols // 2 - (cols % 2 == 0 and rng.random() < 0.5)
            ys = range(depth) if side == "t" else range(rows - depth, rows)
            holes.update((x, y) for y in ys)
        else:
            y = rows // 2
            xs = range(depth) if side == "l" else range(cols - depth, cols)
            holes.update((x, y) for x in xs)
    return kind, frozenset(holes)


# --- Генераторы механик ----------------------------------------------------------------------------------
def pieces_of(rects, rng):
    ps = [(w, h) if rng.random() < 0.5 else (h, w) for (_, _, w, h) in rects]
    rng.shuffle(ps)
    return ps


def level_dict(mech, cols, rows, rects, numbers, holes=frozenset(), tints=None, pinned=None, extra=None, rng=None):
    lv = {"mechanic": mech, "cols": cols, "rows": rows, "solution": [list(r) for r in rects],
          "numbers": [[p[0], p[1], v] for p, v in numbers], "holes": sorted([list(h) for h in holes]),
          "tints": sorted([[p[0], p[1], a] for p, a in (tints or {}).items()]),
          "pinned": list(pinned) if pinned else None, "pieces": [list(p) for p in pieces_of(rects, rng)]}
    lv.update(extra or {})
    return lv


def gen_base(cols, rows, rng):
    rects = partition(cols, rows, frozenset(), rng)
    if not rects:
        return None
    build = lambda pos: MechPuzzle(cols, rows, [(p, r[2] * r[3]) for p, r in zip(pos, rects)])  # noqa: E731
    pos = make_unique(build, rects, rng)
    if pos is None:
        return None
    return level_dict("base", cols, rows, rects, [(p, r[2] * r[3]) for p, r in zip(pos, rects)], rng=rng), build(pos)


def gen_holes(cols, rows, rng):
    kind, holes = hole_pattern(cols, rows, rng)
    rects = partition(cols, rows, holes, rng)
    if not rects:
        return None
    build = lambda pos: MechPuzzle(cols, rows, [(p, r[2] * r[3]) for p, r in zip(pos, rects)], holes)  # noqa: E731
    pos = make_unique(build, rects, rng)
    if pos is None:
        return None
    return (level_dict("holes", cols, rows, rects, [(p, r[2] * r[3]) for p, r in zip(pos, rects)], holes,
                       extra={"pattern": kind}, rng=rng), build(pos))


def gen_pinned(cols, rows, rng):
    # Закреплённый блок 2×2…3×3 ближе к середине: для остальных он — препятствие прямоугольной формы.
    w, h = rng.choice([(2, 2), (2, 3), (3, 2), (3, 3), (2, 4), (4, 2)])
    x0 = rng.randrange(1, cols - w) if cols - w > 1 else 0
    y0 = rng.randrange(1, rows - h) if rows - h > 1 else 0
    pin = (x0, y0, w, h)
    holes = frozenset((x, y) for x in range(x0, x0 + w) for y in range(y0, y0 + h))
    rects = partition(cols, rows, holes, rng)
    if not rects:
        return None
    build = lambda pos: MechPuzzle(cols, rows, [(p, r[2] * r[3]) for p, r in zip(pos, rects)], holes)  # noqa: E731
    pos = make_unique(build, rects, rng)
    if pos is None:
        return None
    lv = level_dict("pinned", cols, rows, rects + [pin], [(p, r[2] * r[3]) for p, r in zip(pos, rects)], holes,
                    pinned=pin, rng=rng)
    lv["pieces"] = [list(p) for p in pieces_of(rects, rng)]  # закреплённый блок в лоток не идёт
    return lv, build(pos)


def gen_unknown(cols, rows, rng, want):
    got = gen_base(cols, rows, rng)
    if not got:
        return None
    lv, _ = got
    rects = [tuple(r) for r in lv["solution"]]
    numbers = [((x, y), v) for x, y, v in lv["numbers"]]
    best = None
    # Перебираем, какие числа спрятать за «?»: решение должно остаться единственным; берём самый трудный набор.
    idx = list(range(len(numbers)))
    for _ in range(30):
        pick = set(rng.sample(idx, want))
        nums = [(p, None if i in pick else v) for i, (p, v) in enumerate(numbers)]
        pz = MechPuzzle(cols, rows, nums)
        if pz.count_solutions(limit=2)[0] != 1:
            continue
        g = pz.grade()
        if not g["solved"]:
            continue
        if best is None or g["score"] > best[0]:
            best = (g["score"], nums, pz)
    if not best:
        return None
    _, nums, pz = best
    return level_dict("unknown", cols, rows, rects, nums, rng=rng), pz


def gen_tints(cols, rows, rng, max_tints=4):
    rects = partition(cols, rows, frozenset(), rng)
    if not rects:
        return None
    ref = frozenset(rects)
    area_at = {}
    for r in rects:
        for yy in range(r[1], r[1] + r[3]):
            for xx in range(r[0], r[0] + r[2]):
                area_at[(xx, yy)] = r[2] * r[3]
    pos = [(x + rng.randrange(w), y + rng.randrange(h)) for x, y, w, h in rects]
    nums = [(p, r[2] * r[3]) for p, r in zip(pos, rects)]
    tints = {}
    pz = MechPuzzle(cols, rows, nums)
    n, sols = pz.count_solutions(limit=2)
    if n == 1:
        return None  # уже единственное — цвета не нужны, это уровень без механики
    while n != 1:
        if n == 0 or len(tints) >= max_tints:
            return None
        alt = next(s for s in sols if s != ref)
        cells = [(xx, yy) for ar in alt for yy in range(ar[1], ar[1] + ar[3]) for xx in range(ar[0], ar[0] + ar[2])
                 if ar[2] * ar[3] != area_at[(xx, yy)] and (xx, yy) not in pos and (xx, yy) not in tints]
        if not cells:
            return None
        c = rng.choice(cells)
        tints[c] = area_at[c]
        pz = MechPuzzle(cols, rows, nums, tints=tints)
        n, sols = pz.count_solutions(limit=2)
    return level_dict("tints", cols, rows, rects, nums, tints=tints, rng=rng), pz


GENERATORS = {"base": gen_base, "holes": gen_holes, "pinned": gen_pinned,
              "unknown": lambda c, r, rng, k=0: gen_unknown(c, r, rng, 1 + k // 4), "tints": gen_tints}


def err(g, k):
    return abs(g["score"] - TARGET[k]) + (1000.0 if g["max_rule"] > MAX_RULE else 0.0)


def tune(lv, k, rng):
    """Как level_design.tune: двигает числа, сохраняя единственность, ближе к целевой оценке."""
    cols, rows = lv["cols"], lv["rows"]
    holes = frozenset(tuple(h) for h in lv["holes"])
    rects = [tuple(r) for r in lv["solution"]][:len(lv["numbers"])]
    pos = [(x, y) for x, y, _ in lv["numbers"]]
    build = lambda ps: MechPuzzle(cols, rows, [(p, r[2] * r[3]) for p, r in zip(ps, rects)], holes)  # noqa: E731
    g = build(pos).grade()
    cur = err(g, k)
    for _ in range(TUNE_ITERS):
        if cur < 0.5:
            break
        i = rng.randrange(len(rects))
        x, y, w, h = rects[i]
        p = (x + rng.randrange(w), y + rng.randrange(h))
        if p == pos[i]:
            continue
        old, pos[i] = pos[i], p
        pz = build(pos)
        if pz.count_solutions(limit=2)[0] == 1:
            g2 = pz.grade()
            if g2["solved"] and err(g2, k) <= cur:
                g, cur = g2, err(g2, k)
                continue
        pos[i] = old
    lv["numbers"] = [[p[0], p[1], r[2] * r[3]] for p, r in zip(pos, rects)]
    return g


def make_level(mech, k, rng):
    cols, rows = SIZES[k]
    tries = cands = 0
    picked = None
    t0 = time.time()
    while cands < CANDIDATES and tries < 400:
        tries += 1
        gen = GENERATORS[mech]
        got = gen(cols, rows, rng, k) if mech == "unknown" else gen(cols, rows, rng)
        if not got:
            continue
        lv, pz = got
        g = pz.grade()
        if not g["solved"]:
            continue
        cands += 1
        d = err(g, k)
        if picked is None or d < picked[0]:
            picked = (d, lv, g)
    if not picked:
        return None, tries, time.time() - t0
    _, lv, g = picked
    if mech in ("base", "holes", "pinned"):
        g = tune(lv, k, rng)
    if g["max_rule"] > MAX_RULE:
        return None, tries, time.time() - t0
    status, steps = game_solve(lv)
    lv["grade"] = {"score": round(g["score"], 1), "max_rule": g["max_rule"],
                   "uses": {str(r): n for r, n in g["uses"].items() if n}}
    lv["game_solver"] = {"status": status, "steps": steps}
    lv["tries"] = tries
    return lv, tries, time.time() - t0


# --- Кадр ------------------------------------------------------------------------------------------------
def draw_sheet(levels, path):
    from PIL import Image, ImageDraw, ImageFont
    font_p = os.path.join(ROOT, "assets", "fonts", "nunito_extrabold.ttf")
    colors = ["#B4C3FF", "#FF4B3E", "#FF9A2E", "#FFD23F", "#2FD67B", "#2EC8F7", "#E552D6", "#3F7BFF", "#14CDB8",
              "#A6E22E", "#1FB26B", "#FF5FA8"]
    cell, pad, head, cap_h = 34, 26, 64, 34
    picks = [0, 3, 6, 9]
    cols_n = len(picks) + 1
    bw, bh = 7 * cell, 8 * cell
    W = pad + cols_n * (bw + pad)
    H = head + len(MECHANICS) * (bh + 2 * cap_h + pad) + pad
    im = Image.new("RGB", (W, H), (34, 22, 70))
    d = ImageDraw.Draw(im)
    f_head = ImageFont.truetype(font_p, 28)
    f_cap = ImageFont.truetype(font_p, 18)
    f_num = ImageFont.truetype(font_p, 20)
    d.text((pad, head // 2), "Этап 19.1 — механики-кандидаты: уровни 1, 4, 7, 10 и решение уровня 1",
           font=f_head, fill=(240, 236, 255), anchor="lm")

    def board(lv, ox, oy, solved):
        c, r = lv["cols"], lv["rows"]
        holes = {tuple(h) for h in lv["holes"]}
        tints = {(x, y): a for x, y, a in lv["tints"]}
        for y in range(r):
            for x in range(c):
                x0, y0 = ox + x * cell, oy + y * cell
                if (x, y) in holes and not (lv["pinned"] and inside(lv["pinned"], (x, y))):
                    d.rounded_rectangle([x0 + 3, y0 + 3, x0 + cell - 3, y0 + cell - 3], 6, fill=(26, 12, 64))
                    continue
                fill = (236, 232, 255) if (x + y) % 2 == 0 else (222, 216, 252)
                d.rectangle([x0, y0, x0 + cell - 1, y0 + cell - 1], fill=fill)
                if (x, y) in tints:
                    d.rounded_rectangle([x0 + 4, y0 + 4, x0 + cell - 5, y0 + cell - 5], 7, fill=colors[tints[(x, y)] - 1])
        rects = [tuple(s) for s in lv["solution"]] if solved else []
        if lv["pinned"]:
            rects = list(set(rects) | {tuple(lv["pinned"])})
        for (x, y, w, h) in rects:
            col = colors[min(w * h, 12) - 1]
            d.rounded_rectangle([ox + x * cell + 2, oy + y * cell + 2, ox + (x + w) * cell - 3, oy + (y + h) * cell - 3],
                                9, fill=col, outline=(46, 22, 120), width=2)
            if lv["pinned"] and (x, y, w, h) == tuple(lv["pinned"]):
                cx, cy = ox + (x + w / 2) * cell, oy + (y + h / 2) * cell
                d.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], fill=(46, 22, 120))  # «гвоздь»
                d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(200, 190, 255))
        for x, y, v in lv["numbers"]:
            cx, cy = ox + (x + 0.5) * cell, oy + (y + 0.5) * cell
            d.ellipse([cx - 13, cy - 13, cx + 13, cy + 13], fill=(255, 255, 255), outline=(46, 22, 120), width=2)
            d.text((cx, cy + 1), "?" if v is None else str(v), font=f_num, fill=(46, 22, 120), anchor="mm")

    y = head
    for mech in MECHANICS:
        lvls = levels.get(mech, [])
        d.text((pad, y + cap_h // 2), TITLES[mech], font=f_cap, fill=(255, 228, 92), anchor="lm")
        y += cap_h  # подписи досок — строкой ниже названия механики
        x = pad
        for k in picks:
            if k < len(lvls) and lvls[k]:
                lv = lvls[k]
                board(lv, x + (bw - lv["cols"] * cell) // 2, y + cap_h + (bh - lv["rows"] * cell) // 2, False)
                d.text((x, y + cap_h // 2), "уровень %d · оценка %.0f" % (k + 1, lv["grade"]["score"]), font=f_cap,
                       fill=(200, 192, 240), anchor="lm")
            x += bw + pad
        if lvls and lvls[0]:
            lv = lvls[0]
            board(lv, x + (bw - lv["cols"] * cell) // 2, y + cap_h + (bh - lv["rows"] * cell) // 2, True)
            d.text((x, y + cap_h // 2), "решение уровня 1", font=f_cap, fill=(200, 192, 240), anchor="lm")
        y += cap_h + bh + pad
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, optimize=True)


# --- Сводка ----------------------------------------------------------------------------------------------
def report(levels, stats):
    lines = ["Лаборатория механик (этап 19.1) — tools/mechanics_lab.py", "",
             "Оценка — сумма цен приёмов из tools/level_design.py (правила 1–5); игровой решатель — шаги поиска",
             "с пустого поля при лимите %d (как scripts/shikaku_solver.gd)." % GAME_STEP_LIMIT, "",
             "%-18s %6s %8s %8s %7s %9s %8s" % ("механика", "уровни", "оценка", "max пр.", "проба", "шаги max",
                                              "попыток")]
    for mech in MECHANICS:
        lv = [x for x in levels[mech] if x]
        if not lv:
            lines.append("%-18s нет уровней" % mech)
            continue
        sc = [x["grade"]["score"] for x in lv]
        mr = max(x["grade"]["max_rule"] for x in lv)
        probe = sum(1 for x in lv if x["grade"]["max_rule"] >= 5)
        steps = max(x["game_solver"]["steps"] for x in lv)
        tries = sum(stats[mech]["tries"]) / max(1, len(stats[mech]["tries"]))
        lines.append("%-18s %6d %8.1f %8d %7d %9d %8.1f" % (mech, len(lv), sum(sc) / len(sc), mr, probe, steps, tries))
    lines += ["", "Уровни (оценка / самый сложный приём / шаги игрового решателя):"]
    for mech in MECHANICS:
        row = []
        for x in levels[mech]:
            if not x:
                row.append("—")
                continue
            extra = ""
            if mech == "unknown":
                extra = " ?%d" % sum(1 for n in x["numbers"] if n[2] is None)
            if mech == "tints":
                extra = " ц%d" % len(x["tints"])
            if mech == "holes":
                extra = " %s" % x["pattern"][:4]
            row.append("%dx%d %.0f/%d/%d%s" % (x["cols"], x["rows"], x["grade"]["score"], x["grade"]["max_rule"],
                                              x["game_solver"]["steps"], extra))
        lines.append("  %-8s %s" % (mech, " | ".join(row)))
    bad = [(m, i + 1) for m in MECHANICS for i, x in enumerate(levels[m]) if x and x["game_solver"]["status"] != "solved"]
    lines += ["", "игровой решатель не справился: %s" % (bad or "нет")]
    return "\n".join(lines) + "\n", bad


def main(argv):
    quick = "--quick" in argv
    n = 3 if quick else 10
    levels, stats = {}, {}
    t_all = time.time()
    for mech in MECHANICS:
        rng = random.Random(SEED * 1000 + MECHANICS.index(mech))
        levels[mech], stats[mech] = [], {"tries": [], "time": []}
        for k in range(n):
            lv, tries, dt = make_level(mech, k, rng)
            levels[mech].append(lv)
            stats[mech]["tries"].append(tries)
            stats[mech]["time"].append(dt)
        print("%-8s %d уровней, %.1f с" % (mech, sum(1 for x in levels[mech] if x), sum(stats[mech]["time"])))
    text, bad = report(levels, stats)
    if not quick:
        with open(OUT_JSON, "w", encoding="utf-8") as f:
            json.dump({"seed": SEED, "sizes": SIZES, "levels": levels}, f, ensure_ascii=False, indent=1)
        with open(OUT_REPORT, "w", encoding="utf-8") as f:
            f.write(text)
        draw_sheet(levels, OUT_PNG)
    print(text)
    print("всего %.1f с" % (time.time() - t_all))
    return 1 if bad or any(not x for m in MECHANICS for x in levels[m]) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
