class_name Juice
extends Node
## Импакт игры (этап 14; PLAN 4.4–4.5, docs/STYLE.md, раздел 12). Игра сообщает о событиях —
## event(&"placed" | &"line" | &"win", точка), — а Juice отвечает тряской, hit-stop и вспышкой частиц.
## Все числа — в theme/juice.tres (JuiceConfig).
##
## Тряска — смещение Content (поле, HUD, лоток; PLAN 4.5). «Травма» 0…1: смещение = shake_max · травма²,
## травма спадает линейно (shake_decay в секунду). Удары подряд берут большую травму, а не сумму — серия
## быстрых ходов не раскачивает экран.
## Hit-stop — короткая пауза твинов эффектов (созданных через tween()) и частиц пула. Логика игры, ввод,
## таймеры и твины самой игры идут как шли. Подряд — не дольше hitstop_max.
## Частицы — CPUParticles2D из пула на FxLayer (не больше pool_size узлов и particles_max частиц сразу;
## вспышка, которой не хватает места, урезается, а совсем без места — пропускается).
## «Меньше движения» (GameState.reduce_motion): тряски нет, частиц — доля reduced_particles.
## Качество (14.7, автозагрузка Quality): на среднем и низком частиц во вспышке и предел particles_max — доля
## Quality.particles() (вместе с «Меньше движения» — произведение долей).
## С 14.2: landed() — удар блока о поле (пыль из-под краёв, разлёт наружу); узел — в группе GROUP, блоки
## находят его через Juice.of() и создают свои твины эффектов через tween().
## С 14.4: lines() — закрытые линии хода: тряска и hit-stop по силе хода, искры вдоль линий.

signal fired(what: StringName)

const DUST := &"dust"
const SPARKS := &"sparks"
const STARS := &"stars"
const STAR_TEXTURE: Texture2D = preload("res://assets/icons/star.png")
## Размер точки-частицы (мягкий круг), px; масштаб частицы — доля от него.
const DOT_SIZE := 16
const CONFIG_PATH := "res://theme/juice.tres"
## Группа узла Juice: блоки и поле находят его через Juice.of(узел).
const GROUP := &"juice"
## Шаг точек пыли по краю блока, px экрана.
const DUST_STEP := 10.0
## Искры линии: при силе хода 0 и при наибольшей (combo_max, 14.4) — теплее.
const LINE_SPARK := Color(1.0, 0.92, 0.55)
const LINE_SPARK_HOT := Color(1.0, 0.72, 0.38)

## Числа эффектов; правятся в theme/juice.tres (инспектор Godot). Тот же ресурс — у Block.cfg().
var config: JuiceConfig = shared_config()

## Текущая «травма» тряски, 0…1.
var trauma := 0.0
## Сколько раз пришло каждое событие (для selftest).
var counts: Dictionary = {}
## Сила последнего хода с линией (lines, 14.4; для selftest).
var last_power := -1

var _target: Control
var _layer: Control
var _base := Vector2.ZERO
var _shake_t := 0.0
var _phase := Vector2.ZERO
var _stop_until := 0
var _stop_started := 0
var _tweens: Array[Tween] = []
var _stopped: Array[Tween] = []
var _pool: Array[CPUParticles2D] = []
var _ends: Dictionary = {}  # CPUParticles2D → конец вспышки, мкс (Time.get_ticks_usec)
var _amounts: Dictionary = {}  # CPUParticles2D → частиц во вспышке
var _dot: Texture2D
var _ramp: Gradient
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(GROUP)
	GameState.settings_changed.connect(_on_settings_changed)


## Числа эффектов (theme/juice.tres; load отдаёт один и тот же ресурс из кэша).
static func shared_config() -> JuiceConfig:
	return load(CONFIG_PATH) as JuiceConfig


## Узел Juice сцены, где живёт node (null — вне игры: редактор, отдельный тест поля).
static func of(node: Node) -> Juice:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as Juice


## target — что трясти (Content игры), layer — куда класть частицы (FxLayer).
func setup(target: Control, layer: Control) -> void:
	_target = target
	_layer = layer
	_base = target.position


## Что трясёт Juice (Content игры).
func target() -> Control:
	return _target


## Событие игры в точке at (глобальные координаты): «блок поставлен», «линия», «победа».
func event(what: StringName, at := Vector2.ZERO) -> void:
	match what:
		&"placed":
			add_trauma(config.trauma_place)
			hit_stop(config.hitstop_place)
			burst(DUST, at)
		&"line":
			add_trauma(config.trauma_line)
			hit_stop(config.hitstop_line)
			burst(SPARKS, at, LINE_SPARK)
		&"win":
			add_trauma(config.trauma_win)
			hit_stop(config.hitstop_win)
			burst(STARS, at, Color(1.0, 0.89, 0.36))
		_:
			push_warning("Juice: неизвестное событие %s" % what)
			return
	counts[what] = int(counts.get(what, 0)) + 1
	fired.emit(what)


## Блок лёг на поле (14.2): событие placed — тряска, и пыль из-под краёв прямоугольника rect (глобальные
## координаты), разлёт наружу; cells — размер блока в клетках (частиц dust_amount + dust_per_cell · (w + h)),
## color — цвет площади (пыль — его светлый оттенок).
func landed(rect: Rect2, cells: Vector2i, color: Color) -> void:
	add_trauma(config.trauma_place)
	hit_stop(config.hitstop_place)
	var amount := config.dust_amount + config.dust_per_cell * (cells.x + cells.y)
	var p := burst(DUST, rect.get_center(), color.lerp(Color.WHITE, 0.65), amount)
	if p != null:
		_edge_points(p, rect.size * 0.5)
	counts[&"placed"] = int(counts.get(&"placed", 0)) + 1
	fired.emit(&"placed")


## Линии закрыты (14.4): тряска и hit-stop по силе хода power (Game: (линий − 1) + (серия − 1); +combo_trauma
## и +combo_hitstop на единицу, hit-stop — не дольше hitstop_max), искры вдоль каждой линии — rects (глобальные
## прямоугольники линий), lengths — их длина в клетках: (sparks_amount + line_sparks_per_cell · длина) ·
## (1 + combo_sparks · сила); с силой искры теплее. Волну света по линии делает поле (Board.flash_line).
func lines(rects: Array[Rect2], lengths: Array[int], power: int) -> void:
	var p := maxi(power, 0)
	last_power = p
	add_trauma(config.trauma_line + config.combo_trauma * p)
	hit_stop(config.hitstop_line + config.combo_hitstop * p)
	var color := LINE_SPARK.lerp(LINE_SPARK_HOT, clampf(float(p) / maxf(float(config.combo_max), 1.0), 0.0, 1.0))
	for k in rects.size():
		var n: int = lengths[k] if k < lengths.size() else 0
		var amount := roundi((config.sparks_amount + config.line_sparks_per_cell * n) * (1.0 + config.combo_sparks * p))
		burst(SPARKS, rects[k].get_center(), color, amount, rects[k].size * 0.5)
	counts[&"line"] = int(counts.get(&"line", 0)) + 1
	fired.emit(&"line")


## Точки пыли по периметру ±half (от центра) с нормалями наружу: частица летит от края, а не из середины.
func _edge_points(p: CPUParticles2D, half: Vector2) -> void:
	var pts := PackedVector2Array()
	var normals := PackedVector2Array()
	var nx := maxi(2, int(ceil(half.x * 2.0 / DUST_STEP)))
	var ny := maxi(2, int(ceil(half.y * 2.0 / DUST_STEP)))
	for k in nx + 1:
		var x := lerpf(-half.x, half.x, float(k) / nx)
		pts.append(Vector2(x, -half.y))
		normals.append(Vector2(x / half.x * 0.3, -1.0).normalized())
		pts.append(Vector2(x, half.y))
		normals.append(Vector2(x / half.x * 0.3, 1.0).normalized())
	for k in range(1, ny):
		var y := lerpf(-half.y, half.y, float(k) / ny)
		pts.append(Vector2(-half.x, y))
		normals.append(Vector2(-1.0, y / half.y * 0.3).normalized())
		pts.append(Vector2(half.x, y))
		normals.append(Vector2(1.0, y / half.y * 0.3).normalized())
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_DIRECTED_POINTS
	p.emission_points = pts
	p.emission_normals = normals
	p.direction = Vector2.RIGHT  # вдоль нормали точки
	p.spread = 25.0
	p.restart()
	p.emitting = true


## Всё к покою: Content на место, hit-stop снят, частицы погашены (новый уровень, уход со сцены).
func reset() -> void:
	_stop_shake()
	if _stop_until > 0:
		_resume()
	for p in _pool:
		p.emitting = false
		_ends[p] = 0


# --- Тряска -------------------------------------------------------------------

## Тряска с «травмой» amount (0…1). При «Меньше движения» её нет.
func add_trauma(amount: float) -> void:
	if amount <= 0.0 or _target == null or GameState.reduce_motion:
		return
	if trauma <= 0.0:
		_base = _target.position
		_shake_t = 0.0
		_phase = Vector2(_rng.randf() * TAU, _rng.randf() * TAU)
	trauma = maxf(trauma, minf(amount, 1.0))


## Смещение тряски сейчас, px.
func shake_offset() -> Vector2:
	var a := config.shake_max * trauma * trauma
	var w := TAU * config.shake_freq * _shake_t
	return a * Vector2(sin(w + _phase.x), sin(w * 1.31 + _phase.y))


func _stop_shake() -> void:
	if trauma > 0.0 and is_instance_valid(_target):
		_target.position = _base
	trauma = 0.0


# --- Hit-stop -----------------------------------------------------------------

## Пауза эффектов на sec секунд (подряд — не дольше hitstop_max от начала паузы).
func hit_stop(sec: float) -> void:
	if sec <= 0.0:
		return
	var now := Time.get_ticks_usec()
	if _stop_until == 0:
		_stop_started = now
		_prune_tweens()
		for tw in _tweens:
			if tw.is_running():
				tw.pause()
				_stopped.append(tw)
		for p in _pool:
			p.speed_scale = 0.0
	var limit := _stop_started + int(config.hitstop_max * 1e6)
	_stop_until = mini(maxi(_stop_until, now + int(sec * 1e6)), limit)


func is_stopped() -> bool:
	return _stop_until > 0


## Твин эффекта на узле node: его останавливает hit-stop (твины логики игры так не создавайте).
func tween(node: Node) -> Tween:
	var tw := node.create_tween()
	_prune_tweens()
	_tweens.append(tw)
	if _stop_until > 0:
		tw.pause()
		_stopped.append(tw)
	return tw


func _resume() -> void:
	var paused_for := Time.get_ticks_usec() - _stop_started
	_stop_until = 0
	for tw in _stopped:
		if tw.is_valid():
			tw.play()
	_stopped.clear()
	for p in _pool:
		p.speed_scale = 1.0
		if int(_ends.get(p, 0)) > _stop_started:
			_ends[p] = int(_ends[p]) + paused_for  # вспышка стояла — живёт дольше


func _prune_tweens() -> void:
	for k in range(_tweens.size() - 1, -1, -1):
		if not _tweens[k].is_valid():
			_tweens.remove_at(k)


# --- Частицы ------------------------------------------------------------------

## Вспышка частиц kind (DUST, SPARKS, STARS) в точке at; amount < 0 — число из конфига;
## extents > 0 — частицы вылетают из прямоугольника ±extents (из-под краёв блока), иначе из точки.
func burst(kind: StringName, at: Vector2, color := Color.WHITE, amount := -1,
		extents := Vector2.ZERO) -> CPUParticles2D:
	if _layer == null:
		return null
	if amount < 0:
		amount = _default_amount(kind)
	amount = int(round(amount * particle_share()))
	amount = mini(amount, particles_cap() - live_particles())
	if amount < 2:
		return null
	var p := _free_emitter()
	if p == null:
		return null
	_setup_emitter(p, kind, color, extents)
	p.amount = amount
	p.global_position = at
	p.speed_scale = 0.0 if _stop_until > 0 else 1.0
	p.restart()
	p.emitting = true
	_amounts[p] = amount
	_ends[p] = Time.get_ticks_usec() + int((p.lifetime + 0.05) * 1e6)
	return p


## Доля частиц вспышки: уровень качества (Quality.particles(), 14.7) × reduced_particles при «Меньше движения».
func particle_share() -> float:
	var k := Quality.particles()
	if GameState.reduce_motion:
		k *= config.reduced_particles
	return k


## Предел частиц в воздухе на текущем уровне качества: particles_max × Quality.particles() (14.7).
func particles_cap() -> int:
	return int(round(config.particles_max * Quality.particles()))


## Сколько частиц сейчас в воздухе (по вспышкам пула).
func live_particles() -> int:
	var now := _stop_started if _stop_until > 0 else Time.get_ticks_usec()
	var n := 0
	for p in _pool:
		if int(_ends.get(p, 0)) > now:
			n += int(_amounts.get(p, 0))
	return n


func pool_size() -> int:
	return _pool.size()


func _default_amount(kind: StringName) -> int:
	match kind:
		STARS:
			return config.stars_amount
		SPARKS:
			return config.sparks_amount
	return config.dust_amount


func _free_emitter() -> CPUParticles2D:
	var now := Time.get_ticks_usec()
	for p in _pool:
		if int(_ends.get(p, 0)) <= now and _stop_until == 0:
			return p
	if _pool.size() >= config.pool_size:
		return null
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	_layer.add_child(p)
	_pool.append(p)
	return p


func _setup_emitter(p: CPUParticles2D, kind: StringName, color: Color, extents: Vector2) -> void:
	p.direction = Vector2.UP
	p.spread = 180.0
	p.color = color
	p.color_ramp = _fade_ramp()
	p.angle_min = 0.0
	p.angle_max = 0.0
	p.angular_velocity_min = 0.0
	p.angular_velocity_max = 0.0
	if extents.x > 0.0 and extents.y > 0.0:
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = extents
	else:
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	match kind:
		STARS:
			p.texture = STAR_TEXTURE
			p.lifetime = config.stars_life
			p.initial_velocity_min = 220.0
			p.initial_velocity_max = 440.0
			p.gravity = Vector2(0.0, 520.0)
			p.damping_min = 20.0
			p.damping_max = 40.0
			p.scale_amount_min = 0.06  # звезда 256 px → 15–26 px
			p.scale_amount_max = 0.1
			p.angle_min = -30.0
			p.angle_max = 30.0
			p.angular_velocity_min = -240.0
			p.angular_velocity_max = 240.0
		SPARKS:
			p.texture = _dot_texture()
			p.lifetime = config.sparks_life
			p.initial_velocity_min = 160.0
			p.initial_velocity_max = 340.0
			p.gravity = Vector2(0.0, 260.0)
			p.damping_min = 60.0
			p.damping_max = 120.0
			p.scale_amount_min = 0.25  # 4–7 px
			p.scale_amount_max = 0.45
		_:
			p.texture = _dot_texture()
			p.lifetime = config.dust_life
			p.initial_velocity_min = 50.0
			p.initial_velocity_max = 120.0
			p.gravity = Vector2(0.0, 180.0)
			p.damping_min = 80.0
			p.damping_max = 140.0
			p.scale_amount_min = 0.3  # 5–10 px
			p.scale_amount_max = 0.6


## Мягкий белый круг DOT_SIZE×DOT_SIZE — частица пыли и искр (цвет — от вспышки).
func _dot_texture() -> Texture2D:
	if _dot == null:
		var img := Image.create(DOT_SIZE, DOT_SIZE, false, Image.FORMAT_RGBA8)
		var c := DOT_SIZE * 0.5
		for y in DOT_SIZE:
			for x in DOT_SIZE:
				var d := Vector2(x + 0.5 - c, y + 0.5 - c).length() / c
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf((1.0 - d) * 3.0, 0.0, 1.0)))
		_dot = ImageTexture.create_from_image(img)
	return _dot


## Частица гаснет к концу жизни: непрозрачна до 60 %, потом линейно до нуля.
func _fade_ramp() -> Gradient:
	if _ramp == null:
		_ramp = Gradient.new()
		_ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		_ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		_ramp.add_point(0.6, Color(1.0, 1.0, 1.0, 1.0))
	return _ramp


# --- Кадр ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if trauma > 0.0:
		_shake_t += delta
		trauma = maxf(trauma - config.shake_decay * delta, 0.0)
		if is_instance_valid(_target):
			_target.position = (_base + shake_offset()) if trauma > 0.0 else _base
	if _stop_until > 0 and Time.get_ticks_usec() >= _stop_until:
		_resume()


func _on_settings_changed() -> void:
	if GameState.reduce_motion:
		_stop_shake()
