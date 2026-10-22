class_name FloatingText
extends Control
## Всплывающий текст: очки (+40) — setup, анимация «float» в floating_text.tscn; текст комбо («Супер!», 14.4) — slam,
## «штамп» на твинах Juice (hit-stop его останавливает).

## «Штамп» прибивается чуть мельче 1 и с дожимом возвращается; держится SLAM_HOLD, с, потом всплывает на
## SLAM_RISE px за SLAM_FLY, с, и гаснет.
const SLAM_UNDER := 0.92
const SLAM_HOLD := 0.35
const SLAM_RISE := 110.0
const SLAM_FLY := 0.6

@onready var text_label: Label = $Text
@onready var anim: AnimationPlayer = $AnimationPlayer

## Твин «штампа» (slam; selftest: он — через Juice).
var slam_tween: Tween


func setup(text: String, color: Color = Color.WHITE, font_size: int = 46) -> void:
	text_label.text = text
	text_label.add_theme_color_override("font_color", color)
	text_label.add_theme_font_size_override("font_size", font_size)
	anim.animation_finished.connect(func(_name: StringName) -> void: queue_free())
	anim.play("float")


## Текст комбо (14.4): «штамп» — влетает с масштабом slam_scale и за slam_time прибивается (в миг касания — тряска
## с травмой trauma), дожим до 1, держится и всплывает, гаснет. slam_scale <= 1 — без штампа: проявляется за 0,15 с.
## Твины — через Juice (вне игры — обычные).
func slam(text: String, color: Color, font_size: int, slam_scale: float, slam_time: float, trauma: float) -> void:
	text_label.text = text
	text_label.add_theme_color_override("font_color", color)
	text_label.add_theme_font_size_override("font_size", font_size)
	var j := Juice.of(self)
	var t := j.tween(self) if j != null else create_tween()
	slam_tween = t
	var lbl := text_label
	var y0 := lbl.position.y
	lbl.modulate.a = 0.0
	if slam_scale > 1.0:
		lbl.scale = Vector2.ONE * slam_scale
		t.tween_property(lbl, "scale", Vector2.ONE * SLAM_UNDER, maxf(slam_time, 0.01)).set_trans(Tween.TRANS_QUAD) \
				.set_ease(Tween.EASE_IN)
		t.parallel().tween_property(lbl, "modulate:a", 1.0, maxf(slam_time, 0.01) * 0.6)
		if trauma > 0.0 and j != null:
			t.tween_callback(j.add_trauma.bind(trauma))
		t.tween_property(lbl, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		lbl.scale = Vector2.ONE
		t.tween_property(lbl, "modulate:a", 1.0, 0.15)
	t.tween_interval(SLAM_HOLD)
	t.tween_property(lbl, "position:y", y0 - SLAM_RISE, SLAM_FLY).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(lbl, "modulate:a", 0.0, SLAM_FLY * 0.6).set_delay(SLAM_FLY * 0.4)
	t.tween_callback(queue_free)
