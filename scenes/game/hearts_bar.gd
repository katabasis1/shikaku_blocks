class_name HeartsBar
extends Control
## Сердца попытки (20.1a, PLAN 20.1) — на месте прежней кнопки «Отмена», слева в полосе действий. Слева направо
## max_hearts сердец: целые — красные с тёмным ободком, сгоревшие — тёмный след. Без предела сердец (max 0: уровни
## со страховкой, «Лаборатория», флаг hearts = 0) — пусто. Нажатия не ловит.
## Вид пока простой (рисуется в _draw, без картинок): сгорание «пуф», пульс последнего сердца и кадр STYLE — 20.1c.

## Сердце не больше HEART px (полоса действий — 96–100 px высотой); не влезают — меньше, промежуток GAP.
const HEART := 56.0
const GAP := 10.0
const FULL := Color(1.0, 0.36, 0.45)
const RIM := Color(0.6, 0.09, 0.22)
const SHINE := Color(1.0, 1.0, 1.0, 0.45)
const EMPTY := Color(0.0, 0.0, 0.0, 0.24)
## Точек на контуре сердца.
const POINTS := 40
## Кривая сердца x = 16 sin³t, y = 13 cos t − 5 cos 2t − 2 cos 3t − cos 4t: x в −16..16, y в −17..HEART_TOP.
const HEART_TOP := 11.92
const HEART_H := 28.92

## Сколько сердец на попытку (0 — без предела, ничего не рисуем).
var max_hearts: int = 0
## Сколько осталось.
var left: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## Game.update_hud: осталось n_left из n_max.
func show_hearts(n_left: int, n_max: int) -> void:
	if n_left == left and n_max == max_hearts:
		return
	left = n_left
	max_hearts = n_max
	queue_redraw()


## Сторона квадрата одного сердца при текущем размере полосы, px.
func heart_size() -> float:
	if max_hearts <= 0:
		return 0.0
	return maxf(0.0, minf(HEART, minf(size.y, (size.x - GAP * (max_hearts - 1)) / max_hearts)))


## Квадрат сердца k (0 — левое) в координатах полосы.
func heart_rect(k: int) -> Rect2:
	var s := heart_size()
	return Rect2(Vector2(k * (s + GAP), (size.y - s) * 0.5), Vector2(s, s))


## Контур сердца, вписанного в квадрат со стороной s и левым верхним углом at.
static func heart_points(at: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var k := s / 32.0
	var top := at.y + (s - HEART_H * k) * 0.5
	for n in POINTS:
		var t := TAU * n / POINTS
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(Vector2(at.x + (x + 16.0) * k, top + (HEART_TOP - y) * k))
	return pts


func _draw() -> void:
	var s := heart_size()
	if s <= 0.0:
		return
	for k in max_hearts:
		var r := heart_rect(k)
		var pts := heart_points(r.position, s)
		if k < left:
			draw_colored_polygon(pts, FULL)
			var rim := pts.duplicate()
			rim.append(pts[0])
			draw_polyline(rim, RIM, maxf(2.0, s * 0.06), true)
			draw_circle(r.position + Vector2(s * 0.3, s * 0.33), s * 0.08, SHINE)
		else:
			draw_colored_polygon(pts, EMPTY)
