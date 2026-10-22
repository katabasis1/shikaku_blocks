extends Node
## Качество эффектов (автозагрузка Quality; этап 14.7, PLAN 4.5: «при просадке кадров частицы и тени
## упрощаются»). Уровень: 2 «высокое» (как задумано), 1 «среднее», 0 «низкое». Выбирает его автоснижение —
## QualityGovernor, которого Quality кормит длительностью кадров; следующий запуск начинается с сохранённого
## уровня (GameState.quality_level). Кто снижает своё — слушает changed и спрашивает level / particles():
## Juice (частицы), Confetti, Background (фон в SubViewport ½ разрешения), TexShadow; разрешение всего 2D
## на низком (content_scale_mode VIEWPORT) меняет сам Quality. Числа — группа «Качество» в JuiceConfig.
##
## Кадры не в счёт: окно не в фокусе (вкладка в фоне, реклама), игра на паузе (_process стоит), идёт шторка
## (Transition), первые quality_warmup секунд новой сцены. auto = false — уровень не трогает никто, кроме
## set_level (selftest, F4 счётчика).
##
## Счётчик кадров (14.7d, FpsMeter): F3 или 5 быстрых касаний заголовка «Настройки» — показать / спрятать
## (toggle_meter); F4 при показанном счётчике или касание счётчика — уровень вручную по кругу (cycle_level:
## высокое → среднее → низкое → высокое), автоснижение до конца сессии выключено. Выбранный уровень
## сохраняется, следующий запуск начинается с него (и с автоснижением). F5 при показанном счётчике — эффекты
## выключить / вернуть (toggle_effects: JuiceConfig.set_effects_off, 14.8a — игра та же, без анимаций; в счётчике
## «эффекты: выкл.»). Не сохраняется: следующий запуск — с эффектами.
## Счётчик и все его клавиши и касания — только в отладочной сборке (dev_tools, 12.10b): в сборке для игроков
## счётчика нет, F3 / F4 / F5 игра не ловит (в браузере это поиск и обновление страницы — требования Яндекс Игр
## 1.6.2.6 и 1.15: не занимать клавиши браузера, без элементов разработки). Автоснижение работает везде.

signal changed(level: int)

const HIGH := 2
const MID := 1
const LOW := 0
## Названия уровней (счётчик кадров, журнал).
const NAMES := ["низкое", "среднее", "высокое"]

var level := HIGH
## Автоснижение включено (selftest и ручной выбор его выключают).
var auto := true
var governor: QualityGovernor
## Счётчик кадров (скрыт; toggle_meter). В сборке для игроков его нет (null).
var meter: FpsMeter
## Счётчик кадров и его клавиши F3 / F4 / F5 (и 5 касаний заголовка «Настройки») есть. По умолчанию — только в
## отладочной сборке (редактор, экспорт «с отладкой»), как таблетки разработчика (SettingsPanel.dev_tools);
## selftest подменяет, чтобы проверить сборку для игроков.
var dev_tools: bool = OS.is_debug_build()

var _cfg: JuiceConfig
var _scene_id := 0
var _focused := true
var _canvas_mode := Window.CONTENT_SCALE_MODE_CANVAS_ITEMS


func _ready() -> void:
	_cfg = Juice.shared_config()
	_canvas_mode = get_tree().root.content_scale_mode
	level = clampi(GameState.quality_level, LOW, HIGH)
	governor = QualityGovernor.new(_cfg, level)
	_apply_resolution()
	if not dev_tools:
		set_process_input(false)  # сборка для игроков: ни счётчика, ни клавиш F3 / F4 / F5
		return
	meter = FpsMeter.new()
	meter.name = "FpsMeter"
	add_child(meter)


func _input(event: InputEvent) -> void:
	if not dev_tools:
		return
	if Desktop.key_pressed(event, KEY_F3):
		toggle_meter()
		get_viewport().set_input_as_handled()
	elif Desktop.key_pressed(event, KEY_F4) and meter != null and meter.visible:
		cycle_level()
		meter.refresh()
		get_viewport().set_input_as_handled()
	elif Desktop.key_pressed(event, KEY_F5) and meter != null and meter.visible:
		toggle_effects()
		meter.refresh()
		get_viewport().set_input_as_handled()


## Показать или спрятать счётчик кадров (только в отладочной сборке, dev_tools).
func toggle_meter() -> void:
	if dev_tools and meter != null:
		meter.set_shown(not meter.visible)


## Эффекты выключить или вернуть (F5 счётчика; 14.8a): числа JuiceConfig.OFF на общем ресурсе theme/juice.tres —
## видят все (Juice, Block, поле, лоток, окна); действует со следующего эффекта.
func toggle_effects() -> void:
	_cfg.set_effects_off(not _cfg.effects_off())


## Уровень вручную по кругу: высокое → среднее → низкое → высокое; автоснижение выключается.
func cycle_level() -> void:
	set_auto(false)
	set_level((level + 2) % 3)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_focused = false
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			if not _focused and governor:
				governor.reset()  # после фона — разогрев заново
			_focused = true


## Доля частиц и конфетти на текущем уровне (вместе с «Меньше движения» — произведение).
func particles() -> float:
	match level:
		LOW:
			return _cfg.quality_particles_low
		MID:
			return _cfg.quality_particles_mid
	return 1.0


## Название уровня: «высокое», «среднее», «низкое».
func level_name(lv := -1) -> String:
	return NAMES[clampi(level if lv < 0 else lv, LOW, HIGH)]


## Уровень вручную (selftest, F4 счётчика) или от автоснижения (by_auto). Сохраняется в настройки.
func set_level(value: int, by_auto := false) -> void:
	var v := clampi(value, LOW, HIGH)
	if not by_auto and governor:
		governor.level = v
		governor.reset()
	if v == level:
		return
	var was := level
	level = v
	GameState.set_quality_level(v)
	_apply_resolution()
	print("Качество: %s → %s (%.0f к/с)" % [level_name(was), level_name(v), governor.last_fps if governor else 0.0])
	changed.emit(v)


## Включить или выключить автоснижение; при включении замер начинается заново.
func set_auto(on: bool) -> void:
	auto = on
	if on and governor:
		governor.level = level
		governor.reset()


## Низкое (quality_low_res): весь 2D — в базовом разрешении проекта, иначе — как в настройках проекта.
func _apply_resolution() -> void:
	var root := get_tree().root
	var mode := Window.CONTENT_SCALE_MODE_VIEWPORT if level == LOW and _cfg.quality_low_res else _canvas_mode
	if root.content_scale_mode != mode:
		root.content_scale_mode = mode


func _process(delta: float) -> void:
	_track_scene()
	if not auto or governor == null:
		return
	if not _focused or Transition.is_busy():
		governor.skip()
		return
	var lv := governor.push(delta)
	if lv >= 0:
		set_level(lv, true)


## Новая сцена — у решателя разогрев (компиляция шейдеров первых кадров не в счёт).
func _track_scene() -> void:
	var sc := get_tree().current_scene
	var id := sc.get_instance_id() if sc else 0
	if id != _scene_id:
		_scene_id = id
		if governor:
			governor.reset()
