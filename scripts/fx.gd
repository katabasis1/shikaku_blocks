class_name Fx
extends RefCounted
## Мелкие эффекты интерфейса, общие для сцен.

const FLOATING_TEXT_SCENE: PackedScene = preload("res://scenes/ui/floating_text.tscn")
const PULSE_META := &"pulse_tween"
const HOP_META := &"hop_tween"


## Дважды «пульсирует» элемент (например, кнопку отмены в тупике). Возвращается
## к масштабу «в покое»: под мышью он чуть больше 1 (Desktop.set_hovered).
static func pulse(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	# Повторный вызов не должен накладывать твины друг на друга; наведение тоже ведёт масштаб.
	for key in [PULSE_META, Desktop.TWEEN_META]:
		var prev = c.get_meta(key, null)
		if prev is Tween and (prev as Tween).is_valid():
			(prev as Tween).kill()
	var rest := Vector2.ONE * float(c.get_meta(Desktop.REST_META, 1.0))
	c.scale = rest
	var t := c.create_tween()
	c.set_meta(PULSE_META, t)
	for _k in 2:
		t.tween_property(c, "scale", rest * 1.2, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(c, "scale", rest, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Всплывающий текст (очки, «Отлично!») в точке global_pos на слое layer.
## Тупик (14.6g): лицо круглой кнопки (CandyButton) дважды подпрыгивает — на dead_hop px и на 55 % от этого,
## прыжок за dead_hop_time, с; тень остаётся на месте. Не CandyButton или «Меньше движения» — прежний pulse.
static func hop(c: Control) -> void:
	var btn := c as CandyButton
	if btn == null or GameState.reduce_motion:
		pulse(c)
		return
	var prev = c.get_meta(HOP_META, null)
	if prev is Tween and (prev as Tween).is_valid():
		(prev as Tween).kill()
	btn.set_hop(0.0)
	var cfg := Juice.shared_config()
	var half := maxf(cfg.dead_hop_time, 0.02) * 0.5
	var t := c.create_tween()
	c.set_meta(HOP_META, t)
	for k in 2:
		var h := cfg.dead_hop * (1.0 if k == 0 else 0.55)
		t.tween_method(btn.set_hop, 0.0, h, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_method(btn.set_hop, h, 0.0, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


static func float_text(layer: Control, text: String, global_pos: Vector2, color: Color, font_size: int) -> void:
	var ft := FLOATING_TEXT_SCENE.instantiate() as FloatingText
	layer.add_child(ft)
	ft.global_position = global_pos
	ft.setup(text, color, font_size)


## Текст комбо (14.4) в точке global_pos на слое layer: «штамп» силы хода power (Game: (линий − 1) + (серия − 1))
## — шрифт combo_text_size + combo_text_grow · сила, влетает с масштабом combo_slam + combo_slam_grow · сила и
## прибивается с дожимом и лёгкой тряской (JuiceConfig, группа «Линия и серия»). «Меньше движения» — без штампа.
static func combo_text(layer: Control, text: String, global_pos: Vector2, color: Color, power: int) -> FloatingText:
	var c := Juice.shared_config()
	var p := maxi(power, 0)
	var ft := FLOATING_TEXT_SCENE.instantiate() as FloatingText
	layer.add_child(ft)
	ft.global_position = global_pos
	var calm := GameState.reduce_motion
	ft.slam(text, color, c.combo_text_size + c.combo_text_grow * p, 0.0 if calm else c.combo_slam + c.combo_slam_grow * p,
			c.combo_slam_time, 0.0 if calm else c.combo_slam_trauma)
	return ft
