class_name CellMark
extends Control
## Знак механики 19.3 на поле (Board.setup, docs/STYLE.md, раздел 11.5) — рисует _draw в локальных px поля
## (клетка = Block.CELL):
##   HOLE — препятствие: в клетку «вырос» бортик поля — белая плитка-«конфета» (assets/icons/obstacle.png);
##   TINT — цветная клетка: рамка цвета площади area (tint_frame.png, перекрашена) и заливка внутри
##          (её накрывает только блок этой площади);
##   PIN  — заклёпки (rivet.png) по углам закреплённого блока (узел — ребёнок блока, size — размер блока).
## Только вид: правила — Board (check_rect, rect_issue) и ShikakuSolver.rules_of.

enum Kind { HOLE, TINT, PIN }

## Картинки листа 5 (docs/icons/PROMPTS.md, нарезка tools/cut_icons.py, 10.10): плитка и рамка — квадрат 240 из 256
## (ICON_FIT), заклёпка — круг 240 из 256. Тени в PNG нет — её рисует _draw (Palette.SHADE, как у кружков карты).
const OBSTACLE_TEX: Texture2D = preload("res://assets/icons/obstacle.png")
const FRAME_TEX: Texture2D = preload("res://assets/icons/tint_frame.png")
const RIVET_TEX: Texture2D = preload("res://assets/icons/rivet.png")
const ICON_FIT := 240.0 / 256.0
## Плитка препятствия: отступ от краёв клетки, скругление тени (≈ 20 % стороны, как у картинки), сдвиг тени вниз.
const TILE_INSET := 4.0
const TILE_RADIUS := 18
const TILE_SHADOW_Y := 4.0
## Цветная клетка: рамка той же формы, что плитка, но с отступом TINT_INSET; белое кольцо красится в цвет площади
## (modulate), внутри — заливка TINT_FILL этого цвета (под кольцом, от его середины: TINT_FILL_K стороны рамки).
const TINT_INSET := 6.0
const TINT_FILL := 0.4
const TINT_FILL_K := 0.12
## Заклёпки: центр в RIVET_INSET px от краёв лица блока, видимый диаметр RIVET_D, тень вниз на 2 px.
const RIVET_INSET := 22.0
const RIVET_D := 18.0

var kind: int = Kind.HOLE
var area: int = 0


func _init(k: int = Kind.HOLE, a: int = 0, cells := Vector2i.ONE) -> void:
	kind = k
	area = a
	size = Vector2(cells) * Block.CELL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Прямоугольник картинки (сторона с полями PNG), видимая часть которой — квадрат side с центром c.
static func icon_rect(c: Vector2, side: float) -> Rect2:
	var full := side / ICON_FIT
	return Rect2(c - Vector2(full, full) * 0.5, Vector2(full, full))


func _draw() -> void:
	match kind:
		Kind.HOLE:
			var side := Block.CELL - TILE_INSET * 2.0
			var c := size * 0.5
			var shadow := StyleBoxFlat.new()
			shadow.bg_color = Palette.SHADE
			shadow.set_corner_radius_all(TILE_RADIUS)
			shadow.anti_aliasing = true
			shadow.draw(get_canvas_item(), Rect2(c - Vector2(side, side) * 0.5 + Vector2(0.0, TILE_SHADOW_Y),
					Vector2(side, side)))
			draw_texture_rect(OBSTACLE_TEX, icon_rect(c, side), false)
		Kind.TINT:
			var col := Palette.color_for(area)
			var side := Block.CELL - TINT_INSET * 2.0
			var c := size * 0.5
			var inner := side * (1.0 - TINT_FILL_K * 2.0)
			var fill := StyleBoxFlat.new()
			fill.bg_color = Color(col, TINT_FILL)
			fill.set_corner_radius_all(int(side * 0.2))
			fill.anti_aliasing = true
			fill.draw(get_canvas_item(), Rect2(c - Vector2(inner, inner) * 0.5, Vector2(inner, inner)))
			draw_texture_rect(FRAME_TEX, icon_rect(c, side), false, col)
		Kind.PIN:
			var lift := Block.DEPTH * Block.CELL * 0.6
			for corner: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE]:
				var at := Vector2(RIVET_INSET, RIVET_INSET - lift) + corner * (size - Vector2.ONE * RIVET_INSET * 2.0)
				draw_circle(at + Vector2(0.0, 2.0), RIVET_D * 0.5, Palette.SHADE)
				draw_texture_rect(RIVET_TEX, icon_rect(at, RIVET_D), false)
