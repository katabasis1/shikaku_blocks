class_name HeartsOutPanel
extends Control
## Окно «Сердца закончились» (20.1b, PLAN 20.1). Открывает Game, когда сгорело последнее сердце попытки и ошибочный
## блок вернулся в лоток (Game._on_hearts_out). Вид — как у паузы (SettingsPanel): карточка CandyCard с фиолетовой
## шапкой, заголовок в шапке (CardTitle, ужимается под ширину — SettingsPanel.title_size), под ним пустые сердца
## (HeartsBar 0 из max), строка CardText и две таблетки:
##   «ПРОДОЛЖИТЬ» / «+1 сердце» — зелёная 400×110, в углу значок рекламы (как у подсказки, 4.5.1: видно, что это
##   реклама и что за неё дают). Без значка — бесплатное продолжение: рекламы нет вовсе (вне Яндекс Игр), а флаг
##   revive_free_on_fail его разрешает. Нет и бесплатного или возрождения исчерпаны (revive_max) — кнопки нет,
##   строка «Начни уровень заново».
##   «ЗАНОВО» — светлая 400×80.
## Окно только сообщает о нажатии (continue_pressed / restart_pressed) — рекламу, возрождение и «Заново» делает Game.
## Пока идёт реклама — set_busy(true): кнопки выключены. Esc окно глотает (пауза под ним не открывается) — решить
## нужно кнопкой. Анимация появления — та же, что у паузы (STYLE 12): фон темнеет, карточка ×0,9 → 1,03 → 1.

## «ПРОДОЛЖИТЬ +1 сердце» (за рекламу или бесплатно — решает Game).
signal continue_pressed
## «ЗАНОВО».
signal restart_pressed

## Сторона значка рекламы на кнопке, px (у подсказки 48 на кнопке 96).
const AD_BADGE := 56.0

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var card: CandyCard = %Card
@onready var title_label: Label = %Title
@onready var hearts_row: HeartsBar = %HeartsRow
@onready var text_label: Label = %Text
@onready var continue_button: PillButton = %ContinueButton
@onready var ad_badge: TextureRect = %ContinueAdBadge
@onready var restart_button: PillButton = %RestartButton

## Можно ли продолжить (кнопка «ПРОДОЛЖИТЬ» видна) и за рекламу ли — как при последнем open.
var can_continue: bool = false
var with_ad: bool = false


func _ready() -> void:
	hide()
	continue_button.pressed.connect(_on_continue_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	card.resized.connect(_on_card_resized)


## Показать окно. n_max — сердец на попытку (пустые сердца в карточке); can_go — можно продолжить; ad — за рекламу
## (значок на кнопке), иначе бесплатно.
func open(n_max: int, can_go: bool, ad: bool) -> void:
	can_continue = can_go
	with_ad = can_go and ad
	var n := maxi(n_max, 1)
	hearts_row.custom_minimum_size = Vector2(n * HeartsBar.HEART + (n - 1) * HeartsBar.GAP, HeartsBar.HEART)
	hearts_row.show_hearts(0, n)
	continue_button.visible = can_continue
	ad_badge.visible = with_ad
	set_busy(false)
	_update_texts()
	show()
	_on_card_resized()
	anim.play(&"show")


func close() -> void:
	hide()


## Идёт реклама: кнопки выключены, чтобы второе нажатие не запросило её снова.
func set_busy(on: bool) -> void:
	continue_button.disabled = on
	restart_button.disabled = on


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and visible:
		_update_texts()


func _update_texts() -> void:
	var title := tr("СЕРДЦА ЗАКОНЧИЛИСЬ")
	title_label.text = title
	title_label.add_theme_font_size_override(&"font_size",
			SettingsPanel.title_size(title_label.get_theme_font(&"font"), title))
	continue_button.subtitle = tr("+1 сердце")
	if not can_continue:
		text_label.text = tr("Начни уровень заново")
	elif with_ad:
		text_label.text = tr("Посмотри рекламу — и продолжай с того же места")
	else:
		text_label.text = tr("Продолжай с того же места")


func _on_card_resized() -> void:
	card.pivot_offset = card.size * 0.5


func _on_continue_pressed() -> void:
	if can_continue and not continue_button.disabled:
		continue_pressed.emit()


func _on_restart_pressed() -> void:
	if not restart_button.disabled:
		restart_pressed.emit()
