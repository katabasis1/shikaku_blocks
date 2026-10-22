#!/usr/bin/env python3
"""Заготовленные уровни -> scripts/level_pack_data.gd и отчёт tools/levels_report.txt.

Каждый уровень:
* решение единственное по правилам шикаку (только числа, без учёта блоков);
* сложность подобрана под кривую: рост с номером уровня + волна из 5 уровней
  (обычный, чуть труднее, передышка, вызов; каждый 10-й — сильный вызов);
* размер поля — как у процедурного генератора (4×4 … 7×8), блоки растут:
  с 61-го появляются 5 (1×5) и 10 (2×5), со 101-го — 12 (3×4).

После последнего уровня игра повторяет уровни LOOP_FROM..COUNT отражёнными
(решение остаётся единственным) и с новым порядком блоков — scripts/level_pack.gd.

Уровни 1..3 — обучающие, сделаны вручную (tools/tutorial_levels.py, PINNED): берутся
как есть и проходят ещё и проверку своих учебных свойств.

Главы 4–10 (151–500, этап 19.5e): в части уровней — механика (препятствия, закреплённый блок, цветные клетки,
число «?»); какая и где — tools/chapter_levels.py (mechanic), там же генератор. Классические уровни — прежние
(тот же генератор и зерно). Механика пишется четвёртой частью строки (scripts/level_pack.gd, tools/make_lab.py).

Запуск из корня проекта (генерация идёт с места остановки — кэш в tools/.levels_cache.jsonl):
    python3 tools/make_levels.py              # сгенерировать недостающие и записать список
    python3 tools/make_levels.py --jobs 4     # в 4 процесса
    python3 tools/make_levels.py --fresh      # без кэша
Поменяли кривую или алгоритм — увеличьте ALGO_VERSION (или SEED_VERSION, если уровни
должны поменяться у игроков) и запустите снова. PACK_VERSION — номер списка у игроков:
увеличивайте при любой смене уровней (он же входит в зерно порядка блоков повторов).
"""
import argparse
import json
import multiprocessing as mp
import pathlib
import random
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import chapter_levels as CL  # noqa: E402
import level_design as D  # noqa: E402
import make_lab as LABF  # noqa: E402
import mechanics_lab as LAB  # noqa: E402
import model as M  # noqa: E402
import tutorial_levels as TL  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_GD = ROOT / "scripts" / "level_pack_data.gd"
REPORT = ROOT / "tools" / "levels_report.txt"
CACHE = ROOT / "tools" / ".levels_cache.jsonl"

PACK_VERSION = 3     # номер списка у игроков (v2 — уровни 1..3 вручную, этап 11; v3 — механики глав, 19.5e)
SEED_VERSION = 1     # зерно генерации уровней: меняет все сгенерированные уровни у игроков
ALGO_VERSION = 1     # только для кэша
MECH_VERSION = 1     # генератор уровней с механикой (tools/chapter_levels.py): зерно и кэш
MECH_CANDIDATES = {"holes": 120, "pinned": 120, "tints": 120, "unknown": 40}  # меньше клеток — реже в цель
PINNED = TL.LEVELS   # уровни, сделанные вручную: номер -> данные
COUNT = 500
LOOP_FROM = 201
MAX_CANDIDATES = 40
TUNE_ITERS = 150
SEED_SALT = 0x5EED  # зерно для повторов после COUNT (перемешивание блоков)

# (уровень, цель) — базовая сложность, между точками линейно.
BASE_CURVE = [(4, 1.0), (10, 3.0), (25, 6.0), (48, 10.0), (100, 16.0), (200, 24.0), (500, 30.0)]


def spec(n):
    """-> (cols, rows, max_area, max_side, веса площадей, обязательные площади)"""
    cols, rows = M.grid_size(n)
    if n <= 3:
        amax, side = 4, 4
    elif n <= 10:
        amax, side = 6, 4
    elif n <= 25:
        amax, side = 8, 4
    elif n <= 60:
        amax, side = 9, 4
    elif n <= 100:
        amax, side = 10, 5
    else:
        amax, side = 12, 5
    weights = {}
    if n > 60:
        weights = {2: 0.6, 3: 1.8}
    must = {61: {5, 10}, 62: {5, 10}, 101: {12}, 102: {12}}.get(n, set())
    return cols, rows, amax, side, weights, must


def wave(n):
    if n % 10 == 0:
        return 1.7   # сильный вызов
    return {1: 0.85, 2: 1.0, 3: 1.15, 4: 0.5, 0: 1.4}[n % 5]  # 4 — передышка, 5 — вызов


def target(n):
    if n <= 3:
        return 0.0
    pts = BASE_CURVE
    if n <= pts[0][0]:
        base = pts[0][1]
    elif n >= pts[-1][0]:
        base = pts[-1][1]
    else:
        for (a, va), (b, vb) in zip(pts, pts[1:]):
            if a <= n <= b:
                base = va + (vb - va) * (n - a) / (b - a)
                break
    return round(base * wave(n), 2)


def max_rule(n):
    """Самый сложный приём, который может понадобиться (см. level_design.RULES)."""
    if n <= 3:
        return 2
    if n <= 10:
        return 3
    if n <= 100:
        return 4
    return 5 if n % 5 == 0 else 4


def mech_target(n):
    return round(target(n) * CL.target_scale(n), 2)


def signature(n):
    if n in PINNED:
        return json.dumps(["pinned", PINNED[n]], sort_keys=True)
    mech = CL.mechanic(n)
    if mech:
        return json.dumps(["mech", SEED_VERSION, MECH_VERSION, mech, MECH_CANDIDATES[mech], TUNE_ITERS, spec(n)[:4],
                           sorted(spec(n)[4].items()), mech_target(n), CL.max_rule(n, max_rule(n))])
    return json.dumps([SEED_VERSION, ALGO_VERSION, MAX_CANDIDATES, TUNE_ITERS, spec(n)[:4],
                       sorted(spec(n)[4].items()), sorted(spec(n)[5]), target(n), max_rule(n)])


def build(n):
    if n in PINNED:
        rec = TL.record(n)
        rec["sig"] = signature(n)
        return rec
    mech = CL.mechanic(n)
    if mech:
        cols, rows, amax, side, weights, _ = spec(n)
        T = mech_target(n)
        rng = random.Random("shikaku-mech-v%d-%d-%d" % (SEED_VERSION, MECH_VERSION, n))
        rec = CL.build(n, mech, (cols, rows, amax, side, weights), T, CL.max_rule(n, max_rule(n)), rng,
                       MECH_CANDIDATES[mech], TUNE_ITERS)
        rec.update(level=n, sig=signature(n), target=T)
        return rec
    rng = random.Random("shikaku-pack-v%d-%d" % (SEED_VERSION, n))
    cols, rows, amax, side, weights, must = spec(n)
    T, mr = target(n), max_rule(n)
    tol = max(0.5, 0.12 * T)
    best = None
    tried = 0
    while tried < MAX_CANDIDATES or best is None:
        tried += 1
        if tried > MAX_CANDIDATES * 20:
            raise RuntimeError("уровень %d: не удалось собрать" % n)
        rects = D.partition(cols, rows, amax, side, rng, weights)
        if not rects:
            continue
        if must and not (must & {w * h for _, _, w, h in rects}):
            continue
        pos = D.make_unique(cols, rows, rects, rng)
        if pos is None:
            continue
        pos, g = D.tune(cols, rows, rects, pos, rng, T, iters=TUNE_ITERS, max_rule=mr)
        if not g["solved"] or g["max_rule"] > mr:
            continue
        err = abs(g["score"] - T)
        if best is None or err < best[0]:
            best = (err, rects, pos, g)
        if err <= tol:
            break
    _, rects, pos, g = best
    pieces = []
    for _, _, w, h in rects:
        pieces.append((h, w) if rng.random() < 0.5 else (w, h))
    rng.shuffle(pieces)
    return dict(level=n, sig=signature(n), cols=cols, rows=rows, rects=rects, pos=pos,
                pieces=pieces, target=T, score=g["score"], max_rule=g["max_rule"],
                uses=g["uses"], ambiguity=round(g["ambiguity"], 2), candidates=tried)


# --- Формат строки (читает scripts/level_pack.gd) ---------------------------
# "CR:" + по 6 цифр на прямоугольник (x y w h и клетка числа x y) + ":" +
# по 2 цифры на блок в порядке выдачи (ширина, высота). У уровня с механикой (19.5e) — ещё ":" и метки
# (как в «Лаборатории», tools/make_lab.py): hXY — препятствие, pXYWH — закреплённый блок (в решение и лоток
# не входит), qXY — число «?», tXYA — цветная клетка площади A.

def mods_of(rec):
    """Четвёртая часть строки уровня (метки механики) или ""."""
    if not rec.get("mechanic"):
        return ""
    out = "".join("h%d%d" % tuple(c) for c in sorted(map(tuple, rec["holes"]), key=lambda c: (c[1], c[0])))
    if rec["pinned"]:
        out += "p%d%d%d%d" % tuple(rec["pinned"])
    out += "".join("q%d%d" % tuple(c) for c in sorted(map(tuple, rec["unknown"]), key=lambda c: (c[1], c[0])))
    out += "".join("t%d%d%d" % tuple(t) for t in sorted(map(tuple, rec["tints"]), key=lambda t: (t[1], t[0])))
    return out


def encode(rec):
    s = "%d%d:" % (rec["cols"], rec["rows"])
    for (x, y, w, h), (px, py) in zip(rec["rects"], rec["pos"]):
        s += "%d%d%d%d%d%d" % (x, y, w, h, px, py)
    s += ":" + "".join("%d%d" % p for p in rec["pieces"])
    mods = mods_of(rec)
    return s + (":" + mods if mods else "")


def decode(s):
    """-> dict(cols, rows, solution=[(x,y,w,h)], numbers=[((x,y), v)], pieces=[(w,h)],
    holes=[(x,y)], pinned=[(x,y,w,h)], tints={(x,y): площадь}); «?» — v = model.ANY. Копия LevelPack.decode
    (с проверками — tools/make_lab.py: decode)."""
    d = LABF.decode(s)
    if d is None:
        raise ValueError("строка уровня испорчена: " + s)
    d["numbers"] = [tuple(nm) for nm in d["numbers"]]
    return d


def mechanic_of(d):
    """Механика разобранного уровня (как LevelPack.mechanic_of): "holes" | "pinned" | "tints" | "unknown" | ""."""
    if d["holes"]:
        return "holes"
    if d["pinned"]:
        return "pinned"
    if d["tints"]:
        return "tints"
    if any(v == M.ANY for _, v in d["numbers"]):
        return "unknown"
    return ""


def pack_level(n, levels):
    """Копия LevelPack.get_level: уровень n из списка строк levels (1-based)."""
    count = len(levels)
    if n <= count:
        return decode(levels[n - 1])
    span = count - LOOP_FROM + 1
    k = n - count - 1
    base = decode(levels[LOOP_FROM - 1 + k % span])
    variant = 1 + (k // span) % 3          # 1 — зеркально по X, 2 — по Y, 3 — оба
    cols, rows = base["cols"], base["rows"]
    sol, nums = [], []
    for (x, y, w, h), ((px, py), v) in zip(base["solution"], base["numbers"]):
        if variant & 1:
            x, px = cols - x - w, cols - 1 - px
        if variant & 2:
            y, py = rows - y - h, rows - 1 - py
        sol.append((x, y, w, h))
        nums.append(((px, py), v))
    rng = M.Rng(M.mix32(n * 2654435761 + SEED_SALT + PACK_VERSION * 97531))
    pieces = []
    for (_, _, w, h) in sol:
        pieces.append((h, w) if rng.randf() < 0.5 else (w, h))
    for i in range(len(pieces) - 1, 0, -1):
        j = rng.randi_range(0, i)
        pieces[i], pieces[j] = pieces[j], pieces[i]
    # Механики (19.5e) отражаются вместе с полем: препятствия, закреплённые блоки, цветные клетки; «?» — в numbers.
    def fx(x, w=1):
        return cols - x - w if variant & 1 else x

    def fy(y, h=1):
        return rows - y - h if variant & 2 else y

    holes = [(fx(x), fy(y)) for x, y in base["holes"]]
    pinned = [(fx(x, w), fy(y, h), w, h) for x, y, w, h in base["pinned"]]
    tints = {(fx(x), fy(y)): a for (x, y), a in base["tints"].items()}
    return dict(cols=cols, rows=rows, solution=sol, numbers=nums, pieces=pieces, holes=holes, pinned=pinned,
                tints=tints)


def read_pack(path=OUT_GD):
    """Строки уровней из готового scripts/level_pack_data.gd."""
    import re
    text = pathlib.Path(path).read_text(encoding="utf-8")
    body = text.split("const LEVELS", 1)[1]
    return re.findall(r'"(\d\d:\d*:\d*(?::[a-z0-9]*)?)"', body)


# --- Проверки ---------------------------------------------------------------

def blocked_of(d):
    """Занятые до игры клетки: препятствия и закреплённые блоки."""
    return LABF.blocked_of(d)


def unique_by_numbers(d):
    """Единственное решение по числам и механике (без набора блоков — строже игры; как при генерации)."""
    if not mechanic_of(d):
        return D.Puzzle(d["cols"], d["rows"], d["numbers"]).count_solutions(limit=2)[0] == 1
    nums = [(p, None if v == M.ANY else v) for p, v in d["numbers"]]
    pz = LAB.MechPuzzle(d["cols"], d["rows"], nums, frozenset(blocked_of(d)), d["tints"], max_area=12, max_side=5)
    return pz.count_solutions(limit=2)[0] == 1


def verify_mech(rec, d):
    """Уровень с механикой (19.5e): та механика, что в плане, и только она; правила механики; одно решение по
    числам и по правилам игры (с набором блоков); решатель игры (с препятствиями, цветом, «?») решает с пустого
    поля и в случайной игре на каждом шаге (make_lab.random_play: подсказки и тупики в игре будут работать)."""
    errs = []
    n = rec["level"]
    kinds = [k for k, on in (("holes", d["holes"]), ("pinned", d["pinned"]), ("tints", d["tints"]),
                             ("unknown", any(v == M.ANY for _, v in d["numbers"]))) if on]
    if kinds != [CL.mechanic(n)]:
        errs.append("механики %s, по плану %s" % (kinds, CL.mechanic(n) or "нет"))
    if len(d["pinned"]) > 1:
        errs.append("закреплённых блоков %d" % len(d["pinned"]))
    msg = LABF.check_rules(d, d["solution"])
    if msg:
        errs.append("решение нарушает правила: " + msg)
    if not unique_by_numbers(d):
        errs.append("по числам решение не единственное")
    if d["tints"]:
        plain = dict(d, tints={})
        if unique_by_numbers(plain):
            errs.append("цветные клетки не нужны: без них решение и так единственное")
        if any(a > CL.TINT_MAX_AREA for a in d["tints"].values()):
            errs.append("цветная клетка площади больше %d" % CL.TINT_MAX_AREA)
    cnt = LABF.count_solutions(d)
    if cnt != 1:
        errs.append("решений по правилам игры: %d" % cnt)
    blocked = blocked_of(d)
    st, sol, steps = M.solve(d["cols"], d["rows"], d["numbers"], [], d["pieces"], LABF.STEP_LIMIT, blocked, d["tints"])
    if st != M.SOLVED:
        errs.append("решатель игры не справился (статус %d, шагов %d)" % (st, steps))
    elif sorted(sol) != sorted(d["solution"]):
        errs.append("решатель игры нашёл другое решение")
    msg, _ = LABF.random_play(d, random.Random(n))
    if msg:
        errs.append("случайная игра: " + msg)
    return errs


def verify(rec):
    """Независимая проверка готового уровня. -> список ошибок."""
    errs = []
    if rec["level"] in PINNED:
        errs += ["обучение: " + e for e in TL.check(rec["level"])]
    d = decode(encode(rec))
    if rec.get("mechanic") or mechanic_of(d) or CL.mechanic(rec["level"]):
        return errs + verify_mech(rec, d)
    cols, rows = d["cols"], d["rows"]
    grid = [0] * (cols * rows)
    for x, y, w, h in d["solution"]:
        if x < 0 or y < 0 or x + w > cols or y + h > rows:
            errs.append("прямоугольник за полем")
            continue
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                grid[yy * cols + xx] += 1
    if any(c != 1 for c in grid):
        errs.append("поле покрыто не ровно один раз")
    for (x, y, w, h), ((px, py), v) in zip(d["solution"], d["numbers"]):
        if not (x <= px < x + w and y <= py < y + h) or v != w * h:
            errs.append("число вне своего прямоугольника")
    if sorted(tuple(sorted(p)) for p in d["pieces"]) != sorted(tuple(sorted(r[2:])) for r in d["solution"]):
        errs.append("набор блоков не совпадает с решением")
    n, _ = D.Puzzle(cols, rows, d["numbers"]).count_solutions(limit=2)
    if n != 1:
        errs.append("решений: %d" % n)
    st, _, steps = M.solve(cols, rows, [(p, v) for p, v in d["numbers"]], [], d["pieces"])
    if st != 0:
        errs.append("решатель игры не справился (статус %d, шагов %d)" % (st, steps))
    return errs


# --- Запись -----------------------------------------------------------------

def write_gd(recs):
    lines = [
        "extends RefCounted",
        "## Заготовленные уровни. Файл создаёт tools/make_levels.py — не правьте вручную.",
        "## Формат и чтение — scripts/level_pack.gd.",
        "",
        "const VERSION := %d" % PACK_VERSION,
        "const LOOP_FROM := %d" % LOOP_FROM,
        "const SEED_SALT := %d" % SEED_SALT,
        "const LEVELS: Array[String] = [",
    ]
    for r in recs:
        lines.append('\t"%s",' % encode(r))
    lines.append("]")
    OUT_GD.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_report(recs, verify_errors):
    out = ["Заготовленные уровни: %d (PACK_VERSION=%d). Создано tools/make_levels.py." % (len(recs), PACK_VERSION), ""]
    out.append("Сложность — сумма цен приёмов, нужных для решения логикой (tools/level_design.py):")
    out.append("  " + ", ".join("%s — %g" % (D.RULE_NAMES[r], D.RULE_COST[r]) for r in D.RULES))
    out.append("")
    out.append("Проверка каждого уровня: покрытие, числа, набор блоков, единственное решение,")
    out.append("решатель игры (с блоками, лимит 4000 шагов); у уровней с механикой — ещё механика по плану,")
    out.append("её правила, одно решение по правилам игры, случайная игра с решателем. Ошибок: %d" % len(verify_errors))
    out.append("Уровни %s — обучающие, сделаны вручную (tools/tutorial_levels.py), цель 0." % (
        ", ".join(map(str, sorted(PINNED)))))
    for e in verify_errors[:20]:
        out.append("  " + e)
    out.append("")
    out.append("По участкам (средняя цель / средняя сложность / макс. / блоков в среднем / нужна проба):")
    bounds = [(1, 3), (4, 10), (11, 25), (26, 48), (49, 60), (61, 100), (101, 200), (201, 300), (301, 400), (401, 500)]
    for a, b in bounds:
        part = [r for r in recs if a <= r["level"] <= b]
        if not part:
            continue
        avg = lambda k: sum(r[k] for r in part) / len(part)
        out.append("  %3d–%3d: %5.1f / %5.1f / %5.1f / %4.1f / %d" % (
            a, b, avg("target"), avg("score"), max(r["score"] for r in part),
            sum(len(r["rects"]) for r in part) / len(part),
            sum(1 for r in part if r["max_rule"] >= 5)))
    out.append("")
    out.append("Механики глав 4–10 (19.5e, tools/chapter_levels.py; H — препятствия, P — закреплённый блок,")
    out.append("T — цветные клетки, ? — число «?», . — классика). По главе: уровней с механикой, средняя цель /")
    out.append("средняя сложность у них, наибольшее отклонение от цели:")
    letter = {"": ".", "holes": "H", "pinned": "P", "tints": "T", "unknown": "?"}
    for first in range(CL.FIRST, COUNT + 1, CL.SPAN):
        part = [r for r in recs if first <= r["level"] < first + CL.SPAN]
        mech = [r for r in part if r.get("mechanic")]
        row = "".join(letter[r.get("mechanic", "")] for r in part)
        if mech:
            out.append("  %3d–%3d  %s  %2d  %5.1f / %5.1f  %4.1f" % (
                first, first + CL.SPAN - 1, row, len(mech), sum(r["target"] for r in mech) / len(mech),
                sum(r["score"] for r in mech) / len(mech), max(abs(r["score"] - r["target"]) for r in mech)))
    out.append("")
    out.append(" ур.  поле  блоков  площади                 цель  слож.  приём  (1/2/3/4/5)  мех.")
    for r in recs:
        areas = sorted((w * h for _, _, w, h in r["rects"]), reverse=True)
        u = r["uses"]
        out.append(("%4d  %dx%d  %5d   %-22s %5.1f  %5.1f  %4d   %-11s  %s" % (
            r["level"], r["cols"], r["rows"], len(r["rects"]), " ".join(map(str, areas))[:22],
            r["target"], r["score"], r["max_rule"],
            "/".join(str(u[k] if k in u else u.get(str(k), 0)) for k in D.RULES),
            letter[r.get("mechanic", "")] if r.get("mechanic") else "")).rstrip())
    REPORT.write_text("\n".join(out) + "\n", encoding="utf-8")


def load_cache():
    recs = {}
    if CACHE.exists():
        for line in CACHE.read_text(encoding="utf-8").splitlines():
            try:
                r = json.loads(line)
            except ValueError:
                continue  # недописанная строка после обрыва
            n = r["level"]
            if 1 <= n <= COUNT and r["sig"] == signature(n):
                r["rects"] = [tuple(x) for x in r["rects"]]
                r["pos"] = [tuple(x) for x in r["pos"]]
                r["pieces"] = [tuple(x) for x in r["pieces"]]
                r["uses"] = {int(k): v for k, v in r["uses"].items()}
                recs[n] = r
    return recs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=max(1, mp.cpu_count()))
    ap.add_argument("--fresh", action="store_true")
    ap.add_argument("--upto", type=int, default=COUNT, help="сгенерировать только уровни 1..N (список не пишется)")
    args = ap.parse_args()
    if args.fresh and CACHE.exists():
        CACHE.unlink()
    recs = load_cache()
    todo = [n for n in range(1, args.upto + 1) if n not in recs]
    print("в кэше %d, генерировать %d" % (len(recs), len(todo)), flush=True)
    t0 = time.time()
    if todo:
        with open(CACHE, "a", encoding="utf-8") as f, mp.Pool(args.jobs) as pool:
            for i, r in enumerate(pool.imap_unordered(build, todo), 1):
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
                f.flush()
                recs[r["level"]] = r
                if i % 10 == 0 or i == len(todo):
                    print("  %d/%d  %.0f с" % (i, len(todo), time.time() - t0), flush=True)
    if args.upto < COUNT:
        return
    ordered = [recs[n] for n in range(1, COUNT + 1)]
    errors = []
    for r in ordered:
        for e in verify(r):
            errors.append("уровень %d: %s" % (r["level"], e))
    write_gd(ordered)
    write_report(ordered, errors)
    # Самопроверка копии чтения: список из файла совпадает с кэшем.
    levels = read_pack()
    assert len(levels) == COUNT and all(decode(levels[i]) == decode(encode(ordered[i])) for i in range(COUNT))
    for n in (COUNT + 1, COUNT + 6, COUNT + 300, COUNT + 301, COUNT + 1000):
        d = pack_level(n, levels)
        assert unique_by_numbers(d) and not LABF.check_rules(d, d["solution"]), n
    print("записано %s (%d уровней, %.0f КБ), отчёт %s; ошибок проверки: %d" % (
        OUT_GD.relative_to(ROOT), COUNT, OUT_GD.stat().st_size / 1024, REPORT.relative_to(ROOT), len(errors)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main() or 0)
