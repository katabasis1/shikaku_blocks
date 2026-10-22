extends Node
## Проигрывает звуки и фоновую музыку, отвечает за вибрацию.
## Все плееры — дочерние узлы сцены audio.tscn: музыка идёт через шину Music,
## звуки — через SFX (переключатели в настройках). Обе шины впадают в Master,
## который GameState глушит на время рекламы / скрытой вкладки.
## Имена звуков — константы ниже (опечатка в строке молча ничего не сыграет,
## а с константой её поймает редактор).
## Этап 15 (docs/STYLE.md, раздел 16): звуки «Мармелад» синтезирует tools/make_sfx.py, он же сводит громкость
## (volume_db узлов audio.tscn — по «телефонной» громкости). В вебе Godot играет звуки сэмплами Web Audio:
## эффекты шин там не работают, поэтому сведение — только в файлах и volume_db.

const PICK := &"Pick"
const PLACE := &"Place"
const NOTE := &"Note"
const ROTATE := &"Rotate"
const MISS := &"Miss"
const ERROR := &"Error"
const LINE := &"Line"
const WIN := &"Win"
const JINGLE := &"Jingle"
const CLICK := &"Click"
const UNDO := &"Undo"
const STAR := &"Star"
const HINT := &"Hint"
## Все звуки: у каждого — узел audio.tscn с этим именем (selftest и check_gd сверяют).
const SOUNDS: Array[StringName] = [PICK, PLACE, NOTE, ROTATE, MISS, ERROR, LINE, WIN, JINGLE, CLICK, UNDO, STAR,
		HINT]
## Голосов у звука (кому не указано — DEFAULT_VOICES). У голоса своя высота: хвост прошлой ноты не меняет высоту,
## когда звучит следующая (pitch_scale плеера действует на всё, что он играет). Звук берёт свободный голос,
## а если все заняты — тот, что звучит дольше всех.
const VOICES := {PLACE: 3, NOTE: 4, LINE: 3, STAR: 3, CLICK: 3}
const DEFAULT_VOICES := 2

## Нота постановки (15.2): ступени пентатоники до мажор в полутонах от C5 (note.wav) — G4 A4 C5 D5 E5 G5 A5 C6.
const PLACE_SCALE: Array[int] = [-5, -3, 0, 2, 4, 7, 9, 12]
## Ступень по площади: первая k, где площадь ≥ PLACE_AREA_MIN[k] — большой блок звучит ниже, маленький выше.
const PLACE_AREA_MIN: Array[int] = [9, 6, 4, 3, 1]
## Серия постановок: ход, поставленный не позже PLACE_STREAK_WINDOW с после прошлого, — на ступень выше
## (не больше PLACE_STREAK_MAX ступеней). Пауза дольше, отмена хода, тупик и новый уровень серию обрывают.
const PLACE_STREAK_WINDOW := 3.0
const PLACE_STREAK_MAX := 3

## Громкость фоновой музыки под звуками.
const MUSIC_VOLUME_DB := -12.0
## Насколько приглушать музыку под победу (15.3) и на сколько секунд: удар победы держит её до джингла
## (окно победы — через ≈ 1,0 с после удара, джингл — ещё через WinPanel.JINGLE_AT), джингл — до своего конца.
## Возврат — за MUSIC_RESTORE_TIME.
const MUSIC_DUCK_DB := -8.0
const DUCK := {WIN: 2.4, JINGLE: 1.3}
const MUSIC_DUCK_IN := 0.15
const MUSIC_RESTORE_TIME := 0.8
## Вибрация (15.4, PLAN 4.4; вернули 07.10): рисунок под событие — [вкл, пауза, вкл, …] в мс, как у navigator.vibrate.
## Вибрирует только там, где GameState.can_vibrate() (Android — браузер и приложение, приложение iOS), и пока она
## включена в настройках (от звука не зависит). Звуки без рисунка не вибрируют: взять, повернуть, кнопки, нота.
## Новый рисунок обрывает прежний: у хода с линией — рисунок линии, у последнего блока — победы (удар PLACE и
## LINE/WIN приходят в один кадр).
const HAPTICS := {
	PLACE: [20],                    # «тук» — блок встал
	LINE: [20, 50, 45],             # «тук-ТУК» — закрыта линия
	MISS: [12, 70, 12],             # лёгкое «тр-тр» — блок не встал и вернулся в лоток
	ERROR: [45, 70, 45],            # «бз-бз» — тупик, подсказке некуда ставить
	WIN: [30, 60, 30, 60, 110],     # «та-та-там» — удар победы
	STAR: [25],                     # звезда легла на карточку победы
}

## Для самопроверки (15.6): каждый запрос звука — и при выключенных звуках — с высотой, которую он получил.
signal requested(sound: StringName, pitch: float)

## Для самопроверки: рисунок вибрации, который попросили (вибрация включена; и там, где вибрировать нечем).
signal vibration_requested(pattern: Array)

## Для самопроверки: сколько раз звук просили сыграть (и при выключенных звуках) и последняя высота.
var requests: Dictionary = {}
var _last_pitch: Dictionary = {}

@onready var _music: AudioStreamPlayer = $Music
var _duck_tween: Tween
## Голоса звука: {звук: [AudioStreamPlayer]} и когда каждый начал играть, мс.
var _voices: Dictionary = {}
var _started: Dictionary = {}
## Номер рисунка вибрации: новый рисунок обрывает импульсы прежнего, ещё ждущие таймера (приложение).
var _haptic_gen := 0


func _ready() -> void:
	# Шины обычно приходят из default_bus_layout.tres; если файла нет — создаём сами.
	_ensure_bus(GameState.BUS_MUSIC)
	_ensure_bus(GameState.BUS_SFX)
	GameState.apply_audio()
	_make_voices()
	# Петлю включаем здесь, чтобы не зависеть от настроек импорта .ogg.
	# Трек сведён с заворотом хвостов, поэтому шов не слышен.
	var ogg := _music.stream as AudioStreamOggVorbis
	if ogg:
		ogg.loop = true
		ogg.loop_offset = 0.0
	_music.volume_db = MUSIC_VOLUME_DB
	# В браузере звук стартует после первого касания/клика — это делает сам Godot.
	_music.play()


## Голоса: узел звука из audio.tscn — первый, остальные — его копии (Note2, Note3…) с тем же файлом,
## громкостью и шиной. Голос играет одно (max_polyphony 1) — высота у него одна.
func _make_voices() -> void:
	for sound in SOUNDS:
		var base := get_node_or_null(NodePath(String(sound))) as AudioStreamPlayer
		if base == null:
			push_warning("Audio: нет звука '%s'" % sound)
			continue
		base.max_polyphony = 1
		var list: Array[AudioStreamPlayer] = [base]
		for k in range(1, int(VOICES.get(sound, DEFAULT_VOICES))):
			var v := base.duplicate() as AudioStreamPlayer
			v.name = "%s%d" % [sound, k + 1]
			add_child(v)
			list.append(v)
		_voices[sound] = list
		var starts: Array[int] = []
		starts.resize(list.size())
		starts.fill(-1000000)
		_started[sound] = starts


## Голоса звука sound (для самопроверки).
func voices(sound: StringName) -> Array[AudioStreamPlayer]:
	var res: Array[AudioStreamPlayer] = []
	res.assign(_voices.get(sound, []))
	return res


## Высота, с которой звук sound просили сыграть последний раз (0 — ещё ни разу).
func last_pitch(sound: StringName) -> float:
	return float(_last_pitch.get(sound, 0.0))


## Играет звук со случайным разбросом высоты вокруг base_pitch.
func play(sound: StringName, pitch_variation: float = 0.05, base_pitch: float = 1.0) -> void:
	var pitch := maxf(0.05, base_pitch + randf_range(-pitch_variation, pitch_variation))
	requests[sound] = int(requests.get(sound, 0)) + 1
	_last_pitch[sound] = pitch
	requested.emit(sound, pitch)
	vibrate_pattern(HAPTICS.get(sound, []))
	if not GameState.sfx_on:
		return
	var k := _free_voice(sound)
	if k < 0:
		push_warning("Audio: нет звука '%s'" % sound)
		return
	var player: AudioStreamPlayer = _voices[sound][k]
	var starts: Array = _started[sound]
	starts[k] = Time.get_ticks_msec()
	player.pitch_scale = pitch
	player.play()
	if DUCK.has(sound):
		duck_music(float(DUCK[sound]))


## Свободный голос звука (или тот, что начал раньше всех); -1 — звука нет.
## Своё время начала, а не playing: в вебе (сэмплы Web Audio) так надёжнее.
func _free_voice(sound: StringName) -> int:
	var list: Array = _voices.get(sound, [])
	if list.is_empty():
		return -1
	var starts: Array = _started[sound]
	var now := Time.get_ticks_msec()
	var oldest := 0
	for k in list.size():
		var p: AudioStreamPlayer = list[k]
		var length_ms := 1000.0 * (p.stream.get_length() if p.stream else 0.0) / maxf(p.pitch_scale, 0.05)
		if now - int(starts[k]) >= length_ms:
			return k
		if int(starts[k]) < int(starts[oldest]):
			oldest = k
	return oldest


## Приглушает музыку на duration с (под победу и джингл), потом возвращает. Повторный вызов продлевает.
func duck_music(duration: float) -> void:
	if _duck_tween and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(_music, "volume_db", MUSIC_VOLUME_DB + MUSIC_DUCK_DB, MUSIC_DUCK_IN)
	_duck_tween.tween_interval(duration)
	_duck_tween.tween_property(_music, "volume_db", MUSIC_VOLUME_DB, MUSIC_RESTORE_TIME)


## Музыка сейчас приглушена (или ещё возвращается).
func is_music_ducked() -> bool:
	return _music.volume_db < MUSIC_VOLUME_DB - 0.5


## Играет звук с точно заданной высотой (например, нарастающие звёзды).
func play_pitched(sound: StringName, pitch: float) -> void:
	play(sound, 0.0, pitch)


## Нота постановки (15.2): ступень по площади блока area плюс серия streak (0 — первый ход серии), в полутонах
## от C5. Всегда нота пентатоники до мажор (до, ре, ми, соль, ля).
static func place_semitones(area: int, streak: int) -> int:
	var step := PLACE_AREA_MIN.size() - 1
	for k in PLACE_AREA_MIN.size():
		if area >= PLACE_AREA_MIN[k]:
			step = k
			break
	step += clampi(streak, 0, PLACE_STREAK_MAX)
	return PLACE_SCALE[mini(step, PLACE_SCALE.size() - 1)]


## Высота ноты постановки для pitch_scale: 2^(полутоны / 12).
static func place_pitch(area: int, streak: int) -> float:
	return pow(2.0, float(place_semitones(area, streak)) / 12.0)


## Короткая вибрация duration_ms (проба в настройках), если она включена и устройство умеет вибрировать.
func vibrate(duration_ms: int) -> void:
	if duration_ms > 0:
		vibrate_pattern([duration_ms])


## Рисунок вибрации pattern ([вкл, пауза, вкл, …], мс), если она включена и устройство умеет вибрировать.
## Новый рисунок обрывает прежний. В браузере — navigator.vibrate(pattern) одним вызовом (паузы точнее кадра;
## в iframe Яндекс Игр работает после первого касания игры). В приложении — импульсы Input.vibrate_handheld,
## паузы — таймером.
func vibrate_pattern(pattern: Array) -> void:
	if pattern.is_empty() or not GameState.vibration_on:
		return
	vibration_requested.emit(pattern)
	if not GameState.can_vibrate():
		return
	_haptic_gen += 1
	if OS.has_feature("web"):
		if Engine.has_singleton(&"JavaScriptBridge"):
			var js = Engine.get_singleton(&"JavaScriptBridge")
			js.eval("navigator.vibrate && navigator.vibrate(%s)" % JSON.stringify(pattern), true)
		return
	# Приложение: первый импульс сразу, остальные — таймером (идёт и при паузе дерева) от начала рисунка.
	var at := 0
	for k in range(0, pattern.size(), 2):
		var on_ms := int(pattern[k])
		if k == 0:
			Input.vibrate_handheld(on_ms)
		else:
			get_tree().create_timer(float(at) / 1000.0, true).timeout.connect(_pulse.bind(on_ms, _haptic_gen))
		at += on_ms + (int(pattern[k + 1]) if k + 1 < pattern.size() else 0)


## Отложенный импульс рисунка gen (приложение): рисунок не сменился и вибрация ещё включена.
func _pulse(on_ms: int, gen: int) -> void:
	if gen == _haptic_gen and GameState.vibration_on:
		Input.vibrate_handheld(on_ms)


static func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, &"Master")
