class_name TutorialCoach
extends Node
## Обучение по навыкам (данные — scripts/tutorial.gd): рука, подпись над полем
## и подсказки в тот момент, когда навык впервые нужен.
##   Уровень 1 (DRAG): рука показывает ход почти сразу; после Tutorial.DRAG_OWN_MOVES
##     своих ходов больше не появляется. Кто ходит сам, руку не видит.
##   Уровень 2 (ROTATE): рука с «нажатием» показывает поворот так же сразу, как на уровне 1
##     (07.10; блок, который надо повернуть, — первый в лотке), и сразу после неудачной попытки
##     с ним. Навык пройден, когда игрок сам повернул блок и потом поставил блок.
##   Уровень 3 (ONE_NUMBER): рука так же сразу (07.10) показывает урок — блок на одно из двух одинаковых
##     соседних чисел (он первый в лотке). Когда игрок сам поставил такой блок, урок понят: дальше рука —
##     только после долгого простоя, учит страховка (подпись объясняет, почему блок не встаёт).
##     Навык пройден вместе с уровнем.
##   Уровни 1..Tutorial.GUARD_LEVELS: подпись над полем (CoachLabel) — навык уровня
##     или правило, а пока блок над красным местом — причина одной строкой.
##   Урок отмены (UNDO: первый тупик — поле тускнеет, рука жмёт на «Отмена») убран вместе с отменой (20.1a);
##     про сердца на уровне 4 — 20.1d.
##   Долгий простой на уровнях Tutorial.HINT_FROM..HINT_TO (HINT): пульс кнопки подсказки,
##     пока игрок ни разу ей не воспользовался.
## Любое нажатие прячет руку и начинает отсчёт простоя заново.
## Ввод и кадры приходят из Game (on_input, tick), ходы — из Game и DragController.

## Уровни 1–3: через сколько секунд рука появляется впервые.
const FIRST_DELAY := 1.2
## Уровни 1–3: через сколько секунд простоя рука показывает ход снова.
const IDLE_DELAY := 3.5
## Уровень 3 после урока (и всё, где рука не учит): рука только после долгого простоя — учит страховка.
const LONG_IDLE := 7.0
## Уровень 2: пауза перед рукой после неудачной попытки с блоком, который надо повернуть.
const TURN_DELAY := 0.35
## Сколько секунд причина держится в подписи после неудачного броска.
const REASON_HOLD := 2.5
## Раскладка экрана поменялась посреди жеста руки: через сколько секунд показать его заново.
const RELAYOUT_DELAY := 0.3
const CAPTION_COLOR := Color(1, 1, 1, 0.95)
const REASON_COLOR := Color(1.0, 0.64, 0.64)

## Навык, которому учит рука на этом уровне (Tutorial.*; 0 — рука не нужна).
var skill: int = 0
## Секунд до следующего показа руки.
var countdown: float = 0.0
## Куда рука ведёт блок сейчас.
var target := Rect2i()
## На поле подсвечено место, куда привела рука.
var preview_shown: bool = false
## Секунд без нажатий (для подсказки HINT).
var idle: float = 0.0
## Своих ходов на уровне (перетаскиванием; подсказки не в счёт).
var own_moves: int = 0
## Кнопку подсказки на этом уровне уже предлагали.
var hint_offered: bool = false

## Навык уровня на момент старта — по нему выбирается подпись.
var _caption_skill: int = 0
## Механика уровня «Лаборатории» (set_rule): её правило — подпись над полем.
var _rule := ""
var _rotated: bool = false
## Уровень 3: игрок сам поставил блок на одно из двух одинаковых соседних чисел — рука больше не торопится.
var _pair_done: bool = false
## Слот, чей ход рука покажет первым (блок, который не удалось поставить без поворота).
var _focus_slot: int = -1
var _reason_left: float = 0.0
var _game: Game
var _hand: TutorialHand
var _label: Label


func setup(game: Game) -> void:
	_game = game
	_hand = game.tutorial_hand
	_label = game.coach_label
	_hand.arrived.connect(_on_hand_arrived)
	_hand.finished.connect(_on_hand_finished)
	game.drag.pressed.connect(postpone)
	game.drag.returned.connect(_on_returned)
	game.drag.hover_changed.connect(_on_hover_changed)
	game.drag.rotated.connect(_on_rotated)
	GameState.hint_used.connect(_on_hint_used)


## Новый уровень: навык уровня, подпись над полем. После обучения — ни подписи, ни напутствий (07.10:
## «Дальше — сам!» на уровне 4 убран — «обучение кончилось и всё»).
func restart(level: int) -> void:
	stop()
	skill = Tutorial.skill_for_level(level, GameState.tutorial)
	_caption_skill = skill
	countdown = FIRST_DELAY if _quick_hand() else LONG_IDLE
	idle = 0.0
	own_moves = 0
	hint_offered = false
	_rotated = false
	_pair_done = false
	_focus_slot = -1
	_rule = ""
	_label.visible = level <= Tutorial.GUARD_LEVELS
	show_caption()


## Игрок что-то делает — спрятать руку и ждать простоя заново.
func postpone() -> void:
	idle = 0.0
	countdown = _repeat_delay()
	stop()


## Прячет руку и подсветку места (игрок начал ход, пауза, новый уровень).
func stop() -> void:
	if _hand.visible:
		_hand.stop()
	_clear_preview()


## Ввод из Game._input: любое нажатие — игрок не простаивает.
func on_input(event: InputEvent) -> void:
	if _is_press(event):
		postpone()


## Каждый кадр из Game._process.
func tick(delta: float) -> void:
	var g := _game
	if g.finished or g.paused or g.hints.ad_pending or Transition.is_busy() \
			or GameState.is_audio_suspended():  # реклама, скрытая вкладка, пауза платформы
		return
	if _reason_left > 0.0:
		_reason_left -= delta
		if _reason_left <= 0.0:
			show_caption()
	if g.drag.is_busy() or not g.can_play():
		return
	idle += delta
	if not hint_offered and idle >= Tutorial.HINT_IDLE and _can_offer_hint():
		_offer_hint()
	if _hand.visible:
		return
	if skill != 0:
		countdown -= delta
		if countdown <= 0.0:
			_show()


## Игрок сам поставил блок на место r (перетаскиванием; Game._on_dropped).
func on_own_move(r := Rect2i()) -> void:
	own_moves += 1
	if skill == Tutorial.DRAG and own_moves >= Tutorial.DRAG_OWN_MOVES:
		_learn_level_skill()
	elif skill == Tutorial.ROTATE and _rotated:
		_learn_level_skill()
	elif skill == Tutorial.ONE_NUMBER and not _pair_done and _game.board.has_twin_next_to(r):
		_pair_done = true
		countdown = LONG_IDLE


## Уровень пройден: навык уровня засчитан, рука убрана.
func on_level_complete() -> void:
	stop()
	if skill != 0:
		_learn_level_skill()


## Верный ход для руки: {slot, rect} или {}. Сначала ход без поворота, а на уроке
## поворота (ROTATE) — блок, который встанет только повёрнутым. Пока ошибочный блок на поле (20.1a) — хода нет.
func next_move() -> Dictionary:
	var g := _game
	if g.has_mistake():
		return {}
	var s := g.solve(g.placed_rects(), g.remaining_pieces())
	if s.status == ShikakuSolver.UNSOLVABLE:
		return {}
	var rects: Array = s.solution
	if s.status != ShikakuSolver.SOLVED:
		rects = g.level_data.solution  # решатель не уложился в лимит — эталонное решение
	# Урок поворота: рука показывает блок, который встанет только повёрнутым, —
	# иначе подпись «Нажми на блок, чтобы повернуть его» и рука говорят о разном.
	if skill == Tutorial.ROTATE:
		var m := _turn_move(rects)
		if not m.is_empty():
			return m
	return g.tray.find_move(rects, g.board, true)


## Ход блока из лотка, который по решению rects встанет только повёрнутым: {slot, rect} или {}.
func _turn_move(rects: Array) -> Dictionary:
	var g := _game
	for i in g.tray.blocks.size():
		var b: Block = g.tray.blocks[i]
		if b == null:
			continue
		var m := _slot_move(i, rects)
		if m.is_empty():
			continue
		var r: Rect2i = m.rect
		if r.size != b.cells:
			return m
	return {}


## Правило механики mechanic (LabLevels: unknown, holes, tints, pinned) над полем — уровень «Лаборатории» (19.3),
## вместо подписи навыка. Сбрасывает restart; задаёт Game.start_lab после restart.
func set_rule(mechanic: String) -> void:
	_rule = mechanic
	_label.visible = true
	show_caption()


## Подпись правила механики — перевод LabLevels.rule ("" — не механика).
func rule_text(mechanic: String) -> String:
	var id := LabLevels.rule(mechanic)
	return tr(id) if not id.is_empty() else ""


## Подпись над полем: правило механики, навык уровня (или правило шикаку, если навык уже пройден).
func caption() -> String:
	if not _rule.is_empty():
		return rule_text(_rule)
	if _caption_skill == Tutorial.DRAG:
		return tr("Число — это размер блока. Перетащи блок на его число")
	if _caption_skill == Tutorial.ROTATE:
		return tr("Нажми на блок, чтобы повернуть его")
	if _caption_skill == Tutorial.ONE_NUMBER:
		return tr("В каждом блоке — ровно одно число")
	return tr("Блок накрывает одно число, и его размер равен этому числу")


## Почему блок не встаёт — одной строкой ("" — объяснять нечего: не над полем или встанет).
func reason_text(issue: int, value: int) -> String:
	if issue == Tutorial.Issue.OCCUPIED:
		return tr("Блоки не должны накладываться")
	if issue == Tutorial.Issue.NO_NUMBER or issue == Tutorial.Issue.MANY_NUMBERS:
		return tr("В блоке должно быть ровно одно число")
	if issue == Tutorial.Issue.WRONG_SIZE:
		return tr("Здесь нужен блок из %d клеток") % value
	if issue == Tutorial.Issue.DEAD_END:
		return tr("Так остальные блоки не поместятся")
	if issue == Tutorial.Issue.BLOCKED:
		return tr("Эта клетка занята с самого начала")
	if issue == Tutorial.Issue.WRONG_COLOR:
		return tr("Цветную клетку накрывает только блок того же цвета")
	return ""


## Вернуть подпись навыка (после причины, при смене языка).
func show_caption() -> void:
	_reason_left = 0.0
	_label.text = caption()
	_label.add_theme_color_override(&"font_color", CAPTION_COLOR)


func _show_reason(text: String) -> void:
	_label.text = text
	_label.add_theme_color_override(&"font_color", REASON_COLOR)


func _repeat_delay() -> float:
	return IDLE_DELAY if _quick_hand() else LONG_IDLE


## Рука показывает ход почти сразу и повторяет его часто: уровни 1 (DRAG), 2 (ROTATE) и 3 (ONE_NUMBER),
## пока игрок сам не поставил блок на одно из двух одинаковых соседних чисел.
func _quick_hand() -> bool:
	return skill == Tutorial.DRAG or skill == Tutorial.ROTATE or (skill == Tutorial.ONE_NUMBER and not _pair_done)


## Game.apply_layout: поле и лоток переехали. Рука вела жест по старым местам —
## прячем её и показываем жест заново по новым.
func on_layout_changed() -> void:
	if _hand != null and _hand.visible:
		stop()
		countdown = RELAYOUT_DELAY


func _learn_level_skill() -> void:
	GameState.learn(skill)
	skill = 0
	_focus_slot = -1
	stop()


func _show() -> void:
	countdown = _repeat_delay()
	var m: Dictionary = {}
	if _focus_slot >= 0:
		m = _move_for_slot(_focus_slot)
		_focus_slot = -1
	if m.is_empty():
		m = next_move()
	if m.is_empty():
		return
	var g := _game
	var i: int = m.slot
	var r: Rect2i = m.rect
	var b: Block = g.tray.blocks[i]
	target = r
	# Блок лежит не той стороной — рука сначала «нажимает» на него (поворот).
	var taps := 0 if r.size == b.cells else 1
	_hand.play(g.tray.slots[i].get_global_rect().get_center(), g.board.cell_center_global(r), taps)


## Ход для блока из слота i по решению от текущей расстановки: {slot, rect} или {}.
## Сначала место без поворота.
func _move_for_slot(i: int) -> Dictionary:
	var g := _game
	if g.tray.blocks[i] == null or g.has_mistake():
		return {}
	var s := g.solve(g.placed_rects(), g.remaining_pieces())
	if s.status != ShikakuSolver.SOLVED:
		return {}
	return _slot_move(i, s.solution)


## Место для блока из слота i среди прямоугольников rects: {slot, rect} или {}.
## Сначала место без поворота.
func _slot_move(i: int, rects: Array) -> Dictionary:
	var g := _game
	var b: Block = g.tray.blocks[i]
	if b == null:
		return {}
	for dims in [b.cells, Vector2i(b.cells.y, b.cells.x)]:
		for item in rects:
			var r: Rect2i = item
			if r.size == dims and g.board.check_rect(r):
				return {"slot": i, "rect": r}
	return {}


## Блок из слота i встанет только повёрнутым.
func _needs_turn(i: int) -> bool:
	var m := _move_for_slot(i)
	if m.is_empty():
		return false
	var b: Block = _game.tray.blocks[i]
	var r: Rect2i = m.rect
	return r.size != b.cells


func _on_returned(slot: int, issue: int, value: int) -> void:
	var text := reason_text(issue, value)
	if _label.visible:
		if text.is_empty():
			show_caption()
		else:
			_show_reason(text)
			_reason_left = REASON_HOLD
	elif issue == Tutorial.Issue.DEAD_END:
		_game.toast.show_text(text, REASON_HOLD)  # страховка без подписи над полем
	if skill == Tutorial.ROTATE and _needs_turn(slot):
		_focus_slot = slot
		countdown = TURN_DELAY


func _on_hover_changed(issue: int, value: int) -> void:
	if not _label.visible:
		return
	var text := reason_text(issue, value)
	if text.is_empty():
		show_caption()
	else:
		_reason_left = 0.0  # держится, пока блок над этим местом
		_show_reason(text)


func _on_rotated() -> void:
	_rotated = true


func _on_hint_used(_level: int) -> void:
	GameState.learn(Tutorial.HINT)


func _can_offer_hint() -> bool:
	var g := _game
	return g.level >= Tutorial.HINT_FROM and g.level <= Tutorial.HINT_TO \
			and not g.has_mistake() and not GameState.has_skill(Tutorial.HINT)


func _offer_hint() -> void:
	hint_offered = true
	Fx.pulse(_game.hint_button)


func _on_hand_arrived() -> void:
	if not _game.drag.is_dragging():
		_game.board.show_preview(target, true)
		preview_shown = true


func _on_hand_finished() -> void:
	_clear_preview()


func _clear_preview() -> void:
	if preview_shown:
		preview_shown = false
		if not _game.drag.is_dragging():
			_game.board.clear_preview()


static func _is_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey:
		return event.is_pressed() and not event.is_echo()
	return false
