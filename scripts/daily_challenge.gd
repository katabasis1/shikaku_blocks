class_name DailyChallenge
extends RefCounted
## Детерминированная ежедневная головоломка (этап 18.1).
## Дата берётся в UTC, поэтому один календарный день имеет один уровень у всех игроков.
## Уровни 1–6 не используются, чтобы ежедневная задача не повторяла обучение.

const FIRST_LEVEL := 7
const LAST_LEVEL := 1000
const SALT := 0x6D5A1F27


## Ключ текущего календарного дня в UTC, формат YYYY-MM-DD.
static func current_date_key() -> String:
	return Time.get_date_string_from_system(true)


## Уровень дня. Один и тот же ключ всегда даёт один и тот же номер.
static func level_for_date(date_key: String) -> int:
	var span := LAST_LEVEL - FIRST_LEVEL + 1
	var mixed := _mix32(day_number(date_key) * 1103515245 + SALT)
	return FIRST_LEVEL + posmod(mixed, span)


static func current_level() -> int:
	return level_for_date(current_date_key())


## Проверка даты нужна для облачного сохранения: повреждённый ключ не должен ломать серию.
static func is_valid_date(date_key: String) -> bool:
	if date_key.length() != 10 or date_key[4] != "-" or date_key[7] != "-":
		return false
	for i in [0, 1, 2, 3, 5, 6, 8, 9]:
		var c := date_key.unicode_at(i)
		if c < 48 or c > 57:
			return false
	var y := int(date_key.substr(0, 4))
	var m := int(date_key.substr(5, 2))
	var d := int(date_key.substr(8, 2))
	if y < 2000 or y > 9999 or m < 1 or m > 12 or d < 1:
		return false
	var days := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if m == 2 and _leap(y):
		days[1] = 29
	return d <= days[m - 1]


## Номер дня по календарю Григорианской системы. Разность соседних дат надёжна без часовых поясов.
static func day_number(date_key: String) -> int:
	if not is_valid_date(date_key):
		return 0
	var y := int(date_key.substr(0, 4))
	var m := int(date_key.substr(5, 2))
	var d := int(date_key.substr(8, 2))
	y -= int(m <= 2)
	var era := floori(float(y) / 400.0)
	var yoe := y - era * 400
	var mp := m + (-3 if m > 2 else 9)
	var doy := (153 * mp + 2) / 5 + d - 1
	var doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe


## Следующая серия после завершения задачи current_date.
static func next_streak(last_date: String, current_date: String, old_streak: int) -> int:
	if not is_valid_date(current_date):
		return maxi(1, old_streak)
	if last_date == current_date:
		return maxi(1, old_streak)
	if is_valid_date(last_date) and day_number(current_date) == day_number(last_date) + 1:
		return maxi(1, old_streak + 1)
	return 1


static func _leap(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


## Маленький стабильный mixer вместо hash(), алгоритм которого не является частью формата сохранения.
static func _mix32(value: int) -> int:
	var x: int = value & 0xffffffff
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xffffffff
	x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xffffffff
	x = (x ^ (x >> 16)) & 0xffffffff
	return x
