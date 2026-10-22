class_name Confetti
extends Control
## Конфетти победы (docs/STYLE.md, раздел 11; стиль-кадр A3B_win; 13.5b): COUNT кусочков цветов блоков
## 2, 3, 4, 5, 6, 8, 9 и белого — скруглённые полоски и кружки (доля кружков DOT_SHARE), часть — с мягким
## краем (SOFT_SHARE, «глубина»). Залп из точки burst(origin) — центра поля — во все стороны с упором вверх;
## дальше кусочки тормозит воздух (DRAG), тянет вниз (GRAVITY), они покачиваются, полоски кувыркаются
## (сплющиваются поперёк) и в конце жизни гаснут.
## Узел стоит в WinBackdrop — за полем, заголовком и карточкой, поэтому на них конфетти не попадает
## (STYLE 11), только на фон вокруг. Текстуры кусочков рисуются один раз в коде (белые, с мягкой альфой —
## повёрнутые края без лесенки), цвет — модуляцией.
## Сколько кусочков (burst без count): COUNT × доля качества (Quality.particles(), 14.7) × confetti_share
## (JuiceConfig; «без эффектов», 14.8a, — 0) × reduced_particles при «Меньше движения» (STYLE 12: конфетти вдвое
## меньше) — на высоком 70, с «Меньше движения» 35, на низком 21.

const COUNT := 70
## Группа узлов конфетти (счётчик кадров FpsMeter считает их кусочки).
const GROUP := &"confetti"
const AREAS: Array[int] = [2, 3, 4, 5, 6, 8, 9]
const DOT_SHARE := 0.35
const SOFT_SHARE := 0.3
const ALPHA := 0.92
## Полоска 8×16 и кружок 8 px (как в кадре), каждый кусочек ×0,8…1,3.
const STRIP := Vector2(8.0, 16.0)
const DOT := 8.0
const SIZE_K := Vector2(0.8, 1.3)
## Скорость залпа, px/с; сопротивление воздуха, 1/с (v *= e^(−DRAG·t)); притяжение, px/с².
const SPEED := Vector2(650.0, 1450.0)
const DRAG := 2.2
const GRAVITY := 1150.0
## Покачивание: размах px и частота рад/с; вращение рад/с; кувырок полоски рад/с.
const SWAY := Vector2(10.0, 26.0)
const SWAY_FREQ := Vector2(3.0, 6.0)
const SPIN := 7.0
const FLIP := Vector2(5.0, 11.0)
## Жизнь кусочка, с; последние FADE с гаснет.
const LIFE := Vector2(2.6, 3.6)
const FADE := 0.5

## Текстуры: [полоска, кружок] резкие и [полоска, кружок] мягкие; во сколько раз текстура больше своей
## фигуры (поля под мягкий край) — прямоугольник рисования растягивается так же.
static var _textures: Array[Texture2D] = []
static var _tex_k: Array[Vector2] = []

## Кусочки: pos, vel, angle, spin, flip, flip_speed, sway, sway_freq, phase, size, color, tex, age, life.
var parts: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(GROUP)
	set_process(false)


## Залп count кусочков из точки origin (координаты узла); count < 0 — default_count().
func burst(origin: Vector2, count: int = -1) -> void:
	if count < 0:
		count = default_count()
	if _textures.is_empty():
		_textures = _make_textures()
	parts.clear()
	_rng.randomize()
	for i in count:
		var dot := _rng.randf() < DOT_SHARE
		var soft := _rng.randf() < SOFT_SHARE
		var k := _rng.randf_range(SIZE_K.x, SIZE_K.y)
		var sz := Vector2(DOT, DOT) * k if dot else Vector2(STRIP.x * _rng.randf_range(SIZE_K.x, SIZE_K.y), STRIP.y * k)
		# Во все стороны, но больше вверх: угол от −180° до 0° (верх) и немного вниз по бокам.
		var a := _rng.randf_range(-PI * 1.08, PI * 0.08)
		var color := Color.WHITE if i % 8 == 7 else Palette.color_for(AREAS[_rng.randi() % AREAS.size()])
		color.a = ALPHA
		parts.append({
			"pos": origin,
			"vel": Vector2.from_angle(a) * _rng.randf_range(SPEED.x, SPEED.y),
			"angle": _rng.randf_range(0.0, TAU),
			"spin": _rng.randf_range(-SPIN, SPIN),
			"flip": _rng.randf_range(0.0, TAU),
			"flip_speed": 0.0 if dot else _rng.randf_range(FLIP.x, FLIP.y),
			"sway": _rng.randf_range(SWAY.x, SWAY.y),
			"sway_freq": _rng.randf_range(SWAY_FREQ.x, SWAY_FREQ.y),
			"phase": _rng.randf_range(0.0, TAU),
			"size": sz,
			"color": color,
			"tex": (1 if dot else 0) + (2 if soft else 0),
			"age": 0.0,
			"life": _rng.randf_range(LIFE.x, LIFE.y),
		})
	set_process(true)
	queue_redraw()


## Кусочков в залпе на текущем уровне качества и с «Меньше движения» (см. шапку).
func default_count() -> int:
	var cfg := Juice.shared_config()
	var k := Quality.particles() * cfg.confetti_share
	if GameState.reduce_motion:
		k *= cfg.reduced_particles
	return roundi(COUNT * k)


func stop() -> void:
	parts.clear()
	set_process(false)
	queue_redraw()


func is_active() -> bool:
	return not parts.is_empty()


func _process(delta: float) -> void:
	step(delta)


## Сдвинуть все кусочки на dt секунд (отдельно от _process — для самопроверки).
func step(dt: float) -> void:
	var damp := exp(-DRAG * dt)
	var alive: Array[Dictionary] = []
	for p in parts:
		p.age += dt
		if p.age >= p.life or p.pos.y > size.y + 60.0:
			continue
		var v: Vector2 = p.vel
		v = v * damp + Vector2(0.0, GRAVITY * dt)
		p.vel = v
		p.pos += v * dt
		p.angle += p.spin * dt
		p.flip += p.flip_speed * dt
		alive.append(p)
	parts = alive
	if parts.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	for p in parts:
		var age: float = p.age
		var col: Color = p.color
		col.a *= clampf((p.life - age) / FADE, 0.0, 1.0)
		# Покачивание растёт, пока кусочек тормозит после залпа.
		var sway: float = p.sway * (1.0 - exp(-2.0 * age)) * sin(age * p.sway_freq + p.phase)
		var flip := maxf(absf(cos(p.flip)), 0.18) if p.flip_speed > 0.0 else 1.0
		var t: int = p.tex
		var sz: Vector2 = p.size * _tex_k[t]
		draw_set_transform(p.pos + Vector2(sway, 0.0), p.angle, Vector2(flip, 1.0))
		draw_texture_rect(_textures[t], Rect2(-sz * 0.5, sz), false, col)
	draw_set_transform(Vector2.ZERO)


## Белые текстуры кусочков: полоска (скругление трети ширины) и кружок; резкие (край 1 px) и мягкие
## (край ~4 px — как размытые в кадре). Полоска 16×32 и кружок 16×16 — вдвое крупнее кусочка на экране.
static func _make_textures() -> Array[Texture2D]:
	var res: Array[Texture2D] = []
	_tex_k.clear()
	for soft: bool in [false, true]:
		for n: Vector2i in [Vector2i(16, 32), Vector2i(16, 16)]:
			var tex := _shape_texture(n, 16.0 / 3.0 if n.y > n.x else 8.0, soft)
			res.append(tex)
			_tex_k.append(tex.get_size() / Vector2(n))
	return res


static func _shape_texture(n: Vector2i, r: float, soft: bool) -> Texture2D:
	var pad := 6 if soft else 2
	var img := Image.create(n.x + 2 * pad, n.y + 2 * pad, false, Image.FORMAT_RGBA8)
	var half := Vector2(n) * 0.5
	var c := Vector2(img.get_width(), img.get_height()) * 0.5
	var edge := 4.0 if soft else 0.75
	for y in img.get_height():
		for x in img.get_width():
			# Расстояние до скруглённого прямоугольника (минус — внутри).
			var q := (Vector2(x + 0.5, y + 0.5) - c).abs() - half + Vector2(r, r)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r
			var a := 1.0 - smoothstep(-edge, edge, d)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)
