class_name LabLevels
extends RefCounted
## «Лаборатория» (этап 19.3): по 10 уровней каждой механики-кандидата из модели 19.1 — играем и выбираем, что
## пойдёт в главы (19.4). Уровни — scripts/lab_levels_data.gd (его пишет tools/make_lab.py), формат строки и
## механики — LevelPack.decode, правила — Board и ShikakuSolver.rules_of. Вход — кнопка в меню только в
## отладочной сборке (OS.is_debug_build), экран — scenes/lab/lab.tscn; прогресс не сохраняется.

const DATA := preload("res://scripts/lab_levels_data.gd")
const SCENE := "res://scenes/lab/lab.tscn"
## Название — кнопка в меню, заголовок экрана, шапка игры (отладочный экран — без перевода).
const NAME := "ЛАБОРАТОРИЯ"

## Названия механик на экране «Лаборатории» (отладочный экран — без перевода).
const TITLES := {
	"unknown": "Число «?»",
	"holes": "Препятствия",
	"tints": "Цветные клетки",
	"pinned": "Закреплённый блок",
}
## Короткие названия для шапки игры: «ЗАКРЕПЛЁННЫЙ БЛОК · 10/10» и «ЦВЕТНЫЕ КЛЕТКИ · 10/10» в альбоме ужимались до
## TITLE_MIN_SIZE и вылезали за шапку (модель шапки, 19.3c: ужатие до 20 и 24 при пределе 24).
const HEADS := {
	"unknown": "ЧИСЛО «?»",
	"holes": "ПРЕПЯТСТВИЯ",
	"tints": "ЦВЕТНЫЕ",
	"pinned": "ЗАКРЕПЛЁН",
}

## Запрос на игру из экрана «Лаборатории» (как GameState.requested_level): Game читает и сбрасывает.
static var requested_mechanic := ""
static var requested_index := 0
## Пройденные в этом запуске уровни: "механика:номер" → звёзды (только для отметок на экране).
static var done := {}


static func mechanics() -> Array[String]:
	return DATA.ORDER


static func count(mechanic: String) -> int:
	var list: Array = DATA.LEVELS.get(mechanic, [])
	return list.size()


## Уровень index (1..count) механики mechanic: словарь LevelPack.decode и mechanic, lab_index. {} — нет такого.
static func get_level(mechanic: String, index: int) -> Dictionary:
	if index < 1 or index > count(mechanic):
		return {}
	var d := LevelPack.decode(DATA.LEVELS[mechanic][index - 1])
	if d.is_empty():
		return {}
	d["mechanic"] = mechanic
	d["lab_index"] = index
	return d


static func title(mechanic: String) -> String:
	return TITLES.get(mechanic, mechanic)


## Заголовок в шапке игры: короткое название механики (HEADS) и номер уровня («ЧИСЛО «?» · 3/10»; без перевода).
static func header(mechanic: String, index: int) -> String:
	var head: String = HEADS.get(mechanic, title(mechanic).to_upper())
	return "%s · %d/%d" % [head, index, count(mechanic)]


## Правило механики — msgid (переводит владелец: tr или Label): подпись над полем (TutorialCoach.rule_text) и
## строка в карточке экрана «Лаборатории». "" — не механика.
static func rule(mechanic: String) -> String:
	match mechanic:
		"holes":
			return "Белые плитки — препятствия: на них блок не встанет"  # msgid
		"pinned":
			return "Серый блок закреплён: строй вокруг него"  # msgid
		"unknown":
			return "«?» — размер неизвестен: подойдёт любой блок, но решение одно"  # msgid
		"tints":
			return "Цветную клетку накрывает только блок того же цвета"  # msgid
	return ""


## Уровень после (mechanic, index): следующий той же механики, после последнего — первый следующей механики;
## после последнего уровня последней механики — {} (назад в «Лабораторию»). {"mechanic", "index"}.
static func next_after(mechanic: String, index: int) -> Dictionary:
	if index < count(mechanic):
		return {"mechanic": mechanic, "index": index + 1}
	var order := mechanics()
	var k := order.find(mechanic)
	if k >= 0 and k + 1 < order.size():
		return {"mechanic": order[k + 1], "index": 1}
	return {}


## Первый уровень без отметки (порядок mechanics(), внутри — по номеру); всё пройдено — первый уровень первой
## механики. {"mechanic", "index"}; {} — уровней нет.
static func first_open() -> Dictionary:
	var order := mechanics()
	for m in order:
		for i in range(1, count(m) + 1):
			if stars_of(m, i) == 0:
				return {"mechanic": m, "index": i}
	for m in order:
		if count(m) > 0:
			return {"mechanic": m, "index": 1}
	return {}


## Сколько уровней механики пройдено в этом запуске.
static func done_count(mechanic: String) -> int:
	var n := 0
	for i in range(1, count(mechanic) + 1):
		if stars_of(mechanic, i) > 0:
			n += 1
	return n


static func mark_done(mechanic: String, index: int, stars: int) -> void:
	var key := "%s:%d" % [mechanic, index]
	done[key] = maxi(stars, int(done.get(key, 0)))


static func stars_of(mechanic: String, index: int) -> int:
	return int(done.get("%s:%d" % [mechanic, index], 0))
