class_name LeaderboardData
extends RefCounted
## Строки экрана лидеров (этап 18.3, docs/STYLE.md, раздел 11.3) из ответа YSDK.request_leaderboard — без узлов
## и без SDK, чтобы selftest проверял всё на готовых словарях.
##
## Ответ: {"entries": [{"rank", "score", "name", "id"}], "userRank": n} или {"error": код}. Строка экрана:
## {"rank": int, "name": String, "score": int, "me": bool, "gap": bool} — gap = разрыв «…» между первыми местами
## и соседями игрока (ранги идут не подряд).

## Длиннее — обрезается с «…» (строка 600 px: место, имя, очки — имя не должно наезжать на очки).
const MAX_NAME := 16
## Больше строк карточка не вмещает (LeaderRows: 640 px по 44 px). YSDK отдаёт до 10 первых мест и по 3 соседа
## игрока сверху и снизу — до 18 строк с разрывом; лишнее срезает fit_ranks, строка игрока остаётся всегда.
const MAX_ROWS := 14
## Столько первых мест (медали) fit_ranks не трогает, пока есть что срезать у соседей.
const KEEP_TOP := 3
## Имя скрыто или пустое (игрок не дал доступ к имени).
const ANON_NAME := "Игрок"  # msgid
## Своя строка вне Яндекса (место «—», местный счёт).
const LOCAL_NAME := "Вы"  # msgid
## Код ошибки «SDK нет» (YSDK.LB_NO_SDK).
const ERROR_NO_SDK := "NO_SDK"


## Строки по возрастанию места, без повторов мест, не больше max_rows (с разрывами). my_id — YSDK.player_id:
## своя строка — по id; нет такого id (или my_id пуст) — по userRank (0 — игрока в таблице нет).
static func rows(data: Dictionary, my_id: String, max_rows: int = MAX_ROWS) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if data.has("error") or not data.get("entries") is Array:
		return out
	var list: Array = data["entries"]
	var user_rank := int(data.get("userRank", 0))
	# Старые ответы считали места с 0 — тогда сдвигаем все на 1 (место игрока тоже).
	var shift := 0
	for e in list:
		if e is Dictionary and int(e.get("rank", -1)) == 0:
			shift = 1
	var by_rank := {}
	var me_rank := 0
	for e in list:
		if not e is Dictionary:
			continue
		var r := int(e.get("rank", 0)) + shift
		if r < 1 or by_rank.has(r):
			continue
		var me: bool = not my_id.is_empty() and str(e.get("id", "")) == my_id and me_rank == 0
		if me:
			me_rank = r
		by_rank[r] = {"rank": r, "name": display_name(str(e.get("name", ""))),
				"score": maxi(0, int(e.get("score", 0))), "me": me, "gap": false}
	if me_rank == 0 and user_rank > 0 and by_rank.has(user_rank + shift):
		me_rank = user_rank + shift
		by_rank[me_rank]["me"] = true
	var ranks: Array[int] = []
	for r: int in by_rank.keys():
		ranks.append(r)
	ranks.sort()
	ranks = fit_ranks(ranks, me_rank, max_rows)
	var prev := 0
	for r in ranks:
		if prev > 0 and r > prev + 1:
			out.append({"rank": 0, "name": "", "score": 0, "me": false, "gap": true})
		out.append(by_rank[r])
		prev = r
	return out


## Сколько строк займут места ranks (по возрастанию): сами места и по разрыву «…» там, где места не подряд.
static func shown_count(ranks: Array[int]) -> int:
	var n := ranks.size()
	for i in range(1, ranks.size()):
		if ranks[i] > ranks[i - 1] + 1:
			n += 1
	return n


## Места, которые влезут в max_rows строк. me — место игрока (0 — его нет): оно остаётся всегда. Срезается по
## одному: дальний сосед снизу (пока снизу больше одного), дальний сосед сверху (пока их больше одного), хвост
## первых мест (до KEEP_TOP), последний сосед снизу, последний сверху, затем любое место, кроме игрока, с конца.
## Соседи сверху — места игрока выше, но не в непрерывном начале таблицы (1, 2, 3 …).
static func fit_ranks(ranks: Array[int], me: int, max_rows: int) -> Array[int]:
	var keep: Array[int] = ranks.duplicate()
	while keep.size() > 1 and shown_count(keep) > maxi(1, max_rows):
		keep.remove_at(_trim_index(keep, me))
	return keep


static func _trim_index(keep: Array[int], me: int) -> int:
	var at: int = keep.find(me) if me > 0 else -1
	if at < 0:
		return keep.size() - 1
	var head := 1  # непрерывное начало: keep[0], keep[0] + 1, …
	while head < keep.size() and keep[head] == keep[head - 1] + 1:
		head += 1
	var below := keep.size() - 1 - at
	var above := maxi(0, at - head)  # соседи сверху вне начала таблицы
	if below > 1:
		return keep.size() - 1
	if above > 1:
		return head
	if at >= head and head > KEEP_TOP:
		return head - 1
	if below > 0:
		return keep.size() - 1
	if above > 0:
		return head
	return keep.size() - 1 if at != keep.size() - 1 else keep.size() - 2


## Имя для строки: пустое — «Игрок» (переводится при показе), длинное — MAX_NAME символов с «…».
static func display_name(raw: String) -> String:
	var name := raw.strip_edges().replace("\n", " ")
	if name.is_empty():
		return ANON_NAME
	if name.length() > MAX_NAME:
		return name.left(MAX_NAME - 1).strip_edges() + "…"
	return name


## Своя строка вне Яндекса или без сети: место «—» (rank 0), местный счёт.
static func local_row(score: int) -> Dictionary:
	return {"rank": 0, "name": LOCAL_NAME, "score": maxi(0, score), "me": true, "gap": false}


## Место игрока среди строк (0 — его строки нет).
static func my_rank(list: Array[Dictionary]) -> int:
	for row in list:
		if bool(row["me"]):
			return int(row["rank"])
	return 0


## Текст под карточкой (русский msgid — переводит экран через tr; "" — ничего не писать).
## daily — вкладка серии дней (подсказка, как попасть в таблицу, своя).
static func status_text(data: Dictionary, authorized: bool, list: Array[Dictionary], daily: bool) -> String:
	if data.has("error"):
		if str(data["error"]) == ERROR_NO_SDK:
			return "Таблица лидеров — в Яндекс Играх"  # msgid
		return "Не удалось загрузить. Проверьте интернет"  # msgid
	if not authorized:
		return "Войдите, чтобы попасть в таблицу"  # msgid
	if my_rank(list) > 0:
		return ""
	if daily:
		return "Пройдите задачу дня, чтобы попасть в таблицу"  # msgid
	return "Пройдите уровень, чтобы попасть в таблицу"  # msgid
