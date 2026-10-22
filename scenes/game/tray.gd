class_name Tray
extends BoxContainer
## Лоток: три слота с блоками и очередь ещё не выданных блоков.
## В портрете слоты в ряд под полем, в альбоме — сверху вниз справа от поля
## (arrange вызывает Game.apply_layout, размеры — GameLayout).
## Сам ход не делает: нажатия на слоты отдаёт сигналом slot_input
## (их разбирает DragController), ставит блоки на поле Game.
## Полку (корпус, гнёзда, штриховка пустого гнезда; docs/STYLE.md, раздел 10) рисует сам Tray
## шейдером shaders/shelf.gdshader в _draw: корпус шире ряда гнёзд на shelf_pad с каждой стороны.
## Слоты — прозрачные Panel (стиль Slot пуст): их место на полке — гнёзда шейдера.
## Простой (14.6e): через idle_after с без ввода блоки в гнёздах едва «дышат» (breathe; Game зовёт его каждый кадр,
## а wake — на каждое нажатие). Дышит сам блок (scale и position вокруг середины гнезда), а не Visual: эффекты
## блока (подскок, поворот, выезд) живут на Visual и с дыханием не спорят.

## Нажатие или движение над слотом (gui_input слота).
signal slot_input(event: InputEvent, slot: int)

const BLOCK_SCENE: PackedScene = preload("res://scenes/game/block.tscn")
const SHELF_SHADER: Shader = preload("res://shaders/shelf.gdshader")
## Масштаб блока в лотке по умолчанию (портрет); длинные блоки (1×5, 2×5) ужимаются под слот.
const BLOCK_SCALE := GameLayout.TRAY_SCALE_PORTRAIT
## Запас по краям слота, в пикселях.
const SLOT_MARGIN := 12.0

var slots: Array[Control] = []
## Блок в каждом слоте или null.
var blocks: Array = [null, null, null]
## Размеры блоков, которые ещё не выданы в лоток.
var queue: Array[Vector2i] = []
## Масштаб блока в лотке сейчас (arrange).
var block_scale: float = BLOCK_SCALE
## Отступ корпуса полки от гнёзд, px (arrange; GameLayout.SHELF_PAD_*).
var shelf_pad: float = GameLayout.SHELF_PAD_PORTRAIT
## Материал полки (shelf.gdshader) — material самого Tray: на слоты и блоки он не действует.
var shelf_material: ShaderMaterial

var _shelf_dirty := false
## Простой (14.6e): секунд без ввода (wake обнуляет; пока дышать нельзя — стоит на нуле).
var idle_time := 0.0
## Сила дыхания по гнёздам, 0…1 (нарастает за idle_rise, гаснет за idle_fade), какой блок дышит в гнезде (id
## узла: удалённый блок не сравниваем как объект) и сдвинут ли его масштаб (в конце гашения — вернуть ровно масштаб
## гнезда). Часы дыхания, с — фаза синуса.
var _breath: Array[float] = [0.0, 0.0, 0.0]
var _breath_block: Array[int] = [0, 0, 0]
var _breath_applied: Array[bool] = [false, false, false]
var _breath_clock := 0.0


func _ready() -> void:
	slots.assign([$Slot0, $Slot1, $Slot2])
	shelf_material = ShaderMaterial.new()
	shelf_material.shader = SHELF_SHADER
	material = shelf_material
	for i in slots.size():
		slots[i].gui_input.connect(_on_slot_gui_input.bind(i))
		slots[i].resized.connect(_recenter.bind(i))
		# Блок пришёл в гнездо или ушёл из него (выдан, поднят, вернулся, удалён) — гнездо на полке
		# становится полным или пустым.
		slots[i].child_entered_tree.connect(_mark_shelf.unbind(1))
		slots[i].child_exiting_tree.connect(_mark_shelf.unbind(1))
		# Наведение мышью — только на слот с блоком.
		Desktop.add_hover(slots[i], func() -> bool: return blocks[i] != null)
	sort_children.connect(_mark_shelf)
	resized.connect(_mark_shelf)
	_mark_shelf()


## Раскладка: слоты сверху вниз (vertical_) или в ряд, размер слота, зазор, масштаб блоков,
## отступ полки от гнёзд. Блоки в слотах встают по центру сразу и ещё раз, когда контейнер
## раздаст слотам новый размер.
func arrange(vertical_: bool, slot_size: Vector2, separation: int, scale_: float,
		pad: float = GameLayout.SHELF_PAD_PORTRAIT) -> void:
	vertical = vertical_
	add_theme_constant_override(&"separation", separation)
	block_scale = scale_
	shelf_pad = pad
	for i in slots.size():
		slots[i].custom_minimum_size = slot_size
		_recenter(i)
	_mark_shelf()


## Корпус полки в координатах Tray: ряд гнёзд плюс shelf_pad со всех сторон.
func shelf_rect() -> Rect2:
	return Rect2(Vector2(-shelf_pad, -shelf_pad), size + Vector2(2.0, 2.0) * shelf_pad)


## Гнездо i пустое: блока нет или его сейчас несут (он на слое перетаскивания).
func is_slot_empty(i: int) -> bool:
	var b: Block = blocks[i]
	return b == null or b.get_parent() != slots[i] or b.is_queued_for_deletion()


## Униформы полки по нынешним слотам и блокам и перерисовка. Вызывается отложенно (_mark_shelf):
## к этому времени контейнер уже расставил слоты, а поднятый блок — на слое перетаскивания.
func update_shelf() -> void:
	_shelf_dirty = false
	if shelf_material == null:
		return
	var r := shelf_rect()
	shelf_material.set_shader_parameter(&"shelf_size", r.size)
	var empty := Vector3.ZERO
	for i in slots.size():
		var s := slots[i]
		shelf_material.set_shader_parameter(StringName("well%d" % i),
				Vector4(s.position.x - r.position.x, s.position.y - r.position.y, s.size.x, s.size.y))
		empty[i] = 1.0 if is_slot_empty(i) else 0.0
	shelf_material.set_shader_parameter(&"well_empty", empty)
	queue_redraw()


func _mark_shelf() -> void:
	if _shelf_dirty:
		return
	_shelf_dirty = true
	update_shelf.call_deferred()


func _draw() -> void:
	draw_rect(shelf_rect(), Color.WHITE)


## Новый уровень: старые блоки убираются, очередь — pieces, слоты заполняются: блоки выезжают по одному
## (14.6b: слот i — через intro_block_start + intro_block_step · i, JuiceConfig).
func setup(pieces: Array) -> void:
	for i in blocks.size():
		if blocks[i] != null:
			(blocks[i] as Block).queue_free()
			blocks[i] = null
	queue.assign(pieces)
	_reset_breath()
	var c := Block.cfg()
	for i in blocks.size():
		fill_slot(i, c.intro_block_start + i * c.intro_block_step)


## Откуда блоки выезжают в лоток (14.6b): в портрете — снизу, в альбоме (слоты столбиком справа от поля) —
## справа, от края экрана.
func slide_dir() -> Vector2:
	return Vector2.RIGHT if vertical else Vector2.DOWN


## Выдаёт в слот i следующий блок из очереди (он выезжает через delay, Block.slide_in).
## false — очередь пуста, слот остаётся пустым.
func fill_slot(i: int, delay: float) -> bool:
	if queue.is_empty():
		blocks[i] = null
		return false
	var b := BLOCK_SCENE.instantiate() as Block
	slots[i].add_child(b)
	b.cells = queue.pop_front()
	blocks[i] = b
	_place_in_slot(b, i, false)
	b.slide_in(delay, slide_dir())
	return true


## Блок из слота i поставлен на поле — слот освобождается (его заполнит fill_slot).
func clear_slot(i: int) -> void:
	blocks[i] = null


## Блок b возвращается в слот i (ошибочный ход 20.1a, снятый ход). drawn — после хода в слот был выдан
## новый блок: он уходит обратно в начало очереди.
func put_back(b: Block, i: int, drawn: bool) -> void:
	if drawn:
		var current: Block = blocks[i]
		if current != null:
			queue.push_front(current.cells)
			current.vanish()
	blocks[i] = b
	return_block(b, i)


## Блок, который несли или сняли с поля, возвращается в свой слот по дуге (14.2: return_time,
## высота — return_arc от пути, не ниже return_arc_min; в конце — лёгкий перелёт и обратно).
func return_block(b: Block, i: int) -> void:
	Board.reparent_keep_global(b, slots[i])
	b.number_cell = Vector2i(-1, -1)  # в лотке цифра по центру блока
	b.set_lifted(false, 0.2)
	_place_in_slot(b, i, true)


## Поворот блока прямо в лотке (тап или ПКМ по слоту).
func rotate_slot(i: int) -> void:
	var b: Block = blocks[i]
	if b == null:
		return
	if b.cells.x == b.cells.y:
		b.pop(0.08)  # квадрат поворачивать бессмысленно — лёгкий отклик без звука
		return
	b.rotate_cells()
	_place_in_slot(b, i, false)
	Audio.play(Audio.ROTATE)


## Размеры всех ещё не поставленных блоков: очередь, затем лоток.
func remaining_cells() -> Array[Vector2i]:
	var res: Array[Vector2i] = []
	res.append_array(queue)
	for b in blocks:
		if b != null:
			res.append((b as Block).cells)
	return res


func remaining_count() -> int:
	var n := queue.size()
	for b in blocks:
		if b != null:
			n += 1
	return n


## В лотке есть блоки, но ни один никуда на поле не встаёт.
func is_stuck(board: Board) -> bool:
	var has_piece := false
	for b in blocks:
		if b == null:
			continue
		has_piece = true
		if board.can_fit_anywhere((b as Block).cells):
			return false
	return has_piece


## Первый блок лотка, которому есть свободное место в решении rects:
## {slot, rect} или {}, если такого нет. upright_first — сначала искать ходы
## без поворота (рука-обучение: сперва показать простое перетаскивание).
func find_move(rects: Array, board: Board, upright_first: bool = false) -> Dictionary:
	for pass_no in (2 if upright_first else 1):
		var allow_rotated: bool = not upright_first or pass_no == 1
		for i in blocks.size():
			var b: Block = blocks[i]
			if b == null:
				continue
			for item in rects:
				var r: Rect2i = item
				var fits := r.size == b.cells or (allow_rotated and r.size == Vector2i(b.cells.y, b.cells.x))
				if fits and board.check_rect(r):
					return {"slot": i, "rect": r}
	return {}


## Ввод, после которого лоток не «простаивает» (14.6e): нажатие (палец, кнопка мыши или колесо, клавиша, кнопка
## геймпада) или ведение с нажатой кнопкой. Курсор, который просто ходит над игрой, — не ввод: это ещё не ход.
static func is_activity(event: InputEvent) -> bool:
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey \
			or event is InputEventJoypadButton:
		return event.is_pressed() and not event.is_echo()
	if event is InputEventScreenDrag:
		return true
	var mm := event as InputEventMouseMotion
	return mm != null and mm.button_mask != 0


## Игрок что-то сделал (Game._input, is_activity): простой — заново, дыхание мягко гаснет за idle_fade.
func wake() -> void:
	idle_time = 0.0


## Дыхание лотка в простое (14.6e, PLAN 4.4: «блоки в лотке едва дышат»; числа — группа «Появление и переходы»
## в JuiceConfig). Каждый кадр из Game._process; allowed — дышать можно (игра идёт: не победа, не пауза, не тупик,
## блок не держат, рука-обучение не показывает; Game._can_breathe). Через idle_after с простоя каждый блок в гнезде
## дышит: масштаб ×(1 + idle_breath · сила · sin(2π (t − idle_phase · i) / idle_period)) вокруг середины гнезда;
## сила нарастает за idle_rise, после касания (wake) или запрета гаснет за idle_fade — и блок встаёт ровно в
## масштаб гнезда. Блок, который едет (выезд в лоток, возврат по дуге) или не в гнезде (его несут, он на поле), не
## трогаем — им управляет его твин. «Меньше движения» — без дыхания.
func breathe(delta: float, allowed: bool) -> void:
	var c := Block.cfg()
	idle_time = idle_time + delta if allowed else 0.0
	var on := allowed and idle_time >= c.idle_after and not GameState.reduce_motion \
			and c.idle_breath > 0.0 and c.idle_period > 0.0
	var any := false
	for i in slots.size():
		var b: Block = blocks[i]
		var id := b.get_instance_id() if b != null else 0
		if id != _breath_block[i]:  # в гнезде другой блок — его дыхание с нуля
			_breath_block[i] = id
			_breath[i] = 0.0
			_breath_applied[i] = false
		if not _is_calm(i):
			_breath[i] = 0.0
			_breath_applied[i] = false
			continue
		if on:
			_breath[i] = move_toward(_breath[i], 1.0, delta / maxf(c.idle_rise, 0.01))
		else:
			_breath[i] = move_toward(_breath[i], 0.0, delta / maxf(c.idle_fade, 0.01))
		if _breath[i] > 0.0:
			any = true
			var wave := sin(TAU * (_breath_clock - c.idle_phase * i) / c.idle_period)
			_set_breath(b, i, 1.0 + c.idle_breath * smoothstep(0.0, 1.0, _breath[i]) * wave)
			_breath_applied[i] = true
		elif _breath_applied[i]:
			_breath_applied[i] = false
			_set_breath(b, i, 1.0)
	_breath_clock = _breath_clock + delta if (any or on) else 0.0


## Сила дыхания блока в гнезде i сейчас, 0…1 (selftest).
func breath_level(i: int) -> float:
	return _breath[i] if i >= 0 and i < _breath.size() else 0.0


## Масштаб блока гнезда i относительно масштаба гнезда сейчас (1 — не дышит; selftest).
func breath_scale(i: int) -> float:
	var b: Block = blocks[i]
	if b == null or b.get_parent() != slots[i]:
		return 1.0
	var k := _slot_scale(b, slots[i])
	return b.scale.x / k if k > 0.0 else 1.0


## Хоть один блок лотка сейчас дышит (selftest).
func is_breathing() -> bool:
	for v in _breath:
		if v > 0.0:
			return true
	return false


## Блок гнезда i лежит в покое: он в своём гнезде, не уходит, не едет (выезд, дуга возврата, подъём).
func _is_calm(i: int) -> bool:
	var b: Block = blocks[i]
	return b != null and b.get_parent() == slots[i] and not b.is_queued_for_deletion() \
			and not b.is_moving() and not b.is_sliding()


## Блок гнезда i — масштаб гнезда ×f, середина — в середине гнезда (масштаб гнезда считаем каждый раз:
## блок могли повернуть, гнездо — поменять размер).
func _set_breath(b: Block, i: int, f: float) -> void:
	var slot := slots[i]
	var k := _slot_scale(b, slot) * f
	b.scale = Vector2.ONE * k
	b.position = (slot.size - b.size * k) * 0.5


## Новый уровень: простоя и дыхания нет (старые блоки удаляются, их масштаб не важен).
func _reset_breath() -> void:
	idle_time = 0.0
	_breath_clock = 0.0
	for i in _breath.size():
		_breath[i] = 0.0
		_breath_block[i] = 0
		_breath_applied[i] = false


func _on_slot_gui_input(event: InputEvent, i: int) -> void:
	slot_input.emit(event, i)


func _place_in_slot(b: Block, i: int, animate: bool) -> void:
	var slot := slots[i]
	var k := _slot_scale(b, slot)
	var target_scale := Vector2.ONE * k
	var target_pos := (slot.size - b.size * k) * 0.5
	if animate:
		var c := Block.cfg()
		var from_pos := b.position
		var dist := from_pos.distance_to(target_pos)
		var lift := maxf(dist * c.return_arc, c.return_arc_min) if dist > 1.0 else 0.0
		# Квадратичная кривая Безье: контрольная точка на 2·lift от середины поперёк пути — вершина дуги
		# на lift. Дуга выгибается вверх, а путь почти отвесный (с поля в лоток) — вбок, к краю экрана,
		# с которого блок ближе: иначе «дуга» вышла бы прямой с разгоном.
		var ctrl := (from_pos + target_pos) * 0.5 + _arc_normal(b, from_pos, target_pos) * (2.0 * lift)
		var t := b.new_move_tween()
		t.tween_method(_arc_step.bind(b, from_pos, ctrl, target_pos, b.scale, target_scale), 0.0, 1.0,
				c.return_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		b.new_move_tween().kill()
		b.scale = target_scale
		b.position = target_pos
	# Блок выставлен заново (поворот, новый размер гнезда, возврат) — дыхание в гнезде начинается с нуля.
	if i < _breath.size():
		_breath[i] = 0.0
		_breath_applied[i] = false


## Куда выгибается дуга возврата (единичный вектор поперёк пути from → to, координаты слота): вверх; путь
## почти отвесный (меньше 30° от вертикали) — вбок, в сторону от середины экрана.
func _arc_normal(b: Block, from_pos: Vector2, to_pos: Vector2) -> Vector2:
	var chord := to_pos - from_pos
	if chord.length() < 1.0:
		return Vector2.UP
	var n := chord.orthogonal().normalized()
	if n.y > 0.0:
		n = -n
	if absf(n.y) < 0.5:  # путь почти отвесный: n почти горизонтален — от середины экрана наружу
		var mid_x := get_viewport_rect().size.x * 0.5 if is_inside_tree() else 0.0
		var side := signf(b.get_global_transform().get_origin().x - mid_x)
		if side == 0.0:
			side = 1.0
		if signf(n.x) != side:
			n = -n
	return n


## Точка дуги возврата при t (TRANS_BACK заходит чуть за 1 — перелёт по касательной и обратно).
func _arc_step(t: float, b: Block, p0: Vector2, p1: Vector2, p2: Vector2, s0: Vector2, s1: Vector2) -> void:
	var u := 1.0 - t
	b.position = p0 * (u * u) + p1 * (2.0 * u * t) + p2 * (t * t)
	b.scale = s0.lerp(s1, clampf(t, 0.0, 1.0))


func _slot_scale(b: Block, slot: Control) -> float:
	var k := block_scale
	if slot.size.x > SLOT_MARGIN and b.size.x > 0.0:
		k = minf(k, (slot.size.x - SLOT_MARGIN) / b.size.x)
	if slot.size.y > SLOT_MARGIN and b.size.y > 0.0:
		k = minf(k, (slot.size.y - SLOT_MARGIN) / b.size.y)
	return k


## Слот поменял размер — блок заново по центру. Блок, который сейчас несут
## (он на слое перетаскивания, а не в слоте), не трогаем.
func _recenter(i: int) -> void:
	var b: Block = blocks[i]
	if b != null and b.get_parent() == slots[i]:
		_place_in_slot(b, i, false)
