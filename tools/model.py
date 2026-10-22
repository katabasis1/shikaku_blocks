#!/usr/bin/env python3
"""Python-модель генератора (scripts/level_generator.gd) и решателя
(scripts/shikaku_solver.gd). Логика повторяет GDScript один в один, чтобы
проверять алгоритмы без редактора:  python3 tools/model.py
"""
import random, sys, time
from collections import Counter

MASK = 0xFFFFFFFF
GENERATOR_VERSION = 2
MAX_SIDE = 4; CANDIDATES = 8; MAX_ATTEMPTS = 400

def mul32(a, b):
    lo = (a * (b & 0xFFFF)) & MASK
    hi = ((a * (b >> 16)) & 0xFFFF) << 16
    return (lo + hi) & MASK

def mix32(v):
    h = v & MASK
    h ^= h >> 16; h = mul32(h, 0x85EBCA6B)
    h ^= h >> 13; h = mul32(h, 0xC2B2AE35)
    h ^= h >> 16
    return h

class Rng:
    def __init__(self, seed):
        self.state = seed & MASK or 0x9E3779B9
    def next_u32(self):
        x = self.state
        x ^= (x << 13) & MASK
        x ^= x >> 17
        x ^= (x << 5) & MASK
        self.state = x
        return x
    def randf(self): return self.next_u32() / 4294967296.0
    def randi_range(self, a, b): return a + self.next_u32() % (b - a + 1)

def level_seed(level): return mix32(level * 2654435761 + GENERATOR_VERSION * 97531)

def grid_size(l):
    for lim, s in [(2,(4,4)),(6,(5,5)),(12,(5,6)),(20,(6,6)),(32,(6,7)),(48,(7,7))]:
        if l <= lim: return s
    return (7, 8)
def max_area(l): return 4 if l <= 3 else 6 if l <= 10 else 8 if l <= 25 else 9
W = {2:1.0,3:2.2,4:2.6,5:1.6,6:2.4,8:1.8,9:1.4}
def weight(w, h):
    g = W.get(w*h, 1.0)
    if min(w,h) == 1 and max(w,h) == 4: g *= 0.6
    return g
def weighted_index(ws, rng):
    # Складываем по порядку, как GDScript: sum() в Python 3.12+ для float
    # суммирует с компенсацией погрешности и может разойтись в последнем бите.
    total = 0.0
    for v in ws: total += v
    roll = rng.randf() * total
    for i, v in enumerate(ws):
        roll -= v
        if roll <= 0.0: return i
    return len(ws) - 1
def partition(size, limit, rng):
    cols, rows = size; used = [0]*(cols*rows); rects = []
    for i in range(cols*rows):
        if used[i]: continue
        x = i % cols; y = i // cols; mw = 0
        while x+mw < cols and mw < MAX_SIDE and used[y*cols+x+mw] == 0: mw += 1
        opts = []; ws = []
        for w in range(1, mw+1):
            for h in range(1, MAX_SIDE+1):
                if y+h > rows: break
                if any(used[(y+h-1)*cols+xx] for xx in range(x, x+w)): break
                a = w*h
                if a < 2 or a > limit: continue
                opts.append((w,h)); ws.append(weight(w,h))
        if not opts: return []
        pw, ph = opts[weighted_index(ws, rng)]
        for yy in range(y, y+ph):
            for xx in range(x, x+pw): used[yy*cols+xx] = 1
        rects.append((x, y, pw, ph))
    return rects
def score(rects, rng):
    areas = set(r[2]*r[3] for r in rects); twos = sum(1 for r in rects if r[2]*r[3] == 2)
    return len(areas)*2.0 - twos*0.7 + rng.randf()
def fallback(size):
    rects = []
    for y in range(size[1]):
        x = 0
        while x < size[0]:
            left = size[0]-x; w = 3 if (left == 3 or left > 4) else 2; w = min(w, left)
            rects.append((x, y, w, 1)); x += w
    return rects
def generate(level):
    rng = Rng(level_seed(level)); size = grid_size(level); lim = max_area(level)
    best = []; bs = -1e9; found = 0; used_fallback = False
    for _ in range(MAX_ATTEMPTS):
        r = partition(size, lim, rng)
        if not r: continue
        s = score(r, rng)
        if s > bs: bs = s; best = r
        found += 1
        if found >= CANDIDATES: break
    if not best: best = fallback(size); used_fallback = True
    numbers = [((x+rng.randi_range(0, w-1), y+rng.randi_range(0, h-1)), w*h) for (x,y,w,h) in best]
    pieces = []
    for (x,y,w,h) in best:
        p = (w, h)
        if rng.randf() < 0.5: p = (h, w)
        pieces.append(p)
    for i in range(len(pieces)-1, 0, -1):
        j = rng.randi_range(0, i); pieces[i], pieces[j] = pieces[j], pieces[i]
    return dict(cols=size[0], rows=size[1], solution=best, numbers=numbers, pieces=pieces, fallback=used_fallback)

# ---------------- решатель (как scripts/shikaku_solver.gd) ----------------
SOLVED, UNSOLVABLE, UNKNOWN = 0, 1, 2
ANY = -1  # число «?» (этап 19.3): площадь не показана, подходит блок любой оставшейся формы
def key(d): return (min(d), max(d))
def shapes_for(v, kidx):
    """Размеры (w, h) прямоугольников числа v в порядке перебора shikaku_solver.gd (_shapes_for):
    делители v по возрастанию ширины; у «?» — обе ориентации каждой оставшейся формы в порядке kidx."""
    out = []
    if v == ANY:
        for a, b in kidx:
            out.append((a, b))
            if a != b: out.append((b, a))
        return out
    for w in range(1, v+1):
        if v % w == 0 and key((w, v // w)) in kidx: out.append((w, v // w))
    return out
def tint_ok(x0, y0, w, h, tints):
    """Цветные клетки под прямоугольником: каждую накрывает только блок её площади (tints: {(x, y): площадь})."""
    if not tints: return True
    a = w*h
    for yy in range(y0, y0+h):
        for xx in range(x0, x0+w):
            if tints.get((xx, yy), a) != a: return False
    return True
def rect_mask(cols, r):
    x0, y0, w, h = r; m = 0
    for y in range(y0, y0+h):
        for x in range(x0, x0+w): m |= 1 << (y*cols+x)
    return m
def solve(cols, rows, numbers, placed, pieces, step_limit=4000, blocked=(), tints=None):
    """-> (status, solution_rects, steps). 19.3: blocked — клетки, занятые с начала (препятствия и закреплённый
    блок), tints — {(x, y): площадь}, число со значением ANY — «?»."""
    if cols*rows > 62: return UNKNOWN, [], 0
    occ = 0
    for r in placed: occ |= rect_mask(cols, r)
    for (x, y) in blocked: occ |= 1 << (y*cols+x)
    allnum = {p for p, v in numbers}
    left = {}; kidx = {}
    for d in pieces:
        k = key(d)
        if k not in kidx: kidx[k] = len(kidx); left[kidx[k]] = 0
        left[kidx[k]] += 1
    nums = [(p, v) for p, v in numbers if not (occ >> (p[1]*cols+p[0])) & 1]
    if len(nums) != len(pieces): return UNKNOWN, [], 0
    cand = []  # per number: list of (mask, keyindex, rect)
    for p, v in nums:
        lst = []
        for (w, h) in shapes_for(v, kidx):
            if w > cols or h > rows: continue
            k = key((w, h))
            for y0 in range(max(0, p[1]-h+1), min(p[1], rows-h)+1):
                for x0 in range(max(0, p[0]-w+1), min(p[0], cols-w)+1):
                    r = (x0, y0, w, h)
                    if any((xx, yy) in allnum and (xx, yy) != p for yy in range(y0, y0+h) for xx in range(x0, x0+w)):
                        continue
                    if not tint_ok(x0, y0, w, h, tints): continue
                    lst.append((rect_mask(cols, r), kidx[k], r))
        cand.append(lst)
    st = dict(occ=occ, steps=0, aborted=False)
    out = []
    def search(todo):
        if not todo: return True
        st['steps'] += 1
        if st['steps'] > step_limit: st['aborted'] = True; return False
        best_t = -1; best_cnt = 0
        for t, i in enumerate(todo):
            cnt = 0
            for m, k, r in cand[i]:
                if (m & st['occ']) == 0 and left[k] > 0: cnt += 1
            if cnt == 0: return False
            if best_t < 0 or cnt < best_cnt: best_t = t; best_cnt = cnt
        i = todo[best_t]; rest = todo[:best_t] + todo[best_t+1:]
        for m, k, r in cand[i]:
            if (m & st['occ']) != 0 or left[k] <= 0: continue
            left[k] -= 1; st['occ'] |= m; out.append(r)
            if search(rest): return True
            out.pop(); st['occ'] &= ~m; left[k] += 1
            if st['aborted']: return False
        return False
    ok = search(list(range(len(nums))))
    if st['aborted']: return UNKNOWN, [], st['steps']
    return (SOLVED if ok else UNSOLVABLE), (out if ok else []), st['steps']

# ---------------- эталонный перебор для сверки ----------------
def brute_solvable(cols, rows, numbers, placed, pieces):
    occ = set()
    for (x,y,w,h) in placed:
        occ |= {(xx,yy) for yy in range(y,y+h) for xx in range(x,x+w)}
    allnum = {p for p,v in numbers}
    nums = [(p,v) for p,v in numbers if p not in occ]
    pc = Counter(key(d) for d in pieces)
    def cands(p, v):
        for w in range(1, v+1):
            if v % w: continue
            h = v//w
            for x0 in range(p[0]-w+1, p[0]+1):
                for y0 in range(p[1]-h+1, p[1]+1):
                    if x0 < 0 or y0 < 0 or x0+w > cols or y0+h > rows: continue
                    cs = {(xx,yy) for yy in range(y0,y0+h) for xx in range(x0,x0+w)}
                    if any(c in allnum and c != p for c in cs): continue
                    yield (w,h), cs
    def rec(k):
        if k == len(nums): return True
        p, v = nums[k]
        for d, cs in cands(p, v):
            kk = key(d)
            if pc[kk] <= 0 or cs & occ: continue
            pc[kk] -= 1; occ.update(cs)
            if rec(k+1): return True
            pc[kk] += 1; occ.difference_update(cs)
        return False
    return rec(0)

def check_solution(cols, rows, numbers, placed, pieces, sol):
    cells = set()
    for (x,y,w,h) in list(placed) + list(sol):
        cs = {(xx,yy) for yy in range(y,y+h) for xx in range(x,x+w)}
        assert not (cells & cs), "overlap"; cells |= cs
    assert len(cells) == cols*rows, "not full"
    for (x,y,w,h) in sol:
        inside = [(p,v) for p,v in numbers if x <= p[0] < x+w and y <= p[1] < y+h]
        assert len(inside) == 1 and inside[0][1] == w*h, "rule"
    assert Counter(key(r[2:]) for r in sol) == Counter(key(d) for d in pieces), "pieces"

if __name__ == '__main__':
    N = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    rnd = random.Random(1)
    fb = 0; stats = Counter(); maxsteps = Counter(); tsum = 0.0; nsolve = 0; mism = 0
    steps_all = []
    for L in range(1, N+1):
        d = generate(L); cols, rows = d['cols'], d['rows']; nums = d['numbers']
        fb += d['fallback']
        # 1) генератор: разбиение корректно
        check_solution(cols, rows, nums, [], d['pieces'], d['solution'])
        # 2) случайная игра: ставим случайные допустимые блоки, на каждом шаге решаем
        placed = []; pieces = list(d['pieces'])
        while pieces:
            t0 = time.perf_counter(); stt, sol, steps = solve(cols, rows, nums, placed, pieces); tsum += time.perf_counter()-t0; nsolve += 1
            steps_all.append(steps); stats[stt] += 1
            if stt == SOLVED: check_solution(cols, rows, nums, placed, pieces, sol)
            if stt != UNKNOWN and (L <= 60 or rnd.random() < 0.15):
                if (stt == SOLVED) != brute_solvable(cols, rows, nums, placed, pieces): mism += 1
            # случайный локально допустимый ход
            occ = set()
            for (x,y,w,h) in placed: occ |= {(xx,yy) for yy in range(y,y+h) for xx in range(x,x+w)}
            val = dict(nums); moves = []
            for pi, (w0,h0) in enumerate(pieces):
                for (w,h) in {(w0,h0),(h0,w0)}:
                    for y in range(rows-h+1):
                        for x in range(cols-w+1):
                            cs = [(xx,yy) for yy in range(y,y+h) for xx in range(x,x+w)]
                            if any(c in occ for c in cs): continue
                            ns = [val[c] for c in cs if c in val]
                            if len(ns) == 1 and ns[0] == w*h: moves.append((pi,(x,y,w,h)))
            if not moves: break
            pi, r = rnd.choice(moves); placed.append(r); pieces.pop(pi)
    print(f"levels={N} fallback={fb}")
    print(f"solves={nsolve} SOLVED={stats[SOLVED]} UNSOLVABLE={stats[UNSOLVABLE]} UNKNOWN={stats[UNKNOWN]} brute-mismatch={mism}")
    steps_all.sort()
    print(f"steps: median={steps_all[len(steps_all)//2]} p99={steps_all[int(len(steps_all)*0.99)]} max={steps_all[-1]}; avg py time={tsum/nsolve*1000:.2f} ms")
