class_name Chapters
extends RefCounted
## Главы (этап 19.5, вариант А — решение пользователя 09.10, сессия 93; PLAN, этап 19): участки основного пути,
## те же номера уровней, та же карта и тот же счёт. У главы — номер, название, тема фона (цвета
## shaders/background.gdshader; цвета блоков не меняются — цвет = площадь) и новая идея, которую показывает
## карточка начала главы. Вид — docs/STYLE.md 11.6, кадр G19_5_chapters.png (tools/chapters_preview.py).
##
## Главы 1–10 — заготовленные уровни 1..LevelPack.count() (FIRST). Дальше LevelPack повторяет уровни
## LOOP_FROM..count() отражёнными; повтор режется на главы по LOOP_SPAN уровней с номерами 11, 12, … — тема,
## название и идея берутся у главы исходного уровня, карточка новой идеи у повтора не показывается.
## Python-копия: tools/chapters_preview.py (index_of, number_of).

## Первый уровень каждой главы (по возрастанию; первая — с 1). С LevelPack LOOP_FROM главы идут ровно по
## LOOP_SPAN уровней (selftest), иначе главы повтора не совпали бы с главами исходных уровней.
const FIRST: Array[int] = [1, 61, 101, 151, 201, 251, 301, 351, 401, 451]
const LOOP_SPAN := 50

## Названия глав (переводятся: tr; правка 12.10 — одна тема «вечер → ночь → космос → рассвет»). Карточка —
## «ГЛАВА 4 · ЛУНА».
const NAMES: Array[String] = [
	"СУМЕРКИ", "ЗВЁЗДЫ", "ПОЛНОЧЬ", "ЛУНА", "КОМЕТА",  # msgid
	"СИЯНИЕ", "ТУМАННОСТЬ", "ГАЛАКТИКА", "КОСМОС", "РАССВЕТ",  # msgid
]
## Новая идея главы — строка под названием на карточке начала главы ("" — без строки: в главе 1 правило учит
## обучение уровней 1–3). Главы 4–7 — по механике (MECHANICS), глава 8 — все четыре вперемешку.
const IDEAS: Array[String] = [
	"",
	"Новое: длинные блоки 5 и 10",  # msgid
	"Новое: большой блок 12",  # msgid
	"Новое: препятствия",  # msgid
	"Новое: закреплённый блок",  # msgid
	"Новое: цветные клетки",  # msgid
	"Новое: число «?»",  # msgid
	"Все новинки вперемешку",  # msgid
	"", "",
]
## Механика, которую вводит глава (19.5e, решение пользователя 09.10: все четыре, по очереди): главы 4–7 — по
## одной (LabLevels.rule — её правило), в 8–10 — все вперемешку. Какой уровень с какой механикой — в самих
## уровнях (LevelPack.mechanic_of; tools/chapter_levels.py: mechanic). Python-копия порядка — MECH_ORDER там же.
const MECHANICS: Array[String] = ["", "", "", "holes", "pinned", "tints", "unknown", "", "", ""]
## Первые RULE_LEVELS уровней такой главы — вводные (её механика на простых полях, tools/chapter_levels.py:
## INTRO): над полем правило механики, как в «Лаборатории».
const RULE_LEVELS := 5
## Шаблон заголовка карточки и плашки на карте: номер, название.
const HEAD := "ГЛАВА %d · %s"  # msgid

## Темы фона: верх, середина, низ градиента и виньетка — униформы top_color, mid_color, bottom_color,
## vignette_color шейдера фона (альфа виньетки — как в шейдере, 0,47); цвета вихря (19.7, 10.10): deep — между
## витками, cool — тон витка вверху, warm — внизу (deep_color, cool_color, warm_color). Глава 1 — цвета шейдера по
## умолчанию (раздел 9 STYLE). Правка 12.10 (пользователь: «главы похожи по цветам»): у каждой главы своё семейство
## тонов под название — сумерки фиолетовые, звёзды сапфировые, полночь — тёмный индиго, луна — серебро, комета —
## ледяная бирюза, сияние — зелёное, туманность — пурпур, галактика — слива → янтарь, космос — почти чёрный, рассвет —
## голубой → розовый → персик; виньетка — тем же сдвигом от mid, что у главы 1 (tools/chapters_model.py). Цвета вихря глав 2–10 выведены из их градиента тем же сдвигом в Oklch, что у главы 1
## (deep — от mid, cool — от top, warm — от bottom; tools/chapters_model.py, swirl_colors).
const THEMES: Array[Dictionary] = [
	{"top": Color("#4A36E0"), "mid": Color("#6A42E4"), "bottom": Color("#9A4CDB"), "vignette": Color("#140646"),
		"deep": Color("#34168F"), "cool": Color("#808CFF"), "warm": Color("#DA5CF0")},
	{"top": Color("#0555B7"), "mid": Color("#016CC3"), "bottom": Color("#0A8FD1"), "vignette": Color("#00192F"),
		"deep": Color("#003B66"), "cool": Color("#6597DE"), "warm": Color("#69AAFE")},
	{"top": Color("#162671"), "mid": Color("#24338D"), "bottom": Color("#4843AA"), "vignette": Color("#000017"),
		"deep": Color("#020445"), "cool": Color("#50659C"), "warm": Color("#7F57CE")},
	{"top": Color("#40546E"), "mid": Color("#516C88"), "bottom": Color("#7291A4"), "vignette": Color("#0C1821"),
		"deep": Color("#24394C"), "cool": Color("#7F8FA2"), "warm": Color("#97B1CD")},
	{"top": Color("#025E78"), "mid": Color("#027D8C"), "bottom": Color("#31A5A5"), "vignette": Color("#002023"),
		"deep": Color("#00454B"), "cool": Color("#6798AA"), "warm": Color("#4DC7DB")},
	{"top": Color("#025350"), "mid": Color("#007C59"), "bottom": Color("#36A558"), "vignette": Color("#001C0E"),
		"deep": Color("#01422A"), "cool": Color("#5F8A87"), "warm": Color("#02CC96")},
	{"top": Color("#7B1B94"), "mid": Color("#AB2097"), "bottom": Color("#D8508F"), "vignette": Color("#2B0029"),
		"deep": Color("#5E005A"), "cool": Color("#AD71C2"), "warm": Color("#FE7A93")},
	{"top": Color("#601A5D"), "mid": Color("#A31B45"), "bottom": Color("#D26C28"), "vignette": Color("#1E0008"),
		"deep": Color("#540022"), "cool": Color("#936190"), "warm": Color("#F39409")},
	{"top": Color("#16142E"), "mid": Color("#241C43"), "bottom": Color("#3D285C"), "vignette": Color("#02010B"),
		"deep": Color("#02000C"), "cool": Color("#48495E"), "warm": Color("#673F77")},
	{"top": Color("#3D73B6"), "mid": Color("#BB76B5"), "bottom": Color("#F0AD7F"), "vignette": Color("#472D48"),
		"deep": Color("#774979"), "cool": Color("#8AB2E3"), "warm": Color("#FFDAB0")},
]
## Непрозрачность виньетки (как vignette_color в shaders/background.gdshader).
const VIGNETTE_ALPHA := 0.470588


static func count() -> int:
	return FIRST.size()


## Индекс главы в таблицах (0..count()-1) для уровня level (с 1). Уровни повтора — по исходному уровню.
static func index_of(level: int) -> int:
	var n := _base_level(level)
	var i := FIRST.size() - 1
	while i > 0 and n < FIRST[i]:
		i -= 1
	return i


## Номер главы на экране (с 1): 1..count() у заготовленных уровней, дальше 11, 12, … по LOOP_SPAN уровней.
static func number_of(level: int) -> int:
	var total := LevelPack.count()
	if level <= total:
		return index_of(level) + 1
	@warning_ignore("integer_division")
	return FIRST.size() + 1 + (level - total - 1) / LOOP_SPAN


## Первый уровень главы, в которой стоит level.
static func first_level(level: int) -> int:
	var total := LevelPack.count()
	if level <= total:
		return FIRST[index_of(maxi(level, 1))]
	@warning_ignore("integer_division")
	return total + 1 + (level - total - 1) / LOOP_SPAN * LOOP_SPAN


## level — первый уровень своей главы (на нём показывается карточка главы; на карте перед ним — плашка).
static func is_start(level: int) -> bool:
	return level >= 1 and first_level(level) == level


## Сколько глав начинается на уровнях 2..level (перед каждой на карте — зазор с плашкой, MapPath.rise).
static func starts_upto(level: int) -> int:
	var total := LevelPack.count()
	var k := 0
	for f in FIRST:
		if f >= 2 and f <= mini(level, total):
			k += 1
	if level > total:
		@warning_ignore("integer_division")
		k += 1 + (level - total - 1) / LOOP_SPAN
	return k


## Название главы уровня level, переведённое (tr — у вызывающего узла: tr недоступен в static).
static func name_of(level: int) -> String:
	return NAMES[index_of(level)]


## Новая идея главы ("" — нет; у глав повтора тоже нет: идея уже знакома).
static func idea_of(level: int) -> String:
	if level > LevelPack.count():
		return ""
	return IDEAS[index_of(level)]


## Механика, правило которой показать над полем уровня level с данными data ("" — без правила):
## вводные уровни главы, которая её вводит (RULE_LEVELS), и ежедневная задача (daily) с механикой, вводные
## уровни которой игрок ещё не прошёл (reached — GameState.level). Повтор после count() — без правила.
static func rule_of(level: int, data: Dictionary, daily: bool, reached: int) -> String:
	var mech := LevelPack.mechanic_of(data)
	if mech.is_empty():
		return ""
	if daily:
		return mech if reached < intro_first(mech) + RULE_LEVELS else ""
	if level > LevelPack.count() or MECHANICS[index_of(level)] != mech:
		return ""
	return mech if level - first_level(level) < RULE_LEVELS else ""


## Первый уровень главы, которая вводит механику mech (0 — такой главы нет).
static func intro_first(mech: String) -> int:
	var i := MECHANICS.find(mech)
	return FIRST[i] if i >= 0 and not mech.is_empty() else 0


## Тема фона главы уровня level: {"top", "mid", "bottom", "vignette", "deep", "cool", "warm"} (виньетка — с
## альфой шейдера).
static func theme_of(level: int) -> Dictionary:
	var t: Dictionary = THEMES[index_of(level)].duplicate()
	var v: Color = t["vignette"]
	v.a = VIGNETTE_ALPHA
	t["vignette"] = v
	return t


## Уровень повтора → исходный заготовленный уровень (как LevelPack.get_level); заготовленные — как есть.
static func _base_level(level: int) -> int:
	var total := LevelPack.count()
	if level <= total:
		return maxi(level, 1)
	var first: int = clampi(LevelPack.DATA.LOOP_FROM, 1, total)
	var span := total - first + 1
	return first + (level - total - 1) % span
