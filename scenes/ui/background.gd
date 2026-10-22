class_name Background
extends ColorRect
## Фон меню и игры (docs/STYLE.md, раздел 9; 13.7, с 19.7 — «шёлковый вихрь»): градиент, витки с прожилками,
## вращающиеся вокруг точки за полем, пятно света и виньетка — shaders/background.gdshader. Размеры в шейдере — в
## виртуальных пикселях: rect_size ставится при каждом resize, поэтому в портрете (720×1280) и в альбоме
## (2276×1280 на 16:9) витки одного размера, а свет и виньетка — по своему экрану.
## Темп вихря — униформа speed: SPEED, при «Меньше движения» — SPEED_CALM (GameState.settings_changed).
## На победе свет ярче (set_win): 70/255 вместо 48/255, как в эталоне A3B_win.
## Качество (14.7, PLAN 4.5): на среднем и низком (Quality.level < HIGH) шейдер считает не каждый пиксель экрана
## каждый кадр, а внутренний SubViewport «Bake» — в quality_bg_scale разрешения экрана, quality_bg_fps_mid /
## quality_bg_fps_low раз в секунду (витки при SPEED смещаются в среднем на ≈ 9 px/с — за кадр Bake на 20 / 10 к/с
## меньше 1 px, у 99 % экрана — до 2 / 4 px; витки мягкие, рывков не видно); сам узел только
## растягивает его картинку (униформа use_baked — одна выборка на пиксель). Пока меняется свет победы — каждый
## кадр. Переход на картинку — после первого кадра Bake (без чёрной вспышки).

## Тема главы (19.5c, Chapters.theme_of, STYLE 11.6): цвета градиента, виньетки и вихря (deep, cool, warm —
## 19.7). При запуске — глава GameState.level (меню, карта, лидеры); игра ставит тему своего уровня, карта — главы
## посреди экрана (set_chapter_theme).
## Смена темы — плавный переход THEME_FADE (линейно, как свет победы).
const THEME_FADE := 0.6
const THEME_PARAMS := {"top": &"top_color", "mid": &"mid_color", "bottom": &"bottom_color",
		"vignette": &"vignette_color", "deep": &"deep_color", "cool": &"cool_color", "warm": &"warm_color"}
## Темп вихря (униформа speed, во сколько раз быстрее «часового»: оборот за 20 мин, витки — 1 px/с). Целые:
## TIME сбрасывается каждые 3600 с, и только при целом темпе на стыке нет скачка. 10.10 (19.7): при 1 движения
## не видно — SPEED 8 (оборот за 2,5 мин, витки — в среднем ≈ 9 px/с). «Меньше движения» — SPEED_CALM.
## Смена темпа на ходу сдвигает узор (фаза = темп × TIME) — бывает только при переключении настройки.
const SPEED := 8.0
const SPEED_CALM := 1.0
## Непрозрачность пятна света: обычная и на победе (STYLE 9).
const LIGHT := 48.0 / 255.0
const LIGHT_WIN := 70.0 / 255.0
## Переход света к победному и обратно, с (линейно — фон не пружинит, STYLE 12).
const LIGHT_FADE := 0.4

var _mat: ShaderMaterial
var _speed := -1.0
var _tween: Tween
var _win := false
var _theme_tween: Tween
var _theme_from := {}
var _theme_to := {}
var _cfg: JuiceConfig
## Фон в SubViewport (среднее и низкое качество): узел, его ColorRect и материал (копия _mat без use_baked).
var _bake: SubViewport
var _bake_rect: ColorRect
var _bake_mat: ShaderMaterial
var _bake_t := 0.0
var _bake_ready := false
var _bake_since := 0
var _bake_frames := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cfg = Juice.shared_config()
	_mat = material as ShaderMaterial
	_mat.set_shader_parameter(&"light", LIGHT)
	set_chapter_theme(Chapters.theme_of(GameState.level), false)
	_apply_speed()
	GameState.settings_changed.connect(_apply_speed)
	resized.connect(_update_rect)
	get_viewport().size_changed.connect(_resize_bake)
	Quality.changed.connect(_on_quality_changed)
	set_process(false)
	_update_rect()
	_apply_quality()


## Победный свет (on) или обычный; animate = false — сразу, без перехода.
func set_win(on: bool, animate := true) -> void:
	if on == _win and animate:
		return  # уже такой свет или переход к нему идёт
	if _tween and _tween.is_valid():
		_tween.kill()
	_win = on
	var target := LIGHT_WIN if on else LIGHT
	if not animate or not is_inside_tree():
		_set_light(target)
		return
	_tween = create_tween()
	_tween.tween_method(_set_light, get_light(), target, LIGHT_FADE)


## Тема главы chapter_theme ({"top", "mid", "bottom", "vignette", "deep", "cool", "warm"} — Chapters.theme_of);
## animate — переход
## THEME_FADE. Та же тема, что уже стоит или к которой идёт переход, — ничего не делает.
## Не set_theme / get_theme: это методы Control (свойство theme: Theme), Godot не даст их переопределить.
func set_chapter_theme(chapter_theme: Dictionary, animate := true) -> void:
	if chapter_theme == _theme_to:
		return
	if _theme_tween and _theme_tween.is_valid():
		_theme_tween.kill()
	_theme_from = theme_colors()
	_theme_to = chapter_theme.duplicate()
	if not animate or not is_inside_tree():
		_apply_theme(1.0)
		return
	_theme_tween = create_tween()
	_theme_tween.tween_method(_apply_theme, 0.0, 1.0, THEME_FADE)


## Тема, к которой идёт (или пришёл) фон.
func get_chapter_theme() -> Dictionary:
	return _theme_to


## Цвета, которые сейчас у шейдера (для перехода и selftest): ключи THEME_PARAMS, только заданные.
func theme_colors() -> Dictionary:
	var out := {}
	for k: String in THEME_PARAMS:
		var v: Variant = _mat.get_shader_parameter(THEME_PARAMS[k])
		if v is Color:
			out[k] = v
	return out


func _apply_theme(t: float) -> void:
	for k: String in THEME_PARAMS:
		if not _theme_to.has(k):
			continue
		var to: Color = _theme_to[k]
		var from: Color = _theme_from.get(k, to)
		_set_param(THEME_PARAMS[k], from.lerp(to, t))
	_request_bake()  # переход темы — каждый кадр


func is_win() -> bool:
	return _win


## Текущая непрозрачность пятна света (для selftest и перехода).
func get_light() -> float:
	return float(_mat.get_shader_parameter(&"light"))


## Темп вихря, который сейчас у шейдера (SPEED или SPEED_CALM; для selftest).
func get_speed() -> float:
	return float(_mat.get_shader_parameter(&"speed"))


## Размер прямоугольника, который сейчас знает шейдер (для selftest).
func get_rect_size() -> Vector2:
	return _mat.get_shader_parameter(&"rect_size")


## Фон считается в SubViewport (среднее и низкое качество) и узел показывает его картинку (selftest).
func is_baked() -> bool:
	return _bake != null and _bake_ready


## Размер картинки Bake, px (Vector2i.ZERO — фон считается прямо на экране; selftest).
func bake_size() -> Vector2i:
	return _bake.size if _bake != null else Vector2i.ZERO


## Сколько раз с включения Bake просили перерисоваться (selftest: частота обновления).
func bake_frames() -> int:
	return _bake_frames


## Обновлений Bake в секунду на текущем уровне качества (0 — Bake нет).
func bake_fps() -> float:
	if _bake == null:
		return 0.0
	return _cfg.quality_bg_fps_low if Quality.level == Quality.LOW else _cfg.quality_bg_fps_mid


func _set_light(v: float) -> void:
	_set_param(&"light", v)
	_request_bake()  # переход света победы — каждый кадр


## Темп вихря по настройке «Меньше движения» (при запуске и на каждое settings_changed).
func _apply_speed() -> void:
	var want := SPEED_CALM if GameState.reduce_motion else SPEED
	if want != _speed:
		_speed = want
		_set_param(&"speed", want)
		_request_bake()


func _update_rect() -> void:
	_set_param(&"rect_size", size)
	_resize_bake()


## Униформа фона — и у узла, и у Bake.
func _set_param(param: StringName, value: Variant) -> void:
	_mat.set_shader_parameter(param, value)
	if _bake_mat != null:
		_bake_mat.set_shader_parameter(param, value)


# --- Качество (14.7) ------------------------------------------------------------

func _on_quality_changed(_level: int) -> void:
	_apply_quality()


func _apply_quality() -> void:
	var want := Quality.level < Quality.HIGH
	if want and _bake == null:
		_make_bake()
	elif not want and _bake != null:
		_drop_bake()
	elif _bake != null:
		_resize_bake()  # низкое ↔ среднее: другое разрешение экрана (content_scale_mode) и частота


func _make_bake() -> void:
	_bake_mat = _mat.duplicate() as ShaderMaterial
	_bake_mat.set_shader_parameter(&"use_baked", false)
	_bake_mat.set_shader_parameter(&"baked", null)
	_bake_mat.set_shader_parameter(&"light", _mat.get_shader_parameter(&"light"))
	_bake_mat.set_shader_parameter(&"rect_size", size)
	_bake = SubViewport.new()
	_bake.name = "Bake"
	_bake.disable_3d = true
	_bake.transparent_bg = false
	_bake.render_target_update_mode = SubViewport.UPDATE_ONCE
	_bake_rect = ColorRect.new()
	_bake_rect.color = Color.WHITE
	_bake_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bake_rect.material = _bake_mat
	_bake.add_child(_bake_rect)
	add_child(_bake, false, Node.INTERNAL_MODE_FRONT)
	_bake_ready = false
	_bake_frames = 0
	_bake_t = 0.0
	# Узел переходит на картинку в следующем кадре, когда Bake уже отрисован (UPDATE_ONCE — в конце этого).
	_bake_since = Engine.get_process_frames()
	_resize_bake()
	set_process(true)


func _use_bake() -> void:
	_bake_ready = true
	_bake_frames += 1
	_mat.set_shader_parameter(&"baked", _bake.get_texture())
	_mat.set_shader_parameter(&"use_baked", true)


func _drop_bake() -> void:
	_mat.set_shader_parameter(&"use_baked", false)
	_mat.set_shader_parameter(&"baked", null)
	_bake.queue_free()
	_bake = null
	_bake_rect = null
	_bake_mat = null
	_bake_ready = false
	set_process(false)


## Размер Bake: quality_bg_scale от размера фона в пикселях экрана (на низком весь 2D уже в базовом разрешении).
func _resize_bake() -> void:
	if _bake == null:
		return
	var k := clampf(_cfg.quality_bg_scale * _screen_scale(), 0.1, 4.0)
	var n := Vector2i(maxi(ceili(size.x * k), 1), maxi(ceili(size.y * k), 1))
	if _bake.size != n:
		_bake.size = n
	_bake_rect.position = Vector2.ZERO
	_bake_rect.size = Vector2(n)
	_request_bake()


## Пикселей экрана на виртуальный px фона: растяжение окна (canvas_items) × масштаб холста узла.
func _screen_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var s := get_viewport().get_final_transform().get_scale().x * get_global_transform_with_canvas().get_scale().x
	return s if s > 0.0 else 1.0


func _request_bake() -> void:
	if _bake == null:
		return
	_bake.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _bake_ready:
		_bake_frames += 1


func _process(delta: float) -> void:
	if _bake == null:
		set_process(false)
		return
	if not _bake_ready:
		if Engine.get_process_frames() > _bake_since:
			_use_bake()
		return
	var fps := bake_fps()
	if fps <= 0.0:
		return
	_bake_t += delta
	if _bake_t >= 1.0 / fps:
		_bake_t = fmod(_bake_t, 1.0 / fps)
		_request_bake()
