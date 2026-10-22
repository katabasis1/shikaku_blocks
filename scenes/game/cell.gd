class_name Cell
extends Control
## Число на поле — «гнездо» (docs/STYLE.md, раздел 6). Вид рисует shaders/nest.gdshader в узле
## Badge/Nest, цифру — Badge/Number (cell.tscn). Ячейки под всеми клетками рисует шейдер поля
## (Board/Frame), поэтому Cell создаётся только на клетках с числом.
## 14.2: ореол магнита пульсирует (униформа pulse, JuiceConfig.pulse_freq; при «Меньше движения» — нет),
## на «щелчок» допустимого места гнездо подпрыгивает (hop).
## 14.6b: на появлении уровня число выпрыгивает снизу после своей ячейки (appear).

## Режимы выделения числа во время перетаскивания блока (Board.emphasize_area).
const EMPHASIS_NONE := 0
## Число той же площади, что и блок в руке, — магнит: гнездо ×1,08 и выше на 4 px, ореол и белое кольцо.
const EMPHASIS_MATCH := 1
## Число другой площади: гнездо приглушается, чтобы не отвлекать.
const EMPHASIS_DIM := 2

## Приглушённое гнездо: 55 % (было 40 % — по срезу 13.1 число «3» почти не читалось; на эталоне A3B
## гнёзда не приглушены, 55 % — компромисс: фокус на магните остаётся, число читается).
const DIM_COLOR := Color(1, 1, 1, 0.55)
const MAGNET_SCALE := 1.08
## Подъём гнезда-магнита, логические px экрана.
const MAGNET_LIFT := 4.0
## Щелчок магнита (STYLE, раздел 12: отклик 0,08–0,12 с).
const MAGNET_TIME := 0.12
## Обводка цифры в гнезде (0,035 C) — в той же мере, что Block.DIGIT_OUTLINE (0,042 C).
const DIGIT_OUTLINE := 7
## Подскок гнезда-магнита на «щелчок» места (hop), логические px экрана — выше MAGNET_LIFT на столько.
const HOP_LIFT := 6.0

@onready var badge: Control = $Badge
@onready var nest: ColorRect = $Badge/Nest
@onready var number_label: Label = $Badge/Number

var value: int = 0

var _emphasis: int = EMPHASIS_NONE
var _emphasis_tween: Tween
## Сила магнита в шейдере (0 — нет, 1 — ореол и кольцо).
var _ring: float = 0.0
## Локальных px поля в логическом px экрана (Board.set_px -> set_px).
var _px: float = 1.0
var _hop_tween: Tween
## Пульс ореола: время с начала магнита, частота (0 — не пульсирует), текущее значение 0…1.
var _pulse_t: float = 0.0
var _pulse_freq: float = 0.0
var _pulse: float = 0.0
## Появление (14.6b): твин, место числа на поле (Board ставит position до appear), подъём сейчас, px экрана.
var _appear_tween: Tween
var _home := Vector2.ZERO
var _rise: float = 0.0


func _ready() -> void:
	set_process(false)


## v > 0 — число, ShikakuSolver.ANY — «?» (механика 19.3: площадь не показана), 0 — пусто.
func set_value(v: int) -> void:
	value = v
	badge.visible = v > 0 or v == ShikakuSolver.ANY
	if not badge.visible:
		return
	var col := Palette.color_for(v)
	nest.color = col
	number_label.text = "?" if v == ShikakuSolver.ANY else str(v)
	number_label.add_theme_color_override("font_color", col)
	number_label.add_theme_color_override("font_outline_color", Palette.nest_digit_outline(v))
	number_label.add_theme_color_override("font_shadow_color", Palette.nest_digit_shadow(v))
	number_label.add_theme_constant_override("outline_size", DIGIT_OUTLINE)
	number_label.add_theme_constant_override("shadow_outline_size", DIGIT_OUTLINE)


## px = 1 / масштаб поля: кант, тень, ореол и кольцо гнезда заданы в логических px.
func set_px(px: float) -> void:
	_px = px
	if _rise != 0.0:
		_set_rise(_rise)
	var mat := nest.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("px", px)
	if _emphasis == EMPHASIS_MATCH and not (_emphasis_tween and _emphasis_tween.is_running()) and not is_hopping():
		badge.position.y = -MAGNET_LIFT * _px


func set_emphasis(mode: int) -> void:
	if mode == _emphasis:
		return
	_emphasis = mode
	if _emphasis_tween and _emphasis_tween.is_valid():
		_emphasis_tween.kill()
	if _hop_tween and _hop_tween.is_valid():
		_hop_tween.kill()
	var on := mode == EMPHASIS_MATCH
	_pulse_t = 0.0
	_pulse_freq = Juice.shared_config().pulse_freq if on and not GameState.reduce_motion else 0.0
	set_process(_pulse_freq > 0.0)
	_emphasis_tween = create_tween().set_parallel()
	_emphasis_tween.tween_property(badge, "scale", Vector2.ONE * (MAGNET_SCALE if on else 1.0), MAGNET_TIME) \
			.set_trans(Tween.TRANS_BACK if on else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_emphasis_tween.tween_property(badge, "position:y", -MAGNET_LIFT * _px if on else 0.0, MAGNET_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_emphasis_tween.tween_method(_set_ring, _ring, 1.0 if on else 0.0, MAGNET_TIME)
	_emphasis_tween.tween_property(badge, "modulate", DIM_COLOR if mode == EMPHASIS_DIM else Color.WHITE, 0.15)
	if _pulse_freq <= 0.0 and _pulse > 0.0:
		_emphasis_tween.tween_method(_set_pulse, _pulse, 0.0, MAGNET_TIME)


## «Щелчок» допустимого места (14.2, Board.snap_preview): гнездо-магнит подпрыгивает — крупнее на долю extra
## и выше на HOP_LIFT — и пружинит обратно за time. Пока магнит ещё включается — не мешает ему.
func hop(extra: float, time: float) -> void:
	if _emphasis != EMPHASIS_MATCH or (_emphasis_tween and _emphasis_tween.is_running()):
		return
	if _hop_tween and _hop_tween.is_valid():
		_hop_tween.kill()
	var base_y := -MAGNET_LIFT * _px
	_hop_tween = create_tween().set_parallel()
	_hop_tween.tween_property(badge, "scale", Vector2.ONE * MAGNET_SCALE * (1.0 + extra), time * 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hop_tween.tween_property(badge, "position:y", base_y - HOP_LIFT * _px, time * 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hop_tween.chain().tween_property(badge, "scale", Vector2.ONE * MAGNET_SCALE, time * 0.65) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hop_tween.tween_property(badge, "position:y", base_y, time * 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Гнездо подпрыгивает сейчас (selftest).
func is_hopping() -> bool:
	return _hop_tween != null and _hop_tween.is_running()


## Пульс ореола сейчас, 0…1 (selftest).
func pulse() -> float:
	return _pulse


func _process(delta: float) -> void:
	_pulse_t += delta
	_set_pulse(0.5 - 0.5 * cos(TAU * _pulse_freq * _pulse_t))


func _set_pulse(v: float) -> void:
	_pulse = v
	var mat := nest.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("pulse", v)


func _set_ring(v: float) -> void:
	_ring = v
	var mat := nest.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("ring", v)


## Появление уровня (14.6b, PLAN 4.4: «числа выпрыгивают по очереди»; числа — группа «Появление и переходы»
## в JuiceConfig). Board зовёт с delay = intro_cell_step · (x + y) + intro_number_delay — после своей ячейки.
## Число выпрыгивает снизу: подъём intro_number_rise px экрана → 0 и ×intro_number_from → 1 за intro_number_time
## с дожимом (TRANS_BACK), проявляясь за первую треть. «Меньше движения» — только проявление, без прыжка.
## Сдвиг — свойство position самой Cell (её больше никто не двигает; гнездо Badge двигает магнит), в px экрана:
## поле вписывается под экран уже после setup, поэтому px пересчитывается на каждом шаге.
## Твин — через Juice (hit-stop его останавливает); ввод не ждёт: магнит и «щелчок» работают на Badge.
func appear(delay: float) -> void:
	var c := Juice.shared_config()
	if _appear_tween and _appear_tween.is_valid():
		_appear_tween.kill()
	_home = position - Vector2(0.0, _rise * _px)  # вызов повторно, пока число ещё поднималось
	_rise = 0.0
	modulate.a = 0.0
	var reduced := GameState.reduce_motion
	var time := maxf(c.intro_number_time, 0.01)
	scale = Vector2.ONE if reduced else Vector2.ONE * c.intro_number_from
	_set_rise(0.0 if reduced else c.intro_number_rise)
	_appear_tween = _effect_tween().set_parallel()
	_appear_tween.tween_property(self, "modulate:a", 1.0, time if reduced else time * 0.35).set_delay(delay)
	if reduced:
		return
	_appear_tween.tween_property(self, "scale", Vector2.ONE, time).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_appear_tween.tween_method(_set_rise, c.intro_number_rise, 0.0, time).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Число ещё появляется (selftest).
func is_appearing() -> bool:
	return _appear_tween != null and _appear_tween.is_running()


## Подъём числа при появлении сейчас, px экрана (0 — на месте; selftest).
func rise() -> float:
	return _rise


func _set_rise(v: float) -> void:
	_rise = v
	position = _home + Vector2(0.0, v * _px)


## Твин эффекта: через Juice (его останавливает hit-stop), вне игры (отдельный тест поля) — обычный.
func _effect_tween() -> Tween:
	var j := Juice.of(self)
	return j.tween(self) if j != null else create_tween()
