#!/usr/bin/env python3
"""Симуляция обучения на уровнях 1..3 (этап 11) — без Godot.

Повторяет логику игры: лоток из 3 блоков с очередью (Tray), ход руки
(TutorialCoach.next_move: решение от текущей расстановки, Tray.find_move
с upright_first) и страховку уровней 1..3 (DragController: тупиковое место
не принимает). Проверяет:
  1. «Делаю только то, что показала рука» — уровень проходится; на уровне 1
     рука не просит поворотов, на уровне 2 первым же ходом показывает поворот
     (навык ROTATE: подпись и рука говорят об одном), число ходов.
  2. «Тыкаю куда попало, но по правилам» — со страховкой игрок не может
     застрять: любой допустимый не тупиковый ход ведёт к победе (N случайных
     прохождений на уровень). Заодно — какие причины отказа видит игрок.
  3. Навык DRAG засчитывается (2 своих хода) раньше конца уровня 1 —
     последний блок игрок ставит без руки.
Запуск из корня проекта:  python3 tools/sim_tutorial.py [--runs N]
Код выхода 0 — всё в порядке.
"""
import argparse
import pathlib
import random
import sys
from collections import Counter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import model as M  # noqa: E402
import tutorial_levels as TL  # noqa: E402

DRAG_OWN_MOVES = 2  # Tutorial.DRAG_OWN_MOVES


class Game:
    """Уровень как в игре: поле, лоток (3 слота) и очередь блоков."""

    def __init__(self, n):
        lv = TL.LEVELS[n]
        self.n, self.lv = n, lv
        self.cols, self.rows = lv["cols"], lv["rows"]
        self.nums = TL.numbers_of(lv)
        self.board = TL.Board(self.cols, self.rows, self.nums)
        pieces = [tuple(p) for p in lv["pieces"]]
        self.tray = pieces[:TL.TRAY] + [None] * (TL.TRAY - len(pieces[:TL.TRAY]))
        self.queue = pieces[TL.TRAY:]
        self.placed = []

    def remaining(self):
        return [b for b in self.tray if b is not None] + self.queue

    def finished(self):
        return not self.remaining()

    def solve(self):
        return M.solve(self.cols, self.rows, self.nums, self.placed, self.remaining())

    def leads_to_dead_end(self, slot, r):
        rest = self.remaining()
        rest.remove(self.tray[slot])
        st = M.solve(self.cols, self.rows, self.nums, self.placed + [r], rest)[0]
        return st == M.UNSOLVABLE

    def place(self, slot, r):
        assert self.board.check(r), (slot, r)
        self.board.place(r)
        self.placed.append(r)
        self.tray[slot] = self.queue.pop(0) if self.queue else None

    def find_move(self, rects, upright_first=True):
        """Tray.find_move: первый блок лотка, которому есть место в решении."""
        for pass_no in range(2 if upright_first else 1):
            allow_rot = not upright_first or pass_no == 1
            for i, b in enumerate(self.tray):
                if b is None:
                    continue
                for r in rects:
                    size = (r[2], r[3])
                    if (size == b or (allow_rot and size == (b[1], b[0]))) and self.board.check(r):
                        return i, r
        return None

    def slot_move(self, i, rects):
        """TutorialCoach._slot_move: место для блока слота i, сначала без поворота."""
        b = self.tray[i]
        if b is None:
            return None
        for d in (b, (b[1], b[0])):
            for r in rects:
                if (r[2], r[3]) == d and self.board.check(r):
                    return i, r
        return None

    def hand_move(self):
        """TutorialCoach.next_move: на уровне 2 (навык ROTATE) — сперва блок,
        который встанет только повёрнутым; иначе — сперва ход без поворота."""
        st, sol, _ = self.solve()
        if st == M.UNSOLVABLE:
            return None
        rects = [tuple(r) for r in (sol if st == M.SOLVED else self.lv["rects"])]
        if self.n == 2:
            for i, b in enumerate(self.tray):
                m = self.slot_move(i, rects)
                if m is not None and (m[1][2], m[1][3]) != b:
                    return m
        return self.find_move(rects)

    def guarded_moves(self):
        """Все ходы, которые примет страховка: [(slot, rect)] и отказы-тупики."""
        ok, dead = [], []
        for i, b in enumerate(self.tray):
            if b is None:
                continue
            for d in {b, (b[1], b[0])}:
                for r in self.board.legal(d):
                    (dead if self.leads_to_dead_end(i, r) else ok).append((i, r))
        return ok, dead


def follow_hand(n):
    g = Game(n)
    moves, turns, first_turn = 0, 0, False
    while not g.finished() and moves < 40:
        m = g.hand_move()
        if m is None:
            return None
        i, r = m
        if (r[2], r[3]) != g.tray[i]:
            turns += 1
            first_turn = first_turn or moves == 0
        g.place(i, r)
        moves += 1
    return moves, turns, g.finished(), first_turn


def random_guarded(n, rng):
    """-> (прошёл?, отказов страховки, причины случайных бросков)"""
    g = Game(n)
    refused = 0
    reasons = Counter()
    while not g.finished():
        # Случайный бросок куда-нибудь на поле — что объяснит подпись.
        b = rng.choice([b for b in g.tray if b is not None])
        w, h = b if rng.random() < 0.5 else (b[1], b[0])
        if w <= g.cols and h <= g.rows:
            r = (rng.randrange(g.cols - w + 1), rng.randrange(g.rows - h + 1), w, h)
            reasons[g.board.reason(r)] += 1
        ok, dead = g.guarded_moves()
        if not ok:
            return False, refused, reasons
        refused += len(dead)
        i, r = rng.choice(ok)
        g.place(i, r)
    return True, refused, reasons


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=300, help="случайных прохождений на уровень")
    ap.add_argument("--seed", type=int, default=11)
    args = ap.parse_args()
    rng = random.Random(args.seed)
    errors = []

    for n in sorted(TL.LEVELS):
        res = follow_hand(n)
        if res is None or not res[2]:
            errors.append(f"L{n}: ходы руки не доводят уровень до конца")
            continue
        moves, turns, _, first_turn = res
        print(f"L{n}: рука — {moves} ходов, с поворотом {turns}, первый ход с поворотом: {'да' if first_turn else 'нет'}")
        if n == 1 and turns:
            errors.append("L1: рука просит повернуть блок")
        if n == 2 and not first_turn:
            errors.append("L2: первый ход руки без поворота — подпись про поворот, а рука про другое")
        if n == 1 and moves <= DRAG_OWN_MOVES:
            errors.append(f"L1: {moves} ходов — навык DRAG засчитывается только к концу уровня")

        wins, refused_total = 0, 0
        reasons = Counter()
        for _ in range(args.runs):
            ok, refused, rs = random_guarded(n, rng)
            wins += ok
            refused_total += refused
            reasons.update(rs)
        print(f"     страховка: {wins}/{args.runs} случайных прохождений дошли до конца, "
              f"тупиковых мест отклонено в среднем {refused_total / args.runs:.1f}")
        total = sum(reasons.values()) or 1
        print("     случайные броски: " + ", ".join(f"{k} {v * 100 // total}%" for k, v in reasons.most_common()))
        if wins != args.runs:
            errors.append(f"L{n}: со страховкой игрок застрял в {args.runs - wins} прохождениях")

    # Урок уровня 3: доминошка на двух двойках — отказ «не одно число».
    g = Game(3)
    twos = [p for p, v in g.nums if v == 2]
    pair = [(x, y, w, h) for (w, h) in ((1, 2), (2, 1))
            for y in range(g.rows - h + 1) for x in range(g.cols - w + 1)
            if sum(1 for c in g.board.cells((x, y, w, h)) if c in twos) == 2]
    if not pair or any(g.board.reason(r) != "count" for r in pair):
        errors.append("L3: нет соседних двоек, на которых видна причина «ровно одно число»")
    else:
        print(f"L3: доминошка на двух двойках {pair} — причина «ровно одно число»")
    # Урок уровня 3 показывает рука (07.10: сразу, как на 1–2): её первый ход — блок из первого гнезда лотка
    # на одну из двух соседних двоек (TutorialCoach: Board.has_twin_next_to).
    g = Game(3)
    i, r = g.hand_move()
    covered = [c for c in g.board.cells(r) if c in twos]
    if i != 0 or len(covered) != 1:
        errors.append(f"L3: первый ход руки — гнездо {i}, место {r}: не блок из первого гнезда на одну из двоек")
    else:
        print(f"L3: первый ход руки — гнездо 0 на {r}: одна из соседних двоек {covered[0]}")

    if errors:
        print("\nОШИБКИ:")
        for e in errors:
            print("  ", e)
        return 1
    print("\nобучение: всё в порядке")
    return 0


if __name__ == "__main__":
    sys.exit(main())
