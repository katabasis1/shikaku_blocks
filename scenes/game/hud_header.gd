class_name HudHeader
extends Control
## Середина шапки игры (docs/STYLE.md, разделы 3 и 13): «УРОВЕНЬ N» и счёт со звездой.
##   Заголовок — Nunito 1000, белый, обводка INK 0,13·размер, тень DEEP 67 % вниз на 0,12·размер.
##   Счёт — Nunito 1000, #FFE45C, обводка INK 0,13·размер, тень DEEP 59 % вниз на 0,1·размер;
##   слева звезда star.png (видимая ширина 1,05·размер, тень по форме — TexShadow), строка
##   «звезда + число» по центру.
## Центры строк (от верха узла) и размеры шрифта задаёт раскладка: configure(…) из Game.apply_layout
## (GameLayout: title_y, score_y, title_size, score_size). Узел — середина TopBar между кнопками;
## длинный заголовок (уровень 500, перевод) уменьшается, пока не влезет по ширине.
## Обводка в Godot (outline_size) — полная толщина, вдвое больше толщины с каждой стороны в STYLE.

## Обводка и тень — доли размера шрифта.
const TITLE_OUTLINE := 0.13
const TITLE_SHADOW := 0.12
const TITLE_SHADOW_ALPHA := 0.67
const SCORE_OUTLINE := 0.13
const SCORE_SHADOW := 0.1
const SCORE_SHADOW_ALPHA := 0.59
## Заголовок не мельче этого при ужатии по ширине.
const TITLE_MIN_SIZE := 24
## Звезда: видимая ширина — доля размера шрифта счёта; в star.png звезда занимает 240 из 256 px.
const STAR_W := 1.05
const STAR_FIT := 240.0 / 256.0
## Строка счёта (доли размера шрифта, как в стиль-кадре): квадрат PNG звезды начинается через STAR_X
## от левого края строки, число — через TEXT_X; середина звезды выше середины строки на STAR_RISE.
const STAR_X := 0.04
const TEXT_X := 1.45
const STAR_RISE := 0.105
## Тень звезды (STYLE, раздел 7): вниз 0,14 R, размытие 0,18 R, #5A2A00 35 %; R = 0,6·размер шрифта.
const STAR_R := 0.6
const STAR_SHADOW := Color(0.353, 0.165, 0.0)
const STAR_SHADOW_ALPHA := 0.35

@onready var level_label: Label = $LevelLabel
@onready var star: TextureRect = $StarIcon
@onready var score_label: Label = $ScoreLabel

## Размеры шрифта и центры строк по высоте (px от верха узла) — из раскладки.
var title_size := 50
var score_size := 38
var title_y := 34.0
var score_y := 88.0

var star_shadow: TexShadow


func _ready() -> void:
	star_shadow = TexShadow.attach(star, Vector2.ZERO, 0.0, STAR_SHADOW, STAR_SHADOW_ALPHA)
	resized.connect(relayout)
	relayout()


## Размеры шрифтов и центры строк для раскладки (портрет / альбом).
func configure(title_size_: int, score_size_: int, title_y_: float, score_y_: float) -> void:
	title_size = title_size_
	score_size = score_size_
	title_y = title_y_
	score_y = score_y_
	relayout()


## Номер уровня и счёт; title — свой заголовок вместо «УРОВЕНЬ N» (уже переведённый: ежедневная задача, 18.1f).
func show_values(level: int, score: int, title: String = "") -> void:
	level_label.text = title if not title.is_empty() else tr("УРОВЕНЬ %d") % level
	score_label.text = format_score(score)
	relayout()


## Счёт с разделителем разрядов, как в стиль-кадре («2 340»): по-русски неразрывный пробел,
## по-английски запятая, по-турецки точка.
static func format_score(n: int) -> String:
	var digits := str(absi(n))
	var sep := String.chr(0xA0)
	var locale := TranslationServer.get_locale()
	if locale.begins_with("en"):
		sep = ","
	elif locale.begins_with("tr"):
		sep = "."
	var out := ""
	while digits.length() > 3:
		out = sep + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


## Размер шрифта заголовка: из раскладки или меньше, если текст с обводкой не влезает по ширине.
func fitted_title_size() -> int:
	var font := level_label.get_theme_font(&"font")
	var tw := font.get_string_size(level_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	var room := size.x - 2.0 * TITLE_OUTLINE * title_size
	if tw <= room or tw <= 0.0:
		return title_size
	return maxi(TITLE_MIN_SIZE, floori(title_size * room / tw))


## Расставить заголовок, звезду и число по нынешним тексту, размеру узла и раскладке.
func relayout() -> void:
	if not is_node_ready():
		return
	var w := size.x
	var ts := fitted_title_size()
	style_label(level_label, ts, TITLE_OUTLINE, TITLE_SHADOW, TITLE_SHADOW_ALPHA)
	level_label.size = Vector2(w, 0.0)  # высота — наименьшая (строка шрифта)
	level_label.position = Vector2(0.0, title_y - level_label.size.y * 0.5)

	layout_score_row(star, star_shadow, score_label, w, score_y, score_size)


## Строка счёта «звезда + число» по центру ширины w, середина строки — на высоте y (в координатах
## родителя звезды и числа), размер шрифта ss. Ею же расставлен счёт в меню (STYLE 11.1).
static func layout_score_row(star_: TextureRect, shadow: TexShadow, label: Label, w: float, y: float,
		ss: int) -> void:
	style_label(label, ss, SCORE_OUTLINE, SCORE_SHADOW, SCORE_SHADOW_ALPHA)
	var font := label.get_theme_font(&"font")
	var tw := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, ss).x
	var x0 := (w - (TEXT_X * ss + tw)) * 0.5
	var box := STAR_W * ss / STAR_FIT
	star_.size = Vector2(box, box)
	star_.position = Vector2(x0 + STAR_X * ss, y - STAR_RISE * ss - box * 0.5)
	var r := STAR_R * ss
	shadow.offset = Vector2(0.0, 0.14 * r)
	shadow.blur = 0.18 * r
	shadow.refresh()
	label.size = Vector2(ceilf(tw), 0.0)
	label.position = Vector2(x0 + TEXT_X * ss, y - label.size.y * 0.5)


## Размер шрифта, обводка (полная толщина = 2·доля·размер) и тень (вниз доля·размер, DEEP с alpha;
## тень обведена так же, как текст). Им же оформлен заголовок победы (WinPanel).
static func style_label(l: Label, fs: int, outline: float, shadow: float, shadow_alpha: float) -> void:
	var o := roundi(2.0 * outline * fs)
	l.add_theme_font_size_override(&"font_size", fs)
	l.add_theme_constant_override(&"outline_size", o)
	l.add_theme_constant_override(&"shadow_outline_size", o)
	l.add_theme_constant_override(&"shadow_offset_x", 0)
	l.add_theme_constant_override(&"shadow_offset_y", roundi(shadow * fs))
	l.add_theme_color_override(&"font_outline_color", Palette.INK)
	var c := Palette.DEEP
	c.a = shadow_alpha
	l.add_theme_color_override(&"font_shadow_color", c)
