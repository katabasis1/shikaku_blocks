extends Node
## Аналитика (этап 16.1): цели Яндекс Метрики.
##
## Счётчик и его номер — в оболочке экспорта web/shell.html (METRIKA_ID; там же цели загрузки load_done и
## load_error), отсюда игра шлёт свои цели через window.ShikakuMetrika.goal. Вне веба, без оболочки или с
## METRIKA_ID = 0 цели только пишутся в журнал journal (selftest, отладка) — игра от Метрики не зависит.
##
## Параметры вложены по имени цели и уровню: {"level_win": {"L0012": {"stars": 3, …}}}. В Метрике (отчёт
## «Параметры визитов») это дерево level_win → L0012 → stars → 3: воронка по уровням без отдельной цели на каждый
## уровень (у счётчика их не больше 200). Время — интервалами (span), а не секундами: иначе в отчёте тысячи строк.
## Список целей для создания в Метрике и отчёты для этапа 17 — README, раздел «Аналитика».
##
## Попытка — от начала уровня до итога: level_win (победа), level_exit (ушёл в меню, на карту, закрыл сцену) или
## level_restart («Заново» посреди уровня; «Заново» из окна победы — уже не попытка). Внутри попытки: first_move
## (первый свой ход, через сколько секунд), dead_end и undo — по разу за попытку (сколько всего — в итоге),
## hint — каждая (бесплатная или за рекламу). Ежедневная задача — цели daily_start / daily_win / daily_exit /
## daily_restart, ключ "day" вместо номера уровня. «Лаборатория» (отладка) не считается.

## Границы интервалов секунд (span): "0-3", "3-5", …, "120-300", "300+". Те же — в web/shell.html (SPAN_EDGES),
## сверяет tools/check_shell.py.
const SPAN_EDGES: Array[int] = [3, 5, 10, 20, 30, 60, 120, 300]
## Сколько последних целей помнит журнал.
const JOURNAL_SIZE := 200
## Ключ ежедневной задачи вместо номера уровня.
const DAILY_KEY := "day"
## Имена навыков обучения (биты Tutorial) в цели tutorial_step.
const SKILL_NAMES := {
	Tutorial.DRAG: "drag", Tutorial.ROTATE: "rotate", Tutorial.ONE_NUMBER: "one_number", Tutorial.SOLO: "solo",
	Tutorial.UNDO: "undo", Tutorial.HINT: "hint",
}

## Последние цели: {"goal": имя, "params": параметры} — старые в начале.
var journal: Array[Dictionary] = []
## Сколько целей ушло в Метрику за запуск.
var sent: int = 0
## Ключ открытой попытки ("L0012" или DAILY_KEY); "" — попытки нет.
var run_key: String = ""
## Открытая попытка — ежедневная задача.
var run_daily: bool = false

var _js = null  # JavaScriptObject window.ShikakuMetrika (только в вебе); без типа — как YSDK._bridge
var _ready_sent: bool = false
var _run_start_ms: int = 0
var _first_move: bool = false
var _undos: int = 0
var _dead_ends: int = 0
var _hints: int = 0


func _ready() -> void:
	if OS.has_feature("web") and Engine.has_singleton(&"JavaScriptBridge"):
		_js = Engine.get_singleton(&"JavaScriptBridge").get_interface("ShikakuMetrika")


## Цели уходят в Метрику: веб, оболочка web/shell.html и номер счётчика в ней.
func is_enabled() -> bool:
	return _js != null and int(_js.id) > 0


## Цель goal_id с параметрами params: в журнал и, если счётчик есть, в Метрику.
func goal(goal_id: String, params: Dictionary = {}) -> void:
	journal.append({"goal": goal_id, "params": params})
	if journal.size() > JOURNAL_SIZE:
		journal.pop_front()
	if is_enabled():
		_js.goal(goal_id, JSON.stringify(params) if not params.is_empty() else "")
		sent += 1


## Последняя цель goal_id из журнала ({} — не было).
func last(goal_id: String) -> Dictionary:
	for i in range(journal.size() - 1, -1, -1):
		if journal[i]["goal"] == goal_id:
			return journal[i]
	return {}


## Сколько раз в журнале цель goal_id.
func count(goal_id: String) -> int:
	var n := 0
	for e in journal:
		if e["goal"] == goal_id:
			n += 1
	return n


## Интервал секунд sec: "0-3", "3-5", …, "300+".
static func span(sec: float) -> String:
	var lo := 0
	for edge in SPAN_EDGES:
		if sec < edge:
			return "%d-%d" % [lo, edge]
		lo = edge
	return "%d+" % lo


## Ключ уровня n в параметрах: "L0012" (нули — чтобы в отчёте уровни шли по порядку).
static func level_key(n: int) -> String:
	return "L%04d" % n


## Игра загрузилась (меню на экране, YSDK.loading_ready): цель game_ready один раз за запуск, boot — сколько
## секунд от старта движка (от открытия страницы — load_done из оболочки).
func game_ready() -> void:
	if _ready_sent:
		return
	_ready_sent = true
	goal("game_ready", {"game_ready": {"boot": span(Time.get_ticks_msec() / 1000.0)}})


# --- Попытка уровня -----------------------------------------------------------

## Начало попытки: уровень n или ежедневная задача (daily). replay — уровень (или задача дня) уже пройден.
## Незакрытая прошлая попытка закрывается как выход.
func run_start(n: int, daily: bool, replay: bool) -> void:
	if not run_key.is_empty():
		run_end(&"exit", -1, -1)
	run_daily = daily
	run_key = DAILY_KEY if daily else level_key(n)
	_run_start_ms = Time.get_ticks_msec()
	_first_move = false
	_undos = 0
	_dead_ends = 0
	_hints = 0
	_run_goal("start", "replay" if replay else "new")


## Свой ход (перетаскиванием, не подсказкой): первый за попытку — first_move через сколько секунд.
func run_move() -> void:
	if run_key.is_empty() or _first_move:
		return
	_first_move = true
	goal("first_move", {"first_move": {run_key: span(_run_seconds())}})


## Тупик: dead_end — первый за попытку, число — в итоге.
func run_dead_end() -> void:
	if run_key.is_empty():
		return
	_dead_ends += 1
	if _dead_ends == 1:
		goal("dead_end", {"dead_end": {run_key: 1}})


## Отмена хода: undo — первая за попытку, число — в итоге.
func run_undo() -> void:
	if run_key.is_empty():
		return
	_undos += 1
	if _undos == 1:
		goal("undo", {"undo": {run_key: 1}})


## Подсказка (поставила блок или откатила тупик): каждая; paid — после рекламы за награду.
func run_hint(paid: bool) -> void:
	if run_key.is_empty():
		return
	_hints += 1
	goal("hint", {"hint": {run_key: "ad" if paid else "free"}})


## Победа: level_win (daily_win) — звёзды, время, отмены, подсказки, тупики; extra — добавить (серия дня).
func run_win(stars: int, extra: Dictionary = {}) -> void:
	if run_key.is_empty():
		return
	var info := {"stars": stars, "time": span(_run_seconds()), "undo": _undos, "hint": _hints, "dead": _dead_ends}
	info.merge(extra)
	_run_goal("win", info)
	run_key = ""


## Попытка закончилась без победы: reason — &"exit" (ушёл) или &"restart" («Заново»); placed из total блоков
## на поле (-1 — неизвестно). Попытки нет — ничего.
func run_end(reason: StringName, placed: int, total: int) -> void:
	if run_key.is_empty():
		return
	var info := {"time": span(_run_seconds()), "undo": _undos, "hint": _hints, "dead": _dead_ends}
	if placed >= 0 and total > 0:
		info["placed"] = "%d/%d" % [placed, total]
	_run_goal(String(reason), info)
	run_key = ""


func _run_seconds() -> float:
	return (Time.get_ticks_msec() - _run_start_ms) / 1000.0


## Цель попытки: level_<what> или daily_<what> с параметрами {цель: {ключ попытки: value}}.
func _run_goal(what: String, value: Variant) -> void:
	var goal_id := ("daily_" if run_daily else "level_") + what
	goal(goal_id, {goal_id: {run_key: value}})


# --- Прочее -------------------------------------------------------------------

## Навык обучения skill (бит Tutorial) пройден впервые (GameState.learn): tutorial_step — навык и уровень
## (ключ открытой попытки; вне уровня — "menu").
func tutorial_step(skill: int) -> void:
	var skill_name: String = SKILL_NAMES.get(skill, str(skill))
	goal("tutorial_step", {"tutorial_step": {skill_name: run_key if not run_key.is_empty() else "menu"}})


## Итог рекламы (YSDK): kind — YSDK.AD_INTERSTITIAL / AD_REWARDED, result — "shown", "rewarded", "closed",
## "not_shown" (Яндекс не показал), "timeout" (не открылась за YSDK.AD_OPEN_TIMEOUT_MS).
func ad(kind: StringName, result: String) -> void:
	var goal_id := "ad_" + String(kind)
	goal(goal_id, {goal_id: result})


## Итог запроса отзыва (YSDK, feedback): "sent", "closed" или причина отказа Яндекса (no_auth, game_rated, …).
func review(result: String) -> void:
	goal("review", {"review": result})
