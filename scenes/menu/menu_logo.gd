class_name MenuLogo
extends Control
## Логотип главного меню (07.10): только графика, без надписи. Решённое мини-поле 4×3 из блоков игры
## (block.tscn): по краям тройки 1×3, внизу посередине четвёрка 2×2, а двойка 2×1 (Hero) висит над своим местом,
## как блок в руке игрока, — с тенью «поднят», наклоном и масштабом LIFT_SCALE. За полем — свечение и медленные
## лучи (win_rays.gdshader, узел Halo), вокруг — мерцающие искры (LogoSparkles). Поле симметрично, логотип —
## прямоугольник SIZE по центру колонны (STYLE 11.1).
## Жизнь (STYLE 11.1, «Движение»): на входе блоки по одному падают сверху (Block.slide_in), свечение проявляется;
## двойка парит (вверх-вниз на BOB, покачивание ±SWAY); через HOVER_TIME с падает на место — сплющивание, волна
## «пульса» и вспышек по соседям, логотип вздрагивает, искры и свечение вспыхивают — через HOLD_TIME с снова
## поднимается. Касание (клик) логотипа — посадка сразу и со звуком постановки (уже на месте — ещё удар).
## «Меньше движения»: всё стоит, двойка над местом, лучи не вращаются; касание — только звук и вспышка.
## Блоки — в LogoBlocks (menu.tscn) в клетках Block.CELL; масштаб CELL / Block.CELL от левого верхнего угла (pivot 0),
## двойка — последний ребёнок (рисуется поверх соседей, пока парит).

const RAYS_SHADER: Shader = preload("res://shaders/win_rays.gdshader")

## Клетка логотипа на экране, px, и поле в клетках: прямоугольник логотипа — GRID · CELL (480×360).
const CELL := 120.0
const GRID := Vector2i(4, 3)
## Двойка над местом: выше на HOVER_UP px блока, наклон HOVER_TILT, масштаб Block.LIFT_SCALE (как в руке).
const HOVER_UP := 50.0
const HOVER_TILT := 0.105            # 6°
## Парение: вверх-вниз на BOB px блока с периодом BOB_PERIOD с; покачивание ±SWAY рад — вдвое медленнее.
const BOB := 7.0
const BOB_PERIOD := 2.4
const SWAY := 0.026                  # 1,5°
## Цикл: парит HOVER_TIME с (первый раз — FIRST_HOVER с после входа), падает за DROP_TIME с, лежит HOLD_TIME с,
## поднимается за LIFT_TIME с (TRANS_BACK).
const HOVER_TIME := 3.6
const FIRST_HOVER := 2.2
const DROP_TIME := 0.2
const HOLD_TIME := 1.0
const LIFT_TIME := 0.5
## Посадка: вспышка двойки LAND_FLASH, соседи — «пульс» ×(1 + WAVE_POP) и вспышка WAVE_FLASH волной от двойки
## (четвёрка через WAVE_STEP с, тройки через 2·WAVE_STEP); логотип вздрагивает ×THUMP (0,07 с туда, 0,25 обратно).
const LAND_FLASH := 0.6
const WAVE_POP := 0.07
const WAVE_FLASH := 0.35
const WAVE_STEP := 0.05
const THUMP := 1.03
## Всплеск искр и свечения при посадке: 1 → 0 за PULSE_TIME с.
const PULSE_TIME := 0.6
## Вход: блоки падают сверху (Block.slide_in, вверх) по одному — через INTRO_DELAY + INTRO_STEP · i с
## (тройка слева, четвёрка, тройка справа, двойка); свечение и искры проявляются за INTRO_FADE с.
const INTRO_DELAY := 0.2
const INTRO_STEP := 0.09
const INTRO_FADE := 0.5
## Свечение и лучи (Halo): квадрат 2·HALO_R с центром в середине логотипа + HALO_SHIFT; лучей HALO_RAYS, белые
## HALO_RAY_ALPHA, гаснут к HALO_R; свечение — эллипс HALO_GLOW с размытием HALO_BLUR, цвет HALO_COLOR;
## поворот HALO_SPIN рад/с (оборот за 60 с). Всплеск посадки — свечение ярче на HALO_PULSE своей альфы.
const HALO_R := 400.0
const HALO_SHIFT := Vector2(0.0, -20.0)
const HALO_RAYS := 14.0
const HALO_RAY_ALPHA := 0.11
const HALO_GLOW := Vector2(300.0, 230.0)
const HALO_BLUR := 55.0
const HALO_COLOR := Color(1.0, 0.88, 1.0, 0.42)
const HALO_SPIN := 0.1047
const HALO_PULSE := 0.5

@onready var blocks_root: Control = $LogoBlocks
@onready var block_left: Block = $LogoBlocks/Block3L
@onready var hero: Block = $LogoBlocks/Block2
@onready var block_four: Block = $LogoBlocks/Block4
@onready var block_right: Block = $LogoBlocks/Block3R

var halo: ColorRect
var sparkles: LogoSparkles
## 1 — двойка над местом, 0 — на месте.
var hover := 1.0
## Двойка лежит на месте (ждёт подъёма).
var landed := false
var _home := {}          # Block -> место (левый верх) в LogoBlocks
var _clock := 0.0        # часы парения, с
var _wait := FIRST_HOVER # до следующего шага цикла, с
var _pulse := 0.0
var _still := false      # «Меньше движения»: всё стоит
var _tween: Tween
var _thump_tween: Tween


func _ready() -> void:
	pivot_offset = size * 0.5
	blocks_root.pivot_offset = Vector2.ZERO
	blocks_root.scale = Vector2.ONE * (CELL / Block.CELL)
	for b in blocks():
		_home[b] = b.position
	hero.pivot_offset = hero.size * 0.5
	hero.set_lifted(true, 0.0)
	halo = _make_halo()
	add_child(halo)
	move_child(halo, 0)
	sparkles = LogoSparkles.new()
	sparkles.name = "Sparkles"
	sparkles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sparkles.size = size
	add_child(sparkles)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_gui_input)
	_still = GameState.reduce_motion
	_apply_still()
	_place_hero()
	if not _still:
		_intro()


## Блоки логотипа: тройка слева, двойка, четвёрка, тройка справа.
func blocks() -> Array[Block]:
	var list: Array[Block] = [block_left, hero, block_four, block_right]
	return list


## Место блока в LogoBlocks (левый верх, px блока): двойка в полёте стоит не на нём (selftest).
func home(b: Block) -> Vector2:
	var at: Vector2 = _home.get(b, b.position)
	return at


func _make_halo() -> ColorRect:
	var r := ColorRect.new()
	r.name = "Halo"
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Узел — с запасом под лучи (HALO_R) и под размытый край свечения (HALO_GLOW + 2σ): края не видно.
	var half := Vector2(maxf(HALO_R, HALO_GLOW.x + 2.0 * HALO_BLUR), maxf(HALO_R, HALO_GLOW.y + 2.0 * HALO_BLUR))
	r.size = half * 2.0
	r.position = size * 0.5 + HALO_SHIFT - half
	r.pivot_offset = half
	var m := ShaderMaterial.new()
	m.shader = RAYS_SHADER
	m.set_shader_parameter("rect_size", r.size)
	m.set_shader_parameter("center", half)
	m.set_shader_parameter("radius", HALO_R)
	m.set_shader_parameter("rays", HALO_RAYS)
	m.set_shader_parameter("ray_alpha", HALO_RAY_ALPHA)
	m.set_shader_parameter("glow_radius", HALO_GLOW)
	m.set_shader_parameter("glow_blur", HALO_BLUR)
	m.set_shader_parameter("glow_color", HALO_COLOR)
	r.material = m
	return r


func _intro() -> void:
	var order: Array[Block] = [block_left, block_four, block_right, hero]
	for i in order.size():
		order[i].slide_in(INTRO_DELAY + INTRO_STEP * i, Vector2.UP)
	halo.modulate.a = 0.0
	sparkles.modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(halo, "modulate:a", 1.0, INTRO_FADE).set_delay(INTRO_DELAY)
	t.tween_property(sparkles, "modulate:a", 1.0, INTRO_FADE).set_delay(INTRO_DELAY + INTRO_STEP * order.size())


func _process(delta: float) -> void:
	if GameState.reduce_motion != _still:
		_still = GameState.reduce_motion
		_apply_still()
	if _still:
		return
	_clock += delta
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta / PULSE_TIME)
		_apply_pulse()
	if _tween == null or not _tween.is_running():
		_wait -= delta
		if _wait <= 0.0:
			if landed:
				_lift()
			else:
				_drop(false)
	_place_hero()


## «Меньше движения» включили или выключили: всё на места — двойка над своим местом, без всплеска;
## лучи стоят или вращаются, искры не мерцают или мерцают.
func _apply_still() -> void:
	(halo.material as ShaderMaterial).set_shader_parameter("spin", 0.0 if _still else HALO_SPIN)
	sparkles.still = _still
	sparkles.queue_redraw()
	if not _still:
		return
	_kill(_tween)
	_kill(_thump_tween)
	scale = Vector2.ONE
	hover = 1.0
	landed = false
	_wait = HOVER_TIME
	_pulse = 0.0
	_apply_pulse()
	hero.set_lifted(true, 0.0)
	_place_hero()


## Двойка: место + подъём на HOVER_UP и парение (доля hover), наклон и масштаб «в руке».
func _place_hero() -> void:
	var bob := 0.0
	var sway := 0.0
	if not _still:
		var ph := _clock * TAU / BOB_PERIOD
		bob = sin(ph) * BOB
		sway = sin(ph * 0.5) * SWAY
	hero.position = home(hero) + Vector2(0.0, (bob - HOVER_UP) * hover)
	hero.tilt = (HOVER_TILT + sway) * hover
	hero.scale = Vector2.ONE * lerpf(1.0, Block.LIFT_SCALE, hover)


func _set_hover(v: float) -> void:
	hover = v
	_place_hero()


## Посадка двойки: падает за DROP_TIME (с текущей высоты — быстрее), на месте — удар (_land).
func _drop(by_player: bool) -> void:
	_kill(_tween)
	_tween = create_tween()
	_tween.tween_method(_set_hover, hover, 0.0, maxf(DROP_TIME * hover, 0.01)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_land.bind(by_player))


func _land(by_player: bool) -> void:
	landed = true
	_wait = HOLD_TIME
	hero.set_lifted(false, 0.08)
	hero.squash()
	hero.flash(0.0, LAND_FLASH)
	block_four.pop(WAVE_POP, WAVE_STEP)
	block_four.flash(WAVE_STEP, WAVE_FLASH)
	for b in [block_left, block_right]:
		(b as Block).pop(WAVE_POP, WAVE_STEP * 2.0)
		(b as Block).flash(WAVE_STEP * 2.0, WAVE_FLASH)
	_pulse = 1.0
	_apply_pulse()
	_kill(_thump_tween)
	_thump_tween = create_tween()
	_thump_tween.tween_property(self, "scale", Vector2.ONE * THUMP, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_thump_tween.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if by_player:
		Audio.play(Audio.PLACE, 0.08)
		Audio.play_pitched(Audio.NOTE, Audio.place_pitch(hero.area, 0))


## Подъём: тень «поднят», «взять» (Block.hop) и вверх с перелётом за LIFT_TIME.
func _lift() -> void:
	_kill(_tween)
	landed = false
	_wait = HOVER_TIME
	hero.set_lifted(true, LIFT_TIME * 0.5)
	hero.hop()
	_tween = create_tween()
	_tween.tween_method(_set_hover, hover, 1.0, LIFT_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Всплеск посадки: искры крупнее и ярче, свечение ярче и чуть шире.
func _apply_pulse() -> void:
	sparkles.burst = _pulse
	var k := 1.0 + HALO_PULSE * _pulse
	(halo.material as ShaderMaterial).set_shader_parameter("glow_color",
			Color(HALO_COLOR, minf(1.0, HALO_COLOR.a * k)))
	halo.scale = Vector2.ONE * (1.0 + 0.05 * _pulse)


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	tap()


## Касание логотипа: посадка сразу (двойка уже на месте — ещё удар) со звуком постановки.
func tap() -> void:
	if _still:
		Audio.play_pitched(Audio.NOTE, Audio.place_pitch(hero.area, 0))
		for b in blocks():
			b.flash(0.0, WAVE_FLASH)
		return
	if landed:
		_kill(_tween)
		_land(true)
	else:
		_drop(true)


static func _kill(t: Tween) -> void:
	if t != null and t.is_valid():
		t.kill()
