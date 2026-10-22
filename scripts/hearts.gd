class_name Hearts
extends RefCounted
## Сердца попытки уровня (20.1a, PLAN 20.1) — чистая логика без узлов: Game держит один экземпляр, HeartsBar
## рисует, самопроверка и tools/hearts_model.py сверяют правила.
## Ошибка — только ход, после которого поле уже не заполнить (решатель: UNSOLVABLE): сгорает сердце, блок
## возвращается в лоток. Ход мимо, не на своё число, внахлёст — просто не встаёт, сердце цело. Решатель не уложился
## в лимит — сердце тоже цело.
## Сердца кончились — поле стоит (окно «Продолжить / Заново» — 20.1b): возрождение даёт одно сердце, поле как есть.
## Без предела (max_hearts 0: уровни обучения со страховкой, «Лаборатория», флаг hearts = 0) — сердец не видно,
## ошибки считаются.
## Звёзды: 3 − ошибки − подсказки, не ниже 1; после возрождения — 1. При 3 сердцах «3 − ошибки» — это сколько
## сердец осталось.

const STARS_MAX := 3

## Сердец на попытку; 0 — без предела.
var max_hearts := 0
## Сколько осталось (без предела — всегда 0).
var left := 0
## Ошибок за попытку (тупиковых ходов).
var mistakes := 0
## Возрождений за попытку (и за рекламу, и бесплатных).
var revives := 0
## Бесплатное продолжение (реклама не показалась, флаг revive_free_on_fail) за попытку уже было.
var free_used := false


## Сколько сердец на попытку: hearts — флаг (0 — без предела), from_level — с какого уровня основного пути (раньше —
## обучение со страховкой); задача дня — с сердцами всегда, «Лаборатория» — без них.
static func max_for(level: int, is_daily: bool, is_lab: bool, hearts: int, from_level: int) -> int:
	if is_lab or hearts <= 0:
		return 0
	if not is_daily and level < from_level:
		return 0
	return hearts


## Новая попытка: n_max сердец (0 — без предела), ошибок и возрождений нет.
func reset(n_max: int) -> void:
	max_hearts = maxi(n_max, 0)
	left = max_hearts
	mistakes = 0
	revives = 0
	free_used = false


## Сердца на этой попытке есть (видны и могут кончиться).
func is_limited() -> bool:
	return max_hearts > 0


## Ошибка: сердце сгорает (без предела — только счёт ошибок). Было последнее — is_out().
func lose() -> void:
	mistakes += 1
	if max_hearts > 0 and left > 0:
		left -= 1


## Сердца кончились: ходить нельзя, пока не возродится или не начнёт заново.
func is_out() -> bool:
	return max_hearts > 0 and left <= 0


## Можно возродиться: сердца кончились, а возрождений меньше revive_max (флаг).
func can_revive(revive_max: int) -> bool:
	return is_out() and revives < revive_max


## Реклама за возрождение не показалась: продолжить бесплатно можно, если флаг allow и бесплатного ещё не было.
func can_continue_free(allow: bool) -> bool:
	return allow and not free_used


## Возрождение: +1 сердце, поле как есть. free — бесплатное продолжение (реклама не показалась).
func revive(free := false) -> void:
	revives += 1
	if free:
		free_used = true
	left += 1


## Звёзды за победу: после возрождения — 1, иначе 3 − ошибки − подсказки (hints_used), не ниже 1.
func stars(hints_used: int) -> int:
	if revives > 0:
		return 1
	return clampi(STARS_MAX - mistakes - maxi(hints_used, 0), 1, STARS_MAX)
