class_name WinPanel
extends Control
## Окно победы (docs/STYLE.md, раздел 11; стиль-кадр A3B_win; 13.5b). Затемнения нет: поле с лучами и
## конфетти за ним (WinBackdrop) остаются видны, панель и лоток уезжают (Game).
##   Заголовок «УРОВЕНЬ N ПРОЙДЕН!» — Nunito 1000, белый, обводка INK, тень DEEP (как «УРОВЕНЬ N» в шапке),
##     в портрете одной строкой над полем, в альбоме — до двух строк в столбике; не влезает — мельче.
##   Карточка CandyCard 512×428 с оранжевой шапкой (места — по кадру, от верха лица карточки):
##     три звезды на кромке (боковые R 54 на ±128 с наклоном ∓14°, средняя R 73 на 18 px выше),
##     в шапке «НОВЫЙ РЕКОРД!» / «ИДЕАЛЬНО!»…, строка «звезда + "+очки"» (накручивается от 0),
##     «Всего очков: N», PillButton «ДАЛЕЕ» 380×110, ссылка «⟳ Переиграть уровень» (шириной по содержимому,
##     по центру: _place_link).
## Места задаёт раскладка: arrange(layout) из Game.apply_layout (GameLayout: win_title, win_title_size,
## win_card). Анимация — твины (STYLE 12): заголовок проявляется, карточка выезжает снизу с перелётом
## до ×1,03, звёзды по одной, очки накручиваются, затем текст и кнопки. До BUTTONS_DELAY нажатия не принимаем.
## 14.5: заработанная звезда влетает «штампом» (крупной, с поворотом — и прибивается с дожимом; числа — группа
## «Победа» в JuiceConfig), в миг касания — нота (до, ми, соль), искры вокруг звезды (свои CPUParticles2D над
## карточкой: частицы пула Juice — на FxLayer, под окном) и карточка вздрагивает. Незаработанная — тихо проявляется.
## «Меньше движения»: звёзды просто проявляются (нота и искры — вдвое меньше — остаются), карточка не вздрагивает.

signal next_pressed
## «Переиграть» — например, чтобы добрать три звезды.
signal replay_pressed

## Звёзды (13.4, STYLE 8): заработанная — star.png, недобранная — star_empty.png (без подкраски).
const STAR_ON: Texture2D = preload("res://assets/icons/star.png")
const STAR_OFF: Texture2D = preload("res://assets/icons/star_empty.png")

## Звёзды на кромке карточки: центры (от верха-левого угла лица), R — как в кадре (STYLE 11), наклон.
## Видимая ширина звезды 1,75·R, в PNG звезда занимает STAR_FIT ширины, её центр — на STAR_CY высоты.
## 07.10 (пользователь): звёзды ниже — лежат на шапке, а не касаются её (+12 боковые, +16 средняя), боковые
## ближе к средней (±148 -> ±128). Нижние лучи боковых — чуть выше заголовка шапки.
const STAR_CENTERS: Array[Vector2] = [Vector2(128.0, -8.0), Vector2(256.0, -26.0), Vector2(384.0, -8.0)]
const STAR_R: Array[float] = [54.0, 73.0, 54.0]
const STAR_TILT: Array[float] = [-14.0, 0.0, 14.0]
const STAR_FIT := 240.0 / 256.0
const STAR_CY := 0.54
## Тень звезды (STYLE 7): вниз 8q, размытие 10q, #5A2A00 35 %, q = R / 56.
const STAR_SHADOW := Color(0.353, 0.165, 0.0)
const STAR_SHADOW_ALPHA := 0.35
## Строка очков: середина по высоте, звезда (квадрат стороной SCORE_STAR до скругления), зазор до числа.
const SCORE_Y := 158.0
const SCORE_STAR := 54.0
const SCORE_GAP := 12.0
## Заголовок: обводка и тень — доли размера (HudHeader), наименьший размер при ужатии.
const TITLE_MIN_SIZE := 28
## Анимация, с от показа (STYLE 12): заголовок, карточка (выезд и перелёт), звёзды (первая, шаг; «штамп» — числа
## группы «Победа» в JuiceConfig), накрутка очков, «Всего очков», кнопки (проявление).
const TITLE_AT := 0.05
const TEXT_FADE := 0.15
const CARD_AT := 0.1
const CARD_TIME := 0.35
const CARD_OVERSHOOT := 1.03
const STARS_AT := 0.5
const STAR_STEP := 0.22
const SCORE_AT := 0.55
const SCORE_TIME := 0.6
const TOTAL_AT := 1.0
const BUTTONS_AT := 1.05
const BUTTONS_FADE := 0.2
## Кнопки проявились — с этого момента нажатия принимаются.
const BUTTONS_DELAY := 1.25
## Джингл (15.3, PLAN: «удар, потом звёзды по нотам, потом джингл»): после ноты последней звезды (≈ 1,08 с) —
## когда проявились кнопки. Музыку под ним приглушает Audio (DUCK).
const JINGLE_AT := 1.25
## Тихое появление звезды (незаработанной; при «Меньше движения» — любой): с масштаба STAR_QUIET_FROM за STAR_QUIET_TIME.
const STAR_QUIET_FROM := 0.8
const STAR_QUIET_TIME := 0.2
## Толчок карточки от удара звезды (star_punch) гаснет за PUNCH_TIME, с — не дольше STAR_STEP, чтобы толчки
## соседних звёзд не накладывались.
const PUNCH_TIME := 0.18
## Искры звезды: звёздочки star.png своим цветом (SPARKLE_COLOR — множитель), размер — доля 256 px (9–17 px),
## разлёт, px/с, время жизни, с.
const SPARKLE_COLOR := Color.WHITE
const SPARKLE_SCALE := Vector2(0.035, 0.065)
const SPARKLE_SPEED := Vector2(140.0, 300.0)
const SPARKLE_LIFE := 0.5

## Надпись в шапке карточки при первом прохождении (и переигровке без рекорда) — по звёздам 1, 2, 3
## (переводятся через tr; tools/make_po.py читает этот список).
const WIN_HEADS: Array[String] = ["ХОРОШО!", "ОТЛИЧНО!", "ИДЕАЛЬНО!"]

@onready var title_label: Label = %Title
@onready var card: CandyCard = %Card
@onready var head_label: Label = %Head
@onready var score_star: TextureRect = %ScoreStar
@onready var score_label: Label = %ScoreLabel
@onready var total_label: Label = %TotalLabel
@onready var next_button: PillButton = %NextButton
@onready var replay_button: Button = %ReplayButton
@onready var stars: Array[TextureRect] = []

## Раскладка: прямоугольники заголовка и карточки, размер заголовка, альбом ли.
var title_rect := Rect2(20.0, 50.0, 680.0, 88.0)
var title_size := 46
var title_lines := 1
var card_rect := Rect2(104.0, 786.0, 512.0, 428.0)
## Показано очков в строке «+N» (накрутка) и сколько всего.
var points_shown := 0
var points := 0
var star_count := 0
## Удары звёзд этого показа — номера по порядку (selftest: только заработанные, по одной).
var star_hits: Array[int] = []
## Джингл этого показа уже прозвучал (selftest; смена раскладки посреди показа — сразу, но один раз).
var jingled := false
## Искры над звёздами (по узлу на звезду).
var sparkles: Array[CPUParticles2D] = []

var _title_text := ""
var _tween: Tween
var _shadows: Array[TexShadow] = []


func _ready() -> void:
	stars.assign([%Star1, %Star2, %Star3])
	for i in stars.size():
		var q := STAR_R[i] / 56.0
		_shadows.append(TexShadow.attach(stars[i], Vector2(0.0, 8.0 * q), 10.0 * q, STAR_SHADOW, STAR_SHADOW_ALPHA))
	var sq := SCORE_STAR * 0.5 / 56.0
	TexShadow.attach(score_star, Vector2(0.0, 8.0 * sq), 10.0 * sq, STAR_SHADOW, STAR_SHADOW_ALPHA)
	hide()
	next_button.pressed.connect(_on_next)
	replay_button.pressed.connect(_on_replay)
	replay_button.minimum_size_changed.connect(_place_link)
	for i in stars.size():
		sparkles.append(_make_sparkle(stars[i].get_parent()))
	_place_card_content()


## Места из раскладки (GameLayout.compute): заголовок, его размер и число строк, карточка.
func arrange(layout: Dictionary) -> void:
	title_rect = layout.win_title
	title_size = layout.win_title_size
	title_lines = 2 if layout.landscape else 1
	card_rect = layout.win_card
	if not is_node_ready():
		return
	_layout_title()
	# Перестановка посреди анимации — сразу в конечное состояние, без прыжков из старых мест.
	if _tween and _tween.is_valid() and _tween.is_running():
		_finish()
	else:
		_place_card()


## points_ — результат этого прохождения; gain — на сколько вырос общий счёт
## (при переигровке только прирост к рекорду уровня); best — рекорд уровня.
## Ежедневная задача (18.1f) — show_daily: свой заголовок, вместо общего счёта — серия, кнопка «В МЕНЮ».
func show_result(level: int, star_count_: int, points_: int, total: int,
		gain: int = -1, best: int = 0) -> void:
	next_button.text = "ДАЛЕЕ"
	star_count = star_count_
	points = points_
	_title_text = tr("УРОВЕНЬ %d ПРОЙДЕН!") % level
	for i in stars.size():
		stars[i].texture = STAR_ON if i < star_count else STAR_OFF
		_shadows[i].refresh()
	var first := gain < 0 or gain >= points
	if not first and gain > 0:
		head_label.text = tr("НОВЫЙ РЕКОРД!")
		total_label.text = tr("Всего очков: %s (+%s)") % [HudHeader.format_score(total), HudHeader.format_score(gain)]
	else:
		head_label.text = tr(head_for_stars(star_count))
		if first:
			total_label.text = tr("Всего очков: %s") % HudHeader.format_score(total)
		else:
			total_label.text = tr("Рекорд уровня: %s") % HudHeader.format_score(best)
	_set_buttons_enabled(false)
	show()
	_layout_title()
	_place_card()
	_place_link()
	_set_points_shown(0)
	_play()


## Окно победы ежедневной задачи: points_ — её очки (в общий счёт не идут), streak — серия после неё.
func show_daily(star_count_: int, points_: int, streak: int) -> void:
	next_button.text = "В МЕНЮ"
	star_count = star_count_
	points = points_
	_title_text = tr("ЕЖЕДНЕВНАЯ ЗАДАЧА ПРОЙДЕНА!")
	for i in stars.size():
		stars[i].texture = STAR_ON if i < star_count else STAR_OFF
		_shadows[i].refresh()
	head_label.text = tr(head_for_stars(star_count))
	total_label.text = tr("Серия: %d") % streak
	_set_buttons_enabled(false)
	show()
	_layout_title()
	_place_card()
	_place_link()
	_set_points_shown(0)
	_play()


static func head_for_stars(n: int) -> String:
	return WIN_HEADS[clampi(n, 1, WIN_HEADS.size()) - 1]


## Число в строке очков: «+N» с разделителем разрядов; строка «звезда + число» по центру карточки.
func _set_points_shown(n: int) -> void:
	points_shown = n
	score_label.text = "+" + HudHeader.format_score(n)
	_place_score_row()


func _play() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	var h := size.y
	title_label.modulate.a = 0.0
	card.modulate.a = 1.0
	card.scale = Vector2.ONE * 0.94
	card.position = Vector2(card_rect.position.x, h + 40.0)
	star_hits.clear()
	jingled = false
	for i in stars.size():
		stars[i].modulate.a = 0.0
		stars[i].scale = Vector2.ZERO
		stars[i].rotation_degrees = STAR_TILT[i]
	score_label.pivot_offset = score_label.size * 0.5
	total_label.modulate.a = 0.0
	next_button.modulate.a = 0.0
	replay_button.modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(title_label, "modulate:a", 1.0, TEXT_FADE).set_delay(TITLE_AT)
	_tween.tween_property(card, "position:y", card_rect.position.y, CARD_TIME).set_delay(CARD_AT) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(card, "scale", Vector2.ONE * CARD_OVERSHOOT, CARD_TIME * 0.7).set_delay(CARD_AT) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(card, "scale", Vector2.ONE, CARD_TIME * 0.45).set_delay(CARD_AT + CARD_TIME * 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in stars.size():
		_play_star(i, STARS_AT + STAR_STEP * i)
	_tween.tween_method(_set_points_shown, 0, points, SCORE_TIME).set_delay(SCORE_AT) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(score_label, "scale", Vector2.ONE * 1.15, 0.08).set_delay(SCORE_AT + SCORE_TIME)
	_tween.tween_property(score_label, "scale", Vector2.ONE, 0.18).set_delay(SCORE_AT + SCORE_TIME + 0.08) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(total_label, "modulate:a", 1.0, TEXT_FADE).set_delay(TOTAL_AT)
	_tween.tween_property(next_button, "modulate:a", 1.0, BUTTONS_FADE).set_delay(BUTTONS_AT)
	_tween.tween_property(replay_button, "modulate:a", 1.0, BUTTONS_FADE).set_delay(BUTTONS_AT)
	_tween.tween_callback(_set_buttons_enabled.bind(true)).set_delay(BUTTONS_DELAY)
	_tween.tween_callback(_play_jingle).set_delay(JINGLE_AT)


func _play_jingle() -> void:
	if jingled:
		return
	jingled = true
	Audio.play(Audio.JINGLE, 0.0)


## Звезда index в момент at: заработанная — «штамп» (с масштаба star_slam и поворотом star_slam_spin — до
## ×star_slam_squash за star_slam_time, EASE_IN; удар — _on_star_hit; дожим до 1 за star_settle_time), карточка
## вздрагивает на star_punch; незаработанная или «Меньше движения» — тихо проявляется (нота у заработанной — в миг появления).
func _play_star(index: int, at: float) -> void:
	var st := stars[index]
	var earned := index < star_count
	if not earned or GameState.reduce_motion:
		st.scale = Vector2.ONE * STAR_QUIET_FROM
		_tween.tween_property(st, "modulate:a", 1.0, STAR_QUIET_TIME).set_delay(at)
		_tween.tween_property(st, "scale", Vector2.ONE, STAR_QUIET_TIME).set_delay(at) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if earned:
			_tween.tween_callback(_on_star_hit.bind(index)).set_delay(at)
		return
	var c := Juice.shared_config()
	var slam := maxf(c.star_slam_time, 0.01)
	var spin := c.star_slam_spin * (-1.0 if index % 2 == 0 else 1.0)
	st.scale = Vector2.ONE * c.star_slam
	st.rotation_degrees = STAR_TILT[index] + spin
	_tween.tween_property(st, "modulate:a", 1.0, slam * 0.5).set_delay(at)
	_tween.tween_property(st, "scale", Vector2.ONE * c.star_slam_squash, slam).set_delay(at) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(st, "rotation_degrees", STAR_TILT[index], slam).set_delay(at) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_on_star_hit.bind(index)).set_delay(at + slam)
	_tween.tween_property(st, "scale", Vector2.ONE, maxf(c.star_settle_time, 0.01)).set_delay(at + slam) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if c.star_punch > 0.0:
		_tween.tween_property(card, "position:y", card_rect.position.y, PUNCH_TIME).set_delay(at + slam) \
				.from(card_rect.position.y + c.star_punch).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Сразу конечное состояние анимации (смена раскладки посреди показа).
func _finish() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	title_label.modulate.a = 1.0
	_place_card()
	card.scale = Vector2.ONE
	for i in stars.size():
		stars[i].scale = Vector2.ONE
		stars[i].modulate.a = 1.0
		stars[i].rotation_degrees = STAR_TILT[i]
	_set_points_shown(points)
	score_label.scale = Vector2.ONE
	total_label.modulate.a = 1.0
	next_button.modulate.a = 1.0
	replay_button.modulate.a = 1.0
	_set_buttons_enabled(true)
	_play_jingle()


## Заголовок: текст переносится по словам не больше чем в title_lines строк; не влезает в ширину —
## размер уменьшается (не мельче TITLE_MIN_SIZE).
func _layout_title() -> void:
	var font := title_label.get_theme_font(&"font")
	var fs := title_size
	var lines := PackedStringArray([_title_text])
	while true:
		var room := title_rect.size.x - 2.0 * HudHeader.TITLE_OUTLINE * fs
		lines = wrap_words(_title_text, font, fs, room, title_lines)
		var fits := true
		for line in lines:
			if font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
				fits = false
		if fits or fs <= TITLE_MIN_SIZE:
			break
		fs -= 2
	title_label.text = "\n".join(lines)
	HudHeader.style_label(title_label, fs, HudHeader.TITLE_OUTLINE, HudHeader.TITLE_SHADOW, HudHeader.TITLE_SHADOW_ALPHA)
	title_label.position = title_rect.position
	title_label.size = title_rect.size


## Слова text по строкам не шире room (жадно); строк не больше max_lines — остаток уходит в последнюю.
static func wrap_words(text: String, font: Font, fs: int, room: float, max_lines: int) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for word in text.split(" ", false):
		var probe := word if cur.is_empty() else cur + " " + word
		if cur.is_empty() or out.size() >= max_lines - 1 \
				or font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= room:
			cur = probe
		else:
			out.append(cur)
			cur = word
	out.append(cur)
	return out


func _place_card() -> void:
	card.position = card_rect.position
	card.size = card_rect.size
	card.pivot_offset = card_rect.size * 0.5


## Звёзды на кромке и подписи — по местам кадра внутри лица карточки (512×428).
func _place_card_content() -> void:
	for i in stars.size():
		var box := 1.75 * STAR_R[i] / STAR_FIT
		var st := stars[i]
		st.size = Vector2(box, box)
		st.position = STAR_CENTERS[i] - Vector2(box * 0.5, box * STAR_CY)
		st.pivot_offset = Vector2(box * 0.5, box * STAR_CY)
		st.rotation_degrees = STAR_TILT[i]
	_place_score_row()
	_place_link()


## «Переиграть» шириной по содержимому (иконка icon_max_width + h_separation + текст) — по центру лица.
## Button ставит иконку к своему левому краю, а текст — по центру остатка: в широкой кнопке между ними
## была бы дыра. Иконка — без expand_icon: иначе её нет в минимальном размере (13.5e).
func _place_link() -> void:
	var w := replay_button.get_combined_minimum_size().x
	replay_button.size = Vector2(w, replay_button.size.y)
	replay_button.position.x = (card_rect.size.x - w) * 0.5


## Строка «звезда + "+N"» по центру лица: квадрат звезды SCORE_STAR, зазор SCORE_GAP, число.
func _place_score_row() -> void:
	var font := score_label.get_theme_font(&"font")
	var fs := score_label.get_theme_font_size(&"font_size")
	var tw := font.get_string_size(score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x0 := (card_rect.size.x - (SCORE_STAR + SCORE_GAP + tw)) * 0.5
	var box := 1.75 * SCORE_STAR * 0.5 / STAR_FIT
	score_star.size = Vector2(box, box)
	var cy := SCORE_Y - SCORE_STAR * 0.04
	score_star.position = Vector2(x0 + SCORE_STAR * 0.5 - box * 0.5, cy - box * STAR_CY)
	score_label.size = Vector2(ceilf(tw), 0.0)
	score_label.position = Vector2(x0 + SCORE_STAR + SCORE_GAP, SCORE_Y - score_label.size.y * 0.5)
	score_label.pivot_offset = score_label.size * 0.5


func _set_buttons_enabled(enabled: bool) -> void:
	next_button.disabled = not enabled
	replay_button.disabled = not enabled


## Enter — «Далее», как только кнопки проявились (Desktop.key_pressed: клавиша по месту).
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or next_button.disabled:
		return
	if Desktop.key_pressed(event, KEY_ENTER) or Desktop.key_pressed(event, KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		_on_next()


## Удар заработанной звезды index: нота (JuiceConfig.star_pitch — до, ми, соль) и искры вокруг неё.
func _on_star_hit(index: int) -> void:
	star_hits.append(index)
	var c := Juice.shared_config()
	Audio.play_pitched(Audio.STAR, c.star_pitch(index))
	var k := Quality.particles()  # уровень качества (14.7)
	if GameState.reduce_motion:
		k *= c.reduced_particles
	var amount := roundi(c.star_sparks * k)
	var p := sparkles[index]
	if amount >= 2:
		p.amount = amount
		p.position = STAR_CENTERS[index]
		p.restart()
		p.emitting = true


## Узел искр звезды: одна вспышка звёздочек во все стороны, над карточкой (последний ребёнок parent).
func _make_sparkle(parent: Node) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Sparkle%d" % (sparkles.size() + 1)
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.amount = maxi(Juice.shared_config().star_sparks, 2)
	p.lifetime = SPARKLE_LIFE
	p.texture = Juice.STAR_TEXTURE
	p.color = SPARKLE_COLOR
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 24.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0.0, 300.0)
	p.initial_velocity_min = SPARKLE_SPEED.x
	p.initial_velocity_max = SPARKLE_SPEED.y
	p.damping_min = 120.0
	p.damping_max = 220.0
	p.scale_amount_min = SPARKLE_SCALE.x
	p.scale_amount_max = SPARKLE_SCALE.y
	p.angle_min = -30.0
	p.angle_max = 30.0
	p.angular_velocity_min = -200.0
	p.angular_velocity_max = 200.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	ramp.add_point(0.6, Color(1.0, 1.0, 1.0, 1.0))
	p.color_ramp = ramp
	parent.add_child(p)
	return p


func _on_next() -> void:
	Audio.play(Audio.CLICK)
	# Не прячемся: пока игра ждёт рекламу, окно закрывает поле от случайных нажатий.
	# Игра сама скроет окно, когда запустит следующий уровень.
	_set_buttons_enabled(false)
	next_pressed.emit()


func _on_replay() -> void:
	Audio.play(Audio.CLICK)
	hide()
	replay_pressed.emit()
