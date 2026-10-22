#!/usr/bin/env python3
"""Дизайн уровней (офлайн): единственное решение и оценка сложности.

Работает по обычным правилам шикаку — только числа на поле, без учёта набора
блоков. Это строже, чем нужно игре: если решение единственное по правилам
шикаку, оно тем более единственное, когда известны формы блоков. Игрок видит
лишь три блока из лотка, поэтому честная головоломка должна решаться по числам.

Используется tools/make_levels.py. Самостоятельный запуск — замеры:
    python3 tools/level_design.py
"""
import random
import time

# --- Правила оценщика и их «цена» -----------------------------------------
# 1 — у числа остался один вариант (очевидный ход, ничего не стоит);
# 2 — клетку может накрыть только один вариант (скрытая одиночка);
# 3 — клетку может накрыть только одно число: у него остаются лишь варианты
#     через эту клетку;
# 4 — клетки, общие для всех вариантов числа, не может занять другое число;
# 5 — проба: вариант за несколько шагов правил 1–4 ведёт к противоречию.
# Сложность уровня = сумма цен применённых правил.
RULES = (1, 2, 3, 4, 5)
RULE_NAMES = {1: "один вариант", 2: "скрытая одиночка", 3: "клетка одного числа",
              4: "пересечение", 5: "проба"}
RULE_COST = {1: 0.0, 2: 1.0, 3: 2.0, 4: 4.0, 5: 10.0}
UNSOLVED = 6


class Puzzle:
    """Числа на поле cols×rows. numbers: [((x, y), value), ...]."""

    def __init__(self, cols, rows, numbers):
        self.cols, self.rows = cols, rows
        self.numbers = list(numbers)
        self.n_cells = cols * rows
        self.full = (1 << self.n_cells) - 1
        num_at = {p: i for i, (p, _) in enumerate(self.numbers)}
        self.masks, self.owner, self.rects = [], [], []
        self.by_num = [[] for _ in self.numbers]
        self.by_cell = [[] for _ in range(self.n_cells)]
        for i, ((px, py), v) in enumerate(self.numbers):
            for w in range(1, v + 1):
                if v % w:
                    continue
                h = v // w
                if w > cols or h > rows:
                    continue
                for y0 in range(max(0, py - h + 1), min(py, rows - h) + 1):
                    for x0 in range(max(0, px - w + 1), min(px, cols - w) + 1):
                        m = 0
                        foreign = False
                        for yy in range(y0, y0 + h):
                            for xx in range(x0, x0 + w):
                                j = num_at.get((xx, yy))
                                if j is not None and j != i:
                                    foreign = True
                                m |= 1 << (yy * cols + xx)
                        if foreign:
                            continue
                        ci = len(self.masks)
                        self.masks.append(m)
                        self.owner.append(i)
                        self.rects.append((x0, y0, w, h))
                        self.by_num[i].append(ci)
                        for c in _bits(m):
                            self.by_cell[c].append(ci)

    # --- Подсчёт решений (точное покрытие клеток) ----------------------------
    def count_solutions(self, limit=2):
        """-> (число решений, но не больше limit; список решений как наборы rect)."""
        if sum(v for _, v in self.numbers) != self.n_cells:
            return 0, []
        masks, by_cell, full = self.masks, self.by_cell, self.full
        sols = []
        chosen = []

        def rec(occ):
            if occ == full:
                sols.append(frozenset(self.rects[c] for c in chosen))
                return len(sols) >= limit
            best, best_n = -1, 1 << 30
            free = full & ~occ
            while free:
                low = free & -free
                c = low.bit_length() - 1
                free ^= low
                n = 0
                for ci in by_cell[c]:
                    if not masks[ci] & occ:
                        n += 1
                if n == 0:
                    return False
                if n < best_n:
                    best, best_n = c, n
                    if n == 1:
                        break
            for ci in by_cell[best]:
                m = masks[ci]
                if not m & occ:
                    chosen.append(ci)
                    if rec(occ | m):
                        return True
                    chosen.pop()
            return False

        rec(0)
        return len(sols), sols

    # --- Оценка сложности «как человек» ---------------------------------------
    def grade(self):
        """Решает правилами 1–4 от простого к сложному.

        -> dict(solved, score, max_rule (6 — не решилось), uses={правило: раз}, ambiguity)
        score — сумма цен применённых правил; ambiguity — сумма log2(вариантов)
        по числам в начале (насколько «широко» поле).
        """
        st = _State(self)
        import math
        ambiguity = sum(math.log2(max(1, len(l))) for l in self.by_num)
        uses = {r: 0 for r in RULES}
        score = 0.0
        while not st.done():
            if st.contradiction():
                return dict(solved=False, score=score, max_rule=UNSOLVED, uses=uses, ambiguity=ambiguity)
            for rule in RULES:
                if st.apply(rule):
                    uses[rule] += 1
                    score += RULE_COST[rule]
                    break
            else:
                return dict(solved=False, score=score, max_rule=UNSOLVED, uses=uses, ambiguity=ambiguity)
        max_rule = max([r for r in uses if uses[r]] or [1])
        return dict(solved=True, score=score, max_rule=max_rule, uses=uses, ambiguity=ambiguity)


class _State:
    """Живые варианты + занятые клетки. Методы правил возвращают True, если был прогресс."""

    def __init__(self, pz, alive=None, occ=0, assigned=None):
        self.pz = pz
        self.alive = set(range(len(pz.masks))) if alive is None else set(alive)
        self.occ = occ
        self.assigned = set() if assigned is None else set(assigned)

    def copy(self):
        return _State(self.pz, self.alive, self.occ, self.assigned)

    def done(self):
        return len(self.assigned) == len(self.pz.numbers)

    def num_alive(self, i):
        return [c for c in self.pz.by_num[i] if c in self.alive]

    def cell_alive(self, c):
        return [ci for ci in self.pz.by_cell[c] if ci in self.alive]

    def contradiction(self):
        for i in range(len(self.pz.numbers)):
            if i not in self.assigned and not self.num_alive(i):
                return True
        free = self.pz.full & ~self.occ
        for c in _bits(free):
            if not self.cell_alive(c):
                return True
        return False

    def commit(self, ci):
        m = self.pz.masks[ci]
        i = self.pz.owner[ci]
        self.occ |= m
        self.assigned.add(i)
        self.alive = {c for c in self.alive
                      if c == ci or (self.pz.owner[c] != i and not self.pz.masks[c] & m)}

    def apply(self, rule):
        pz = self.pz
        if rule == 1:
            for i in range(len(pz.numbers)):
                if i in self.assigned:
                    continue
                al = self.num_alive(i)
                if len(al) == 1:
                    self.commit(al[0])
                    return True
            return False
        if rule == 2:
            free = pz.full & ~self.occ
            for c in _bits(free):
                al = self.cell_alive(c)
                if len(al) == 1:
                    self.commit(al[0])
                    return True
            return False
        if rule == 3:
            free = pz.full & ~self.occ
            for c in _bits(free):
                al = self.cell_alive(c)
                owners = {pz.owner[ci] for ci in al}
                if len(owners) == 1:
                    i = owners.pop()
                    drop = [ci for ci in self.num_alive(i) if not (pz.masks[ci] >> c) & 1]
                    if drop:
                        self.alive.difference_update(drop)
                        return True
            return False
        if rule == 4:
            for i in range(len(pz.numbers)):
                if i in self.assigned:
                    continue
                al = self.num_alive(i)
                inter = pz.full
                for ci in al:
                    inter &= pz.masks[ci]
                if not inter:
                    continue
                drop = [c for c in self.alive if pz.owner[c] != i and pz.masks[c] & inter]
                if drop:
                    self.alive.difference_update(drop)
                    return True
            return False
        if rule == 5:
            for ci in sorted(self.alive):
                if pz.owner[ci] in self.assigned:
                    continue
                t = self.copy()
                t.commit(ci)
                if t._basic_fails():
                    self.alive.discard(ci)
                    return True
            return False
        return False

    def _basic_fails(self, max_rounds=64):
        """Правила 1–4 до упора; True, если вышло противоречие."""
        for _ in range(max_rounds):
            if self.contradiction():
                return True
            if self.done():
                return False
            if not (self.apply(1) or self.apply(2) or self.apply(3) or self.apply(4)):
                return False
        return False


def _bits(m):
    while m:
        low = m & -m
        yield low.bit_length() - 1
        m ^= low


# --- Разбиение поля и подбор позиций чисел ---------------------------------

AREA_WEIGHT = {2: 1.0, 3: 2.2, 4: 2.6, 5: 1.4, 6: 2.4, 8: 1.8, 9: 1.4, 10: 1.3, 12: 1.2}


def partition(cols, rows, max_area, max_side, rng, weights=None):
    """Разбиение на прямоугольники (площадь 2..max_area, стороны <= max_side).
    Та же схема, что в процедурном генераторе: верхняя левая свободная клетка
    накрывается случайным прямоугольником. -> [(x, y, w, h)] или []"""
    wt = dict(AREA_WEIGHT)
    if weights:
        wt.update(weights)
    used = [0] * (cols * rows)
    rects = []
    for i in range(cols * rows):
        if used[i]:
            continue
        x, y = i % cols, i // cols
        mw = 0
        while x + mw < cols and mw < max_side and not used[y * cols + x + mw]:
            mw += 1
        opts, ws = [], []
        for w in range(1, mw + 1):
            for h in range(1, max_side + 1):
                if y + h > rows:
                    break
                if any(used[(y + h - 1) * cols + xx] for xx in range(x, x + w)):
                    break
                a = w * h
                if a < 2 or a > max_area or a not in wt:
                    continue
                g = wt[a]
                if min(w, h) == 1 and max(w, h) >= 4:
                    g *= 0.6  # длинные палки реже
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


def make_unique(cols, rows, rects, rng, max_iter=60):
    """Ставит по числу в каждый прямоугольник так, чтобы решение было единственным.
    Двигает числа внутри их прямоугольников, ломая найденные чужие решения.
    -> список позиций [(x, y)] или None."""
    pos = [(x + rng.randrange(w), y + rng.randrange(h)) for x, y, w, h in rects]
    ref = frozenset(rects)
    for _ in range(max_iter):
        pz = Puzzle(cols, rows, [(p, r[2] * r[3]) for p, r in zip(pos, rects)])
        n, sols = pz.count_solutions(limit=2)
        if n == 1:
            return pos
        alt = next((s for s in sols if s != ref), None)
        if alt is None:
            return None
        alt_of = {}
        for ar in alt:
            for i, p in enumerate(pos):
                if ar[0] <= p[0] < ar[0] + ar[2] and ar[1] <= p[1] < ar[1] + ar[3]:
                    alt_of[i] = ar
        diff = [i for i, r in enumerate(rects) if r not in alt]
        moves = []
        for i in diff:
            x, y, w, h = rects[i]
            ar = alt_of.get(i)
            for yy in range(y, y + h):
                for xx in range(x, x + w):
                    if (xx, yy) == pos[i]:
                        continue
                    # Ход ломает чужое решение, если число выходит из своего «чужого»
                    # прямоугольника или попадает в прямоугольник другого числа.
                    inside_own = ar and ar[0] <= xx < ar[0] + ar[2] and ar[1] <= yy < ar[1] + ar[3]
                    moves.append((0 if not inside_own else 1, i, (xx, yy)))
        if not moves:
            return None
        best = [m for m in moves if m[0] == 0] or moves
        _, i, p = rng.choice(best)
        pos[i] = p
    return None


def numbers_of(rects, pos):
    return [(p, r[2] * r[3]) for p, r in zip(pos, rects)]


def is_unique(cols, rows, rects, pos):
    return Puzzle(cols, rows, numbers_of(rects, pos)).count_solutions(limit=2)[0] == 1


def tune(cols, rows, rects, pos, rng, target, iters=80, max_rule=5):
    """Двигает числа внутри прямоугольников, сохраняя единственность решения,
    и приближает сложность к target (жадно, с допуском равных шагов).
    Уровни, которым нужен приём сложнее max_rule, не принимаются.
    -> (pos, grade)"""
    def err(g):
        return abs(g["score"] - target) + (1000.0 if g["max_rule"] > max_rule else 0.0)

    pos = list(pos)
    g = Puzzle(cols, rows, numbers_of(rects, pos)).grade()
    cur = err(g)
    for _ in range(iters):
        if cur < 0.5:
            break
        i = rng.randrange(len(rects))
        x, y, w, h = rects[i]
        if w * h == 1:
            continue
        p = (x + rng.randrange(w), y + rng.randrange(h))
        if p == pos[i]:
            continue
        old = pos[i]
        pos[i] = p
        if is_unique(cols, rows, rects, pos):
            g2 = Puzzle(cols, rows, numbers_of(rects, pos)).grade()
            d2 = err(g2)
            if g2["solved"] and d2 <= cur:
                g, cur = g2, d2
                continue
        pos[i] = old
    return pos, g


def _bench():
    rng = random.Random(1)
    for (cols, rows, amax, side) in [(5, 5, 6, 4), (6, 7, 8, 4), (7, 8, 9, 4), (7, 8, 10, 5), (7, 8, 12, 5)]:
        t = time.time()
        ok = tries = 0
        scores = []
        rules = {r: 0 for r in RULES + (UNSOLVED,)}
        hard = []
        while ok < 40 and tries < 400:
            tries += 1
            rects = partition(cols, rows, amax, side, rng)
            if not rects:
                continue
            pos = make_unique(cols, rows, rects, rng)
            if pos is None:
                continue
            ok += 1
            g = Puzzle(cols, rows, numbers_of(rects, pos)).grade()
            rules[g["max_rule"]] += 1
            scores.append(g["score"])
            _, gh = tune(cols, rows, rects, pos, rng, target=999, iters=60)
            hard.append(gh["score"])
        scores.sort()
        q = lambda f: scores[int(f * (len(scores) - 1))] if scores else 0
        hard.sort()
        qh = lambda f: hard[int(f * (len(hard) - 1))] if hard else 0
        print("%dx%d area<=%d side<=%d: единственных %d из %d попыток, %.1f с; "
              "оценка p10/p50/p90 = %.0f/%.0f/%.0f; после усложнения %.0f/%.0f/%.0f; макс. правило %s"
              % (cols, rows, amax, side, ok, tries, time.time() - t, q(.1), q(.5), q(.9),
                 qh(.1), qh(.5), qh(.9), rules))


if __name__ == "__main__":
    _bench()
