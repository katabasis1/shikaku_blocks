class_name Board
extends Control
## Игровое поле: клетки, поставленные блоки, проверка правил шикаку.
## Вид (docs/STYLE.md, раздел 6): рамку, лоток и ячейки рисует один шейдер в узле Frame
## (shaders/board.gdshader), числа — «гнёзда» cell.tscn, место под блоком — призрак Ghost
## (shaders/ghost.gdshader), волны света по закрытым линиям — line_flash.tscn (14.4), по всему полю на победе —
## win_wave.tscn (14.5, celebrate: блоки вспыхивают, подпрыгивают и сходятся в мозаику).
## 14.2: блок долетает до места за JuiceConfig.land_time и в этот миг — удар: сплющивание (Block.squash)
## и сигнал landed (Game: тряска, пыль, звук); «щелчок» допустимого места — snap_preview.
## 14.3: в тот же миг число блока закрыто — Block.close_number (вспышка цифры, галочка, свет по клеткам).
## 14.6b: появление уровня — ячейки вырастают волной по диагонали (униформа appear шейдера рамки), числа
## выпрыгивают после своих ячеек (Cell.appear); шаг и время — группа «Появление и переходы» в JuiceConfig.

## Блок долетел до места r (через land_time после place_block; отмена хода в полёте — сигнала нет).
signal landed(block: Block, r: Rect2i)

const CELL := Block.CELL  # единый размер клетки — в block.gd
## Рамка в логических px экрана (не зависит от масштаба поля): от ячеек до наружного края бортика,
## ширина бортика, губа бортика под полем. Тень рамки помещается в поля FRAME_MARGIN.
const PAD := 26.0
const RIM := 15.0
const FRAME_DEPTH := 12.0
const FRAME_MARGIN := 72.0
## Наибольший масштаб по умолчанию (портрет); в альбоме Game ставит max_scale из GameLayout.
const MAX_SCALE := 1.35
## Блок подсказки, пока ждёт искру и плывёт на место (14.6g): поверх лотка и панелей; на месте — снова 0.
const FLOAT_Z := 1
const CELL_SCENE: PackedScene = preload("res://scenes/game/cell.tscn")
const LINE_FLASH_SCENE: PackedScene = preload("res://scenes/game/line_flash.tscn")
const WIN_WAVE_SCENE: PackedScene = preload("res://scenes/game/win_wave.tscn")
const BLOCK_SCENE: PackedScene = preload("res://scenes/game/block.tscn")
## Занятость клетки-препятствия (19.3) в _occupant: не null, но и не блок.
const HOLE := &"hole"

@onready var frame: ColorRect = $Frame
@onready var cells_root: Control = $Cells
@onready var ghost: ColorRect = $Ghost
@onready var blocks_root: Control = $Blocks
@onready var fx_root: Control = $Fx

## Наибольший масштаб поля: маленькие поля не раздуваются на всё место (GameLayout.BOARD_SCALE_*).
var max_scale: float = MAX_SCALE
var cols: int = 0
var rows: int = 0
## Гнёзда чисел по индексу клетки (null — клетка без числа).
var _cells: Array[Cell] = []
var _values := PackedInt32Array()
var _occupant: Array = []
var _blocks: Dictionary = {}
## Механики 19.3 (LevelPack.decode): цветные клетки {Vector2i: площадь} и закреплённые блоки (узлы Block,
## в _blocks не входят — их не снять и не отменить; клетки — в _occupant).
var _tints: Dictionary = {}
var _pinned: Array[Block] = []
## Локальных px поля в логическом px экрана (1 / масштаб поля).
var _px: float = 1.0
var _appear_tween: Tween
var _dim_tween: Tween
var _dim := 0.0
var _snap_tween: Tween


func setup(data: Dictionary) -> void:
	if _dim_tween and _dim_tween.is_valid():
		_dim_tween.kill()
	_set_dim(0.0)
	for root in [cells_root, blocks_root, fx_root]:
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()
	_cells.clear()
	_blocks.clear()
	_pinned.clear()
	clear_preview()

	cols = data.cols
	rows = data.rows
	_values.resize(cols * rows)
	_values.fill(0)
	_occupant.resize(cols * rows)
	_occupant.fill(null)
	for n in data.numbers:
		var p: Vector2i = n.pos
		_values[p.y * cols + p.x] = n.value
	_tints = ShikakuSolver.rules_of(data).tints

	_cells.resize(cols * rows)
	_cells.fill(null)
	var c := Juice.shared_config()
	for y in rows:
		for x in cols:
			if _values[y * cols + x] == 0:
				continue
			var cell := CELL_SCENE.instantiate() as Cell
			cells_root.add_child(cell)
			cell.position = Vector2(x, y) * CELL
			_cells[y * cols + x] = cell
			cell.set_value(_values[y * cols + x])
	_setup_mechanics(data)
	_update_frame()
	for y in rows:
		for x in cols:
			if _cells[y * cols + x] != null:
				_cells[y * cols + x].appear(c.intro_cell_step * (x + y) + c.intro_number_delay)
	_play_appear()


## Механики 19.3 (STYLE 11.5): препятствия — плитки бортика (CellMark.HOLE, в _occupant — HOLE), цветные
## клетки — CellMark.TINT, закреплённые блоки — блоки цвета Palette.PINNED без цифры, с заклёпками (CellMark.PIN).
## Знаки проявляются волной вместе с ячейками.
func _setup_mechanics(data: Dictionary) -> void:
	var c := Juice.shared_config()
	var marks: Array[CellMark] = []
	for h: Vector2i in data.get("holes", []):
		_occupant[h.y * cols + h.x] = HOLE
		var mark := CellMark.new(CellMark.Kind.HOLE)
		mark.position = Vector2(h) * CELL
		marks.append(mark)
	for t: Dictionary in data.get("tints", []):
		var mark := CellMark.new(CellMark.Kind.TINT, int(t.value))
		mark.position = Vector2(t.pos) * CELL
		marks.append(mark)
	for mark in marks:
		cells_root.add_child(mark)
		var at := Vector2i(mark.position / CELL)
		mark.modulate.a = 0.0
		mark.create_tween().tween_property(mark, "modulate:a", 1.0, 0.2).set_delay(c.intro_cell_step * (at.x + at.y))
	for r: Rect2i in data.get("pinned", []):
		var b := BLOCK_SCENE.instantiate() as Block
		b.cells = r.size
		b.show_number = false
		b.fixed_color = Palette.PINNED
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		blocks_root.add_child(b)
		b.position = Vector2(r.position) * CELL
		b.add_child(CellMark.new(CellMark.Kind.PIN, 0, r.size))
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				_occupant[y * cols + x] = b
		_pinned.append(b)
		b.modulate.a = 0.0
		b.create_tween().tween_property(b, "modulate:a", 1.0, 0.25) \
				.set_delay(c.intro_cell_step * (r.position.x + r.position.y))


## Клетка c занята с начала уровня (препятствие или закреплённый блок, 19.3).
func is_blocked(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
		return false
	var o: Variant = _occupant[c.y * cols + c.x]
	return o is StringName or (o is Block and _pinned.has(o))


## Закреплённые блоки уровня (19.3; selftest).
func pinned_blocks() -> Array[Block]:
	return _pinned


## Тупик (14.6g): поле на миг темнеет — рамка, ячейки и блоки ×(1 − dead_dim) (чуть в синеву) за dead_dim_in, держится
## dead_dim_hold и светлеет за dead_dim_out. Обычный твин (не Juice): hit-stop его не держит.
func dim_flash() -> void:
	var c := Block.cfg()
	if _dim_tween and _dim_tween.is_valid():
		_dim_tween.kill()
	_dim_tween = create_tween()
	_dim_tween.tween_method(_set_dim, _dim, c.dead_dim, maxf(c.dead_dim_in, 0.01)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if c.dead_dim_hold > 0.0:
		_dim_tween.tween_interval(c.dead_dim_hold)
	_dim_tween.tween_method(_set_dim, c.dead_dim, 0.0, maxf(c.dead_dim_out, 0.01)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Насколько поле сейчас темнее обычного: 0 — как всегда (selftest).
func dimmed() -> float:
	return _dim


func _set_dim(v: float) -> void:
	_dim = v
	var k := 1.0 - v
	# Слои поля, а не само поле: board.modulate держит притушенное поле обучения (TutorialCoach) — цвета
	# перемножаются, вспышка тупика его не сбрасывает.
	for layer in [frame, cells_root, blocks_root]:
		(layer as CanvasItem).modulate = Color(k, k, minf(1.0, k + 0.35 * v))


## Ячейки вырастают волной по диагонали (14.6b: шаг JuiceConfig.intro_cell_step) — униформа appear шейдера
## поля; числа выпрыгивают после своих ячеек (Cell.appear). Ввод не ждёт появления.
func _play_appear() -> void:
	var mat := frame.material as ShaderMaterial
	if mat == null:
		return
	if _appear_tween and _appear_tween.is_valid():
		_appear_tween.kill()
	var step := Juice.shared_config().intro_cell_step
	var duration := step * float(cols + rows) + 0.4
	mat.set_shader_parameter("appear_step", step)
	mat.set_shader_parameter("appear", 0.0)
	_appear_tween = create_tween()
	_appear_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("appear", v), 0.0, duration, duration)
	_appear_tween.tween_callback(func() -> void: mat.set_shader_parameter("appear", 100.0))


## Рамку, тени и призрак — под текущий масштаб поля (их размеры заданы в логических px).
func _update_frame() -> void:
	var s := scale.x
	_px = 1.0 / s if s > 0.01 else 1.0
	var grid := Vector2(cols, rows) * CELL
	var m := (FRAME_MARGIN + PAD) * _px
	frame.position = Vector2(-m, -m)
	frame.size = grid + Vector2(2.0 * m, 2.0 * m + FRAME_DEPTH * _px)
	var mat := frame.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("frame_size", frame.size)
		mat.set_shader_parameter("grid", Vector2(cols, rows))
		mat.set_shader_parameter("px", _px)
		mat.set_shader_parameter("margin", FRAME_MARGIN)
		mat.set_shader_parameter("pad", PAD)
		mat.set_shader_parameter("rim", RIM)
		mat.set_shader_parameter("lip", FRAME_DEPTH)
	var gmat := ghost.material as ShaderMaterial
	if gmat:
		gmat.set_shader_parameter("px", _px)
	for cell in _cells:
		if cell != null:
			cell.set_px(_px)


## Вписывает поле с рамкой в прямоугольник area_size (координаты родителя). Рамка (PAD, губа
## FRAME_DEPTH) — в логических px и не масштабируется, масштаб s — только у клеток (max_scale —
## наибольшая клетка, ×CELL px).
func fit_in(area_size: Vector2) -> void:
	if cols == 0:
		return
	var grid := Vector2(cols, rows) * CELL
	var frame_add := Vector2(PAD * 2.0, PAD * 2.0 + FRAME_DEPTH)
	var avail := area_size - frame_add
	var s := minf(minf(avail.x / grid.x, avail.y / grid.y), max_scale)
	s = maxf(s, 0.05)
	scale = Vector2(s, s)
	position = (area_size - (grid * s + frame_add)) * 0.5 + Vector2(PAD, PAD)
	_update_frame()


## Рамка поля целиком (с губой, без тени) в глобальных координатах — для проверок раскладки.
func frame_rect_global() -> Rect2:
	var gs := get_global_transform().get_scale().x
	var k := gs * _px  # логических px холста в одном px рамки (1, если над полем нет масштаба)
	var grid := Vector2(cols, rows) * CELL * gs
	return Rect2(global_position - Vector2(PAD, PAD) * k, grid + Vector2(PAD * 2.0, PAD * 2.0 + FRAME_DEPTH) * k)


func global_to_cell(global_point: Vector2) -> Vector2i:
	var local := get_global_transform().affine_inverse() * global_point
	return Vector2i(roundi(local.x / CELL), roundi(local.y / CELL))


## Дробные координаты клетки (для магнита: насколько точка далека от сетки).
func global_to_cell_f(global_point: Vector2) -> Vector2:
	var local := get_global_transform().affine_inverse() * global_point
	return local / CELL


## Подсветка чисел той же площади, что и перетаскиваемый блок; остальные приглушаются.
func emphasize_area(area: int) -> void:
	for i in _cells.size():
		var v := _values[i]
		if v == 0 or _cells[i] == null:
			continue
		if _occupant[i] != null:
			_cells[i].set_emphasis(Cell.EMPHASIS_NONE)
		elif v == area or v == ShikakuSolver.ANY:
			_cells[i].set_emphasis(Cell.EMPHASIS_MATCH)
		else:
			_cells[i].set_emphasis(Cell.EMPHASIS_DIM)


func clear_emphasis() -> void:
	for cell in _cells:
		if cell != null:
			cell.set_emphasis(Cell.EMPHASIS_NONE)


func cell_center_global(r: Rect2i) -> Vector2:
	var local := (Vector2(r.position) + Vector2(r.size) * 0.5) * CELL
	return get_global_transform() * local


func is_inside(r: Rect2i) -> bool:
	return r.position.x >= 0 and r.position.y >= 0 and r.end.x <= cols and r.end.y <= rows


func is_free(r: Rect2i) -> bool:
	if not is_inside(r):
		return false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if _occupant[y * cols + x] != null:
				return false
	return true


## Главное правило шикаку: внутри ровно одно число, и оно равно площади. Механики 19.3: «?» (ANY) — любая
## площадь; препятствия и закреплённые блоки заняты; цветную клетку накрывает только блок её площади.
func check_rect(r: Rect2i) -> bool:
	if not is_inside(r):
		return false
	var count := 0
	var found := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := y * cols + x
			if _occupant[i] != null:
				return false
			if _values[i] != 0:
				count += 1
				found = _values[i]
				if count > 1:
					return false
	return count == 1 and (found == r.size.x * r.size.y or found == ShikakuSolver.ANY) \
			and ShikakuSolver.tint_ok(r, _tints)


## Почему блок r не встаёт: Tutorial.Issue (OK — встаёт по правилам шикаку).
## Страховку (тупик) не проверяет — это DragController. Число под блоком — number_in(r).
func rect_issue(r: Rect2i) -> int:
	if not is_inside(r):
		return Tutorial.Issue.OUTSIDE
	var count := 0
	var found := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := y * cols + x
			if _occupant[i] != null:
				return Tutorial.Issue.BLOCKED if is_blocked(Vector2i(x, y)) else Tutorial.Issue.OCCUPIED
			if _values[i] != 0:
				count += 1
				found = _values[i]
	if count == 0:
		return Tutorial.Issue.NO_NUMBER
	if count > 1:
		return Tutorial.Issue.MANY_NUMBERS
	if found != r.size.x * r.size.y and found != ShikakuSolver.ANY:
		return Tutorial.Issue.WRONG_SIZE
	return Tutorial.Issue.OK if ShikakuSolver.tint_ok(r, _tints) else Tutorial.Issue.WRONG_COLOR


## Первое число под блоком r (0 — чисел нет или r за полем; ShikakuSolver.ANY — «?»).
func number_in(r: Rect2i) -> int:
	if not is_inside(r):
		return 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if _values[y * cols + x] != 0:
				return _values[y * cols + x]
	return 0


## Число в r стоит вплотную (по стороне) к такому же числу вне r — урок уровня 3 (TutorialCoach):
## блок занял одно из двух одинаковых соседних чисел.
func has_twin_next_to(r: Rect2i) -> bool:
	var at := _number_cell_in(r)
	if at.x < 0:
		return false
	var c := r.position + at
	var v := _values[c.y * cols + c.x]
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n := c + d
		if n.x >= 0 and n.y >= 0 and n.x < cols and n.y < rows and not r.has_point(n) and _values[n.y * cols + n.x] == v:
			return true
	return false


func can_fit_anywhere(dims: Vector2i) -> bool:
	for d in [dims, Vector2i(dims.y, dims.x)]:
		for y in range(0, rows - d.y + 1):
			for x in range(0, cols - d.x + 1):
				if check_rect(Rect2i(Vector2i(x, y), d)):
					return true
	return false


## Призрак места r (STYLE, раздел 6): форма блока цветом площади 35 % с белой рамкой. Место, куда
## нельзя, — красный призрак (GHOST_BAD). area — площадь несомого блока (-1 — площадь r).
func show_preview(r: Rect2i, valid: bool, area: int = -1) -> void:
	if not is_inside(r):
		clear_preview()
		return
	var a := area if area > 0 else r.size.x * r.size.y
	ghost.position = Vector2(r.position) * CELL
	ghost.size = Vector2(r.size) * CELL
	ghost.color = Palette.color_for(a) if valid else Palette.GHOST_BAD
	var mat := ghost.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("rect_size", ghost.size)
		mat.set_shader_parameter("px", _px)
		mat.set_shader_parameter("frame_alpha", 1.0 if valid else 0.6)
	ghost.visible = true


func clear_preview() -> void:
	ghost.visible = false
	if _snap_tween and _snap_tween.is_valid():
		_snap_tween.kill()
	ghost.scale = Vector2.ONE


## «Щелчок» нового допустимого места r (14.2): призрак появляется ×(1 + hop) и пружинит к 1 за time,
## число под ним (гнездо с магнитом) подпрыгивает. Вызывать после show_preview.
func snap_preview(r: Rect2i, hop: float, time: float) -> void:
	if not ghost.visible or hop <= 0.0 or time <= 0.0:
		return
	if _snap_tween and _snap_tween.is_valid():
		_snap_tween.kill()
	ghost.pivot_offset = ghost.size * 0.5
	ghost.scale = Vector2.ONE * (1.0 + hop)
	var j := Juice.of(self)
	_snap_tween = j.tween(self) if j != null else create_tween()
	_snap_tween.tween_property(ghost, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var n := _number_cell_in(r)
	if n.x >= 0:
		var cell := _cells[(r.position.y + n.y) * cols + r.position.x + n.x]
		if cell != null:
			cell.hop(hop, time)


## Ставит блок на место r; место и ход засчитаны сразу (ввод не ждёт анимацию). Перетаскивание (float_time = 0):
## блок летит из-под пальца за land_time (QUAD, EASE_IN). Подсказка (14.6g, 12.10, float_time > 0): блок сразу
## поднимается (тень «поднят») и летит из гнезда на место за float_time, с (TRANS_SINE, EASE_IN_OUT), вместе с ним
## летит искра (HintSpark); пока летит — поверх лотка и панелей (z_index FLOAT_Z). Отмена посреди полёта гасит
## твин (Tray.return_block → new_move_tween), смена уровня удаляет блок (setup).
func place_block(block: Block, r: Rect2i, float_time := 0.0) -> void:
	reparent_keep_global(block, blocks_root)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_occupant[y * cols + x] = block
	_blocks[block] = r
	block.modulate = Color.WHITE
	_sort_block(block, r)
	var n := _number_cell_in(r)
	var to := Vector2(r.position) * CELL
	if float_time <= 0.0:
		block.end_slide()
		block.number_cell = n
		block.set_lifted(false, 0.12)  # тень снова «лежит»
		var fly := Block.cfg().land_time
		var t := block.new_move_tween().set_parallel()
		t.tween_property(block, "position", to, fly).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(block, "scale", Vector2.ONE, fly).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.chain().tween_callback(_on_landed.bind(block, r))
		return
	block.z_index = FLOAT_Z
	var ft := block.new_move_tween()
	ft.tween_callback(_float_start.bind(block, n))
	ft.tween_property(block, "position", to, float_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ft.parallel().tween_property(block, "scale", Vector2.ONE, float_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ft.parallel().tween_callback(block.set_lifted.bind(false, 0.12)).set_delay(maxf(float_time - 0.12, 0.0))
	ft.tween_callback(_float_landed.bind(block, r))


## Подсказка: блок взлетает — поднимается (тень «поднят»), цифра — на клетку числа, и летит. Ещё выезжал в лоток
## (подсказка в начале уровня) — сразу встаёт на место и проявляется.
func _float_start(block: Block, number_cell: Vector2i) -> void:
	block.end_slide()
	block.number_cell = number_cell
	block.set_lifted(true, 0.12)


func _float_landed(block: Block, r: Rect2i) -> void:
	block.z_index = 0
	_on_landed(block, r)


## Блок block стоит (или летит) на месте r (HintSpark: ход ещё в силе). Без типа: после смены уровня в
## привязанном Callable — уже удалённый блок.
func holds(block: Variant, r: Rect2i) -> bool:
	return is_instance_valid(block) and _blocks.has(block) and _blocks[block] == r


## Удар о поле: сплющивание, число закрыто (поле принимает блок только на верное место) и сигнал landed
## (тряску, пыль и звук делает Game). Твины эффектов созданы до hit-stop удара — он их и останавливает.
func _on_landed(block: Block, r: Rect2i) -> void:
	if not is_instance_valid(block) or _blocks.get(block) != r:
		return
	block.squash()
	block.close_number()
	landed.emit(block, r)


## Клетка числа внутри r — относительно r (на ней блок рисует цифру); (-1, -1) — числа нет.
func _number_cell_in(r: Rect2i) -> Vector2i:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if is_inside(Rect2i(x, y, 1, 1)) and _values[y * cols + x] != 0:
				return Vector2i(x, y) - r.position
	return Vector2i(-1, -1)


## Блоки на поле рисуются по рядам (сверху вниз, слева направо): нижний перекрывает тень верхнего.
## Блок только что добавлен последним; дети blocks_root уже упорядочены.
func _sort_block(block: Block, r: Rect2i) -> void:
	for child in blocks_root.get_children():
		if child == block or not _blocks.has(child):
			continue
		var cr: Rect2i = _blocks[child]
		if cr.position.y > r.position.y or (cr.position.y == r.position.y and cr.position.x > r.position.x):
			blocks_root.move_child(block, child.get_index())
			return


func remove_block(block: Block) -> void:
	if not _blocks.has(block):
		return
	var r: Rect2i = _blocks[block]
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_occupant[y * cols + x] = null
	_blocks.erase(block)
	block.unmerge()
	block.z_index = 0  # сняли посреди полёта подсказки


func is_full() -> bool:
	for o in _occupant:
		if o == null:
			return false
	return true


## Строки и столбцы, которые стали полностью заполненными после установки r.
func completed_lines(r: Rect2i) -> Array[Rect2i]:
	var lines: Array[Rect2i] = []
	for y in range(r.position.y, r.end.y):
		var full := true
		for x in cols:
			if _occupant[y * cols + x] == null:
				full = false
				break
		if full:
			lines.append(Rect2i(0, y, cols, 1))
	for x in range(r.position.x, r.end.x):
		var full := true
		for y in rows:
			if _occupant[y * cols + x] == null:
				full = false
				break
		if full:
			lines.append(Rect2i(x, 0, 1, rows))
	return lines


## Волна света по закрытой линии line (14.4, LineFlash) через delay, с: из клеток блока from на этой линии (пусто —
## из середины линии) к концам; блоки линии вспыхивают (line_block_flash + combo_flash · power), когда до них
## доходит фронт. power — сила хода (Game: (линий − 1) + (серия − 1)).
func flash_line(line: Rect2i, delay: float, from := Rect2i(), power := 0) -> LineFlash:
	var fx := LINE_FLASH_SCENE.instantiate() as LineFlash
	fx_root.add_child(fx)
	fx.position = Vector2(line.position) * CELL
	fx.size = Vector2(line.size) * CELL
	var src := from.intersection(line) if from.has_area() else Rect2i()
	var origin := fx.size * 0.5
	if src.has_area():
		origin = (Vector2(src.position - line.position) + Vector2(src.size) * 0.5) * CELL
	fx.play(delay, origin, power)
	var c := Block.cfg()
	var amount := c.line_block_flash + c.combo_flash * maxi(power, 0)
	if GameState.reduce_motion:
		amount = minf(amount, c.reduced_wave)
	for b in _blocks:
		var br: Rect2i = _blocks[b]
		var part := br.intersection(line)
		if part.has_area():
			var mid := (Vector2(part.position - line.position) + Vector2(part.size) * 0.5) * CELL
			(b as Block).flash(delay + fx.arrival(mid), amount)
	return fx


## Победа (14.5, WinWave; числа — группа «Победа» в JuiceConfig): от последнего блока from (пусто — от середины поля)
## по всему полю расходится кольцо света; когда фронт доходит до середины блока, блок вспыхивает (win_block_flash),
## подпрыгивает (×(1 + win_block_pop); последний блок — нет: он ещё сплющивается от удара) и, если мозаика есть
## (win_mosaic; с 14.8e убрана), через win_merge_delay сходится с соседями (Block.merge).
## «Меньше движения»: вспышка не сильнее reduced_wave, без подскока.
func celebrate(from := Rect2i()) -> WinWave:
	var fx := WIN_WAVE_SCENE.instantiate() as WinWave
	fx_root.add_child(fx)
	fx.position = Vector2.ZERO
	fx.size = Vector2(cols, rows) * CELL
	var origin := fx.size * 0.5
	if from.has_area():
		origin = (Vector2(from.position) + Vector2(from.size) * 0.5) * CELL
	fx.play(0.0, origin)
	var c := Block.cfg()
	var amount := c.win_block_flash
	if GameState.reduce_motion:
		amount = minf(amount, c.reduced_wave)
	for b in _blocks:
		var br: Rect2i = _blocks[b]
		var block := b as Block
		var at := fx.arrival((Vector2(br.position) + Vector2(br.size) * 0.5) * CELL)
		block.flash(at, amount)
		if br != from and not GameState.reduce_motion and c.win_block_pop > 0.0:
			block.pop(c.win_block_pop, at)
		if c.win_mosaic:
			block.merge(at + c.win_merge_delay)
	return fx


static func reparent_keep_global(node: Control, new_parent: Control) -> void:
	var gpos := node.global_position
	var gscale := node.get_global_transform().get_scale()
	if node.get_parent():
		node.get_parent().remove_child(node)
	new_parent.add_child(node)
	var pscale := new_parent.get_global_transform().get_scale()
	node.scale = gscale / pscale
	node.global_position = gpos
