#!/usr/bin/env python3
"""Обучающие уровни 1–3: сделаны вручную (этап 11), каждый учит одному навыку.

  1 — DRAG: число — это размер блока. Три блока разного размера (9, 3, 4),
      все выданы как надо (поворот не нужен); у каждого ровно одно допустимое
      место, повёрнутый не встаёт никуда — ошибиться можно только «мимо числа».
  2 — ROTATE: палку 4 выдают стоя, а нужна лёжа. Как выдана — не встаёт никуда;
      она первая в лотке (07.10: рука показывает поворот сразу — блок для него
      должен стоять первым, а не посередине); остальные блоки выданы как надо;
      тупиковых допустимых мест нет.
  3 — ONE_NUMBER: две двойки рядом в центре. Домино на обе — «ровно одно число»;
      лёжа — тупик (страховка: «так остальные блоки не поместятся»);
      верно — стоя, по одной двойке. Тройку выдают стоя: нужен поворот.

Уровни подобраны перебором (скрипты поиска — в логе 30.09, docs/log/journal_01_start-0930.md), здесь —
готовые данные и проверка свойств. make_levels.py берёт их как есть (PINNED).
Запуск — только проверка:
    python3 tools/tutorial_levels.py
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import level_design as D  # noqa: E402
import model as M  # noqa: E402

# rects — решение (x, y, w, h), pos — клетка числа в каждом прямоугольнике,
# pieces — блоки в порядке выдачи (ширина, высота) — как их увидит игрок.
LEVELS = {
    1: dict(cols=4, rows=4,
            rects=[(0, 0, 3, 3), (3, 0, 1, 3), (0, 3, 4, 1)],
            pos=[(1, 0), (3, 0), (1, 3)],
            pieces=[(3, 3), (1, 3), (4, 1)]),
    2: dict(cols=4, rows=4,
            rects=[(0, 0, 4, 1), (0, 1, 1, 3), (1, 1, 3, 1), (1, 2, 1, 2), (2, 2, 1, 2), (3, 2, 1, 2)],
            pos=[(3, 0), (0, 3), (3, 1), (1, 3), (2, 3), (3, 3)],
            pieces=[(1, 4), (1, 2), (3, 1), (1, 3), (1, 2), (1, 2)]),
    3: dict(cols=5, rows=5,
            rects=[(0, 0, 2, 2), (2, 0, 1, 2), (3, 0, 2, 4), (0, 2, 2, 3), (2, 2, 1, 2), (2, 4, 3, 1)],
            pos=[(0, 0), (2, 1), (4, 0), (1, 4), (2, 2), (2, 4)],
            pieces=[(1, 2), (2, 2), (2, 1), (1, 3), (2, 3), (2, 4)]),
}
TRAY = 3  # блоков в лотке одновременно (Tray.SLOTS)


class Board:
    """Поле как в игре: Board.check_rect и причина отказа (Tutorial.reason)."""

    def __init__(self, cols, rows, numbers):
        self.cols, self.rows = cols, rows
        self.val = {tuple(p): v for p, v in numbers}
        self.occ = set()

    def cells(self, r):
        x, y, w, h = r
        return [(xx, yy) for yy in range(y, y + h) for xx in range(x, x + w)]

    def reason(self, r):
        """"ok" | "outside" | "occupied" | "count" (не одно число) | "value" (число не то)."""
        x, y, w, h = r
        if x < 0 or y < 0 or x + w > self.cols or y + h > self.rows:
            return "outside"
        cs = self.cells(r)
        if any(c in self.occ for c in cs):
            return "occupied"
        nums = [self.val[c] for c in cs if c in self.val]
        if len(nums) != 1:
            return "count"
        return "ok" if nums[0] == w * h else "value"

    def check(self, r):
        return self.reason(r) == "ok"

    def legal(self, dims):
        w, h = dims
        return [(x, y, w, h) for y in range(self.rows - h + 1) for x in range(self.cols - w + 1)
                if self.check((x, y, w, h))]

    def place(self, r):
        self.occ.update(self.cells(r))


def numbers_of(lv):
    return [(tuple(p), w * h) for p, (_, _, w, h) in zip(lv["pos"], lv["rects"])]


def dead_ends(lv):
    """Допустимые на пустом поле места (любой блок, любой поворот), ведущие в тупик."""
    cols, rows, nums = lv["cols"], lv["rows"], numbers_of(lv)
    b = Board(cols, rows, nums)
    out = set()
    for i, (w, h) in enumerate(lv["pieces"]):
        rest = lv["pieces"][:i] + lv["pieces"][i + 1:]
        for d in {(w, h), (h, w)}:
            for r in b.legal(d):
                if M.solve(cols, rows, nums, [r], rest)[0] != M.SOLVED:
                    out.add(r)
    return sorted(out)


def check(n):
    """Свойства обучающего уровня n. -> список ошибок."""
    lv = LEVELS[n]
    cols, rows = lv["cols"], lv["rows"]
    nums = numbers_of(lv)
    errs = []
    if (cols, rows) != M.grid_size(n):
        errs.append("размер %dx%d, а у уровня %d поле %dx%d" % ((cols, rows, n) + tuple(M.grid_size(n))))
    if D.Puzzle(cols, rows, nums).count_solutions(limit=2)[0] != 1:
        errs.append("решение не единственное")
    g = D.Puzzle(cols, rows, nums).grade()
    if not g["solved"] or g["score"] > 0:
        errs.append("нужна не только очевидная логика (сложность %.1f)" % g["score"])
    shape = lambda d: tuple(sorted(d))
    if sorted(map(shape, lv["pieces"])) != sorted(shape(r[2:]) for r in lv["rects"]):
        errs.append("набор блоков не совпадает с решением")
    b = Board(cols, rows, nums)
    upright = {tuple(r[2:]) for r in lv["rects"]}
    need_turn = [p for p in lv["pieces"] if tuple(p) not in upright]
    traps = dead_ends(lv)
    if n == 1:
        if len({w * h for *_, w, h in lv["rects"]}) != len(lv["rects"]) or not 3 <= len(lv["rects"]) <= 4:
            errs.append("L1: нужно 3–4 блока разного размера")
        if need_turn:
            errs.append("L1: блоки выданы не так, как лежат в решении: %s" % need_turn)
        for w, h in lv["pieces"]:
            if len(b.legal((w, h))) != 1:
                errs.append("L1: у блока %dx%d не одно место" % (w, h))
            if w != h and b.legal((h, w)):
                errs.append("L1: повёрнутый блок %dx%d куда-то встаёт" % (w, h))
    elif n == 2:
        if len(need_turn) != 1:
            errs.append("L2: повернуть нужно не ровно один блок: %s" % need_turn)
        else:
            w, h = need_turn[0]
            if b.legal((w, h)):
                errs.append("L2: блок %dx%d встаёт и без поворота" % (w, h))
            if [shape(p) for p in lv["pieces"]].count(shape((w, h))) != 1:
                errs.append("L2: блок для поворота не единственный такой формы")
            if tuple(lv["pieces"][0]) != (w, h):
                errs.append("L2: блок для поворота не первый в лотке")
        if traps:
            errs.append("L2: есть тупиковые места %s" % traps)
    elif n == 3:
        from collections import Counter
        c = Counter(v for _, v in nums)
        pair = [v for v, k in c.items() if k == 2]
        if len(pair) != 1 or max(c.values()) != 2:
            errs.append("L3: нужна ровно одна пара одинаковых чисел, остальные разные")
        else:
            v = pair[0]
            p1, p2 = [p for p, x in nums if x == v]
            both = False
            for w in range(1, v + 1):
                if v % w:
                    continue
                h = v // w
                for y in range(rows - h + 1):
                    for x in range(cols - w + 1):
                        cs = b.cells((x, y, w, h))
                        if p1 in cs and p2 in cs and b.reason((x, y, w, h)) == "count":
                            both = True
            if not both:
                errs.append("L3: пару нельзя накрыть одним блоком (нет ошибки «ровно одно число»)")
            pair_cells = {p1, p2}
            if not traps or any(not (set(b.cells(r)) & pair_cells) for r in traps):
                errs.append("L3: ловушки должны быть только у пары: %s" % traps)
            if any(tuple(p) not in [tuple(q) for q in lv["pieces"][:TRAY]]
                   for p in lv["pieces"] if p[0] * p[1] == v):
                errs.append("L3: блоки пары не в первом лотке")
        if not need_turn:
            errs.append("L3: хотя бы один блок нужно повернуть (закрепить навык)")
    st, _, _ = M.solve(cols, rows, nums, [], lv["pieces"])
    if st != M.SOLVED:
        errs.append("решатель игры не решил уровень")
    return errs


def record(n):
    """Запись уровня в формате make_levels.build (сложность — по оценщику)."""
    lv = LEVELS[n]
    g = D.Puzzle(lv["cols"], lv["rows"], numbers_of(lv)).grade()
    return dict(level=n, sig="pinned", cols=lv["cols"], rows=lv["rows"],
                rects=[tuple(r) for r in lv["rects"]], pos=[tuple(p) for p in lv["pos"]],
                pieces=[tuple(p) for p in lv["pieces"]], target=0.0, score=g["score"],
                max_rule=g["max_rule"], uses=g["uses"], ambiguity=round(g["ambiguity"], 2), candidates=0)


def main():
    bad = 0
    for n in sorted(LEVELS):
        errs = check(n)
        lv = LEVELS[n]
        print("уровень %d: %dx%d, блоков %d, тупиковых мест %d — %s" % (
            n, lv["cols"], lv["rows"], len(lv["pieces"]), len(dead_ends(lv)), "ок" if not errs else "; ".join(errs)))
        bad += len(errs)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
