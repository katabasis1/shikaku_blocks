class_name DragController
extends Node
## Перетаскивание блока из лотка на поле: нажатие на слот, «подъём» блока (×1,08, тень «поднят»),
## поворот на лету (ПКМ, колесо, R/пробел, второй палец), магнит к ближайшему
## допустимому месту и примерка каждой клетки (Fit).
## Ход не делает сам: верное место отдаёт сигналом dropped, его ставит Game;
## о неудаче (returned), цели под блоком (hover_changed) и повороте (rotated) узнаёт
## TutorialCoach. На уровнях 1..Tutorial.GUARD_LEVELS тупиковое место — тоже красное.
## Ввод и кадры приходят из Game (handle_input, follow_pointer), чтобы порядок
## обработки с рукой-обучением был явным.
## Импакт (14.2, STYLE 12; числа — theme/juice.tres): взятый блок подскакивает (Block.hop), едет за пальцем
## на пружине (лёгкое отставание — вес) и наклоняется по скорости (Block.tilt), над допустимым местом чуть
## притягивается к нему, новое допустимое место «щёлкает» (Board.snap_preview); промах — Block.refuse.
## Цель (призрак) всегда считается по пальцу, а не по отставшему блоку. «Меньше движения» — без пружины и наклона.

## Игрок нажал на блок в лотке.
signal pressed
## Блок отпущен на допустимое место: Game ставит его на поле.
signal dropped(block: Block, slot: int, rect: Rect2i)
## Блок отпущен мимо и вернулся в слот. issue — почему не встал (Tutorial.Issue),
## value — число под ним (для WRONG_SIZE).
signal returned(slot: int, issue: int, value: int)
## Цель под перетаскиваемым блоком сменилась: issue — Tutorial.Issue (OK — встанет,
## OUTSIDE — не над полем или перетаскивание кончилось). Подпись обучения объясняет причину.
signal hover_changed(issue: int, value: int)
## Игрок сам повернул блок (не квадратный): в лотке или на лету.
signal rotated

const DRAG_THRESHOLD := 10.0
## На таче блок поднимается над пальцем, чтобы его было видно.
const TOUCH_LIFT := 60.0
## Несомый блок непрозрачный и своего цвета всегда (STYLE, раздел 12): цвет — это площадь, подкраска
## путала бы (жёлтый 4 с розовым оттенком читался как оранжевый 3). «Нельзя» показывает только
## красный призрак на поле (Board.show_preview). DRAG_TINT_BAD убран 02.10 по срезу tools/shader_preview.py.
## Взять блок: ×Block.LIFT_SCALE от полевого масштаба за это время, тень — в «поднят».
const LIFT_TIME := 0.1
## Магнит: на сколько клеток блок притягивается к ближайшему допустимому месту.
const SNAP_RADIUS := 1.0
## Защита от лавины поворотов с тачпада/колеса.
const ROTATE_COOLDOWN_MS := 150

## Результат примерки блока в точку поля.
enum Fit { OUTSIDE, BAD, OK, DEAD_END }

var _game: Game
var _board: Board
var _tray: Tray
var _layer: Control
var _press_slot: int = -1
var _press_pos := Vector2.ZERO
var _dragging: Block = null
var _target := Rect2i()
var _target_fit: int = -1
var _target_issue: int = Tutorial.Issue.OUTSIDE
var _eval_cache: Dictionary = {}
var _is_touch: bool = false
var _last_rotate_ms: int = 0
var _cfg: JuiceConfig
## Пружина несомого блока: где он сейчас (глобальные координаты) и его скорость, px/с.
var _pos := Vector2.ZERO
var _vel := Vector2.ZERO


func setup(game: Game) -> void:
	_game = game
	_board = game.board
	_tray = game.tray
	_layer = game.drag_layer
	_cfg = Juice.shared_config()
	_tray.slot_input.connect(_on_slot_input)


## Палец или кнопка мыши держит блок (ещё до начала перетаскивания).
func is_busy() -> bool:
	return _dragging != null or _press_slot >= 0


## Блок уже «поднят» и едет за пальцем.
func is_dragging() -> bool:
	return _dragging != null


## Ввод из Game._input: поворот на лету, начало и конец перетаскивания.
func handle_input(event: InputEvent) -> void:
	# Поворот прямо во время перетаскивания: ПКМ, колесо, R/пробел, второй палец.
	if _dragging != null and _is_rotate_event(event):
		get_viewport().set_input_as_handled()
		_rotate_dragging()
		return
	if _press_slot < 0:
		return
	if event is InputEventMouseMotion:
		if _dragging == null and _pointer().distance_to(_press_pos) > DRAG_THRESHOLD:
			_begin_drag()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _dragging != null:
				_end_drag()
			else:
				_rotate_in_tray(_press_slot)
			_press_slot = -1


## Каждый кадр из Game._process: блок едет за пальцем, подсветка цели.
func follow_pointer() -> void:
	if _dragging != null:
		_update_drag(get_process_delta_time())


## Скорость несомого блока, px/с (пружина; для наклона и selftest).
func carry_velocity() -> Vector2:
	return _vel


## Бросить перетаскивание: блок возвращается в слот (новый уровень, пауза, потеря фокуса).
func cancel() -> void:
	if _dragging != null and _press_slot >= 0:
		_dragging.modulate = Color.WHITE
		_dragging.settle_tilt(_cfg.tilt_return)
		_tray.return_block(_dragging, _press_slot)  # там же тень снова «лежит»
	if _dragging != null:
		hover_changed.emit(Tutorial.Issue.OUTSIDE, 0)
	_dragging = null
	_press_slot = -1
	_target_fit = -1
	_board.clear_preview()
	_board.clear_emphasis()


func _on_slot_input(event: InputEvent, i: int) -> void:
	if _game.finished or is_busy():
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or _tray.blocks[i] == null:
		return
	pressed.emit()
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_press_slot = i
		_press_pos = _pointer()
		# Тач определяем по самому событию: касание эмулирует мышь с особым device.
		# is_touchscreen_available() врёт на ноутбуках с сенсорным экраном.
		_is_touch = mb.device == InputEvent.DEVICE_ID_EMULATION
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_rotate_in_tray(i)


## Поворот блока в лотке (тап или ПКМ по слоту).
func _rotate_in_tray(i: int) -> void:
	var b: Block = _tray.blocks[i]
	if b == null:
		return
	_tray.rotate_slot(i)
	if b.cells.x != b.cells.y:
		rotated.emit()


func _pointer() -> Vector2:
	return _layer.get_global_mouse_position()


func _is_rotate_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and (mb.button_index == MOUSE_BUTTON_RIGHT
				or mb.button_index == MOUSE_BUTTON_WHEEL_UP
				or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN)
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		return st.pressed and st.index > 0
	if event is InputEventKey:
		var key := event as InputEventKey
		return Desktop.key_pressed(key, KEY_R) or Desktop.key_pressed(key, KEY_SPACE)
	return false


func _begin_drag() -> void:
	var b: Block = _tray.blocks[_press_slot]
	if b == null:
		_press_slot = -1
		return
	_dragging = b
	_eval_cache.clear()
	_target_fit = -1
	Board.reparent_keep_global(b, _layer)
	b.modulate = Color.WHITE
	# Поднять: полевой масштаб ×LIFT_SCALE, тень одновременно переходит в «поднят».
	var t := b.new_move_tween()
	t.tween_property(b, "scale", _lifted_scale(), LIFT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	b.set_lifted(true, LIFT_TIME)
	b.settle_tilt(0.0)
	b.hop()
	_pos = b.global_position
	_vel = Vector2.ZERO
	_board.emphasize_area(b.area)
	Audio.play(Audio.PICK)
	_update_drag()


func _rotate_dragging() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_rotate_ms < ROTATE_COOLDOWN_MS:
		return
	_last_rotate_ms = now
	var b := _dragging
	if b.cells.x == b.cells.y:
		b.pop(0.08)
		return
	b.rotate_cells()
	_eval_cache.clear()
	_target_fit = -1  # форма изменилась — пересчитать цель
	Audio.play(Audio.ROTATE)
	rotated.emit()
	_update_drag()


## Масштаб поднятого блока: как на поле, ×Block.LIFT_SCALE.
func _lifted_scale() -> Vector2:
	return _board.get_global_transform().get_scale() * Block.LIFT_SCALE


func _drag_offset(block_size: Vector2) -> Vector2:
	var offset := block_size * 0.5
	if _is_touch:
		offset.y = block_size.y + TOUCH_LIFT
	return offset


## Кадр перетаскивания: цель под пальцем, призрак, положение блока. dt — время кадра (0 — без шага
## пружины: начало перетаскивания, поворот).
func _update_drag(dt: float = 0.0) -> void:
	var b := _dragging
	var mouse := _pointer()
	var current_size := b.size * b.scale
	var want := mouse - _drag_offset(current_size)

	# Привязку считаем по итоговому масштабу, чтобы не зависеть от анимации: центр поднятого
	# блока (×LIFT_SCALE) совпадает с центром места на поле (полевой масштаб).
	var lifted_size := b.size * _lifted_scale()
	var final_size := b.size * _board.get_global_transform().get_scale()
	var center := mouse - _drag_offset(lifted_size) + lifted_size * 0.5
	var fcell := _board.global_to_cell_f(center - final_size * 0.5)
	var base := Vector2i(roundi(fcell.x), roundi(fcell.y))
	var r := Rect2i(base, b.cells)
	var fit := _evaluate(r)
	if fit != Fit.OK:
		# Магнит: ближайшее допустимое место в радиусе SNAP_RADIUS клеток.
		var best_d := SNAP_RADIUS + 0.001
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var cand := Rect2i(base + Vector2i(dx, dy), b.cells)
				var d := fcell.distance_to(Vector2(cand.position))
				if d < best_d and _evaluate(cand) == Fit.OK:
					best_d = d
					r = cand
					fit = Fit.OK
	if r != _target or fit != _target_fit:
		_target = r
		_target_fit = fit
		if fit == Fit.OUTSIDE:
			_board.clear_preview()
		else:
			_board.show_preview(r, fit == Fit.OK, b.area)
			if fit == Fit.OK:
				_board.snap_preview(r, _cfg.snap_hop, _cfg.snap_time)
		_target_issue = _issue_of(r, fit)
		hover_changed.emit(_target_issue, _board.number_in(r))
	# Магнит: над допустимым местом блок смещается к нему на долю magnet_pull.
	if fit == Fit.OK and _cfg.magnet_pull > 0.0:
		want = want.lerp(_board.cell_center_global(r) - current_size * 0.5, _cfg.magnet_pull)
	_move_block(b, want, dt)


## Блок к точке want: пружина (вес, лёгкое отставание) и наклон по скорости; «Меньше движения» — сразу.
func _move_block(b: Block, want: Vector2, dt: float) -> void:
	if GameState.reduce_motion:
		_pos = want
		_vel = Vector2.ZERO
		b.global_position = want
		b.tilt = 0.0
		return
	if dt > 0.0:
		_spring_step(want, dt)
	b.global_position = _pos
	var k := 1.0 - exp(-dt * 3.0 / maxf(_cfg.tilt_return, 0.01))  # 95 % пути за tilt_return
	var aim := clampf(_vel.x * _cfg.tilt_per_speed, -_cfg.tilt_max, _cfg.tilt_max)
	b.tilt = lerpf(b.tilt, deg_to_rad(aim), k)


## Шаг пружины к want (полунеявный Эйлер, подшаги не длиннее 1/240 с; кадр длиннее 0,1 с — как 0,1 с).
func _spring_step(want: Vector2, dt: float) -> void:
	var w := _cfg.carry_stiffness
	var z := _cfg.carry_damping
	var dtc := minf(dt, 0.1)
	var steps := maxi(1, ceili(dtc * 240.0))
	var h := dtc / steps
	for _i in steps:
		_vel += ((want - _pos) * w * w - _vel * 2.0 * z * w) * h
		_pos += _vel * h


## Причина для подписи обучения: Tutorial.Issue по результату примерки.
func _issue_of(r: Rect2i, fit: int) -> int:
	match fit:
		Fit.OK:
			return Tutorial.Issue.OK
		Fit.DEAD_END:
			return Tutorial.Issue.DEAD_END
		Fit.BAD:
			return _board.rect_issue(r)
	return Tutorial.Issue.OUTSIDE


func _evaluate(r: Rect2i) -> int:
	if _eval_cache.has(r):
		return int(_eval_cache[r])
	var fit: int = Fit.OK
	if not _board.is_inside(r):
		fit = Fit.OUTSIDE
	elif not _board.check_rect(r):
		fit = Fit.BAD
	elif _game.level <= Tutorial.GUARD_LEVELS and _game.leads_to_dead_end(r, _dragging.cells):
		fit = Fit.DEAD_END
	_eval_cache[r] = fit
	return fit


func _end_drag() -> void:
	var b := _dragging
	var slot := _press_slot
	var fit := _target_fit
	var r := _target
	var issue: int = _target_issue if fit >= 0 else Tutorial.Issue.OUTSIDE
	_dragging = null
	_target_fit = -1
	_board.clear_preview()
	_board.clear_emphasis()
	b.modulate = Color.WHITE
	b.settle_tilt(_cfg.tilt_return)
	if fit == Fit.OK:
		hover_changed.emit(Tutorial.Issue.OUTSIDE, 0)
		dropped.emit(b, slot, r)
		return
	if fit == Fit.BAD or fit == Fit.DEAD_END:
		Audio.play(Audio.MISS)  # тихое «блюк» (15.1); «у-у» Error — только тупик
		b.refuse()  # «мотает головой» на пути в лоток
	_tray.return_block(b, slot)
	# Почему не встал, объясняет TutorialCoach (на уровнях со страховкой — подписью над полем).
	returned.emit(slot, issue, _board.number_in(r) if fit >= 0 else 0)
