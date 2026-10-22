class_name Toast
extends PanelContainer
## Всплывающее сообщение (13.5d, docs/STYLE.md, разделы 3, 7 и 11): тёмная плотная капсула с мягкой тенью
## и светлой кромкой сверху (тип темы Toast — StyleBoxFlat), текст — ToastText (Nunito 800, белый).
## Ширина — по тексту, не шире места от раскладки (GameLayout "toast"); не влезает в строку — две строки,
## разбитые поровну (balance_lines), капсула растёт вверх от нижнего края места.
## Появление: прозрачность 0 → 1 за FADE_IN и ×POP_FROM → 1 (TRANS_BACK, POP_TIME); новый текст
## на видимом сообщении — лёгкий «тычок» ×BUMP → 1; уход — 1 → 0 за FADE_OUT.

const FADE_IN := 0.15
const POP_FROM := 0.9
const POP_TIME := 0.25
const BUMP := 1.05
const FADE_OUT := 0.15
## Строк не больше (две — разбивка поровну; три — только если слова не делятся на две).
const MAX_LINES := 3
## Строка не начинается с тире: «Всё ещё тупик» / «— отмени ещё ход» не годится.
const NO_LINE_START: Array[String] = ["—", "–"]
## Конец предложения: разрыв после него лучше («Дальше — сам!» / «Ошибки больше не подсвечиваются»).
const SENTENCE_END := ".!?…"

@onready var _label: Label = $ToastLabel

var _area := Rect2()
var _raw := ""      # текст без переносов (переразбить, если место сменилось)
var _tween: Tween   # появление / уход
var _timer: Tween   # скрыть через duration
var _hiding := false


func _ready() -> void:
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF  # строки режет balance_lines
	_area = Rect2(position, size)  # до первой раскладки — место из сцены


## Место от раскладки: капсула по центру r по горизонтали, нижний край — по нижнему краю r.
func place(r: Rect2) -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_area = r
	if not _raw.is_empty():
		_label.text = _balanced(_raw)
	_fit()


## Показать text; через duration секунд скрыть (0 — висит, пока не скроют).
func show_text(text: String, duration: float = 0.0) -> void:
	_kill(_timer)
	var was_shown := is_shown()
	_raw = text
	_label.text = _balanced(text)
	_fit()
	_kill(_tween)
	_hiding = false
	show()
	scale = Vector2.ONE * (BUMP if was_shown else POP_FROM)
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN)
	var pop := _tween.tween_property(self, "scale", Vector2.ONE, POP_TIME)
	pop.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if duration > 0.0:
		_timer = create_tween()
		_timer.tween_interval(duration)
		_timer.tween_callback(dismiss)


func dismiss() -> void:
	_kill(_timer)
	if not visible or _hiding:
		return
	_hiding = true
	_kill(_tween)
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	_tween.tween_callback(_on_hidden)


## Видно и не уходит.
func is_shown() -> bool:
	return visible and not _hiding


## Текст на экране (с переносами строк balance_lines).
func shown_text() -> String:
	return _label.text


## Сколько px текста влезает в строку: ширина места без полей капсулы.
func text_room() -> float:
	return _area.size.x - get_theme_stylebox(&"panel").get_minimum_size().x


## Строки text через "\n": влезает в room — одна строка; иначе две по словам: если можно — по концу
## предложения, иначе — так, чтобы длинная строка была как можно короче (вторая не начинается с тире);
## среди разрывов по предложению тоже самый ровный. Слова не делятся на две — жадно, не больше MAX_LINES
## (остаток — в последнюю). Python-копия — tools/layout_model.py, toast_lines.
static func balance_lines(text: String, font: Font, font_size: int, room: float) -> String:
	if _width(text, font, font_size) <= room:
		return text
	var words := text.split(" ", false)
	var best := ""
	var best_w := INF
	var best_sentence := false
	for i in range(1, words.size()):
		if words[i] in NO_LINE_START:
			continue
		var a := " ".join(words.slice(0, i))
		var b := " ".join(words.slice(i))
		var w := maxf(_width(a, font, font_size), _width(b, font, font_size))
		var sentence := SENTENCE_END.contains(a.right(1))
		if w > room or (best_sentence and not sentence):
			continue
		if w < best_w or (sentence and not best_sentence):
			best_w = w
			best = a + "\n" + b
			best_sentence = sentence
	if not best.is_empty():
		return best
	var lines := PackedStringArray()
	var cur := ""
	for word: String in words:
		var probe: String = word if cur.is_empty() else cur + " " + word
		if cur.is_empty() or lines.size() >= MAX_LINES - 1 or _width(probe, font, font_size) <= room:
			cur = probe
		else:
			lines.append(cur)
			cur = word
	lines.append(cur)
	return "\n".join(lines)


static func _width(s: String, font: Font, font_size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _balanced(text: String) -> String:
	return balance_lines(text, _label.get_theme_font(&"font"), _label.get_theme_font_size(&"font_size"), text_room())


## Размер — наименьший для текста (текст + поля стиля), место — по центру _area, низ — по низу _area.
func _fit() -> void:
	reset_size()
	position = Vector2(roundf(_area.get_center().x - size.x * 0.5), roundf(_area.end.y - size.y))
	pivot_offset = size * 0.5


func _on_hidden() -> void:
	_hiding = false
	hide()
	scale = Vector2.ONE


static func _kill(t: Tween) -> void:
	if t and t.is_valid():
		t.kill()
