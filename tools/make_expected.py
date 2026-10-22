#!/usr/bin/env python3
"""Эталон для самопроверки: tests/expected_levels.txt.

Строки L — уровни игры 1..GAME_LEVELS (заготовки из scripts/level_pack_data.gd
и отражённые повторы после них, tools/make_levels.py: pack_level): md5
канонической записи уровня (размер, решение, числа, блоки). Для уровней
1..SOLVER_LEVELS — ещё статусы решателя для всех «первых ходов»
(0 — решается, 1 — тупик, 2 — не уложился в лимит).
Строки G — запасной процедурный генератор 1..PROC_LEVELS (tools/model.py).

tests/selftest.gd считает то же самое в Godot и сравнивает построчно. Так
видно, что GDScript и Python-копия совпадают, а значит проверки алгоритмов
на Python относятся к настоящим уровням игры.

Поменял уровни, генератор или решатель — перезапусти:
    python3 tools/make_expected.py
"""
import hashlib
import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_levels as ML  # noqa: E402
import model as M  # noqa: E402

GAME_LEVELS = 1000
PROC_LEVELS = 300
SOLVER_LEVELS = 60
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "expected_levels.txt")


def canonical(d):
    """Та же строка, что строит tests/selftest.gd (_canonical). Число «?» — значение -1 (model.ANY); у уровня
    с механикой (19.5e) в конце ещё "|M:" — препятствия hX,Y, закреплённые блоки pX,Y,W,H, цвет tX,Y,A."""
    sol = ";".join("%d,%d,%d,%d" % r for r in d["solution"])
    nums = ";".join("%d,%d,%d" % (p[0], p[1], v) for p, v in d["numbers"])
    pcs = ";".join("%d,%d" % p for p in d["pieces"])
    out = "%dx%d|S:%s|N:%s|P:%s" % (d["cols"], d["rows"], sol, nums, pcs)
    mods = (["h%d,%d" % c for c in d.get("holes", [])] + ["p%d,%d,%d,%d" % r for r in d.get("pinned", [])]
            + ["t%d,%d,%d" % (c[0], c[1], a) for c, a in d.get("tints", {}).items()])
    return out + ("|M:" + ";".join(mods) if mods else "")


def first_move_candidates(d):
    """Все прямоугольники для каждого числа (в порядке selftest.gd/_first_moves)."""
    cols, rows = d["cols"], d["rows"]
    all_num = {p for p, _ in d["numbers"]}
    shapes = Counter(M.key(p) for p in d["pieces"])
    out = []
    for p, v in d["numbers"]:
        for w in range(1, v + 1):
            if v % w:
                continue
            h = v // w
            if w > cols or h > rows or shapes[M.key((w, h))] == 0:
                continue
            for y0 in range(max(0, p[1] - h + 1), min(p[1], rows - h) + 1):
                for x0 in range(max(0, p[0] - w + 1), min(p[0], cols - w) + 1):
                    foreign = any((xx, yy) in all_num and (xx, yy) != p
                                  for yy in range(y0, y0 + h) for xx in range(x0, x0 + w))
                    if not foreign:
                        out.append((x0, y0, w, h))
    return out


def solver_statuses(d):
    res = []
    for r in first_move_candidates(d):
        pieces = list(d["pieces"])
        k = M.key(r[2:])
        for i, pc in enumerate(pieces):
            if M.key(pc) == k:
                del pieces[i]
                break
        st, _, _ = M.solve(d["cols"], d["rows"], d["numbers"], [r], pieces)
        res.append(str(st))
    return "".join(res)


def md5(d):
    return hashlib.md5(canonical(d).encode("ascii")).hexdigest()[:12]


def main():
    levels = ML.read_pack()
    lines = [
        "# Эталон для tests/selftest.gd. Создан tools/make_expected.py — не правьте вручную.",
        "# pack_version=%d pack_count=%d generator_version=%d" % (ML.PACK_VERSION, len(levels), M.GENERATOR_VERSION),
        "# L уровень md5[:12] статусы_первых_ходов(0=решается,1=тупик,2=лимит | -) — уровни игры",
        "# G уровень md5[:12] — запасной процедурный генератор",
    ]
    dead = total = 0
    for level in range(1, GAME_LEVELS + 1):
        d = ML.pack_level(level, levels)
        st = solver_statuses(d) if level <= SOLVER_LEVELS else "-"
        if st != "-":
            dead += st.count("1")
            total += len(st)
        lines.append("L %d %s %s" % (level, md5(d), st))
    for level in range(1, PROC_LEVELS + 1):
        lines.append("G %d %s" % (level, md5(M.generate(level))))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("Записано:", OUT)
    print("Первых ходов проверено: %d, тупиковых: %d (%.0f%%)" % (total, dead, 100.0 * dead / max(1, total)))


if __name__ == "__main__":
    main()
