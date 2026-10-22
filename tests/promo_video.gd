extends Node
## Сцена-видео (этап 16.5c): ролики игрового процесса для страницы Яндекс Игр — «Горизонтальное видео» 1920×1080
## и «Вертикальное видео» 1080×1920 на каждом языке (LANGS).
##
## Настоящая игра (game.tscn) и настоящие нажатия (Viewport.push_input, как в selftest): блок поворачивается
## нажатием, перетаскивается и встаёт, победа, окно победы, нажатие «ДАЛЕЕ», затем уровень другой главы до победы.
## Поверх игры — указатель: в вертикальном ролике рука обучения (касание, блок поднят над пальцем, как на
## телефоне), в горизонтальном — стрелка мыши. Подсказки, реклама и всплывающие окна в кадр не попадают.
##
## Запуск: открыть сцену tests/promo_video.tscn и нажать F6. Сцена сама перезапустит Godot с --fixed-fps 30 и
## закроется: съёмка идёт в новом окне (превью и счётчик кадров), ≈1–3 мин на ролик. Постоянный шаг нужен, потому
## что снимок кадра дольше 1/30 с — без него анимации шли бы рывками.
## Из консоли:  godot --path . --fixed-fps 30 res://tests/promo_video.tscn
## Только часть роликов:  … res://tests/promo_video.tscn -- --lang=ru --format=horizontal
## Окно съёмки не сворачивать и не переключаться на другие окна: свёрнутое окно не рисует кадры, а потеря фокуса
## бросает перетаскивание (игра так защищает игрока). Такой ролик tools/promo_video.py не соберёт и скажет почему.
##
## Кадры: docs/promo/video/frames_<формат>_<язык>/f_00000.jpg …; звуки игры по кадрам (сигнал Audio.requested) —
## events.tsv; сведения о съёмке — meta.json. Ролик mp4 со звуком игры собирает  python3 tools/promo_video.py
## (нужен ffmpeg). Сохранение и настройки игрока на время съёмки прячутся и потом возвращаются (как в promo_shots).

const GAME_SCENE := "res://scenes/game/game.tscn"
const HAND_SCENE: PackedScene = preload("res://scenes/ui/tutorial_hand.tscn")
const SELF_SCENE := "res://tests/promo_video.tscn"
const OUT_DIR := "res://docs/promo/video"
const FPS := 30
const LANGS: Array[String] = ["ru", "en", "tr"]
## Формат: имя (поле консоли «Горизонтальное видео» / «Вертикальное видео»), размер кадра, логический экран (база
## 720×1280, растяжение expand — как в promo_shots), касание (true — палец: эмуляция мыши, блок над пальцем).
const FORMATS: Array[Dictionary] = [
	{"name": "horizontal", "size": Vector2i(1920, 1080), "logical": Vector2i(2276, 1280), "touch": false},
	{"name": "vertical", "size": Vector2i(1080, 1920), "logical": Vector2i(720, 1280), "touch": true},
]
## Уровни ролика по порядку. 28 — глава 1, поле 6×7, 7 крупных блоков; 449 — глава 9 (другая тема фона), цветные
## клетки, 7×8, 7 блоков. Не первые уровни глав и не вводные уровни механики: без карточки главы и правила над полем.
const LEVELS: Array[int] = [28, 449]
## Очки за каждый пройденный уровень до ролика (общий счёт в шапке — правдоподобный, а не 0).
const SCORE_PER_LEVEL := 300
const JPG_QUALITY := 0.95
## Задержка кадра при проверке постоянного шага (_measure_fixed_fps), мс.
const DETECT_DELAY_MS := 120
## Шаг длиннее этого, с, — кадр шёл по настоящим часам: --fixed-fps нет (с задержкой шаг ≈0,12 с).
const DETECT_SLOW := 0.09
## Сколько шагов подряд должны совпасть, чтобы считать шаг постоянным; больше DETECT_MAX_FRAMES кадров не ждём.
const DETECT_SAME := 3
const DETECT_MAX_FRAMES := 30
## Тайминги, с. Ход ≈1 с: указатель к блоку, нажатие, перенос, пауза над местом (пружина догоняет, виден призрак),
## отпускание. Ролик ≈25–27 с — посчитанная длина печатается в конце.
const INTRO_WAIT := 1.5  # выезд блоков и чисел; указатель появляется под конец
const POINTER_FADE := 0.2
const REACH_TIME := 0.28
const PRESS_TIME := 0.08
const TAP_WAIT := 0.3  # после нажатия-поворота: блок докрутился
const DRAG_TIME := 0.45
const DROP_HOLD := 0.1
const MOVE_GAP := 0.08
## После последнего хода уровня (не последнего в ролике) — нажать «ДАЛЕЕ»: окно победы через Game.WIN_SHOW_AT (+ хвост
## посадки), кнопки принимают нажатия ещё через WinPanel.BUTTONS_DELAY — итого ≈2,4–2,7 с.
const NEXT_AT := 3.0
const END_HOLD := 3.8  # после последнего хода ролика — конец (окно победы и джингл почти доиграли)
## Стрелка мыши: контур в единицах ARROW_SCALE (кончик — в точке указателя).
const ARROW: Array[Vector2] = [Vector2(0, 0), Vector2(0, 21), Vector2(5, 16.5), Vector2(8.6, 24.5),
		Vector2(12, 23), Vector2(8.6, 15.2), Vector2(15, 15.2)]
const ARROW_SCALE := 2.2
const ARROW_PRESS := Vector2(0.86, 0.86)

const BACKUPS := [
	["user://save.cfg", "user://save.cfg.video_backup", "user://video_no_save.flag"],
	["user://settings.cfg", "user://settings.cfg.video_backup", "user://video_no_settings.flag"],
]

var _fps: int = FPS
var _vp: SubViewport
var _game: Game
var _fade: ColorRect
var _hand: TutorialHand
var _arrow: Node2D
var _touch: bool = false
var _ptr := Vector2.ZERO
var _pressed: bool = false
var _last_slot: int = -1
var _recording: bool = false
var _dir := ""
var _name := ""
var _frame: int = 0
var _proc_frames: int = 0
var _bad_steps: int = 0
var _misses: int = 0
var _write_errors: int = 0
var _events: PackedStringArray = []
var _had_file: Dictionary = {}
var _preview: TextureRect
var _status: Label
var _relaunched: bool = false


func _ready() -> void:
	_build_ui()
	if DisplayServer.get_name() == "headless":
		print("promo_video: в --headless кадры пустые — запустите с окном (F6 в редакторе)")
		get_tree().quit(1)
		return
	_relaunched = OS.get_cmdline_user_args().has("--relaunched")
	# Замер нарочно тормозит кадры, а с --fixed-fps 30 автоснижение видит «30 к/с» — не даём ему снизить и
	# сохранить качество игрока (съёмка и так ставит высокое, _record_all).
	Quality.set_auto(false)
	var fixed: int = await _measure_fixed_fps()
	if fixed <= 0:
		_relaunch()
		return
	_fps = fixed
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	await _record_all()


func _process(delta: float) -> void:
	if not _recording:
		return
	_proc_frames += 1
	if absf(delta - 1.0 / float(_fps)) > 0.002:
		_bad_steps += 1


## Постоянный шаг кадра (--fixed-fps N): N или 0. Из командной строки его не узнать — движок забирает
## --fixed-fps себе, в OS.get_cmdline_args() его нет. Поэтому меряем: каждый кадр нарочно держим DETECT_DELAY_MS.
## Без --fixed-fps шаг кадра тогда ≈0,12 с (больше DETECT_SLOW), с ним — 1/N, сколько бы кадр ни длился.
## Но не сразу: первые ≈6 кадров после запуска движок подгоняет шаг под такты физики (60 в секунду), и даже
## с --fixed-fps 30 шаг гуляет 0,025–0,042 с. Поэтому ждём DETECT_SAME одинаковых шагов подряд (первая версия
## брала 4 кадра сразу после запуска, видела разброс и считала, что --fixed-fps нет, — съёмка не начиналась).
func _measure_fixed_fps() -> int:
	var last := -1.0
	var same := 0
	for i in DETECT_MAX_FRAMES:
		OS.delay_msec(DETECT_DELAY_MS)
		await get_tree().process_frame
		var step := get_process_delta_time()
		if step > DETECT_SLOW:
			return 0
		same = same + 1 if absf(step - last) < 0.0005 else 0
		last = step
		if same >= DETECT_SAME:
			return roundi(1.0 / step)
	# Все шаги короче задержки — часы не настоящие, значит --fixed-fps есть, хоть шаг и не устоялся;
	# неровный шаг посчитает _process (bad_steps в meta.json).
	print("promo_video: шаг кадра не устоялся за %d кадров, последний %.4f с" % [DETECT_MAX_FRAMES, last])
	return roundi(1.0 / last)


## F6 в редакторе запускает без --fixed-fps: запускаем Godot заново с ним (тот же исполняемый файл и проект) и выходим.
func _relaunch() -> void:
	var cmd := "godot --path . --fixed-fps %d %s" % [FPS, SELF_SCENE]
	if _relaunched:
		_finish("Godot запущен без --fixed-fps. Запустите из консоли в папке проекта:\n" + cmd, 1)
		return
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", str(FPS),
			SELF_SCENE, "--"])
	args.append_array(OS.get_cmdline_user_args())
	args.append("--relaunched")
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid < 0:
		_finish("Не удалось перезапустить Godot. Запустите из консоли в папке проекта:\n" + cmd, 1)
		return
	print("promo_video: перезапуск с --fixed-fps %d — съёмка идёт в новом окне" % FPS)
	get_tree().quit(0)


func _record_all() -> void:
	var langs: Array[String] = []
	for lang in LANGS:
		if _wanted("--lang=", lang):
			langs.append(lang)
	var formats: Array[Dictionary] = []
	for fmt in FORMATS:
		if _wanted("--format=", str(fmt.name)):
			formats.append(fmt)
	var total := langs.size() * formats.size()
	if total == 0:
		_finish("Нечего снимать: --lang= — из %s, --format= — horizontal или vertical" % str(LANGS), 1)
		return
	_backup_files()
	var master := AudioServer.get_bus_index(&"Master")
	var was_muted := AudioServer.is_bus_mute(master)
	AudioServer.set_bus_mute(master, true)  # звук игры пишется списком (events.tsv), а не с колонок
	Quality.set_auto(false)
	Quality.set_level(Quality.HIGH)
	GameState.reduce_motion = false
	var lang_before := TranslationServer.get_locale()
	Audio.requested.connect(_on_sound)
	var report: Array[String] = []
	var good := 0
	var n := 0
	for fmt in formats:
		for lang in langs:
			n += 1
			GameState.set_language(lang)
			var line := await _record(fmt, lang, "%d / %d" % [n, total])
			if line.begins_with("ok"):
				good += 1
			report.append(line)
			print("  " + line)
	Audio.requested.disconnect(_on_sound)
	GameState.set_language(lang_before)
	_restore_files()
	AudioServer.set_bus_mute(master, was_muted)
	var text := "Снято роликов: %d из %d → %s\n%s\n\nДальше: python3 tools/promo_video.py — соберёт mp4 со звуком" % [
			good, total, ProjectSettings.globalize_path(OUT_DIR), "\n".join(report)]
	_finish(text, 0 if good == total else 1)


## Аргумент «-- --lang=ru,en» / «--format=vertical»: нет такого — снимаем всё.
static func _wanted(prefix: String, value: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return value in arg.trim_prefix(prefix).split(",")
	return true


## Один ролик: формат fmt, язык lang. Возвращает строку отчёта («ok …» или «FAIL …»).
func _record(fmt: Dictionary, lang: String, counter: String) -> String:
	_name = "%s_%s" % [fmt.name, lang]
	_dir = ProjectSettings.globalize_path(OUT_DIR).path_join("frames_" + _name)
	_clear_dir(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	_touch = bool(fmt.touch)
	_frame = 0
	_proc_frames = 0
	_bad_steps = 0
	_misses = 0
	_write_errors = 0
	_events.clear()
	_status.text = "%s  %s" % [counter, _name]
	_make_viewport(fmt)
	_set_progress(LEVELS[0])
	_start_game()
	_recording = true
	var failed := ""
	for k in LEVELS.size():
		if k > 0:
			await _fade_to(1.0, Transition.FADE_OUT)
			_set_progress(LEVELS[k])
			_start_game()
			await _fade_to(0.0, Transition.FADE_IN)
		var solved: bool = await _play_level(k == LEVELS.size() - 1)
		if not solved:
			failed = "уровень %d не решился" % LEVELS[k]
			break
	_recording = false
	await get_tree().process_frame
	_write_meta(fmt, lang)
	_preview.texture = null
	_vp.queue_free()
	_vp = null
	_game = null
	await get_tree().process_frame
	var skipped := _proc_frames - _frame
	var info := "%s: %d кадров, %.1f с" % [_name, _frame, float(_frame) / float(_fps)]
	if failed == "" and _misses > 0:
		failed = "блок не встал %d раз" % _misses
	if failed == "" and _bad_steps > 0:
		failed = "шаг кадра не постоянный (%d) — нужен --fixed-fps" % _bad_steps
	if failed == "" and absi(skipped) > 2:
		failed = "пропущено кадров: %d — окно сворачивали?" % skipped
	if failed == "" and _write_errors > 0:
		failed = "не записалось кадров: %d" % _write_errors
	return ("FAIL " + info + " — " + failed) if failed != "" else ("ok " + info)


## Игра в SubViewport формата fmt (как promo_shots) и слой поверх неё: затемнение между уровнями и указатель.
func _make_viewport(fmt: Dictionary) -> void:
	var logical: Vector2i = fmt.logical
	_vp = SubViewport.new()
	_vp.size = fmt.size
	_vp.size_2d_override = logical
	_vp.size_2d_override_stretch = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_preview.texture = _vp.get_texture()
	var top := CanvasLayer.new()
	top.layer = 120
	_vp.add_child(top)
	# Всё на слое — без ввода: нажатия идут в игру под ним.
	_fade = ColorRect.new()
	_fade.color = Transition.COLOR
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.size = Vector2(logical)
	_fade.modulate.a = 0.0
	top.add_child(_fade)
	_hand = HAND_SCENE.instantiate() as TutorialHand
	top.add_child(_hand)  # _ready прячет; круг «касания» — и для мыши
	_hand.hand.visible = _touch
	_arrow = _make_arrow()
	_arrow.visible = false
	top.add_child(_arrow)
	_pressed = false
	_last_slot = -1
	_ptr = Vector2(logical) * 0.5


## Стрелка мыши из многоугольников: тень, белая заливка, тёмный контур.
func _make_arrow() -> Node2D:
	var node := Node2D.new()
	var pts := PackedVector2Array()
	for p in ARROW:
		pts.append(p * ARROW_SCALE)
	var shadow := Polygon2D.new()
	shadow.polygon = pts
	shadow.color = Color(0.0, 0.0, 0.0, 0.28)
	shadow.position = Vector2(3.0, 4.0)
	shadow.antialiased = true
	node.add_child(shadow)
	var fill := Polygon2D.new()
	fill.polygon = pts
	fill.color = Color.WHITE
	fill.antialiased = true
	node.add_child(fill)
	var outline := Line2D.new()
	outline.points = pts
	outline.closed = true
	outline.width = 3.0
	outline.default_color = Color(0.1, 0.08, 0.16)
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	outline.antialiased = true
	node.add_child(outline)
	return node


## Прогресс «пройдены уровни 1..level-1 на 3 звезды», обучение пройдено (как promo_shots).
func _set_progress(level: int) -> void:
	GameState.reset_progress()
	for i in range(1, level):
		GameState.complete_level(i, 3, SCORE_PER_LEVEL)
	GameState.tutorial = Tutorial.ALL
	GameState.save_game()


## Новая игра (уровень GameState.level) под слоем; прошлая уходит.
func _start_game() -> void:
	if _game != null:
		_game.queue_free()
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_vp.add_child(_game)
	_vp.move_child(_game, 0)
	_game.coach.countdown = 1.0e9
	_last_slot = -1


## Уровень до победы ходами по решению. last — последний в ролике: окно победы до конца; иначе — нажать «ДАЛЕЕ».
func _play_level(last: bool) -> bool:
	await _wait(INTRO_WAIT)
	var guard := 0
	while not _game.finished:
		guard += 1
		var m := _next_move()
		if m.is_empty() or guard > 40:
			push_warning("promo_video: нет хода на уровне %d" % GameState.level)
			return false
		if not _pointer_shown():
			var near := _slot_center(int(m.slot))
			await _show_pointer(near.lerp(Vector2(_vp.size_2d_override) * 0.5, 0.25))
		await _do_move(m)
		_game.coach.countdown = 1.0e9
	if last:
		await _hide_pointer()
		await _wait(END_HOLD - POINTER_FADE)
		return true
	await _wait(NEXT_AT - REACH_TIME * 1.5 - PRESS_TIME)
	await _glide(_center(_game.win_panel.next_button), REACH_TIME * 1.5)
	await _tap()
	return true  # указатель гаснет вместе с затемнением (_fade_to)


## Ход по решению из оставшихся блоков: {slot, rect} или {}. Слоты — по кругу после прошлого хода, чтобы указатель
## не ходил всё время к одному и тому же блоку.
func _next_move() -> Dictionary:
	var s := _game.solve(_game.placed_rects(), _game.remaining_pieces())
	var rects: Array = s.solution if s.status == ShikakuSolver.SOLVED else _game.level_data.solution
	var count := _game.tray.blocks.size()
	for k in count:
		var i := (_last_slot + 1 + k) % count
		var b: Block = _game.tray.blocks[i]
		if b == null:
			continue
		for item in rects:
			var r: Rect2i = item
			var fits := r.size == b.cells or r.size == Vector2i(b.cells.y, b.cells.x)
			if fits and _game.board.check_rect(r):
				_last_slot = i
				return {"slot": i, "rect": r}
	return {}


## Ход как у игрока: к блоку, нажатие-поворот (если нужен), нажать — перенести — подержать над местом — отпустить.
func _do_move(m: Dictionary) -> void:
	var slot: int = m.slot
	var r: Rect2i = m.rect
	var b: Block = _game.tray.blocks[slot]
	await _glide(_slot_center(slot), REACH_TIME)
	if r.size != b.cells:
		await _tap()
		await _wait(TAP_WAIT)
	var before := _game.moves.size()
	_press(true)
	await _wait(PRESS_TIME)
	await _glide(_drop_point(b, r), DRAG_TIME)
	await _wait(DROP_HOLD)
	_press(false)
	await _wait(MOVE_GAP)
	if _game.moves.size() == before:
		_misses += 1
		push_warning("promo_video: %s — блок не встал (кадр %d)" % [_name, _frame])


## Куда вести указатель, чтобы середина поднятого блока пришлась на середину места r (DragController._drag_offset:
## мышь держит блок за середину, палец — снизу, блок на TOUCH_LIFT выше пальца).
func _drop_point(b: Block, r: Rect2i) -> Vector2:
	var board := _game.board
	var local := (Vector2(r.position) + Vector2(r.size) * 0.5) * Block.CELL
	var at := board.get_global_transform_with_canvas() * local
	if not _touch:
		return at
	var lifted := Vector2(b.cells) * Block.CELL * board.get_global_transform().get_scale() * Block.LIFT_SCALE
	return at + Vector2(0.0, lifted.y * 0.5 + DragController.TOUCH_LIFT)


func _slot_center(slot: int) -> Vector2:
	return _center(_game.tray.slots[slot])


func _center(c: Control) -> Vector2:
	return c.get_global_transform_with_canvas() * (c.size * 0.5)


# --- Указатель и ввод ---------------------------------------------------------

func _pointer_shown() -> bool:
	return _hand.visible


func _show_pointer(at: Vector2) -> void:
	_set_pointer(at)
	_hand.modulate.a = 0.0
	_hand.show()
	_arrow.modulate.a = 0.0
	_arrow.visible = not _touch
	await _tween_alpha(1.0)


func _hide_pointer() -> void:
	await _tween_alpha(0.0)
	_hand.hide()
	_arrow.visible = false


func _tween_alpha(a: float) -> void:
	var from := _hand.modulate.a
	var n := maxi(1, roundi(POINTER_FADE * _fps))
	for i in n:
		await get_tree().process_frame
		var v := lerpf(from, a, float(i + 1) / float(n))
		_hand.modulate.a = v
		_arrow.modulate.a = v


func _set_pointer(at: Vector2) -> void:
	_ptr = at
	_hand.position = at
	_arrow.position = at


## Указатель плавно (smoothstep) в точку to за t с; каждый кадр — движение мыши (с зажатой кнопкой, если нажато).
## Касание без нажатия событий не шлёт: палец над экраном не «водит».
func _glide(to: Vector2, t: float) -> void:
	var from := _ptr
	var n := maxi(1, roundi(t * _fps))
	for i in n:
		await get_tree().process_frame
		var k := float(i + 1) / float(n)
		var prev := _ptr
		_set_pointer(from.lerp(to, k * k * (3.0 - 2.0 * k)))
		if _pressed or not _touch:
			var mm := InputEventMouseMotion.new()
			mm.device = InputEvent.DEVICE_ID_EMULATION if _touch else 0
			mm.button_mask = MOUSE_BUTTON_MASK_LEFT if _pressed else 0
			mm.position = _ptr
			mm.global_position = _ptr
			mm.relative = _ptr - prev
			mm.velocity = (_ptr - prev) * float(_fps)
			_vp.push_input(mm, true)


## Нажатие (down = true) или отпускание левой кнопки / пальца в точке указателя.
func _press(down: bool) -> void:
	_pressed = down
	var ev := InputEventMouseButton.new()
	ev.device = InputEvent.DEVICE_ID_EMULATION if _touch else 0
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	ev.pressed = down
	ev.position = _ptr
	ev.global_position = _ptr
	_vp.push_input(ev, true)
	var t := create_tween().set_parallel()
	t.tween_property(_hand.hand, "scale", TutorialHand.PRESS_SCALE if down else Vector2.ONE, TutorialHand.TAP_TIME)
	t.tween_property(_arrow, "scale", ARROW_PRESS if down else Vector2.ONE, TutorialHand.TAP_TIME)
	if down:
		_hand._ring_pulse()


## Нажать и отпустить на месте (поворот блока в лотке, кнопка).
func _tap() -> void:
	_press(true)
	await _wait(PRESS_TIME)
	_press(false)
	await _wait(TutorialHand.TAP_TIME)


## t секунд игрового времени — при постоянном шаге это ровно столько кадров.
func _wait(t: float) -> void:
	for _i in maxi(1, roundi(t * _fps)):
		await get_tree().process_frame


## Затемнение между уровнями (цвет и время — как у Transition). При затемнении указатель гаснет вместе с ним.
func _fade_to(a: float, t: float) -> void:
	var from := _fade.modulate.a
	var ptr_from := _hand.modulate.a
	var n := maxi(1, roundi(t * _fps))
	for i in n:
		await get_tree().process_frame
		var k := float(i + 1) / float(n)
		_fade.modulate.a = lerpf(from, a, k)
		if a > 0.5 and _pointer_shown():
			_hand.modulate.a = lerpf(ptr_from, 0.0, k)
			_arrow.modulate.a = _hand.modulate.a
	if a > 0.5:
		_hand.hide()
		_arrow.visible = false


# --- Запись -------------------------------------------------------------------

## Кадр нарисован: снимок SubViewport — в JPG (PNG 1920×1080 на каждый кадр — слишком медленно и много места).
func _on_post_draw() -> void:
	if not _recording or _vp == null:
		return
	var img := _vp.get_texture().get_image()
	if img == null or img.is_empty():
		_write_errors += 1
	else:
		img.convert(Image.FORMAT_RGB8)
		if img.save_jpg(_dir.path_join("f_%05d.jpg" % _frame), JPG_QUALITY) != OK:
			_write_errors += 1
	_frame += 1
	if _frame % 10 == 0:
		_status.text = "%s  %s  кадр %d (%.1f с)" % [_status.text.get_slice("  ", 0), _name, _frame,
				float(_frame) / float(_fps)]


## Звук игры (Audio.requested): номер кадра, который сейчас рисуется, имя и высота — для сведения в promo_video.py.
func _on_sound(sound: StringName, pitch: float) -> void:
	if _recording:
		_events.append("%d\t%s\t%.4f" % [_frame, sound, pitch])


func _write_meta(fmt: Dictionary, lang: String) -> void:
	var f := FileAccess.open(_dir.path_join("events.tsv"), FileAccess.WRITE)
	if f != null:
		f.store_string("# кадр\tзвук\tвысота (pitch_scale)\n" + "\n".join(_events) + "\n")
		f.close()
	var size: Vector2i = fmt.size
	var meta := {
		"format": fmt.name, "lang": lang, "fps": _fps, "width": size.x, "height": size.y,
		"frames": _frame, "pattern": "f_%05d.jpg", "levels": LEVELS, "misses": _misses,
		"bad_steps": _bad_steps, "skipped": _proc_frames - _frame, "write_errors": _write_errors,
		"godot": Engine.get_version_info().get("string", ""),
	}
	f = FileAccess.open(_dir.path_join("meta.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(meta, "\t") + "\n")
		f.close()


## Старые кадры этого ролика — удалить (иначе хвост прошлой, более длинной съёмки попал бы в ролик).
static func _clear_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for file in d.get_files():
		d.remove(file)


# --- Окно ---------------------------------------------------------------------

func _build_ui() -> void:
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ui)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.1, 0.18)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_preview)
	_status = Label.new()
	_status.position = Vector2(16, 12)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size = Vector2(get_viewport().get_visible_rect().size.x - 32.0, 0.0)
	_status.add_theme_font_size_override(&"font_size", 22)
	ui.add_child(_status)


## Итог: в консоль и в окно. Перезапущенное окно (F6) остаётся открытым с итогом — его закрывают сами;
## запуск из консоли выходит с кодом code.
func _finish(text: String, code: int) -> void:
	print("promo_video: " + text)
	_status.text = text + ("\n\nОкно можно закрыть." if _relaunched else "")
	if not _relaunched:
		get_tree().quit(code)


# --- Сохранение игрока --------------------------------------------------------

## Прячем настоящие сохранение и настройки игрока (как promo_shots._backup_files).
func _backup_files() -> void:
	for entry: Array in BACKUPS:
		var path: String = entry[0]
		var backup: String = entry[1]
		var flag: String = entry[2]
		if FileAccess.file_exists(backup):
			_had_file[path] = true  # прошлая съёмка оборвалась: копия — настоящий файл
		elif FileAccess.file_exists(flag):
			_had_file[path] = false
		elif FileAccess.file_exists(path):
			_had_file[path] = true
			_copy_file(path, backup)
		else:
			_had_file[path] = false
			var f := FileAccess.open(flag, FileAccess.WRITE)
			if f != null:
				f.store_string("1")
				f.close()


func _restore_files() -> void:
	for entry: Array in BACKUPS:
		var path: String = entry[0]
		var backup: String = entry[1]
		var flag: String = entry[2]
		if bool(_had_file.get(path, false)):
			if FileAccess.file_exists(backup):
				_copy_file(backup, path)
				DirAccess.remove_absolute(backup)
		else:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
			DirAccess.remove_absolute(flag)
	GameState.load_game()
	GameState.load_settings()


static func _copy_file(from: String, to: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(from)
	var f := FileAccess.open(to, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()
