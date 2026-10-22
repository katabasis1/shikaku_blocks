class_name Desktop
extends RefCounted
## Мелочи для мыши и клавиатуры (docs/DESKTOP.md): наведение, курсор-«рука», клавиши по месту.
## Наведение срабатывает только от настоящей мыши: касание на телефоне Godot превращает
## в мышь с device = InputEvent.DEVICE_ID_EMULATION — такие события пропускаем,
## и на таче кнопки не «залипают» увеличенными.

## Элемент под мышью чуть крупнее.
const HOVER_SCALE := 1.05
const HOVER_TIME := 0.1
## Масштаб «в покое» (1 или HOVER_SCALE) — к нему возвращается Fx.pulse.
const REST_META := &"rest_scale"
const TWEEN_META := &"hover_tween"


## Клавиша code нажата (не автоповтор). Сравниваем по месту на клавиатуре (physical_keycode):
## Z, H и R работают и в русской, и в турецкой раскладке. У событий без физического кода
## (экранные клавиатуры) — по keycode.
static func key_pressed(event: InputEvent, code: Key) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return false
	if k.physical_keycode != KEY_NONE:
		return k.physical_keycode == code
	return k.keycode == code


## Наведение на c: ×HOVER_SCALE и курсор-«рука». active — когда наведение имеет смысл
## (например, в слоте есть блок); выключенная кнопка не откликается.
static func add_hover(c: Control, active: Callable = Callable()) -> void:
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var on_input := func(event: InputEvent) -> void:
		_on_hover_input(c, event, active)
	var on_exit := func() -> void:
		set_hovered(c, false)
	c.gui_input.connect(on_input)
	c.mouse_exited.connect(on_exit)


## Наведение на все кнопки внутри root. skip — кнопки, чей масштаб ведёт анимация
## (дыхание «Играть» в меню): им только курсор.
static func add_hover_all(root: Node, skip: Array = []) -> void:
	for n in root.find_children("*", "BaseButton", true, false):
		var b := n as BaseButton
		if skip.has(b):
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		else:
			add_hover(b)


## Увеличить (on) или вернуть к 1. Повторный вызов с тем же состоянием ничего не делает,
## если масштаб уже на месте или его ведёт твин (наведение, пульс). Контейнер при пересборке
## сбрасывает масштаб детей в 1 (fit_child_in_rect) — следующее движение мыши вернёт ×1,05.
static func set_hovered(c: Control, on: bool) -> void:
	var rest := HOVER_SCALE if on else 1.0
	if is_equal_approx(float(c.get_meta(REST_META, 1.0)), rest) \
			and (c.scale.is_equal_approx(Vector2.ONE * rest) or _tweening(c)):
		return
	c.set_meta(REST_META, rest)
	if not c.is_inside_tree():
		c.scale = Vector2.ONE * rest
		return
	for key in [TWEEN_META, Fx.PULSE_META]:  # наведение перехватывает и пульс
		var prev = c.get_meta(key, null)
		if prev is Tween and (prev as Tween).is_valid():
			(prev as Tween).kill()
	c.pivot_offset = c.size * 0.5
	var t := c.create_tween()
	c.set_meta(TWEEN_META, t)
	t.tween_property(c, "scale", Vector2.ONE * rest, HOVER_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func _tweening(c: Control) -> bool:
	for key in [TWEEN_META, Fx.PULSE_META]:
		var t = c.get_meta(key, null)
		if t is Tween and (t as Tween).is_valid():
			return true
	return false


static func is_hovered(c: Control) -> bool:
	return float(c.get_meta(REST_META, 1.0)) > 1.0


static func _on_hover_input(c: Control, event: InputEvent, active: Callable) -> void:
	var m := event as InputEventMouseMotion
	if m == null:
		return
	var ok := _is_active(c, active)
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if ok else Control.CURSOR_ARROW
	# С зажатой кнопкой — это перетаскивание, а не наведение.
	set_hovered(c, ok and m.device != InputEvent.DEVICE_ID_EMULATION and m.button_mask == 0)


static func _is_active(c: Control, active: Callable) -> bool:
	if c is BaseButton and (c as BaseButton).disabled:
		return false
	return not active.is_valid() or bool(active.call())
