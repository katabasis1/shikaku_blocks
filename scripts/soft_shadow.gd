class_name SoftShadow
extends ColorRect
## Мягкая тень под картинкой-родителем (docs/STYLE.md, раздел 7): размытый скруглённый прямоугольник
## (shaders/soft_shadow.gdshader), рисуется за родителем (show_behind_parent) и вместе с ним
## масштабируется и прячется. Форма — видимая часть картинки: доля shape размера родителя по центру,
## скругление round_k — доля половины меньшей стороны формы (1 — круг или таблетка).
## Тени кнопок и значков ставит CandyButton; узел внутренний (на get_children его не видно).

const SHADER: Shader = preload("res://shaders/soft_shadow.gdshader")

## Видимая часть родителя (доли его размера), по центру.
var shape := Vector2.ONE
## Скругление формы: доля половины меньшей стороны.
var round_k := 1.0
## Смещение тени, px родителя.
var offset := Vector2.ZERO
## Размытие (σ), px родителя.
var blur := 0.0
## Множитель смещения: 1 — обычная, 0,5 — нажатая кнопка (тень вдвое ближе). Можно твинить.
var near := 1.0:
	set(v):
		near = v
		if _mat != null:
			_mat.set_shader_parameter(&"offset", offset * near)

var _mat: ShaderMaterial


## Тень под parent (обычно TextureRect): внутренний узел, сразу на месте.
static func attach(parent: Control, shape_: Vector2, round_: float, offset_: Vector2, blur_: float,
		strength: float) -> SoftShadow:
	var s := SoftShadow.new()
	s.name = "Shadow"
	s.shape = shape_
	s.round_k = round_
	s.offset = offset_
	s.blur = blur_
	s._mat.set_shader_parameter(&"strength", strength)
	parent.add_child(s, false, Node.INTERNAL_MODE_FRONT)
	parent.resized.connect(s.refresh)
	s.refresh()
	return s


func _init() -> void:
	show_behind_parent = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"shade", Palette.SHADE)
	material = _mat


func get_strength() -> float:
	return float(_mat.get_shader_parameter(&"strength"))


## Поставить узел и униформы по нынешнему размеру родителя (после смены offset / blur — вызвать).
func refresh() -> void:
	var p := get_parent() as Control
	if p == null:
		return
	var ps := p.size
	var m := Vector2(blur * 3.0 + absf(offset.x), blur * 3.0 + absf(offset.y)).ceil()
	position = -m
	size = ps + m * 2.0
	var sz := ps * shape
	var lo := m + (ps - sz) * 0.5
	_mat.set_shader_parameter(&"rect_size", size)
	_mat.set_shader_parameter(&"shape_lo", lo)
	_mat.set_shader_parameter(&"shape_hi", lo + sz)
	_mat.set_shader_parameter(&"radius", minf(sz.x, sz.y) * 0.5 * round_k)
	_mat.set_shader_parameter(&"offset", offset * near)
	_mat.set_shader_parameter(&"blur", blur)
