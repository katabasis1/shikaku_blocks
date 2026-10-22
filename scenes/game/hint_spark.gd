class_name HintSpark
extends Node2D
## Искра подсказки (14.6g; 12.10 — летит вместе с блоком). Светящаяся точка-звезда со следом летит из from в to
## (глобальные координаты) за time, с (TRANS_SINE, EASE_IN_OUT); arc — дуга (квадратичная Безье, вершина выше
## середины пути на arc его длины), 0 — по прямой. Подсказка (HintController._place) пускает её по прямой из
## середины блока в середину места за hint_float_time — тем же ходом, что и блок (Board.place_block): ядро всё время
## под блоком, виден золотой след за ним. Долетела — вспышка искр Juice (SPARKS) в точке места, узел удаляется.
## alive() — ход ещё в силе (блок летит на своё место); отменили ход или сменился уровень — искра тает без вспышки.
## Твин обычный, не Juice: как и твин перемещения блока (Block.new_move_tween), hit-stop его не держит — искра и
## блок касаются места в один кадр. Рисует себя сама (_draw), в FxLayer: над полем и лотком, под летящим блоком.
## Качество (14.7): точек следа — TRAIL × Quality.particles(), не меньше TRAIL_MIN (среднее 6, низкое 4).

const GROUP := &"hint_spark"
const COLOR := Color(1.0, 0.9, 0.5)
const CORE := Color(1.0, 0.99, 0.92)
const CORE_R := 7.0        # ядро, px
const GLOW_R := 24.0       # ореол, px
const STAR_SIZE := 30.0    # звёздочка в ядре, px
const STAR_SPIN := 7.0     # её поворот, рад/с
const TRAIL := 12          # точек следа
const TRAIL_MIN := 3       # точек следа не меньше (низкое качество)
const TRAIL_R := 6.0       # радиус первой точки следа, px (к хвосту — меньше и прозрачнее)
const FADE_TIME := 0.12    # тает при отмене, с
const BURST_COLOR := Color(1.0, 0.92, 0.55)  # как искры линии (Juice.LINE_SPARK)

var _p0 := Vector2.ZERO
var _p1 := Vector2.ZERO
var _p2 := Vector2.ZERO
var _u := 0.0
var _age := 0.0
var _trail := PackedVector2Array()
var _trail_len := TRAIL
var _alive := Callable()
var _juice: Juice
var _tween: Tween
var _fading := false


## Запускает искру в слое layer (FxLayer): из from в to за time, с; arc — высота дуги, доля пути; juice — для
## вспышки в конце (null — без неё); alive — Callable() -> bool, пока ход в силе (пустой — всегда в силе).
static func fly(layer: Control, from: Vector2, to: Vector2, time: float, arc: float, juice: Juice,
		alive := Callable()) -> HintSpark:
	var s := HintSpark.new()
	layer.add_child(s)
	s.setup(from, to, time, arc, juice, alive)
	return s


func setup(from: Vector2, to: Vector2, time: float, arc: float, juice: Juice, alive := Callable()) -> void:
	add_to_group(GROUP)
	z_index = Board.FLOAT_Z - 1  # над полем и лотком (FxLayer выше них), под летящим блоком подсказки (FLOAT_Z)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD  # свет, а не краска: на фиолетовом — тёплое свечение
	material = mat
	_juice = juice
	_alive = alive
	_trail_len = maxi(TRAIL_MIN, roundi(TRAIL * Quality.particles()))
	_p0 = from
	_p2 = to
	# Вершина квадратичной Безье в середине хода — (p0 + 2·p1 + p2) / 4: контрольная точка вдвое выше вершины.
	_p1 = (from + to) * 0.5 + Vector2.UP * 2.0 * arc * from.distance_to(to)
	_trail.clear()
	_trail.append(from)
	_tween = create_tween()
	_tween.tween_method(_step, 0.0, 1.0, maxf(time, 0.01)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_arrive)
	queue_redraw()


## Точка дуги при ходе u (0…1), глобальные координаты.
func point_at(u: float) -> Vector2:
	var v := 1.0 - u
	return _p0 * v * v + _p1 * 2.0 * u * v + _p2 * u * u


## Ход полёта 0…1 (selftest).
func progress() -> float:
	return _u


## Где сейчас ядро, глобальные координаты (selftest).
func head() -> Vector2:
	return point_at(_u)


## Куда летит (selftest).
func target() -> Vector2:
	return _p2


## Наибольшая длина следа, точек (по уровню качества при запуске; selftest).
func trail_length() -> int:
	return _trail_len


func is_fading() -> bool:
	return _fading


func _step(u: float) -> void:
	if _fading:
		return
	if _alive.is_valid() and not bool(_alive.call()):
		_fade_out()
		return
	_u = u
	_trail.insert(0, point_at(u))
	if _trail.size() > _trail_len:
		_trail.resize(_trail_len)
	queue_redraw()


func _arrive() -> void:
	if _fading:
		return
	if _alive.is_valid() and not bool(_alive.call()):
		_fade_out()
		return
	if _juice != null and is_instance_valid(_juice):
		_juice.burst(Juice.SPARKS, _p2, BURST_COLOR)
	queue_free()


## Ход отменили посреди полёта: искра тает на месте, без вспышки.
func _fade_out() -> void:
	_fading = true
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	_tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()


func _draw() -> void:
	if _trail.is_empty():
		return
	var inv := get_global_transform().affine_inverse()
	# След: от хвоста к голове — мельче и прозрачнее к хвосту.
	var n := _trail.size()
	for k in range(n - 1, 0, -1):
		var f := 1.0 - float(k) / float(_trail_len)
		draw_circle(inv * _trail[k], TRAIL_R * (0.35 + 0.65 * f), Color(COLOR, 0.5 * f * f))
	var p := inv * _trail[0]
	draw_circle(p, GLOW_R, Color(COLOR, 0.16))
	draw_circle(p, GLOW_R * 0.55, Color(COLOR, 0.3))
	draw_circle(p, CORE_R, CORE)
	var tex := Juice.STAR_TEXTURE
	if tex != null:
		draw_set_transform(p, _age * STAR_SPIN, Vector2.ONE)
		draw_texture_rect(tex, Rect2(Vector2.ONE * -STAR_SIZE * 0.5, Vector2.ONE * STAR_SIZE), false, CORE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
