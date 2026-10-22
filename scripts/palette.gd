@tool
class_name Palette
extends RefCounted
## Цвета блоков по площади (палитра B, docs/STYLE.md, раздел 2) и производные оттенки:
## обводка и тень цифр, тени. Цвет числа в гнезде совпадает с цветом блока.

const BLOCK_COLORS: Array[Color] = [
	Color(0.706, 0.765, 1.000),  # 1 запас #B4C3FF
	Color(1.000, 0.294, 0.243),  # 2 красный #FF4B3E
	Color(1.000, 0.604, 0.180),  # 3 оранжевый #FF9A2E
	Color(1.000, 0.824, 0.247),  # 4 жёлтый #FFD23F
	Color(0.184, 0.839, 0.482),  # 5 зелёный #2FD67B
	Color(0.180, 0.784, 0.969),  # 6 голубой #2EC8F7
	Color(0.898, 0.322, 0.839),  # 7 запас #E552D6
	Color(0.247, 0.482, 1.000),  # 8 синий #3F7BFF
	Color(0.078, 0.804, 0.722),  # 9 бирюзовый #14CDB8
	Color(0.651, 0.886, 0.180),  # 10 лайм #A6E22E
	Color(0.122, 0.698, 0.420),  # 11 запас #1FB26B
	Color(1.000, 0.373, 0.659),  # 12 розовый #FF5FA8
]

## Призрак места, куда блок не встаёт (Board.show_preview): красный #FF4B3E. В STYLE не задан —
## предложение 13.1c, проверить на экране.
const GHOST_BAD := Color(1.0, 0.294, 0.243)

## Тень лежащего блока (STYLE, раздел 7): SHADE #34168F, 34 %.
const SHADE := Color(0.204, 0.086, 0.561, 0.34)
## Тень поднятого (несомого) блока: #26107A, 42 %.
const SHADE_LIFTED := Color(0.149, 0.063, 0.478, 0.42)

## Текст интерфейса (STYLE, разделы 2 и 3): INK #2E1678 — обводка заголовков и счёта,
## DEEP #1E0B5C — тени текста (непрозрачность у каждой подписи своя), SCORE #FFE45C — счёт в шапке.
const INK := Color(0.180, 0.086, 0.471)
const DEEP := Color(0.118, 0.043, 0.361)
const SCORE := Color(1.0, 0.894, 0.361)

## Механики 19.3 (STYLE 11.5, предложение — проверить на экране). Число «?» (площадь UNKNOWN_AREA =
## ShikakuSolver.ANY): гнездо приглушённого фиолетового #8B7AD5 — ни с одним цветом блока не путается.
const UNKNOWN_AREA := -1
const UNKNOWN := Color(0.545, 0.478, 0.835)
## Закреплённый блок: «камень» #9890BC — без цвета площади, его не двигают.
const PINNED := Color(0.596, 0.565, 0.737)


static func color_for(area: int) -> Color:
	if area == UNKNOWN_AREA:
		return UNKNOWN
	return BLOCK_COLORS[clampi(area, 1, BLOCK_COLORS.size()) - 1]


## Обводка числа на блоке: темнее(цвет, 0,45).
static func block_digit_outline(area: int) -> Color:
	return color_for(area).darkened(0.45)


## Тень числа на блоке: темнее(цвет, 0,6), 47 %.
static func block_digit_shadow(area: int) -> Color:
	var c := color_for(area).darkened(0.6)
	c.a = 0.47
	return c


## Обводка числа в гнезде: темнее(цвет, 0,42).
static func nest_digit_outline(area: int) -> Color:
	return color_for(area).darkened(0.42)


## Тень числа в гнезде: темнее(цвет, 0,5), 35 %.
static func nest_digit_shadow(area: int) -> Color:
	var c := color_for(area).darkened(0.5)
	c.a = 0.35
	return c
