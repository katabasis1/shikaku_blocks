#!/usr/bin/env python3
"""Сердца (этап 20, PLAN 20.1–20.2): Python-копия правил scripts/hearts.gd и разбор тупиков уровней.

1. Правила. Класс Hearts — тот же набор полей и функций, что у scripts/hearts.gd. Таблицы MAX_FOR_CASES и
   SCENARIOS — сценарии с ожидаемым итогом; tests/selftest.gd (_test_hearts_rules) гоняет те же таблицы в Godot.
   Поменял правила — поменяй обе копии и таблицы, запусти `python3 tools/hearts_model.py --rules`.

2. Тупики (20.2, «причина тупика»). Ошибка — ход, после которого поле не заполнить (решатель: UNSOLVABLE). Чтобы
   подпись была честной, а не «так нельзя», важно, видно ли игроку, почему ход тупиковый. Для уровней основного пути
   (с hearts_from_level) берём состояния по ходу решения: пусто, затем блоки решения в случайном (по уровню —
   одинаковом) порядке; в каждом — все ходы, которые игра примет (одно число, площадь, свободно, цвет; форма есть
   в лотке). Тупиковые делятся на:
     number   — у какого-то числа не осталось ни одного места (подсветить число);
     cell     — пустую клетку больше не накрыть ни одним местом ни одного числа (подсветить клетку);
     forced:k — видно после k вынужденных блоков (у числа одно место, ставим его) — число или клетка;
     deep     — вынужденные кончились, а противоречия не видно (только общая подпись);
     pieces   — места у всех чисел есть, но не хватает блоков нужной формы (два числа на один оставшийся блок).
   Ещё по уровню: доля тупиковых среди принимаемых ходов и «цена угадывания» — сколько ошибок в среднем сделает
   игрок, который ставит случайный принимаемый ход и не повторяет уже сгоревший: на каждом шаге d / (g + 1),
   d — тупиковых ходов, g — верных (при одном решении верный ход — блок решения).
   Итог — tools/hearts_report.txt; на нём решается, хватает ли 20.2 подписи «Так остальные блоки не поместятся».

Запуск:
    python3 tools/hearts_model.py --rules          # только правила
    python3 tools/hearts_model.py --to 300         # правила и тупики уровней 4..300 (по умолчанию 4..200)
"""
import argparse
import os
import random
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_levels as ML  # noqa: E402
import model as M  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPORT = os.path.join(ROOT, "tools", "hearts_report.txt")

# Как YSDK.DEFAULT_* (autoload/ysdk.gd).
DEFAULT_HEARTS = 3
DEFAULT_HEARTS_FROM_LEVEL = 4
DEFAULT_REVIVE_MAX = 3
DEFAULT_REVIVE_FREE_ON_FAIL = True
FORCED_MAX = 12


# --- 1. Правила (копия scripts/hearts.gd) --------------------------------------

class Hearts:
    STARS_MAX = 3

    def __init__(self):
        self.max_hearts = 0
        self.left = 0
        self.mistakes = 0
        self.revives = 0
        self.free_used = False

    @staticmethod
    def max_for(level, is_daily, is_lab, hearts, from_level):
        if is_lab or hearts <= 0:
            return 0
        if not is_daily and level < from_level:
            return 0
        return hearts

    def reset(self, n_max):
        self.max_hearts = max(n_max, 0)
        self.left = self.max_hearts
        self.mistakes = 0
        self.revives = 0
        self.free_used = False

    def is_limited(self):
        return self.max_hearts > 0

    def lose(self):
        self.mistakes += 1
        if self.max_hearts > 0 and self.left > 0:
            self.left -= 1

    def is_out(self):
        return self.max_hearts > 0 and self.left <= 0

    def can_revive(self, revive_max):
        return self.is_out() and self.revives < revive_max

    def can_continue_free(self, allow):
        return allow and not self.free_used

    def revive(self, free=False):
        self.revives += 1
        if free:
            self.free_used = True
        self.left += 1

    def stars(self, hints_used):
        if self.revives > 0:
            return 1
        return min(max(self.STARS_MAX - self.mistakes - max(hints_used, 0), 1), self.STARS_MAX)


# (уровень, задача дня, «Лаборатория», флаг hearts, флаг hearts_from_level) -> сердец на попытку.
# Та же таблица — tests/selftest.gd, HEARTS_MAX_FOR_CASES.
MAX_FOR_CASES = [
    ((1, False, False, 3, 4), 0),     # обучение со страховкой — без сердец
    ((3, False, False, 3, 4), 0),
    ((4, False, False, 3, 4), 3),     # первый уровень с сердцами
    ((250, False, False, 3, 4), 3),
    ((1, True, False, 3, 4), 3),      # задача дня — всегда с сердцами, даже если её уровень меньше from_level
    ((50, False, True, 3, 4), 0),     # «Лаборатория» — без сердец
    ((50, False, False, 0, 4), 0),    # флаг hearts = 0 — без предела (A/B)
    ((50, True, False, 0, 4), 0),
    ((9, False, False, 5, 10), 0),    # флаги сдвинули начало
    ((10, False, False, 5, 10), 5),
]

# Сценарий попытки: имя, сердец на попытку, ходы, подсказок, возрождений можно (revive_max),
# бесплатное продолжение разрешено (revive_free_on_fail) -> ожидание
# (осталось, ошибок, возрождений, кончились, можно возродиться, можно бесплатно, звёзд).
# Ходы: L — ошибка (lose), R — возрождение за рекламу, F — бесплатное продолжение.
# Та же таблица — tests/selftest.gd, HEARTS_SCENARIOS.
SCENARIOS = [
    ("без ошибок", 3, "", 0, 3, True, (3, 0, 0, False, False, True, 3)),
    ("одна ошибка", 3, "L", 0, 3, True, (2, 1, 0, False, False, True, 2)),
    ("ошибка и подсказка", 3, "L", 1, 3, True, (2, 1, 0, False, False, True, 1)),
    ("две ошибки", 3, "LL", 0, 3, True, (1, 2, 0, False, False, True, 1)),
    ("три подсказки — не ниже 1", 3, "", 3, 3, True, (3, 0, 0, False, False, True, 1)),
    ("сердца кончились", 3, "LLL", 0, 3, True, (0, 3, 0, True, True, True, 1)),
    ("ошибка при нуле — не ниже 0", 3, "LLLL", 0, 3, True, (0, 4, 0, True, True, True, 1)),
    ("возрождение за рекламу", 3, "LLLR", 0, 3, True, (1, 3, 1, False, False, True, 1)),
    ("бесплатное продолжение", 3, "LLLF", 0, 3, True, (1, 3, 1, False, False, False, 1)),
    ("второе бесплатное нельзя", 3, "LLLFL", 0, 3, True, (0, 4, 1, True, True, False, 1)),
    ("бесплатное выключено флагом", 3, "LLL", 0, 3, False, (0, 3, 0, True, True, False, 1)),
    ("возрождения исчерпаны", 3, "LLLRLRLRL", 0, 3, True, (0, 6, 3, True, False, True, 1)),
    ("возрождений 0 (флаг)", 3, "LLL", 0, 0, True, (0, 3, 0, True, False, True, 1)),
    ("пять сердец, две ошибки", 5, "LL", 0, 3, True, (3, 2, 0, False, False, True, 1)),
    ("одно сердце", 1, "L", 0, 3, True, (0, 1, 0, True, True, True, 2)),
    ("без предела: ошибки считаются", 0, "LL", 0, 3, True, (0, 2, 0, False, False, True, 1)),
    ("без предела: одна ошибка", 0, "L", 0, 3, True, (0, 1, 0, False, False, True, 2)),
]


def run_scenario(n_max, ops, hints, revive_max, allow_free):
    h = Hearts()
    h.reset(n_max)
    for op in ops:
        if op == "L":
            h.lose()
        elif op == "R":
            assert h.can_revive(revive_max), "возрождение вне правил"
            h.revive(False)
        elif op == "F":
            assert h.can_revive(revive_max) and h.can_continue_free(allow_free), "бесплатное вне правил"
            h.revive(True)
        else:
            raise ValueError(op)
    return (h.left, h.mistakes, h.revives, h.is_out(), h.can_revive(revive_max), h.can_continue_free(allow_free),
            h.stars(hints))


SELFTEST = os.path.join(ROOT, "tests", "selftest.gd")


def gd_table(name):
    """Таблица const NAME := [...] из tests/selftest.gd как список Python (true/false → True/False)."""
    import ast
    import re
    with open(SELFTEST, encoding="utf-8") as f:
        src = f.read()
    m = re.search(r"^const %s := (\[.*?^\])" % name, src, re.S | re.M)
    if not m:
        return None
    body = re.sub(r"\btrue\b", "True", re.sub(r"\bfalse\b", "False", m.group(1)))
    return ast.literal_eval(body)


def check_selftest_tables():
    """Таблицы selftest.gd (HEARTS_MAX_FOR_CASES, HEARTS_SCENARIOS) — те же, что здесь."""
    bad = 0
    want_max = [list(args) + [n] for args, n in MAX_FOR_CASES]
    want_sc = [[name, n, ops, hints, rmax, free, list(res)] for name, n, ops, hints, rmax, free, res in SCENARIOS]
    for name, want in (("HEARTS_MAX_FOR_CASES", want_max), ("HEARTS_SCENARIOS", want_sc)):
        got = gd_table(name)
        if got is None:
            bad += 1
            print("selftest.gd: нет таблицы %s" % name)
        elif got != want:
            bad += 1
            extra = [r for r in got if r not in want]
            miss = [r for r in want if r not in got]
            print("selftest.gd: %s разошлась с Python — лишние %s, нет %s" % (name, extra, miss))
    return bad


def check_rules():
    bad = check_selftest_tables()
    for args, want in MAX_FOR_CASES:
        got = Hearts.max_for(*args)
        if got != want:
            bad += 1
            print("max_for%s = %d, ждали %d" % (args, got, want))
    for name, n_max, ops, hints, rmax, free, want in SCENARIOS:
        got = run_scenario(n_max, ops, hints, rmax, free)
        if got != want:
            bad += 1
            print("«%s»: %s, ждали %s" % (name, got, want))
    print("правила сердец: случаев %d, расхождений %d (с таблицами tests/selftest.gd)"
          % (len(MAX_FOR_CASES) + len(SCENARIOS), bad))
    return bad == 0


# --- 2. Тупики уровней (20.2) ---------------------------------------------------

def blocked_cells(d):
    out = set(tuple(c) for c in d.get("holes", []))
    for (x0, y0, w, h) in d.get("pinned", []):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                out.add((x, y))
    return out


def cells(r):
    x0, y0, w, h = r
    return {(x, y) for y in range(y0, y0 + h) for x in range(x0, x0 + w)}


def places(d, p, v, occ, pieces):
    """Места числа v в клетке p, которые игра примет (Board.rect_issue): одно число, площадь (у «?» — любая
    форма лотка), свободно, цвет (tint_ok), форма есть в лотке pieces (в любом повороте)."""
    cols, rows = d["cols"], d["rows"]
    kinds = sorted({M.key(pc) for pc in pieces})
    allnum = {q for q, _ in d["numbers"]}
    out = []
    for (w, h) in M.shapes_for(v, kinds):
        if w > cols or h > rows:
            continue
        for y0 in range(max(0, p[1] - h + 1), min(p[1], rows - h) + 1):
            for x0 in range(max(0, p[0] - w + 1), min(p[0], cols - w) + 1):
                r = (x0, y0, w, h)
                cs = cells(r)
                if cs & occ or any(q in cs and q != p for q in allnum):
                    continue
                if not M.tint_ok(x0, y0, w, h, d.get("tints") or {}):
                    continue
                out.append(r)
    return out


def take_piece(pieces, r):
    k = M.key(r[2:])
    out = list(pieces)
    for i, pc in enumerate(out):
        if M.key(pc) == k:
            del out[i]
            return out
    raise ValueError("нет блока %s" % (r,))


def open_numbers(d, occ):
    return [(p, v) for p, v in d["numbers"] if p not in occ]


def visible_reason(d, occ, pieces):
    """'number' / 'cell' — противоречие видно сразу, None — нет; второе — карта мест чисел."""
    nums = open_numbers(d, occ)
    cand = {p: places(d, p, v, occ, pieces) for p, v in nums}
    if any(not c for c in cand.values()):
        return "number", cand
    cover = set()
    for c in cand.values():
        for r in c:
            cover |= cells(r)
    free = {(x, y) for y in range(d["rows"]) for x in range(d["cols"])} - occ
    if free - cover:
        return "cell", cand
    return None, cand


def classify_dead(d, occ, pieces):
    """Причина тупика после хода (occ и pieces — уже с ошибочным блоком)."""
    occ = set(occ)
    pieces = list(pieces)
    for k in range(FORCED_MAX + 1):
        why, cand = visible_reason(d, occ, pieces)
        if why:
            return why if k == 0 else "forced:%d" % k
        forced = [(p, c[0]) for p, c in cand.items() if len(c) == 1]
        if not forced:
            break
        _, r = forced[0]
        occ |= cells(r)
        pieces = take_piece(pieces, r)
    # Места у всех чисел есть и клетки накрываются: не хватает ли блоков нужной формы?
    need = Counter()
    for p, c in cand.items():
        kinds = {M.key(r[2:]) for r in c}
        if len(kinds) == 1:
            need[next(iter(kinds))] += 1
    have = Counter(M.key(pc) for pc in pieces)
    if any(n > have[k] for k, n in need.items()):
        return "pieces"
    return "deep"


def level_states(d, level):
    """Состояния по ходу решения: пусто, затем блоки решения по одному в случайном (по уровню) порядке."""
    order = list(range(len(d["solution"])))
    random.Random(level * 7919).shuffle(order)
    placed = []
    pieces = list(d["pieces"])
    states = [(list(placed), list(pieces))]
    for i in order[:-1]:
        r = tuple(d["solution"][i])
        placed.append(r)
        pieces = take_piece(pieces, r)
        states.append((list(placed), list(pieces)))
    return states


def analyze_level(d, level):
    blocked = blocked_cells(d)
    reasons = Counter()
    dead_total = good_total = 0
    guess = 0.0
    for placed, pieces in level_states(d, level):
        occ = set(blocked)
        for r in placed:
            occ |= cells(r)
        dead = good = 0
        for p, v in open_numbers(d, occ):
            for r in places(d, p, v, occ, pieces):
                rest = take_piece(pieces, r)
                st, _, _ = M.solve(d["cols"], d["rows"], d["numbers"], placed + [r], rest,
                                   blocked=tuple(blocked), tints=d.get("tints") or None)
                if st == M.UNSOLVABLE:
                    dead += 1
                    reasons[classify_dead(d, occ | cells(r), rest)] += 1
                elif st == M.SOLVED:
                    good += 1
                else:
                    reasons["limit"] += 1
        dead_total += dead
        good_total += good
        guess += dead / (good + 1)
    return reasons, dead_total, good_total, guess


def band_of(level):
    for lo, hi in [(4, 10), (11, 25), (26, 50), (51, 100), (101, 150), (151, 200), (201, 250), (251, 300),
                   (301, 400), (401, 600), (601, 1000)]:
        if lo <= level <= hi:
            return "%d–%d" % (lo, hi)
    return "?"


def analyze(lo, hi):
    pack = ML.read_pack()
    lines = [
        "# Тупики уровней %d–%d (tools/hearts_model.py, PLAN 20.2). Не правьте вручную." % (lo, hi),
        "# Причины: number — у числа нет мест, cell — клетку не накрыть, forced:k — видно после k вынужденных,",
        "# pieces — не хватает блоков формы, deep — не видно без перебора, limit — решатель не уложился.",
        "# Цена угадывания — ошибок у игрока, который ставит случайный принимаемый ход (сердец по умолчанию %d)."
        % DEFAULT_HEARTS,
        "",
    ]
    bands = {}
    per_level = []
    total = Counter()
    for level in range(lo, hi + 1):
        d = ML.pack_level(level, pack)
        reasons, dead, good, guess = analyze_level(d, level)
        b = bands.setdefault(band_of(level), {"levels": 0, "reasons": Counter(), "dead": 0, "good": 0,
                                                "guess": [], "over": 0})
        b["levels"] += 1
        b["reasons"] += reasons
        b["dead"] += dead
        b["good"] += good
        b["guess"].append(guess)
        b["over"] += guess >= DEFAULT_HEARTS
        total += reasons
        per_level.append((level, dead, good, guess, reasons))
    def fmt_reasons(rs):
        n = sum(rs.values()) or 1
        vis = rs["number"] + rs["cell"]
        forced = sum(v for k, v in rs.items() if k.startswith("forced:"))
        return "видно сразу %3.0f%% (число %3.0f%%, клетка %3.0f%%) | после вынужденных %3.0f%% | формы %3.0f%% | " \
               "глубоко %3.0f%% | лимит %d" % (100 * vis / n, 100 * rs["number"] / n, 100 * rs["cell"] / n,
                                             100 * forced / n, 100 * rs["pieces"] / n, 100 * rs["deep"] / n,
                                             rs["limit"])
    lines.append("## По полосам уровней")
    lines.append("полоса      ур.  тупиковых ходов  цена угадывания (среднее / макс, ур. с ценой ≥ сердец)  причины")
    for name, b in bands.items():
        n = b["dead"] + b["good"]
        g = b["guess"]
        lines.append("%-10s %4d  %5d из %5d (%2.0f%%)  %4.1f / %4.1f, %3d  %s" % (
            name, b["levels"], b["dead"], n, 100.0 * b["dead"] / max(1, n), sum(g) / len(g), max(g), b["over"],
            fmt_reasons(b["reasons"])))
    lines.append("")
    lines.append("## Всего: " + fmt_reasons(total))
    forced_depth = Counter({k: v for k, v in total.items() if k.startswith("forced:")})
    if forced_depth:
        lines.append("   глубина вынужденных: " + ", ".join("%s — %d" % (k.split(":")[1], v)
                                                        for k, v in sorted(forced_depth.items(),
                                                                           key=lambda kv: int(kv[0].split(":")[1]))))
    lines.append("")
    lines.append("## Уровни с самой высокой ценой угадывания")
    for level, dead, good, guess, reasons in sorted(per_level, key=lambda t: -t[3])[:15]:
        lines.append("L%04d  тупиковых %3d, верных %3d, цена %.1f  глубоких %d" % (level, dead, good, guess,
                                                                                  reasons["deep"]))
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rules", action="store_true", help="только правила")
    ap.add_argument("--from", dest="lo", type=int, default=DEFAULT_HEARTS_FROM_LEVEL)
    ap.add_argument("--to", dest="hi", type=int, default=200)
    a = ap.parse_args()
    ok = check_rules()
    if a.rules:
        sys.exit(0 if ok else 1)
    lines = analyze(a.lo, a.hi)
    with open(REPORT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines[5:20]))
    print("записано:", REPORT)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
