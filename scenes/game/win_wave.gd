class_name WinWave
extends ColorRect
## Волна света по полю на победе (14.5; docs/STYLE.md, раздел 12, «Победа»; числа — JuiceConfig, группа «Победа»).
## От последнего блока расходится кольцо света (shaders/win_wave.gdshader; с 20.8 — только в блоках, зазоры между
## ними и рамка не светятся) — фронт доходит до дальнего угла поля за win_wave_time, замедляясь к концу (как
## EASE_OUT QUAD), за ним — след; дошёл — всё гаснет за win_fade.
## При «Меньше движения» сила не больше reduced_wave. Твины — через Juice: hit-stop удара победы их останавливает.
## Узел — поверх блоков (Board/Fx), размер — всё поле; доиграл — удаляется.

const SHADER: Shader = preload("res://shaders/win_wave.gdshader")
## Скругление углов, px поля (как у волны линии).
const RADIUS := 24.0
## Сколько клеток поля берёт шейдер (uniform vec4 cells[81]): поле не больше 9 × 9 (размер — по цифре в LevelPack).
const MAX_CELLS := 81

## Сила волны сейчас (0 — не видна) и радиус фронта, px узла (selftest).
var strength := 0.0
var front := 0.0
## Сила, до которой волна вспыхивает (после play).
var peak := 0.0
var _mat: ShaderMaterial
var _origin := Vector2.ZERO
var _reach := 1.0
var _tween: Tween


## Запуск через delay, с: кольцо из точки origin (px узла — середина последнего блока). blocks — прямоугольники
## блоков поля в клетках (20.8, строка 12: свет — только в них), grid — размер поля в клетках; пусто — всё поле.
func play(delay: float, origin: Vector2, blocks: Array[Rect2i] = [], grid := Vector2i.ZERO) -> void:
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
	_set_cells(blocks, grid)
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


## Униформы cells / grid / cell: у каждой клетки поля — прямоугольник её блока (клетки, x, y, w, h). Поле больше
## MAX_CELLS клеток или блоков нет — grid = 0: шейдер светит по всему полю, как до 20.8.
func _set_cells(blocks: Array[Rect2i], grid: Vector2i) -> void:
	var cells := PackedVector4Array()
	cells.resize(MAX_CELLS)
	var n := grid.x * grid.y
	if blocks.is_empty() or n <= 0 or n > MAX_CELLS:
		grid = Vector2i.ZERO
	else:
		for r in blocks:
			for y in range(maxi(r.position.y, 0), mini(r.end.y, grid.y)):
				for x in range(maxi(r.position.x, 0), mini(r.end.x, grid.x)):
					cells[y * grid.x + x] = Vector4(r.position.x, r.position.y, r.size.x, r.size.y)
	_mat.set_shader_parameter("cells", cells)
	_mat.set_shader_parameter("grid", Vector2(grid))
	_mat.set_shader_parameter("cell", Block.CELL)


## Доля пути фронта u = 0…1 → радиус, px: _reach · (1 − (1 − u)²).
func _set_u(u: float) -> void:
	front = _reach * (1.0 - (1.0 - u) * (1.0 - u))
	if _mat:
		_mat.set_shader_parameter("front", front)


func _set_strength(v: float) -> void:
	strength = v
	if _mat:
		_mat.set_shader_parameter("strength", v)
