class_name HeartsBar
extends Control
## Сердца попытки (20.1, PLAN 20.1) — на месте прежней кнопки «Отмена», слева в полосе действий (портрет и альбом;
## ряд пустых сердец в окне «Сердца закончились» — тот же класс). Слева направо max_hearts сердец. Без предела сердец
## (max 0: уровни со страховкой, «Лаборатория», флаг hearts = 0) — пусто. Нажатия не ловит.
## Вид (20.1c, docs/STYLE.md, раздел 17) — мармелад, как у кнопок и блоков (STYLE 5): мягкая тень, губа, лицо
## с градиентом сверху вниз, кайма, блик-серп на левой доле; сгоревшее — утопленная лунка со светлым кантом снизу.
## Рисуется в _draw, без картинок; кадр — tools/window_preview.py --hearts-bar (G20_1_hearts.png).
## Движение (числа — JuiceConfig, группа «Сердца»):
##   сгорание — show_hearts заметил, что сердец меньше: heart_burn_delay сердце ещё целое (ждёт трещины ошибочного
##     блока), за heart_crack_time по нему бежит трещина, затем «пуф» (сигнал puffed — мягкий звук Puff даёт Game):
##     сердце раздувается до ×heart_puff_scale и тает за heart_puff_time, искры его цвета (Juice, SPARKS);
##   последнее из нескольких бьётся «тук-тук» (BEAT_AT) раз в heart_beat_period с — после того, как догорело
##     предпоследнее (сигнал last_heart, раз — тихий удар сердца Heartbeat);
##   возрождение (pop) — сердце вырастает из ×0 с дожимом за heart_pop_time.
## «Меньше движения»: трещина сразу, сердце гаснет без раздувания и искр, появляется без роста, не бьётся (звуки те же).
## Новый уровень и «Заново» (сердец больше или другой предел) — сразу, без анимаций.

## Сердце догорело — «пуф» (k — номер сердца слева, 0…).
signal puffed(index: int)
## Осталось последнее сердце из нескольких — оно начало биться.
signal last_heart

## Сердце не больше HEART px (полоса действий — 96–100 px высотой); не влезают — меньше, промежуток GAP.
const HEART := 56.0
const GAP := 10.0
## Цвет сердца — красно-розовый счётчика подсказок (STYLE 2.2, #FF4D6D); «конфета» — из него (STYLE 5).
const COLOR := Color(1.0, 0.302, 0.427)
## Лицо: сверху светлее на FACE_TOP, снизу темнее на FACE_BOTTOM (lightened / darkened); градиент — по высоте
## квадрата сердца (у губы — тот же, что у лица над ней).
const FACE_TOP := 0.3
const FACE_BOTTOM := 0.07
## Губа: то же сердце ниже на DEPTH стороны (у блока — 0,075 клетки), темнее на LIP_TOP сверху и LIP_BOTTOM снизу.
const DEPTH := 0.075
const LIP_TOP := 0.34
const LIP_BOTTOM := 0.22
## Тень — SHADE, как у кнопок (STYLE 7): вниз на SHADOW_Y стороны, три слоя ×SHADOW_GROW (мягкий край), у слоя
## SHADOW.a — вместе ≈ 38 %.
const SHADOW := Color(0.204, 0.086, 0.561, 0.15)
const SHADOW_Y := 0.06
const SHADOW_GROW: Array[float] = [1.0, 1.06, 1.12]
## Кайма объёма: контур, ужатый до ×RIM_INSET, толщиной RIM_W стороны, темнее цвета на RIM_DARK, непрозрачность
## RIM_ALPHA (STYLE 5: «тёмная кайма» по краю лица).
const RIM_INSET := 0.92
const RIM_W := 0.06
const RIM_DARK := 0.14
const RIM_ALPHA := 0.35
## Блик-серп на левой доле: дуга вокруг GLINT_C (доли стороны от середины) радиусом GLINT_R, углы GLINT_FROM…
## GLINT_TO (рад, 0 — вправо, −π/2 — вверх), толщина GLINT_W, белый GLINT_ALPHA.
const GLINT_C := Vector2(-0.25, -0.2)
const GLINT_R := 0.15
const GLINT_FROM := -2.89
const GLINT_TO := -1.82
const GLINT_W := 0.055
const GLINT_ALPHA := 0.55
## Лунка сгоревшего: DEEP 30 % и светлый кант снизу (лунка на EDGE_Y стороны ниже — как кант лотка поля, STYLE 6).
const EMPTY := Color(0.118, 0.043, 0.361, 0.3)
const EMPTY_EDGE := Color(1.0, 1.0, 1.0, 0.16)
const EDGE_Y := 0.03
## Трещина: ломаные в долях стороны от середины (главная — от выемки к острию, две ветки), растут разом. Тёмная —
## цвет сердца темнее на CRACK_DARK, толщиной CRACK_W стороны (не тоньше CRACK_MIN_W px); под ней светлый край
## CRACK_LIGHT, ниже на CRACK_LIT стороны.
const CRACK := [
	[Vector2(0.0, -0.2), Vector2(-0.06, -0.08), Vector2(0.05, 0.03), Vector2(-0.03, 0.15), Vector2(0.01, 0.27)],
	[Vector2(-0.06, -0.08), Vector2(-0.18, -0.03), Vector2(-0.26, -0.07)],
	[Vector2(0.05, 0.03), Vector2(0.19, 0.08)],
]
const CRACK_DARK := 0.55
const CRACK_W := 0.05
const CRACK_MIN_W := 2.0
const CRACK_LIGHT := Color(1.0, 1.0, 1.0, 0.35)
const CRACK_LIT := 0.025
## Искры «пуфа» — цвет сердца, светлее на SPARK_LIGHT.
const SPARK_LIGHT := 0.35
## Биение последнего сердца: удары от начала цикла, с, их сила (доля heart_beat), длина удара BEAT_LEN с (масштаб
## растёт и спадает по синусу). Звук Heartbeat — те же удары (tools/make_sfx.py читает BEAT_AT и BEAT_POWER).
const BEAT_AT: Array[float] = [0.0, 0.22]
const BEAT_POWER: Array[float] = [1.0, 0.6]
const BEAT_LEN := 0.16
## Точек на контуре сердца.
const POINTS := 40
## Кривая сердца x = 16 sin³t, y = 13 cos t − 5 cos 2t − 2 cos 3t − cos 4t: x в −16..16, y в −17..HEART_TOP.
const HEART_TOP := 11.92
const HEART_H := 28.92

## Сколько сердец на попытку (0 — без предела, ничего не рисуем).
var max_hearts: int = 0
## Ряд сердец не шире row_max px (0 — вся ширина полосы): в портрете полоса тянется до «Подсказки», а справа от
## сердец стоит плашка «Осталось блоков» (Game.apply_layout, GameLayout.HEARTS_ROW_PORTRAIT). Больше сердец, чем
## влезает полного размера, — мельче.
var row_max := 0.0:
	set(v):
		row_max = v
		queue_redraw()
## Сколько осталось.
var left: int = 0
## Сколько раз сердце «пуфнуло» (для самопроверки).
var puffs: int = 0
## Свои часы, с (идут, пока есть движение).
var _t := 0.0
## Горящие сердца: {номер: миг начала трещины по _t} (до него — ещё целое).
var _burns: Dictionary = {}
## Сердца, у которых «пуф» уже был: {номер: true}.
var _puffed: Dictionary = {}
## Возрождённое сердце (−1 — нет) и миг, когда оно начало расти.
var _pop_k := -1
var _pop_from := 0.0
## Миг, с которого бьётся последнее сердце (< 0 — не бьётся).
var _beat_from := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	GameState.settings_changed.connect(_on_settings_changed)
	set_process(false)


## «Меньше движения» включили или выключили посреди уровня: биение последнего сердца — сразу по-новому.
func _on_settings_changed() -> void:
	set_process(_moving())
	queue_redraw()


## Game.update_hud: осталось n_left из n_max. Меньше, чем было, — сердца сгорают (по очереди справа, разом);
## больше или другой предел (новый уровень, «Заново», возрождение) — сразу.
func show_hearts(n_left: int, n_max: int) -> void:
	if n_left == left and n_max == max_hearts:
		return
	if n_max != max_hearts or n_left > left:
		_burns.clear()
		_puffed.clear()
		_pop_k = -1
	else:
		var at := _t + cfg().heart_burn_delay
		for k in range(n_left, left):
			_burns[k] = at
			_puffed.erase(k)
	left = n_left
	max_hearts = n_max
	_update_beat()
	set_process(_moving())
	queue_redraw()


## Game.revive: сердце left − 1 только что вернулось — вырастает (show_hearts уже знает новое число).
func pop() -> void:
	if left <= 0 or left > max_hearts:
		return
	_pop_k = left - 1
	_pop_from = _t
	set_process(true)
	queue_redraw()


## Сердце k ещё горит (трещина или «пуф»; до трещины — тоже).
func is_burning(k: int = -1) -> bool:
	return not _burns.is_empty() if k < 0 else _burns.has(k)


## Последнее сердце бьётся.
func is_beating() -> bool:
	return _beat_from >= 0.0


## Масштаб сердца k сейчас (1 — в покое).
func heart_scale(k: int) -> float:
	return heart_state(k).x


## Трещина по сердцу k, 0…1.
func heart_crack(k: int) -> float:
	return heart_state(k).z


## Сердце k сейчас: x — масштаб, y — непрозрачность «конфеты» (0 — только лунка), z — трещина 0…1.
func heart_state(k: int) -> Vector3:
	var c := cfg()
	var calm := GameState.reduce_motion
	if _burns.has(k):
		var p := _t - float(_burns[k])
		if p < 0.0:
			return Vector3(1.0, 1.0, 0.0)
		if p < c.heart_crack_time:
			return Vector3(1.0, 1.0, 1.0 if calm else p / c.heart_crack_time)
		var q := 1.0 if c.heart_puff_time <= 0.0 else clampf((p - c.heart_crack_time) / c.heart_puff_time, 0.0, 1.0)
		var grow := 1.0 if calm else lerpf(1.0, c.heart_puff_scale, 1.0 - (1.0 - q) * (1.0 - q))
		return Vector3(grow, 1.0 - q, 1.0)
	if k >= left or k >= max_hearts:
		return Vector3(1.0, 0.0, 0.0)
	var sc := 1.0
	var alpha := 1.0
	if k == _pop_k:
		var q := 1.0 if c.heart_pop_time <= 0.0 else clampf((_t - _pop_from) / c.heart_pop_time, 0.0, 1.0)
		if calm:
			alpha = q
		else:
			sc = back_out(q)
	if _beat_from >= 0.0 and k == left - 1 and not calm:
		sc *= 1.0 + c.heart_beat * beat_shape(_t - _beat_from, c.heart_beat_period)
	return Vector3(sc, alpha, 0.0)


func _process(delta: float) -> void:
	_t += delta
	var c := cfg()
	for k: int in _burns.keys():
		var p := _t - float(_burns[k])
		if p >= c.heart_crack_time and not _puffed.has(k):
			_puffed[k] = true
			_puff(k)
		if p >= c.heart_crack_time + c.heart_puff_time:
			_burns.erase(k)
	if _pop_k >= 0 and _t - _pop_from >= c.heart_pop_time:
		_pop_k = -1
	_update_beat()
	set_process(_moving())
	queue_redraw()


## «Пуф» сердца k: искры (не при «Меньше движения»), счётчик и сигнал (звук — Game).
func _puff(k: int) -> void:
	puffs += 1
	var juice := Juice.of(self)
	if juice != null and not GameState.reduce_motion and cfg().heart_puff_sparks > 0:
		var at := get_global_transform() * heart_rect(k).get_center()
		juice.burst(Juice.SPARKS, at, COLOR.lightened(SPARK_LIGHT), cfg().heart_puff_sparks)
	puffed.emit(k)


## Последнее сердце из нескольких бьётся, когда ничего не горит; начало — сигнал last_heart (раз).
func _update_beat() -> void:
	var want := left == 1 and max_hearts > 1 and _burns.is_empty()
	if want and _beat_from < 0.0:
		_beat_from = _t
		last_heart.emit()
	elif not want and not (left == 1 and max_hearts > 1 and _beat_from >= 0.0):
		_beat_from = -1.0


## Нужны кадры: горит, растёт или бьётся (биение видно — без «Меньше движения» и при heart_beat > 0).
func _moving() -> bool:
	if not _burns.is_empty() or _pop_k >= 0:
		return true
	return _beat_from >= 0.0 and not GameState.reduce_motion and cfg().heart_beat > 0.0


static func cfg() -> JuiceConfig:
	return Juice.shared_config()


## Биение: 0…1 в миг t от начала (цикл period с) — удары BEAT_AT силой BEAT_POWER, по синусу за BEAT_LEN.
static func beat_shape(t: float, period: float) -> float:
	if period <= 0.0 or t < 0.0:
		return 0.0
	var p := fposmod(t, period)
	var v := 0.0
	for i in BEAT_AT.size():
		var x := (p - BEAT_AT[i]) / BEAT_LEN
		if x > 0.0 and x < 1.0:
			v = maxf(v, BEAT_POWER[i] * sin(PI * x))
	return v


## Рост с дожимом (как TRANS_BACK + EASE_OUT): 0 → чуть больше 1 → 1.
static func back_out(q: float) -> float:
	var c1 := 1.70158
	var x := q - 1.0
	return 1.0 + (c1 + 1.0) * x * x * x + c1 * x * x


## Размер ряда из n сердец полного размера (HEART, промежуток GAP), px: окно «Сердца закончились» (20.1b) ставит
## ряд по центру.
static func row_size(n: int) -> Vector2:
	if n <= 0:
		return Vector2.ZERO
	return Vector2(HEART * n + GAP * (n - 1), HEART)


## Сторона квадрата одного сердца при текущем размере полосы, px.
func heart_size() -> float:
	if max_hearts <= 0:
		return 0.0
	var w := minf(size.x, row_max) if row_max > 0.0 else size.x
	return maxf(0.0, minf(HEART, minf(size.y, (w - GAP * (max_hearts - 1)) / max_hearts)))


## Квадрат сердца k (0 — левое) в координатах полосы.
func heart_rect(k: int) -> Rect2:
	var s := heart_size()
	return Rect2(Vector2(k * (s + GAP), (size.y - s) * 0.5), Vector2(s, s))


## Контур сердца, вписанного в квадрат со стороной s и левым верхним углом at.
static func heart_points(at: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var k := s / 32.0
	var top := at.y + (s - HEART_H * k) * 0.5
	for n in POINTS:
		var t := TAU * n / POINTS
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(Vector2(at.x + (x + 16.0) * k, top + (HEART_TOP - y) * k))
	return pts


func _draw() -> void:
	var s := heart_size()
	if s <= 0.0:
		return
	for k in max_hearts:
		var center := heart_rect(k).get_center()
		var st := heart_state(k)
		if k >= left:
			_draw_socket(center, s)
		if st.y > 0.0:
			_draw_candy(center, s, st.x, st.y, st.z)


## Лунка сгоревшего сердца с серединой c.
func _draw_socket(c: Vector2, s: float) -> void:
	var pts := heart_points(c - Vector2(s, s) * 0.5, s)
	draw_colored_polygon(_moved(pts, 1.0, Vector2(0.0, maxf(1.5, EDGE_Y * s))), EMPTY_EDGE)
	draw_colored_polygon(pts, EMPTY)


## Мармеладное сердце с серединой c: масштаб sc, непрозрачность a, трещина crack 0…1.
func _draw_candy(c: Vector2, s: float, sc: float, a: float, crack: float) -> void:
	draw_set_transform(c, 0.0, Vector2(sc, sc))
	var pts := heart_points(-Vector2(s, s) * 0.5, s)
	for g in SHADOW_GROW:
		draw_colored_polygon(_moved(pts, g, Vector2(0.0, SHADOW_Y * s)), _fade(SHADOW, a))
	draw_polygon(_moved(pts, 1.0, Vector2(0.0, DEPTH * s)),
			_ramp(pts, s, COLOR.darkened(LIP_TOP), COLOR.darkened(LIP_BOTTOM), a))
	draw_polygon(pts, _ramp(pts, s, COLOR.lightened(FACE_TOP), COLOR.darkened(FACE_BOTTOM), a))
	var rim := _moved(pts, RIM_INSET, Vector2.ZERO)
	rim.append(rim[0])
	var rim_color := COLOR.darkened(RIM_DARK)
	rim_color.a = RIM_ALPHA
	draw_polyline(rim, _fade(rim_color, a), RIM_W * s, true)
	draw_arc(GLINT_C * s, GLINT_R * s, GLINT_FROM, GLINT_TO, 12, _fade(Color(1.0, 1.0, 1.0, GLINT_ALPHA), a),
			GLINT_W * s, true)
	if crack > 0.0:
		_draw_crack(s, crack, a)
	draw_set_transform(Vector2.ZERO)


## Трещина (уже в координатах середины сердца): каждая ломаная CRACK — на долю part своей длины.
func _draw_crack(s: float, part: float, a: float) -> void:
	var w := maxf(CRACK_MIN_W, CRACK_W * s)
	var lit := Vector2(0.0, maxf(1.0, CRACK_LIT * s))
	var dark := COLOR.darkened(CRACK_DARK)
	for line: Array in CRACK:
		var pts := crack_part(line, part, s)
		if pts.size() < 2:
			continue
		draw_polyline(_moved(pts, 1.0, lit), _fade(CRACK_LIGHT, a), w, true)
		draw_polyline(pts, _fade(dark, a), w, true)


## Начало ломаной line (точки — доли стороны s) длиной part от всей, px.
static func crack_part(line: Array, part: float, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if line.size() < 2 or part <= 0.0:
		return out
	var total := 0.0
	for i in range(1, line.size()):
		var from: Vector2 = line[i - 1]
		var to: Vector2 = line[i]
		total += from.distance_to(to)
	var want := total * clampf(part, 0.0, 1.0)
	out.append(line[0] * s)
	for i in range(1, line.size()):
		var a: Vector2 = line[i - 1]
		var b: Vector2 = line[i]
		var d := (b - a).length()
		if want >= d:
			out.append(b * s)
			want -= d
			continue
		if want > 0.0:
			out.append(a.lerp(b, want / d) * s)
		break
	return out


## Точки pts ×k и сдвинуты на by.
static func _moved(pts: PackedVector2Array, k: float, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = pts[i] * k + by
	return out


## Цвета вершин: от top (верх квадрата сердца) к bottom (низ) по высоте точки, непрозрачность ×a.
static func _ramp(pts: PackedVector2Array, s: float, top: Color, bottom: Color, a: float) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = _fade(top.lerp(bottom, clampf(pts[i].y / s + 0.5, 0.0, 1.0)), a)
	return out


static func _fade(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)
