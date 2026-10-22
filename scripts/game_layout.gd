class_name GameLayout
extends RefCounted
## Две раскладки игрового экрана (docs/STYLE.md, раздел 10; docs/DESKTOP.md).
##   Портрет — столбик COLUMN по центру: панель, поле, кнопки с «Осталось блоков», лоток
##     из трёх гнёзд в ряд (места как в game.tscn).
##   Альбом — поле слева квадратом S, справа столбик SIDE_W: панель, «Осталось блоков»,
##     лоток из трёх гнёзд сверху вниз, сердца (20.1a, на месте «Отмены») и «Подсказка», подпись про поворот.
##     Группа «поле + столбик» стоит по центру экрана; S растёт с шириной до BOARD_MAX.
## В альбом переходим при ширина/высота ≥ TO_LANDSCAPE, обратно — при < TO_PORTRAIT:
## окно у самого порога не дёргает раскладку туда-обратно.
## Здесь только расчёт; узлы расставляет Game (apply_layout). Python-двойник для проверки
## на любой ширине и схемы docs/layout/*.png — tools/layout_model.py.

const TO_LANDSCAPE := 1.15
const TO_PORTRAIT := 1.10

## Портрет: ширина столбика (логическая ширина экрана в project.godot).
const COLUMN := 720.0
## Альбом: ширина столбика, зазор до поля, наименьшие поля по бокам, наибольшее поле.
const SIDE_W := 560.0
const SIDE_GAP := 64.0
const MARGIN := 40.0
const BOARD_MAX := 1168.0
## Альбом: высота, под которую размечен столбик (логическая высота экрана).
const HEIGHT := 1280.0

## Наибольший масштаб поля. В портрете маленькие поля (4×4) не раздуваются больше клетки 135,
## в альбоме — тот же предел относительно большего места под поле.
const BOARD_SCALE_PORTRAIT := 1.35
const BOARD_SCALE_LANDSCAPE := 2.4
## Масштаб блока в лотке (клетка 100 -> 62 и 78 px; STYLE, раздел 10). Было 0,46 в портрете до 13.2a.
const TRAY_SCALE_PORTRAIT := 0.62
const TRAY_SCALE_LANDSCAPE := 0.78
## Отступ корпуса полки от гнёзд (STYLE, разделы 10 и 13): полка шире ряда гнёзд на столько с каждой стороны.
const SHELF_PAD_PORTRAIT := 12.0
const SHELF_PAD_LANDSCAPE := 14.0
## Шапка (13.2c, STYLE 3 и 13): размеры шрифта заголовка и счёта, центры их строк от верха top_bar;
## размер подписи на плашке «Осталось блоков».
const TITLE_SIZE_PORTRAIT := 50
const TITLE_SIZE_LANDSCAPE := 48
const SCORE_SIZE := 38
const TITLE_Y_PORTRAIT := 34.0   # 62 − 28
const SCORE_Y_PORTRAIT := 88.0   # 116 − 28
const TITLE_Y_LANDSCAPE := 30.0  # 78 − 48
const SCORE_Y_LANDSCAPE := 90.0  # 138 − 48
const REMAINING_SIZE_PORTRAIT := 27
const REMAINING_SIZE_LANDSCAPE := 29
## Победа (13.5b, STYLE 11; стиль-кадр A3B_win). Портрет: заголовок «УРОВЕНЬ N ПРОЙДЕН!» по центру
## строки WIN_TITLE_Y, карточка WIN_CARD внизу (её верх на WIN_CARD_BOTTOM выше низа экрана), поле —
## между ними: от WIN_BOARD_TOP до верха карточки минус WIN_STARS (звёзды на кромке карточки).
## Альбом: поле остаётся на месте, заголовок (в две строки) и карточка — в столбике вместо панели и лотка.
const WIN_CARD := Vector2(512.0, 428.0)
const WIN_TITLE_SIZE_PORTRAIT := 46
const WIN_TITLE_SIZE_LANDSCAPE := 50
const WIN_TITLE_Y := 94.0
const WIN_BOARD_TOP := 130.0
const WIN_CARD_BOTTOM := 494.0   # 1280 − 786
const WIN_STARS := 120.0
## Всплывающее сообщение (13.5d): место — наибольшая капсула TOAST (две строки Nunito 800 30 с полями);
## Toast стоит по центру места, шириной по тексту, и растёт вверх от его нижнего края. Нижний край:
## в портрете — на TOAST_BOTTOM_PORTRAIT выше низа экрана (над кнопками), в альбоме — на TOAST_BOTTOM_LANDSCAPE
## выше низа рамки поля.
const TOAST := Vector2(640.0, 124.0)
const TOAST_BOTTOM_PORTRAIT := 414.0
const TOAST_BOTTOM_LANDSCAPE := 66.0
const WIN_BOARD_SCALE := 1.0

## Последний выбранный режим: следующая сцена начинает с него (гистерезис между сценами).
static var last_landscape: bool = false


## Режим для экрана screen; was — режим сейчас (для гистерезиса).
static func pick(screen: Vector2, was: bool) -> bool:
	if screen.x <= 0.0 or screen.y <= 0.0:
		return was
	return screen.x / screen.y >= (TO_PORTRAIT if was else TO_LANDSCAPE)


## Прямоугольники узлов game.tscn в координатах экрана screen:
##   top_bar, board, remaining, actions, tray (ряд гнёзд), shelf (корпус полки = tray + shelf_pad
##   со всех сторон, рисует Tray), toast (место сообщения: Toast.place),
##   slot (размер гнезда), separation (между гнёздами), shelf_pad, vertical (лоток сверху вниз),
##   board_scale (наибольший масштаб поля), tray_scale (масштаб блока в лотке), landscape;
##   победа (13.5b): win_title (строка заголовка; в альбоме — на две строки), win_title_size,
##   win_board (куда переезжает поле), win_board_scale, win_card (лицо карточки без губы).
static func compute(screen: Vector2, landscape: bool) -> Dictionary:
	return _landscape(screen) if landscape else _portrait(screen)


static func _portrait(screen: Vector2) -> Dictionary:
	var x := (screen.x - COLUMN) * 0.5
	var h := screen.y
	return {
		"landscape": false,
		"top_bar": Rect2(x + 24.0, 28.0, 672.0, 108.0),
		"board": Rect2(x + 22.0, 160.0, 676.0, h - 564.0),
		"actions": Rect2(x + 28.0, h - 390.0, 664.0, 100.0),
		"remaining": Rect2(x + 138.0, h - 390.0, 444.0, 100.0),
		"tray": Rect2(x + 24.0, h - 268.0, 672.0, 232.0),
		"shelf": Rect2(x + 12.0, h - 280.0, 696.0, 256.0),
		"toast": Rect2(Vector2(x + (COLUMN - TOAST.x) * 0.5, h - TOAST_BOTTOM_PORTRAIT - TOAST.y), TOAST),
		"slot": Vector2(216.0, 232.0),
		"separation": 12,
		"shelf_pad": SHELF_PAD_PORTRAIT,
		"vertical": false,
		"board_scale": BOARD_SCALE_PORTRAIT,
		"tray_scale": TRAY_SCALE_PORTRAIT,
		"title_size": TITLE_SIZE_PORTRAIT,
		"score_size": SCORE_SIZE,
		"title_y": TITLE_Y_PORTRAIT,
		"score_y": SCORE_Y_PORTRAIT,
		"remaining_size": REMAINING_SIZE_PORTRAIT,
		"win_title": Rect2(x + 20.0, WIN_TITLE_Y - 44.0, 680.0, 88.0),
		"win_title_size": WIN_TITLE_SIZE_PORTRAIT,
		"win_board": Rect2(x + 40.0, WIN_BOARD_TOP, 640.0,
				maxf(200.0, h - WIN_CARD_BOTTOM - WIN_STARS - WIN_BOARD_TOP)),
		"win_board_scale": WIN_BOARD_SCALE,
		"win_card": Rect2(Vector2(x + (COLUMN - WIN_CARD.x) * 0.5, h - WIN_CARD_BOTTOM), WIN_CARD),
	}


static func _landscape(screen: Vector2) -> Dictionary:
	var s := minf(BOARD_MAX, minf(screen.x - 2.0 * MARGIN - SIDE_GAP - SIDE_W,
			screen.y - (HEIGHT - BOARD_MAX)))
	var left := (screen.x - (s + SIDE_GAP + SIDE_W)) * 0.5
	var board := Rect2(left, (screen.y - s) * 0.5, s, s)
	var x := left + s + SIDE_GAP
	var y := (screen.y - HEIGHT) * 0.5  # столбик размечен под высоту HEIGHT
	return {
		"landscape": true,
		"top_bar": Rect2(x, y + 48.0, SIDE_W, 100.0),
		"board": board,
		"remaining": Rect2(x, y + 204.0, SIDE_W, 44.0),  # 44: строка Nunito 29 — 41 px (14.8e)
		"tray": Rect2(x + 14.0, y + 276.0, 532.0, 792.0),
		"shelf": Rect2(x, y + 262.0, SIDE_W, 820.0),
		"actions": Rect2(x + 118.0, y + 1116.0, 324.0, 96.0),
		"toast": Rect2(Vector2(board.get_center().x - TOAST.x * 0.5, board.end.y - TOAST_BOTTOM_LANDSCAPE - TOAST.y), TOAST),
		"slot": Vector2(532.0, 256.0),
		"separation": 12,
		"shelf_pad": SHELF_PAD_LANDSCAPE,
		"vertical": true,
		"board_scale": BOARD_SCALE_LANDSCAPE,
		"tray_scale": TRAY_SCALE_LANDSCAPE,
		"title_size": TITLE_SIZE_LANDSCAPE,
		"score_size": SCORE_SIZE,
		"title_y": TITLE_Y_LANDSCAPE,
		"score_y": SCORE_Y_LANDSCAPE,
		"remaining_size": REMAINING_SIZE_LANDSCAPE,
		"win_title": Rect2(x, y + 240.0, SIDE_W, 180.0),
		"win_title_size": WIN_TITLE_SIZE_LANDSCAPE,
		"win_board": board,
		"win_board_scale": BOARD_SCALE_LANDSCAPE,
		"win_card": Rect2(Vector2(x + (SIDE_W - WIN_CARD.x) * 0.5, y + 560.0), WIN_CARD),
	}
