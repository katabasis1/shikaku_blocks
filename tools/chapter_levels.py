#!/usr/bin/env python3
"""Уровни глав с механиками (этап 19.5e): на каком уровне какая механика и генератор таких уровней.

Решение пользователя 09.10 (сессия 94): в главы идут все четыре механики «Лаборатории» (19.3), и появляются они
по очереди — каждая из глав 4–7 вводит одну механику (MECH_ORDER), главы 8–10 — все четыре вперемешку:
* глава 4 (151–200) — препятствия, 5 (201–250) — закреплённый блок, 6 (251–300) — цветные клетки,
  7 (301–350) — число «?»: от простого к сложному (19.1: препятствия — новый вид при той же сложности,
  закреплённый блок — то же препятствие, только прямоугольное; цвет надо помнить; «?» поднимает сложность);
* первые INTRO уровней такой главы — её механика на простых полях (цель сложности × INTRO_SCALE, без пробы),
  на них игра показывает правило над полем (scripts/chapters.gd: MECHANICS, RULE_LEVELS);
* дальше механика в двух уровнях из трёх, каждый третий (k % 3 == 2) — классика;
* главы 8–10 (351–500): в двух уровнях из трёх механика, по кругу MECH_ORDER; каждый третий — классика.
В одном уровне — одна механика. Классические уровни этих глав — прежние уровни списка v2 (тот же генератор и
зерно), меняются только уровни с механикой.

Генератор (build): поле и набор площадей — как у основного пути (make_levels.spec: 7×8, площади до 12,
стороны до 5), сложность — та же кривая make_levels.target; оценка и единственность — по числам, как в
«Лаборатории» (mechanics_lab.MechPuzzle: препятствия, цвет, «?»). Строже, чем нужно игре: единственное по числам
решение тем более единственное с набором блоков. Цветные клетки — только у площадей до 9 (одна цифра в строке
уровня, LevelPack: tXYA).

Используется tools/make_levels.py. Самостоятельный запуск — план механик по главам и пробная генерация:
    python3 tools/chapter_levels.py            # план
    python3 tools/chapter_levels.py 151 301    # собрать уровни 151 и 301 и показать оценку
    python3 tools/chapter_levels.py --gd       # план строкой для tests/selftest.gd (CHAPTER_MECH_PLAN)
"""
import os
import random
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import level_design as LD  # noqa: E402
import mechanics_lab as LAB  # noqa: E402

MECH_ORDER = ("holes", "pinned", "tints", "unknown")
FIRST = 151                                # глава 4 — первая с механикой
SPAN = 50                                  # уровней в главах 4–10 (scripts/chapters.gd: FIRST)
MIX_FROM = FIRST + SPAN * len(MECH_ORDER)  # 351: глава 8 — все механики вперемешку
LAST = 500                                 # последний заготовленный уровень (make_levels.COUNT)
INTRO = 5                                  # первые уровни главы — её механика на простых полях
INTRO_SCALE = (0.35, 0.45, 0.55, 0.65, 0.75)
CLASSIC_EVERY = 3                          # с INTRO-го уровня главы каждый третий (k % 3 == 2) — без механики
TINT_MAX_AREA = 9                          # цветная клетка — площадь одной цифрой
MAX_TINTS = 4
UNKNOWN_TRIES = 30
PIN_SHAPES = [(2, 2), (2, 3), (3, 2), (3, 3), (2, 4), (4, 2)]


def chapter_start(n):
    return FIRST + (n - FIRST) // SPAN * SPAN


def mechanic(n):
    """Механика уровня n основного пути: "holes" | "pinned" | "tints" | "unknown" | "" (классика)."""
    if n < FIRST or n > LAST:
        return ""
    first = chapter_start(n)
    k = n - first
    if first < MIX_FROM:
        m = MECH_ORDER[(first - FIRST) // SPAN]
        if k < INTRO:
            return m
        return "" if k % CLASSIC_EVERY == 2 else m
    if k % CLASSIC_EVERY == 2:
        return ""
    j = sum(1 for t in range(MIX_FROM, n) if (t - chapter_start(t)) % CLASSIC_EVERY != 2)
    return MECH_ORDER[j % len(MECH_ORDER)]


def intro_index(n):
    """Номер уровня среди первых INTRO уровней главы, вводящей механику (0..INTRO-1), иначе -1."""
    if n < FIRST or n >= MIX_FROM:
        return -1
    k = n - chapter_start(n)
    return k if k < INTRO else -1


def target_scale(n):
    i = intro_index(n)
    return INTRO_SCALE[i] if i >= 0 else 1.0


def max_rule(n, base):
    """Самый сложный приём: у вводных уровней механики — без пробы."""
    return min(base, 4) if intro_index(n) >= 0 else base


def unknown_count(n, rng):
    """Сколько чисел спрятать за «?»: на вводных уровнях одно, дальше одно или два."""
    return 1 if intro_index(n) >= 0 else rng.choice([1, 1, 2])


# --- Разбиение поля с занятыми клетками (площади и веса — как у основного пути) -----------------------------
def partition(cols, rows, blocked, amax, side, rng, weights=None):
    wt = dict(LD.AREA_WEIGHT)
    if weights:
        wt.update(weights)
    used = [0] * (cols * rows)
    for (x, y) in blocked:
        used[y * cols + x] = 1
    rects = []
    for i in range(cols * rows):
        if used[i]:
            continue
        x, y = i % cols, i // cols
        mw = 0
        while x + mw < cols and mw < side and not used[y * cols + x + mw]:
            mw += 1
        opts, ws = [], []
        for w in range(1, mw + 1):
            for h in range(1, side + 1):
                if y + h > rows or any(used[(y + h - 1) * cols + xx] for xx in range(x, x + w)):
                    break
                a = w * h
                if a < 2 or a > amax or a not in wt:
                    continue
                g = wt[a] * (0.6 if min(w, h) == 1 and max(w, h) >= 4 else 1.0)
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


def pick_pin(cols, rows, rng):
    w, h = rng.choice(PIN_SHAPES)
    x0 = rng.randrange(1, cols - w) if cols - w > 1 else 0
    y0 = rng.randrange(1, rows - h) if rows - h > 1 else 0
    return (x0, y0, w, h)


def cells_of(r):
    x, y, w, h = r
    return [(xx, yy) for yy in range(y, y + h) for xx in range(x, x + w)]


# --- Подбор сложности -------------------------------------------------------------------------------------
def _err(g, target, mr):
    return abs(g["score"] - target) + (1000.0 if g["max_rule"] > mr or not g["solved"] else 0.0)


def tune(build, rects, pos, rng, target, mr, iters, forbid=frozenset()):
    """Как level_design.tune, но головоломку собирает build(pos) — с механикой; числа не встают на forbid."""
    pos = list(pos)
    g = build(pos).grade()
    cur = _err(g, target, mr)
    for _ in range(iters):
        if cur < 0.5:
            break
        i = rng.randrange(len(rects))
        x, y, w, h = rects[i]
        p = (x + rng.randrange(w), y + rng.randrange(h))
        if p == pos[i] or p in forbid:
            continue
        old, pos[i] = pos[i], p
        pz = build(pos)
        if pz.count_solutions(limit=2)[0] == 1:
            g2 = pz.grade()
            d2 = _err(g2, target, mr)
            if g2["solved"] and d2 <= cur:
                g, cur = g2, d2
                continue
        pos[i] = old
    return pos, g


def add_tints(cols, rows, rects, pos, amax, side, rng):
    """Цветные клетки, без которых решение не единственное (как mechanics_lab.gen_tints). -> tints | None."""
    ref = frozenset(rects)
    area_at = {c: r[2] * r[3] for r in rects for c in cells_of(r)}
    nums = [(p, r[2] * r[3]) for p, r in zip(pos, rects)]
    tints = {}
    n, sols = LAB.MechPuzzle(cols, rows, nums, max_area=amax, max_side=side).count_solutions(limit=2)
    if n == 1:
        return None  # уже единственное — цвет не нужен
    while n != 1:
        if n == 0 or len(tints) >= MAX_TINTS:
            return None
        alt = next(s for s in sols if s != ref)
        cells = [c for ar in alt for c in cells_of(ar)
                 if ar[2] * ar[3] != area_at[c] and area_at[c] <= TINT_MAX_AREA and c not in pos and c not in tints]
        if not cells:
            return None
        c = rng.choice(cells)
        tints[c] = area_at[c]
        n, sols = LAB.MechPuzzle(cols, rows, nums, tints=tints, max_area=amax, max_side=side).count_solutions(limit=2)
    return tints


def tune_tints(cols, rows, rects, pos, tints, amax, side, rng, target, mr, iters):
    """Подбор сложности уровня с цветными клетками: двигаются и числа, и цветные клетки (перенос, удаление).
    Ход принимается, если решение единственное с цветом и не единственное без него (цвет нужен), а оценка не
    дальше от цели. Цвет — подсказка «бесплатно» для оценки, поэтому одни числа (tune) не дотягивали до цели
    (сессия 97: уровень 260 — цель 42,8, оценка 4); с переносом цвета — в допуске. Меняет tints на месте."""
    areas = [r[2] * r[3] for r in rects]
    area_at = {c: r[2] * r[3] for r in rects for c in cells_of(r)}
    spots = sorted(c for c, a in area_at.items() if a <= TINT_MAX_AREA)

    def pz(ps, ts):
        return LAB.MechPuzzle(cols, rows, list(zip(ps, areas)), frozenset(), ts, max_area=amax, max_side=side)

    pos = list(pos)
    g = pz(pos, tints).grade()
    cur = _err(g, target, mr)
    for _ in range(iters):
        if cur < 0.5:
            break
        ps, ts = list(pos), dict(tints)
        r = rng.random()
        if r < 0.6:
            i = rng.randrange(len(rects))
            x, y, w, h = rects[i]
            p = (x + rng.randrange(w), y + rng.randrange(h))
            if p == ps[i] or p in ts:
                continue
            ps[i] = p
        else:
            del ts[rng.choice(sorted(ts))]
            if r < 0.85 or not ts:
                c = rng.choice(spots)
                if c in ps or c in ts:
                    continue
                ts[c] = area_at[c]
        p2 = pz(ps, ts)
        if p2.count_solutions(limit=2)[0] != 1:
            continue
        if pz(ps, {}).count_solutions(limit=2)[0] == 1:
            continue  # без цвета решение и так единственное — цвет не нужен
        g2 = p2.grade()
        d2 = _err(g2, target, mr)
        if g2["solved"] and d2 <= cur:
            pos, g, cur = ps, g2, d2
            tints.clear()
            tints.update(ts)
    return pos, g


def candidate(n, mech, spec, target, mr, iters, rng):
    """Один уровень с механикой mech. -> (rec без служебных полей, grade) или None."""
    cols, rows, amax, side, weights = spec
    holes, pin = frozenset(), None
    if mech == "holes":
        _, holes = LAB.hole_pattern(cols, rows, rng)
    elif mech == "pinned":
        pin = pick_pin(cols, rows, rng)
    blocked = set(holes) | (set(cells_of(pin)) if pin else set())
    rects = partition(cols, rows, blocked, amax, side, rng, weights)
    if not rects:
        return None
    if mech == "tints" and not any(r[2] * r[3] <= TINT_MAX_AREA for r in rects):
        return None
    areas = [r[2] * r[3] for r in rects]
    tints, unknown = {}, []

    def build(ps, hide=()):
        nums = [(p, None if i in hide else a) for i, (p, a) in enumerate(zip(ps, areas))]
        return LAB.MechPuzzle(cols, rows, nums, frozenset(blocked), tints, max_area=amax, max_side=side)

    if mech == "tints":
        pos = [(x + rng.randrange(w), y + rng.randrange(h)) for x, y, w, h in rects]
        got = add_tints(cols, rows, rects, pos, amax, side, rng)
        if not got:
            return None
        tints.update(got)
        pos, g = tune_tints(cols, rows, rects, pos, tints, amax, side, rng, target, mr, iters * 2)
    else:
        pos = LAB.make_unique(build, rects, rng)
        if pos is None:
            return None
        if mech == "unknown":
            # Сначала числа — к цели чуть ниже (за «?» сложность растёт), потом какие спрятать: решение
            # единственное, оценка ближе всего к цели.
            pos, g = tune(build, rects, pos, rng, target * 0.8, mr, iters)
            want = unknown_count(n, rng)
            best = None
            idx = list(range(len(rects)))
            for _ in range(UNKNOWN_TRIES):
                hide = frozenset(rng.sample(idx, want))
                pz = build(pos, hide)
                if pz.count_solutions(limit=2)[0] != 1:
                    continue
                g2 = pz.grade()
                if not g2["solved"]:
                    continue
                d = _err(g2, target, mr)
                if best is None or d < best[0]:
                    best = (d, hide, g2)
            if best is None:
                return None
            _, hide, g = best
            unknown = sorted(pos[i] for i in hide)
        else:
            pos, g = tune(build, rects, pos, rng, target, mr, iters)
    if not g["solved"] or g["max_rule"] > mr:
        return None
    pieces = [(h, w) if rng.random() < 0.5 else (w, h) for _, _, w, h in rects]
    rng.shuffle(pieces)
    rec = dict(cols=cols, rows=rows, rects=rects, pos=[tuple(p) for p in pos], pieces=pieces, mechanic=mech,
               holes=sorted(holes, key=lambda c: (c[1], c[0])), pinned=pin,
               tints=sorted(([c[0], c[1], a] for c, a in tints.items()), key=lambda t: (t[1], t[0])),
               unknown=[list(p) for p in unknown])
    return rec, g


def build(n, mech, spec, target, mr, rng, max_candidates, iters):
    """Лучший из max_candidates уровней с механикой (ближе к цели; при попадании в допуск — сразу)."""
    tol = max(0.5, 0.12 * target)
    best, tried = None, 0
    while tried < max_candidates or best is None:
        tried += 1
        if tried > max_candidates * 20:
            raise RuntimeError("уровень %d (%s): не удалось собрать" % (n, mech))
        got = candidate(n, mech, spec, target, mr, iters, rng)
        if not got:
            continue
        rec, g = got
        err = abs(g["score"] - target)
        if best is None or err < best[0]:
            best = (err, rec, g)
        if err <= tol:
            break
    _, rec, g = best
    rec.update(score=g["score"], max_rule=g["max_rule"], uses=g["uses"], ambiguity=round(g["ambiguity"], 2),
               candidates=tried)
    return rec


def plan_lines():
    out = []
    for first in range(FIRST, LAST + 1, SPAN):
        row = "".join({"": ".", "holes": "H", "pinned": "P", "tints": "T", "unknown": "?"}[mechanic(n)]
                      for n in range(first, first + SPAN))
        out.append("%3d–%3d  %s" % (first, first + SPAN - 1, row))
    return out


def plan_string():
    """План уровней FIRST..LAST одной строкой (H, P, T, Q, «.» — классика); по SPAN на главу — CHAPTER_MECH_PLAN
    в tests/selftest.gd (--gd)."""
    letters = {"holes": "H", "pinned": "P", "tints": "T", "unknown": "Q", "": "."}
    return "".join(letters[mechanic(n)] for n in range(FIRST, LAST + 1))


def main(argv):
    import make_levels as MLV
    print("План механик по главам (H — препятствия, P — закреплённый блок, T — цвет, ? — «?», . — классика):")
    for line in plan_lines():
        print("  " + line)
    if "--gd" in argv:
        plan = plan_string()
        print("const CHAPTER_MECH_PLAN: Array[String] = [")
        for i in range(0, len(plan), SPAN):
            print('\t\t"%s",' % plan[i:i + SPAN])
        print("]")
        return
    for a in argv:
        n = int(a)
        mech = mechanic(n)
        if not mech:
            print("уровень %d — классика" % n)
            continue
        cols, rows, amax, side, weights, _ = MLV.spec(n)
        t = MLV.target(n) * target_scale(n)
        t0 = time.time()
        rec = build(n, mech, (cols, rows, amax, side, weights), t, max_rule(n, MLV.max_rule(n)),
                    random.Random("probe-%d" % n), 24, 150)
        print("уровень %d (%s): цель %.1f, оценка %.1f, приём %d, кандидатов %d, %.1f с" % (
            n, mech, t, rec["score"], rec["max_rule"], rec["candidates"], time.time() - t0))


if __name__ == "__main__":
    main(sys.argv[1:])
