class_name ChapterCard
extends Control
## Карточка начала главы (19.5d, docs/STYLE.md 11.6). Первый уровень главы 2 и дальше, пока он не пройден (это
## текущий уровень игрока), — один раз за сцену игры (wanted): над серединой поля «конфета» цвета «верх» темы
## главы — «ГЛАВА N» мелко, название крупно и идея главы (Chapters.idea_of) строкой ниже, если она есть.
## Появляется толчком (×POP_FROM → 1, прозрачность 0 → 1), держится HOLD (с идеей — HOLD_IDEA), уходит вверх на
## RISE с растворением. Нажатий не ловит: любое нажатие убирает её раньше (Game._input → dismiss), игра под ней
## идёт как обычно (14.8c: в игре нажатия ловят только кнопки, гнёзда лотка и окна). «Меньше движения» — только
## прозрачность. Рисует себя в _draw, как плашки глав MapPath (материал «конфеты», текст с обводкой).

const HEAD := "ГЛАВА %d"  # msgid
## Лицо: ширина (не шире места поля без SIDE с боков), поля текста, скругление, губа вниз (темнее цвета на
## MapPath.LIP_DARK), тень Palette.SHADE ниже губы ещё на SHADOW, белая рамка.
const W := 600.0
const SIDE := 20.0
const PAD := 24.0
const RADIUS := 36.0
const DEPTH := 8.0
const SHADOW := 6.0
const RIM := Color(1, 1, 1, 0.6)
const RIM_W := 3.0
## Шрифт Nunito 1000 (как числа и плашки карты): «ГЛАВА N» (белый HEAD_ALPHA), название, идея.
const HEAD_FONT := 28
const NAME_FONT := 60
const IDEA_FONT := 26
const HEAD_ALPHA := 0.8
## Ряды сверху вниз: поле TOP, «ГЛАВА N», GAP, название, (IDEA_GAP, идея), поле BOTTOM.
const TOP := 18.0
const HEAD_ROW := 32.0
const GAP := 4.0
const NAME_ROW := 66.0
const IDEA_GAP := 6.0
const IDEA_ROW := 30.0
const BOTTOM := 22.0
## Движение, с: пауза после начала уровня (поле успевает начать появляться), толчок, держится, уход.
const IN_DELAY := 0.2
const POP_FROM := 0.7
const POP_TIME := 0.35
const FADE_IN := 0.15
const HOLD := 1.8
const HOLD_IDEA := 2.6
const RISE := 40.0
const FADE_OUT := 0.3
const FONT: Font = preload("res://assets/fonts/nunito_black.ttf")

var level := 0
var head := ""
var title := ""
var idea := ""
var color := Color.WHITE
var _area := Rect2()
var _lift := 0.0
var _tween: Tween
var _hiding := false
var _box: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_box = StyleBoxFlat.new()
	_box.set_corner_radius_all(roundi(RADIUS))
	_box.anti_aliasing = true


## Нужна ли карточка на уровне n: обычный уровень (own — не ежедневная и не «Лаборатория»), начало главы 2 и
## дальше, ещё не пройден (n — текущий уровень игрока current) и в этой сцене для него карточки не было (shown —
## последний уровень с карточкой). «Заново» и переигровка с карты карточку не повторяют.
static func wanted(n: int, current: int, own: bool, shown: int) -> bool:
	return own and n > 1 and Chapters.is_start(n) and n == current and n != shown


## Нажатие (мышь, касание, клавиша) — карточка уходит раньше.
static func is_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey:
		return event.is_pressed() and not event.is_echo()
	return false


## Язык сменился, пока карточка видна, — тексты на новом языке.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and visible and level > 0:
		_set_texts(level)
		_fit()


## Место поля от раскладки: карточка — по его центру.
func place(r: Rect2) -> void:
	_area = r
	_fit()


func card_width() -> float:
	if _area.size.x <= 0.0:
		return W
	return clampf(_area.size.x - 2.0 * SIDE, 0.0, W)


## Высота лица (без губы и тени).
func card_height() -> float:
	var h := TOP + HEAD_ROW + GAP + NAME_ROW + BOTTOM
	if not idea.is_empty():
		h += IDEA_GAP + IDEA_ROW
	return h


func hold_time() -> float:
	return HOLD if idea.is_empty() else HOLD_IDEA


## Сколько карточка на экране от начала уровня до конца ухода (без нажатий).
func total_time() -> float:
	return IN_DELAY + maxf(FADE_IN, POP_TIME) + hold_time() + FADE_OUT


## Видна и ещё не уходит.
func is_shown() -> bool:
	return visible and not _hiding


## Показать карточку главы уровня n (тексты — на текущем языке).
func show_chapter(n: int) -> void:
	clear()
	level = n
	_set_texts(n)
	color = Chapters.theme_of(n)["top"]
	_fit()
	visible = true
	modulate.a = 0.0
	var calm := GameState.reduce_motion
	scale = Vector2.ONE if calm else Vector2.ONE * POP_FROM
	queue_redraw()
	_tween = create_tween()
	_tween.tween_interval(IN_DELAY)
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN)
	if not calm:
		_tween.parallel().tween_property(self, "scale", Vector2.ONE, POP_TIME) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(hold_time())
	_tween.tween_callback(_hide)


func _set_texts(n: int) -> void:
	head = tr(HEAD) % Chapters.number_of(n)
	title = tr(Chapters.name_of(n))
	var id := Chapters.idea_of(n)
	idea = tr(id) if not id.is_empty() else ""


## Убрать раньше (нажатие игрока): уход вверх с растворением.
func dismiss() -> void:
	if not visible or _hiding:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_hide()


## Сразу спрятать (новый уровень, победа).
func clear() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
	_on_hidden()


func _hide() -> void:
	_hiding = true
	scale = Vector2.ONE
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	if not GameState.reduce_motion:
		_tween.tween_method(_set_lift, _lift, RISE, FADE_OUT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(_on_hidden)


func _on_hidden() -> void:
	_hiding = false
	visible = false
	modulate.a = 1.0
	scale = Vector2.ONE
	_set_lift(0.0)


func _set_lift(v: float) -> void:
	_lift = v
	_fit()


func _fit() -> void:
	var w := card_width()
	var h := card_height()
	size = Vector2(w, h + DEPTH + SHADOW)
	pivot_offset = Vector2(w, h) * 0.5
	var c: Vector2 = _area.get_center() if _area.size.x > 0.0 else Vector2(w, h) * 0.5
	position = c - Vector2(w, h + DEPTH) * 0.5 - Vector2(0.0, _lift)
	queue_redraw()


## Размер шрифта строки text: не шире лица без PAD с боков (иначе ужимается).
func font_size_for(text: String, fs: int) -> int:
	var room := card_width() - 2.0 * PAD
	var tw := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if tw > room and tw > 0.0:
		return floori(fs * room / tw)
	return fs


func _draw() -> void:
	var w := size.x
	var face := Rect2(0.0, 0.0, w, card_height())
	_box.set_border_width_all(0)
	_box.bg_color = Palette.SHADE
	draw_style_box(_box, Rect2(Vector2(0.0, DEPTH + SHADOW), face.size))
	_box.bg_color = color.darkened(MapPath.LIP_DARK)
	draw_style_box(_box, Rect2(Vector2(0.0, DEPTH), face.size))
	_box.bg_color = color
	_box.border_color = RIM
	_box.set_border_width_all(roundi(RIM_W))
	draw_style_box(_box, face)
	var ink := color.darkened(0.45)
	var y := TOP
	_text(head, HEAD_FONT, y + HEAD_ROW * 0.5, Color(1, 1, 1, HEAD_ALPHA), ink)
	y += HEAD_ROW + GAP
	_text(title, NAME_FONT, y + NAME_ROW * 0.5, Color.WHITE, ink)
	if not idea.is_empty():
		y += NAME_ROW + IDEA_GAP
		_text(idea, IDEA_FONT, y + IDEA_ROW * 0.5, Color.WHITE, ink)


## Строка по центру лица, середина заглавных — на высоте cy (как числа кружков карты), белая с обводкой ink.
func _text(text: String, fs0: int, cy: float, col: Color, ink: Color) -> void:
	var fs := font_size_for(text, fs0)
	var tw := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2((size.x - tw) * 0.5, cy + fs * MapPath.DIGIT_BASE_K)
	draw_string_outline(FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, roundi(fs * MapPath.DIGIT_OUTLINE_K),
			Color(ink, col.a))
	draw_string(FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
