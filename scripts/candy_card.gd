class_name CandyCard
extends PanelContainer
## Карточка окна (docs/STYLE.md, раздел 11; стиль-кадр A3B_win): белое лицо с лавандовым градиентом,
## радиус 46, губа 14 px (#C4B0FF), мягкая тень DEEP 55 % (вниз 18, размытие 26), шапка 104 px
## с глянцевой полосой и разделителем 5 px. Шапка оранжевая у победы, фиолетовая у паузы, настроек
## и подтверждений (STYLE 11, кадр G13_5_panels), без шапки — HEAD_NONE.
## Сама PanelContainer ничего не рисует (тип темы CandyCard — пустой StyleBox с полями; CandyCardFlat —
## без полей, для окна победы с местами по стиль-кадру). Рисует внутренний узел Body (ColorRect
## с shaders/card.gdshader) за карточкой: он больше карточки на поля под тень и губу.
## Размер узла = лицо карточки (512×428 у победы), губа и тень — ниже и вокруг, вне узла.
## Заголовок в шапке — первый ребёнок-Label высотой head_height (тип темы CardTitle).

const SHADER: Shader = preload("res://shaders/card.gdshader")

enum Head { NONE, ORANGE, VIOLET }

const RADIUS := 46.0
const LIP := 14.0
const LINE := 5.0
const SHADOW_OFFSET := Vector2(0.0, 18.0)
const SHADOW_BLUR := 26.0
const SHADOW_ALPHA := 0.55
## Цвета шапки: верх, низ, разделитель.
const ORANGE := [Color("#FFC247"), Color("#FF7B3A"), Color("#E0602A")]
const VIOLET := [Color("#8B6CF6"), Color("#6A42E4"), Color("#5530C8")]

## Цвет шапки (NONE — без шапки).
@export var head_style: Head = Head.VIOLET:
	set(v):
		head_style = v
		_apply_head()
## Высота шапки, px.
@export var head_height := 104.0:
	set(v):
		head_height = v
		_apply_head()

var body: ColorRect
var _mat: ShaderMaterial


func _init() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	body = ColorRect.new()
	body.name = "Body"
	body.show_behind_parent = true
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.color = Color.WHITE
	body.material = _mat
	var sh := Palette.DEEP
	sh.a = SHADOW_ALPHA
	_mat.set_shader_parameter(&"shadow_color", sh)
	_mat.set_shader_parameter(&"shadow_offset", SHADOW_OFFSET)
	_mat.set_shader_parameter(&"shadow_blur", SHADOW_BLUR)
	_mat.set_shader_parameter(&"radius", RADIUS)
	_mat.set_shader_parameter(&"lip", LIP)
	_mat.set_shader_parameter(&"line", LINE)


func _ready() -> void:
	add_child(body, false, Node.INTERNAL_MODE_FRONT)
	resized.connect(refresh)
	sort_children.connect(refresh)
	_apply_head()
	refresh()


## Поля узла Body вокруг карточки: тень (3σ + смещение) и губа.
static func body_margin() -> Vector2:
	return Vector2(ceilf(SHADOW_BLUR * 3.0 + absf(SHADOW_OFFSET.x)),
			ceilf(SHADOW_BLUR * 3.0 + SHADOW_OFFSET.y + LIP))


## Поставить Body и униформы по нынешнему размеру карточки.
func refresh() -> void:
	if body == null:
		return
	var m := body_margin()
	body.position = -m
	body.size = size + m * 2.0
	_mat.set_shader_parameter(&"rect_size", body.size)
	_mat.set_shader_parameter(&"face_lo", m)
	_mat.set_shader_parameter(&"face_hi", m + size)


func _apply_head() -> void:
	if _mat == null:
		return
	var cols: Array = ORANGE if head_style == Head.ORANGE else VIOLET
	_mat.set_shader_parameter(&"head", 0.0 if head_style == Head.NONE else head_height)
	_mat.set_shader_parameter(&"head_top", cols[0])
	_mat.set_shader_parameter(&"head_bottom", cols[1])
	_mat.set_shader_parameter(&"head_line", cols[2])
