class_name JuiceConfig
extends Resource
## Числа эффектов (этап 14, PLAN 4.4–4.5, docs/STYLE.md, раздел 12) — в одном ресурсе theme/juice.tres,
## чтобы подстраивать «сочность» без правки кода. Узел Juice (scenes/game/juice.gd) читает его при запуске.
## «Без эффектов» (14.8a, в конце файла): set_effects_off(true) ставит числа OFF, при которых эффектов нет, — логика
## игры от них не зависит; set_effects_off(false) возвращает прежние. Новое число — решить, куда оно: в OFF или
## в KEEP_ON_OFF (иначе — ошибка самопроверки и tools/check_gd.py).

@export_group("Тряска")
## Наибольшее смещение Content при «травме» 1, px. Смещение = shake_max · травма² (слабые удары почти не трясут).
@export var shake_max := 8.0
## Сколько «травмы» уходит за секунду (1 → 0 за 1 / shake_decay с).
@export var shake_decay := 3.0
## Частота дрожания, Гц.
@export var shake_freq := 22.0
## «Травма» по событиям: поставлен блок (поле вздрагивает на 2–4 px: 8 · 0,6² ≈ 2,9), линия, победа.
@export var trauma_place := 0.6
@export var trauma_line := 0.75
@export var trauma_win := 0.85

@export_group("Hit-stop")
## Пауза твинов и частиц эффектов в момент удара, с (логика игры не останавливается). PLAN 4.4: победа — 60–80 мс.
@export var hitstop_place := 0.0
@export var hitstop_line := 0.04
@export var hitstop_win := 0.07
## Дольше этого hit-stop не бывает, даже если удары идут подряд, с.
@export var hitstop_max := 0.12

@export_group("Частицы")
## Предел частиц на экране сразу (PLAN 4.5: 150–200). Вспышка, которой не хватает места, урезается или пропускается.
@export var particles_max := 180
## Узлов CPUParticles2D в пуле (одновременных вспышек).
@export var pool_size := 12
## Частиц во вспышке: пыль из-под краёв поставленного блока (+ dust_per_cell на клетку, группа «Удар и промах»),
## искры линии, звёздочки победы. Звёздочки удара победы убраны 04.10 (14.8e, по просьбе пользователя: «излишне») —
## 0; вернуть — 12.
@export var dust_amount := 6
@export var sparks_amount := 16
@export var stars_amount := 0
## Время жизни частиц, с.
@export var dust_life := 0.45
@export var sparks_life := 0.6
@export var stars_life := 0.9
## Доля конфетти победы (Confetti: Confetti.COUNT · confetti_share · доля качества · «Меньше движения»).
@export var confetti_share := 1.0

@export_group("Блок в руке")
## Взять (14.2): Visual блока на миг вытягивается до pick_hop и пружинит обратно за pick_time, с
## (масштаб ×Block.LIFT_SCALE и тень «поднят» — отдельно, DragController.LIFT_TIME).
@export var pick_hop := Vector2(0.95, 1.06)
@export var pick_time := 0.18
## Нести: блок едет за пальцем на пружине — жёсткость carry_stiffness (ω, рад/с) и затухание carry_damping
## (1 — без перелёта, меньше — лёгкий перелёт). Отставание при скорости v ≈ 2 · затухание · v / ω
## (1000 px/с → ≈ 30 px). Цель (призрак) считается по пальцу, а не по отставшему блоку.
@export var carry_stiffness := 55.0
@export var carry_damping := 0.8
## Наклон в сторону движения (STYLE 12): до tilt_max градусов, tilt_per_speed градусов на 1 px/с скорости,
## к нулю — за tilt_return с.
@export var tilt_max := 5.0
@export var tilt_per_speed := 0.006
@export var tilt_return := 0.15
## Магнит: над допустимым местом блок смещается к нему на эту долю пути (0 — нет, 1 — встаёт ровно на место).
@export var magnet_pull := 0.3
## «Щелчок» нового допустимого места: призрак ×(1 + snap_hop) и обратно, число под ним — так же, за snap_time, с.
@export var snap_hop := 0.08
@export var snap_time := 0.14

@export_group("Удар и промах")
## Поставить: блок долетает до места за land_time, с, — в этот миг удар (тряска, пыль, звук) и сплющивание
## ×land_squash, обратно с дожимом за squash_time, с (STYLE 12: ×(1,06; 0,94) за 0,12 с).
@export var land_time := 0.12
@export var land_squash := Vector2(1.06, 0.94)
@export var squash_time := 0.12
## Пыль из-под краёв: dust_amount + dust_per_cell · (ширина + высота блока в клетках) частиц.
@export var dust_per_cell := 2
## Промах: блок «мотает головой» — качается до miss_wobble градусов, затухая, за miss_time, с.
@export var miss_wobble := 9.0
@export var miss_time := 0.36
## Возврат в лоток (промах, бросок мимо, отмена хода) по дуге: высота дуги — return_arc от длины пути,
## не меньше return_arc_min px, за return_time, с.
@export var return_arc := 0.25
@export var return_arc_min := 30.0
@export var return_time := 0.3
## Поворот: быстрый (rotate_time, с) с дожимом; край блока в начале поворота размыт на rotate_smear клетки
## («смаз»), к концу — чёткий.
@export var rotate_time := 0.17
@export var rotate_smear := 0.09

@export_group("Закрытое число")
## Блок встал — его число закрыто (14.3, PLAN 4.4): цифра вспыхивает — растёт до ×close_pop и светлеет
## (modulate ×close_flash) за close_pop_time, с, — и сменяется галочкой (смена — close_swap, с); галочка видна
## close_hold, с, и уступает место цифре. Цифра остаётся: закрыто каждое число поля, стереть их нельзя.
@export var close_pop := 1.25
@export var close_flash := 1.6
@export var close_pop_time := 0.08
@export var close_swap := 0.1
@export var close_hold := 0.35
## Свет по клеткам блока: волна от числа к краям за glow_time, с; за ней клетки коротко светлеют. Сила — glow_strength
## (0 — нет, 1 — до светлого тона площади). При «Меньше движения» волны нет.
@export var glow_time := 0.4
@export var glow_strength := 0.8

@export_group("Линия и серия")
## Линия (строка или столбец поля) закрыта (14.4, PLAN 4.4): от поставленного блока к концам линии бежит волна
## света (shaders/line_wave.gdshader) — фронт доходит до дальнего конца за line_wave_time, с; светлая полоса
## шириной line_wave_width клетки, за ней — след яркостью line_trail от полосы; после прихода фронта всё гаснет
## за line_fade, с. Сила волны — line_wave_strength (0 — нет, 1 — белая полоса). Блоки линии вспыхивают
## (line_block_flash, 0…1), когда до них доходит фронт. Искры — вдоль всей линии: sparks_amount (группа
## «Частицы») + line_sparks_per_cell на клетку её длины.
@export var line_wave_time := 0.3
@export var line_wave_width := 1.2
@export var line_trail := 0.35
@export var line_fade := 0.25
@export var line_wave_strength := 0.75
@export var line_block_flash := 0.55
@export var line_sparks_per_cell := 2
## Серия — ходы подряд, каждый из которых закрыл линию; ход без линии её обрывает, отмена хода возвращает прежнюю.
## Сила хода = (линий за ход − 1) + (длина серии − 1), от 0 до combo_max. Очки от неё не зависят — только эффекты.
## С каждой единицей силы: волна ярче на combo_wave и вспышка блоков — на combo_flash, тряска (травма) больше
## на combo_trauma, hit-stop дольше на combo_hitstop, с (но не дольше hitstop_max), искр больше на долю combo_sparks.
@export var combo_max := 4
@export var combo_wave := 0.06
@export var combo_flash := 0.05
@export var combo_trauma := 0.05
@export var combo_hitstop := 0.01
@export var combo_sparks := 0.4
## Звук линии выше с силой хода: на combo_semitones[сила] полутонов (до мажор: до, ре, ми, фа, соль).
@export var combo_semitones := PackedInt32Array([0, 2, 4, 5, 7])
## Текст комбо (слово по силе — Game.COMBO_WORDS): шрифт combo_text_size px и + combo_text_grow на единицу силы.
## «Штамп» в миг удара: текст влетает с масштабом combo_slam (+ combo_slam_grow на единицу силы) и за
## combo_slam_time, с, прибивается до 1 с дожимом; в миг касания — тряска с травмой combo_slam_trauma.
@export var combo_text_size := 54
@export var combo_text_grow := 4
@export var combo_slam := 1.7
@export var combo_slam_grow := 0.1
@export var combo_slam_time := 0.16
@export var combo_slam_trauma := 0.45


## Сила хода (14.4): lines — линий закрыто этим ходом, streak — длина серии вместе с ним; −1 — линий нет.
func combo_power(lines: int, streak: int) -> int:
	if lines <= 0:
		return -1
	return clampi(lines - 1 + maxi(streak, 1) - 1, 0, maxi(combo_max, 0))


## Высота звука линии при силе power: 2^(полутоны / 12).
func combo_pitch(power: int) -> float:
	if combo_semitones.is_empty() or power < 0:
		return 1.0
	return pow(2.0, float(combo_semitones[mini(power, combo_semitones.size() - 1)]) / 12.0)


@export_group("Победа")
## Удар победы (14.5, PLAN 4.4) — в миг касания последнего блока: тряска trauma_win и hit-stop hitstop_win (группы
## «Тряска» и «Hit-stop»), звёздочки stars_amount (с 14.8e — 0, убраны). Затем волна по полю (shaders/win_wave.gdshader): кольцо света от
## последнего блока к дальнему углу поля — фронт доходит за win_wave_time, с, замедляясь к концу; полоса шириной
## win_wave_width клетки, за ней след win_trail от полосы; дошёл — всё гаснет за win_fade, с. Сила — win_wave_strength.
@export var win_wave_time := 0.55
@export var win_wave_width := 1.6
@export var win_trail := 0.3
@export var win_fade := 0.3
@export var win_wave_strength := 0.85
## Блоки вспыхивают (win_block_flash, 0…1) и подпрыгивают до ×(1 + win_block_pop), когда до них доходит фронт.
@export var win_block_flash := 0.7
@export var win_block_pop := 0.14
## Мозаика: через win_merge_delay, с, после фронта блок за win_merge_time, с, сходится с соседями — зазор до
## win_merge_gap, скругление до win_merge_radius (доли клетки; у блока 0,045 и 0,24), швы между клетками гаснут.
## win_mosaic — мозаика есть. Убрана 04.10 (14.8e, по просьбе пользователя: «излишне») — false; вернуть — true,
## остальные числа мозаики не тронуты.
@export var win_mosaic := false
@export var win_merge_delay := 0.1
@export var win_merge_time := 0.3
@export var win_merge_gap := 0.006
@export var win_merge_radius := 0.07
## Звёзды окна победы — «штампом» по одной: влетает с масштабом star_slam и поворотом star_slam_spin, градусов,
## за star_slam_time, с, прибивается до ×star_slam_squash (EASE_IN) и с дожимом встаёт за star_settle_time, с.
## В миг касания — нота: звук звезды выше на star_semitones[номер] полутонов (до, ми, соль), star_sparks искр
## вокруг звезды, карточка вздрагивает вниз на star_punch px. Незаработанная звезда появляется тихо, без удара.
@export var star_slam := 2.4
@export var star_slam_spin := 25.0
@export var star_slam_time := 0.14
@export var star_slam_squash := 0.88
@export var star_settle_time := 0.16
@export var star_semitones := PackedInt32Array([0, 4, 7])
@export var star_sparks := 14
@export var star_punch := 6.0


## Высота звука звезды номер index (0…2) в окне победы: 2^(полутоны / 12).
func star_pitch(index: int) -> float:
	if star_semitones.is_empty() or index < 0:
		return 1.0
	return pow(2.0, float(star_semitones[mini(index, star_semitones.size() - 1)]) / 12.0)


@export_group("Появление и переходы")
## Появление уровня (14.6, PLAN 4.4): ячейки поля вырастают волной по диагонали — ячейка (x, y) через
## intro_cell_step · (x + y), с; число выпрыгивает через intro_number_delay, с, после своей ячейки: снизу на
## intro_number_rise px и с ×intro_number_from до ×1 за intro_number_time, с (TRANS_BACK — с дожимом).
@export var intro_cell_step := 0.03
@export var intro_number_delay := 0.12
@export var intro_number_rise := 14.0
@export var intro_number_from := 0.3
@export var intro_number_time := 0.3
## Блоки выезжают в лоток (в портрете — снизу, в альбоме — справа, Tray.slide_dir) на intro_block_from px экрана
## за intro_block_time, с (TRANS_BACK), по одному: слот i — через intro_block_start + intro_block_step · i, с.
## Взятый на лету блок сразу в руке — выезд гасится.
@export var intro_block_from := 220.0
@export var intro_block_time := 0.32
@export var intro_block_start := 0.3
@export var intro_block_step := 0.08
## Шторка из клеток (Transition, shaders/transition.gdshader): клетка — curtain_cell короткой стороны экрана,
## скругление curtain_radius клетки (как у блока); закрывается за curtain_close, с, открывается за curtain_open, с.
## Волна по диагонали занимает curtain_spread времени, каждая клетка растёт (или тает) за остаток.
@export var curtain_cell := 0.11
@export var curtain_radius := 0.24
@export var curtain_close := 0.3
@export var curtain_open := 0.34
@export var curtain_spread := 0.5
## Кнопки: отпускание — с отскоком: лицо из нажатого (0,92 / 0,95) до ×button_release_peak и обратно до ×1,
## всего за button_release_time, с (нажатие — как было, CandyButton.PRESS_TIME).
@export var button_release_peak := 1.04
@export var button_release_time := 0.14
## Простой: через idle_after, с, без ввода блоки лотка «дышат» — масштаб ×(1 ± idle_breath) с периодом
## idle_period, с, слот i — со сдвигом фазы idle_phase · i, с; дыхание нарастает за idle_rise, с (не рывком),
## любое касание гасит его за idle_fade, с.
@export var idle_after := 4.0
@export var idle_breath := 0.02
@export var idle_period := 2.4
@export var idle_phase := 0.35
@export var idle_rise := 1.2
@export var idle_fade := 0.15

@export_group("Тупик и подсказка")
## Тупик (14.6g): поле на миг темнеет — цвет ×(1 − dead_dim) за dead_dim_in, с, держится dead_dim_hold, с,
## и светлеет за dead_dim_out, с; неверный блок «трескается» за dead_crack_time, с (трещина остаётся, пока его
## не отменят); лицо кнопки отмены дважды подпрыгивает на dead_hop px экрана, прыжок — dead_hop_time, с.
@export var dead_dim := 0.3
@export var dead_dim_in := 0.08
@export var dead_dim_hold := 0.12
@export var dead_dim_out := 0.4
@export var dead_crack_time := 0.18
@export var dead_hop := 16.0
@export var dead_hop_time := 0.26
## Подсказка (14.6g, переделана 12.10): блок сразу взлетает из гнезда и летит на место за hint_float_time, с;
## искра (HintSpark) летит вместе с ним, под блоком (виден её золотой след), и в миг касания вспыхивает.
## Было: сначала искра от кнопки 0,42 с, потом блок 0,36 с — 0,78 с от нажатия до касания, игроку долго.
@export var hint_float_time := 0.3

@export_group("Магнит")
## Ореол гнёзд той же площади пульсирует с частотой pulse_freq, Гц (при «Меньше движения» — нет).
@export var pulse_freq := 1.4

@export_group("Меньше движения")
## Доля частиц при «Меньше движения» (STYLE 12: конфетти вдвое меньше). Тряски, наклона, пружины несомого
## блока, «мотания головой» и пульса ореола нет.
@export var reduced_particles := 0.5
## Линия (14.4) и победа (14.5): волна и вспышка блоков не сильнее reduced_wave, у текста комбо и звёзд окна
## победы нет «штампа» (просто проявляются), блоки на победе не подпрыгивают, карточка не вздрагивает.
## Появление и переходы (14.6): числа и блоки лотка просто проявляются, без прыжка и выезда; шторка — ровное
## затемнение; кнопки отпускаются без перелёта; лоток в простое не дышит.
## Тупик и подсказка (14.6g): трещина — сразу целиком, кнопка отмены пульсирует (без прыжков); у подсказки нет
## искры и паузы — блок сразу вплывает на место.
@export var reduced_wave := 0.4

@export_group("Качество")
## Автоснижение качества (14.7, PLAN 4.5; Quality, QualityGovernor, модель — tools/quality_model.py). Кадры копятся
## в окно quality_window, с; к/с окна ниже quality_fps quality_bad_windows раз подряд — уровень вниз (2 «высокое»
## → 1 «среднее» → 0 «низкое»). Первые quality_warmup, с, после смены сцены и quality_settle, с, после смены
## уровня не считаются; кадры дольше quality_hitch, с (сборка мусора, вкладка в фоне) — тоже. Весь спуск дал
## меньше quality_gain (доля) к исходным к/с — откат и до конца сессии не трогать (браузер сам держит 30 к/с).
## Вверх — одна проба за сессию после quality_probe_after, с, ровных окон не ниже quality_fps_good.
@export var quality_fps := 50.0
@export var quality_fps_good := 57.0
@export var quality_window := 2.0
@export var quality_bad_windows := 2
@export var quality_warmup := 1.5
@export var quality_settle := 1.0
@export var quality_gain := 0.08
@export var quality_probe_after := 60.0
@export var quality_hitch := 0.25
## Что снижается. Частицы и конфетти: доля на среднем и низком (вместе с «Меньше движения» — произведение).
@export var quality_particles_mid := 0.5
@export var quality_particles_low := 0.3
## Фон на среднем и низком: шейдер рисуется в quality_bg_scale разрешения экрана и обновляется
## quality_bg_fps_mid / quality_bg_fps_low раз в секунду. С 19.7 витки вихря смещаются в среднем на ≈ 9 px/с
## (Background.SPEED; у 99 % экрана — до 30–40): на низком 10 раз в секунду (было 5 — для фигур медленнее
## 6 px/с), иначе шаг до 8 px был бы заметен.
@export var quality_bg_scale := 0.5
@export var quality_bg_fps_mid := 20.0
@export var quality_bg_fps_low := 10.0
## Низкое: весь 2D — в базовом разрешении (720 по ширине; текст чуть мягче).
@export var quality_low_res := true


# --- Без эффектов (14.8a) ----------------------------------------------------------

## «Без эффектов» (14.8a; selftest «Эффекты и логика (14.8)», F5 при показанном счётчике кадров — Quality): числа,
## при которых эффекта нет, — время 0, сила, частицы, тряска и hit-stop 0, масштабы 1. Игра без них та же (PLAN
## 4.4–4.5: эффекты не держат логику), только без анимаций: блок сразу на месте, лоток и числа — сразу, без волн,
## искр, вспышек, конфетти и прыжков. Что не числа конфига, остаётся: окно победы (таймлайн WinPanel), лучи, «+очки»,
## текст комбо — тихо проявляется (combo_slam 1 — без штампа), сообщения, рука-обучение, вырастание ячеек поля.
## Тип значения — как у числа (float 0.0, int 0, Vector2): Tween не примет Vector2 вместо float.
const OFF := {
	# Тряска и hit-stop
	&"shake_max": 0.0, &"trauma_place": 0.0, &"trauma_line": 0.0, &"trauma_win": 0.0,
	&"hitstop_place": 0.0, &"hitstop_line": 0.0, &"hitstop_win": 0.0,
	# Частицы (и конфетти)
	&"particles_max": 0, &"pool_size": 0, &"dust_amount": 0, &"sparks_amount": 0, &"stars_amount": 0,
	&"confetti_share": 0.0,
	# Блок в руке
	&"pick_hop": Vector2.ONE, &"pick_time": 0.0, &"tilt_max": 0.0, &"tilt_per_speed": 0.0, &"tilt_return": 0.0,
	&"magnet_pull": 0.0, &"snap_hop": 0.0, &"snap_time": 0.0,
	# Удар и промах
	&"land_time": 0.0, &"land_squash": Vector2.ONE, &"squash_time": 0.0, &"dust_per_cell": 0, &"miss_wobble": 0.0,
	&"miss_time": 0.0, &"return_arc": 0.0, &"return_arc_min": 0.0, &"return_time": 0.0, &"rotate_time": 0.0,
	&"rotate_smear": 0.0,
	# Закрытое число
	&"close_pop": 1.0, &"close_flash": 1.0, &"close_pop_time": 0.0, &"close_swap": 0.0, &"close_hold": 0.0,
	&"glow_time": 0.0, &"glow_strength": 0.0,
	# Линия и серия
	&"line_wave_time": 0.0, &"line_trail": 0.0, &"line_fade": 0.0, &"line_wave_strength": 0.0,
	&"line_block_flash": 0.0, &"line_sparks_per_cell": 0, &"combo_wave": 0.0, &"combo_flash": 0.0,
	&"combo_trauma": 0.0, &"combo_hitstop": 0.0, &"combo_sparks": 0.0, &"combo_text_grow": 0, &"combo_slam": 1.0,
	&"combo_slam_grow": 0.0, &"combo_slam_time": 0.0, &"combo_slam_trauma": 0.0,
	# Победа
	&"win_wave_time": 0.0, &"win_trail": 0.0, &"win_fade": 0.0, &"win_wave_strength": 0.0, &"win_block_flash": 0.0,
	&"win_block_pop": 0.0, &"win_merge_delay": 0.0, &"win_merge_time": 0.0, &"star_slam": 1.0,
	&"star_slam_spin": 0.0, &"star_slam_time": 0.0, &"star_slam_squash": 1.0, &"star_settle_time": 0.0,
	&"star_sparks": 0, &"star_punch": 0.0,
	# Появление и переходы
	&"intro_cell_step": 0.0, &"intro_number_delay": 0.0, &"intro_number_rise": 0.0, &"intro_number_from": 1.0,
	&"intro_number_time": 0.0, &"intro_block_from": 0.0, &"intro_block_time": 0.0, &"intro_block_start": 0.0,
	&"intro_block_step": 0.0, &"curtain_close": 0.0, &"curtain_open": 0.0, &"button_release_peak": 1.0,
	&"button_release_time": 0.0, &"idle_after": 0.0, &"idle_breath": 0.0, &"idle_rise": 0.0, &"idle_fade": 0.0,
	# Тупик и подсказка
	&"dead_dim": 0.0, &"dead_dim_in": 0.0, &"dead_dim_hold": 0.0, &"dead_dim_out": 0.0, &"dead_crack_time": 0.0,
	&"dead_hop": 0.0, &"dead_hop_time": 0.0, &"hint_float_time": 0.0,
	# Магнит
	&"pulse_freq": 0.0,
}

## Числа, которые «без эффектов» не трогает: без силы эффекта они ничего не меняют, а 0 сломал бы игру.
const KEEP_ON_OFF: Array[StringName] = [
	# Форма тряски и предел hit-stop (силы и пауз нет — тряски и остановок тоже).
	&"shake_decay", &"shake_freq", &"hitstop_max",
	# Жизнь частиц: CPUParticles2D не берёт lifetime 0, а частиц и так 0.
	&"dust_life", &"sparks_life", &"stars_life",
	# Пружина несомого блока — управление, а не эффект (жёсткость 0 — блок не поедет за пальцем).
	&"carry_stiffness", &"carry_damping",
	# Сила хода и ноты: звук — не эффект; размер шрифта текста комбо.
	&"combo_max", &"combo_semitones", &"star_semitones", &"combo_text_size",
	# Геометрия: ширина волн, мозаика (и есть ли она), шторка.
	&"win_mosaic", &"line_wave_width", &"win_wave_width", &"win_merge_gap", &"win_merge_radius",
	&"curtain_cell", &"curtain_radius",
	&"curtain_spread",
	# Дыхание лотка: период — делитель, фаза — сдвиг (размах 0 — дыхания нет).
	&"idle_period", &"idle_phase",
	# «Меньше движения» и «Качество» — свои режимы.
	&"reduced_particles", &"reduced_wave",
	&"quality_fps", &"quality_fps_good", &"quality_window", &"quality_bad_windows", &"quality_warmup",
	&"quality_settle", &"quality_gain", &"quality_probe_after", &"quality_hitch", &"quality_particles_mid",
	&"quality_particles_low", &"quality_bg_scale", &"quality_bg_fps_mid", &"quality_bg_fps_low", &"quality_low_res",
]

var _off := false
## Числа до set_effects_off(true) — для точного возврата.
var _saved: Dictionary = {}


## Эффекты выключены (числа OFF стоят).
func effects_off() -> bool:
	return _off


## Выключить (on) или вернуть эффекты. Повторный вызов с тем же on ничего не делает; возврат — ровно прежние
## числа (и те, что меняли руками, пока эффекты были включены).
func set_effects_off(on: bool) -> void:
	if on == _off:
		return
	if on:
		_saved.clear()
		for key: StringName in OFF:
			_saved[key] = get(key)
			set(key, OFF[key])
	else:
		for key: StringName in _saved:
			set(key, _saved[key])
		_saved.clear()
	_off = on
	emit_changed()


## Числа конфига (@export) по порядку объявления.
func number_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for p: Dictionary in get_property_list():
		var usage := int(p.usage)
		var n := String(p.name)
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and (usage & PROPERTY_USAGE_STORAGE) != 0 \
				and not n.begins_with("_"):
			names.append(StringName(n))
	return names


## Ошибки списков «без эффектов» (selftest): число не в OFF и не в KEEP_ON_OFF или сразу в обоих, в списке — не
## число конфига, тип значения OFF — не как у числа. Пусто — всё решено.
func off_list_errors() -> PackedStringArray:
	var errs := PackedStringArray()
	var names := number_names()
	for n in names:
		var off := OFF.has(n)
		var keep := KEEP_ON_OFF.has(n)
		if off == keep:
			errs.append("%s: %s" % [n, "и в OFF, и в KEEP_ON_OFF" if off else "нет ни в OFF, ни в KEEP_ON_OFF"])
		elif off and typeof(OFF[n]) != typeof(get(n)):
			errs.append("%s: в OFF %s, а число — %s" % [n, type_string(typeof(OFF[n])), type_string(typeof(get(n)))])
	for key: StringName in OFF:
		if not names.has(key):
			errs.append("OFF.%s: такого числа нет" % key)
	for key in KEEP_ON_OFF:
		if not names.has(key):
			errs.append("KEEP_ON_OFF: %s — такого числа нет" % key)
	return errs
