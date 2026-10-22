class_name WinWave
extends ColorRect
## Волна света по полю на победе (14.5; docs/STYLE.md, раздел 12, «Победа»; числа — JuiceConfig, группа «Победа»).
## От последнего блока расходится кольцо света (shaders/win_wave.gdshader) — фронт доходит до дальнего угла поля
## за win_wave_time, замедляясь к концу (как EASE_OUT QUAD), за ним — след; дошёл — всё гаснет за win_fade.
## При «Меньше движения» сила не больше reduced_wave. Твины — через Juice: hit-stop удара победы их останавливает.
## Узел — поверх блоков (Board/Fx), размер — всё поле; доиграл — удаляется.

const SHADER: Shader = preload("res://shaders/win_wave.gdshader")
## Скругление углов, px поля (как у волны линии).
const RADIUS := 24.0

## Сила волны сейчас (0 — не видна) и радиус фронта, px узла (selftest).
var strength := 0.0
var front := 0.0
## Сила, до которой волна вспыхивает (после play).
var peak := 0.0
var _mat: ShaderMaterial
var _origin := Vector2.ZERO
var _reach := 1.0
var _tween: Tween


## Запуск через delay, с: кольцо из точки origin (px узла — середина последнего блока).
func play(delay: float, origin: Vector2) -> void:
	var c := Block.cfg()
	_origin = origin
	_reach = 1.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(size.x, 0.0), Vector2(0.0, size.y), size]:
		_reach = maxf(_reach, origin.distance_to(corner))
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("radius", RADIUS)
	_mat.set_shader_parameter("origin", origin)
	_mat.set_shader_parameter("band", c.win_wave_width * Block.CELL)
	_mat.set_shader_parameter("trail", c.win_trail)
	peak = clampf(c.win_wave_strength, 0.0, 1.0)
	if GameState.reduce_motion:
		peak = minf(peak, c.reduced_wave)
	_set_strength(0.0)
	_set_u(0.0)
	var j: Juice = null if Engine.is_editor_hint() else Juice.of(self)
	_tween = j.tween(self) if j != null else create_tween()
	if delay > 0.0:
		_tween.tween_interval(delay)
	_tween.tween_callback(_set_strength.bind(peak))
	_tween.tween_method(_set_u, 0.0, 1.0, maxf(c.win_wave_time, 0.01))
	_tween.tween_method(_set_strength, peak, 0.0, maxf(c.win_fade, 0.01))
	_tween.tween_callback(queue_free)


## Через сколько секунд после старта волны фронт дойдёт до точки p (px узла); вызывать после play.
func arrival(p: Vector2) -> float:
	var k := clampf(p.distance_to(_origin) / _reach, 0.0, 1.0)
	return Block.cfg().win_wave_time * (1.0 - sqrt(1.0 - k))


## Радиус, на котором фронт остановится (до дальнего угла поля), px.
func reach() -> float:
	return _reach


## Волна ещё идёт (selftest).
func is_playing() -> bool:
	return _tween != null and _tween.is_valid()


## Твин волны (selftest: он — через Juice).
func wave_tween() -> Tween:
	return _tween


## Доля пути фронта u = 0…1 → радиус, px: _reach · (1 − (1 − u)²).
func _set_u(u: float) -> void:
	front = _reach * (1.0 - (1.0 - u) * (1.0 - u))
	if _mat:
		_mat.set_shader_parameter("front", front)


func _set_strength(v: float) -> void:
	strength = v
	if _mat:
		_mat.set_shader_parameter("strength", v)
