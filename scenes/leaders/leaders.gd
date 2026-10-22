class_name LeadersScreen
extends Control
## Экран лидеров (этап 18.3, docs/STYLE.md, раздел 11.3; кадр G18_3_leaders.png). Колонна Content 720×1280
## по центру экрана, как в меню: сверху вкладки «ОЧКИ» / «СЕРИЯ» (таблицы YSDK.LEADERBOARD_NAME и
## DAILY_LEADERBOARD_NAME; выбранная — зелёная), под ними карточка «ЛИДЕРЫ» со строками LeaderRows, ниже —
## строка состояния и «ВОЙТИ» у гостя. «Домой» — в левом верхнем углу экрана, как на карте уровней.
## Данные — YSDK.request_leaderboard (кэш 60 с) → LeaderboardData.rows. Вне Яндекс Игр и без сети в карточке
## одна своя строка с местным счётом (место «—») и пояснение. Esc — меню, ←/→ — вкладки.

const MENU_SCENE := "res://scenes/menu/menu.tscn"
enum Tab { SCORE, STREAK }
const LOADING := "Загрузка…"  # msgid
const EMPTY := "Пока пусто — будьте первым!"  # msgid

@onready var content: Control = $Content
@onready var home_button: CandyButton = %HomeButton
@onready var score_tab: PillButton = %ScoreTab
@onready var streak_tab: PillButton = %StreakTab
@onready var rows_view: LeaderRows = %Rows
@onready var status_label: Label = %StatusLabel
@onready var login_button: PillButton = %LoginButton

var tab: Tab = Tab.SCORE
## Последний ответ таблицы текущей вкладки ({} — ждём).
var data: Dictionary = {}
## Строки, которые сейчас показаны.
var shown: Array[Dictionary] = []


func _ready() -> void:
	home_button.pressed.connect(go_home)
	score_tab.pressed.connect(select_tab.bind(Tab.SCORE))
	streak_tab.pressed.connect(select_tab.bind(Tab.STREAK))
	login_button.pressed.connect(_on_login_pressed)
	YSDK.leaderboard_loaded.connect(_on_leaderboard_loaded)
	YSDK.auth_changed.connect(_on_auth_changed)
	YSDK.leaderboard_changed.connect(_on_leaderboard_changed)
	YSDK.initialized.connect(reload)
	YSDK.init_failed.connect(reload)
	Desktop.add_hover_all(self)
	select_tab(Tab.SCORE, false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		go_home()
	elif Desktop.key_pressed(event, KEY_LEFT) or Desktop.key_pressed(event, KEY_RIGHT):
		get_viewport().set_input_as_handled()
		select_tab(Tab.STREAK if tab == Tab.SCORE else Tab.SCORE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_status()


## Имя таблицы вкладки.
static func board_name(t: Tab) -> String:
	return YSDK.DAILY_LEADERBOARD_NAME if t == Tab.STREAK else YSDK.LEADERBOARD_NAME


## Переключить вкладку (выбранная — зелёная) и прочитать её таблицу.
func select_tab(t: Tab, sound: bool = true) -> void:
	if sound and t != tab:
		Audio.play(Audio.CLICK)
	tab = t
	score_tab.tone = PillButton.Tone.GREEN if t == Tab.SCORE else PillButton.Tone.LIGHT
	streak_tab.tone = PillButton.Tone.GREEN if t == Tab.STREAK else PillButton.Tone.LIGHT
	reload()


## Прочитать таблицу текущей вкладки заново (из кэша YSDK, если ответ свежий). Пока SDK грузится или вход ещё
## неизвестен — «Загрузка…» и ждём сигнала.
func reload() -> void:
	data = {}
	shown = []
	rows_view.set_message(LOADING)
	_update_status()
	if YSDK.sdk_pending or (YSDK.is_available and not YSDK.auth_known):
		return
	YSDK.request_leaderboard(board_name(tab))


## Местный результат текущей вкладки (своя строка вне Яндекса).
func local_score() -> int:
	return GameState.daily_current_streak() if tab == Tab.STREAK else GameState.total_score


func go_home() -> void:
	if Transition.is_busy():
		return
	Audio.play(Audio.CLICK)
	Transition.change_scene(MENU_SCENE)


func _on_leaderboard_loaded(board: String, answer: Dictionary) -> void:
	if board != board_name(tab):
		return
	data = answer
	if answer.has("error"):
		shown = [LeaderboardData.local_row(local_score())]
	else:
		shown = LeaderboardData.rows(answer, YSDK.player_id)
	if shown.is_empty():
		rows_view.set_message(EMPTY)
	else:
		rows_view.set_rows(shown)
	_update_status()


func _on_auth_changed(_authorized: bool) -> void:
	reload()


## Яндекс принял новый результат (после входа — очки и серия): прочитать таблицу вкладки ещё раз, не стирая строк.
func _on_leaderboard_changed(board: String) -> void:
	if board == board_name(tab) and not data.is_empty():
		YSDK.request_leaderboard(board)


func _on_login_pressed() -> void:
	Audio.play(Audio.CLICK)
	YSDK.open_auth()


func _update_status() -> void:
	var text := ""
	if not data.is_empty():
		text = LeaderboardData.status_text(data, YSDK.is_authorized, shown, tab == Tab.STREAK)
	status_label.text = tr(text) if not text.is_empty() else ""
	login_button.visible = YSDK.is_available and YSDK.auth_known and not YSDK.is_authorized
