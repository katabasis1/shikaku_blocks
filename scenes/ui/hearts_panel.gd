class_name HeartsPanel
extends Control
## Окно «Сердца закончились» (20.1b, PLAN 20.1). Вид — как у паузы (SettingsPanel, docs/STYLE.md, раздел 11):
## карточка CandyCard с фиолетовой шапкой, заголовок в шапке ужимается под ширину (SettingsPanel.title_size), текст,
## зелёная таблетка «ПРОДОЛЖИТЬ» со второй строкой «+1 СЕРДЦЕ», светлая «ЗАНОВО» и ссылка «⌂ В меню». Появление —
## анимация show сцены (фон темнеет, карточка ×0,9 → 1,03 → 1).
## Что предлагает (open, Offer — решает Game.revive_offer):
##   AD   — продолжить за рекламу: на «ПРОДОЛЖИТЬ» значок рекламы (правила Яндекса 4.5.1: до показа видно, что это
##          реклама и что за неё дают);
##   FREE — бесплатно (рекламы нет или не показалась, бесплатное продолжение уровня ещё не взято): без значка;
##   NONE — продолжить нельзя (возрождения уровня исчерпаны, флаг revive_max): «ПРОДОЛЖИТЬ» нет, «ЗАНОВО» — главная
##          (зелёная, 400×110).
## note — строка под текстом: почему продолжения не было (рекламу закрыли до награды, реклама не загрузилась).
## set_waiting(true) — ждём рекламу: кнопки выключены. Логика (сердце, реклама, Метрика) — в Game: окно только
## показывает и сообщает о нажатиях. Esc окно гасит, а не закрывает: выбор нужен (ходить без сердец нельзя).

signal revive_pressed
signal restart_pressed
signal home_pressed

enum Offer { NONE, AD, FREE }

const RESTART_MAIN := Vector2(400, 110)
const RESTART_SECOND := Vector2(400, 80)
const RESTART_SECOND_FONT := 30

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var card: CandyCard = %Card
@onready var title_label: Label = %Title
@onready var text_label: Label = %Text
@onready var note_label: Label = %Note
@onready var revive_button: PillButton = %ReviveButton
@onready var ad_badge: TextureRect = %ReviveAdBadge
@onready var restart_button: PillButton = %RestartButton
@onready var home_button: Button = %HomeButton

var offer: int = Offer.NONE
var waiting: bool = false


func _ready() -> void:
	hide()
	revive_button.pressed.connect(_on_revive_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	home_button.pressed.connect(_on_home_pressed)
	card.resized.connect(_on_card_resized)
	# Значок рекламы — как на кнопках-конфетах (CandyButton): своя мягкая тень вниз.
	SoftShadow.attach(ad_badge, ad_badge.get_meta(&"badge_shape", Vector2.ONE), float(ad_badge.get_meta(&"badge_round", 1.0)),
			Vector2(0.0, CandyButton.BADGE_SHADOW_OFFSET), CandyButton.BADGE_SHADOW_BLUR, CandyButton.BADGE_SHADOW_STRENGTH)


## Показывает окно (или обновляет открытое): what — Offer, note — строка под текстом ("" — нет).
func open(what: int, note: String = "") -> void:
	var was := visible
	offer = what
	waiting = false
	note_label.text = note
	note_label.visible = not note.is_empty()
	_update_texts()
	_apply_offer()
	_sync_disabled()
	show()
	_on_card_resized()
	if not was:
		anim.play(&"show")


func close() -> void:
	waiting = false
	hide()


## Ждём ответа рекламы: кнопки выключены.
func set_waiting(on: bool) -> void:
	waiting = on
	_sync_disabled()


func _apply_offer() -> void:
	revive_button.visible = offer != Offer.NONE
	ad_badge.visible = offer == Offer.AD
	var main := offer == Offer.NONE
	restart_button.tone = PillButton.Tone.GREEN if main else PillButton.Tone.LIGHT
	restart_button.custom_minimum_size = RESTART_MAIN if main else RESTART_SECOND
	if main:
		restart_button.remove_theme_font_size_override(&"font_size")  # размер темы PillButton
	else:
		restart_button.add_theme_font_size_override(&"font_size", RESTART_SECOND_FONT)
	_update_restart_text()


## «ЗАНОВО» — главная кнопка (продолжить нельзя), «Начать заново» — вторая, под «ПРОДОЛЖИТЬ».
func _update_restart_text() -> void:
	restart_button.text = tr("ЗАНОВО") if offer == Offer.NONE else tr("Начать заново")


func _sync_disabled() -> void:
	revive_button.disabled = waiting
	restart_button.disabled = waiting
	home_button.disabled = waiting


func _update_texts() -> void:
	var title := tr("СЕРДЦА ЗАКОНЧИЛИСЬ")
	title_label.text = title
	title_label.add_theme_font_size_override(&"font_size",
			SettingsPanel.title_size(title_label.get_theme_font(&"font"), title))
	text_label.text = tr("Продолжи с этого места или начни уровень заново") if offer != Offer.NONE \
			else tr("Начни уровень заново — ты уже знаешь, где ловушка")
	revive_button.subtitle = tr("+1 СЕРДЦЕ")
	_update_restart_text()


func _notification(what: int) -> void:
	# Язык сменился, пока окно открыто, — тексты из кода заново (note — уже переведённая строка от Game).
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and visible:
		_update_texts()


func _unhandled_input(event: InputEvent) -> void:
	# Esc не закрывает окно (без сердец ходить нельзя) и не открывает паузу под ним.
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()


func _on_card_resized() -> void:
	card.pivot_offset = card.size * 0.5


func _on_revive_pressed() -> void:
	if waiting:
		return
	Audio.play(Audio.CLICK)
	revive_pressed.emit()


func _on_restart_pressed() -> void:
	if waiting:
		return
	restart_pressed.emit()  # звук клика — у Game._on_restart_pressed


func _on_home_pressed() -> void:
	if waiting:
		return
	Audio.play(Audio.CLICK)
	home_pressed.emit()
