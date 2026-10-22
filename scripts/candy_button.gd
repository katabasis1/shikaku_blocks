class_name CandyButton
extends Button
## Круглая кнопка-картинка из PNG 256×256 (docs/STYLE.md, разделы 4, 7, 8). Сама Button ничего не рисует
## (тип темы CandyButton — пустые StyleBox): картинку `icon` из сцены при _ready забирает лицо `Face`
## (TextureRect на 256/240 больше видимого круга: в PNG круг кнопки — 240 px), под лицом — тень SoftShadow
## (SHADE 38 %, вниз 4,5 % Ø, размытие 4 % Ø). Видимый Ø = меньшая сторона кнопки (зона нажатия = круг).
## Состояния: наведение — Desktop.add_hover (×1,05 всей кнопки, курсор-«рука»); нажата — лицо и значки
## ×0,92 вокруг центра кнопки, тень вдвое ближе; выключена — лицо 45 %, без тени. Значки на кнопке — обычные дети-TextureRect
## с метаданными badge_d (видимый Ø, px): встают центром на (0,36·Ø; −0,36·Ø) от центра, поверх лица,
## со своей тенью (вниз 3 px, размытие 3 px, SHADE 35 %); badge_shape / badge_round — форма для тени.
## 14.6d: отпускание — с отскоком (tween_release: лицо 0,92 → ×button_release_peak → 1, JuiceConfig);
## «Меньше движения» — без перелёта. Звук — как был, в обработчиках нажатий.

## Текстура больше видимого круга: в PNG 256 круг кнопки — 240.
const FACE_OVERSCAN := 256.0 / 240.0
## Видимая часть PNG кнопки (губа снизу: чуть выше, чем шире; tools/cut_icons.py).
const FACE_SHAPE := Vector2(236.0, 240.0) / 256.0
const SHADOW_OFFSET := 0.045  # доли видимого Ø
const SHADOW_BLUR := 0.04
const SHADOW_STRENGTH := 0.38
const PRESS_SCALE := 0.92
const PRESS_NEAR := 0.5       # тень нажатой кнопки вдвое ближе
const PRESS_TIME := 0.07
const DISABLED_ALPHA := 0.45
## Значки: центр на 0,36·Ø от центра кнопки по обеим осям; картинка больше видимого на 256/240.
const BADGE_SHIFT := 0.36
const BADGE_OVERSCAN := 256.0 / 240.0
const BADGE_SHADOW_OFFSET := 3.0
const BADGE_SHADOW_BLUR := 3.0
const BADGE_SHADOW_STRENGTH := 0.35

var face: TextureRect
var face_shadow: SoftShadow
## Сейчас показано: нажата / выключена.
var looks_pressed := false
var looks_disabled := false

var _tween: Tween
var _hop := 0.0


func _ready() -> void:
	face = TextureRect.new()
	face.name = "Face"
	face.texture = icon
	icon = null
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_SCALE
	face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(face, false, Node.INTERNAL_MODE_FRONT)
	face_shadow = SoftShadow.attach(face, FACE_SHAPE, 1.0, Vector2.ZERO, 0.0, SHADOW_STRENGTH)
	for b in badges():
		b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		SoftShadow.attach(b, b.get_meta(&"badge_shape", Vector2.ONE * (240.0 / 256.0)),
				float(b.get_meta(&"badge_round", 1.0)), Vector2(0.0, BADGE_SHADOW_OFFSET), BADGE_SHADOW_BLUR,
				BADGE_SHADOW_STRENGTH)
	resized.connect(_layout)
	_layout()
	_sync_look(true)


## Картинка кнопки (вместо icon: его забирает лицо).
func set_face(tex: Texture2D) -> void:
	face.texture = tex


## Видимый диаметр кнопки, px.
func diameter() -> float:
	return minf(size.x, size.y)


## Значки на кнопке: дети-TextureRect с метаданными badge_d.
func badges() -> Array[TextureRect]:
	var res: Array[TextureRect] = []
	for c in get_children():
		if c is TextureRect and c.has_meta(&"badge_d"):
			res.append(c)
	return res


func _layout() -> void:
	var d := diameter()
	var t := Vector2.ONE * d * FACE_OVERSCAN
	face.size = t
	face.position = (size - t) * 0.5 - Vector2(0.0, _hop)
	face.pivot_offset = t * 0.5
	face_shadow.offset = Vector2(0.0, d * SHADOW_OFFSET)
	face_shadow.blur = d * SHADOW_BLUR
	face_shadow.refresh()
	var c := size * 0.5 + Vector2(1.0, -1.0) * d * BADGE_SHIFT
	for b in badges():
		var bs := Vector2.ONE * float(b.get_meta(&"badge_d")) * BADGE_OVERSCAN
		b.size = bs
		b.position = c - bs * 0.5 - Vector2(0.0, _hop)
		# Нажатие сжимает значок вместе с лицом — вокруг центра кнопки, а не своего.
		b.pivot_offset = size * 0.5 - b.position


## Подъём лица и значков над местом, px (14.6g, Fx.hop: кнопка отмены в тупике подпрыгивает); тень остаётся
## на месте. Значки сжимаются при нажатии вокруг центра кнопки — их pivot сдвигается вместе с ними.
func set_hop(v: float) -> void:
	var dv := v - _hop
	_hop = v
	face.position.y -= dv
	for b in badges():
		b.position.y -= dv
		b.pivot_offset.y += dv


## Подъём лица сейчас, px (0 — на месте; selftest).
func hop_height() -> float:
	return _hop


## Перерисовка Button = сменилось состояние (нажатие, наведение, disabled): сама кнопка пустая,
## поэтому _draw только сверяет вид лица и тени с состоянием.
func _draw() -> void:
	_sync_look.call_deferred()


func _sync_look(instant: bool = false) -> void:
	if face == null:
		return
	var mode := get_draw_mode()
	var dis := disabled
	var pr := not dis and (mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED)
	if not instant and pr == looks_pressed and dis == looks_disabled:
		return
	var released := looks_pressed and not pr and not dis
	looks_pressed = pr
	looks_disabled = dis
	face.modulate = Color(1.0, 1.0, 1.0, DISABLED_ALPHA if dis else 1.0)
	face_shadow.visible = not dis
	var k := Vector2.ONE * (PRESS_SCALE if pr else 1.0)
	var near := PRESS_NEAR if pr else 1.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if instant or not is_inside_tree():
		face.scale = k
		face_shadow.near = near
		for b in badges():
			b.scale = k
		return
	_tween = create_tween().set_parallel()
	_tween.tween_property(face_shadow, "near", near, PRESS_TIME)
	var nodes: Array = [face]
	nodes.append_array(badges())
	if released:
		tween_release(_tween, nodes)
		return
	for n: Control in nodes:
		_tween.tween_property(n, "scale", k, PRESS_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Отпускание (14.6d; группа «Появление и переходы» в JuiceConfig) в параллельный твин tw: узлы nodes (лицо,
## значки) из нажатого до ×button_release_peak за 45 % button_release_time и обратно до ×1 за остальное.
## «Меньше движения» (или пик не больше 1) — прямо к ×1 за PRESS_TIME, как было. Общее с PillButton.
static func tween_release(tw: Tween, nodes: Array) -> void:
	var c := Juice.shared_config()
	if GameState.reduce_motion or c.button_release_peak <= 1.0 or c.button_release_time <= 0.0:
		for n: Control in nodes:
			tw.tween_property(n, "scale", Vector2.ONE, PRESS_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		return
	var peak := Vector2.ONE * c.button_release_peak
	var up := c.button_release_time * 0.45
	var down := c.button_release_time - up
	for n: Control in nodes:
		tw.tween_property(n, "scale", peak, up).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "scale", Vector2.ONE, down).from(peak).set_delay(up) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
