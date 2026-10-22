class_name LevelPack
extends RefCounted
## Заготовленные уровни: у каждого единственное решение и подобранная сложность.
## Данные — scripts/level_pack_data.gd, их создаёт tools/make_levels.py.
##
## Строка уровня: "CR:" — ширина и высота поля; затем по 6 цифр на прямоугольник
## решения (x, y, ширина, высота, клетка числа x, y); затем ":" и по 2 цифры на
## блок в порядке выдачи (ширина, высота).
##
## После последнего уровня повторяются уровни LOOP_FROM..count(): отражённые
## по горизонтали, вертикали или обеим осям (решение остаётся единственным)
## и с новым порядком блоков. Python-копия: tools/make_levels.py (pack_level).
##
## 19.3, механики «Лаборатории» — необязательная четвёртая часть после ":", метки подряд:
##   hXY — препятствие в клетке (X, Y);  pXYWH — закреплённый блок (без числа, в решение не входит);
##   qXY — число в клетке (X, Y) — «?» (value = ShikakuSolver.ANY);  tXYA — цветная клетка: её накрывает
##   только блок площади A. В словаре уровня тогда есть holes (Array[Vector2i]), pinned (Array[Rect2i]) и
##   tints (Array[Dictionary] {pos, value}). Python-копия чтения и проверки — tools/make_lab.py (decode).
## 19.5e: так же записаны уровни глав 4–10 с механикой (tools/chapter_levels.py); повтор отражает и механику.

const DATA := preload("res://scripts/level_pack_data.gd")


static func count() -> int:
	return DATA.LEVELS.size()


## Уровень n (с 1) в формате LevelGenerator.generate или {} — если строка испорчена.
static func get_level(n: int) -> Dictionary:
	var total := count()
	if n < 1 or total == 0:
		return {}
	if n <= total:
		return decode(DATA.LEVELS[n - 1])
	var first: int = clampi(DATA.LOOP_FROM, 1, total)
	var span := total - first + 1
	var k := n - total - 1
	var base := decode(DATA.LEVELS[first - 1 + k % span])
	if base.is_empty():
		return {}
	@warning_ignore("integer_division")
	var variant := 1 + (k / span) % 3
	return _mirror(base, n, variant)


## Механика уровня (словарь decode/get_level): "holes", "pinned", "tints", "unknown" или "" — классика.
## В одном уровне основного пути — одна механика (tools/make_levels.py: verify_mech); при нескольких —
## первая по этому порядку. Python-копия — tools/make_levels.py (mechanic_of).
static func mechanic_of(data: Dictionary) -> String:
	if not (data.get("holes", []) as Array).is_empty():
		return "holes"
	if not (data.get("pinned", []) as Array).is_empty():
		return "pinned"
	if not (data.get("tints", []) as Array).is_empty():
		return "tints"
	for nm: Dictionary in data.get("numbers", []):
		if int(nm.value) == ShikakuSolver.ANY:
			return "unknown"
	return ""


## Длина метки механики вместе с буквой (четвёртая часть строки).
const MOD_LEN := {"h": 3, "p": 5, "q": 3, "t": 4}


static func decode(s: String) -> Dictionary:
	var parts := s.split(":")
	if (parts.size() != 3 and parts.size() != 4) or parts[0].length() != 2:
		return {}
	var rs := parts[1]
	var ps := parts[2]
	var mods := parts[3] if parts.size() == 4 else ""
	if rs.is_empty() or rs.length() % 6 != 0 or ps.length() * 3 != rs.length():
		return {}
	if not (_all_digits(parts[0]) and _all_digits(rs) and _all_digits(ps)):
		return {}
	var cols := _digit(parts[0], 0)
	var rows := _digit(parts[0], 1)
	if cols < 2 or rows < 2:
		return {}
	var used := []
	used.resize(cols * rows)
	used.fill(false)
	var solution: Array[Rect2i] = []
	var numbers: Array[Dictionary] = []
	for i in range(0, rs.length(), 6):
		var r := Rect2i(_digit(rs, i), _digit(rs, i + 1), _digit(rs, i + 2), _digit(rs, i + 3))
		var pos := Vector2i(_digit(rs, i + 4), _digit(rs, i + 5))
		if not r.has_point(pos) or not _take(used, cols, rows, r):
			return {}
		solution.append(r)
		numbers.append({"pos": pos, "value": r.size.x * r.size.y})
	var pieces: Array[Vector2i] = []
	for i in range(0, ps.length(), 2):
		pieces.append(Vector2i(_digit(ps, i), _digit(ps, i + 1)))
	var data := {
		"cols": cols,
		"rows": rows,
		"solution": solution,
		"numbers": numbers,
		"pieces": pieces,
	}
	if not mods.is_empty() and not _decode_mods(mods, data, used):
		return {}
	if used.count(true) != cols * rows:
		return {}
	return data


## Четвёртая часть строки (механики 19.3) → holes, pinned, tints и числа «?» в data; false — строка испорчена.
static func _decode_mods(mods: String, data: Dictionary, used: Array) -> bool:
	var cols: int = data.cols
	var rows: int = data.rows
	var numbers: Array = data.numbers
	var holes: Array[Vector2i] = []
	var pinned: Array[Rect2i] = []
	var tints: Array[Dictionary] = []
	var i := 0
	while i < mods.length():
		var tag := mods.substr(i, 1)
		var n: int = MOD_LEN.get(tag, 0)
		if n == 0 or i + n > mods.length() or not _all_digits(mods.substr(i + 1, n - 1)):
			return false
		var c := Vector2i(_digit(mods, i + 1), _digit(mods, i + 2))
		match tag:
			"h":
				if not _take(used, cols, rows, Rect2i(c, Vector2i.ONE)):
					return false
				holes.append(c)
			"p":
				var r := Rect2i(c, Vector2i(_digit(mods, i + 3), _digit(mods, i + 4)))
				if not _take(used, cols, rows, r):
					return false
				pinned.append(r)
			"q":
				var hit := -1
				for k in numbers.size():
					if numbers[k].pos == c:
						hit = k
						break
				if hit < 0:
					return false
				numbers[hit].value = ShikakuSolver.ANY
			_:
				var area := _digit(mods, i + 3)
				if c.x >= cols or c.y >= rows or area <= 0:
					return false
				for nm: Dictionary in numbers:
					if nm.pos == c:
						return false
				tints.append({"pos": c, "value": area})
		i += n
	data["holes"] = holes
	data["pinned"] = pinned
	data["tints"] = tints
	return true


## Занять клетки r в used (cols × rows); false — r выходит за поле или задевает занятое.
static func _take(used: Array, cols: int, rows: int, r: Rect2i) -> bool:
	if r.size.x < 1 or r.size.y < 1 or r.position.x < 0 or r.position.y < 0 or r.end.x > cols or r.end.y > rows:
		return false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if used[y * cols + x]:
				return false
			used[y * cols + x] = true
	return true


## Отражение уровня (variant: 1 — по X, 2 — по Y, 3 — оба) и новый порядок блоков. Механика (19.5e)
## отражается вместе с полем: препятствия, закреплённые блоки, цветные клетки; «?» остаётся в numbers.
static func _mirror(base: Dictionary, n: int, variant: int) -> Dictionary:
	var cols: int = base.cols
	var rows: int = base.rows
	var src_solution: Array = base.solution
	var src_numbers: Array = base.numbers
	var solution: Array[Rect2i] = []
	var numbers: Array[Dictionary] = []
	for i in src_solution.size():
		var r: Rect2i = src_solution[i]
		var pos: Vector2i = src_numbers[i].pos
		if variant & 1:
			r.position.x = cols - r.position.x - r.size.x
			pos.x = cols - 1 - pos.x
		if variant & 2:
			r.position.y = rows - r.position.y - r.size.y
			pos.y = rows - 1 - pos.y
		solution.append(r)
		numbers.append({"pos": pos, "value": int(src_numbers[i].value)})

	var rng := LevelGenerator.Rng.new(LevelGenerator.Rng.mix32(n * 2654435761 + DATA.SEED_SALT + DATA.VERSION * 97531))
	var pieces: Array[Vector2i] = []
	for r in solution:
		var p := r.size
		if rng.next_float() < 0.5:
			p = Vector2i(p.y, p.x)
		pieces.append(p)
	for i in range(pieces.size() - 1, 0, -1):
		var j := rng.range_int(0, i)
		var tmp := pieces[i]
		pieces[i] = pieces[j]
		pieces[j] = tmp
	var data := {
		"cols": cols,
		"rows": rows,
		"solution": solution,
		"numbers": numbers,
		"pieces": pieces,
	}
	if base.has("holes"):
		var holes: Array[Vector2i] = []
		for c: Vector2i in base.holes:
			holes.append(_flip(Rect2i(c, Vector2i.ONE), cols, rows, variant).position)
		var pinned: Array[Rect2i] = []
		for r: Rect2i in base.pinned:
			pinned.append(_flip(r, cols, rows, variant))
		var tints: Array[Dictionary] = []
		for t: Dictionary in base.tints:
			tints.append({"pos": _flip(Rect2i(t.pos, Vector2i.ONE), cols, rows, variant).position, "value": t.value})
		data["holes"] = holes
		data["pinned"] = pinned
		data["tints"] = tints
	return data


## Прямоугольник r, отражённый как поле в _mirror.
static func _flip(r: Rect2i, cols: int, rows: int, variant: int) -> Rect2i:
	if variant & 1:
		r.position.x = cols - r.position.x - r.size.x
	if variant & 2:
		r.position.y = rows - r.position.y - r.size.y
	return r


static func _all_digits(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 48 or c > 57:
			return false
	return true


static func _digit(s: String, i: int) -> int:
	return s.unicode_at(i) - 48
