class_name SettingsPanel
extends Control
## Окно настроек (меню) и паузы (игра). Переключатели: музыка, звуки, вибрация
## (вибрация — только там, где она есть, см. GameState.can_vibrate()); под ними — светлая таблетка
## «Меньше движения: выкл / вкл» (этап 14, GameState.reduce_motion: без тряски, частиц вдвое меньше).
## В меню — ещё сброс прогресса с подтверждением, в паузе — «Продолжить» и «В меню».
## Вид (13.5c, docs/STYLE.md, раздел 11): карточка CandyCard с фиолетовой шапкой, заголовок в шапке
## (CardTitle, ужимается под ширину), главная кнопка — зелёная таблетка PillButton 400×110 («ГОТОВО» /
## «ПРОДОЛЖИТЬ»), под ней второстепенное: светлая таблетка «Сбросить прогресс» (настройки) или ссылка
## «⌂ В меню» (CardLink с иконкой, как «Переиграть уровень» у победы; иконка без expand_icon — кнопка
## шириной по содержимому, иконка вплотную к тексту). Подтверждение сброса — в той же
## карточке: заголовок «СБРОСИТЬ ПРОГРЕСС?», текст, красная «СБРОСИТЬ» и светлая «ОТМЕНА».
## Высота карточки — по содержимому (Card растёт от середины экрана), ширина CARD_W.
## Анимация появления — в AnimationPlayer сцены: фон темнеет, карточка ×0,9 → 1,03 → 1 (STYLE 12).
## Таблетки разработчика (12.10): «Меньше движения» и «Сбросить прогресс» видны только в отладочной сборке
## (dev_tools = OS.is_debug_build(): редактор, экспорт «с отладкой») — как «ЛАБОРАТОРИЯ» в меню. В сборке для
## игроков их нет: в настройках — переключатели и «ГОТОВО», в паузе — переключатели, «ПРОДОЛЖИТЬ» и «В меню».
## Сохранённое «Меньше движения: вкл» сборка для игроков не читает (GameState.load_settings).
## Скрытое (14.7d): METER_TAPS быстрых касаний заголовка подряд (между касаниями не больше METER_TAP_GAP, с) —
## показать / спрятать счётчик кадров (Quality.toggle_meter; 12.10b — только в отладочной сборке, Quality.dev_tools).
## «Оценить игру» (12.10b): золотая таблетка PillButton (Tone.GOLD) с дугой из пяти звёзд над верхним краем — под
## переключателями, только в настройках (меню; в паузе нет), после обучения (GameState.tutorial_done) и пока можно
## просить оценку (YSDK.can_offer_review): вошедшему — пока Яндекс разрешает (игру не оценивал, окно оценки ему не
## показывали), гостю — тоже видна. Нажатие — окно оценки Яндекса (YSDK.request_review_by_player), гостю — сначала окно
## входа, после входа сразу окно оценки (отказался от входа — таблетка возвращается). Таблетка сразу прячется: второй
## раз за сессию Яндекс окно не покажет. Ответ canReview и вход приходят после старта — пока окно открыто, видимость
## следует за YSDK.review_availability_changed. Сама игра просит оценку после победы на уровнях 11–15 (YSDK).

## Окно закрыто: «Готово» / «Продолжить» / Esc.
signal closed
## «В меню» (только в режиме паузы). closed при этом не приходит.
signal home_pressed
## Прогресс сброшен (только в режиме настроек).
signal progress_wiped

enum Mode { SETTINGS, PAUSE }

const MUSIC_ON: Texture2D = preload("res://assets/icons/music_on.png")
const MUSIC_OFF: Texture2D = preload("res://assets/icons/music_off.png")
const SFX_ON: Texture2D = preload("res://assets/icons/sound_on.png")
const SFX_OFF: Texture2D = preload("res://assets/icons/sound_off.png")
const VIBRATION_ON: Texture2D = preload("res://assets/icons/vibration_on.png")
const VIBRATION_OFF: Texture2D = preload("res://assets/icons/vibration_off.png")
## Короткий толчок при включении вибрации — чтобы игрок сразу почувствовал.
const VIBRATION_PREVIEW_MS := 40
## Ширина карточки; заголовок в шапке — от TITLE_SIZE (тип темы CardTitle) до TITLE_MIN_SIZE.
const CARD_W := 560.0
const TITLE_SIZE := 42
const TITLE_MIN_SIZE := 30
## Поля карточки слева и справа (тип темы CandyCard) и полная толщина обводки CardTitle.
const CARD_PAD := 40.0
const TITLE_OUTLINE := 10.0
## Счётчик кадров (14.7d): касаний заголовка подряд и наибольший промежуток между ними, с.
const METER_TAPS := 5
const METER_TAP_GAP := 0.5

## Показывать таблетки разработчика («Меньше движения», «Сбросить прогресс»). По умолчанию — только в отладочной
## сборке; selftest подменяет, чтобы проверить вид окна у игроков.
static var dev_tools: bool = OS.is_debug_build()

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var card: CandyCard = %Card
@onready var main_box: Control = %MainBox
@onready var confirm_box: Control = %ConfirmBox
@onready var title_label: Label = %Title
@onready var music_button: CandyButton = %MusicButton
@onready var sfx_button: CandyButton = %SfxButton
@onready var vibration_button: CandyButton = %VibrationButton
@onready var vibration_toggle: Control = %VibrationToggle
@onready var motion_button: PillButton = %MotionButton
@onready var rate_box: Control = %RateBox
@onready var rate_button: PillButton = %RateButton
@onready var home_button: Button = %HomeButton
@onready var close_button: PillButton = %CloseButton
@onready var reset_button: PillButton = %ResetButton
@onready var cancel_reset_button: PillButton = %CancelResetButton
@onready var confirm_reset_button: PillButton = %ConfirmResetButton

var mode: int = Mode.SETTINGS

var _taps := 0
var _tap_at := -100000


func _ready() -> void:
	hide()
	music_button.pressed.connect(_on_music_pressed)
	sfx_button.pressed.connect(_on_sfx_pressed)
	vibration_button.pressed.connect(_on_vibration_pressed)
	motion_button.pressed.connect(_on_motion_pressed)
	rate_button.pressed.connect(_on_rate_pressed)
	home_button.pressed.connect(_on_home_pressed)
	close_button.pressed.connect(_on_close_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	cancel_reset_button.pressed.connect(_on_cancel_reset_pressed)
	confirm_reset_button.pressed.connect(_on_confirm_reset_pressed)
	GameState.settings_changed.connect(_refresh)
	YSDK.review_availability_changed.connect(_update_rate)
	card.resized.connect(_on_card_resized)
	title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	title_label.gui_input.connect(_on_title_input)


## Показывает окно в режиме Mode.SETTINGS или Mode.PAUSE.
func open(as_mode: int) -> void:
	mode = as_mode
	var pause := mode == Mode.PAUSE
	home_button.visible = pause
	reset_button.visible = dev_tools and not pause
	motion_button.visible = dev_tools
	vibration_toggle.visible = GameState.can_vibrate()
	_update_rate()
	_show_confirm(false)
	_refresh()
	show()
	_on_card_resized()
	anim.play(&"show")


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	# Esc (ui_cancel): из подтверждения — назад, иначе закрыть окно.
	if not is_visible_in_tree() or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if confirm_box.visible:
		_on_cancel_reset_pressed()
	else:
		_on_close_pressed()


func _notification(what: int) -> void:
	# Язык сменился, пока окно открыто, — перерисовать тексты, заданные из кода.
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and visible:
		_update_texts()
		_refresh()


## Заголовок в шапке и надпись главной кнопки — по режиму и виду (основной / подтверждение сброса).
func _update_texts() -> void:
	var pause := mode == Mode.PAUSE
	close_button.text = tr("ПРОДОЛЖИТЬ") if pause else tr("ГОТОВО")
	var title := tr("НАСТРОЙКИ")
	if confirm_box.visible:
		title = tr("СБРОСИТЬ ПРОГРЕСС?")
	elif pause:
		title = tr("ПАУЗА")
	title_label.text = title
	title_label.add_theme_font_size_override(&"font_size", title_size(title_label.get_theme_font(&"font"), title))


## Размер заголовка в шапке: TITLE_SIZE, а не влезает в карточку (без полей и обводки) — меньше,
## шагом 2, но не меньше TITLE_MIN_SIZE.
static func title_size(font: Font, text: String) -> int:
	var room := CARD_W - 2.0 * CARD_PAD
	var fs := TITLE_SIZE
	while fs > TITLE_MIN_SIZE and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + TITLE_OUTLINE > room:
		fs -= 2
	return fs


func _on_card_resized() -> void:
	card.pivot_offset = card.size * 0.5


func _refresh() -> void:
	_set_toggle(music_button, GameState.music_on, MUSIC_ON, MUSIC_OFF)
	_set_toggle(sfx_button, GameState.sfx_on, SFX_ON, SFX_OFF)
	_set_toggle(vibration_button, GameState.vibration_on, VIBRATION_ON, VIBRATION_OFF)
	motion_button.text = tr("Меньше движения: вкл") if GameState.reduce_motion else tr("Меньше движения: выкл")


## Кнопки — CandyButton (13.4): картинка — лицо кнопки, «выключено» нарисовано на самой PNG (*_off.png).
static func _set_toggle(button: CandyButton, on: bool, icon_on: Texture2D, icon_off: Texture2D) -> void:
	button.set_face(icon_on if on else icon_off)


func _show_confirm(on: bool) -> void:
	main_box.visible = not on
	confirm_box.visible = on
	_update_texts()


func _on_music_pressed() -> void:
	GameState.set_music(not GameState.music_on)
	Audio.play(Audio.CLICK)


func _on_sfx_pressed() -> void:
	GameState.set_sfx(not GameState.sfx_on)
	Audio.play(Audio.CLICK)  # при включении — сразу слышно, что звук вернулся


func _on_vibration_pressed() -> void:
	GameState.set_vibration(not GameState.vibration_on)
	Audio.play(Audio.CLICK)
	if GameState.vibration_on:
		Audio.vibrate(VIBRATION_PREVIEW_MS)


func _on_motion_pressed() -> void:
	GameState.set_reduce_motion(not GameState.reduce_motion)
	Audio.play(Audio.CLICK)


## «Оценить игру» видна: режим настроек (не пауза), обучение пройдено, оценку можно просить (YSDK.can_offer_review).
static func rate_shown(as_mode: int, tutorial_done: bool, can_review: bool) -> bool:
	return as_mode == Mode.SETTINGS and tutorial_done and can_review


func _update_rate() -> void:
	rate_box.visible = rate_shown(mode, GameState.tutorial_done(), YSDK.can_offer_review())


func _on_rate_pressed() -> void:
	Audio.play(Audio.CLICK)
	YSDK.request_review_by_player()
	_update_rate()


func _on_close_pressed() -> void:
	Audio.play(Audio.CLICK)
	close()


func _on_home_pressed() -> void:
	Audio.play(Audio.CLICK)
	hide()
	home_pressed.emit()


func _on_reset_pressed() -> void:
	Audio.play(Audio.CLICK)
	_show_confirm(true)


func _on_cancel_reset_pressed() -> void:
	Audio.play(Audio.CLICK)
	_show_confirm(false)


func _on_confirm_reset_pressed() -> void:
	GameState.wipe_progress()
	Audio.play(Audio.UNDO)
	_show_confirm(false)
	progress_wiped.emit()
	close()


## Касание заголовка: METER_TAPS подряд (промежутки не больше METER_TAP_GAP) — счётчик кадров (14.7d).
func _on_title_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if count_tap(Time.get_ticks_msec()):
		Quality.toggle_meter()


## Учесть касание заголовка в момент now_ms; true — набралось METER_TAPS подряд (счёт начинается заново).
func count_tap(now_ms: int) -> bool:
	_taps = _taps + 1 if now_ms - _tap_at <= int(METER_TAP_GAP * 1000.0) else 1
	_tap_at = now_ms
	if _taps >= METER_TAPS:
		_taps = 0
		return true
	return false
