class_name LeaderRows
extends Control
## Строки таблицы лидеров (этап 18.3, docs/STYLE.md, раздел 11.3) — рисуются в _draw, без узла на строку.
## Строка: место (1–3 — медаль-кружок с белой цифрой, дальше — цифра INK 70 %, 0 — «—»), имя (Nunito 800,
## INK, длинное — с «…» по ширине) и очки справа (Nunito 1000, INK, с разрядами HudHeader.format_score).
## Своя строка — на жёлтой плашке (Palette.SCORE), разрыв между первыми местами и соседями игрока — «…».
## Вместо строк может стоять сообщение по центру (загрузка, «пока пусто»).

const ROW_H := 44.0
## Отступ строк сверху и снизу внутри узла (поля по бокам даёт карточка).
const PAD_Y := 12.0
const RANK_W := 60.0
## Медаль: видимый диаметр (с белым кольцом, губой и обводкой; в PNG — 240 из 256).
const MEDAL_D := 42.0
const SCORE_W := 170.0
const NAME_GAP := 10.0
const FONT_SIZE := 28
const RANK_SIZE := 24
## Медали 1–3 — картинки листа 5 (assets/icons/medal_*.png, 10.10): пустой диск в белом кольце, номер места
## рисует _draw_rank. Цвета MEDALS — лица медалей: от них обводка номера (темнее на 0,45). Лицо выше середины
## картинки на MEDAL_FACE_Y стороны (губа снизу; tools/cut_icons.py печатает центр лица).
const MEDAL_TEX: Array[Texture2D] = [preload("res://assets/icons/medal_gold.png"),
		preload("res://assets/icons/medal_silver.png"), preload("res://assets/icons/medal_bronze.png")]
const MEDALS: Array[Color] = [Color("#FFC83D"), Color("#AEBBD8"), Color("#E8955A")]
const MEDAL_FACE_Y := -0.02
## Плашка своей строки: выходит за поля строк на ME_BLEED по бокам, радиус ME_RADIUS.
const ME_BLEED := 14.0
const ME_RADIUS := 16.0
## Больше строк карточка не вмещает (height_for(MAX_ROWS) = 640 px — высота Rows в leaders.tscn). Строки
## под этот предел подгоняет LeaderboardData.rows (fit_ranks: строка игрока остаётся); срез здесь — только защита.
const MAX_ROWS := LeaderboardData.MAX_ROWS
const MUTED_ALPHA := 0.55

const FONT_BLACK: Font = preload("res://assets/fonts/nunito_black.ttf")
const FONT_BOLD: Font = preload("res://assets/fonts/nunito_extrabold.ttf")

var rows: Array[Dictionary] = []
## Сообщение по центру вместо строк (русский msgid, переводится при рисовании); "" — строки.
var message := ""

var _me_box: StyleBoxFlat


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_me_box = StyleBoxFlat.new()
	_me_box.bg_color = Palette.SCORE
	_me_box.set_corner_radius_all(int(ME_RADIUS))
	_me_box.anti_aliasing = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED or what == NOTIFICATION_RESIZED:
		queue_redraw()


## Показать строки (LeaderboardData.rows / local_row); лишние сверх MAX_ROWS отбрасываются.
func set_rows(list: Array[Dictionary]) -> void:
	rows = list.slice(0, MAX_ROWS)
	message = ""
	queue_redraw()


## Показать сообщение по центру (msgid).
func set_message(text: String) -> void:
	rows = []
	message = text
	queue_redraw()


## Высота узла под n строк.
static func height_for(n: int) -> float:
	return PAD_Y * 2.0 + ROW_H * n


## Прямоугольник строки i (локально).
func row_rect(i: int) -> Rect2:
	return Rect2(0.0, PAD_Y + ROW_H * i, size.x, ROW_H)


## Ширина под имя: всё между местом и очками.
func name_width() -> float:
	return maxf(0.0, size.x - RANK_W - NAME_GAP * 2.0 - SCORE_W)


func _draw() -> void:
	var ink := Palette.INK
	var muted := Color(ink, MUTED_ALPHA)
	if not message.is_empty():
		_draw_centered(tr(message), FONT_BOLD, FONT_SIZE, Rect2(Vector2.ZERO, size), muted)
		return
	for i in rows.size():
		var row: Dictionary = rows[i]
		var rect := row_rect(i)
		if bool(row["gap"]):
			_draw_centered("…", FONT_BLACK, FONT_SIZE, rect, muted)
			continue
		if bool(row["me"]):
			draw_style_box(_me_box, Rect2(rect.position.x - ME_BLEED, rect.position.y + 2.0,
					rect.size.x + ME_BLEED * 2.0, rect.size.y - 4.0))
		_draw_rank(int(row["rank"]), Rect2(rect.position, Vector2(RANK_W, ROW_H)))
		var name := str(row["name"])
		if name == LeaderboardData.ANON_NAME or name == LeaderboardData.LOCAL_NAME:
			name = tr(name)
		var line := TextLine.new()
		line.add_string(name, FONT_BOLD, FONT_SIZE)
		line.width = name_width()
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.draw(get_canvas_item(), Vector2(rect.position.x + RANK_W + NAME_GAP,
				rect.position.y + (ROW_H - line.get_size().y) * 0.5), ink)
		var score_rect := Rect2(rect.end.x - SCORE_W, rect.position.y, SCORE_W, ROW_H)
		draw_string(FONT_BLACK, Vector2(score_rect.position.x, _baseline(FONT_BLACK, FONT_SIZE, score_rect)),
				HudHeader.format_score(int(row["score"])), HORIZONTAL_ALIGNMENT_RIGHT, SCORE_W, FONT_SIZE, ink)


func _draw_rank(rank: int, box: Rect2) -> void:
	var text := str(rank) if rank > 0 else "—"
	if rank >= 1 and rank <= MEDALS.size():
		var c := box.get_center()
		var face: Color = MEDALS[rank - 1]
		var side := MEDAL_D * 256.0 / 240.0
		draw_texture_rect(MEDAL_TEX[rank - 1], Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false)
		var y := _baseline(FONT_BLACK, RANK_SIZE, box) + side * MEDAL_FACE_Y
		draw_string_outline(FONT_BLACK, Vector2(box.position.x, y), text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x,
				RANK_SIZE, 6, face.darkened(0.45))
		draw_string(FONT_BLACK, Vector2(box.position.x, y), text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x,
				RANK_SIZE, Color.WHITE)
	else:
		_draw_centered(text, FONT_BLACK, RANK_SIZE, box, Color(Palette.INK, 0.7))


func _draw_centered(text: String, font: Font, fs: int, box: Rect2, color: Color) -> void:
	draw_string(font, Vector2(box.position.x, _baseline(font, fs, box)), text, HORIZONTAL_ALIGNMENT_CENTER,
			box.size.x, fs, color)


## Базовая линия текста, стоящего по центру box по высоте.
static func _baseline(font: Font, fs: int, box: Rect2) -> float:
	return box.position.y + (box.size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
