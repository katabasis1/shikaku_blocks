class_name FpsMeter
extends CanvasLayer
## Счётчик кадров для проверки на телефоне (14.7d). Скрыт; показывает и прячет его Quality.toggle_meter() —
## F3 или 5 быстрых касаний заголовка «Настройки» (SettingsPanel). В левом верхнем углу, поверх всего (слой
## LAYER — выше шторки Transition): «60 к/с · качество: высокое · частиц 34» — к/с движка за последнюю секунду,
## уровень Quality (с пометкой «вручную», когда автоснижение выключено) и частицы в воздухе (вспышки Juice и
## кусочки конфетти). Касание счётчика (или F4) — уровень вручную по кругу: Quality.cycle_level(). F5 —
## эффекты выключить / вернуть (Quality.toggle_effects, 14.8a): в конце текста — « · эффекты: выкл.».
## Текст — только по-русски (инструмент проверки, не для игроков), без перевода.
## Только в отладочной сборке (Quality.dev_tools, 12.10b): в сборке для игроков счётчика нет, F3 / F4 / F5 и
## касания заголовка «Настройки» игра не ловит.

const LAYER := 101
## Обновление текста, с.
const UPDATE := 0.25
const MARGIN := Vector2(6.0, 6.0)
const FONT_SIZE := 20
const BG := Color(0.0, 0.0, 0.0, 0.55)
const FG := Color(1.0, 1.0, 1.0)

var label: Label

var _t := 0.0


func _init() -> void:
	layer = LAYER
	visible = false
	label = Label.new()
	label.name = "Text"
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.position = MARGIN
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.add_theme_color_override(&"font_color", FG)
	label.add_theme_constant_override(&"outline_size", 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	label.add_theme_stylebox_override(&"normal", sb)
	add_child(label)
	label.gui_input.connect(_on_label_input)


## Показать или спрятать; при показе текст обновляется сразу.
func set_shown(on: bool) -> void:
	visible = on
	if on:
		refresh()


## Текст счётчика сейчас (selftest).
func meter_text() -> String:
	return label.text


func refresh() -> void:
	_t = 0.0
	var manual := "" if Quality.auto else " (вручную)"
	var off := " · эффекты: выкл." if Juice.shared_config().effects_off() else ""
	label.text = "%d к/с · качество: %s%s · частиц %d%s" % [roundi(Engine.get_frames_per_second()),
			Quality.level_name(), manual, live_particles(get_tree()), off]
	label.reset_size()


## Частицы в воздухе: вспышки всех узлов Juice и кусочки конфетти.
static func live_particles(tree: SceneTree) -> int:
	if tree == null:
		return 0
	var n := 0
	for j in tree.get_nodes_in_group(Juice.GROUP):
		if j is Juice:
			n += (j as Juice).live_particles()
	for c in tree.get_nodes_in_group(Confetti.GROUP):
		if c is Confetti:
			n += (c as Confetti).parts.size()
	return n


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= UPDATE:
		refresh()


func _on_label_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	label.accept_event()
	Quality.cycle_level()
	refresh()
