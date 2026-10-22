class_name LevelGenerator
extends RefCounted
## Уровни шикаку. generate() берёт заготовку из LevelPack (единственное решение,
## подобранная сложность); процедурный генератор ниже — запасной, если список
## уровней недоступен или испорчен.
##
## Процедурный генератор: поле разбивается на прямоугольники (это и есть решение), в каждый
## прямоугольник ставится число = его площадь. Уровни детерминированы:
## один и тот же номер уровня всегда даёт одно и то же поле.
##
## Случайность — собственный xorshift32 с зерном от номера уровня, а не
## RandomNumberGenerator + hash(): их алгоритмы движок не обещает сохранять
## между версиями, и уровни у игроков могли бы тихо поменяться.
## Меняешь логику генерации — увеличь GENERATOR_VERSION.
## Python-копия генератора для проверки: tools/model.py.

const GENERATOR_VERSION := 2
const MAX_SIDE := 4
const CANDIDATES := 8
const MAX_ATTEMPTS := 400


static func grid_size(level: int) -> Vector2i:
	if level <= 2:
		return Vector2i(4, 4)
	if level <= 6:
		return Vector2i(5, 5)
	if level <= 12:
		return Vector2i(5, 6)
	if level <= 20:
		return Vector2i(6, 6)
	if level <= 32:
		return Vector2i(6, 7)
	if level <= 48:
		return Vector2i(7, 7)
	return Vector2i(7, 8)


static func max_area(level: int) -> int:
	if level <= 3:
		return 4
	if level <= 10:
		return 6
	if level <= 25:
		return 8
	return 9


## Возвращает словарь:
## cols, rows — размер поля;
## solution — Array[Rect2i] (эталонное разбиение);
## numbers — Array[Dictionary] { pos: Vector2i, value: int };
## pieces — Array[Vector2i] размеры блоков в порядке выдачи в лоток.
static func generate(level: int) -> Dictionary:
	var d := LevelPack.get_level(level)
	if not d.is_empty():
		return d
	push_warning("Список уровней недоступен, уровень %d создан процедурно" % level)
	return generate_procedural(level)


## Запасной процедурный генератор (решение может быть не единственным).
static func generate_procedural(level: int) -> Dictionary:
	var rng := Rng.new(level_seed(level))
	var size := grid_size(level)
	var limit := max_area(level)

	var best: Array[Rect2i] = []
	var best_score := -1.0e9
	var found := 0
	for attempt in MAX_ATTEMPTS:
		var rects := _partition(size, limit, rng)
		if rects.is_empty():
			continue
		var score := _score(rects, rng)
		if score > best_score:
			best_score = score
			best = rects
		found += 1
		if found >= CANDIDATES:
			break
	if best.is_empty():
		best = _fallback(size)

	var numbers: Array[Dictionary] = []
	for r in best:
		var pos := r.position + Vector2i(rng.range_int(0, r.size.x - 1), rng.range_int(0, r.size.y - 1))
		numbers.append({"pos": pos, "value": r.size.x * r.size.y})

	var pieces: Array[Vector2i] = []
	for r in best:
		var p := r.size
		if rng.next_float() < 0.5:
			p = Vector2i(p.y, p.x)
		pieces.append(p)
	for i in range(pieces.size() - 1, 0, -1):
		var j := rng.range_int(0, i)
		var tmp := pieces[i]
		pieces[i] = pieces[j]
		pieces[j] = tmp

	return {
		"cols": size.x,
		"rows": size.y,
		"solution": best,
		"numbers": numbers,
		"pieces": pieces,
	}


## Зерно уровня: перемешивание номера (murmur3 fmix32) с версией генератора.
static func level_seed(level: int) -> int:
	return Rng.mix32(level * 2654435761 + GENERATOR_VERSION * 97531)


static func _partition(size: Vector2i, limit: int, rng: Rng) -> Array[Rect2i]:
	var cols := size.x
	var rows := size.y
	var used := PackedByteArray()
	used.resize(cols * rows)
	used.fill(0)
	var rects: Array[Rect2i] = []
	for i in cols * rows:
		if used[i] == 1:
			continue
		var x := i % cols
		@warning_ignore("integer_division")
		var y := i / cols
		var max_w := 0
		while x + max_w < cols and max_w < MAX_SIDE and used[y * cols + x + max_w] == 0:
			max_w += 1
		var options: Array[Vector2i] = []
		var weights := PackedFloat64Array()
		for w in range(1, max_w + 1):
			for h in range(1, MAX_SIDE + 1):
				if y + h > rows:
					break
				var row_free := true
				for xx in range(x, x + w):
					if used[(y + h - 1) * cols + xx] == 1:
						row_free = false
						break
				if not row_free:
					break
				var a := w * h
				if a < 2 or a > limit:
					continue
				options.append(Vector2i(w, h))
				weights.append(_weight(w, h))
		if options.is_empty():
			return []
		var pick := options[_weighted_index(weights, rng)]
		for yy in range(y, y + pick.y):
			for xx in range(x, x + pick.x):
				used[yy * cols + xx] = 1
		rects.append(Rect2i(x, y, pick.x, pick.y))
	return rects


static func _weight(w: int, h: int) -> float:
	var a := w * h
	var wgt := 1.0
	match a:
		2: wgt = 1.0
		3: wgt = 2.2
		4: wgt = 2.6
		5: wgt = 1.6
		6: wgt = 2.4
		8: wgt = 1.8
		9: wgt = 1.4
	if mini(w, h) == 1 and maxi(w, h) == 4:
		wgt *= 0.6
	return wgt


static func _weighted_index(weights: PackedFloat64Array, rng: Rng) -> int:
	var total := 0.0
	for v in weights:
		total += v
	var roll := rng.next_float() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return weights.size() - 1


static func _score(rects: Array[Rect2i], rng: Rng) -> float:
	var areas := {}
	var twos := 0
	for r in rects:
		var a := r.size.x * r.size.y
		areas[a] = true
		if a == 2:
			twos += 1
	return areas.size() * 2.0 - twos * 0.7 + rng.next_float()


static func _fallback(size: Vector2i) -> Array[Rect2i]:
	# Простое разбиение строк на куски по 2–3 клетки (на случай неудачи генератора).
	var rects: Array[Rect2i] = []
	for y in size.y:
		var x := 0
		while x < size.x:
			var left := size.x - x
			var w := 3 if (left == 3 or left > 4) else 2
			w = mini(w, left)
			rects.append(Rect2i(x, y, w, 1))
			x += w
	return rects


## Детерминированный ГПСЧ xorshift32. Все операции укладываются в 32 бита,
## поэтому результат одинаков на любой платформе и версии движка.
class Rng:
	const MASK := 0xFFFFFFFF

	var state: int

	func _init(seed_value: int) -> void:
		state = seed_value & MASK
		if state == 0:
			state = 0x9E3779B9

	func next_u32() -> int:
		var x := state
		x ^= (x << 13) & MASK
		x ^= x >> 17
		x ^= (x << 5) & MASK
		state = x
		return x

	## Число из [0, 1).
	func next_float() -> float:
		return float(next_u32()) / 4294967296.0

	## Целое из [from, to] включительно.
	func range_int(from: int, to: int) -> int:
		return from + next_u32() % (to - from + 1)

	## Умножение по модулю 2^32 без переполнения int64.
	static func mul32(a: int, b: int) -> int:
		var lo := (a * (b & 0xFFFF)) & MASK
		var hi := ((a * (b >> 16)) & 0xFFFF) << 16
		return (lo + hi) & MASK

	static func mix32(v: int) -> int:
		var h := v & MASK
		h ^= h >> 16
		h = mul32(h, 0x85EBCA6B)
		h ^= h >> 13
		h = mul32(h, 0xC2B2AE35)
		h ^= h >> 16
		return h
