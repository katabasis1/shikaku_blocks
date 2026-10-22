class_name Game
extends Control
## Уровень: запуск, HUD, ходы, сердца и ошибки (20.1a), победа, навигация, пауза.
## Остальное — в компонентах (узлы game.tscn):
##   Tray (Content/Tray)  — лоток: слоты, блоки, очередь, поиск хода по решению;
##   DragController       — перетаскивание, поворот на лету, магнит, примерка;
##   HintController       — подсказка (бесплатная / за рекламу), откат тупика;
##   TutorialCoach        — обучение по навыкам: рука, подпись над полем (Tutorial);
##   Toast (Content/Toast) — всплывающие сообщения;
##   WinPanel, WinBackdrop — окно победы и лучи с конфетти за полем (13.5b);
##   Background — фон (13.7): на победе свет ярче.
## Ввод (_input) и кадры (_process) раздаёт Game: сначала рука, потом перетаскивание.
## Раскладка (портрет / альбом) — apply_layout по размеру экрана, расчёт в GameLayout.
##
## Сердца (20.1a, PLAN 20.1; логика — Hearts): отмены хода нет. Перед каждым своим ходом ShikakuSolver проверяет,
## можно ли после него заполнить поле. Нельзя — ошибка: сердце сгорает сразу, блок встаёт на место, трескается
## (14.6g) и сам возвращается в своё гнездо (MISTAKE_RETURN; любое нажатие на лоток или подсказка — сразу). Так
## тупик на поле не задерживается, и подсказка всегда ищет решение от текущей расстановки. Сердца кончились — поле
## стоит до возрождения (revive) или «Заново»; окно с выбором — 20.1b.

const MENU_SCENE := "res://scenes/menu/menu.tscn"
## level уровня «Лаборатории» (19.3): дальше всех уровней с обучением и страховкой.
const LAB_LEVEL := 100000
const COMBO_WORDS: Array[String] = ["Отлично!", "Супер!", "Невероятно!"]
const COMBO_COLORS: Array[Color] = [Color(0.45, 1.0, 0.7), Color(1.0, 0.85, 0.3), Color(1.0, 0.5, 0.9)]
## Несколько линий за ход: волна по каждой следующей стартует на столько позже, с (14.4).
const LINE_STAGGER := 0.07
## Место над полем под подпись обучения (CoachLabel в BoardArea, уровни со страховкой).
const COACH_SPACE := 96.0
## Победа (13.5b, STYLE 11–12; стиль-кадр A3B_win): поле переезжает в layout.win_board (в альбоме оно на
## месте), шапка, кнопки, «Осталось блоков» и лоток уезжают за край и гаснут — в портрете шапка вверх,
## остальное вниз, в альбоме весь столбик вправо. За полем — WinBackdrop. На новом уровне поле сразу на
## своём месте, а панели возвращаются за WIN_RETURN_TIME.
const WIN_MOVE_TIME := 0.4
const WIN_HIDE_TIME := 0.3
const WIN_RETURN_TIME := 0.25
const WIN_SLIDE_TOP := 180.0
const WIN_SLIDE_BOTTOM := 420.0
const WIN_SLIDE_SIDE := 160.0
## Окно победы — через столько секунд после последнего хода (14.5: удар победы — в миг касания последнего блока,
## через JuiceConfig.land_time; затем hit-stop, волна по полю и мозаика — к окну они доиграли).
const WIN_SHOW_AT := 1.15
## Ошибка (20.1a): неверный блок возвращается в гнездо через столько секунд после хода — после трещины (0,45 с
## предупреждение + JuiceConfig.dead_crack_time). Начальное значение: игрок должен успеть увидеть трещину. Если на
## пробе блок «пропадает раньше, чем понял, что не так» — +0,2 с; если ждут его, чтобы ходить дальше, — −0,2 с.
const MISTAKE_RETURN := 0.9

@onready var board: Board = %Board
@onready var board_area: Control = %BoardArea
@onready var top_bar: Control = $Content/TopBar
@onready var actions_bar: Control = $Content/ActionsBar
@onready var drag_layer: Control = %DragLayer
@onready var fx_layer: Control = %FxLayer
@onready var tray: Tray = %Tray
@onready var toast: Toast = %Toast
@onready var header: HudHeader = %Header
@onready var level_label: Label = %LevelLabel
@onready var score_label: Label = %ScoreLabel
@onready var remaining_label: PillLabel = %RemainingLabel
@onready var coach_label: Label = %CoachLabel
@onready var hearts_bar: HeartsBar = %HeartsBar
@onready var hint_button: Button = %HintButton
@onready var hint_ad_badge: Control = %AdBadge
@onready var hint_counter: Control = %HintCounter
@onready var hint_count: Label = %HintCount
@onready var pause_button: Button = %PauseButton
@onready var restart_button: Button = %RestartButton
@onready var win_panel: WinPanel = %WinPanel
@onready var win_backdrop: WinBackdrop = %WinBackdrop
@onready var background: Background = %Background
@onready var pause_panel: SettingsPanel = %PausePanel
@onready var tutorial_hand: TutorialHand = %TutorialHand
@onready var drag: DragController = $DragController
@onready var hints: HintController = $HintController
@onready var coach: TutorialCoach = $TutorialCoach
@onready var juice: Juice = $Juice

var level: int = 1
var level_data: Dictionary = {}
var daily_mode: bool = false
## «Лаборатория» (19.3): механика и номер уровня (LabLevels); "" — обычная игра. Уровень не идёт в прогресс и счёт,
## без межстраничной рекламы, «Далее» — следующий уровень «Лаборатории». level у такого уровня — LAB_LEVEL:
## обучение, страховка и пульс подсказки ведут себя как на поздних уровнях.
var lab_mechanic: String = ""
var lab_index: int = 0
var daily_date_key: String = ""
## Сделанные ходы: {slot, block, rect, drawn, points, lines, line_rects, streak_before, power}. Ошибочного хода здесь
## нет: он не засчитан (_mistake).
var moves: Array[Dictionary] = []
## Серия (14.4): сколько ходов подряд закрыли хотя бы одну линию; ход без линии и ошибка обнуляют.
var line_streak: int = 0
## Серия постановок (15.2): сколько ходов подряд легли не позже Audio.PLACE_STREAK_WINDOW после прошлого — нота
## постановки на столько ступеней выше (не больше Audio.PLACE_STREAK_MAX). Ошибка и новый уровень обнуляют.
var note_streak: int = 0
var _last_note_ms: int = -1000000
var level_score: int = 0
## Сердца, ошибки и возрождения попытки (20.1a).
var hearts := Hearts.new()
var finished: bool = false
## Открыто окно паузы.
var paused: bool = false
## Ошибочный ход (20.1a): {block, slot, rect} — блок ещё на поле и трескается, сейчас вернётся в гнездо; {} — нет.
## Ход не засчитан: в moves его нет, очков нет, гнездо пустое (новый блок в него не выдан).
var _mistake: Dictionary = {}
## Номер запуска уровня: ответы рекламы от прежнего запуска игнорируются.
var session: int = 0
## Альбомная раскладка (поле слева, столбик справа) — см. apply_layout.
var landscape: bool = GameLayout.last_landscape
## Прямоугольники текущей раскладки (GameLayout.compute).
var layout: Dictionary = {}

## Победа: 0 — игровые места, 1 — победные (_apply_win). Поле и панели — порознь: на новом уровне
## поле сразу на месте, а панели возвращаются твином.
var win_board_t := 0.0
var win_panels_t := 0.0

var _win_tween: Tween
## Через сколько секунд после последнего хода окно победы на этом уровне: WIN_SHOW_AT, а если последний блок
## поставила подсказка (14.6g) — позже на её ожидание и вплывание сверх land_time (удар победы — в миг касания).
var win_at: float = WIN_SHOW_AT
var _return_tween: Tween
## После «Далее» ждём межстраничную рекламу.
var _next_pending: bool = false
## Уровень уже запускался в этой сцене: смена темы фона дальше — плавно (19.5c), первая — сразу.
var _started := false
## Карточка начала главы (19.5d, ChapterCard): создаётся в _ready между FxLayer и DragLayer (несомый блок, рука и
## окна — над ней); _card_level — уровень, для которого она уже была в этой сцене («Заново» не повторяет).
var chapter_card: ChapterCard
var _card_level := 0


func _ready() -> void:
	drag.setup(self)
	hints.setup(self)
	coach.setup(self)
	juice.setup($Content, fx_layer)
	drag.dropped.connect(_on_dropped)
	board.landed.connect(_on_block_landed)
	board_area.resized.connect(_layout_board)
	hint_button.pressed.connect(hints.request)
	pause_button.pressed.connect(_on_pause_pressed)
	pause_panel.closed.connect(_on_resume)
	pause_panel.home_pressed.connect(_on_home_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	win_panel.next_pressed.connect(_on_next_pressed)
	win_panel.replay_pressed.connect(_on_replay_pressed)
	Desktop.add_hover_all(self)
	resized.connect(_on_resized)
	chapter_card = ChapterCard.new()
	chapter_card.name = "ChapterCard"
	add_child(chapter_card)
	move_child(chapter_card, drag_layer.get_index())
	apply_layout(size)
	# Одноразовые запросы меню и карты уровней (18.1, 18.2): ежедневная задача или уровень с карты.
	var open_daily := GameState.daily_requested
	var open_level := GameState.requested_level
	GameState.daily_requested = false
	GameState.requested_level = 0
	# «Лаборатория» (19.3, только отладочная сборка): уровень механики с экрана scenes/lab.
	var open_lab := LabLevels.requested_mechanic
	LabLevels.requested_mechanic = ""
	if not open_lab.is_empty():
		start_lab(open_lab, LabLevels.requested_index)
	elif open_daily:
		start_level(DailyChallenge.current_level(), true)
	elif open_level >= 1 and open_level <= GameState.level:
		start_level(open_level)
	else:
		start_level(GameState.level)


func _exit_tree() -> void:
	YSDK.gameplay_stop()
	_analytics_end(&"exit")  # ушёл посреди уровня (меню, «Лаборатория», сцена закрыта); после победы — ничего


func start_level(n: int, is_daily: bool = false) -> void:
	_begin_level(n, is_daily, LevelGenerator.generate(n), "", 0)


## Уровень «Лаборатории» (19.3): index (1..10) механики mechanic (LabLevels). Нет такого — назад на экран
## «Лаборатории».
func start_lab(mechanic: String, index: int) -> void:
	var data := LabLevels.get_level(mechanic, index)
	if data.is_empty():
		Transition.change_scene(LabLevels.SCENE)
		return
	_begin_level(LAB_LEVEL, false, data, mechanic, index)


## Запуск уровня n с данными data (LevelPack.decode): обычного, ежедневного или «Лаборатории» (mechanic не "").
func _begin_level(n: int, is_daily: bool, data: Dictionary, mechanic: String, index: int) -> void:
	# Метрика (16.1): прошлая попытка не закончилась (уровень сменился посреди) — выход, пока её ходы на месте.
	# После победы и «Заново» попытки уже нет — ничего.
	_analytics_end(&"exit")
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
	# Ежедневная задача: дата — та, чей это уровень. Рестарт после полуночи UTC — та же задача и та же дата,
	# иначе старый уровень засчитался бы за новый день (18.1f).
	if not is_daily:
		daily_date_key = ""
	elif not (daily_mode and n == level and DailyChallenge.is_valid_date(daily_date_key)):
		daily_date_key = DailyChallenge.current_date_key()
	level = n
	daily_mode = is_daily
	lab_mechanic = mechanic
	lab_index = index
	session += 1
	finished = false
	_mistake = {}
	hints.reset()
	juice.reset()
	_next_pending = false
	if paused:
		paused = false
		pause_panel.hide()
	drag.cancel()
	level_data = data
	board.setup(level_data)
	moves.clear()
	line_streak = 0
	_reset_note_streak()
	level_score = 0
	# Сердца (20.1a): обычный уровень — с флага hearts_from_level, задача дня — всегда, «Лаборатория» — без предела.
	hearts.reset(Hearts.max_for(n, is_daily, not mechanic.is_empty(), YSDK.hearts(), YSDK.hearts_from_level()))
	toast.dismiss()
	chapter_card.clear()
	win_panel.hide()
	_reset_win()
	tray.setup(level_data.pieces)
	# Тема фона главы (19.5c): обычный уровень — его глава (на «ДАЛЕЕ» через границу главы — плавно), ежедневная
	# задача и «Лаборатория» — тема главы 1.
	var own_theme := not is_daily and mechanic.is_empty()
	background.set_chapter_theme(Chapters.theme_of(n if own_theme else 1), _started)
	_started = true
	coach.restart(n)
	# Правило механики над полем: «Лаборатория» — всегда; основной путь — вводные уровни главы с новой механикой,
	# ежедневная задача — пока игрок не прошёл вводные уровни этой механики (19.5e, Chapters.rule_of).
	var rule := mechanic if not mechanic.is_empty() else Chapters.rule_of(n, data, is_daily, GameState.level)
	if not rule.is_empty():
		coach.set_rule(rule)
	# Начало главы 2 и дальше, ещё не пройденное, — карточка главы над полем (19.5d), один раз за сцену.
	if ChapterCard.wanted(n, GameState.level, own_theme, _card_level):
		_card_level = n
		chapter_card.show_chapter(n)
	update_hud()
	_layout_board.call_deferred()
	YSDK.gameplay_start()
	# Метрика (16.1): попытка уровня или задачи дня; «Лаборатория» (отладка) не считается.
	if mechanic.is_empty():
		var replay := GameState.daily_is_completed(daily_date_key) if is_daily else n < GameState.level
		Analytics.run_start(n, is_daily, replay)


## Попытка уровня закончилась без победы (16.1): reason — &"exit" или &"restart"; на поле — сколько блоков из всех.
func _analytics_end(reason: StringName) -> void:
	Analytics.run_end(reason, moves.size(), (level_data.get("pieces", []) as Array).size())


## Расставляет узлы под экран screen: портрет или альбом (GameLayout, гистерезис по ширина/высота).
func apply_layout(screen: Vector2) -> void:
	var was := landscape
	landscape = GameLayout.pick(screen, landscape)
	GameLayout.last_landscape = landscape
	layout = GameLayout.compute(screen, landscape)
	_place(top_bar, layout.top_bar)
	_place(board_area, layout.board)
	_place(actions_bar, layout.actions)
	_place(remaining_label, layout.remaining)
	remaining_label.add_theme_font_size_override(&"font_size", layout.remaining_size)
	header.configure(layout.title_size, layout.score_size, layout.title_y, layout.score_y)
	# Сначала гнёзда нового размера, потом рамка лотка: иначе прежний наименьший размер
	# контейнера (столбик 532×792) не дал бы ужать лоток до ряда 700×240.
	tray.arrange(layout.vertical, layout.slot, layout.separation, layout.tray_scale, layout.shelf_pad)
	_place(tray, layout.tray)
	toast.place(layout.toast)  # по центру места, шириной по тексту
	chapter_card.place(layout.board)  # по центру места поля
	win_panel.arrange(layout)
	_apply_win()  # поле (max_scale, вписать) и, если идёт победа, сдвиг панелей
	if landscape != was:
		drag.cancel()  # лоток переехал — несомый блок вернётся в свой слот
	coach.on_layout_changed()


func _on_resized() -> void:
	if is_node_ready():
		apply_layout(size)


## Узел c — ровно в прямоугольник r (координаты Content, он на весь экран).
static func _place(c: Control, r: Rect2) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = r.position
	c.size = r.size


## На уровнях со страховкой над полем подпись обучения (CoachLabel): поле ниже и меньше.
func _layout_board() -> void:
	var top := COACH_SPACE * (1.0 - win_board_t) if coach_label.visible else 0.0
	board.fit_in(board_area.size - Vector2(0.0, top))
	board.position.y += top


## Счёт в шапке: общий счёт и прирост к рекорду уровня (при переигровке — только он).
func hud_score() -> int:
	if daily_mode or not lab_mechanic.is_empty():
		return GameState.total_score  # очки ежедневной задачи и «Лаборатории» в общий счёт не идут (18.1f, 19.3)
	return GameState.total_score + maxi(0, level_score - GameState.get_best(level))


func update_hud() -> void:
	# При переигровке в общий счёт идёт только прирост к рекорду уровня.
	if not lab_mechanic.is_empty():  # «Лаборатория» — отладочный экран, подпись без перевода
		header.show_values(lab_index, hud_score(), LabLevels.header(lab_mechanic, lab_index))
	else:
		header.show_values(level, hud_score(), tr("ЗАДАЧА ДНЯ") if daily_mode else "")
	remaining_label.text = tr("Осталось блоков: %d") % tray.remaining_count()
	hearts_bar.show_hearts(hearts.left, hearts.max_hearts)
	hint_button.disabled = finished or hearts.is_out()
	# Значок на подсказке (13.2b): счётчик бесплатных, когда кончились — «реклама», без рекламы — ничего.
	var free := hints.free_left()
	hint_counter.visible = not finished and free > 0
	hint_count.text = str(free)
	hint_ad_badge.visible = not finished and free == 0 and hints.needs_ad()


# --- Ввод -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Порядок важен: любое нажатие сначала прячет руку, потом идёт в перетаскивание
	# (которое может поглотить событие поворота).
	coach.on_input(event)
	if chapter_card.is_shown() and ChapterCard.is_press(event):
		chapter_card.dismiss()  # карточка главы уходит раньше, нажатие идёт дальше в игру
	if Tray.is_activity(event):
		tray.wake()  # лоток перестаёт «дышать» (14.6e)
	drag.handle_input(event)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or paused:
		return
	# Esc — пауза. Открытое окно паузы само ловит Esc раньше и закрывается.
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_pause_pressed()
	# Клавиши — по месту на клавиатуре (Desktop.key_pressed): работают в любой раскладке. Ctrl+Z и Backspace
	# (отмена хода) убраны вместе с отменой (20.1a).
	elif Desktop.key_pressed(k, KEY_H):
		get_viewport().set_input_as_handled()
		hints.request()


func _notification(what: int) -> void:
	# Окно потеряло фокус посреди перетаскивания — отпускание мыши может не прийти,
	# и лоток «залипнет». Возвращаем блок на место.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		drag.cancel()
	# Язык сменился (YSDK узнал язык игрока) — перерисовать тексты, заданные из кода.
	elif what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not level_data.is_empty():
		update_hud()
		coach.show_caption()


func _process(delta: float) -> void:
	drag.follow_pointer()
	coach.tick(delta)
	tray.breathe(delta, _can_breathe())


## Лотку можно «дышать» в простое (14.6e): уровень идёт, окна паузы и победы нет, ошибочный блок не возвращается
## и сердца не кончились (20.1a), блок не держат, рука-обучение не показывает ход, нет шторки, рекламы и скрытой
## вкладки. Пока нельзя — простой не копится: дыхание начнётся через idle_after после того, как снова можно.
func _can_breathe() -> bool:
	return can_play() and not paused and _mistake.is_empty() and not _next_pending and not drag.is_busy() \
			and not hints.ad_pending and not tutorial_hand.visible and not Transition.is_busy() \
			and not GameState.is_audio_suspended()


# --- Ходы ---------------------------------------------------------------------

## Игрок сам поставил блок перетаскиванием (подсказка ставит через commit_place). Ход заводит в тупик — ошибка
## (20.1a, _on_mistake): ход не засчитан, сердце сгорает.
func _on_dropped(b: Block, i: int, r: Rect2i) -> void:
	Analytics.run_move()  # первый свой ход попытки — first_move (16.1); подсказка сюда не идёт
	if leads_to_dead_end(r, b.cells):
		_on_mistake(b, i, r)
		return
	commit_place(b, i, r)
	coach.on_own_move(r)


## Ставит блок b из слота i на место r (перетаскивание или подсказка). Подсказка (14.6g, 12.10): float_time —
## полёт блока из гнезда на место (Board.place_block); «+очки» — в миг касания.
func commit_place(b: Block, i: int, r: Rect2i, float_time := 0.0) -> void:
	coach.postpone()
	tray.clear_slot(i)
	board.place_block(b, r, float_time)  # удар (звук, тряска, пыль) — когда блок долетит: _on_block_landed

	var points := b.area * 10
	var center := board.cell_center_global(r)
	var lines := board.completed_lines(r)
	var streak_before := line_streak
	line_streak = line_streak + 1 if lines.size() > 0 else 0
	if lines.size() > 0:
		points += 40 * lines.size() * lines.size()  # очки от серии не зависят — серия только в эффектах (14.4)
	level_score += points
	var floating := float_time > 0.0
	if not floating:
		Fx.float_text(fx_layer, "+%d" % points, center, Color.WHITE, 46)

	var drawn := tray.fill_slot(i, 0.12)
	# Линии, серия и сила хода — для удара (_on_block_landed): волна, искры, текст комбо и звук — в миг касания.
	moves.append({"slot": i, "block": b, "rect": r, "drawn": drawn, "points": points, "lines": lines.size(),
			"line_rects": lines, "streak_before": streak_before,
			"power": Block.cfg().combo_power(lines.size(), line_streak), "late_text": floating})
	update_hud()

	if board.is_full():
		_on_level_complete(maxf(0.0, float_time - Block.cfg().land_time) if floating else 0.0)
	else:
		_after_move()


## Блок долетел до места (Board.landed, 14.2): удар — звук, тряска, пыль из-под краёв. Закрыл линии (14.4) —
## по каждой от блока к концам бежит волна света, вдоль линий — искры, звук линии выше по силе хода, над блоком —
## текст комбо «штампом» (слово по силе: COMBO_WORDS). Ход отменён в полёте — сигнала нет.
## Последний блок уровня (14.5) — удар победы (_celebrate): волна по полю заменяет волны и текст линий.
## Звук (15.1–15.3): удар «плюх» и нота постановки (по площади и серии). У хода с линией ноты нет — её заменяет
## перелив линии (две ноты разной высоты разом — каша); у последнего блока — аккорд удара победы. Серия считается
## и на таких ходах.
func _on_block_landed(b: Block, r: Rect2i) -> void:
	var m: Dictionary = {}
	for k in range(moves.size() - 1, -1, -1):
		if moves[k].block == b:
			m = moves[k]
			break
	var rect := board.get_global_transform() * Rect2(Vector2(r.position) * Block.CELL, Vector2(r.size) * Block.CELL)
	var last: bool = finished and not moves.is_empty() and moves.back().block == b
	var lines: Array[Rect2i] = []
	lines.assign(m.get("line_rects", []))
	Audio.play(Audio.PLACE, 0.08)
	_play_place_note(b.area, last or not lines.is_empty())
	juice.landed(rect, r.size, Palette.color_for(b.area))
	if bool(m.get("late_text", false)):  # подсказка (14.6g): «+очки» — когда блок вплыл
		Fx.float_text(fx_layer, "+%d" % int(m.points), rect.get_center(), Color.WHITE, 46)
	if last:
		_celebrate(r, rect.get_center())  # последний блок: удар победы вместо удара линии (14.5)
		return
	if lines.is_empty():
		return
	var power := maxi(int(m.get("power", 0)), 0)
	Audio.play(Audio.LINE, 0.0, Block.cfg().combo_pitch(power))
	var rects: Array[Rect2] = []
	var lengths: Array[int] = []
	for k in lines.size():
		board.flash_line(lines[k], k * LINE_STAGGER, r, power)
		rects.append(board.get_global_transform() * Rect2(Vector2(lines[k].position) * Block.CELL,
				Vector2(lines[k].size) * Block.CELL))
		lengths.append(maxi(lines[k].size.x, lines[k].size.y))
	juice.lines(rects, lengths, power)
	var word := mini(power, COMBO_WORDS.size() - 1)
	Fx.combo_text(fx_layer, tr(COMBO_WORDS[word]), board.cell_center_global(r) + Vector2(0, -70), COMBO_COLORS[word],
			power)


## Нота постановки (15.2): высота — по площади блока и серии постановок (Audio.place_pitch). Серия растёт, если
## прошлый блок лёг не больше чем PLACE_STREAK_WINDOW с назад. silent — только посчитать серию (ноту заменяет
## линия или победа).
func _play_place_note(area: int, silent := false) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_note_ms <= int(Audio.PLACE_STREAK_WINDOW * 1000.0):
		note_streak += 1
	else:
		note_streak = 0
	_last_note_ms = now
	if not silent:
		Audio.play_pitched(Audio.NOTE, Audio.place_pitch(area, note_streak))


func _reset_note_streak() -> void:
	note_streak = 0
	_last_note_ms = -1000000


## Снимает последний засчитанный ход: блок возвращается в свой слот, вытянутый после него — в очередь. Отмены хода
## у игрока нет (20.1a) — так игра выходит из «нет ходов» (_after_move) и самопроверка готовит позиции.
func undo_last() -> void:
	coach.postpone()
	_reset_note_streak()
	var m: Dictionary = moves.pop_back()
	level_score = maxi(0, level_score - int(m.points))
	var b: Block = m.block
	line_streak = int(m.get("streak_before", 0))
	board.remove_block(b)
	b.clear_warn()
	tray.put_back(b, int(m.slot), bool(m.drawn))


## Проверка после засчитанного хода. Тупиковый свой ход сюда не доходит (_on_dropped → _on_mistake), подсказка ставит
## только из решения. Остаётся случай, когда решатель не уложился в лимит (на уровнях игры такого нет — максимум
## 216 шагов из 4000): если ни один блок лотка больше никуда не встаёт, последний ход снимается — без сердца.
func _after_move() -> void:
	var s := solve(placed_rects(), remaining_pieces())
	if s.status == ShikakuSolver.UNKNOWN and tray.is_stuck(board):
		undo_last()
		Audio.play(Audio.MISS)
		toast.show_text(tr("Так остальные блоки не поместятся"), 2.5)
		update_hud()


# --- Сердца и ошибки (20.1a) ----------------------------------------------------

## Можно ходить: уровень идёт и сердца не кончились (пауза, блок в руке — отдельно).
func can_play() -> bool:
	return not finished and not hearts.is_out()


## Ошибочный блок ещё на поле — трескается и сейчас вернётся в гнездо.
func has_mistake() -> bool:
	return not _mistake.is_empty()


## Ошибка (20.1a): блок b из гнезда i лёг на место r, после которого поле не заполнить. Сердце сгорает сразу —
## в кадре хода (14.8: эффекты логику не держат); ход не засчитан: ни очков, ни линий, гнездо остаётся пустым,
## серии обнуляются. Блок ложится (удар, «нота»), через 0,45 с предупреждение — тряска и красный, затем трещина,
## звук ошибки и темнота поля (_play_dead_end), через MISTAKE_RETURN — сам обратно в гнездо (_return_mistake).
## Подпись объясняет причину. Последнее сердце — поле стоит (_on_hearts_out) после возврата блока.
func _on_mistake(b: Block, i: int, r: Rect2i) -> void:
	coach.postpone()
	flush_mistake()
	tray.clear_slot(i)
	board.place_block(b, r)
	_mistake = {"block": b, "slot": i, "rect": r}
	hearts.lose()
	Analytics.run_dead_end()
	_reset_note_streak()
	line_streak = 0
	b.warn(0.45)
	var t := create_tween()
	t.tween_interval(0.45)
	t.tween_callback(_play_dead_end.bind(b, session))
	t.tween_interval(maxf(MISTAKE_RETURN - 0.45, 0.0))
	t.tween_callback(_return_mistake.bind(b, session))
	toast.show_text(tr("Так остальные блоки не поместятся"), 2.5)
	update_hud()


## Тупик (14.6g), в миг предупреждения неверного блока (0,45 с после хода — он уже лёг): звук ошибки, поле на миг
## темнеет, блок трескается, сердца вздрагивают. Блок уже вернулся (нажатие на лоток, подсказка) или уровень
## сменился — ничего.
func _play_dead_end(placed: Block, at_session: int) -> void:
	if at_session != session or _mistake.get("block") != placed or not is_instance_valid(placed) \
			or placed.get_parent() != board.blocks_root:
		return
	Audio.play(Audio.ERROR, 0.0, 1.0)
	board.dim_flash()
	placed.crack()
	Fx.hop(hearts_bar)


## Таймер ошибки: блок placed всё ещё на поле — вернуть его в гнездо.
func _return_mistake(placed: Block, at_session: int) -> void:
	if at_session == session and _mistake.get("block") == placed:
		flush_mistake()


## Ошибочный блок — сразу в своё гнездо (по таймеру или потому, что игрок уже взялся за лоток или подсказку):
## поле снова как до ошибки. Сердца кончились — поле встаёт (_on_hearts_out).
func flush_mistake() -> void:
	if _mistake.is_empty():
		return
	var b: Block = _mistake.block
	var i: int = _mistake.slot
	_mistake = {}
	if is_instance_valid(b):
		board.remove_block(b)
		b.clear_warn()
		tray.put_back(b, i, false)
	update_hud()
	if hearts.is_out():
		_on_hearts_out()


## Сердца кончились: ходить и брать подсказку нельзя (can_play), пауза и «Заново» работают. До окна 20.1b
## («Продолжить» за рекламу / «Заново») — подпись и прыжок кнопки «Заново».
func _on_hearts_out() -> void:
	drag.cancel()
	toast.show_text(tr("Сердца кончились — начни заново"), 0.0)
	Fx.hop(restart_button)
	update_hud()


## Возрождение (20.1b вызовет из окна): +1 сердце, поле как есть; звёзд за уровень — 1. free — бесплатное
## продолжение (реклама не показалась). false — сейчас нельзя (сердца не кончились или возрождения исчерпаны).
func revive(free := false) -> bool:
	if finished or not hearts.can_revive(YSDK.revive_max()):
		return false
	if free and not hearts.can_continue_free(YSDK.revive_free_on_fail()):
		return false
	hearts.revive(free)
	toast.dismiss()
	update_hud()
	return true


# --- Решатель -------------------------------------------------------------------

func solve(placed: Array[Rect2i], pieces: Array[Vector2i]) -> ShikakuSolver:
	return ShikakuSolver.run_level(level_data, placed, pieces)  # механики 19.3 — правила из level_data


## Прямоугольники поставленных блоков (без последних skip_last ходов).
func placed_rects(skip_last: int = 0) -> Array[Rect2i]:
	var res: Array[Rect2i] = []
	for k in maxi(0, moves.size() - skip_last):
		res.append(moves[k].rect)
	return res


## Размеры ещё не поставленных блоков (очередь и лоток).
func remaining_pieces() -> Array[Vector2i]:
	return tray.remaining_cells()


## Ход «блок dims на место r» оставляет поле нерешаемым.
func leads_to_dead_end(r: Rect2i, dims: Vector2i) -> bool:
	var placed := placed_rects()
	placed.append(r)
	var pieces := remaining_pieces()
	var key := ShikakuSolver.shape_key(dims)
	for k in pieces.size():
		if ShikakuSolver.shape_key(pieces[k]) == key:
			pieces.remove_at(k)
			break
	return solve(placed, pieces).status == ShikakuSolver.UNSOLVABLE


# --- Победа и навигация ---------------------------------------------------------

## later — на сколько позже обычного окно победы (последний блок ставит подсказка: его ожидание и вплывание).
func _on_level_complete(later := 0.0) -> void:
	finished = true
	win_at = WIN_SHOW_AT + later
	coach.on_level_complete()
	_mistake = {}
	toast.dismiss()
	chapter_card.dismiss()
	YSDK.gameplay_stop()
	var stars := hearts.stars(hints.used)  # 20.1a: 3 − ошибки − подсказки, не ниже 1; после возрождения — 1
	level_score += 50 * stars
	var earned := level_score
	# Засчитываем уровень сразу, а не после празднования: иначе выход в меню,
	# рестарт или закрытие вкладки в эти ~1,2 с теряли прогресс.
	# gain — на сколько вырос общий счёт (при переигровке только прирост к рекорду).
	var gain := -1
	if daily_mode:
		GameState.complete_daily(daily_date_key, stars, earned)
		Analytics.run_win(stars, {"streak": GameState.daily_streak})
	elif not lab_mechanic.is_empty():
		LabLevels.mark_done(lab_mechanic, lab_index, stars)  # «Лаборатория»: только отметка на её экране
	else:
		gain = GameState.complete_level(level, stars, earned)
		Analytics.run_win(stars)
	level_score = 0
	update_hud()
	# Таймлайн празднования на твине, привязанном к узлу: при уходе со сцены он гасится сам.
	# Удар победы и волна по полю — в миг касания последнего блока (_on_block_landed → _celebrate), затем окно
	# победы: поле переезжает, панели уходят (STYLE 12, «Торжество»). Окно — по времени, а не по удару: блок
	# мог и не долететь (уход со сцены), а окно нужно в любом случае.
	_win_tween = create_tween()
	_win_tween.tween_interval(win_at)
	_win_tween.tween_callback(_show_win.bind(stars, earned, gain))
	_win_tween.tween_method(_set_win_board_t, 0.0, 1.0, WIN_MOVE_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_win_tween.parallel().tween_method(_set_win_panels_t, 0.0, 1.0, WIN_HIDE_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


## Удар победы (14.5, PLAN 4.4) в миг касания последнего блока r (at — его середина на экране): hit-stop
## (hitstop_win), тряска, звёздочки и звук победы; после паузы — волна по полю от блока, блоки вспыхивают и сходятся
## в мозаику (Board.celebrate; его твины — через Juice, поэтому ждут конца hit-stop).
func _celebrate(r: Rect2i, at: Vector2) -> void:
	juice.event(&"win", at)
	board.celebrate(r)
	Audio.play(Audio.WIN, 0.0)


func _show_win(stars: int, earned: int, gain: int) -> void:
	if _return_tween and _return_tween.is_valid():
		_return_tween.kill()
	if daily_mode:
		win_panel.show_daily(stars, earned, GameState.daily_streak)
	elif not lab_mechanic.is_empty():
		win_panel.show_result(lab_index, stars, earned, GameState.total_score)
	else:
		win_panel.show_result(level, stars, earned, GameState.total_score, gain, GameState.get_best(level))
	var fr := _board_frame()
	win_backdrop.play(fr.get_center(), maxf(fr.size.x, fr.size.y))
	background.set_win(true)


func _set_win_board_t(t: float) -> void:
	win_board_t = t
	_apply_win()


func _set_win_panels_t(t: float) -> void:
	win_panels_t = t
	_apply_win()


## Места на время победы (и обычные при 0 / 0): BoardArea — между layout.board и layout.win_board
## (win_board_t), наибольший масштаб поля — между board_scale и win_board_scale; шапка, кнопки,
## «Осталось блоков», лоток, подпись про поворот и подпись обучения уезжают и гаснут (win_panels_t).
## Лучи и конфетти — за серединой поля.
func _apply_win() -> void:
	var bt := win_board_t
	var r0: Rect2 = layout.board
	var r1: Rect2 = layout.win_board
	_place(board_area, Rect2(r0.position.lerp(r1.position, bt), r0.size.lerp(r1.size, bt)))
	board.max_scale = lerpf(layout.board_scale, layout.win_board_scale, bt)
	var pt := win_panels_t
	var up := Vector2(WIN_SLIDE_SIDE, 0.0) if landscape else Vector2(0.0, -WIN_SLIDE_TOP)
	var down := Vector2(WIN_SLIDE_SIDE, 0.0) if landscape else Vector2(0.0, WIN_SLIDE_BOTTOM)
	var panels: Array = [[top_bar, layout.top_bar, up], [actions_bar, layout.actions, down],
			[remaining_label, layout.remaining, down], [tray, layout.tray, down]]
	for item: Array in panels:
		var c: Control = item[0]
		var r: Rect2 = item[1]
		var shift: Vector2 = item[2]
		c.position = r.position + shift * pt
		c.modulate.a = 1.0 - pt
	coach_label.modulate.a = 1.0 - pt
	_layout_board()
	if win_backdrop.visible:
		var fr := _board_frame()
		win_backdrop.set_center(fr.get_center(), maxf(fr.size.x, fr.size.y))


## Рамка поля в координатах WinBackdrop (он на весь экран Game).
func _board_frame() -> Rect2:
	var fr := board.frame_rect_global()
	fr.position -= win_backdrop.global_position
	return fr


## Новый уровень: лучи и конфетти гаснут, свет фона — обычный, поле сразу на своём месте, панели
## возвращаются твином.
func _reset_win() -> void:
	win_backdrop.stop()
	background.set_win(false)
	if _return_tween and _return_tween.is_valid():
		_return_tween.kill()
	win_board_t = 0.0
	if win_panels_t > 0.0:
		_return_tween = create_tween()
		_return_tween.tween_method(_set_win_panels_t, win_panels_t, 0.0, WIN_RETURN_TIME) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_apply_win()


func _on_next_pressed() -> void:
	if _next_pending:
		return
	if daily_mode:
		Audio.play(Audio.CLICK)
		Transition.change_scene(MENU_SCENE)
		return
	if not lab_mechanic.is_empty():  # «Лаборатория»: следующий её уровень без рекламы, после последнего — её экран
		Audio.play(Audio.CLICK)
		var nx := LabLevels.next_after(lab_mechanic, lab_index)
		if nx.is_empty():
			Transition.change_scene(LabLevels.SCENE)
		else:
			start_lab(nx.mechanic, nx.index)
		return
	# Окно победы остаётся на экране (кнопки выключены) и закрывает поле, пока
	# ждём рекламу: иначе «Заново» / «Домой» успевали сработать до её показа.
	_next_pending = true
	# Межстраничная реклама (YSDK сам следит за частотой; вне Яндекса — сразу колбэк).
	YSDK.show_interstitial(_go_to_next_level.bind(session))


func _go_to_next_level(from_session: int) -> void:
	if from_session != session:
		return
	start_level(GameState.level)


func _on_replay_pressed() -> void:
	if _next_pending:
		return
	_restart_same()


func _on_restart_pressed() -> void:
	if _next_pending:
		return
	Audio.play(Audio.CLICK)
	_analytics_end(&"restart")  # «Заново» посреди уровня (после победы попытки уже нет — ничего)
	_restart_same()


## Тот же уровень заново: обычный, ежедневный или «Лаборатории».
func _restart_same() -> void:
	if lab_mechanic.is_empty():
		start_level(level, daily_mode)
	else:
		start_lab(lab_mechanic, lab_index)


## «В меню» из окна паузы (звук клика играет само окно).
func _on_home_pressed() -> void:
	if _next_pending:
		return
	Transition.change_scene(MENU_SCENE if lab_mechanic.is_empty() else LabLevels.SCENE)


# --- Пауза ----------------------------------------------------------------------

func _on_pause_pressed() -> void:
	if finished or paused or _next_pending:
		return
	Audio.play(Audio.CLICK)
	open_pause()


## Окно паузы: настройки звука, «Продолжить», «В меню». GameplayAPI на это время стоит.
func open_pause() -> void:
	paused = true
	drag.cancel()
	coach.postpone()
	YSDK.gameplay_stop()
	pause_panel.open(SettingsPanel.Mode.PAUSE)


func _on_resume() -> void:
	paused = false
	if not finished:
		YSDK.gameplay_start()
