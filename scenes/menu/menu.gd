extends Control
## Главное меню (docs/STYLE.md, раздел 11.1). Колонна Content 720×1280 стоит по центру экрана:
## логотип — только графика, без надписи (07.10): живое решённое мини-поле из block.tscn (MenuLogo, menu_logo.gd)
## по центру колонны; «ИГРАТЬ» — зелёная PillButton со второй строкой «УРОВЕНЬ N»; под ней светлые таблетки
## «ЗАДАЧА ДНЯ» (до 12.10 — «ЕЖЕДНЕВНАЯ»; вторая строка — живая серия, 18.1) и «УРОВНИ» (карта уровней, 18.2).
## У краёв экрана: сверху по центру счёт со звездой (как в шапке игры, HudHeader.layout_score_row),
## в правом верхнем углу — шестерёнка
## (открывает scenes/ui/settings_panel.tscn), в левом — кубок (экран лидеров, 18.3). Названия игры и подписи
## внизу нет. В отладочной сборке (OS.is_debug_build: редактор, экспорт «с отладкой») под «УРОВНЯМИ» — ещё светлая
## таблетка «ЛАБОРАТОРИЯ» (экран механик-кандидатов 19.3, scenes/lab; создаётся в коде, у игроков её нет).

const GAME_SCENE := "res://scenes/game/game.tscn"
const MAP_SCENE := "res://scenes/map/level_map.tscn"
const LEADERS_SCENE := "res://scenes/leaders/leaders.tscn"
## Кнопка «Лаборатории» (только отладочная сборка): место в колонне под «УРОВНЯМИ», размер подписи.
const LAB_RECT := Rect2(200.0, 1154.0, 320.0, 84.0)
const LAB_FONT := 34
## Счёт в верхнем ряду — размер шрифта (у шапки игры 38: здесь он один в ряду).
const SCORE_SIZE := 44

@onready var content: Control = $Content
@onready var logo: MenuLogo = %Logo
@onready var score_row: Control = %ScoreRow
@onready var star: TextureRect = %StarIcon
@onready var score_label: Label = %ScoreLabel
@onready var play_button: PillButton = %PlayButton
@onready var daily_button: PillButton = %DailyButton
@onready var levels_button: PillButton = %LevelsButton
@onready var settings_button: CandyButton = %SettingsButton
@onready var leaders_button: CandyButton = %LeadersButton
@onready var settings_panel: SettingsPanel = %SettingsPanel
@onready var anim: AnimationPlayer = $AnimationPlayer

var star_shadow: TexShadow
## «ЛАБОРАТОРИЯ» (19.3b); null — сборка не отладочная.
var lab_button: PillButton = null


func _ready() -> void:
	star_shadow = TexShadow.attach(star, Vector2.ZERO, 0.0, HudHeader.STAR_SHADOW, HudHeader.STAR_SHADOW_ALPHA)
	play_button.pressed.connect(_on_play_pressed)
	daily_button.pressed.connect(_on_daily_pressed)
	levels_button.pressed.connect(_on_levels_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	leaders_button.pressed.connect(_on_leaders_pressed)
	if OS.is_debug_build():
		lab_button = make_lab_button()
	# Наведение и курсор-«рука»; масштаб «Играть» ведёт дыхание (анимация idle) — ей только курсор.
	Desktop.add_hover_all(self, [play_button])
	# Колонна одна в обеих раскладках, но режим помним: игра начнёт с него (гистерезис).
	resized.connect(_on_resized)
	_on_resized()
	score_row.resized.connect(_layout_score)
	# Облачное сохранение или сброс в настройках меняют прогресс, пока открыто меню.
	GameState.progress_changed.connect(_refresh)
	_refresh()
	anim.play(&"idle")
	# Меню на экране — игра загружена (Яндекс: LoadingAPI.ready; Метрика: game_ready один раз за запуск, 16.1).
	YSDK.loading_ready()
	Analytics.game_ready()


func _on_resized() -> void:
	GameLayout.last_landscape = GameLayout.pick(size, GameLayout.last_landscape)


## Enter — «Играть» (клавиша по месту, Desktop.key_pressed). Открытые настройки ловят ввод сами.
func _unhandled_input(event: InputEvent) -> void:
	if Desktop.key_pressed(event, KEY_ENTER) or Desktop.key_pressed(event, KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		_on_play_pressed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()


## Уровень на кнопке, счёт (разряды — по языку).
func _refresh() -> void:
	play_button.subtitle = tr("УРОВЕНЬ %d") % GameState.level
	daily_button.subtitle = daily_subtitle()
	score_label.text = HudHeader.format_score(GameState.total_score)
	_layout_score()


## Вторая строка «ЗАДАЧИ ДНЯ»: живая серия (пропущен день — 0), сегодняшняя пройдена — «· ГОТОВО».
func daily_subtitle() -> String:
	var streak := GameState.daily_current_streak()
	if GameState.daily_is_completed():
		return tr("СЕРИЯ %d · ГОТОВО") % streak
	return tr("СЕРИЯ %d") % streak


func _layout_score() -> void:
	HudHeader.layout_score_row(star, star_shadow, score_label, score_row.size.x, score_row.size.y * 0.5, SCORE_SIZE)


func _on_play_pressed() -> void:
	if settings_panel.visible or Transition.is_busy():
		return
	Audio.play(Audio.CLICK)
	Transition.change_scene(GAME_SCENE)


func _on_daily_pressed() -> void:
	if settings_panel.visible or Transition.is_busy():
		return
	Audio.play(Audio.CLICK)
	GameState.daily_requested = true
	Transition.change_scene(GAME_SCENE)


func _on_levels_pressed() -> void:
	if settings_panel.visible or Transition.is_busy():
		return
	Audio.play(Audio.CLICK)
	Transition.change_scene(MAP_SCENE)


func _on_leaders_pressed() -> void:
	if settings_panel.visible or Transition.is_busy():
		return
	Audio.play(Audio.CLICK)
	Transition.change_scene(LEADERS_SCENE)


## Таблетка «ЛАБОРАТОРИЯ» под «УРОВНЯМИ» (светлая, мельче; без перевода — экран только для разработки).
func make_lab_button() -> PillButton:
	var b := PillButton.new()
	b.name = "LabButton"
	b.tone = PillButton.Tone.LIGHT
	b.focus_mode = Control.FOCUS_NONE
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.text = LabLevels.NAME
	b.add_theme_font_size_override(&"font_size", LAB_FONT)
	content.add_child(b)
	b.position = LAB_RECT.position
	b.size = LAB_RECT.size
	b.pivot_offset = LAB_RECT.size * 0.5
	b.pressed.connect(_on_lab_pressed)
	return b


func _on_lab_pressed() -> void:
	if settings_panel.visible or Transition.is_busy():
		return
	Audio.play(Audio.CLICK)
	Transition.change_scene(LabLevels.SCENE)


func _on_settings_pressed() -> void:
	Audio.play(Audio.CLICK)
	settings_panel.open(SettingsPanel.Mode.SETTINGS)
