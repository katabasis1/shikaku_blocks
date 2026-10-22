class_name ShikakuSolver
extends RefCounted
## Решатель шикаку с учётом набора блоков.
##
## Ищет любое полное решение, продолжающее текущую расстановку: каждое
## непокрытое число получает прямоугольник своей площади из оставшихся блоков
## (с поворотом), прямоугольники не пересекаются и не накрывают чужих чисел.
##
## Перебор с эвристикой MRV (сначала число с наименьшим числом вариантов).
## Клетки поля кодируются битами int (поле до 62 клеток), поэтому проверка
## «прямоугольник свободен» — одна операция AND. На уровнях игры (до 7×8)
## перебор укладывается в десятки шагов; лимит шагов — страховка от зависаний.
## Python-копия алгоритма с тестами: tools/model.py.
##
## 19.3: правила механик (run_level, rules_of): препятствия и закреплённый блок — занятые с начала клетки
## (blocked), число «?» (value = ANY) — блок любой оставшейся формы, цветная клетка (tints) — накрыть её можно
## только блоком её площади. Python-копия — tools/model.py (solve с blocked / tints / ANY), проверка уровней
## «Лаборатории» — tools/make_lab.py.

enum { SOLVED, UNSOLVABLE, UNKNOWN }

const DEFAULT_STEP_LIMIT := 4000
const MAX_CELLS := 62
## Значение числа «?» (LevelPack.decode, механика 19.3): площадь не показана.
const ANY := -1

## Результат: SOLVED, UNSOLVABLE или UNKNOWN (лимит шагов / неподходящие данные).
var status: int = UNKNOWN
## Прямоугольники решения для непокрытых чисел (заполнено при SOLVED).
var solution: Array[Rect2i] = []
## Сколько узлов перебора пройдено.
var steps: int = 0

var _occ: int = 0
var _left := PackedInt32Array()
var _cand_masks: Array = []   # на каждое число — PackedInt64Array масок кандидатов
var _cand_keys: Array = []    # на каждое число — PackedInt32Array индексов формы блока
var _cand_rects: Array = []   # на каждое число — Array прямоугольников
var _limit: int = DEFAULT_STEP_LIMIT
var _aborted := false


## cols, rows — размер поля; numbers — все числа уровня ({pos: Vector2i, value: int});
## placed — уже поставленные прямоугольники; pieces — размеры оставшихся блоков.
static func run(cols: int, rows: int, numbers: Array, placed: Array[Rect2i],
		pieces: Array[Vector2i], step_limit: int = DEFAULT_STEP_LIMIT) -> ShikakuSolver:
	var solver := ShikakuSolver.new()
	solver._solve(cols, rows, numbers, placed, pieces, step_limit, {})
	return solver


## Решатель уровня с механиками (LevelPack.decode: holes, pinned, tints, числа ANY): placed — блоки игрока.
## У обычного уровня — то же, что run.
static func run_level(data: Dictionary, placed: Array[Rect2i], pieces: Array[Vector2i],
		step_limit: int = DEFAULT_STEP_LIMIT) -> ShikakuSolver:
	var solver := ShikakuSolver.new()
	solver._solve(int(data.cols), int(data.rows), data.numbers, placed, pieces, step_limit, rules_of(data))
	return solver


## Правила механик уровня: {"blocked": Array[Vector2i] — препятствия и клетки закреплённых блоков,
## "tints": {Vector2i: площадь}}. У обычного уровня — пустые.
static func rules_of(data: Dictionary) -> Dictionary:
	var blocked: Array[Vector2i] = []
	for c: Vector2i in data.get("holes", []):
		blocked.append(c)
	for r: Rect2i in data.get("pinned", []):
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				blocked.append(Vector2i(x, y))
	var tints := {}
	for t: Dictionary in data.get("tints", []):
		tints[t.pos] = int(t.value)
	return {"blocked": blocked, "tints": tints}


## Короткая и длинная сторона — форма блока без учёта поворота.
static func shape_key(dims: Vector2i) -> Vector2i:
	return Vector2i(mini(dims.x, dims.y), maxi(dims.x, dims.y))


static func rect_mask(cols: int, r: Rect2i) -> int:
	var m := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			m |= 1 << (y * cols + x)
	return m


func _solve(cols: int, rows: int, numbers: Array, placed: Array[Rect2i],
		pieces: Array[Vector2i], step_limit: int, rules: Dictionary) -> void:
	status = UNKNOWN
	_limit = step_limit
	if cols * rows > MAX_CELLS or cols <= 0 or rows <= 0:
		return

	_occ = 0
	for r in placed:
		_occ |= rect_mask(cols, r)
	for c: Vector2i in rules.get("blocked", []):
		_occ |= 1 << (c.y * cols + c.x)
	var tints: Dictionary = rules.get("tints", {})

	# Формы оставшихся блоков → индекс и количество.
	var key_index := {}
	_left = PackedInt32Array()
	for d in pieces:
		var k := shape_key(d)
		if not key_index.has(k):
			key_index[k] = _left.size()
			_left.append(0)
		_left[int(key_index[k])] += 1

	# Все клетки с числами (накрытые тоже: прямоугольник с чужим числом недопустим).
	var number_cells := {}
	for n in numbers:
		number_cells[n.pos] = true

	# Непокрытые числа и их кандидаты.
	_cand_masks.clear()
	_cand_keys.clear()
	_cand_rects.clear()
	for n in numbers:
		var p: Vector2i = n.pos
		if ((_occ >> (p.y * cols + p.x)) & 1) == 1:
			continue
		var masks := PackedInt64Array()
		var keys := PackedInt32Array()
		var rects: Array[Rect2i] = []
		for dims: Vector2i in _shapes_for(int(n.value), key_index):
			var w := dims.x
			var h := dims.y
			if w > cols or h > rows:
				continue
			var k := shape_key(dims)
			for y0 in range(maxi(0, p.y - h + 1), mini(p.y, rows - h) + 1):
				for x0 in range(maxi(0, p.x - w + 1), mini(p.x, cols - w) + 1):
					var r := Rect2i(x0, y0, w, h)
					if _has_foreign_number(r, p, number_cells) or not tint_ok(r, tints):
						continue
					masks.append(rect_mask(cols, r))
					keys.append(int(key_index[k]))
					rects.append(r)
		_cand_masks.append(masks)
		_cand_keys.append(keys)
		_cand_rects.append(rects)

	# Каждый поставленный блок накрыл ровно одно число, поэтому непокрытых чисел
	# должно быть столько же, сколько блоков осталось. Иначе данные неконсистентны.
	if _cand_masks.size() != pieces.size():
		return

	var todo := PackedInt32Array()
	for i in _cand_masks.size():
		todo.append(i)
	var out: Array[Rect2i] = []
	steps = 0
	_aborted = false
	var ok := _search(todo, out)
	if _aborted:
		status = UNKNOWN
	elif ok:
		status = SOLVED
		solution = out
	else:
		status = UNSOLVABLE


## Размеры (ширина, высота) прямоугольников числа v: делители v; у «?» (ANY) — обе ориентации каждой
## оставшейся формы (порядок key_index). Только формы, которые ещё есть в наборе. Как shapes_for в model.py.
static func _shapes_for(v: int, key_index: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if v == ANY:
		for k: Vector2i in key_index:
			out.append(k)
			if k.x != k.y:
				out.append(Vector2i(k.y, k.x))
		return out
	for w in range(1, v + 1):
		if v % w != 0:
			continue
		@warning_ignore("integer_division")
		var dims := Vector2i(w, v / w)
		if key_index.has(shape_key(dims)):
			out.append(dims)
	return out


## Цветные клетки под r (tints: {Vector2i: площадь}) — все площади r: блок накрывает только «свой» цвет.
static func tint_ok(r: Rect2i, tints: Dictionary) -> bool:
	if tints.is_empty():
		return true
	var area := r.size.x * r.size.y
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if int(tints.get(Vector2i(x, y), area)) != area:
				return false
	return true


func _has_foreign_number(r: Rect2i, own: Vector2i, number_cells: Dictionary) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if c != own and number_cells.has(c):
				return true
	return false


func _search(todo: PackedInt32Array, out: Array[Rect2i]) -> bool:
	if todo.is_empty():
		return true
	steps += 1
	if steps > _limit:
		_aborted = true
		return false

	# MRV: число с наименьшим количеством доступных вариантов.
	var best_t := -1
	var best_count := 0
	for t in todo.size():
		var i := todo[t]
		var masks: PackedInt64Array = _cand_masks[i]
		var keys: PackedInt32Array = _cand_keys[i]
		var count := 0
		for c in masks.size():
			if (masks[c] & _occ) == 0 and _left[keys[c]] > 0:
				count += 1
		if count == 0:
			return false
		if best_t < 0 or count < best_count:
			best_t = t
			best_count = count

	var idx := todo[best_t]
	var rest := todo.duplicate()
	rest.remove_at(best_t)
	var best_masks: PackedInt64Array = _cand_masks[idx]
	var best_keys: PackedInt32Array = _cand_keys[idx]
	var best_rects: Array = _cand_rects[idx]
	for c in best_masks.size():
		var m := best_masks[c]
		var k := best_keys[c]
		if (m & _occ) != 0 or _left[k] <= 0:
			continue
		_left[k] -= 1
		_occ |= m
		out.append(best_rects[c])
		if _search(rest, out):
			return true
		out.pop_back()
		_occ &= ~m
		_left[k] += 1
		if _aborted:
			return false
	return false
