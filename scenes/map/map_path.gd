class_name MapPath
extends Control
## Дорожка карты уровней (этап 18.2, docs/STYLE.md, раздел 11.2). Уровни — кружки-«конфеты» волной снизу вверх:
## уровень 1 внизу, выше — следующие (ось — середина ширины, размах AMP, период PERIOD уровней, шаг STEP).
## Кружок — картинка листа 6 (assets/icons/node_*.png, 10.10: «конфета» с обводкой, губой и бликом); тень, число,
## звёзды, кольцо и замок рисует код. Пройденные — цвет блока по номеру (PASSED_AREAS, без зелёного), число с
## обводкой, под кружком три звезды (лучший результат); текущий (GameState.level) — крупнее, зелёный главного
## действия, с расходящимся кольцом; закрытые — AHEAD уровней выше текущего, белые полупрозрачные с замком. Между
## кружками — дорога: пройденная часть ярче.
## Рисуется в _draw только видимое окно прокрутки (уровней может быть больше тысячи — без узлов-детей).
## Касание: отпускание на том же кружке, а палец (мышь) за всё нажатие не ушёл дальше TAP_SLOP от точки нажатия
## на экране (иначе это прокрутка) — level_pressed(n) у открытого, level_locked(n) у закрытого (он вздрагивает).
## Сдвиг меряется в координатах экрана (global_position), а не карты: при прокрутке карта едет вместе с пальцем,
## и в её координатах палец почти стоит на месте — потянул карту с кружка, отпустил, и уровень открылся бы. Наведение на компьютере — ×HOVER_SCALE и
## курсор-«рука». Мышью карту можно тянуть (на сенсорном экране тянет сам ScrollContainer).
## «Меньше движения»: кольцо не расходится, закрытый не вздрагивает.
## Главы (19.5c, Chapters, STYLE 11.6): перед первым уровнем каждой главы дорога длиннее на CHAPTER_GAP, посреди
## зазора — плашка «ГЛАВА N · НАЗВАНИЕ» цвета темы главы (у главы 1 — под уровнем 1); плашка закрытой главы —
## полупрозрачная. Высота уровня над первым — rise(), обратно — level_below().

signal level_pressed(level: int)
signal level_locked(level: int)

enum State { LOCKED, PASSED, CURRENT }

const FONT: Font = preload("res://assets/fonts/nunito_black.ttf")
const STAR_ON: Texture2D = preload("res://assets/icons/star.png")
const STAR_OFF: Texture2D = preload("res://assets/icons/star_empty.png")

## Шаг по высоте между уровнями, размах волны от оси, уровней на период волны.
const STEP := 150.0
const AMP := 170.0
const PERIOD := 8.0
## Поля: над последним показанным уровнем (под верхним рядом экрана) и под первым.
const PAD_TOP := 260.0
const PAD_BOTTOM := 230.0
## Сколько закрытых уровней видно выше текущего.
const AHEAD := 12
## Диаметры: обычный кружок и текущий.
const NODE_D := 104.0
const CURRENT_D := 132.0
## Кружок — картинка (лист 6): диск с обводкой занимает 240/256 стороны PNG (tools/cut_icons.py, BTN_D; у PNG 192 —
## та же доля), губа внутри обводки — снизу. Лицо над губой выше середины кружка на FACE_Y_K·Ø (cut_icons.py
## печатает 0,033–0,038) — по его центру число.
const NODE_PNG_K := 256.0 / 240.0
const FACE_Y_K := 0.036
## Тень: круг Ø кружка цветом Palette.SHADE, ниже на SHADOW_K·Ø (выглядывает из-под губы).
const SHADOW_K := 0.07
## Губа плашки главы (и карточки главы, ChapterCard): темнее цвета лица на LIP_DARK.
const LIP_DARK := 0.3
## Число: размер (доля Ø), обводка (полная толщина, доля размера) темнее(цвет, 0,45), базовая линия ниже
## центра на DIGIT_BASE_K·размер (цифры Nunito высотой ≈0,71 размера — так они стоят по центру лица).
const DIGIT_K := 0.42
const DIGIT_OUTLINE_K := 0.24
const DIGIT_BASE_K := 0.36
## Число не шире этой доли Ø (четыре цифры ужимаются).
const DIGIT_ROOM_K := 0.78
## Дорога: ширина, пройденная часть и та, что впереди.
const ROAD_W := 34.0
const ROAD_DONE := Color(1, 1, 1, 0.34)
const ROAD_AHEAD := Color(1, 1, 1, 0.14)
## Точек дороги на шаг между уровнями.
const ROAD_SAMPLES := 10
## Текущий — зелёный главного действия (как PillButton GREEN): картинка node_green, цвет — для обводки числа.
const CURRENT_COLOR := Color("#2FCF78")
const CURRENT_TEX: Texture2D = preload("res://assets/icons/node_green.png")
## Пройденные — цвета блоков этих площадей по кругу: без зелёных и лайма (зелёный — только у текущего, он должен
## выделяться) и без бледной лавандовой «единицы» (похожа на закрытый). Картинки — в том же порядке.
const PASSED_AREAS: Array[int] = [2, 3, 4, 6, 8, 12, 7]
const PASSED_TEX: Array[Texture2D] = [
	preload("res://assets/icons/node_red.png"),      # 2
	preload("res://assets/icons/node_orange.png"),   # 3
	preload("res://assets/icons/node_yellow.png"),   # 4
	preload("res://assets/icons/node_sky.png"),      # 6
	preload("res://assets/icons/node_blue.png"),     # 8
	preload("res://assets/icons/node_pink.png"),     # 12
	preload("res://assets/icons/node_magenta.png"),  # 7
]
## Закрытый — белая картинка с непрозрачностью LOCKED_ALPHA (обводка тоже бледнеет: «ещё не твоё»), без тени.
const LOCKED_TEX: Texture2D = preload("res://assets/icons/node_white.png")
const LOCKED_ALPHA := 0.5
## Замок на закрытом кружке — картинка листа 5 (assets/icons/lock.png, 10.10): высота замка LOCK_K диаметра кружка
## (замок в PNG — 240 из 256 по высоте), непрозрачность LOCK_ALPHA.
const LOCK_TEX: Texture2D = preload("res://assets/icons/lock.png")
const LOCK_K := 0.5
const LOCK_ALPHA := 1.0
## Главы: добавка к шагу перед первым уровнем главы; плашка — высота, шрифт, поля по бокам, наименьшая ширина,
## подъём губы (как у кружка, тень SHADE ниже ещё на BANNER_SHADOW), рамка, непрозрачность у закрытой главы.
const CHAPTER_GAP := 120.0
const BANNER_H := 60.0
const BANNER_FONT := 28
const BANNER_PAD := 34.0
const BANNER_MIN_W := 300.0
const BANNER_DEPTH := 6.0
const BANNER_SHADOW := 5.0
const BANNER_RIM := Color(1, 1, 1, 0.6)
const BANNER_RIM_W := 3.0
const BANNER_LOCKED_ALPHA := 0.55
## Плашка главы 1 — ниже середины уровня 1 на столько px (в поле PAD_BOTTOM, под звёздами).
const FIRST_BANNER_DROP := 135.0
## Звёзды под кружком: размер, шаг по x, подъём средней, верх ниже низа кружка на STAR_DROP·размер.
const STAR_SIZE := 34.0
const STAR_DX := 32.0
const STAR_LIFT := 6.0
const STAR_DROP := -0.3
## Кольцо текущего: на сколько px расходится за PULSE_TIME, толщина, непрозрачность в начале.
const PULSE_GROW := 24.0
const PULSE_TIME := 1.6
const PULSE_W := 6.0
const PULSE_ALPHA := 0.55
const HOVER_SCALE := 1.06
## Касание: допуск сдвига (px) и запас вокруг кружка.
const TAP_SLOP := 24.0
const HIT_PAD := 8.0
## Закрытый уровень вздрагивает: время, размах.
const SHAKE_TIME := 0.35
const SHAKE_PX := 9.0

## Первый непройденный уровень (открыт и выделен), последний показанный, лучшие звёзды {уровень: 0..3}.
var current: int = 1
var count: int = 1 + AHEAD
var stars: Dictionary = {}
## Уровень под мышью (0 — нет).
var hovered: int = 0
## Фаза кольца текущего 0..1.
var pulse: float = 0.0

## Точка нажатия на экране (global_position) и кружок под ней (0 — касание отменено: увели дальше TAP_SLOP).
var _press_at := Vector2.ZERO
var _press_level := 0
var _shake_level := 0
var _shake := 0.0
var _shake_tween: Tween
var _banner_box: StyleBoxFlat


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_PASS
	# Картинки 128–256 px рисуются в 34–140 px: без mipmaps края обводки и звёзд рябят.
	texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_banner_box = StyleBoxFlat.new()
	_banner_box.set_corner_radius_all(roundi(BANNER_H * 0.5))
	_banner_box.anti_aliasing = true
	# ScrollContainer двигает карту (position) — видимое окно сменилось, перерисовать.
	item_rect_changed.connect(queue_redraw)


## current_ — GameState.level, stars_ — GameState.level_stars.
func setup(current_: int, stars_: Dictionary) -> void:
	current = maxi(1, current_)
	stars = stars_
	count = current + AHEAD
	custom_minimum_size = Vector2(0.0, total_height(count))
	queue_redraw()


static func total_height(n: int) -> float:
	return PAD_TOP + PAD_BOTTOM + rise(float(maxi(1, n)))


## Высота точки дороги t (в «уровнях», 1 — уровень 1) над уровнем 1: по STEP на уровень и CHAPTER_GAP перед
## первым уровнем каждой главы (внутри этого отрезка зазор растёт линейно — дорога непрерывна).
static func rise(t: float) -> float:
	var whole := floori(t)
	var gaps := float(Chapters.starts_upto(whole))
	if t > float(whole) and Chapters.is_start(whole + 1):
		gaps += t - float(whole)
	return (t - 1.0) * STEP + gaps * CHAPTER_GAP


## Наибольший уровень 1..n_max, чей кружок не выше высоты h над уровнем 1 (rise(уровень) <= h); 1 — если ниже.
static func level_below(h: float, n_max: int) -> int:
	var lo := 1
	var hi := maxi(1, n_max)
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi + 1) / 2
		if rise(float(mid)) <= h:
			lo = mid
		else:
			hi = mid - 1
	return lo


## Точка дороги в «уровнях» t (1 — середина первого кружка) на карте ширины w и высоты h.
static func road_point(t: float, w: float, h: float) -> Vector2:
	var k := t - 1.0
	return Vector2(w * 0.5 + AMP * sin(k * TAU / PERIOD), h - PAD_BOTTOM - rise(t))


## Высота карты: по уровням или больше, если контейнер растянул её на высокий экран.
func map_height() -> float:
	return maxf(size.y, total_height(count))


## Середина кружка уровня n.
func node_pos(n: int) -> Vector2:
	return road_point(float(n), size.x, map_height())


func state_of(n: int) -> State:
	if n == current:
		return State.CURRENT
	return State.PASSED if n < current else State.LOCKED


func diameter(n: int) -> float:
	return CURRENT_D if n == current else NODE_D


## Цвет кружка (от него обводка числа): текущий — зелёный, пройденные — цвета блоков PASSED_AREAS по кругу,
## закрытые — белый LOCKED_ALPHA.
func node_color(n: int) -> Color:
	match state_of(n):
		State.CURRENT:
			return CURRENT_COLOR
		State.PASSED:
			return Palette.color_for(PASSED_AREAS[(n - 1) % PASSED_AREAS.size()])
	return Color(1.0, 1.0, 1.0, LOCKED_ALPHA)


## Картинка кружка: текущий — зелёная, пройденные — PASSED_TEX по кругу (как цвета), закрытые — белая.
func node_texture(n: int) -> Texture2D:
	match state_of(n):
		State.CURRENT:
			return CURRENT_TEX
		State.PASSED:
			return PASSED_TEX[(n - 1) % PASSED_TEX.size()]
	return LOCKED_TEX


## Кружок-картинка Ø d с центром c на холсте ci (вызывать из его _draw): диск — 240/256 стороны PNG.
static func draw_node_png(ci: CanvasItem, tex: Texture2D, c: Vector2, d: float, alpha := 1.0) -> void:
	var side := d * NODE_PNG_K
	ci.draw_texture_rect(tex, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false, Color(1, 1, 1, alpha))


## Уровень под точкой p (координаты карты) или 0.
func level_at(p: Vector2) -> int:
	var guess := level_below(map_height() - PAD_BOTTOM - p.y, count)
	for n in range(guess - 1, guess + 3):
		if n >= 1 and n <= count and p.distance_to(node_pos(n)) <= diameter(n) * 0.5 + HIT_PAD:
			return n
	return 0


## Уровни, видимые в полосе карты top…bottom (с запасом в кружок): Vector2i(нижний, верхний).
func visible_range(top: float, bottom: float) -> Vector2i:
	var base := map_height() - PAD_BOTTOM
	var hi := level_below(base - top + CURRENT_D, count) + 1
	var lo := level_below(base - bottom - CURRENT_D, count)
	return Vector2i(clampi(lo, 1, count), clampi(hi, 1, count))


## Уровень, чей кружок ближе всех к высоте y карты (по вертикали; тема фона главы посреди экрана — LevelMap).
func level_near(y: float) -> int:
	var h := map_height() - PAD_BOTTOM - y
	var n := level_below(h, count)
	if n < count and absf(rise(float(n + 1)) - h) < absf(rise(float(n)) - h):
		n += 1
	return n


## Прокрутка, при которой кружок n стоит на доле at высоты окна view_h.
func scroll_for(n: int, view_h: float, at: float) -> int:
	return maxi(0, roundi(node_pos(n).y - view_h * at))


## Видимая полоса карты: Vector2(верх, низ) в её координатах (ScrollContainer сдвигает карту вверх).
func view_band() -> Vector2:
	var top := -position.y
	return Vector2(top, top + get_parent_area_size().y)


func _process(delta: float) -> void:
	if GameState.reduce_motion:
		if pulse != 0.0:
			pulse = 0.0
			queue_redraw()
		return
	pulse = fposmod(pulse + delta / PULSE_TIME, 1.0)
	var band := view_band()
	var y := node_pos(current).y
	if y > band.x - CURRENT_D and y < band.y + CURRENT_D:
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		set_hovered(0)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press_at = mb.global_position
			_press_level = level_at(mb.position)
		else:
			var n := level_at(mb.position)
			if n > 0 and n == _press_level and mb.global_position.distance_to(_press_at) <= TAP_SLOP:
				tap(n)
			_press_level = 0
		return
	var mm := event as InputEventMouseMotion
	if mm == null:
		return
	if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		# Увели дальше допуска — это прокрутка: касание отменено, даже если палец вернётся на кружок.
		if _press_level > 0 and mm.global_position.distance_to(_press_at) > TAP_SLOP:
			_press_level = 0
		# Тянуть мышью (на сенсорном экране прокручивает сам ScrollContainer — не вдвое).
		var sc := get_parent() as ScrollContainer
		if sc != null and not DisplayServer.is_touchscreen_available():
			sc.scroll_vertical -= roundi(mm.relative.y)
		return
	set_hovered(level_at(mm.position))


## Касание кружка n: открытый — level_pressed, закрытый вздрагивает — level_locked.
func tap(n: int) -> void:
	if n < 1 or n > count:
		return
	if state_of(n) == State.LOCKED:
		shake(n)
		level_locked.emit(n)
	else:
		level_pressed.emit(n)


func set_hovered(n: int) -> void:
	if n == hovered:
		return
	hovered = n
	var open := n > 0 and state_of(n) != State.LOCKED
	mouse_default_cursor_shape = CURSOR_POINTING_HAND if open else CURSOR_ARROW
	queue_redraw()


func shake(n: int) -> void:
	if GameState.reduce_motion:
		return
	_shake_level = n
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.tween_method(_set_shake, 0.0, 1.0, SHAKE_TIME)


func _set_shake(t: float) -> void:
	_shake = t if t < 1.0 else 0.0
	queue_redraw()


# --- Рисование ------------------------------------------------------------------

func _draw() -> void:
	var band := view_band()
	var r := visible_range(band.x, band.y)
	_draw_road(r)
	_draw_banners(r)
	for n in range(r.y, r.x - 1, -1):
		_draw_node(n)


func _draw_road(r: Vector2i) -> void:
	var a := maxi(1, r.x - 1)
	var b := mini(count, r.y + 1)
	if b <= a:
		return
	var h := map_height()
	var done := PackedVector2Array()
	var ahead := PackedVector2Array()
	for i in (b - a) * ROAD_SAMPLES + 1:
		var t := float(a) + float(i) / ROAD_SAMPLES
		var p := road_point(t, size.x, h)
		if t <= float(current) + 0.001:
			done.append(p)
		if t >= float(current) - 0.001:
			ahead.append(p)
	if done.size() >= 2:
		draw_polyline(done, ROAD_DONE, ROAD_W, true)
	if ahead.size() >= 2:
		draw_polyline(ahead, ROAD_AHEAD, ROAD_W, true)


func _draw_node(n: int) -> void:
	var st := state_of(n)
	var d := diameter(n)
	var c := node_pos(n)
	if n == _shake_level and _shake > 0.0:
		c.x += sin(_shake * TAU * 3.0) * SHAKE_PX * (1.0 - _shake)
	if n == hovered and st != State.LOCKED:
		d *= HOVER_SCALE
	var rad := d * 0.5
	if st == State.LOCKED:
		draw_node_png(self, LOCKED_TEX, c, d, LOCKED_ALPHA)
		_draw_lock(c, d)
		return
	if st == State.CURRENT and pulse > 0.0:
		draw_arc(c, rad + PULSE_GROW * pulse, 0.0, TAU, 64, Color(1, 1, 1, PULSE_ALPHA * (1.0 - pulse)), PULSE_W, true)
	var col := node_color(n)
	draw_circle(c + Vector2(0.0, d * SHADOW_K), rad, Palette.SHADE)
	draw_node_png(self, node_texture(n), c, d)
	_draw_number(n, c - Vector2(0.0, d * FACE_Y_K), d, col.darkened(0.45))
	if st == State.PASSED:
		_draw_stars(c, rad, int(stars.get(n, 0)))


func _draw_number(n: int, at: Vector2, d: float, ink: Color) -> void:
	var text := str(n)
	var fs := roundi(d * DIGIT_K)
	var tw := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if tw > d * DIGIT_ROOM_K:
		fs = floori(fs * d * DIGIT_ROOM_K / tw)
		tw = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(at.x - tw * 0.5, at.y + fs * DIGIT_BASE_K)
	draw_string_outline(FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, roundi(fs * DIGIT_OUTLINE_K), ink)
	draw_string(FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_stars(c: Vector2, rad: float, got: int) -> void:
	for i in 3:
		var x := c.x + (i - 1) * STAR_DX - STAR_SIZE * 0.5
		var y := c.y + rad + STAR_DROP * STAR_SIZE - (STAR_LIFT if i == 1 else 0.0)
		draw_texture_rect(STAR_ON if i < got else STAR_OFF, Rect2(x, y, STAR_SIZE, STAR_SIZE), false)


## Плашки глав, начинающихся в видимых уровнях r (и следующей за ними — её зазор над верхним видимым кружком).
func _draw_banners(r: Vector2i) -> void:
	for n in range(r.x, mini(count, r.y + 1) + 1):
		if Chapters.is_start(n):
			_draw_banner(n)


## Середина плашки главы, начинающейся с уровня n: посреди зазора перед ним, у главы 1 — под уровнем 1.
func banner_pos(n: int) -> Vector2:
	var h := map_height()
	if n <= 1:
		return Vector2(size.x * 0.5, h - PAD_BOTTOM + FIRST_BANNER_DROP)
	var y := h - PAD_BOTTOM - (rise(float(n - 1)) + rise(float(n))) * 0.5
	return Vector2(size.x * 0.5, y)


## Текст плашки главы, начинающейся с уровня n: «ГЛАВА 4 · ЛУНА».
func banner_text(n: int) -> String:
	return tr(Chapters.HEAD) % [Chapters.number_of(n), tr(Chapters.name_of(n))]


## Ширина плашки под текст: поля BANNER_PAD, не уже BANNER_MIN_W и не шире карты без полей.
func banner_width(text: String) -> float:
	var tw := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BANNER_FONT).x
	return clampf(tw + 2.0 * BANNER_PAD, BANNER_MIN_W, maxf(BANNER_MIN_W, size.x - 40.0))


## Плашка-«конфета» главы: тень SHADE, губа темнее цвета на LIP_DARK, лицо — цвет «верх» темы главы, белая
## рамка, белый текст с обводкой темнее(цвет, 0,45). Закрытая глава (n > current) — BANNER_LOCKED_ALPHA.
func _draw_banner(n: int) -> void:
	var text := banner_text(n)
	var w := banner_width(text)
	var c := banner_pos(n)
	var col: Color = Chapters.theme_of(n)["top"]
	var a := BANNER_LOCKED_ALPHA if n > current else 1.0
	var face := Rect2(c.x - w * 0.5, c.y - BANNER_H * 0.5 - BANNER_DEPTH * 0.5, w, BANNER_H)
	var box := _banner_box
	box.set_border_width_all(0)
	box.bg_color = Color(Palette.SHADE, Palette.SHADE.a * a)
	draw_style_box(box, Rect2(face.position + Vector2(0.0, BANNER_DEPTH + BANNER_SHADOW), face.size))
	box.bg_color = Color(col.darkened(LIP_DARK), a)
	draw_style_box(box, Rect2(face.position + Vector2(0.0, BANNER_DEPTH), face.size))
	box.bg_color = Color(col, a)
	box.border_color = Color(BANNER_RIM, BANNER_RIM.a * a)
	box.set_border_width_all(roundi(BANNER_RIM_W))
	draw_style_box(box, face)
	var tw := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BANNER_FONT).x
	var fs := BANNER_FONT
	if tw > w - 2.0 * BANNER_PAD:
		fs = floori(BANNER_FONT * (w - 2.0 * BANNER_PAD) / tw)
		tw = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(face.get_center().x - tw * 0.5, face.get_center().y + fs * DIGIT_BASE_K)
	draw_string_outline(FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, roundi(fs * DIGIT_OUTLINE_K),
			Color(col.darkened(0.45), a))
	draw_string(FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))


## Замок (картинка-«конфета» с обводкой) по центру закрытого кружка.
func _draw_lock(c: Vector2, d: float) -> void:
	var side := d * LOCK_K * 256.0 / 240.0
	draw_texture_rect(LOCK_TEX, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false,
			Color(1, 1, 1, LOCK_ALPHA))
