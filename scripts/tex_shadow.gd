class_name TexShadow
extends ColorRect
## Мягкая тень по форме картинки-родителя (docs/STYLE.md, раздел 7): альфа его текстуры, размытая
## и сдвинутая (shaders/tex_shadow.gdshader). Для фигурных PNG — звезда счёта, звёзды победы (13.5);
## круглым кнопкам и значкам хватает SoftShadow. Узел внутренний, рисуется за родителем
## (show_behind_parent) и вместе с ним масштабируется и прячется.
## Родитель рисует текстуру на весь свой прямоугольник (stretch_mode SCALE).
## Качество (14.7): на низком (Quality.LOW) — 9 отсчётов вместо 49 (LOW_REACH, LOW_STEP, mip выше на
## log2(blur) + LOW_LOD_SHIFT; см. шапку шейдера); узел слушает Quality.changed.

const SHADER: Shader = preload("res://shaders/tex_shadow.gdshader")
## Отсчётов в каждую сторону и шаг (доля σ): обычно (7×7) и на низком качестве (3×3).
const REACH := 3
const STEP := 0.75
const LOW_REACH := 1
const LOW_STEP := 1.25
## На низком mip-уровень выше на log2(blur) + LOW_LOD_SHIFT (не меньше 0).
const LOW_LOD_SHIFT := -0.5

## Смещение тени и размытие (σ), px родителя. После смены — refresh().
var offset := Vector2.ZERO
var blur := 0.0

var _mat: ShaderMaterial
var _reach := REACH


## Тень под parent: внутренний узел, сразу на месте.
static func attach(parent: TextureRect, offset_: Vector2, blur_: float, shade: Color,
		strength: float) -> TexShadow:
	var s := TexShadow.new()
	s.name = "Shadow"
	s.offset = offset_
	s.blur = blur_
	s._mat.set_shader_parameter(&"shade", shade)
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
	material = _mat


func _ready() -> void:
	Quality.changed.connect(_on_quality_changed)


func get_strength() -> float:
	return float(_mat.get_shader_parameter(&"strength"))


## Отсчётов размытия на пиксель: 49 обычно, 9 на низком качестве (selftest).
func samples() -> int:
	return (2 * _reach + 1) * (2 * _reach + 1)


## Поставить узел и униформы по нынешнему размеру и текстуре родителя.
func refresh() -> void:
	var p := get_parent() as TextureRect
	if p == null:
		return
	var m := (Vector2(blur, blur) * 3.0 + offset.abs()).ceil()
	position = -m
	size = p.size + m * 2.0
	_mat.set_shader_parameter(&"src", p.texture)
	_mat.set_shader_parameter(&"rect_size", size)
	_mat.set_shader_parameter(&"tex_lo", m)
	_mat.set_shader_parameter(&"tex_size", p.size)
	_mat.set_shader_parameter(&"offset", offset)
	_mat.set_shader_parameter(&"blur", blur)
	_apply_quality()


## Сетка отсчётов по уровню качества (Quality.level).
func _apply_quality() -> void:
	var low := Quality.level == Quality.LOW
	_reach = LOW_REACH if low else REACH
	_mat.set_shader_parameter(&"reach", _reach)
	_mat.set_shader_parameter(&"step_k", LOW_STEP if low else STEP)
	_mat.set_shader_parameter(&"lod_bias", maxf(log(maxf(blur, 1.0)) / log(2.0) + LOW_LOD_SHIFT, 0.0) if low else 0.0)


func _on_quality_changed(_level: int) -> void:
	_apply_quality()
