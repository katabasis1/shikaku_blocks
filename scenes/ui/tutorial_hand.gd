class_name TutorialHand
extends Control
## Рука для обучения: показывает жест «нажми» (поворот блока) и «перетащи»
## из точки from в точку to (play) или просто «нажми сюда» (tap — кнопка «Отмена»).
## Ввод не ловит — игрок может сразу повторить ход.
## Когда и что показать, решает TutorialCoach (scenes/game/tutorial_coach.gd).

## Рука «донесла» блок до места — игра подсвечивает клетки.
signal arrived
## Жест показан до конца и рука исчезла.
signal finished

const FADE_TIME := 0.2
const TAP_TIME := 0.12
const TAP_PAUSE := 0.3
const MOVE_TIME := 0.85
const HOLD_TIME := 0.45
const PRESS_SCALE := Vector2(0.84, 0.84)

@onready var hand: Control = %Hand
@onready var ring: Control = %Ring

var _tween: Tween
var _ring_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


func is_playing() -> bool:
	return visible and _tween != null and _tween.is_valid()


## from и to — глобальные точки (кончик пальца). taps — сколько раз «нажать»
## в from перед перетаскиванием: 1 — показать, что блок надо повернуть.
func play(from: Vector2, to: Vector2, taps: int = 0) -> void:
	stop()
	position = _to_local(from)
	modulate.a = 0.0
	hand.scale = Vector2.ONE
	show()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_TIME)
	for _k in taps:
		_tween.tween_property(hand, "scale", PRESS_SCALE, TAP_TIME)
		_tween.tween_callback(_ring_pulse)
		_tween.tween_property(hand, "scale", Vector2.ONE, TAP_TIME)
		_tween.tween_interval(TAP_PAUSE)
	# Нажали — повели — отпустили.
	_tween.tween_property(hand, "scale", PRESS_SCALE, TAP_TIME)
	_tween.tween_callback(_ring_pulse)
	_tween.tween_property(self, "position", _to_local(to), MOVE_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(arrived.emit)
	_tween.tween_property(hand, "scale", Vector2.ONE, TAP_TIME)
	_tween.tween_interval(HOLD_TIME)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME * 1.25)
	_tween.tween_callback(_on_done)


## Жест «нажми сюда» times раз в глобальной точке at (arrived не приходит).
func tap(at: Vector2, times: int = 2) -> void:
	stop()
	position = _to_local(at)
	modulate.a = 0.0
	hand.scale = Vector2.ONE
	show()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_TIME)
	for _k in times:
		_tween.tween_property(hand, "scale", PRESS_SCALE, TAP_TIME)
		_tween.tween_callback(_ring_pulse)
		_tween.tween_property(hand, "scale", Vector2.ONE, TAP_TIME)
		_tween.tween_interval(TAP_PAUSE)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME * 1.25)
	_tween.tween_callback(_on_done)


## Прячет руку сразу (игрок начал ход, пауза, новый уровень). finished не приходит.
func stop() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if _ring_tween and _ring_tween.is_valid():
		_ring_tween.kill()
	ring.modulate.a = 0.0
	hide()


func _on_done() -> void:
	hide()
	finished.emit()


## Круг «касания» под пальцем.
func _ring_pulse() -> void:
	if _ring_tween and _ring_tween.is_valid():
		_ring_tween.kill()
	ring.scale = Vector2(0.4, 0.4)
	ring.modulate.a = 0.9
	_ring_tween = create_tween().set_parallel()
	_ring_tween.tween_property(ring, "scale", Vector2(1.3, 1.3), 0.35).set_ease(Tween.EASE_OUT)
	_ring_tween.tween_property(ring, "modulate:a", 0.0, 0.35)


func _to_local(global_point: Vector2) -> Vector2:
	var parent := get_parent() as CanvasItem
	if parent == null:
		return global_point
	return parent.get_global_transform().affine_inverse() * global_point
