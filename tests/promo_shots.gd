extends Node
## Сцена-витрина (этап 16.5b): настоящие скриншоты игры для страницы Яндекс Игр.
##
## Из редактора: открыть сцену tests/promo_shots.tscn и нажать F6 («Запустить текущую сцену»). Нужен обычный запуск
## с окном (не --headless: без видеокарты кадр пустой). Идёт ≈3 мин, в окне — превью и счётчик; звук выключен.
## Из консоли:  godot --path . res://tests/promo_shots.tscn
##
## Что делает: для каждого кадра SHOTS ставит прогресс «пройдено до уровня», открывает игру (game.tscn) с этим
## уровнем, ставит часть блоков по решению, ждёт, пока улягутся эффекты, и сохраняет кадр — на каждом языке
## (LANGS) в двух форматах (FORMATS): телефон 1080×1920 (портрет) и компьютер 1920×1080 (16:9, раскладка «альбом»).
## Игра рисуется в SubViewport нужного размера с тем же растяжением, что окно (canvas_items, expand): размер
## монитора не важен. Файлы: docs/promo/shots/<формат>_<язык>_<N>.png (RGB). Проверка — tools/promo_check.py.
##
## Сохранение и настройки игрока (user://save.cfg, settings.cfg) на время съёмки прячутся и потом возвращаются, как в
## selftest; оборвали съёмку — следующий запуск сначала вернёт их.

const GAME_SCENE := "res://scenes/game/game.tscn"
const OUT_DIR := "res://docs/promo/shots"
const LANGS: Array[String] = ["ru", "en", "tr"]
## Формат: имя, размер кадра, логический экран (база 720×1280, растяжение expand: меньшая сторона вписывается).
const FORMATS: Array[Dictionary] = [
	{"name": "phone", "size": Vector2i(1080, 1920), "logical": Vector2i(720, 1280)},
	{"name": "desktop", "size": Vector2i(1920, 1080), "logical": Vector2i(2276, 1280)},
]
## Кадры: уровень и доля блоков решения на поле. Разные главы — разные темы фона; 275 — цветные клетки (глава 6),
## 340 — «?» (глава 7). Не первые уровни глав: без карточки главы и правила над полем.
const SHOTS: Array[Dictionary] = [
	{"level": 24, "placed": 0.5},
	{"level": 135, "placed": 0.6},
	{"level": 275, "placed": 0.45},
	{"level": 340, "placed": 0.55},
]
## Очки за каждый пройденный уровень до кадра (общий счёт в шапке — правдоподобный, а не 0).
const SCORE_PER_LEVEL := 300
## Ожидание: выезд блоков и чисел (до ≈2 с на поле 7×8), между ходами, после последнего хода (текст очков, волны).
const INTRO_WAIT := 2.6
const MOVE_GAP := 0.12
const SETTLE_WAIT := 3.0

const BACKUPS := [
	["user://save.cfg", "user://save.cfg.promo_backup", "user://promo_no_save.flag"],
	["user://settings.cfg", "user://settings.cfg.promo_backup", "user://promo_no_settings.flag"],
]

var _had_file: Dictionary = {}
var _preview: TextureRect
var _status: Label
var _saved: Array[String] = []


func _ready() -> void:
	_build_ui()
	if DisplayServer.get_name() == "headless":
		print("promo_shots: в --headless кадры пустые — запустите с окном (F6 в редакторе)")
		get_tree().quit(1)
		return
	_backup_files()
	var master := AudioServer.get_bus_index(&"Master")
	var was_muted := AudioServer.is_bus_mute(master)
	AudioServer.set_bus_mute(master, true)
	Quality.set_auto(false)
	Quality.set_level(Quality.HIGH)
	GameState.reduce_motion = false
	var lang_before := TranslationServer.get_locale()
	var total := SHOTS.size() * LANGS.size() * FORMATS.size()
	var dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	for si in SHOTS.size():
		var shot: Dictionary = SHOTS[si]
		_set_progress(int(shot.level))
		for lang in LANGS:
			GameState.set_language(lang)
			for fmt in FORMATS:
				var file := "%s_%s_%d.png" % [fmt.name, lang, si + 1]
				_status.text = "%d / %d  %s" % [_saved.size() + 1, total, file]
				var img := await _capture(shot, fmt)
				if img == null:
					print("  [FAIL] %s: пустой кадр" % file)
					continue
				var err := img.save_png(dir.path_join(file))
				if err != OK:
					print("  [FAIL] %s: не записался (%s)" % [file, error_string(err)])
					continue
				_saved.append(file)
				print("  %s  %d×%d" % [file, img.get_width(), img.get_height()])
	GameState.set_language(lang_before)
	_restore_files()
	AudioServer.set_bus_mute(master, was_muted)
	print("promo_shots: %d из %d кадров → %s" % [_saved.size(), total, dir])
	print("Проверка: python3 tools/promo_check.py")
	get_tree().quit(0 if _saved.size() == total else 1)


## Прогресс «пройдены уровни 1..level-1 на 3 звезды», обучение пройдено: рука и подсказки-напутствия не появятся.
func _set_progress(level: int) -> void:
	GameState.reset_progress()
	for i in range(1, level):
		GameState.complete_level(i, 3, SCORE_PER_LEVEL)
	GameState.tutorial = Tutorial.ALL
	GameState.save_game()


## Один кадр: игра в SubViewport формата fmt, уровень shot.level (текущий по прогрессу), доля shot.placed блоков
## решения на поле. Возвращает картинку RGB или null.
func _capture(shot: Dictionary, fmt: Dictionary) -> Image:
	var vp := SubViewport.new()
	vp.size = fmt.size
	vp.size_2d_override = fmt.logical
	vp.size_2d_override_stretch = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	_preview.texture = vp.get_texture()
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	vp.add_child(game)  # _ready: уровень GameState.level = shot.level
	game.coach.countdown = 1.0e9
	await get_tree().create_timer(INTRO_WAIT).timeout
	var want := int(round(float(shot.placed) * float((game.level_data.solution as Array).size())))
	var placed := 0
	while placed < want and not game.finished:
		if not _solution_move(game):
			break
		placed += 1
		await get_tree().create_timer(MOVE_GAP).timeout
	game.coach.countdown = 1.0e9
	await get_tree().create_timer(SETTLE_WAIT).timeout
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	_preview.texture = null
	vp.queue_free()
	await get_tree().process_frame
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGB8)
	return img


## Ход по решению (как selftest._play_solution_move): блок из лотка — на его место. false — хода нет.
func _solution_move(game: Game) -> bool:
	var s := game.solve(game.placed_rects(), game.remaining_pieces())
	var rects: Array = s.solution if s.status == ShikakuSolver.SOLVED else game.level_data.solution
	var m := game.tray.find_move(rects, game.board)
	if m.is_empty():
		return false
	var slot: int = m.slot
	var r: Rect2i = m.rect
	var b: Block = game.tray.blocks[slot]
	if r.size != b.cells:
		b.rotate_cells()
	game.commit_place(b, slot, r)
	return true


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
	_status.add_theme_font_size_override(&"font_size", 28)
	ui.add_child(_status)


## Прячем настоящие сохранение и настройки игрока (как selftest._backup_save).
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
	# Память игры — снова из файлов игрока (иначе выход из сцены мог бы записать прогресс съёмки).
	GameState.load_game()
	GameState.load_settings()


static func _copy_file(from: String, to: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(from)
	var f := FileAccess.open(to, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()
