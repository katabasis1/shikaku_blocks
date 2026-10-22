class_name LineFlash
extends ColorRect
## Волна света по закрытой линии (14.4; docs/STYLE.md, раздел 12, «Линия и серия»; числа — JuiceConfig, группа
## «Линия и серия»). От блока, закрывшего линию, к обоим её концам бежит светлая полоса (shaders/line_wave.gdshader),
## за ней — след; фронт замедляется к концу (как EASE_OUT QUAD), дошёл — всё гаснет за line_fade. Сила растёт
## с силой хода (combo_wave), при «Меньше движения» — не больше reduced_wave. Твины — через Juice: hit-stop удара
## их останавливает. Узел — поверх блоков (Board/Fx), размер — вся линия; доиграл — удаляется.

const SHADER: Shader = preload("res://shaders/line_wave.gdshader")
## Скругление углов, px поля (как у прежней вспышки линии).
const RADIUS := 24.0

## Сила волны сейчас (0 — не видна) и путь фронта от точки старта, px узла (selftest).
var strength := 0.0
var front := 0.0
## Сила, до которой волна вспыхивает (после play).
var peak := 0.0
var _mat: ShaderMaterial
var _origin := Vector2.ZERO
var _reach := 1.0
var _tween: Tween


## Запуск через delay, с: волна из точки origin (px узла — середина клеток блока на линии), power — сила хода.
func play(delay: float, origin: Vector2, power: int = 0) -> void:
	var c := Block.cfg()
	_origin = origin
	var horiz := size.x >= size.y
	var along := origin.x if horiz else origin.y
	var span := size.x if horiz else size.y
	_reach = maxf(maxf(along, span - along), 1.0)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("radius", RADIUS)
	_mat.set_shader_parameter("origin", origin)
	_mat.set_shader_parameter("band", c.line_wave_width * Block.CELL)
	_mat.set_shader_parameter("trail", c.line_trail)
	peak = clampf(c.line_wave_strength + c.combo_wave * maxi(power, 0), 0.0, 1.0)
	if GameState.reduce_motion:
		peak = minf(peak, c.reduced_wave)
	_set_strength(0.0)
	_set_u(0.0)
	var j: Juice = null if Engine.is_editor_hint() else Juice.of(self)
	_tween = j.tween(self) if j != null else create_tween()
	if delay > 0.0:
		_tween.tween_interval(delay)
	_tween.tween_callback(_set_strength.bind(peak))
	_tween.tween_method(_set_u, 0.0, 1.0, maxf(c.line_wave_time, 0.01))
	_tween.tween_method(_set_strength, peak, 0.0, maxf(c.line_fade, 0.01))
	_tween.tween_callback(queue_free)


## Через сколько секунд после старта волны фронт дойдёт до точки p (px узла); вызывать после play.
func arrival(p: Vector2) -> float:
	var d := absf(p.x - _origin.x) if size.x >= size.y else absf(p.y - _origin.y)
	var k := clampf(d / _reach, 0.0, 1.0)
	return Block.cfg().line_wave_time * (1.0 - sqrt(1.0 - k))


## Волна ещё идёт (selftest).
func is_playing() -> bool:
	return _tween != null and _tween.is_valid()


## Твин волны (selftest: он — через Juice).
func wave_tween() -> Tween:
	return _tween


## Доля пути фронта u = 0…1 → путь, px: _reach · (1 − (1 − u)²).
func _set_u(u: float) -> void:
	front = _reach * (1.0 - (1.0 - u) * (1.0 - u))
	if _mat:
		_mat.set_shader_parameter("front", front)


func _set_strength(v: float) -> void:
	strength = v
	if _mat:
		_mat.set_shader_parameter("strength", v)
