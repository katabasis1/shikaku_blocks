class_name QualityGovernor
extends RefCounted
## Решатель автоснижения качества (14.7b; PLAN 4.5). Только логика: кормится длительностью кадров — push(dt) —
## и отвечает новым уровнем (2 «высокое», 1 «среднее», 0 «низкое») или -1 — «ничего не менять». Узлов, часов
## и настроек не трогает — selftest кормит его синтетическими кадрами. Та же логика и те же сценарии —
## в tools/quality_model.py (менять вместе). Числа — группа «Качество» в JuiceConfig.
##
## - кадры дольше quality_hitch (сборка мусора, вкладка в фоне, загрузка) не считаются;
## - первые quality_warmup секунд после reset() (новая сцена) не считаются — компиляция шейдеров;
## - кадры копятся в окно quality_window секунд; к/с окна = кадров / время;
## - окно ниже quality_fps quality_bad_windows раз подряд — уровень вниз; так начинается «спуск»,
##   запоминаются его исходные уровень и к/с;
## - после любой смены quality_settle секунд не считаем, затем одно окно проверки:
##   * после шага вниз стало ≥ quality_fps — спуск удался;
##   * всё ещё мало и есть куда — спуск продолжается (следующее плохое окно — ещё шаг): отдельный шаг может
##     не дать ничего, браузер подгоняет кадр под vsync — 22 мс работы дают те же 30 к/с, что и 28 мс;
##   * дошли до низкого, а к/с не выросли на quality_gain от исходных — узкое место не в эффектах (браузер сам
##     держит 30 к/с — энергосбережение iOS, — или занят процессор): откат к исходному уровню и «замок»
##     до конца сессии;
##   * проба вверх просела ниже quality_fps — назад вниз;
## - вверх — одна проба за сессию: на сниженном уровне quality_probe_after секунд подряд окна ≥ quality_fps_good.

const LEVEL_MAX := 2

enum Phase { WARM, MEASURE, SETTLE, VERIFY, LOCKED }

var cfg: JuiceConfig
var level := LEVEL_MAX
var phase := Phase.WARM
## Замок: весь спуск ничего не дал — до конца сессии уровень не трогаем.
var locked := false
## Проба вверх уже была.
var probed := false
## к/с последнего законченного окна (для счётчика и selftest).
var last_fps := 0.0

var _wait := 0.0
var _w_time := 0.0
var _w_frames := 0
var _bad := 0
var _good_time := 0.0
var _dir := 0
var _chain := false
var _chain_level := 0
var _chain_fps := 0.0


func _init(config: JuiceConfig, start_level := LEVEL_MAX) -> void:
	cfg = config
	level = clampi(start_level, 0, LEVEL_MAX)


## Новая сцена (или вернулись из фона): разогрев заново, окно — с нуля. Замок остаётся.
func reset() -> void:
	phase = Phase.LOCKED if locked else Phase.WARM
	_wait = 0.0
	_clear_window()
	_bad = 0
	_good_time = 0.0


## Кадр не в счёт (шторка, окно не в фокусе, пауза): незаконченное окно выбросить, чтобы оно не перешагнуло дыру.
func skip() -> void:
	_clear_window()


## Кадр длительностью dt, с. Возвращает новый уровень или -1.
func push(dt: float) -> int:
	if phase == Phase.LOCKED or dt <= 0.0 or dt > cfg.quality_hitch:
		return -1
	if phase == Phase.WARM or phase == Phase.SETTLE:
		_wait += dt
		var limit := cfg.quality_warmup if phase == Phase.WARM else cfg.quality_settle
		if _wait >= limit:
			phase = Phase.VERIFY if phase == Phase.SETTLE else Phase.MEASURE
			_wait = 0.0
			_clear_window()
		return -1
	_w_time += dt
	_w_frames += 1
	if _w_time < cfg.quality_window:
		return -1
	var fps := _w_frames / _w_time
	last_fps = fps
	_clear_window()
	if phase == Phase.VERIFY:
		return _verify(fps)
	return _measure(fps)


func _measure(fps: float) -> int:
	_bad = _bad + 1 if fps < cfg.quality_fps else 0
	if fps >= cfg.quality_fps:
		_chain = false
	if _bad >= cfg.quality_bad_windows and level > 0:
		if not _chain:
			_chain = true
			_chain_level = level
			_chain_fps = fps
		return _change(-1)
	if level < LEVEL_MAX and not probed and fps >= cfg.quality_fps_good:
		_good_time += cfg.quality_window
		if _good_time >= cfg.quality_probe_after:
			probed = true
			return _change(1)
	else:
		_good_time = 0.0
	return -1


func _verify(fps: float) -> int:
	phase = Phase.MEASURE
	_bad = 0
	_good_time = 0.0
	if fps >= cfg.quality_fps:
		_chain = false
		return -1
	if _dir > 0:
		level -= 1  # проба вверх не выдержала
		return level
	if level > 0:
		_bad = 1  # спуск продолжается: следующее плохое окно — ещё шаг
		return -1
	_chain = false
	if fps < _chain_fps * (1.0 + cfg.quality_gain):
		locked = true  # весь спуск ничего не дал — эффекты ни при чём
		phase = Phase.LOCKED
		level = _chain_level
		return level
	return -1  # помогло, хоть и не до порога — остаёмся на низком


func _change(d: int) -> int:
	_dir = d
	level += d
	phase = Phase.SETTLE
	_wait = 0.0
	_bad = 0
	_good_time = 0.0
	return level


func _clear_window() -> void:
	_w_time = 0.0
	_w_frames = 0
