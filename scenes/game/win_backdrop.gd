class_name WinBackdrop
extends Control
## Фон победы за полем (docs/STYLE.md, раздел 11; стиль-кадр A3B_win; 13.5b): лучи и мягкое свечение от
## центра поля (Rays, shaders/win_rays.gdshader) и конфетти (Confetti). Узел game.tscn стоит сразу за
## Background — под Content (поле, HUD) и окном победы: конфетти не летят поверх заголовка, поля и
## карточки, видны только на фоне вокруг них.
## Game: play(центр поля) при показе победы, set_center(…) при смене раскладки, stop() при новом уровне.

const SHADER: Shader = preload("res://shaders/win_rays.gdshader")
## Проявление лучей и свечения, с; когда после play() стреляет конфетти, с.
const FADE_IN := 0.4
const CONFETTI_DELAY := 0.1
## Лучи и свечение в кадре — для поля 520 px (клетка 80 на 6×6): радиус лучей и полуоси свечения
## растут вместе с полем (от этой стороны), но не меньше, чем в кадре.
const FRAME_BOARD := 520.0
const RAYS_RADIUS := 760.0
const GLOW_RADIUS := Vector2(330.0, 335.0)

var rays: ColorRect
var confetti: Confetti

var _mat: ShaderMaterial
var _tween: Tween
var _center := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	rays = ColorRect.new()
	rays.name = "Rays"
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.color = Color.WHITE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	rays.material = _mat
	add_child(rays)
	rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confetti = Confetti.new()
	confetti.name = "Confetti"
	add_child(confetti)
	confetti.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_update_rect)


## Показать фон победы вокруг поля: center — середина поля, board_side — его большая сторона (px узла).
func play(center: Vector2, board_side: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	set_center(center, board_side)
	show()
	rays.modulate.a = 0.0
	confetti.stop()
	_tween = create_tween()
	_tween.tween_property(rays, "modulate:a", 1.0, FADE_IN)
	_tween.parallel().tween_callback(confetti.burst.bind(center)).set_delay(CONFETTI_DELAY)


## Центр лучей и свечения (и размер под поле) — после смены раскладки во время победы.
func set_center(center: Vector2, board_side: float) -> void:
	_center = center
	var k := maxf(1.0, board_side / FRAME_BOARD)
	_mat.set_shader_parameter(&"center", center)
	_mat.set_shader_parameter(&"radius", RAYS_RADIUS * k)
	_mat.set_shader_parameter(&"glow_radius", GLOW_RADIUS * k)
	_update_rect()


func stop() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	confetti.stop()
	hide()


func get_center() -> Vector2:
	return _center


func _update_rect() -> void:
	_mat.set_shader_parameter(&"rect_size", size)
