#!/usr/bin/env python3
"""19.3a: уровни «Лаборатории» — tools/mechanics_levels.json (модель 19.1) -> scripts/lab_levels_data.gd.

Формат строки уровня (scripts/level_pack.gd) с механиками — четвёртая часть после ':':
  hXY    — препятствие в клетке (X, Y);
  pXYWH  — закреплённый блок (без числа, в решение RECTS не входит);
  qXY    — число в клетке (X, Y) — «?» (площадь не показана);
  tXYA   — цветная клетка (X, Y): её накрывает только блок площади A.
Пример: "66:<RECTS>:<PIECES>:h12h45" — две клетки-препятствия.

Проверки (код выхода 0 — всё хорошо):
  * строка читается Python-копией LevelPack.decode и даёт то же, что модель 19.1;
  * решатель игры (Python-копия tools/model.py: solve с blocked / tints / ANY) с пустого поля решает уровень,
    и решение — ровно решение модели; решений по правилам игры (с набором блоков) — одно;
  * случайная игра: на каждом шаге решатель отвечает, найденное решение проверяется правилами механики.
Запуск из корня проекта:  python3 tools/make_lab.py
"""
import json
import os
import random
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import model as M  # noqa: E402

SRC = os.path.join(ROOT, "tools", "mechanics_levels.json")
OUT = os.path.join(ROOT, "scripts", "lab_levels_data.gd")
ORDER = ["unknown", "holes", "tints", "pinned"]  # как в выборе 19.2: сначала рекомендованные
STEP_LIMIT = 4000
problems = []


def bad(msg):
    problems.append(msg)
    print("  [!] " + msg)


# --- Кодирование ------------------------------------------------------------------------------------------
def encode(lv):
    cols, rows = lv["cols"], lv["rows"]
    pin = tuple(lv["pinned"]) if lv["pinned"] else None
    pin_cells = set()
    if pin:
        x, y, w, h = pin
        pin_cells = {(xx, yy) for yy in range(y, y + h) for xx in range(x, x + w)}
    nums = {(x, y): v for x, y, v in lv["numbers"]}
    rects = ""
    for r in lv["solution"]:
        r = tuple(r)
        if r == pin:
            continue
        x, y, w, h = r
        inside = [p for p in nums if x <= p[0] < x + w and y <= p[1] < y + h]
        assert len(inside) == 1, (lv["mechanic"], r, inside)
        p = inside[0]
        rects += "%d%d%d%d%d%d" % (x, y, w, h, p[0], p[1])
    pieces = "".join("%d%d" % (w, h) for w, h in lv["pieces"])
    mods = ""
    for (x, y) in sorted(map(tuple, lv["holes"]), key=lambda c: (c[1], c[0])):
        if (x, y) not in pin_cells:
            mods += "h%d%d" % (x, y)
    if pin:
        mods += "p%d%d%d%d" % pin
    for (x, y), v in sorted(nums.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        if v is None:
            mods += "q%d%d" % (x, y)
    for x, y, a in sorted(lv["tints"], key=lambda t: (t[1], t[0])):
        mods += "t%d%d%d" % (x, y, a)
    s = "%d%d:%s:%s" % (cols, rows, rects, pieces)
    return s + (":" + mods if mods else "")


# --- Python-копия LevelPack.decode -----------------------------------------------------------------------
MOD_LEN = {"h": 3, "p": 5, "q": 3, "t": 4}


def decode(s):
    parts = s.split(":")
    if len(parts) not in (3, 4) or len(parts[0]) != 2:
        return None
    rs, ps = parts[1], parts[2]
    mods = parts[3] if len(parts) == 4 else ""
    if not rs or len(rs) % 6 or len(ps) * 3 != len(rs):
        return None
    if not (parts[0].isdigit() and rs.isdigit() and ps.isdigit()):
        return None
    cols, rows = int(parts[0][0]), int(parts[0][1])
    if cols < 2 or rows < 2:
        return None
    used = [0] * (cols * rows)

    def take(x, y, w, h):
        if w < 1 or h < 1 or x + w > cols or y + h > rows:
            return False
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if used[yy * cols + xx]:
                    return False
                used[yy * cols + xx] = 1
        return True

    solution, numbers = [], []
    for i in range(0, len(rs), 6):
        x, y, w, h, px, py = (int(c) for c in rs[i:i + 6])
        if not (x <= px < x + w and y <= py < y + h) or not take(x, y, w, h):
            return None
        solution.append((x, y, w, h))
        numbers.append([(px, py), w * h])
    pieces = [(int(ps[i]), int(ps[i + 1])) for i in range(0, len(ps), 2)]
    holes, pinned, tints = [], [], {}
    i = 0
    while i < len(mods):
        tag = mods[i]
        n = MOD_LEN.get(tag, 0)
        if n == 0 or i + n > len(mods) or not mods[i + 1:i + n].isdigit():
            return None
        d = [int(c) for c in mods[i + 1:i + n]]
        if tag == "h":
            if not take(d[0], d[1], 1, 1):
                return None
            holes.append((d[0], d[1]))
        elif tag == "p":
            if not take(*d):
                return None
            pinned.append(tuple(d))
        elif tag == "q":
            hit = [k for k, nm in enumerate(numbers) if nm[0] == (d[0], d[1])]
            if not hit:
                return None
            numbers[hit[0]][1] = M.ANY
        else:
            if not (d[0] < cols and d[1] < rows and d[2] > 0) or any(nm[0] == (d[0], d[1]) for nm in numbers):
                return None
            tints[(d[0], d[1])] = d[2]
        i += n
    if sum(used) != cols * rows:
        return None
    return {"cols": cols, "rows": rows, "solution": solution, "numbers": [tuple(nm) for nm in numbers],
            "pieces": pieces, "holes": holes, "pinned": pinned, "tints": tints}


def blocked_of(d):
    out = list(d["holes"])
    for x, y, w, h in d["pinned"]:
        out += [(xx, yy) for yy in range(y, y + h) for xx in range(x, x + w)]
    return out


# --- Правила механики (проверка решения) -------------------------------------------------------------------
def check_rules(d, rects):
    cols, rows = d["cols"], d["rows"]
    cover = {}
    for r in rects:
        x, y, w, h = r
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if (xx, yy) in cover:
                    return "наложение"
                cover[(xx, yy)] = r
    for c in blocked_of(d):
        if c in cover:
            return "блок на препятствии"
    if len(cover) + len(blocked_of(d)) != cols * rows:
        return "поле не заполнено"
    for r in rects:
        x, y, w, h = r
        inside = [(p, v) for p, v in d["numbers"] if x <= p[0] < x + w and y <= p[1] < y + h]
        if len(inside) != 1 or inside[0][1] not in (w * h, M.ANY):
            return "правило числа: %s" % (r,)
    for c, a in d["tints"].items():
        r = cover.get(c)
        if r is None or r[2] * r[3] != a:
            return "цвет %s" % (c,)
    if Counter(M.key(r[2:]) for r in rects) != Counter(M.key(p) for p in d["pieces"]):
        return "набор блоков"
    return ""


def count_solutions(d, limit=2):
    """Все решения по правилам игры (с набором блоков) до limit — перебор с MRV, без лимита шагов."""
    cols, rows = d["cols"], d["rows"]
    occ0 = 0
    for (x, y) in blocked_of(d):
        occ0 |= 1 << (y * cols + x)
    kidx, left = {}, {}
    for p in d["pieces"]:
        k = M.key(p)
        if k not in kidx:
            kidx[k] = len(kidx)
            left[kidx[k]] = 0
        left[kidx[k]] += 1
    allnum = {p for p, _ in d["numbers"]}
    cand = []
    for p, v in d["numbers"]:
        lst = []
        for (w, h) in M.shapes_for(v, kidx):
            k = M.key((w, h))
            if k not in kidx or w > cols or h > rows:
                continue
            for y0 in range(max(0, p[1] - h + 1), min(p[1], rows - h) + 1):
                for x0 in range(max(0, p[0] - w + 1), min(p[0], cols - w) + 1):
                    if any((xx, yy) in allnum and (xx, yy) != p for yy in range(y0, y0 + h) for xx in range(x0, x0 + w)):
                        continue
                    if not M.tint_ok(x0, y0, w, h, d["tints"]):
                        continue
                    lst.append((M.rect_mask(cols, (x0, y0, w, h)), kidx[k]))
        cand.append(lst)
    found = [0]
    st = {"occ": occ0}

    def rec(todo):
        if found[0] >= limit:
            return
        if not todo:
            found[0] += 1
            return
        best, bc = -1, 0
        for t, i in enumerate(todo):
            c = sum(1 for m, k in cand[i] if not m & st["occ"] and left[k] > 0)
            if c == 0:
                return
            if best < 0 or c < bc:
                best, bc = t, c
        i = todo[best]
        rest = todo[:best] + todo[best + 1:]
        for m, k in cand[i]:
            if m & st["occ"] or left[k] <= 0:
                continue
            left[k] -= 1
            st["occ"] |= m
            rec(rest)
            st["occ"] &= ~m
            left[k] += 1

    rec(list(range(len(cand))))
    return found[0]


def random_play(d, rnd):
    """Случайные допустимые по правилам ходы; на каждом шаге — решатель и проверка его решения."""
    cols, rows = d["cols"], d["rows"]
    placed, pieces = [], list(d["pieces"])
    blocked = set(blocked_of(d))
    val = dict(d["numbers"])
    worst = 0
    while pieces:
        st, sol, steps = M.solve(cols, rows, d["numbers"], placed, pieces, STEP_LIMIT, blocked, d["tints"])
        worst = max(worst, steps)
        if st == M.UNKNOWN:
            return "лимит шагов", worst
        if st == M.SOLVED:
            msg = check_rules(d, placed + sol)
            if msg:
                return "решение решателя нарушает правила: " + msg, worst
        occ = set(blocked)
        for (x, y, w, h) in placed:
            occ |= {(xx, yy) for yy in range(y, y + h) for xx in range(x, x + w)}
        moves = []
        for pi, (w0, h0) in enumerate(pieces):
            for (w, h) in {(w0, h0), (h0, w0)}:
                for y in range(rows - h + 1):
                    for x in range(cols - w + 1):
                        cs = [(xx, yy) for yy in range(y, y + h) for xx in range(x, x + w)]
                        if any(c in occ for c in cs):
                            continue
                        ns = [val[c] for c in cs if c in val]
                        if len(ns) == 1 and ns[0] in (w * h, M.ANY) and M.tint_ok(x, y, w, h, d["tints"]):
                            moves.append((pi, (x, y, w, h)))
        if not moves:
            break
        pi, r = rnd.choice(moves)
        placed.append(r)
        pieces.pop(pi)
    return "", worst


def main():
    data = json.load(open(SRC, encoding="utf-8"))
    rnd = random.Random(193)
    out = {}
    print("Лаборатория 19.3: %s" % ", ".join("%s ×%d" % (m, len(data["levels"][m])) for m in ORDER))
    for mech in ORDER:
        strings = []
        steps_max = 0
        for i, lv in enumerate(data["levels"][mech]):
            tag = "%s %d" % (mech, i + 1)
            s = encode(lv)
            d = decode(s)
            if d is None:
                bad("%s: строка не читается: %s" % (tag, s))
                continue
            # То же, что в модели: размер, числа, препятствия, цвета, блоки.
            want_nums = sorted(((x, y), M.ANY if v is None else v) for x, y, v in lv["numbers"])
            if sorted(d["numbers"]) != want_nums or d["pieces"] != [tuple(p) for p in lv["pieces"]]:
                bad("%s: числа или блоки после чтения не те" % tag)
            if sorted(blocked_of(d)) != sorted(map(tuple, lv["holes"])):
                bad("%s: занятые клетки не те" % tag)
            if d["tints"] != {(x, y): a for x, y, a in lv["tints"]}:
                bad("%s: цвета не те" % tag)
            msg = check_rules(d, d["solution"])
            if msg:
                bad("%s: эталонное решение: %s" % (tag, msg))
            st, sol, steps = M.solve(d["cols"], d["rows"], d["numbers"], [], d["pieces"], STEP_LIMIT,
                                     blocked_of(d), d["tints"])
            steps_max = max(steps_max, steps)
            if st != M.SOLVED or sorted(sol) != sorted(d["solution"]):
                bad("%s: решатель игры: %s за %d шагов" % (tag, st, steps))
            n = count_solutions(d)
            if n != 1:
                bad("%s: решений по правилам игры %d" % (tag, n))
            for _ in range(6):
                msg, worst = random_play(d, rnd)
                steps_max = max(steps_max, worst)
                if msg:
                    bad("%s: случайная игра: %s" % (tag, msg))
                    break
            strings.append(s)
        out[mech] = strings
        print("  %-8s %d уровней, решатель — до %d шагов" % (mech, len(strings), steps_max))
    lines = [
        "extends RefCounted",
        "## Уровни «Лаборатории» (этап 19.3). Файл создаёт tools/make_lab.py из tools/mechanics_levels.json (модель",
        "## 19.1) — не правьте вручную. Формат строки и механики — scripts/level_pack.gd (decode), чтение — LabLevels.",
        "",
        "const ORDER: Array[String] = [%s]" % ", ".join('"%s"' % m for m in ORDER),
        "const LEVELS := {",
    ]
    for mech in ORDER:
        lines.append('\t"%s": [' % mech)
        for s in out[mech]:
            lines.append('\t\t"%s",' % s)
        lines.append("\t],")
    lines.append("}")
    text = "\n".join(lines) + "\n"
    old = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
    if old != text:
        open(OUT, "w", encoding="utf-8").write(text)
        print("записан " + os.path.relpath(OUT, ROOT))
    else:
        print(os.path.relpath(OUT, ROOT) + " без изменений")
    print("проблем: %d" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
