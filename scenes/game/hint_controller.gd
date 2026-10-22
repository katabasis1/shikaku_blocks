class_name HintController
extends Node
## Подсказка: FREE_PER_LEVEL бесплатно на уровень, дальше — за rewarded-рекламу
## (только в Яндекс Играх). Ставит блок на место из решения от текущей расстановки;
## в тупике откатывает неверные ходы до последнего решаемого состояния.

## Бесплатных подсказок на уровень по умолчанию. YSDK может заменить число remote flag-ом.
const FREE_PER_LEVEL := 1

## Сколько подсказок взято на этом уровне (каждая — минус 2 к «штрафу» звёзд).
var used: int = 0
## Ждём ответа рекламы за подсказку.
var ad_pending: bool = false
## Текущая подсказка дана за рекламу (give(true)) — для цели hint в Метрике.
var _paid: bool = false

var _game: Game


func setup(game: Game) -> void:
	_game = game


## Новый уровень.
func reset() -> void:
	used = 0
	ad_pending = false


## Сколько бесплатных подсказок осталось на уровне (счётчик на кнопке, 13.2b).
func free_left() -> int:
	return maxi(0, YSDK.free_hints_per_level() - used)


## Следующая подсказка — только после рекламы (значок на кнопке).
func needs_ad() -> bool:
	return YSDK.is_rewarded_available() and used >= YSDK.free_hints_per_level()


## Нажатие «Подсказки» сейчас сработает: уровень идёт, не пауза, блок не в руке, реклама не ждёт ответа.
## Эффекты ввод не держат (14.8c).
func can_request() -> bool:
	var g := _game
	return not (g.finished or g.paused or g.drag.is_busy() or ad_pending)


## Кнопка подсказки или клавиша H.
func request() -> void:
	if not can_request():
		return
	var g := _game
	if needs_ad():
		ad_pending = true
		YSDK.show_rewarded(_on_ad_finished.bind(g.session))
		return
	give()


## Подсказка без проверки рекламы: поставить верный блок или откатить тупик. paid — после рекламы за награду
## (Метрика, 16.1: цель hint — "ad" или "free").
func give(paid := false) -> void:
	var g := _game
	if g.finished or g.drag.is_busy():
		return
	_paid = paid
	var s := g.solve(g.placed_rects(), g.remaining_pieces())
	if s.status == ShikakuSolver.UNSOLVABLE:
		_rollback()
		return
	if s.status == ShikakuSolver.SOLVED and _place(s.solution):
		return
	# Решатель не уложился в лимит (на уровнях игры такого не бывает) — эталонное решение.
	if _place(g.level_data.solution):
		return
	Audio.play(Audio.ERROR)
	g.toast.show_text(tr("Сначала отмени ошибочный ход"), 2.5)
	Fx.hop(g.undo_button)


func _on_ad_finished(rewarded: bool, session: int) -> void:
	if session != _game.session:
		return  # уровень уже перезапущен или сменился
	ad_pending = false
	if _game.finished:
		return
	if rewarded:
		give(true)
	else:
		_game.toast.show_text(tr("Подсказка откроется после просмотра рекламы"), 2.0)


## Ставит блок из лотка на его место в решении rects. false — подходящего нет.
## 14.6g (PLAN 4.4), переделано 12.10: блок сразу взлетает из гнезда и летит на место за hint_float_time (0,3 с).
## Искра (HintSpark) летит вместе с ним — по прямой из середины блока в середину места, тем же ходом, под блоком:
## видно только её золотой след, — и вспыхивает в миг касания. Было: искра от кнопки 0,42 с, блок ждал её и только
## потом вплывал 0,36 с — долго. Ход засчитан сразу — ввод не ждёт. «Меньше движения» и «без эффектов» — без искры.
func _place(rects: Array) -> bool:
	var g := _game
	var m := g.tray.find_move(rects, g.board)
	if m.is_empty():
		return false
	var i: int = m.slot
	var r: Rect2i = m.rect
	var b: Block = g.tray.blocks[i]
	_use()
	Audio.play(Audio.HINT, 0.0)  # перелив (15.1) — пока блок летит, «искры» звука — в миг касания (hint_float_time)
	if r.size != b.cells:
		b.rotate_cells()
	# Середина блока в гнезде (уже повёрнутого) — отсюда вместе с ним летит искра.
	var from := b.get_global_transform() * (Vector2(b.cells) * Block.CELL * 0.5)
	var ft := Block.cfg().hint_float_time
	g.commit_place(b, i, r, ft)
	if ft > 0.0 and not GameState.reduce_motion:
		HintSpark.fly(g.fx_layer, from, g.board.cell_center_global(r), ft, 0.0, g.juice, g.board.holds.bind(b, r))
	return true


## Тупик: откатываем ходы до последнего состояния, из которого поле ещё решается.
func _rollback() -> void:
	var g := _game
	var pieces := g.remaining_pieces()
	var k := 0
	while k < g.moves.size():
		k += 1
		var m: Dictionary = g.moves[g.moves.size() - k]
		pieces.append((m.block as Block).cells)
		if g.solve(g.placed_rects(k), pieces).status != ShikakuSolver.UNSOLVABLE:
			break
	if k == 0:
		return
	_use()
	for _j in k:
		g.undo_last()
	g.dead_end = false
	Audio.play(Audio.UNDO)
	g.toast.show_text(tr("Подсказка: убраны неверные блоки (%d)") % k, 2.5)
	g.update_hud()


func _use() -> void:
	used += 1
	Analytics.run_hint(_paid)
	GameState.hint_used.emit(_game.level)
