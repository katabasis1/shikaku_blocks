@tool
class_name Block
extends Control
## Прямоугольный блок. Один и тот же узел живёт в лотке, при перетаскивании
## и на поле. Размер задаётся свойством cells (в клетках) — его можно менять
## прямо в инспекторе, блок обновится в редакторе.
## Вид — шейдер «мармелад» (shaders/block.gdshader, docs/STYLE.md, раздел 5); тень рисует
## тот же шейдер в полях узла Shape (MARGIN_* с каждой стороны).
## Анимации (этап 14.2, STYLE 12) — на узле Visual, числа — theme/juice.tres (JuiceConfig, cfg()):
## подскок при взятии (hop), наклон в руке (tilt, ставит DragController), удар о поле (squash),
## «мотает головой» при промахе (refuse), поворот со смазом края (rotate_cells, униформа smear).
## Поворот Visual = вращение анимации (_spin) + наклон (tilt): они не мешают друг другу.
## Твины эффектов создаются через Juice (hit-stop их останавливает); перемещение (new_move_tween) и тень — нет.
## 14.3: число закрыто (close_number) — цифра вспыхивает и на миг сменяется галочкой (узел Visual/Check,
## shaders/check.gdshader), по клеткам от цифры расходится волна света (униформы glow / glow_r).
## 14.5: на победе блок сходится с соседями в мозаику (merge: униформа merge — зазор и скругление меньше, швов нет).
## 14.6b: в начале уровня и после хода блок выезжает в лоток (slide_in) — взять его можно и на лету.

## Размер клетки в пикселях — единый источник для блока и поля (Board.CELL ссылается сюда).
const CELL := 100.0
## Глубина губы (доля клетки): лицо блока выше нижнего края на DEPTH·CELL, цифра — на 0,6 этого.
const DEPTH := 0.075
## Поля узла Shape под тень, в логических px экрана: лежащий блок и поднятый (несомый).
## Хватает на смещение и размытие тени (2,2 размытия) с запасом.
const MARGIN_REST := 26.0
const MARGIN_LIFTED := 82.0
## Тени (STYLE, раздел 7): смещение и размытие в логических px экрана. В пиксели блока их
## переводит шейдер (униформа px = 1 / масштаб блока на экране), поэтому тень одинакова
## в лотке (клетка 46–78 px), на поле (клетка 104–186 px) и в руке.
const SHADOW_REST := Vector2(0.0, 7.0)
const SHADOW_LIFTED := Vector2(10.0, 34.0)
const BLUR_REST := 7.0
const BLUR_LIFTED := 20.0
## Поднятый блок крупнее лежащего.
const LIFT_SCALE := 1.08
## Обводка цифры (theme constant outline_size). Если на экране обводка выйдет толще или тоньше
## эталона A3B (0,042 C), править здесь.
const DIGIT_OUTLINE := 9
## Галочка «число закрыто» (14.3): рисует шейдер — в шрифте Nunito галочки нет.
const CHECK_SHADER: Shader = preload("res://shaders/check.gdshader")
## Цифра на смене с галочкой: уходит до этого масштаба и возвращается с него (с дожимом).
const CLOSE_DIGIT_MIN := 0.6
## Белая вспышка блока (flash) по умолчанию: победа; линия — JuiceConfig.line_block_flash и сила хода (14.4).
const FLASH_DEFAULT := 0.7

@export var cells: Vector2i = Vector2i(2, 1):
	set(value):
		cells = Vector2i(maxi(1, value.x), maxi(1, value.y))
		if is_node_ready():
			_apply()

@export var show_number: bool = true:
	set(value):
		show_number = value
		if is_node_ready():
			_apply()

## Клетка блока, на которой стоит число (её ставит поле); (-1, -1) — цифра по центру (лоток, в руке).
var number_cell := Vector2i(-1, -1):
	set(value):
		number_cell = value
		if is_node_ready():
			clear_close()  # блок сняли с поля (отмена хода) или поставили заново — галочки и света нет
			_apply()

@onready var visual: Control = $Visual
@onready var shape: ColorRect = $Visual/Shape
@onready var number_label: Label = $Visual/Number

var area: int:
	get:
		return cells.x * cells.y

## Свой цвет вместо цвета площади (закреплённый блок 19.3 — Palette.PINNED); прозрачный — цвет площади.
var fixed_color := Color.TRANSPARENT:
	set(value):
		fixed_color = value
		if is_node_ready():
			_apply()

## Блок поднят (его несут): тень выше и мягче, блок крупнее (scale задаёт DragController).
var lifted: bool = false
## Наклон в руке, рад (DragController, 14.2). Складывается с вращением анимаций (_spin).
var tilt: float = 0.0:
	set(value):
		tilt = value
		if is_node_ready():
			_apply_rotation()
## Вращение анимаций поворота и промаха, рад.
var _spin: float = 0.0
var _tilt_tween: Tween
var _lift_tween: Tween
var _fx_tween: Tween
var _move_tween: Tween
var _flash_tween: Tween
var _warn_tween: Tween
var _crack_tween: Tween
var _crack := 0.0
var _close_tween: Tween
var _glow_tween: Tween
var _merge_tween: Tween
var _merge: float = 0.0
## Выезд в лоток (14.6b, slide_in): идёт ли, откуда (единичный вектор), сдвиг сейчас, px экрана.
var _sliding := false
var _slide_dir := Vector2.DOWN
var _slide: float = 0.0
## Галочка (создаётся при первом закрытии числа) и сила света по клеткам сейчас (0 — нет).
var _check: ColorRect
var _glow: float = 0.0
## Пикселей блока в логическом px экрана (1 / масштаб на экране) — для тени и полей под неё.
var _px: float = 1.0


## Числа анимаций (theme/juice.tres) — тот же ресурс, что у узла Juice.
static func cfg() -> JuiceConfig:
	return Juice.shared_config()


func _ready() -> void:
	# Масштаб блока на экране меняется: лоток, подъём, поле, подгонка поля под экран.
	set_notify_transform(true)
	_px = _screen_px()
	_apply()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready():
		_update_px()


## 1 / масштаб блока на экране (глобальное преобразование — в логических px холста).
func _screen_px() -> float:
	var s := get_global_transform().get_scale().x
	return 1.0 / s if s > 0.01 else _px


## Масштаб на экране изменился больше чем на 2 % — тень и поля под неё пересчитать.
func _update_px() -> void:
	var px := _screen_px()
	if absf(px - _px) <= _px * 0.02:
		return
	_px = px
	var mat := shape.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("px", _px)
	var lifting := _lift_tween != null and _lift_tween.is_valid()
	_set_margin(MARGIN_LIFTED if (lifted or lifting) else MARGIN_REST)


func _apply() -> void:
	size = Vector2(cells) * CELL
	visual.pivot_offset = size * 0.5
	shape.color = fixed_color if fixed_color.a > 0.0 else Palette.color_for(area)
	var lift := DEPTH * CELL * 0.6
	var center := size * 0.5 - Vector2(0.0, lift)
	if number_cell.x >= 0 and number_cell.y >= 0 and number_cell.x < cells.x and number_cell.y < cells.y:
		number_label.position = Vector2(number_cell) * CELL - Vector2(0.0, lift)
		number_label.size = Vector2(CELL, CELL)
		center = (Vector2(number_cell) + Vector2(0.5, 0.5)) * CELL - Vector2(0.0, lift)
	else:
		number_label.position = Vector2(0.0, -lift)
		number_label.size = size
	var mat := shape.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("rect_size", size)
		mat.set_shader_parameter("cells", Vector2(cells))
		mat.set_shader_parameter("num_center", center if show_number else Vector2(-1000.0, -1000.0))
		mat.set_shader_parameter("px", _px)
	_set_margin(MARGIN_LIFTED if lifted else MARGIN_REST)
	number_label.text = str(area)
	number_label.visible = show_number
	number_label.add_theme_color_override("font_outline_color", Palette.block_digit_outline(area))
	number_label.add_theme_color_override("font_shadow_color", Palette.block_digit_shadow(area))
	number_label.add_theme_constant_override("outline_size", DIGIT_OUTLINE)
	number_label.add_theme_constant_override("shadow_outline_size", DIGIT_OUTLINE)


## Поля узла Shape под тень: m — в логических px, в пиксели блока переводит _px
## (шейдер знает поля через униформу margin).
func _set_margin(m_px: float) -> void:
	var m := m_px * _px
	shape.offset_left = -m
	shape.offset_top = -m
	shape.offset_right = m
	shape.offset_bottom = m
	var mat := shape.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("margin", m)


## Поднять блок (его взяли) или опустить (лёг в лоток или на поле): тень и поля под неё.
## Масштаб блока задаёт тот, кто его несёт (DragController, LIFT_SCALE).
func set_lifted(on: bool, duration: float = 0.12) -> void:
	if _lift_tween and _lift_tween.is_valid():
		_lift_tween.kill()
	lifted = on
	var mat := shape.material as ShaderMaterial
	if mat == null:
		return
	if on:
		_set_margin(MARGIN_LIFTED)
	var from_off: Vector2 = mat.get_shader_parameter("shadow_offset")
	var from_blur: float = mat.get_shader_parameter("shadow_blur")
	var from_col: Color = mat.get_shader_parameter("shadow_color")
	var to_off := SHADOW_LIFTED if on else SHADOW_REST
	var to_blur := BLUR_LIFTED if on else BLUR_REST
	var to_col := Palette.SHADE_LIFTED if on else Palette.SHADE
	if duration <= 0.0 or not is_inside_tree():
		_shadow_step(1.0, mat, from_off, to_off, from_blur, to_blur, from_col, to_col)
		if not on:
			_set_margin(MARGIN_REST)
		return
	_lift_tween = create_tween()
	_lift_tween.tween_method(_shadow_step.bind(mat, from_off, to_off, from_blur, to_blur, from_col, to_col),
			0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if not on:
		_lift_tween.tween_callback(_set_margin.bind(MARGIN_REST))


func _shadow_step(v: float, mat: ShaderMaterial, from_off: Vector2, to_off: Vector2,
		from_blur: float, to_blur: float, from_col: Color, to_col: Color) -> void:
	mat.set_shader_parameter("shadow_offset", from_off.lerp(to_off, v))
	mat.set_shader_parameter("shadow_blur", lerpf(from_blur, to_blur, v))
	mat.set_shader_parameter("shadow_color", from_col.lerp(to_col, v))


## Твин для перемещения/масштаба самого блока (предыдущий гасится).
func new_move_tween() -> Tween:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	return _move_tween


## Блок сейчас перемещается твином new_move_tween: возврат по дуге в слот, подъём, полёт на поле
## (Tray: дыхание лотка такой блок не трогает — им управляет твин).
func is_moving() -> bool:
	return _move_tween != null and _move_tween.is_valid() and _move_tween.is_running()


## Твин эффекта: через Juice (его останавливает hit-stop), вне игры (редактор, тест поля) — обычный.
func _effect_tween() -> Tween:
	var j: Juice = null if Engine.is_editor_hint() else Juice.of(self)
	return j.tween(self) if j != null else create_tween()


func _new_fx_tween() -> Tween:
	if _fx_tween and _fx_tween.is_valid():
		_fx_tween.kill()
	visual.scale = Vector2.ONE
	visual.position = Vector2.ZERO
	visual.modulate.a = 1.0  # выезд (slide_in) погашен: блок виден и на месте
	_sliding = false
	_slide = 0.0
	_set_spin(0.0)
	_set_smear(0.0)
	_fx_tween = _effect_tween()
	return _fx_tween


func _apply_rotation() -> void:
	visual.rotation = _spin + tilt


func _set_spin(v: float) -> void:
	_spin = v
	_apply_rotation()


## Смаз края (униформа smear шейдера), px блока: 0 — край чёткий.
func _set_smear(v: float) -> void:
	var mat := shape.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("smear", v)


## Наклон плавно к нулю за sec с (блок отпустили); 0 — сразу.
func settle_tilt(sec: float) -> void:
	if _tilt_tween and _tilt_tween.is_valid():
		_tilt_tween.kill()
	if sec <= 0.0 or is_zero_approx(tilt) or not is_inside_tree():
		tilt = 0.0
		return
	_tilt_tween = create_tween()
	_tilt_tween.tween_property(self, "tilt", 0.0, sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Взять (14.2): Visual вытягивается до pick_hop и пружинит обратно.
func hop() -> void:
	var c := cfg()
	var t := _new_fx_tween()
	t.tween_property(visual, "scale", c.pick_hop, c.pick_time * 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(visual, "scale", Vector2.ONE, c.pick_time * 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Удар о поле (14.2, STYLE 12): сплющивание ×land_squash и обратно с дожимом за squash_time.
func squash() -> void:
	var c := cfg()
	var t := _new_fx_tween()
	t.tween_property(visual, "scale", c.land_squash, c.squash_time * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(visual, "scale", Vector2.ONE, c.squash_time * 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Промах (14.2): блок «мотает головой» — качается до miss_wobble градусов, затухая. При «Меньше движения» — нет.
func refuse() -> void:
	if GameState.reduce_motion:
		return
	var c := cfg()
	var w := deg_to_rad(c.miss_wobble)
	var swings: Array[float] = [1.0, -0.7, 0.4, -0.15, 0.0]
	var t := _new_fx_tween()
	var prev := 0.0
	for k: float in swings:
		t.tween_method(_set_spin, prev, w * k, c.miss_time / swings.size()) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		prev = w * k


## Число закрыто (14.3, PLAN 4.4; числа — группа «Закрытое число» в JuiceConfig). Вызывает поле в миг удара.
## Цифра вспыхивает (×close_pop и светлее ×close_flash за close_pop_time), за close_swap сменяется галочкой,
## галочка видна close_hold и уступает место цифре — цифра остаётся: закрыто каждое число поля, стирать их нельзя.
## По клеткам от цифры за glow_time расходится волна света (при «Меньше движения» — нет).
func close_number() -> void:
	clear_close()
	if not show_number or number_cell.x < 0 or not is_inside_tree():
		return
	var c := cfg()
	var chk := _check_node()
	chk.position = number_label.position
	chk.size = number_label.size
	chk.pivot_offset = chk.size * 0.5
	chk.scale = Vector2.ONE * 0.5
	chk.modulate = Color(1.0, 1.0, 1.0, 0.0)
	chk.visible = true
	number_label.pivot_offset = number_label.size * 0.5
	var bright := Color(c.close_flash, c.close_flash, c.close_flash, 1.0)
	var back := c.close_swap * 1.5
	var t := _effect_tween()
	_close_tween = t
	# 1. Вспышка: цифра растёт и светлеет (обводка и тень — к светлому; белое белее не станет).
	t.tween_property(number_label, "scale", Vector2.ONE * c.close_pop, c.close_pop_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(number_label, "modulate", bright, c.close_pop_time)
	# 2. Цифра уходит, галочка выпрыгивает на её место.
	t.tween_property(number_label, "scale", Vector2.ONE * CLOSE_DIGIT_MIN, c.close_swap) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(number_label, "modulate:a", 0.0, c.close_swap)
	t.parallel().tween_property(chk, "modulate:a", 1.0, c.close_swap)
	t.parallel().tween_property(chk, "scale", Vector2.ONE, c.close_swap * 2.0) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 3. Галочка видна close_hold (с мига, когда проявилась целиком).
	t.tween_interval(maxf(c.close_hold - c.close_swap, 0.0))
	# 4. Галочка тает, цифра возвращается с дожимом.
	t.tween_property(chk, "modulate:a", 0.0, back)
	t.parallel().tween_property(chk, "scale", Vector2.ONE * 0.8, back).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(number_label, "modulate", Color.WHITE, back)
	t.parallel().tween_property(number_label, "scale", Vector2.ONE, c.close_swap * 2.5) \
			.from(Vector2.ONE * CLOSE_DIGIT_MIN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(_end_close)
	if GameState.reduce_motion or c.glow_strength <= 0.0 or c.glow_time <= 0.0:
		return
	_glow_tween = _effect_tween()
	_glow_tween.tween_method(_glow_step, 0.0, 1.0, c.glow_time)
	_glow_tween.tween_callback(_set_glow.bind(0.0, 0.0))


## Галочка и свет погашены, цифра — как была (отмена хода, новое закрытие).
func clear_close() -> void:
	for tw: Tween in [_close_tween, _glow_tween]:
		if tw != null and tw.is_valid():
			tw.kill()
	_close_tween = null
	_glow_tween = null
	_end_close()
	if _glow != 0.0:  # без нужды униформы не трогаем: в редакторе это пометило бы сцену изменённой
		_set_glow(0.0, 0.0)


func _end_close() -> void:
	if _check != null:
		_check.visible = false
	number_label.scale = Vector2.ONE
	number_label.modulate = Color.WHITE


## Закрытие числа ещё идёт (selftest).
func is_closing() -> bool:
	return _close_tween != null and _close_tween.is_running()


## Насколько видна галочка, 0…1 (selftest).
func check_alpha() -> float:
	return _check.modulate.a if _check != null and _check.visible else 0.0


## Сила света по клеткам сейчас (selftest).
func glow() -> float:
	return _glow


## Узел галочки (Visual/Check): поверх цифры, цвета обводки и тени — как у цифры этой площади.
func _check_node() -> ColorRect:
	if _check == null:
		_check = ColorRect.new()
		_check.name = "Check"
		_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_check.color = Color.WHITE
		var m := ShaderMaterial.new()
		m.shader = CHECK_SHADER
		_check.material = m
		visual.add_child(_check)
	var mat := _check.material as ShaderMaterial
	mat.set_shader_parameter("rect_size", number_label.size)
	mat.set_shader_parameter("outline", float(DIGIT_OUTLINE))
	mat.set_shader_parameter("outline_color", Palette.block_digit_outline(area))
	mat.set_shader_parameter("shadow_color", Palette.block_digit_shadow(area))
	return _check


## Шаг волны света, v = 0…1: фронт уходит от цифры за дальний угол блока, сила спадает к нулю.
func _glow_step(v: float) -> void:
	var c := cfg()
	var lift := DEPTH * CELL * 0.6
	var from := (Vector2(number_cell) + Vector2(0.5, 0.5)) * CELL - Vector2(0.0, lift)
	var reach := 0.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0.0), Vector2(0.0, size.y), size]:
		reach = maxf(reach, from.distance_to(corner))
	_set_glow(c.glow_strength * (1.0 - v), v * (reach + 0.3 * CELL))


func _set_glow(strength: float, radius: float) -> void:
	_glow = strength
	var mat := shape.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("glow", strength)
		mat.set_shader_parameter("glow_r", radius)


## Выезд в лоток (14.6b, PLAN 4.4: «блоки выезжают в лоток»; числа — группа «Появление и переходы»
## в JuiceConfig): через delay блок въезжает в слот со стороны dir (снизу в портрете, справа в альбоме — от края
## экрана) с intro_block_from px экрана за intro_block_time с пружиной (TRANS_BACK), проявляясь за первую треть
## пути. Едет Visual — сам блок уже в слоте, поэтому его можно взять или повернуть, пока он едет: любой новый
## эффект (подскок при взятии, поворот) гасит выезд (_new_fx_tween). «Меньше движения» — только проявление.
func slide_in(delay: float = 0.0, dir := Vector2.DOWN) -> void:
	var c := cfg()
	var time := maxf(c.intro_block_time, 0.01)
	var t := _new_fx_tween()
	_sliding = true
	_slide_dir = dir.normalized() if dir != Vector2.ZERO else Vector2.DOWN
	visual.modulate.a = 0.0
	if delay > 0.0:
		t.tween_interval(delay)
	if GameState.reduce_motion:
		t.tween_property(visual, "modulate:a", 1.0, time)
	else:
		_set_slide(c.intro_block_from)
		t.tween_property(visual, "modulate:a", 1.0, time * 0.35)
		t.parallel().tween_method(_set_slide, c.intro_block_from, 0.0, time) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void: _sliding = false)


## Выезд в лоток (slide_in) ещё идёт — сразу встать на место и проявиться. Подсказка (14.6g) взяла блок, пока он
## едет (начало уровня, вторая подсказка подряд): вплывать на поле он должен целиком, а не выезжать из-под края
## экрана посреди полёта. Остальные эффекты блока (поворот подсказки) не трогает.
func end_slide() -> void:
	if not _sliding:
		return
	if _fx_tween and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx_tween = null
	_sliding = false
	_set_slide(0.0)
	visual.modulate.a = 1.0


## Блок ещё выезжает в лоток (selftest).
func is_sliding() -> bool:
	return _sliding and _fx_tween != null and _fx_tween.is_valid()


## Сдвиг выезда сейчас, px экрана (0 — на месте; selftest).
func slide_offset() -> float:
	return _slide


func _set_slide(v: float) -> void:
	_slide = v
	visual.position = _slide_dir * (v * _px)


func pop(strength: float = 0.12, delay: float = 0.0) -> void:
	var t := _new_fx_tween()
	if delay > 0.0:
		t.tween_interval(delay)
	t.tween_property(visual, "scale", Vector2.ONE * (1.0 + strength), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(visual, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Поворот на 90° (14.2): быстрый, с дожимом (перелёт TRANS_BACK) и смазом края в начале.
func rotate_cells() -> void:
	cells = Vector2i(cells.y, cells.x)
	var c := cfg()
	var t := _new_fx_tween()
	_set_spin(-PI * 0.5)
	t.tween_method(_set_spin, -PI * 0.5, 0.0, c.rotate_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var smear := c.rotate_smear * CELL
	if smear > 0.0:
		_set_smear(smear)
		t.parallel().tween_method(_set_smear, smear, 0.0, c.rotate_time * 0.7) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func shake() -> void:
	var t := _new_fx_tween()
	for i in 4:
		t.tween_property(visual, "position:x", 14.0 if i % 2 == 0 else -14.0, 0.04)
	t.tween_property(visual, "position:x", 0.0, 0.04)


## Белая вспышка блока силой amount (0…1) через delay, с, гаснет за 0,45 с; твин — через Juice (hit-stop).
func flash(delay: float = 0.0, amount: float = FLASH_DEFAULT) -> void:
	var mat := shape.material as ShaderMaterial
	if mat == null:
		return
	# Блок на пересечении двух закрытых линий получает две вспышки подряд —
	# гасим предыдущую, чтобы твины не боролись за один параметр шейдера.
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = _effect_tween()
	if delay > 0.0:
		_flash_tween.tween_interval(delay)
	_flash_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("flash", v), amount, 0.0, 0.45)


## Мозаика на победе (14.5; числа — группа «Победа» в JuiceConfig): через delay, с, блок за win_merge_time сходится
## с соседями — зазор до win_merge_gap, скругление до win_merge_radius, швы между клетками гаснут (униформа merge).
## Твин — через Juice (hit-stop удара победы его останавливает).
func merge(delay: float = 0.0) -> void:
	var mat := shape.material as ShaderMaterial
	if mat == null:
		return
	var c := cfg()
	mat.set_shader_parameter("merge_gap", c.win_merge_gap)
	mat.set_shader_parameter("merge_radius", c.win_merge_radius)
	if _merge_tween and _merge_tween.is_valid():
		_merge_tween.kill()
	_merge_tween = _effect_tween()
	if delay > 0.0:
		_merge_tween.tween_interval(delay)
	_merge_tween.tween_method(_set_merge, merged(), 1.0, maxf(c.win_merge_time, 0.01)) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


## Обычный блок, без мозаики (блок снят с поля).
func unmerge() -> void:
	if _merge_tween and _merge_tween.is_valid():
		_merge_tween.kill()
	_set_merge(0.0)


## Насколько блок сошёлся в мозаику: 0…1 (униформа merge).
func merged() -> float:
	return _merge


func _set_merge(v: float) -> void:
	_merge = v
	var mat := shape.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("merge", v)


## Предупреждение «ход ведёт в тупик»: блок краснеет и трясётся.
func warn(delay: float = 0.0) -> void:
	if _warn_tween and _warn_tween.is_valid():
		_warn_tween.kill()
	visual.modulate = Color.WHITE
	_warn_tween = create_tween()
	if delay > 0.0:
		_warn_tween.tween_interval(delay)
	_warn_tween.tween_callback(shake)
	for _i in 2:
		_warn_tween.tween_property(visual, "modulate", Color(1.0, 0.55, 0.6), 0.12)
		_warn_tween.tween_property(visual, "modulate", Color.WHITE, 0.18)


## Сбрасывает визуальные эффекты предупреждения (например, при отмене хода).
func clear_warn() -> void:
	if _warn_tween and _warn_tween.is_valid():
		_warn_tween.kill()
	visual.modulate = Color.WHITE
	if _crack_tween and _crack_tween.is_valid():
		_crack_tween.kill()
	_set_crack(0.0)


## Тупик (14.6g): блок «трескается» — от цифры по лицу за dead_crack_time расходятся ломаные трещины (униформа
## crack). Трещина остаётся, пока блок на поле; снимает её clear_warn (отмена хода). «Меньше движения» — сразу целиком.
func crack() -> void:
	if _crack_tween and _crack_tween.is_valid():
		_crack_tween.kill()
	var c := cfg()
	if GameState.reduce_motion or c.dead_crack_time <= 0.0:
		_set_crack(1.0)
		return
	_crack_tween = _effect_tween()
	_crack_tween.tween_method(_set_crack, _crack, 1.0, c.dead_crack_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Насколько блок треснул: 0…1 (униформа crack; selftest).
func cracked() -> float:
	return _crack


func _set_crack(v: float) -> void:
	_crack = v
	var mat := shape.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("crack", v)


func vanish() -> void:
	var t := _new_fx_tween()
	t.tween_property(visual, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)
