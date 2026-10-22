class_name LabScreen
extends Control
## Экран «Лаборатории» (этап 19.3b, docs/STYLE.md, раздел 11.5; кадр G19_3_lab.png): уровни механик-кандидатов,
## чтобы сыграть и выбрать, что пойдёт в главы (19.4). Только в отладочной сборке — кнопку в меню создаёт menu.gd
## при OS.is_debug_build(). Колонна Content 720×1280 по центру экрана, как в меню: сверху заголовок LabLevels.NAME,
## под ним по карточке на механику (порядок LabLevels.mechanics()): в фиолетовой шапке — название, ниже — правило
## (то же, что над полем в игре; переводится) и ряд уровней LabRow. Внизу — пояснение. «Домой» — в левом верхнем
## углу экрана, как на карте уровней и у лидеров. Касание уровня — игра (LabLevels.requested_mechanic / _index);
## «Далее» в игре ведёт по уровням подряд, после последнего — сюда. Отметки пройденных — LabLevels.done (до
## перезапуска). Клавиатура: Enter — первый непройденный уровень, Esc — меню. Названия и пояснение — без перевода.

const MENU_SCENE := "res://scenes/menu/menu.tscn"
const GAME_SCENE := "res://scenes/game/game.tscn"
## Карточка механики: высота шапки и размер названия в ней, поля лица слева / справа и снизу.
const HEAD_H := 64.0
const TITLE_SIZE := 34
const PAD_X := 24.0
const PAD_BOTTOM := 14.0
## Правило под шапкой: размер шрифта, место (две строки: 2 × 1,364 × 22 + 3 = 63).
const RULE_SIZE := 22
const RULE_H := 66.0
## Пояснение внизу экрана.
const NOTE := "Отладочная сборка: отметки до перезапуска\n«Далее» в игре — следующий уровень подряд"

@onready var content: Control = $Content
@onready var home_button: CandyButton = %HomeButton
@onready var title_label: Label = %TitleLabel
@onready var cards_box: VBoxContainer = %Cards
@onready var note_label: Label = %NoteLabel

## Ряды уровней: механика → LabRow.
var rows: Dictionary = {}


func _ready() -> void:
	title_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title_label.text = LabLevels.NAME
	note_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	note_label.text = NOTE
	for m in LabLevels.mechanics():
		cards_box.add_child(make_card(m))
	home_button.pressed.connect(go_home)
	Desktop.add_hover_all(self)


## Карточка механики m: шапка с названием, правило, ряд уровней.
func make_card(m: String) -> CandyCard:
	var card := CandyCard.new()
	card.name = "Card_" + m
	card.theme_type_variation = &"CandyCard"
	card.head_height = HEAD_H
	card.mouse_filter = MOUSE_FILTER_IGNORE
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = PAD_X
	pad.content_margin_right = PAD_X
	pad.content_margin_bottom = PAD_BOTTOM
	card.add_theme_stylebox_override(&"panel", pad)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 0)
	card.add_child(box)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"CardTitle"
	title.custom_minimum_size = Vector2(0.0, HEAD_H)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", TITLE_SIZE)
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.text = LabLevels.title(m).to_upper()
	box.add_child(title)
	var rule := Label.new()
	rule.name = "Rule"
	rule.theme_type_variation = &"CardText"
	rule.custom_minimum_size = Vector2(0.0, RULE_H)
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rule.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.add_theme_font_size_override(&"font_size", RULE_SIZE)
	rule.text = LabLevels.rule(m)  # msgid: Label переводит сам
	box.add_child(rule)
	var row := LabRow.new()
	row.name = "Row"
	row.setup(m)
	row.level_pressed.connect(_on_row_pressed.bind(m))
	box.add_child(row)
	rows[m] = row
	return card


## Ряд уровней механики m (null — нет такой).
func row_of(m: String) -> LabRow:
	return rows.get(m) as LabRow


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		go_home()
	elif Desktop.key_pressed(event, KEY_ENTER) or Desktop.key_pressed(event, KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		var f := LabLevels.first_open()
		if not f.is_empty():
			open_level(String(f.mechanic), int(f.index))


func _on_row_pressed(index: int, m: String) -> void:
	open_level(m, index)


## Сыграть уровень index механики m: запрос для Game и переход в игру.
func open_level(m: String, index: int) -> void:
	if Transition.is_busy() or index < 1 or index > LabLevels.count(m):
		return
	Audio.play(Audio.CLICK)
	LabLevels.requested_mechanic = m
	LabLevels.requested_index = index
	Transition.change_scene(GAME_SCENE)


func go_home() -> void:
	if Transition.is_busy():
		return
	Audio.play(Audio.CLICK)
	Transition.change_scene(MENU_SCENE)
