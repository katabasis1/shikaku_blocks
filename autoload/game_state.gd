extends Node
## Глобальное состояние: прогресс, очки, настройки.
## Точка интеграции с Яндекс SDK: сигналы и get_save_data()/apply_save_data().

## Изменилась настройка (музыка, звуки, вибрация) — обновить переключатели.
signal settings_changed
## Прогресс изменился целиком (загрузка облачного сохранения, сброс) — обновить UI.
signal progress_changed
## Уровень пройден — удобно показать рекламу / отправить очки в лидерборд.
signal level_completed(level: int, stars: int, score: int)
## Ежедневная задача завершена: дата UTC, серия, звёзды и очки.
signal daily_completed(date_key: String, streak: int, stars: int, score: int)
## Игрок запросил подсказку — сюда можно повесить rewarded-рекламу.
signal hint_used(level: int)
## Прогресс записан на диск — YSDK дублирует его в облако.
signal saved(data: Dictionary)

const SAVE_PATH := "user://save.cfg"
## Предел значения таблицы лидеров в сохранении (как у рекордов уровней).
const LEADERBOARD_MAX := 1 << 30
## v3: лучший результат по каждому уровню (level_best) и legacy_score.
## v4: поколение прогресса (epoch); настройки звука переехали в SETTINGS_PATH.
## v5: пройденные навыки обучения (tutorial, биты Tutorial.*).
## v6: ежедневная задача и серия (daily).
## v7: лучшее, что Яндекс принял в таблицы лидеров (leaderboard, 16.3), — сброс прогресса его не трогает.
const SAVE_VERSION := 7
## Настройки устройства: хранятся отдельно от прогресса и в облако не уходят.
const SETTINGS_PATH := "user://settings.cfg"
## Шины из default_bus_layout.tres (Audio создаёт их, если файла нет).
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"

## Языки с переводом (исходные строки в коде и сценах — русские, переводы в locale/*.po).
const LANGUAGES := ["ru", "en", "tr"]
## Языки, где игроки Яндекс Игр обычно понимают русский: показываем русскую версию.
## Остальным, для кого перевода нет, — английскую.
const RUSSIAN_SPEAKING := ["ru", "be", "kk", "uk", "uz"]

var level: int = 1
## Общий счёт = legacy_score + сумма лучших результатов по уровням.
## Переигровка добавляет к нему только прирост к рекорду уровня,
## поэтому накрутить счёт (и таблицу лидеров) повторными прохождениями нельзя.
## Меняется только через _recount_total().
var total_score: int = 0
var level_stars: Dictionary = {}   # уровень -> лучшие звёзды (0..3)
var level_best: Dictionary = {}    # уровень -> лучший результат (очки)
## Очки из сохранений до v3: там хранился только общий счёт, без разбивки по уровням.
var legacy_score: int = 0
## Поколение прогресса: растёт при сбросе из настроек. Облачное сохранение
## старого поколения (до сброса) не возвращает прогресс, а более нового
## (сброс на другом устройстве) заменяет локальный целиком.
var epoch: int = 0
## Пройденные навыки обучения — биты Tutorial (DRAG, ROTATE, ...). Меняется через learn().
var tutorial: int = 0
## Последняя завершённая ежедневная задача и серия. Это прогресс, он уходит в облако.
var daily_last_date: String = ""
var daily_streak: int = 0
var daily_best_streak: int = 0
var daily_last_score: int = 0
var daily_last_stars: int = 0
## Лучшее, что Яндекс принял в таблицы лидеров (16.3): {техническое имя таблицы: значение}. YSDK не отправляет
## в таблицу значение не больше этого — после сброса прогресса счёт растёт с нуля, и в таблицу не уходит меньший,
## что бы Яндекс с ним ни делал. Это не прогресс: сброс (wipe_progress / reset_progress) его не трогает, облако
## сливается по максимуму при любом поколении. Меняется через note_leaderboard_sent().
var leaderboard_sent: Dictionary = {}
## Одноразовый запрос меню открыть ежедневную задачу. Не сохраняется.
var daily_requested: bool = false
## Одноразовый запрос карты уровней (18.2) открыть уровень N (0 — нет: игра начнёт с GameState.level). Не сохраняется.
var requested_level: int = 0

var music_on: bool = true
var sfx_on: bool = true
var vibration_on: bool = true
## «Меньше движения» (этап 14, PLAN 4.5, STYLE 12): без тряски, наклона, вращения лучей и сильных вспышек,
## частиц вдвое меньше. Доступность — для тех, кого укачивает.
var reduce_motion: bool = false
## Уровень качества эффектов (14.7, Quality): 2 «высокое», 1 «среднее», 0 «низкое». Его выбирает автоснижение;
## следующий запуск начинается с него. Меняет только Quality (set_quality_level).
var quality_level: int = 2
## Запрос отзыва уже был показан игроку. Это настройка устройства, а не прогресс.
var review_prompted: bool = false

## Причины временного приглушения звука (потеря фокуса, реклама, скрытая вкладка).
## Пока есть хоть одна причина, молчит всё (шина Master) независимо от настроек.
var _mute_reasons: Dictionary = {}
## Настройка звука из сохранения до v4 — переносится, если settings.cfg ещё нет.
var _legacy_sound_on: bool = true


func _ready() -> void:
	# Язык системы/браузера; в Яндекс Играх YSDK потом уточнит его по environment.i18n.lang.
	# Для проверки переводов в редакторе: Настройки проекта → Internationalization → Locale → Test = en / tr
	# (в выпуске пусто). Без этого TranslationServer взял бы Test, а здесь его перебил бы язык системы.
	var test_locale := str(ProjectSettings.get_setting("internationalization/locale/test", "")).strip_edges()
	set_language(test_locale if not test_locale.is_empty() else OS.get_locale_language())
	load_game()
	load_settings()
	apply_audio()


## Включает перевод по коду языка ("ru", "en-US", "tr"...).
func set_language(lang: String) -> void:
	var code := lang.to_lower().left(2)
	if code in RUSSIAN_SPEAKING:
		code = "ru"
	elif not (code in LANGUAGES):
		code = "en"
	if TranslationServer.get_locale() != code:
		TranslationServer.set_locale(code)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			set_audio_suspended(&"focus", true)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			set_audio_suspended(&"focus", false)


## Засчитывает уровень. Возвращает, на сколько вырос общий счёт: при первом
## прохождении это score, при переигровке — только прирост к рекорду уровня.
func complete_level(finished_level: int, stars: int, score: int) -> int:
	var gain := maxi(0, score - get_best(finished_level))
	if gain > 0:
		level_best[finished_level] = score
	level_stars[finished_level] = maxi(get_stars(finished_level), stars)
	if finished_level >= level:
		level = finished_level + 1
	_recount_total()
	save_game()
	level_completed.emit(finished_level, stars, score)
	return gain


## Засчитывает ежедневную задачу. Повтор в тот же день не сбрасывает серию и
## может только улучшить сохранённые звёзды и очки.
func complete_daily(date_key: String, stars: int, score: int) -> bool:
	if not DailyChallenge.is_valid_date(date_key):
		return false
	var changed := false
	if daily_last_date != date_key:
		daily_streak = DailyChallenge.next_streak(daily_last_date, date_key, daily_streak)
		daily_last_date = date_key
		daily_last_score = maxi(0, score)
		daily_last_stars = clampi(stars, 0, 3)
		daily_best_streak = maxi(daily_best_streak, daily_streak)
		changed = true
	else:
		if score > daily_last_score:
			daily_last_score = score
			changed = true
		if stars > daily_last_stars:
			daily_last_stars = clampi(stars, 0, 3)
			changed = true
	if changed:
		save_game()
		daily_completed.emit(daily_last_date, daily_streak, daily_last_stars, daily_last_score)
	return changed


## Серия, которая ещё жива на дату today (пусто — сегодня по UTC): задача пройдена сегодня или вчера.
## Пропущен день — 0 (сохранённая daily_streak начнётся заново со следующей задачи, DailyChallenge.next_streak).
func daily_current_streak(today: String = "") -> int:
	var key := today if not today.is_empty() else DailyChallenge.current_date_key()
	if not DailyChallenge.is_valid_date(key) or not DailyChallenge.is_valid_date(daily_last_date):
		return 0
	var gap := DailyChallenge.day_number(key) - DailyChallenge.day_number(daily_last_date)
	return daily_streak if gap == 0 or gap == 1 else 0


func daily_is_completed(date_key: String = "") -> bool:
	var key := date_key if not date_key.is_empty() else DailyChallenge.current_date_key()
	return DailyChallenge.is_valid_date(key) and daily_last_date == key


## Навык обучения skill (бит Tutorial) уже пройден.
func has_skill(skill: int) -> bool:
	return (tutorial & skill) == skill


## Отмечает навык обучения пройденным и сохраняет (один раз на навык; Метрика — tutorial_step, 16.1).
func learn(skill: int) -> void:
	if (tutorial & skill) == skill:
		return
	tutorial |= skill
	save_game()
	Analytics.tutorial_step(skill)


## Лучшее значение, которое Яндекс принял в таблицу board (0 — ещё ничего), 16.3.
func leaderboard_best(board: String) -> int:
	return int(leaderboard_sent.get(board, 0))


## Яндекс принял value в таблицу board (ответ setScore): запомнить, если больше прежнего, и сохранить.
## Возвращает true, если лучшее значение выросло.
func note_leaderboard_sent(board: String, value: int) -> bool:
	if board.is_empty() or value <= leaderboard_best(board):
		return false
	leaderboard_sent[board] = mini(value, LEADERBOARD_MAX)
	save_game()
	return true


func get_stars(for_level: int) -> int:
	return int(level_stars.get(for_level, 0))


## Обучение пройдено: открыт уровень после последнего обучающего (Tutorial.LEVELS). После сброса прогресса — снова нет.
func tutorial_done() -> bool:
	return level > Tutorial.LEVELS


## Лучший результат уровня (0 — ещё не пройден).
func get_best(for_level: int) -> int:
	return int(level_best.get(for_level, 0))


func _recount_total() -> void:
	var sum := legacy_score
	for k in level_best:
		sum += int(level_best[k])
	total_score = sum


# --- Настройки ------------------------------------------------------------

func set_music(enabled: bool) -> void:
	music_on = enabled
	_settings_updated()


func set_sfx(enabled: bool) -> void:
	sfx_on = enabled
	_settings_updated()


func set_vibration(enabled: bool) -> void:
	vibration_on = enabled
	_settings_updated()


func set_reduce_motion(enabled: bool) -> void:
	reduce_motion = enabled
	_settings_updated()


## Уровень качества (Quality, 14.7): сохраняется без settings_changed — экраны настроек он не касается.
func set_quality_level(value: int) -> void:
	var v := clampi(value, 0, 2)
	if v == quality_level:
		return
	quality_level = v
	save_settings()


## Вибрация есть на телефонах: Android (приложение и браузер) и приложение iOS.
## В iOS Safari navigator.vibrate нет, на компьютере вибрировать нечему —
## там переключатель в настройках скрыт.
func can_vibrate() -> bool:
	return OS.has_feature("android") or OS.has_feature("web_android") or OS.has_feature("ios")


func _settings_updated() -> void:
	apply_audio()
	save_settings()
	settings_changed.emit()


## Временно глушит (или возвращает) звук по причине reason, не трогая настройки игрока.
func set_audio_suspended(reason: StringName, suspended: bool) -> void:
	if suspended:
		_mute_reasons[reason] = true
	else:
		_mute_reasons.erase(reason)
	apply_audio()


func is_audio_suspended() -> bool:
	return not _mute_reasons.is_empty()


## Применяет настройки и приглушение к шинам.
func apply_audio() -> void:
	AudioServer.set_bus_mute(0, is_audio_suspended())
	_set_bus_mute(BUS_MUSIC, not music_on)
	_set_bus_mute(BUS_SFX, not sfx_on)


static func _set_bus_mute(bus: StringName, mute: bool) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, mute)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "music_on", music_on)
	cfg.set_value("settings", "sfx_on", sfx_on)
	cfg.set_value("settings", "vibration_on", vibration_on)
	cfg.set_value("settings", "reduce_motion", reduce_motion)
	cfg.set_value("settings", "quality_level", quality_level)
	cfg.set_value("settings", "review_prompted", review_prompted)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("Не удалось сохранить настройки: %s" % error_string(err))


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		# Первый запуск этой версии: переносим общий выключатель звука из сохранения v3.
		music_on = _legacy_sound_on
		sfx_on = _legacy_sound_on
		vibration_on = true
		save_settings()
		return
	music_on = bool(cfg.get_value("settings", "music_on", true))
	sfx_on = bool(cfg.get_value("settings", "sfx_on", true))
	vibration_on = bool(cfg.get_value("settings", "vibration_on", true))
	# 12.10: переключатель «Меньше движения» есть только в отладочной сборке (SettingsPanel.dev_tools) —
	# у игроков сохранённое «вкл» (от старой версии или отладки) не должно остаться без способа выключить.
	reduce_motion = bool(cfg.get_value("settings", "reduce_motion", false)) and OS.is_debug_build()
	quality_level = clampi(int(cfg.get_value("settings", "quality_level", 2)), 0, 2)
	review_prompted = bool(cfg.get_value("settings", "review_prompted", false))


# --- Сохранение -----------------------------------------------------------

func get_save_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"epoch": epoch,
		"level": level,
		"total_score": total_score,  # для удобства чтения; при загрузке пересчитывается
		"legacy_score": legacy_score,
		"level_stars": _dict_to_save(level_stars),
		"level_best": _dict_to_save(level_best),
		"tutorial": tutorial,
		"daily": {
			"date": daily_last_date,
			"streak": daily_streak,
			"best_streak": daily_best_streak,
			"score": daily_last_score,
			"stars": daily_last_stars,
		},
		"leaderboard": leaderboard_sent.duplicate(),
	}


## Загружает сохранение целиком (локальный файл). Понимает старые версии.
func apply_save_data(data: Dictionary) -> void:
	var p := _parse_save(data)
	level = maxi(1, int(data.get("level", level)))
	epoch = p.epoch
	legacy_score = p.legacy
	level_stars = p.stars
	level_best = p.best
	tutorial = p.tutorial
	daily_last_date = p.daily.date
	daily_streak = p.daily.streak
	daily_best_streak = p.daily.best_streak
	daily_last_score = p.daily.score
	daily_last_stars = p.daily.stars
	leaderboard_sent = p.sent
	_recount_total()
	progress_changed.emit()


## Объединяет облачное сохранение с локальным: по каждому уровню берём лучшие
## звёзды и лучший результат, поэтому прогресс с двух устройств не теряется.
## Поколения (epoch) сравниваются первыми: облако до сброса не учитывается,
## облако после сброса на другом устройстве заменяет локальный прогресс.
## Таблицы лидеров (leaderboard_sent, 16.3) — не прогресс: по максимуму при любом поколении.
## Возвращает true, если локальное сохранение изменилось (оно уже сохранено).
func merge_save_data(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var p := _parse_save(data)
	var sent_changed := _merge_sent(p.sent)
	if p.epoch < epoch:
		if sent_changed:
			save_game()
		return sent_changed
	if p.epoch > epoch:
		var keep := leaderboard_sent.duplicate()
		apply_save_data(data)
		leaderboard_sent = keep
		save_game()
		return true
	var changed := sent_changed
	var cloud_level := int(data.get("level", 1))
	if cloud_level > level:
		level = cloud_level
		changed = true
	if p.legacy > legacy_score:
		legacy_score = p.legacy
		changed = true
	if (p.tutorial | tutorial) != tutorial:
		tutorial |= p.tutorial
		changed = true
	for lvl in p.stars:
		if int(p.stars[lvl]) > get_stars(lvl):
			level_stars[lvl] = int(p.stars[lvl])
			changed = true
	for lvl in p.best:
		if int(p.best[lvl]) > get_best(lvl):
			level_best[lvl] = int(p.best[lvl])
			changed = true
	changed = _merge_daily(p.daily) or changed
	if changed:
		_recount_total()
		save_game()
		progress_changed.emit()
	return changed


## Разбирает сохранение любой версии:
## { epoch: int, legacy: int, stars: {int: int}, best: {int: int}, tutorial: int, daily: Dictionary,
##   sent: {String: int} } — до v7 sent пуст.
func _parse_save(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 1))
	var legacy := 0
	var best := {}
	if version >= 3:
		legacy = maxi(0, int(data.get("legacy_score", 0)))
		best = _dict_from_save(data.get("level_best", {}), 1 << 30)
	else:
		# До v3 был только общий счёт: он целиком переходит в legacy_score.
		legacy = maxi(0, int(data.get("total_score", 0)))
	var skills := 0
	if version >= 5:
		skills = int(data.get("tutorial", 0)) & Tutorial.ALL
	elif int(data.get("level", 1)) > Tutorial.GUARD_LEVELS:
		skills = Tutorial.ALL  # до v5 навыков не было: кто прошёл обучающие уровни, тот обучен
	return {
		"epoch": maxi(0, int(data.get("epoch", 0))),
		"legacy": legacy,
		"stars": _dict_from_save(data.get("level_stars", {}), 3),
		"best": best,
		"tutorial": skills,
		"daily": _daily_from_save(data.get("daily", {})),
		"sent": _sent_from_save(data.get("leaderboard", {})),
	}


static func _daily_from_save(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {"date": "", "streak": 0, "best_streak": 0, "score": 0, "stars": 0}
	var d: Dictionary = raw
	var date := str(d.get("date", ""))
	if not date.is_empty() and not DailyChallenge.is_valid_date(date):
		date = ""
	return {
		"date": date,
		"streak": maxi(0, int(d.get("streak", 0))),
		"best_streak": maxi(0, int(d.get("best_streak", 0))),
		"score": maxi(0, int(d.get("score", 0))),
		"stars": clampi(int(d.get("stars", 0)), 0, 3),
	}


## {"score": 1200, "daily_streak": 4} из сохранения: ключи — непустые строки, значения 0…LEADERBOARD_MAX,
## нули не хранятся. Прочее (старые версии, мусор) — {}.
static func _sent_from_save(raw: Variant) -> Dictionary:
	var res := {}
	if raw is Dictionary:
		for k in raw:
			var v: Variant = raw[k]
			var board := str(k)
			if board.is_empty() or not (v is int or v is float):
				continue
			var value := clampi(int(v), 0, LEADERBOARD_MAX)
			if value > 0:
				res[board] = value
	return res


## Таблицы лидеров из облака: по каждой — большее. true — что-то выросло.
func _merge_sent(cloud: Dictionary) -> bool:
	var changed := false
	for board in cloud:
		if int(cloud[board]) > leaderboard_best(board):
			leaderboard_sent[board] = int(cloud[board])
			changed = true
	return changed


func _merge_daily(cloud: Dictionary) -> bool:
	if cloud.is_empty():
		return false
	var cloud_date := str(cloud.get("date", ""))
	if cloud_date.is_empty():
		return false
	var changed := false
	if daily_last_date.is_empty() or cloud_date > daily_last_date:
		daily_last_date = cloud_date
		daily_streak = int(cloud.get("streak", 0))
		daily_last_score = int(cloud.get("score", 0))
		daily_last_stars = int(cloud.get("stars", 0))
		changed = true
	elif cloud_date == daily_last_date:
		var streak := int(cloud.get("streak", 0))
		var score := int(cloud.get("score", 0))
		var stars := int(cloud.get("stars", 0))
		if streak > daily_streak:
			daily_streak = streak
			changed = true
		if score > daily_last_score:
			daily_last_score = score
			changed = true
		if stars > daily_last_stars:
			daily_last_stars = clampi(stars, 0, 3)
			changed = true
	var best := int(cloud.get("best_streak", 0))
	if best > daily_best_streak:
		daily_best_streak = best
		changed = true
	return changed


## {int: int} -> {"1": 3, ...}: в JSON (облако) ключи бывают только строками.
static func _dict_to_save(d: Dictionary) -> Dictionary:
	var res := {}
	for k in d:
		res[str(k)] = int(d[k])
	return res


static func _dict_from_save(raw: Variant, max_value: int) -> Dictionary:
	var res := {}
	if raw is Dictionary:
		for k in raw:
			var lvl := int(k)
			if lvl >= 1:
				res[lvl] = clampi(int(raw[k]), 0, max_value)
	return res


func save_game() -> void:
	var cfg := ConfigFile.new()
	var data := get_save_data()
	for key in data:
		cfg.set_value("progress", key, data[key])
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Не удалось сохранить прогресс: %s" % error_string(err))
	saved.emit(data)


func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if not cfg.has_section("progress"):
		return
	var data := {}
	for key in cfg.get_section_keys("progress"):
		data[key] = cfg.get_value("progress", key)
	_legacy_sound_on = bool(data.get("sound_on", true))
	apply_save_data(data)


## Сброс по просьбе игрока (кнопка в настройках): новое поколение, чтобы
## облачное сохранение не вернуло прогресс. Таблица лидеров не сбрасывается: leaderboard_sent остаётся,
## и YSDK не отправит в неё меньший счёт, пока новый не перерастёт прежний (16.3).
func wipe_progress() -> void:
	epoch += 1
	reset_progress()


## Обнуляет прогресс текущего поколения (самопроверка, wipe_progress). leaderboard_sent не трогает.
func reset_progress() -> void:
	level = 1
	legacy_score = 0
	level_stars = {}
	level_best = {}
	tutorial = 0
	daily_last_date = ""
	daily_streak = 0
	daily_best_streak = 0
	daily_last_score = 0
	daily_last_stars = 0
	_recount_total()
	save_game()
	progress_changed.emit()
