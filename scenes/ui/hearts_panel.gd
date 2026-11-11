class_name HeartsPanel
extends Control
## Окно «Сердца закончились» (20.1b, PLAN 20.1): карточка как у паузы (SettingsPanel — CandyCard с фиолетовой
## шапкой шириной SettingsPanel.CARD_W, заголовок ужимается под ширину — SettingsPanel.title_size; появление —
## AnimationPlayer «show»: фон темнеет, карточка ×0,9 → 1,03 → 1). Под шапкой — пустые сердца попытки (HeartsBar),
## пояснение и кнопки:
##   «ПРОДОЛЖИТЬ / +1 СЕРДЦЕ» — зелёная таблетка 400×110; за рекламу — со значком рекламы в правом верхнем углу
##     (ad.png, как у подсказки за рекламу: MODERATION 4.5.1 — кнопка говорит, что это реклама и что за неё дают);
##   «ЗАНОВО» — светлая 400×80, а когда продолжить нельзя — главная (зелёная 400×110);
##   «⌂ В меню» — ссылка CardLink, как в паузе (без неё из окна не уйти: пауза под ним не нажимается).
## Окно ничего не решает само: что предложить — offer_for (Game.hearts_offer по Hearts и YSDK), что делать после
## рекламы — after_ad. Правила — модель tools/hearts_model.py (строки W и D эталона tests/hearts_expected.txt).
## Пока идёт реклама (set_busy) кнопки выключены. Esc окно не закрывает: поле без сердец стоит, выбор — кнопками.
## Звук клика у «Продолжить» и «В меню» играет окно, у «Заново» — Game (как у кнопки «Заново» в игре).

signal continue_pressed
signal restart_pressed
signal home_pressed

## Что предложить: AD — продолжить за рекламу; FREE — рекламы нет, бесплатное продолжение ещё можно (флаг
## revive_free_on_fail, раз за попытку); NO_AD — рекламы нет и бесплатного нет; LIMIT — возрождения исчерпаны
## (флаг revive_max) — только «Заново».
enum Offer { AD, FREE, NO_AD, LIMIT }
## Что делать, когда реклама за сердце закончилась: REVIVE — награда пришла, возродить; NOTE_CLOSED — закрыл
## рекламу раньше награды: окно остаётся, пояснение NOTE_CLOSED; FREE — реклама не показалась (нет, ошибка, не
## открылась за YSDK.AD_OPEN_TIMEOUT_MS), бесплатное ещё можно — возродить бесплатно; NOTE_FAILED — не показалась,
## а бесплатное уже брали: окно остаётся, пояснение NOTE_FAILED (можно попробовать ещё раз).
enum After { REVIVE, NOTE_CLOSED, FREE, NOTE_FAILED }

## Пояснения после рекламы (переводятся при показе).
const NOTE_CLOSED := "Сердце дают, если досмотреть рекламу до конца"  # msgid
const NOTE_FAILED := "Реклама не загрузилась. Попробуй ещё раз или начни заново"  # msgid
## «Заново»: второстепенная (есть «Продолжить») и главная (нет) — размер; шрифт второстепенной.
const RESTART_MINOR := Vector2(400.0, 80.0)
const RESTART_MAIN := Vector2(400.0, 110.0)
const MINOR_FONT := 30
## Тень значка рекламы — как у значков CandyButton (форма видимой части ad.png — как у значка подсказки в game.tscn).
const BADGE_SHAPE := Vector2(0.9375, 0.8984)
const BADGE_ROUND := 0.6

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var card: CandyCard = %Card
@onready var title_label: Label = %Title
@onready var hearts_row: HeartsBar = %HeartsRow
@onready var text_label: Label = %Text
@onready var continue_button: PillButton = %ContinueButton
@onready var ad_badge: TextureRect = %ContinueAdBadge
@onready var restart_button: PillButton = %RestartButton
@onready var home_button: Button = %HomeButton

var offer: int = Offer.AD
## Ждём рекламу: кнопки выключены.
var busy := false
## Пояснение вместо обычного (msgid; "" — обычное по предложению).
var note := ""


func _ready() -> void:
	hide()
	continue_button.pressed.connect(_on_continue_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	home_button.pressed.connect(_on_home_pressed)
	card.resized.connect(_on_card_resized)
	ad_badge.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	SoftShadow.attach(ad_badge, BADGE_SHAPE, BADGE_ROUND, Vector2(0.0, CandyButton.BADGE_SHADOW_OFFSET),
			CandyButton.BADGE_SHADOW_BLUR, CandyButton.BADGE_SHADOW_STRENGTH)


## Что предложить: возродиться нельзя (возрождения исчерпаны) — LIMIT; реклама есть — AD; нет — FREE, если
## бесплатное продолжение ещё можно взять, иначе NO_AD. Модель — offer_for в tools/hearts_model.py.
static func offer_for(can_revive: bool, ad_available: bool, can_free: bool) -> int:
	if not can_revive:
		return Offer.LIMIT
	if ad_available:
		return Offer.AD
	return Offer.FREE if can_free else Offer.NO_AD


## Реклама за сердце закончилась: rewarded — награда пришла, result — YSDK.last_ad_result ("rewarded", "closed",
## "not_shown", "timeout"), can_free — бесплатное продолжение ещё можно (Hearts.can_continue_free). Модель — after_ad
## в tools/hearts_model.py.
static func after_ad(rewarded: bool, result: String, can_free: bool) -> int:
	if rewarded:
		return After.REVIVE
	if result == "closed":
		return After.NOTE_CLOSED
	return After.FREE if can_free else After.NOTE_FAILED


## Пояснение под сердцами для предложения o (msgid; переводится при показе).
static func offer_text(o: int) -> String:
	match o:
		Offer.AD:
			return "Посмотри рекламу и продолжи с того же места"  # msgid
		Offer.FREE:
			return "Держи ещё одно сердце и продолжай с того же места"  # msgid
		Offer.NO_AD:
			return "Реклама сейчас недоступна. Начни заново — с полными сердцами"  # msgid
	return "Продолжений на этом уровне больше нет. Начни заново — с полными сердцами"  # msgid


## Показать окно: предложение as_offer, сердец на попытку n_hearts (все пустые).
func open(as_offer: int, n_hearts: int) -> void:
	busy = false
	note = ""
	hearts_row.custom_minimum_size = HeartsBar.row_size(n_hearts)
	hearts_row.show_hearts(0, n_hearts)
	hearts_row.visible = n_hearts > 0
	set_offer(as_offer)
	show()
	_on_card_resized()
	anim.play(&"show")


func close() -> void:
	busy = false
	hide()


## Сменить предложение в открытом окне (реклама не показалась, бесплатное взяли).
func set_offer(as_offer: int) -> void:
	offer = as_offer
	_sync()


## Пояснение вместо обычного: msgid (NOTE_CLOSED, NOTE_FAILED) или "" — обычное по предложению.
func set_note(msgid: String) -> void:
	note = msgid
	_sync()


## Ждём рекламу (on) — кнопки выключены.
func set_busy(on: bool) -> void:
	busy = on
	_sync()


## Можно продолжить: кнопка «Продолжить» есть.
func can_continue() -> bool:
	return offer == Offer.AD or offer == Offer.FREE


func _sync() -> void:
	var cont := can_continue()
	continue_button.visible = cont
	ad_badge.visible = offer == Offer.AD
	restart_button.tone = PillButton.Tone.LIGHT if cont else PillButton.Tone.GREEN
	restart_button.custom_minimum_size = RESTART_MINOR if cont else RESTART_MAIN
	if cont:
		restart_button.add_theme_font_size_override(&"font_size", MINOR_FONT)
	else:
		restart_button.remove_theme_font_size_override(&"font_size")
	continue_button.disabled = busy
	restart_button.disabled = busy
	home_button.disabled = busy
	_update_texts()


func _update_texts() -> void:
	var title := tr("СЕРДЦА ЗАКОНЧИЛИСЬ")
	title_label.text = title
	title_label.add_theme_font_size_override(&"font_size",
			SettingsPanel.title_size(title_label.get_theme_font(&"font"), title))
	continue_button.subtitle = tr("+1 СЕРДЦЕ")
	text_label.text = tr(note if not note.is_empty() else offer_text(offer))


func _unhandled_input(event: InputEvent) -> void:
	# Esc окно не закрывает (выбор — кнопками), но и до игры не доходит: пауза под окном не открывается.
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Язык сменился, пока окно открыто, — перерисовать тексты, заданные из кода.
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and visible:
		_update_texts()


func _on_continue_pressed() -> void:
	if busy:
		return
	Audio.play(Audio.CLICK)
	continue_pressed.emit()


func _on_restart_pressed() -> void:
	if busy:
		return
	restart_pressed.emit()


func _on_home_pressed() -> void:
	if busy:
		return
	Audio.play(Audio.CLICK)
	home_pressed.emit()


func _on_card_resized() -> void:
	card.pivot_offset = card.size * 0.5
