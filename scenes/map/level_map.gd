class_name LevelMap
extends Control
## Карта уровней (этап 18.2, docs/STYLE.md, раздел 11.2): фон игры, дорожка MapPath в ScrollContainer (тянется
## пальцем, колесом и мышью), сверху — затемнение-«потолок», по центру счёт со звездой (как в меню), в левом
## верхнем углу — «домой» (светлая CandyButton Ø 96, место паузы в игре). При входе текущий уровень стоит на
## FOCUS_AT высоты экрана. Касание открытого уровня — игра с этого уровня (GameState.requested_level:
## пройденные — переигровка, текущий — как «ИГРАТЬ»); закрытого — звук «мимо», кружок вздрагивает.
## Клавиатура: Enter — текущий уровень, Esc — меню.
## Главы (19.5c): фон — тема главы посреди экрана (update_theme), плашки глав рисует MapPath.

const MENU_SCENE := "res://scenes/menu/menu.tscn"
const GAME_SCENE := "res://scenes/game/game.tscn"
## Счёт в верхнем ряду — как в меню (STYLE 11.1).
const SCORE_SIZE := 44
## Текущий уровень при входе — на этой доле высоты окна (ниже середины: впереди видно больше).
const FOCUS_AT := 0.6

@onready var scroll: ScrollContainer = %Scroll
@onready var path: MapPath = %Path
@onready var score_row: Control = %ScoreRow
@onready var star: TextureRect = %StarIcon
@onready var score_label: Label = %ScoreLabel
@onready var home_button: CandyButton = %HomeButton
@onready var background: Background = $Background

var star_shadow: TexShadow


func _ready() -> void:
	star_shadow = TexShadow.attach(star, Vector2.ZERO, 0.0, HudHeader.STAR_SHADOW, HudHeader.STAR_SHADOW_ALPHA)
	path.setup(GameState.level, GameState.level_stars)
	path.level_pressed.connect(open_level)
	path.level_locked.connect(_on_locked)
	home_button.pressed.connect(go_home)
	score_row.resized.connect(_layout_score)
	resized.connect(_on_resized)
	Desktop.add_hover_all(self)
	_refresh()
	_on_resized()
	# Прокрутка — после того как ScrollContainer разложит карту (иначе предел прокрутки ещё 0).
	await get_tree().process_frame
	focus_current()
	update_theme(false)
	scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)


func _on_resized() -> void:
	GameLayout.last_landscape = GameLayout.pick(size, GameLayout.last_landscape)


## Прокрутить так, чтобы текущий уровень стоял на FOCUS_AT высоты окна.
func focus_current() -> void:
	scroll.scroll_vertical = path.scroll_for(path.current, scroll.size.y, FOCUS_AT)


## Тема фона — глава уровня посреди экрана (19.5c): прокрутили в другую главу — фон плавно меняется.
func update_theme(animate: bool) -> void:
	var band := path.view_band()
	background.set_chapter_theme(Chapters.theme_of(path.level_near((band.x + band.y) * 0.5)), animate)


func _on_scrolled(_value: float) -> void:
	update_theme(true)


func _refresh() -> void:
	score_label.text = HudHeader.format_score(GameState.total_score)
	_layout_score()


func _layout_score() -> void:
	HudHeader.layout_score_row(star, star_shadow, score_label, score_row.size.x, score_row.size.y * 0.5, SCORE_SIZE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		go_home()
	elif Desktop.key_pressed(event, KEY_ENTER) or Desktop.key_pressed(event, KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		open_level(path.current)


## Игра с уровня n (только открытые: 1…GameState.level).
func open_level(n: int) -> void:
	if Transition.is_busy() or n < 1 or n > GameState.level:
		return
	Audio.play(Audio.CLICK)
	GameState.requested_level = n
	Transition.change_scene(GAME_SCENE)


func _on_locked(_n: int) -> void:
	Audio.play(Audio.MISS)


func go_home() -> void:
	if Transition.is_busy():
		return
	Audio.play(Audio.CLICK)
	Transition.change_scene(MENU_SCENE)
