class_name PillLabel
extends Label
## Подпись на плашке-таблетке (docs/STYLE.md, разделы 3, 4 и 13; «Осталось блоков»).
## Узел занимает отведённое раскладкой место, текст — по центру; плашка шириной в текст + PAD_X
## с каждой стороны и высотой HEIGHT_K·размер шрифта стоит по центру узла, на TEXT_RISE ниже текста.
## Рисует её внутренний узел Pill (ColorRect с shaders/pill.gdshader) за текстом. Размер плашки
## обновляется сам при смене текста, шрифта и размера узла: на всё это Label перерисовывается
## (сигнал draw), а плашка подгоняется отложенно, после отрисовки.

const SHADER: Shader = preload("res://shaders/pill.gdshader")
## Поля плашки слева и справа от текста, px.
const PAD_X := 24.0
## Высота плашки — доля размера шрифта.
const HEIGHT_K := 1.9
## Текст выше середины плашки на столько px (как в стиль-кадре).
const TEXT_RISE := 1.0

var pill: ColorRect
var _mat: ShaderMaterial
var _fit_queued := false


func _ready() -> void:
	pill = ColorRect.new()
	pill.name = "Pill"
	pill.show_behind_parent = true
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.color = Color.WHITE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	pill.material = _mat
	add_child(pill, false, Node.INTERNAL_MODE_FRONT)
	draw.connect(_queue_fit)
	fit()


## Прямоугольник плашки для нынешнего текста, в координатах узла.
func pill_rect() -> Rect2:
	var fs := get_theme_font_size(&"font_size")
	var tw := get_theme_font(&"font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var s := Vector2(ceilf(tw + PAD_X * 2.0), roundf(fs * HEIGHT_K))
	return Rect2(((size - s) * 0.5 + Vector2(0.0, TEXT_RISE)).round(), s)


## Подогнать плашку под текст сейчас (обычно само, после перерисовки).
func fit() -> void:
	_fit_queued = false
	if pill == null:
		return
	var r := pill_rect()
	pill.position = r.position
	pill.size = r.size
	pill.visible = not text.is_empty()
	_mat.set_shader_parameter(&"rect_size", r.size)


func _queue_fit() -> void:
	if not _fit_queued:
		_fit_queued = true
		fit.call_deferred()
