#!/usr/bin/env python3
"""Сердца (этап 20.1, PLAN 20.1): Python-копия правил scripts/hearts.gd и модель игроков по уровням игры.

1. Правила. Класс Hearts повторяет scripts/hearts.gd один в один (max_for, reset, lose, is_out, can_revive,
   can_continue_free, revive, stars), revive_gated — как Game.revive (возрождение только когда сердца кончились
   и возрождений меньше revive_max; бесплатное — один раз и если флаг revive_free_on_fail). Таблицы случаев
   MAX_FOR_CASES и CASES прогоняются здесь и в самопроверке (tests/selftest.gd, _test_hearts): их GDScript-текст
   между метками «hearts_model: begin / end» создаёт этот скрипт. Поменял правила или таблицу — перезапусти
   с --write (перепишет кусок selftest.gd), без --write расхождение — ошибка.

2. Модель игрока (--play). Уровни игры 1..1000 — как в игре (tools/make_levels.py: pack_level). Лоток — три
   гнезда и очередь в порядке level_data.pieces, освободившееся гнездо берёт следующий блок (Tray.fill_slot).
   Допустимый ход — блок лотка в любой ориентации, без нахлёста и препятствий, накрывает ровно одно число своей
   площади («?» — любой), цветные клетки — блоком своей площади (как Board / make_lab.random_play). Остальное
   в игре просто не встаёт (красный призрак) — сердце цело.
   Ошибка — допустимый ход вне решения: решение у каждого уровня одно (make_levels.py это проверяет), значит,
   после такого хода поле не заполнить, и решатель игры скажет UNSOLVABLE. --verify сверяет это с решателем
   (tools/model.py: solve) на всех допустимых ходах выборки позиций.
   Ошибочный блок возвращается в лоток, поле не меняется (20.1a), поэтому позиция — всегда часть решения.
   Игроки (решают «в уме» правилами оценщика сложности tools/level_design.py, по числам на поле — набор блоков
   игрок не видит; у «?» — формы набора; каждый свой неверный ход запоминает и больше не рассматривает):
     guess  — без логики: случайный допустимый ход (перебор «поставил — трещина»);
     simple — правила 1–2 (у числа один вариант, клетку накрывает один вариант);
     logic  — правила 1–4 (ещё клетка одного числа и пересечение), без проб.
   Выведенное в уме место ставится, если блок для него есть в лотке; иначе — догадка среди живых мест числа,
   у которого их меньше всего. Уровень, решаемый правилами 1–4 целиком, logic проходит без ошибок — ошибки у
   него только там, где нужна проба (make_levels: «нужна проба»), и это цена сердец для думающего игрока.
   Уровни 1..GUARD_LEVELS в игре не дают поставить тупиковый ход (страховка обучения) — там ошибок не бывает,
   модель их пропускает.
   Итог — по участкам уровней: ошибок за попытку, доля попыток с ошибкой, доля попыток, где сердца кончились
   (ошибок ≥ сердец), средние звёзды (без подсказок; кончились — возрождение, 1 звезда) и доля тупиковых среди
   допустимых первых ходов. --report пишет tools/hearts_report.txt.

Запуск из корня проекта:
    python3 tools/hearts_model.py                 # правила и сверка таблицы с selftest.gd
    python3 tools/hearts_model.py --write         # переписать таблицу в selftest.gd
    python3 tools/hearts_model.py --play --report # модель игроков 4..1000 → tools/hearts_report.txt
    python3 tools/hearts_model.py --play --levels 4-60 --runs 400
    python3 tools/hearts_model.py --verify --levels 4-200
Код выхода 0 — правила сходятся, таблица в selftest.gd та же, --verify без расхождений.
"""
import argparse
import os
import random
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SELFTEST = os.path.join(ROOT, "tests", "selftest.gd")
REPORT = os.path.join(ROOT, "tools", "hearts_report.txt")
BEGIN = "# hearts_model: begin"
END = "# hearts_model: end"

# Как в autoload/ysdk.gd (флаги getFlags, 16.2) и scripts/tutorial.gd.
DEFAULT_HEARTS = 3
DEFAULT_HEARTS_FROM_LEVEL = 4
DEFAULT_REVIVE_MAX = 3
DEFAULT_REVIVE_FREE_ON_FAIL = True
GUARD_LEVELS = 3
GAME_LEVELS = 1000
RANGES = [(4, 10), (11, 25), (26, 48), (49, 60), (61, 100), (101, 150), (151, 200), (201, 300), (301, 400),
          (401, 500), (501, 1000)]


# --- 1. Правила: копия scripts/hearts.gd ------------------------------------------------------------------------

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


def revive_gated(h, free, revive_max, free_allow):
    """Game.revive: False — сейчас нельзя (сердца не кончились, возрождения исчерпаны, бесплатное уже было)."""
    if not h.can_revive(revive_max):
        return False
    if free and not h.can_continue_free(free_allow):
        return False
    h.revive(free)
    return True


def apply_ops(h, ops, revive_max, free_allow):
    """ops: L — ошибка (Hearts.lose), R — возрождение за рекламу, F — бесплатное продолжение (через revive_gated)."""
    for op in ops:
        if op == "L":
            h.lose()
        elif op == "R":
            revive_gated(h, False, revive_max, free_allow)
        elif op == "F":
            revive_gated(h, True, revive_max, free_allow)
        else:
            raise ValueError("неизвестный шаг %r" % op)


# Hearts.max_for: [уровень, задача дня, «Лаборатория», флаг hearts, флаг hearts_from_level, ждём].
MAX_FOR_CASES = [
    [1, False, False, 3, 4, 0],     # обучение со страховкой — без сердец
    [3, False, False, 3, 4, 0],
    [4, False, False, 3, 4, 3],     # с 4-го — три
    [250, False, False, 3, 4, 3],
    [2, True, False, 3, 4, 3],      # задача дня — с сердцами всегда
    [20, False, True, 3, 4, 0],     # «Лаборатория» — без них
    [20, False, False, 0, 4, 0],    # флаг hearts = 0 — без предела
    [2, True, False, 0, 4, 0],
    [9, False, False, 5, 10, 0],
    [10, False, False, 5, 10, 5],
    [1, False, False, 1, 1, 1],
]

# Попытка: [сердец, шаги, подсказок, revive_max, revive_free_on_fail,
#           ждём: осталось, ошибок, возрождений, кончились, можно возродиться, бесплатное было, звёзды].
CASES = [
    [3, "", 0, 3, True, 3, 0, 0, False, False, False, 3],
    [3, "L", 0, 3, True, 2, 1, 0, False, False, False, 2],
    [3, "LL", 0, 3, True, 1, 2, 0, False, False, False, 1],
    [3, "", 1, 3, True, 3, 0, 0, False, False, False, 2],          # подсказка — минус звезда
    [3, "L", 1, 3, True, 2, 1, 0, False, False, False, 1],
    [3, "", 5, 3, True, 3, 0, 0, False, False, False, 1],          # не ниже 1
    [3, "R", 0, 3, True, 3, 0, 0, False, False, False, 3],         # сердца не кончились — возрождения нет
    [3, "LLL", 0, 3, True, 0, 3, 0, True, True, False, 1],
    [3, "LLLR", 0, 3, True, 1, 3, 1, False, False, False, 1],      # после возрождения — 1 звезда
    [3, "LLLRL", 0, 3, True, 0, 4, 1, True, True, False, 1],
    [3, "LLLRLRLRL", 0, 3, True, 0, 6, 3, True, False, False, 1],  # revive_max исчерпан
    [3, "LLLR", 0, 0, True, 0, 3, 0, True, False, False, 1],       # revive_max = 0
    [3, "LLLF", 0, 3, True, 1, 3, 1, False, False, True, 1],       # реклама не показалась — бесплатно
    [3, "LLLFLF", 0, 3, True, 0, 4, 1, True, True, True, 1],       # бесплатно — один раз
    [3, "LLLFLR", 0, 3, True, 1, 4, 2, False, False, True, 1],     # дальше — за рекламу
    [3, "LLLF", 0, 3, False, 0, 3, 0, True, True, False, 1],       # revive_free_on_fail = 0
    [1, "L", 0, 3, True, 0, 1, 0, True, True, False, 2],          # сам Hearts: 3 − 1; в игре без возрождения не выиграть
    [5, "LL", 0, 3, True, 3, 2, 0, False, False, False, 1],        # флаг hearts = 5: звёзды всё равно 3 − ошибки
    [0, "", 0, 3, True, 0, 0, 0, False, False, False, 3],          # без предела: сердец не видно
    [0, "L", 0, 3, True, 0, 1, 0, False, False, False, 2],         # ошибки считаются
    [0, "LLLL", 0, 3, True, 0, 4, 0, False, False, False, 1],      # и не кончаются
    [0, "LLLR", 0, 3, True, 0, 3, 0, False, False, False, 1],
    [-2, "", 0, 3, True, 0, 0, 0, False, False, False, 3],
]


def run_case(c):
    n, ops, hints, rmax, allow = c[:5]
    h = Hearts()
    h.reset(n)
    apply_ops(h, ops, rmax, allow)
    return [h.left, h.mistakes, h.revives, h.is_out(), h.can_revive(rmax), h.free_used, h.stars(hints)]


def check_rules():
    errs = []
    for c in MAX_FOR_CASES:
        got = Hearts.max_for(*c[:5])
        if got != c[5]:
            errs.append("max_for%s = %d, ждали %d" % (tuple(c[:5]), got, c[5]))
    for c in CASES:
        got = run_case(c)
        if got != c[5:]:
            errs.append("случай %s: %s, ждали %s" % (c[:5], got, c[5:]))
    # Свойство, не только таблица: при трёх сердцах без подсказок и возрождений звёзды = оставшиеся сердца
    # (PLAN 20.1: «звёзды = оставшиеся сердца»).
    for k in range(3):
        h = Hearts()
        h.reset(3)
        for _ in range(k):
            h.lose()
        if h.stars(0) != h.left:
            errs.append("3 сердца, ошибок %d: звёзд %d, сердец %d" % (k, h.stars(0), h.left))
    return errs


def gd_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"%s"' % v
    return str(v)


def gd_table():
    """Кусок tests/selftest.gd между метками: таблицы как константы GDScript."""
    out = [BEGIN + " (создано tools/hearts_model.py --write — не правьте вручную)"]
    out.append("## Hearts.max_for: [уровень, задача дня, «Лаборатория», флаг hearts, флаг hearts_from_level, ждём].")
    out.append("const HEARTS_MAX_FOR_CASES := [")
    for c in MAX_FOR_CASES:
        out.append("\t[%s]," % ", ".join(gd_value(v) for v in c))
    out.append("]")
    out.append("## Попытка: [сердец, шаги (L — ошибка, R — возрождение, F — бесплатное), подсказок, revive_max,")
    out.append("## revive_free_on_fail, ждём: осталось, ошибок, возрождений, кончились, можно возродиться,")
    out.append("## бесплатное было, звёзды].")
    out.append("const HEARTS_CASES := [")
    for c in CASES:
        out.append("\t[%s]," % ", ".join(gd_value(v) for v in c))
    out.append("]")
    out.append(END)
    return "\n".join(out)


def sync_selftest(write):
    """Сверяет (или переписывает) таблицу в tests/selftest.gd. -> текст ошибки или ""."""
    src = open(SELFTEST, encoding="utf-8").read()
    a = src.find(BEGIN)
    b = src.find(END, a + 1) if a >= 0 else -1
    if a < 0 or b < 0:
        return "в tests/selftest.gd нет меток «%s» … «%s»" % (BEGIN, END)
    b += len(END)
    want = gd_table()
    if src[a:b] == want:
        return ""
    if not write:
        return "таблица сердец в tests/selftest.gd не та, что здесь: python3 tools/hearts_model.py --write"
    with open(SELFTEST, "w", encoding="utf-8", newline="\n") as f:
        f.write(src[:a] + want + src[b:])
    print("Таблица сердец в tests/selftest.gd переписана")
    return ""


# --- 2. Модель игрока -----------------------------------------------------------------------------------------

class Level:
    """Уровень игры n: места чисел битовыми масками, решение, лоток."""

    def __init__(self, n, d):
        import model as M
        self.n = n
        self.d = d
        cols, rows = d["cols"], d["rows"]
        self.cols, self.rows = cols, rows
        blocked = set()
        for x, y in d["holes"]:
            blocked.add((x, y))
        for x, y, w, h in d["pinned"]:
            blocked |= {(xx, yy) for yy in range(y, y + h) for xx in range(x, x + w)}
        self.blocked_mask = 0
        for x, y in blocked:
            self.blocked_mask |= 1 << (y * cols + x)
        self.numbers = [(tuple(p), v) for p, v in d["numbers"] if tuple(p) not in blocked]
        allnum = {tuple(p) for p, _ in d["numbers"]}
        shapes = {M.key(p) for p in d["pieces"]}
        self.solution = {tuple(r) for r in d["solution"]}
        # Все места каждого числа: (маска, ключ формы, rect). Число «?» — любые формы набора.
        self.cand = []
        for p, v in self.numbers:
            dims = set()
            if v == M.ANY:
                for a, b in shapes:
                    dims |= {(a, b), (b, a)}
            else:
                dims = {(w, v // w) for w in range(1, v + 1) if v % w == 0}
            lst = []
            for w, h in sorted(dims):
                if w > cols or h > rows:
                    continue
                for y0 in range(max(0, p[1] - h + 1), min(p[1], rows - h) + 1):
                    for x0 in range(max(0, p[0] - w + 1), min(p[0], cols - w) + 1):
                        cells = [(xx, yy) for yy in range(y0, y0 + h) for xx in range(x0, x0 + w)]
                        if any(c in allnum and c != p for c in cells):
                            continue
                        if any(c in blocked for c in cells):
                            continue
                        if not M.tint_ok(x0, y0, w, h, d["tints"]):
                            continue
                        r = (x0, y0, w, h)
                        lst.append((M.rect_mask(cols, r), M.key((w, h)), r))
            self.cand.append(lst)
        self.unknown = [v == M.ANY for _, v in self.numbers]
        self.pieces = [M.key(p) for p in d["pieces"]]
        self.pz = _Pz(self)
        self.memo = {}

    def free_cand(self, occ, k, shapes_left):
        """Места числа k, свободные при занятых клетках occ; у «?» — только формы из shapes_left."""
        out = []
        for m, key, r in self.cand[k]:
            if m & occ:
                continue
            if self.unknown[k] and key not in shapes_left:
                continue
            out.append((m, key, r))
        return out


class Attempt:
    """Попытка уровня: поле (поставленные блоки решения), лоток из трёх гнёзд, очередь."""

    def __init__(self, lv):
        self.lv = lv
        self.occ = lv.blocked_mask
        self.slots = list(lv.pieces[:3]) + [None] * max(0, 3 - len(lv.pieces))
        self.queue = list(lv.pieces[3:])
        self.done = [False] * len(lv.numbers)
        self.placed = []

    def finished(self):
        return all(self.done)

    def shapes_left(self):
        return {s for s in self.slots if s is not None} | set(self.queue)

    def legal(self):
        """Допустимые ходы сейчас: [(k числа, rect, маска, ключ формы)] — блок лотка, место по правилам."""
        tray = {s for s in self.slots if s is not None}
        out = []
        for k, ok in enumerate(self.done):
            if ok:
                continue
            for m, key, r in self.lv.cand[k]:
                if key in tray and not (m & self.occ):
                    out.append((k, r, m, key))
        return out

    def place(self, k, r, m, key):
        i = self.slots.index(key)
        self.slots[i] = self.queue.pop(0) if self.queue else None
        self.occ |= m
        self.done[k] = True
        self.placed.append(r)


PLAYERS = {"guess": 0, "simple": 2, "logic": 4}


class _Pz:
    """Уровень как головоломка для level_design._State: места чисел (с механиками: препятствия, закреплённый блок,
    цветные клетки, «?» — уже учтены в Level.cand)."""

    def __init__(self, lv):
        self.numbers = lv.numbers
        self.full = (1 << (lv.cols * lv.rows)) - 1
        self.masks, self.owner, self.rects, self.keys = [], [], [], []
        self.by_num = [[] for _ in lv.numbers]
        self.by_cell = [[] for _ in range(lv.cols * lv.rows)]
        self.index = {}
        for i, lst in enumerate(lv.cand):
            for m, key, r in lst:
                ci = len(self.masks)
                self.masks.append(m)
                self.owner.append(i)
                self.rects.append(r)
                self.keys.append(key)
                self.by_num[i].append(ci)
                self.index[r] = ci
                mm = m
                while mm:
                    bit = mm & -mm
                    self.by_cell[bit.bit_length() - 1].append(ci)
                    mm ^= bit


def deduce(lv, at, tried, max_rule):
    """Что игрок выводит в уме правилами 1..max_rule от поля at, зная свои неверные ходы tried.
    -> (выведенные места {rect}, живые места {rect}). Кэш по позиции — позиции у попыток повторяются."""
    import level_design as LD
    key = (frozenset(at.placed), frozenset(tried), max_rule)
    hit = lv.memo.get(key)
    if hit is not None:
        return hit
    pz = lv.pz
    st = LD._State(pz, occ=lv.blocked_mask)
    for r in at.placed:
        st.commit(pz.index[r])
    st.alive.difference_update(pz.index[r] for r in tried if r in pz.index)
    rules = [r for r in (1, 2, 3, 4) if r <= max_rule]
    for _ in range(4 * len(pz.numbers) + 8):
        if st.done() or st.contradiction():
            break
        if not any(st.apply(rule) for rule in rules):
            break
    placed = set(at.placed)
    known = {pz.rects[ci] for ci in st.alive if pz.owner[ci] in st.assigned} - placed
    alive = {pz.rects[ci] for ci in st.alive}
    lv.memo[key] = (known, alive)
    return known, alive


def play(lv, player, rnd, hearts=DEFAULT_HEARTS):
    """Одна попытка. -> (ошибок, сердца кончились хоть раз, звёзды без подсказок)."""
    h = Hearts()
    h.reset(Hearts.max_for(lv.n, False, False, hearts, DEFAULT_HEARTS_FROM_LEVEL))
    at = Attempt(lv)
    tried = set()
    out_once = False
    max_rule = PLAYERS[player]
    guard = 0
    while not at.finished():
        guard += 1
        if guard > 10000:
            raise RuntimeError("L%d: модель зациклилась" % lv.n)
        legal = [mv for mv in at.legal() if mv[1] not in tried]
        moves = legal
        if max_rule > 0:
            known, alive = deduce(lv, at, tried, max_rule)
            sure = [mv for mv in legal if mv[1] in known]
            if sure:
                moves = sure
            else:
                live = [mv for mv in legal if mv[1] in alive] or legal
                # догадка — у числа с наименьшим числом живых мест
                size = {}
                for rr in alive:
                    k = lv.pz.owner[lv.pz.index[rr]]
                    size[k] = size.get(k, 0) + 1
                best = min(size.get(mv[0], 0) for mv in live)
                moves = [mv for mv in live if size.get(mv[0], 0) == best]
        if not moves:
            raise RuntimeError("L%d: нет допустимого хода, поле %s" % (lv.n, at.placed))
        k, r, m, key = rnd.choice(moves)
        if r in lv.solution:
            at.place(k, r, m, key)
        else:
            tried.add(r)
            h.lose()
            if h.is_out():
                out_once = True
                # окно 20.1b: возрождение за рекламу (возрождения кончились — модель доигрывает с тем же счётом)
                if not revive_gated(h, False, DEFAULT_REVIVE_MAX, DEFAULT_REVIVE_FREE_ON_FAIL):
                    h.left = 1
                    h.revives += 1
    return h.mistakes, out_once, h.stars(0)


def first_move_dead_share(lv):
    at = Attempt(lv)
    legal = at.legal()
    return sum(1 for mv in legal if mv[1] not in lv.solution), len(legal)


def load_levels(lo, hi):
    import make_levels as ML
    pack = ML.read_pack()
    return [Level(n, ML.pack_level(n, pack)) for n in range(lo, hi + 1)]


def run_play(levels, runs, seed):
    rows = {}
    t0 = time.time()
    for lv in levels:
        if lv.n <= GUARD_LEVELS:
            continue
        rnd = random.Random(seed * 100003 + lv.n)
        dead, legal = first_move_dead_share(lv)
        res = {"dead": dead, "legal": legal}
        for player in PLAYERS:
            mist = outs = stars = with_mist = 0
            for _ in range(runs):
                m, o, s = play(lv, player, rnd)
                mist += m
                outs += o
                stars += s
                with_mist += m > 0
            res[player] = (mist / runs, with_mist / runs, outs / runs, stars / runs)
        rows[lv.n] = res
    return rows, time.time() - t0


def summary(rows, runs, elapsed):
    lines = []
    lines.append("Сердца: модель игроков (tools/hearts_model.py --play). Уровни игры, 3 сердца, без подсказок,")
    lines.append("попыток на уровень: %d у каждого игрока (%.0f с)." % (runs, elapsed))
    lines.append("guess — случайный допустимый ход (неверный на той же позиции не повторяет); logic — вынужденные")
    lines.append("ходы (одно место у числа, клетка одного места), иначе угадывает у числа с наименьшим числом мест.")
    lines.append("Ошибка — допустимый ход вне решения (решение одно → решатель: UNSOLVABLE). Уровни 1–3 — страховка.")
    lines.append("")
    lines.append("Колонки: тупиковых среди допустимых первых ходов | по игроку: ошибок за попытку / доля попыток")
    lines.append("с ошибкой / доля, где сердца кончились (нужно возрождение или «Заново») / средние звёзды.")
    lines.append("")
    lines.append("  участок     тупик 1-го |  guess: ошиб  с ош.  кончились  звёзды |  logic: ошиб  с ош.  кончились  звёзды")

    def fmt(ns, label):
        ns = [n for n in ns if n in rows]
        if not ns:
            return None
        dead = sum(rows[n]["dead"] for n in ns) / max(1, sum(rows[n]["legal"] for n in ns))
        cols = []
        for p in ("guess", "logic"):
            vals = [rows[n][p] for n in ns]
            avg = [sum(v[i] for v in vals) / len(vals) for i in range(4)]
            cols.append("%11.2f  %4.0f%%  %8.0f%%  %6.2f" % (avg[0], 100 * avg[1], 100 * avg[2], avg[3]))
        return "  %-10s  %9.0f%% | %s | %s" % (label, 100 * dead, cols[0], cols[1])

    for lo, hi in RANGES:
        s = fmt(range(lo, hi + 1), "%d–%d" % (lo, hi))
        if s:
            lines.append(s)
    s = fmt(sorted(rows), "все")
    if s:
        lines.append(s)
    # Самые «дорогие» для думающего игрока уровни — где сердца кончаются чаще (PLAN 20.1, риск: пробы после 100-го).
    top = sorted(rows, key=lambda n: (-rows[n]["logic"][2], -rows[n]["logic"][0]))[:15]
    top = [n for n in top if rows[n]["logic"][2] > 0]
    lines.append("")
    if top:
        lines.append("У logic чаще всего кончаются сердца (уровень: доля попыток, ошибок за попытку):")
        lines.append("  " + ", ".join("%d: %.0f%% / %.1f" % (n, 100 * rows[n]["logic"][2], rows[n]["logic"][0])
                                       for n in top))
    else:
        lines.append("У logic сердца не кончаются ни на одном уровне.")
    return "\n".join(lines)


def run_verify(levels, rnd, positions=3):
    """Каждый допустимый ход на positions случайных позициях уровня: вне решения — UNSOLVABLE, в решении — SOLVED."""
    import model as M
    import make_lab as LABF
    errs = []
    checked = 0
    for lv in levels:
        if lv.n <= GUARD_LEVELS:
            continue
        d = lv.d
        blocked = LABF.blocked_of(d)
        for _ in range(positions):
            at = Attempt(lv)
            for _s in range(rnd.randint(0, max(0, len(lv.pieces) - 1))):
                legal = [mv for mv in at.legal() if mv[1] in lv.solution]
                if not legal:
                    break
                at.place(*rnd.choice(legal))
            pieces_left = [s for s in at.slots if s is not None] + list(at.queue)
            for k, r, m, key in at.legal():
                rest = list(pieces_left)
                rest.remove(key)
                st, _, _ = M.solve(d["cols"], d["rows"], d["numbers"], at.placed + [r], rest, LABF.STEP_LIMIT,
                                   blocked, d["tints"])
                checked += 1
                want = M.SOLVED if r in lv.solution else M.UNSOLVABLE
                if st != want:
                    errs.append("L%d: ход %s после %s — решатель %d, ждали %d" % (lv.n, r, at.placed, st, want))
    return errs, checked


def parse_levels(s):
    a, _, b = s.partition("-")
    lo = int(a)
    hi = int(b) if b else lo
    return max(1, lo), min(GAME_LEVELS, hi)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--write", action="store_true", help="переписать таблицу сердец в tests/selftest.gd")
    ap.add_argument("--play", action="store_true", help="модель игроков")
    ap.add_argument("--verify", action="store_true", help="сверить «ошибка = ход вне решения» с решателем")
    ap.add_argument("--levels", default="4-1000", help="уровни, например 4-200")
    ap.add_argument("--runs", type=int, default=60, help="попыток на уровень у каждого игрока")
    ap.add_argument("--seed", type=int, default=20)
    ap.add_argument("--report", action="store_true", help="записать итог --play в tools/hearts_report.txt")
    args = ap.parse_args()

    errs = check_rules()
    for e in errs:
        print("ПРАВИЛА:", e)
    print("Правила сердец: %d + %d случаев, расхождений %d" % (len(MAX_FOR_CASES), len(CASES), len(errs)))
    msg = sync_selftest(args.write)
    if msg:
        print("SELFTEST:", msg)
        errs.append(msg)
    else:
        print("Таблица в tests/selftest.gd совпадает")

    if args.verify or args.play:
        lo, hi = parse_levels(args.levels)
        levels = load_levels(lo, hi)
    if args.verify:
        verrs, checked = run_verify(levels, random.Random(args.seed))
        for e in verrs[:20]:
            print("VERIFY:", e)
        print("Сверка с решателем: ходов %d, расхождений %d" % (checked, len(verrs)))
        errs += verrs
    if args.play:
        rows, elapsed = run_play(levels, args.runs, args.seed)
        text = summary(rows, args.runs, elapsed)
        print()
        print(text)
        if args.report:
            with open(REPORT, "w", encoding="utf-8", newline="\n") as f:
                f.write(text + "\n")
            print("\nЗаписано:", REPORT)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
