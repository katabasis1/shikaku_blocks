class_name PillButton
extends Button
## Кнопка с текстом — «мармеладная таблетка» (docs/STYLE.md, разделы 5 и 11; «ДАЛЕЕ» в A3B_win:
## 380×110, #2FCF78, губа 11 px). Материал — тот же, что у блоков (shaders/block.gdshader: одна
## «клетка» высотой с кнопку, скругление — половина высоты, без швов) с тенью darken(цвет, 0,6) 35 %
## вниз 0,08·h, размытие 0,09·h. Текст — Nunito 1000 (шрифт и размер — тип темы PillButton), белый,
## обводка цветом «чернил» тона 0,12·размер, тень вниз 3 px; стоит по центру лица (над губой).
## Тоны: GREEN — главное действие («ДАЛЕЕ», «ПРОДОЛЖИТЬ», «ГОТОВО»), RED — необратимое («СБРОСИТЬ»),
## LIGHT — второстепенное («Сбросить прогресс», «ОТМЕНА»): светлая таблетка, фиолетовый текст без обводки;
## GOLD — «Оценить игру» в настройках (цвета золота очков, STYLE 3: #FFC21A, обводка #A85400).
## Нажата — лицо ×0,95, тень вдвое ближе; выключена — 45 %, без тени (как CandyButton).
## 14.6d: отпускание — с отскоком, как у CandyButton (CandyButton.tween_release).
## Свой текст Button не рисует (цвета шрифта в теме прозрачные) — его рисует внутренний Caption:
## atr(Button.text) — Button.text хранит исходную строку (msgid), перевод — по auto_translate_mode кнопки;
## обновляется при смене текста, языка, темы и размера. Не влезает в кнопку без FIT_PAD_K·h с каждой
## стороны — размер подписи меньше шагом 2 (caption_size), не меньше MIN_FONT_K от размера темы.
## subtitle — вторая строка под подписью («ИГРАТЬ» / «УРОВЕНЬ 12» в меню, STYLE 11.1): размер SUB_K от размера
## подписи, тот же цвет, обводка и тень; центры строк — TWO_LINE_Y высоты лица. Её текст уже переведён
## владельцем (в нём число), кнопка его не переводит. Пустая — одна строка по центру лица.

const SHADER: Shader = preload("res://shaders/block.gdshader")

enum Tone { GREEN, RED, LIGHT, GOLD }

## Цвет таблетки, «чернила» (обводка и тень текста), цвет текста.
const TONES := {
	Tone.GREEN: [Color("#2FCF78"), Color("#12733F"), Color(1, 1, 1)],
	Tone.RED: [Color("#FF5A4E"), Color("#A3163A"), Color(1, 1, 1)],
	Tone.LIGHT: [Color("#EEE8FF"), Color("#6A42E4"), Color("#6A42E4")],
	Tone.GOLD: [Color("#FFC21A"), Color("#A85400"), Color(1, 1, 1)],
}
## Доли высоты кнопки: губа, смещение и размытие тени.
const DEPTH_K := 0.1
const SHADOW_K := 9.0 / 110.0
const BLUR_K := 10.0 / 110.0
const SHADOW_ALPHA := 0.35
const SHADOW_DARK := 0.6
## Текст: обводка (полная толщина = 2·доля·размер), тень вниз, её непрозрачность.
const OUTLINE_K := 0.12
const TEXT_SHADOW_Y := 3
const TEXT_SHADOW_ALPHA := 0.47
## Нажата — лицо мельче (у круглых CandyButton 0,92: таблетка крупнее, хватает 0,95).
const PRESSED_SCALE := 0.95
const DISABLED_ALPHA := 0.45
## Подпись не заходит на скругления: свободно FIT_PAD_K·h с каждой стороны («ПРОДОЛЖИТЬ» 46 → 42 в 400×110).
const FIT_PAD_K := 0.25
## Ужимается не меньше чем до этой доли размера темы.
const MIN_FONT_K := 0.75
## Вторая строка: размер — доля размера темы подписи (64 → 30); центры строк — доли высоты лица.
const SUB_K := 30.0 / 64.0
const TWO_LINE_Y := Vector2(0.37, 0.74)

@export var tone: Tone = Tone.GREEN:
	set(v):
		tone = v
		_apply_tone()

## Вторая строка (уже переведённая); пусто — её нет.
@export var subtitle: String = "":
	set(v):
		subtitle = v
		if is_node_ready():
			_sync_caption()

## Лицо: тело-таблетка и подпись; масштабируется при нажатии.
var face: Control
var body: ColorRect
var caption: Label
var sub_caption: Label
## Сейчас показано: нажата / выключена.
var looks_pressed := false
var looks_disabled := false
## Множитель смещения тени: 1 — обычная, 0,5 — нажата (тень вдвое ближе). Твинится.
var near := 1.0:
	set(v):
		near = v
		if _mat != null:
			_mat.set_shader_parameter(&"shadow_offset", Vector2(0.0, SHADOW_K * size.y * near))

var _mat: ShaderMaterial
var _tween: Tween
var _caption_src := ""   # Button.text, с которого сделана подпись


func _init() -> void:
	theme_type_variation = &"PillButton"
	face = Control.new()
	face.name = "Face"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"cells", Vector2.ONE)
	_mat.set_shader_parameter(&"radius", 0.5)
	_mat.set_shader_parameter(&"gap", 0.0)
	_mat.set_shader_parameter(&"depth", DEPTH_K)
	_mat.set_shader_parameter(&"seams", 0.0)
	_mat.set_shader_parameter(&"flash", 0.0)
	_mat.set_shader_parameter(&"px", 1.0)
	body = ColorRect.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.material = _mat
	face.add_child(body)
	caption = Label.new()
	caption.name = "Caption"
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # переводит сама кнопка: atr(text)
	face.add_child(caption)
	sub_caption = Label.new()
	sub_caption.name = "SubCaption"
	sub_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # текст переводит владелец
	sub_caption.visible = false
	face.add_child(sub_caption)


func _ready() -> void:
	add_child(face, false, Node.INTERNAL_MODE_FRONT)
	resized.connect(refresh)
	_apply_tone()
	refresh()
	_sync_caption()
	_sync_look(true)


## Тело, подпись и тень под нынешний размер кнопки.
func refresh() -> void:
	if face == null:
		return
	var h := size.y
	face.size = size
	face.pivot_offset = size * 0.5
	var m := ceilf(h * (BLUR_K * 3.0 + SHADOW_K))
	body.position = Vector2(-m, -m)
	body.size = size + Vector2(m, m) * 2.0
	_mat.set_shader_parameter(&"rect_size", size)
	_mat.set_shader_parameter(&"margin", m)
	_mat.set_shader_parameter(&"cell", maxf(h, 1.0))
	_mat.set_shader_parameter(&"num_center", size * 0.5)
	_mat.set_shader_parameter(&"shadow_blur", BLUR_K * h)
	_place_captions()
	near = near  # смещение тени — от новой высоты
	if is_node_ready():
		_sync_caption()  # размер подписи — от ширины кнопки


func _apply_tone() -> void:
	if body == null:
		return
	var t: Array = TONES[tone]
	body.color = t[0]
	var ink: Color = t[1]
	var sh := (t[0] as Color).darkened(SHADOW_DARK)
	sh.a = SHADOW_ALPHA
	_mat.set_shader_parameter(&"shadow_color", sh)
	var tsh := ink
	tsh.a = TEXT_SHADOW_ALPHA if tone != Tone.LIGHT else 0.0
	for l: Label in [caption, sub_caption]:
		l.add_theme_color_override(&"font_color", t[2])
		l.add_theme_color_override(&"font_outline_color", ink)
		l.add_theme_color_override(&"font_shadow_color", tsh)
	if is_node_ready():
		_sync_caption()
		_sync_look(true)


## Подпись — шрифтом темы кнопки (PillButton), переведённым текстом кнопки, размером caption_size;
## вторая строка — тем же шрифтом, размером caption_size от SUB_K·размера темы.
func _sync_caption() -> void:
	var font := get_theme_font(&"font")
	var light := tone == Tone.LIGHT
	var base := get_theme_font_size(&"font_size")
	_caption_src = text
	caption.text = atr(text)
	_style_caption(caption, font, caption_size(font, caption.text, base, light, size), light)
	sub_caption.text = subtitle
	sub_caption.visible = not subtitle.is_empty()
	_style_caption(sub_caption, font, caption_size(font, subtitle, sub_size(base), light, size), light)
	_place_captions()


## Размер второй строки при размере темы подписи base.
static func sub_size(base: int) -> int:
	return roundi(base * SUB_K)


func _style_caption(l: Label, font: Font, fs: int, light: bool) -> void:
	var o := outline_for(fs, light)
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", fs)
	l.add_theme_constant_override(&"outline_size", o)
	l.add_theme_constant_override(&"shadow_outline_size", o)
	l.add_theme_constant_override(&"shadow_offset_x", 0)
	l.add_theme_constant_override(&"shadow_offset_y", TEXT_SHADOW_Y)


## Строки над губой: одна — по центру лица; две — центры на TWO_LINE_Y высоты лица (Label по центру
## своей полосы: полоса подписи — от верха до 2·0,37, второй строки — симметрично вокруг 0,74).
func _place_captions() -> void:
	var fh := size.y * (1.0 - DEPTH_K)
	if subtitle.is_empty():
		caption.position = Vector2.ZERO
		caption.size = Vector2(size.x, fh)
		return
	var c1 := TWO_LINE_Y.x * fh
	var c2 := TWO_LINE_Y.y * fh
	var half2 := fh - c2
	caption.position = Vector2.ZERO
	caption.size = Vector2(size.x, 2.0 * c1)
	sub_caption.position = Vector2(0.0, c2 - half2)
	sub_caption.size = Vector2(size.x, 2.0 * half2)


## Размер подписи: fs (тема), а не влезает в ширину кнопки без FIT_PAD_K·h с каждой стороны (с обводкой) —
## меньше шагом 2, но не меньше MIN_FONT_K·fs. Кнопка ещё без размера — fs.
static func caption_size(font: Font, s: String, fs: int, light: bool, box: Vector2) -> int:
	if box.x <= 0.0 or box.y <= 0.0 or font == null:
		return fs
	var room := box.x - 2.0 * FIT_PAD_K * box.y
	var lo := ceili(fs * MIN_FONT_K)
	var out := fs
	while out - 2 >= lo and font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, out).x + outline_for(out, light) > room:
		out -= 2
	return out


## Полная толщина обводки подписи при размере fs (у светлой таблетки обводки нет).
static func outline_for(fs: int, light: bool) -> int:
	return 0 if light else roundi(2.0 * OUTLINE_K * fs)


## Перерисовка Button = сменилось состояние (нажатие, наведение, disabled, текст): сама кнопка пустая,
## поэтому _draw только сверяет подпись, лицо и тень с состоянием (как CandyButton).
func _draw() -> void:
	_sync_look.call_deferred()


func _sync_look(instant: bool = false) -> void:
	if face == null:
		return
	if text != _caption_src:
		_sync_caption()
	var mode := get_draw_mode()
	var dis := disabled
	var pr := not dis and (mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED)
	if not instant and pr == looks_pressed and dis == looks_disabled:
		return
	var released := looks_pressed and not pr and not dis
	looks_pressed = pr
	looks_disabled = dis
	face.modulate = Color(1.0, 1.0, 1.0, DISABLED_ALPHA if dis else 1.0)
	_set_shadow_alpha(0.0 if dis else SHADOW_ALPHA)
	var k := Vector2.ONE * (PRESSED_SCALE if pr else 1.0)
	var n := CandyButton.PRESS_NEAR if pr else 1.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if instant or not is_inside_tree():
		face.scale = k
		near = n
		return
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "near", n, CandyButton.PRESS_TIME)
	if released:
		CandyButton.tween_release(_tween, [face])
		return
	_tween.tween_property(face, "scale", k, CandyButton.PRESS_TIME).set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT)


func _set_shadow_alpha(a: float) -> void:
	var sh: Color = _mat.get_shader_parameter(&"shadow_color")
	sh.a = a
	_mat.set_shader_parameter(&"shadow_color", sh)


func _notification(what: int) -> void:
	if (what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_TRANSLATION_CHANGED) and caption != null:
		_sync_caption()
