class_name LabRow
extends Control
## Ряд уровней одной механики на экране «Лаборатории» (этап 19.3b, docs/STYLE.md, раздел 11.5): COUNT кружков-
## «конфет» в строку на всю ширину, как на карте уровней (MapPath: картинка листа 6, тень, число с обводкой). Не
## пройден в этом запуске — фиолетовый (цвет шапки карточки), пройден — зелёный, под ним три звезды (лучший
## результат, LabLevels.stars_of). Все уровни открыты. Касание: отпускание на том же кружке, что и нажатие, — level_pressed;
## наведение мышью — ×MapPath.HOVER_SCALE и курсор-«рука». Рисуется в _draw, без узлов-детей.

signal level_pressed(index: int)

## Диаметр кружка (шаг — ширина ряда / count), центр по высоте, высота ряда (кружок, губа, звёзды).
const NODE_D := 52.0
const NODE_Y := 30.0
const ROW_H := 76.0
## Цвета (от них обводка числа) и картинки: не пройден — фиолетовый шапки карточки (CandyCard.VIOLET), пройден —
## зелёный главного действия.
const OPEN_COLOR := Color("#8B6CF6")
const DONE_COLOR := Color("#2FCF78")
const OPEN_TEX: Texture2D = preload("res://assets/icons/node_violet.png")
const DONE_TEX: Texture2D = preload("res://assets/icons/node_green.png")
## Звёзды под кружком: размер, шаг по x, подъём средней (как MapPath, мельче).
const STAR_SIZE := 18.0
const STAR_DX := 17.0
const STAR_LIFT := 4.0

var mechanic := ""
var count := 0
## Звёзды уровней 1..count (0 — не пройден).
var stars: Array[int] = []
var hovered := 0
var _press_index := 0


func _init() -> void:
	custom_minimum_size = Vector2(0.0, ROW_H)
	mouse_filter = MOUSE_FILTER_STOP
	# Кружок 192 px и звёзды 256 px рисуются в 18–55 px: без mipmaps края рябят.
	texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func setup(mechanic_: String) -> void:
	mechanic = mechanic_
	count = LabLevels.count(mechanic)
	refresh()


## Перечитать отметки LabLevels.
func refresh() -> void:
	stars.clear()
	for i in range(1, count + 1):
		stars.append(LabLevels.stars_of(mechanic, i))
	queue_redraw()


## Шаг между центрами кружков.
func pitch() -> float:
	return size.x / float(maxi(1, count))


## Центр кружка уровня index (1..count).
func node_pos(index: int) -> Vector2:
	return Vector2(pitch() * (float(index) - 0.5), NODE_Y)


## Уровень под точкой p (координаты ряда) или 0: попадание — в полосу шага по x и в высоту ряда.
func index_at(p: Vector2) -> int:
	if count <= 0 or p.x < 0.0 or p.x >= size.x or p.y < 0.0 or p.y > size.y:
		return 0
	return clampi(floori(p.x / pitch()) + 1, 1, count)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		set_hovered(0)
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press_index = index_at(mb.position)
		else:
			var i := index_at(mb.position)
			if i > 0 and i == _press_index:
				accept_event()
				level_pressed.emit(i)
			_press_index = 0
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		set_hovered(index_at(mm.position))


func set_hovered(index: int) -> void:
	if index == hovered:
		return
	hovered = index
	mouse_default_cursor_shape = CURSOR_POINTING_HAND if index > 0 else CURSOR_ARROW
	queue_redraw()


func _draw() -> void:
	for i in range(1, count + 1):
		_draw_node(i)


func _draw_node(index: int) -> void:
	var got: int = stars[index - 1] if index - 1 < stars.size() else 0
	var d := NODE_D * (MapPath.HOVER_SCALE if index == hovered else 1.0)
	var rad := d * 0.5
	var c := node_pos(index)
	var col := DONE_COLOR if got > 0 else OPEN_COLOR
	draw_circle(c + Vector2(0.0, d * MapPath.SHADOW_K), rad, Palette.SHADE)
	MapPath.draw_node_png(self, DONE_TEX if got > 0 else OPEN_TEX, c, d)
	_draw_number(index, c - Vector2(0.0, d * MapPath.FACE_Y_K), d, col.darkened(0.45))
	if got > 0:
		for k in 3:
			var x := c.x + (k - 1) * STAR_DX - STAR_SIZE * 0.5
			var y := c.y + rad + MapPath.STAR_DROP * STAR_SIZE - (STAR_LIFT if k == 1 else 0.0)
			draw_texture_rect(MapPath.STAR_ON if k < got else MapPath.STAR_OFF, Rect2(x, y, STAR_SIZE, STAR_SIZE), false)


func _draw_number(n: int, at: Vector2, d: float, ink: Color) -> void:
	var text := str(n)
	var fs := roundi(d * MapPath.DIGIT_K)
	var tw := MapPath.FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if tw > d * MapPath.DIGIT_ROOM_K:
		fs = floori(fs * d * MapPath.DIGIT_ROOM_K / tw)
		tw = MapPath.FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(at.x - tw * 0.5, at.y + fs * MapPath.DIGIT_BASE_K)
	draw_string_outline(MapPath.FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			roundi(fs * MapPath.DIGIT_OUTLINE_K), ink)
	draw_string(MapPath.FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
