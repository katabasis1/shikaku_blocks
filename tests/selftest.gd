extends Node
## Самопроверка проекта без редактора.
##
##   godot --headless --path . --import                      # один раз: импорт ресурсов
##   godot --headless --path . res://tests/selftest.tscn     # полная (~10–30 с)
##   godot --headless --path . res://tests/selftest.tscn -- --quick
##
## Из редактора: открыть сцену tests/selftest.tscn и нажать F6 («Запустить текущую сцену»)
## или Ctrl+Shift+F5 и выбрать её. Итог — в панели «Вывод». Файл → Запустить (Ctrl+Shift+X)
## не подходит: так запускают только EditorScript.
##
## Что проверяется:
##  1. сцены загружаются и создаются, меню запускается; автозагрузки, звуки, шрифт,
##     переводы, иконки;
##  2. уровни игры 1..1000 (заготовки из LevelPack и отражённые повторы) корректны:
##     разбиение, числа, набор блоков, механики глав 4–10 (препятствия и закреплённые блоки не накрыты решением,
##     «?» — любая площадь, цветные клетки — блоком своей площади); generate() берёт их из списка;
##  3. сверка с Python (tests/expected_levels.txt, см. tools/make_expected.py):
##     md5 уровней игры 1..1000, статусы решателя для всех первых ходов уровней 1..60,
##     md5 запасного процедурного генератора 1..300;
##  4. решатель находит корректное решение каждого уровня (с механикой — по её правилам, run_level);
##  5. очки: рекорд по уровню, переигровка без накрутки, миграция v2 -> v3, слияние облака;
##     поколения прогресса (сброс не возвращается из облака, облако новее заменяет);
##     таблицы лидеров после сброса (16.3): лучшее принятое Яндексом переживает сброс, JSON, файл и облако
##     любого поколения, меньший счёт и серия в таблицу не уходят (мост JS — подделка FakeBridge);
##     функции Яндекса (16.2a): флаги Remote Config (мусор — значение по умолчанию, пределы), отзыв на 11–15 уровне
##     (один запрос за сессию, запоминается по ответу); ярлыка нет (убран в 16.2b);
##  6. настройки: шины Music/SFX, settings.cfg, приглушение, перенос звука из сохранения v3;
##     окно настроек и паузы: переключатели, сброс с подтверждением, Esc, «В меню»;
##  7. игра целиком: рука-обучение (когда видна, что показывает, ходы руки проходят
##     уровни 1–3), пауза, тупиковый ход, отмена, откат подсказкой, прохождение
##     подсказками (длинные блоки помещаются в лоток), окно победы, «Далее»,
##     устаревший ответ рекламы;
##  8. десктоп (этап 13.0): раскладки GameLayout (гистерезис, всё в экране, без наложений,
##     гнёзда в лотке) и их применение к игре (смена туда и обратно, лоток, поле, рука),
##     клавиши по месту (physical_keycode), наведение только от настоящей мыши;
##  9. поле и блоки в новом стиле (этап 13.1): палитра B и шрифт цифр, гнёзда чисел, рамка
##     поля под масштаб, призрак места, магнит (ореол, ×1,08, приглушение), подъём блока
##     (×1,08 от поля, непрозрачный, тень «поднят») и возврат, цифра на клетке с числом,
##     блоки на поле по рядам. Шейдеры в --headless не компилируются: их ошибки видны
##     только в редакторе (панель «Вывод») и в игре;
## 10. фон (этап 13.7): Background — шейдер background.gdshader, размер узла в шейдере при любом
##     resize (портрет и альбом), свой материал у каждого экземпляра, свет победы и его возврат, темп вихря
##     (19.7: SPEED, при «Меньше движения» — SPEED_CALM).
## 11. импакт (этап 14): Juice — тряска, hit-stop, пул частиц, «Меньше движения» (14.1); блок в руке
##     (14.2): удар, когда блок долетел, отмена в полёте без удара, дуга возврата, пружина и наклон,
##     поворот со смазом, «мотание» при промахе, «щелчок» места, пульс ореола магнита.
##     Закрытое число (14.3): в миг удара — вспышка цифры, галочка, свет по клеткам; цифра остаётся, hit-stop
##     останавливает закрытие, отмена хода гасит его сразу, «Меньше движения» — без света.
##     Комбо и линии (14.4): сила хода и серия (ход без линии обрывает, отмена возвращает), в миг удара — волна по
##     каждой линии из клеток блока, вспышка блоков, звук выше по силе, текст комбо «штампом»; hit-stop, «Меньше движения».
##     Победа (14.5): удар в миг касания последнего блока, волна по полю, звёзды окна «штампом» по одной; мозаики
##     и звёздочек удара нет (убраны в 14.8e: win_mosaic, stars_amount).
##     Появление и переходы (14.6): блоки выезжают по одному, числа выпрыгивают после своих ячеек, всё доигрывает на
##     место, ввод не ждёт (блок берётся на лету, ход засчитан); шторка из клеток ловит нажатия, действие — один раз
##     под закрытым экраном; отскок кнопки до ×button_release_peak и ровно в ×1; дыхание лотка в простое (±idle_breath
##     со сдвигом фаз) гаснет от касания и стоит в руке, на паузе, в тупике, в окне; «Меньше движения» — без движения.
##     Тупик и подсказка (14.6g): в миг предупреждения поле на миг темнеет (слои, не board.modulate), неверный блок
##     трескается до отмены, лицо «Отмены» дважды подпрыгивает; искра подсказки летит от кнопки к месту по дуге,
##     блок ждёт её и вплывает (ход засчитан сразу, «+очки» в миг касания); отмена посреди — искра тает без вспышки;
##     последний блок подсказкой — окно победы позже на искру и вплывание; подсказка, пока лоток ещё выезжает, —
##     блок летит целиком, не выезжая посреди пути; «Меньше движения» — без искры и прыжков.
## 12. качество (этап 14.7): решатель автоснижения на синтетических кадрах — все сценарии tools/quality_model.py;
##     что снижается на каждом уровне (частицы и их предел, конфетти, след искры подсказки, тень звезды 49 → 9
##     отсчётов, фон в SubViewport — размер, частота, каждый кадр на смене света, разрешение 2D на низком),
##     «Меньше движения» — произведение долей; уровень в settings.cfg; счётчик кадров (F3, F4, касания).
## 13. эффекты и логика (этап 14.8): «без эффектов» (14.8a) — каждое число JuiceConfig решено (OFF или
##     KEEP_ON_OFF), выключатель ставит OFF и возвращает ровно прежние числа, частиц, конфетти, тряски и hit-stop
##     нет; F5 — только при показанном счётчике кадров, в счётчике «эффекты: выкл.». Эффекты не держат логику
##     (14.8b): уровень 12 с чистого прогресса — ход сразу после старта, подсказка, тупик и отмена, остальное по
##     решению, победа, «Далее» — в режимах «обычный», «Меньше движения» + низкое, «без эффектов», «эффекты
##     заморожены» (в --quick — два последних): итоги одинаковы, победа — в кадр последнего хода, «Далее» — через
##     win_at + BUTTONS_DELAY. Ввод не ждёт эффектов (14.8c): в том же сценарии после каждого хода, линии, подсказки,
##     тупика и отмены — в тот же кадр — настоящее нажатие (Viewport.push_input) доходит до каждого блока лотка (его
##     берёт DragController), до «Отмены» и «Подсказки» (и они сработали бы), под заморозкой — тоже; в разгар эффектов
##     («+очки», линия, сообщение тупика, поле темнеет, искра подсказки, лучи и конфетти победы) в игре нет Control,
##     кроме кнопок, гнёзд лотка и окон (и контейнеров с ними), который ловил бы нажатия; «Далее» достижима.
## 14. звук (этап 15): у каждого звука Audio.SOUNDS — голоса VOICES (один файл, шина SFX, по звуку на голос), новая
##     нота не меняет высоту прошлой (свой голос; все заняты — берётся старейший); нота постановки — пентатоника
##     до мажор (больше блок — не выше, серия — не ниже, предел PLACE_STREAK_MAX), линия (тоника, квинта, октава)
##     и звёзды — в до мажоре; при выключенных звуках запрос считается, но не играет; кнопка музыку не приглушает,
##     удар победы — приглушает, возврат — за MUSIC_RESTORE_TIME. В сценарии 14.8b (кроме «эффекты заморожены»):
##     каждый удар блока — ровно одно из «нота», «линия», «победа»; ноты — в пентатонике, линии — по силе хода;
##     тупик — Error один раз, промахов нет, подсказка и отмена — по разу; победа один раз, затем звёзды до-ми
##     (по заработанным), затем джингл один раз; под звёздами и джинглом музыка приглушена (если звуки включены).
## 15. механики «Лаборатории» (этап 19.3): формат (метки h, p, q, t; испорченные не читаются), 40 уровней — у каждой
##     механики только её метки, блоки — формы решения, решатель с правилами приходит к эталону; правила на поле
##     (препятствие и закреплённый блок заняты, «?» — любая площадь, цветную клетку — только блок её площади), знаки
##     механик; уровень в игре до победы без очков и прогресса игрока, «Далее» — следующий без рекламы; шапка с
##     «10/10» не ужата до предела; экран «Лаборатории» (карточки, ряды, касания, ru / en / tr, альбом); кнопка
##     в меню — только в отладочной сборке.
## 16. главы (этап 19.5c): таблицы Chapters (длины, начала с 1 по возрастанию, повтор с LOOP_FROM по LOOP_SPAN),
##     номера и начала глав на трёх кругах повтора, образцы из Python, темы фона; высоты карты с зазором перед
##     главой (MapPath.rise / level_below), плашка главы между кружками (не задевает их, не ловит касание, текст на
##     ru / en / tr влезает), фон карты — тема главы посреди экрана и плавный переход к ней.
## 17. карточка начала главы (этап 19.5d): когда нужна (ChapterCard.wanted), на уровне 61 — карточка главы 2 с идеей
##     над серединой поля, между FxLayer и DragLayer, нажатий не ловит; нажатие убирает её, «Заново» и переигровка
##     пройденного не повторяют, сама уходит; тексты глав на ru / en / tr не ужимаются.
## 18. уровни глав с механиками (этап 19.5e): механика каждого уровня 1..500 — по плану tools/chapter_levels.py
##     (CHAPTER_MECH_PLAN), в уровне одна механика, повтор после 500 сохраняет её; Chapters.MECHANICS, intro_first,
##     rule_of (вводные уровни, ежедневная задача, повтор); в игре на уровнях 151, 201, 251, 301 — поле с механикой,
##     правило над полем и идея на карточке главы, прохождение подсказками до победы; на 156 и 351 правила нет;
##     ежедневная с механикой — правило, пока вводные уровни не пройдены.
## 19. аналитика (этап 16.1): интервалы секунд и ключи уровней Analytics; вне веба цели только в журнале (не больше
##     JOURNAL_SIZE); журнал целей в игре — уровень 12: начало, первый свой ход один раз, тупик и отмена по разу за
##     попытку (число — в итоге), подсказка бесплатная и за рекламу, «Заново» посреди уровня (level_restart с
##     числами и «блоков на поле»), победа (звёзды, отмены, подсказки — как в игре), переигровка, «Заново» после
##     победы — не попытка, уход со сцены — level_exit; задача дня (daily_*, серия); «Лаборатория» не считается;
##     навык обучения — tutorial_step один раз; итоги рекламы (YSDK.ad_result и события JS) и отзыва (review_result).
## Код выхода: 0 — всё хорошо, 1 — есть ошибки (подробности в выводе).
## Сохранение и настройки игрока (user://save.cfg, user://settings.cfg) на время
## теста откладываются и потом возвращаются.

const GAME_SCENE := "res://scenes/game/game.tscn"
const MENU_SCENE := "res://scenes/menu/menu.tscn"
const MAP_SCENE := "res://scenes/map/level_map.tscn"  # 18.2
## 19.5c: главы по tools/chapters_model.py — [уровень, индекс в таблицах Chapters, номер на экране, начало главы]
## (при 500 заготовленных уровнях и LOOP_FROM 201: повтор режется на главы по 50 с темами глав 5–10).
const CHAPTER_SAMPLES := [[1, 0, 1, true], [60, 0, 1, false], [61, 1, 2, true], [101, 2, 3, true],
		[151, 3, 4, true], [500, 9, 10, false], [501, 4, 11, true], [551, 5, 12, true], [1000, 7, 20, false],
		[1001, 8, 21, true]]
## 19.5e: план механик уровней 151..500 по главам 4–10 (по 50) — tools/chapter_levels.py --gd: H — препятствия,
## P — закреплённый блок, T — цветные клетки, Q — число «?», «.» — классика. Уровни 1..150 — классика.
const CHAPTER_MECH_PLAN: Array[String] = [
		"HHHHH.HH.HH.HH.HH.HH.HH.HH.HH.HH.HH.HH.HH.HH.HH.HH",
		"PPPPP.PP.PP.PP.PP.PP.PP.PP.PP.PP.PP.PP.PP.PP.PP.PP",
		"TTTTT.TT.TT.TT.TT.TT.TT.TT.TT.TT.TT.TT.TT.TT.TT.TT",
		"QQQQQ.QQ.QQ.QQ.QQ.QQ.QQ.QQ.QQ.QQ.QQ.QQ.QQ.QQ.QQ.QQ",
		"HP.TQ.HP.TQ.HP.TQ.HP.TQ.HP.TQ.HP.TQ.HP.TQ.HP.TQ.HP",
		"TQ.HP.TQ.HP.TQ.HP.TQ.HP.TQ.HP.TQ.HP.TQ.HP.TQ.HP.TQ",
		"HP.TQ.HP.TQ.HP.TQ.HP.TQ.HP.TQ.HP.TQ.HP.TQ.HP.TQ.HP",
]
const MECH_LETTERS := {"H": "holes", "P": "pinned", "T": "tints", "Q": "unknown", ".": ""}
const LEADERS_SCENE := "res://scenes/leaders/leaders.tscn"  # 18.3
const MenuScript := preload("res://scenes/menu/menu.gd")
const SETTINGS_PANEL_SCENE := "res://scenes/ui/settings_panel.tscn"
const FONT_PATH := "res://assets/fonts/nunito_extrabold.ttf"  # 13.3: Nunito 800 — шрифт темы по умолчанию
const DIGIT_FONT_PATH := "res://assets/fonts/nunito_black.ttf"
const BOARD_SCENE := "res://scenes/game/board.tscn"
const BLOCK_SCENE := "res://scenes/game/block.tscn"
## 19.3c: образец механик 4×3 — 4 с цветной клеткой «4» (1, 1), 2, «?» (1, 2), 1; препятствие (2, 0), закреплённый
## блок 1×2 в (3, 0). Решение одно (tools/model.py).
const LAB_SYN := "43:002200211221022112321132:22122111:h20p3012q12t114"
## Без правил решаются, с правилами — нет: 4×1 через препятствие и закреплённый блок; 2×2 на цветную клетку «2».
const LAB_SYN_41 := "42:002200211121:4111:h20p3012"
const LAB_SYN_T2 := "23:002200022102:2221:t112"
## Испорченные метки механик (LevelPack.decode — {}): обрезанная, чужая буква, на занятой клетке, за полем, «?» не на
## числе, цветная на числе и площади 0, клетка не накрыта, не цифра, пятая часть строки.
const LAB_BROKEN: Array[String] = [
	"43:002200211221022112321132:22122111:h20p3012q12t11",
	"43:002200211221022112321132:22122111:h20p3012q12x114",
	"43:002200211221022112321132:22122111:h00p3012q12t114",
	"43:002200211221022112321132:22122111:h20p3013q12t114",
	"43:002200211221022112321132:22122111:h20p3012q22t114",
	"43:002200211221022112321132:22122111:h20p3012q12t004",
	"43:002200211221022112321132:22122111:h20p3012q12t110",
	"43:002200211221022112321132:22122111:h20q12t114",
	"43:002200211221022112321132:22122111:h20p3012q12t1a4",
	"43:002200211221022112321132:22122111:h20p3012q12t414",
	"43:002200211221022112321132:22122111:h20p3012q12t114:",
]
const SHELF_SHADER_PATH := "res://shaders/shelf.gdshader"
const BACKGROUND_SCENE := "res://scenes/ui/background.tscn"
const SOFT_SHADOW_SHADER_PATH := "res://shaders/soft_shadow.gdshader"
const TEX_SHADOW_SHADER_PATH := "res://shaders/tex_shadow.gdshader"
const PILL_SHADER_PATH := "res://shaders/pill.gdshader"
const TRANSITION_SHADER_PATH := "res://shaders/transition.gdshader"
const STAR_PNG_PATH := "res://assets/icons/star.png"
const EXPECTED_PATH := "res://tests/expected_levels.txt"
const SAVE_BACKUP := "user://save.cfg.selftest_backup"
const NO_SAVE_FLAG := "user://selftest_no_save.flag"
const SETTINGS_BACKUP := "user://settings.cfg.selftest_backup"
const NO_SETTINGS_FLAG := "user://selftest_no_settings.flag"
const WATCHDOG_SEC := 267.0  # 14.6f: +~10 с на _test_juice_intro; 14.6g: +~15 с на _test_juice_dead_hint; 14.7: +~5 с;
# 14.8b: +~15 с на _test_effects_logic (4 прохода уровня, на каждом ждём «Далее» ~2,4 с); 14.8c: +~6 с (покой перед
# сценарием ~1 с, в каждом проходе — ожидание тупика до 0,8 с и линии до 0,5 с); 19.3c: +~10 с на _test_lab (4 уровня
# до победы, окно победы ~2,7 с, смена языков и раскладок); 19.5c: +~5 с на _test_chapters (переход фона 0,6 с,
# высоты карты на 1400 уровнях); 19.5d: +~4 с на _test_chapter_card (уход карточки 2,8 с); 19.5e: +~7 с на
# _test_chapter_levels (4 уровня с механикой до победы подсказками, run_level на 1000 уровнях в _test_levels);
# 16.1: +~5 с на _test_analytics (уровень 12 и задача дня до победы подсказками)
const LOGIC_LEVEL := 12  # 14.8b: уровень сценария «эффекты и логика» (с чистого прогресса)
const LOGIC_FREEZE_SEC := 600.0  # 14.8b: hit-stop «на весь уровень» — эффекты заморожены
## Режимы сценария 14.8b (индексы — в _test_effects_logic).
const LOGIC_MODES: Array[String] = ["обычный", "«Меньше движения» + низкое качество", "без эффектов",
		"эффекты заморожены"]
const MAX_REPORTS := 5  # сколько однотипных ошибок печатать подробно
const PACK_MAX_AREA := 12  # пределы заготовленных уровней (tools/make_levels.py: spec)
const PACK_MAX_SIDE := 5

var _fails: int = 0
var _checks: int = 0
var _quick: bool = false
var _done: bool = false
var _had_file: Dictionary = {}  # путь -> был ли файл игрока до теста
var _landed_log: Array = []  # Board.landed в _test_juice_moves: [блок, место, мс]
var _sound_log: Array = []  # Audio.requested (15.6): [звук, высота, кадр, музыка приглушена]
var _vib_log: Array = []  # Audio.vibration_requested (15.4): рисунки вибрации
## 14.8c: нажатия проб ввода — настоящими событиями (Viewport.push_input); false — в покое они не дошли, в сценарии
## остаются проверки логики (can_undo, can_request) и Control поверх (см. _test_effects_logic).
var _probe_push: bool = true
var _probe_hits: int = 0  # сколько нажатий ЛКМ дошло до цели пробы (_push_press)


func _ready() -> void:
	_quick = OS.get_cmdline_user_args().has("--quick")
	get_tree().create_timer(WATCHDOG_SEC).timeout.connect(_on_watchdog)
	print("Самопроверка Shikaku Blocks%s" % (" (быстрая)" if _quick else ""))
	_backup_save()
	# Автоснижение качества (14.7) не должно менять эффекты посреди проверок (число частиц, фон): уровень —
	# «высокое», замер выключен; раздел «Качество (14.7)» включает уровни сам.
	Quality.set_auto(false)
	Quality.set_level(Quality.HIGH)
	await get_tree().process_frame
	await _run()
	_finish()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	await _test_scenes()
	_test_assets()
	_test_levels(200 if _quick else 1000)
	_test_procedural(100 if _quick else 300)
	_test_scoring()
	_test_daily()
	_test_epoch()
	_test_leaderboard_sent()
	_test_yandex_features()
	_test_tutorial_save()
	_test_settings()
	await _test_settings_panel()
	await _test_audio()
	await _test_menu()
	await _test_level_map()
	await _test_chapters()
	await _test_chapter_card()
	await _test_chapter_levels()
	await _test_leaders()
	await _test_daily_game()
	await _test_analytics()
	await _test_lab()
	await _test_background()
	_test_layout()
	_test_keys()
	_test_quality_governor()
	await _test_game()
	print("\nВремя: %.1f с" % ((Time.get_ticks_msec() - t0) / 1000.0))


# --- Инфраструктура ----------------------------------------------------------

func _section(title: String) -> void:
	print("\n== " + title)


func _check(cond: bool, what: String) -> bool:
	_checks += 1
	if not cond:
		_fails += 1
		print("  [FAIL] " + what)
	return cond


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _finish() -> void:
	if _done:
		return
	_done = true
	_restore_save()
	print("\n==========")
	if _fails == 0:
		print("САМОПРОВЕРКА ПРОЙДЕНА: %d проверок" % _checks)
	else:
		print("ОШИБОК: %d (всего проверок %d). Пришли этот вывод целиком." % [_fails, _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _on_watchdog() -> void:
	if _done:
		return
	_fails += 1
	print("  [FAIL] самопроверка не закончилась за %d с: зависла или прервалась ошибкой скрипта (смотри ошибки выше)" % int(WATCHDOG_SEC))
	_finish()


## Файлы игрока, которые тест меняет: [файл, копия, флаг «файла не было»].
func _player_files() -> Array:
	return [
		[GameState.SAVE_PATH, SAVE_BACKUP, NO_SAVE_FLAG],
		[GameState.SETTINGS_PATH, SETTINGS_BACKUP, NO_SETTINGS_FLAG],
	]


## Прячем настоящие сохранение и настройки игрока: тест проходит уровни,
## переключает звук и пишет свои файлы.
func _backup_save() -> void:
	for entry in _player_files():
		var path: String = entry[0]
		var backup: String = entry[1]
		var flag: String = entry[2]
		if FileAccess.file_exists(backup):
			_had_file[path] = true  # прошлый запуск оборвался: копия — настоящий файл
		elif FileAccess.file_exists(flag):
			_had_file[path] = false  # прошлый запуск оборвался, файла не было
		elif FileAccess.file_exists(path):
			_had_file[path] = true
			_copy_file(path, backup)
		else:
			_had_file[path] = false
			var f := FileAccess.open(flag, FileAccess.WRITE)
			if f != null:
				f.store_string("1")
				f.close()


func _restore_save() -> void:
	for entry in _player_files():
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


static func _copy_file(from: String, to: String) -> void:
	var bytes := FileAccess.get_file_as_bytes(from)
	var f := FileAccess.open(to, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()


static func _list_files(dir: String, ext: String, out: Array[String]) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if da.current_is_dir():
			if not entry.begins_with("."):
				_list_files(dir.path_join(entry), ext, out)
		elif entry.get_extension() == ext:
			out.append(dir.path_join(entry))
		entry = da.get_next()
	da.list_dir_end()


# --- 1. Сцены ------------------------------------------------------------------

func _test_scenes() -> void:
	_section("Сцены")
	var files: Array[String] = []
	_list_files("res://scenes", "tscn", files)
	_check(files.size() > 0, "в res://scenes не найдено ни одной сцены")
	for path in files:
		var ps := load(path) as PackedScene
		if not _check(ps != null, "не загружается: " + path):
			continue
		var inst := ps.instantiate()
		if _check(inst != null, "не создаётся: " + path):
			inst.free()
	print("  загружено и создано сцен: %d" % files.size())

	var menu_ps := load(MENU_SCENE) as PackedScene
	if _check(menu_ps != null, "меню не загружается"):
		var menu := menu_ps.instantiate()
		add_child(menu)
		await _frames(3)
		_check(menu.is_inside_tree(), "меню не запустилось")
		menu.queue_free()
		await _frames(1)
		print("  меню запускается")


# --- 1б. Автозагрузки, звуки, шрифт, переводы ------------------------------------

func _test_assets() -> void:
	_section("Автозагрузки и ресурсы")
	for n in ["GameState", "Audio", "YSDK", "Transition"]:
		_check(get_node_or_null("/root/" + n) != null, "нет автозагрузки " + n)
	_check(not Transition.is_busy(), "затемнение перехода между сценами висит без перехода")

	var audio := get_node_or_null("/root/Audio")
	var players := 0
	if audio != null:
		for child in audio.get_children():
			if child is AudioStreamPlayer:
				players += 1
				_check((child as AudioStreamPlayer).stream != null, "у звука %s нет файла" % child.name)
	print("  звуков %d (узлов-голосов %d) и музыка" % [Audio.SOUNDS.size(), players - 1])

	var font := load(FONT_PATH) as Font
	if _check(font != null, "шрифт не загружается: " + FONT_PATH):
		var missing := ""
		for ch in "АЯЁабвёжщъыэюя0123456789+%×«»—ÇçĞğİıÖöŞşÜü":
			if not font.has_char(ch.unicode_at(0)):
				missing += ch
		_check(missing.is_empty(), "в шрифте нет символов: " + missing)

	# 13.3: Nunito 800 — по умолчанию (подписи, текст карточек, ссылка), Nunito 1000 — кнопки с текстом и заголовки.
	_check(not FileAccess.file_exists("res://assets/fonts/game_font.ttf"),
			"остался assets/fonts/game_font.ttf (после 13.3 его нет — распакуйте архив в чистую папку)")
	var ui_theme := load("res://theme/main_theme.tres") as Theme
	if _check(ui_theme != null, "тема не загружается"):
		var df := ui_theme.default_font
		_check(df != null and df.resource_path == FONT_PATH,
				"шрифт темы по умолчанию — %s, нужен %s" % [df.resource_path if df else "нет", FONT_PATH])
		for pair in [["Button", DIGIT_FONT_PATH], ["SecondaryButton", DIGIT_FONT_PATH], ["PillButton", DIGIT_FONT_PATH],
				["CardTitle", DIGIT_FONT_PATH], ["WinTitle", DIGIT_FONT_PATH], ["CardLink", FONT_PATH]]:
			var tf: Font = ui_theme.get_font(&"font", StringName(pair[0])) if ui_theme.has_font(&"font", StringName(pair[0])) else null
			_check(tf != null and tf.resource_path == pair[1],
					"тема: шрифт %s — %s, нужен %s" % [pair[0], tf.resource_path if tf else "нет", pair[1]])
		for t in ["TitleLabel", "TitleSubLabel"]:
			# 07.10: названия игры в меню нет — типов темы под него тоже.
			_check(not ui_theme.get_type_list().has(t), "тема: остался тип %s (названия в меню нет)" % t)
		for t in ["Label", "CardText"]:
			# Theme.has_font истинно и при одном default_font (14.8e) — смотрим только шрифты самого типа.
			_check(not ui_theme.get_font_list(t).has("font"), "тема: у %s свой шрифт — должен быть шрифт по умолчанию (Nunito 800)" % t)

	var saved_locale := TranslationServer.get_locale()
	for pair in [["en", "PLAY"], ["tr", ""]]:
		TranslationServer.set_locale(pair[0])
		var t := tr("ИГРАТЬ")
		var ok: bool = t != "ИГРАТЬ" and (pair[1] == "" or t == pair[1])
		_check(ok, "перевод %s не подключён (tr(\"ИГРАТЬ\") = \"%s\")" % [pair[0], t])
	TranslationServer.set_locale(saved_locale)
	print("  шрифт и переводы проверены")

	# 13.4: SVG-иконки ушли (docs/icons/svg_old), сцены и скрипты ссылаются только на PNG.
	var svgs: Array[String] = []
	_list_files("res://assets/icons", "svg", svgs)
	_check(svgs.is_empty(), "в res://assets/icons остались SVG: %s (после 13.4 их нет — распакуйте архив в чистую папку)" % str(svgs))
	var sources: Array[String] = []
	for dir in ["res://scenes", "res://scripts"]:
		_list_files(dir, "tscn", sources)
		_list_files(dir, "gd", sources)
	var svg_refs: Array[String] = []
	var svg_re := RegEx.create_from_string("assets/icons/\\w+\\.svg")
	for path in sources:
		if svg_re.search(FileAccess.get_file_as_string(path)) != null:
			svg_refs.append(path)
	_check(svg_refs.is_empty(), "ссылки на SVG-иконки: %s" % str(svg_refs))
	print("  SVG-иконок нет, ссылок на них нет (%d файлов)" % sources.size())
	# PNG-иконки (этап 12.3g, подключаются с 13.2b): грузятся, импорт с mipmaps (кнопка 96 px из 256).
	var pngs: Array[String] = []
	_list_files("res://assets/icons", "png", pngs)
	# 10.10: +7 картинок листа 5 (замок, медали, плитка, рамка, заклёпка; кубок заменён) — всего 27;
	# +10 кружков уровней листа 6 (node_*.png) — 37.
	_check(pngs.size() >= 37, "PNG-иконок %d, нужно 37" % pngs.size())
	for path in pngs:
		_check(load(path) is Texture2D, "иконка не загружается: " + path)
		var imp := ConfigFile.new()
		var ok := imp.load(path + ".import") == OK and bool(imp.get_value("params", "mipmaps/generate", false))
		_check(ok, "%s: импорт без mipmaps (нужен %s.import с mipmaps/generate=true, затем Reimport)" % [path, path.get_file()])
	print("  PNG-иконок: %d, все с mipmaps" % pngs.size())


# --- 2–4. Уровни: генератор, сверка с Python, решатель ------------------------------

func _test_levels(n: int) -> void:
	_section("Уровни игры 1..%d (заготовки и повторы) и решатель" % n)
	var expected := _load_expected()
	var parity_md5: bool = not (expected.md5 as Dictionary).is_empty()
	if not parity_md5:
		_check(false, "нет эталона %s — запусти python3 tools/make_expected.py" % EXPECTED_PATH)
	elif int(expected.pack_version) != LevelPack.DATA.VERSION or int(expected.pack_count) != LevelPack.count():
		_check(false, "эталон для списка v%d из %d уровней, а в игре v%d из %d — перезапусти tools/make_expected.py"
				% [int(expected.pack_version), int(expected.pack_count), LevelPack.DATA.VERSION, LevelPack.count()])
		parity_md5 = false
	if _check(LevelPack.count() > 0 and not LevelPack.get_level(1).is_empty(), "список заготовленных уровней пуст или испорчен"):
		_check(_canonical(LevelGenerator.generate(1)) == _canonical(LevelPack.get_level(1)),
				"LevelGenerator.generate берёт уровень не из списка")

	var solver_levels := 20 if _quick else 60
	var gen_errors := 0
	var md5_errors := 0
	var st_errors := 0
	var solver_errors := 0
	var max_steps := 0
	var md5_checked := 0
	var st_checked := 0
	var mech_levels := 0
	var t0 := Time.get_ticks_msec()
	for level in range(1, n + 1):
		var d := LevelPack.get_level(level)
		var err := "строка уровня в списке испорчена"
		if not d.is_empty():
			err = _validate_level(level, d, PACK_MAX_AREA, PACK_MAX_SIDE)
		if not err.is_empty():
			gen_errors += 1
			if gen_errors <= MAX_REPORTS:
				_check(false, "уровень %d: %s" % [level, err])
			else:
				_fails += 1
			continue
		_checks += 1

		var canon := _canonical(d)
		if level % 25 == 0:
			_check(_canonical(LevelGenerator.generate(level)) == canon,
					"уровень %d: generate() дал другой уровень" % level)

		if parity_md5 and expected.md5.has(level):
			md5_checked += 1
			var h := canon.md5_text().substr(0, 12)
			if h != expected.md5[level]:
				md5_errors += 1
				if md5_errors <= MAX_REPORTS:
					_check(false, "уровень %d не совпадает с Python-моделью: %s" % [level, canon])
				else:
					_fails += 1
			else:
				_checks += 1

		if parity_md5 and level <= solver_levels and expected.st.has(level):
			st_checked += 1
			var st := _first_move_statuses(d)
			if st != expected.st[level]:
				st_errors += 1
				if st_errors <= MAX_REPORTS:
					_check(false, "уровень %d: решатель расходится с Python-моделью\n         Godot:  %s\n         Python: %s"
							% [level, st, expected.st[level]])
				else:
					_fails += 1
			else:
				_checks += 1

		var none: Array[Rect2i] = []
		var pieces: Array[Vector2i] = []
		pieces.assign(d.pieces)
		var sv := ShikakuSolver.run_level(d, none, pieces)  # 19.5e: с механикой — по её правилам
		max_steps = maxi(max_steps, sv.steps)
		if not LevelPack.mechanic_of(d).is_empty():
			mech_levels += 1
		var serr := ""
		if sv.status != ShikakuSolver.SOLVED:
			serr = "статус %d вместо «решено»" % sv.status
		else:
			serr = _validate_solution(d, sv.solution)
		if not serr.is_empty():
			solver_errors += 1
			if solver_errors <= MAX_REPORTS:
				_check(false, "уровень %d, решатель: %s" % [level, serr])
			else:
				_fails += 1
		else:
			_checks += 1

	print("  уровней: %d (с механикой %d), ошибок генератора: %d, решателя: %d, макс. шагов решателя: %d, время %.1f с"
			% [n, mech_levels, gen_errors, solver_errors, max_steps, (Time.get_ticks_msec() - t0) / 1000.0])
	if parity_md5:
		print("  сверка с Python: уровней %d (расхождений %d), первых ходов на %d уровнях (расхождений %d)"
				% [md5_checked, md5_errors, st_checked, st_errors])


func _load_expected() -> Dictionary:
	var res := {"pack_version": -1, "pack_count": -1, "generator_version": -1, "md5": {}, "st": {}, "gmd5": {}}
	if not FileAccess.file_exists(EXPECTED_PATH):
		return res
	var text := FileAccess.get_file_as_string(EXPECTED_PATH)
	for raw_line in text.split("\n", false):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("#"):
			for key: String in ["pack_version", "pack_count", "generator_version"]:
				var at := line.find(key + "=")
				if at >= 0:
					res[key] = line.substr(at + key.length() + 1).get_slice(" ", 0).to_int()
			continue
		var f := line.split(" ", false)
		if f.size() < 3:
			continue
		var lvl := f[1].to_int()
		if f[0] == "L":
			res["md5"][lvl] = f[2]
			if f.size() > 3 and f[3] != "-":
				res["st"][lvl] = f[3]
		elif f[0] == "G":
			res["gmd5"][lvl] = f[2]
	return res


## Запасной процедурный генератор: корректность и совпадение с tools/model.py.
func _test_procedural(n: int) -> void:
	_section("Запасной процедурный генератор: уровни 1..%d" % n)
	var expected := _load_expected()
	var gmd5: Dictionary = expected.gmd5
	var parity: bool = not gmd5.is_empty() and int(expected.generator_version) == LevelGenerator.GENERATOR_VERSION
	_check(parity, "эталон процедурного генератора отсутствует или устарел — перезапусти tools/make_expected.py")
	var errors := 0
	var mismatches := 0
	for level in range(1, n + 1):
		var d := LevelGenerator.generate_procedural(level)
		var err := _validate_level(level, d, LevelGenerator.max_area(level), LevelGenerator.MAX_SIDE)
		if err.is_empty() and parity and gmd5.has(level) and _canonical(d).md5_text().substr(0, 12) != gmd5[level]:
			err = "не совпадает с Python-моделью: %s" % _canonical(d)
			mismatches += 1
		if not err.is_empty():
			errors += 1
			if errors <= MAX_REPORTS:
				_check(false, "процедурный уровень %d: %s" % [level, err])
			else:
				_fails += 1
		else:
			_checks += 1
	print("  уровней: %d, ошибок: %d (из них расхождений с Python: %d)" % [n, errors, mismatches])


## Та же строка, что строит tools/make_expected.py (canonical).
static func _canonical(d: Dictionary) -> String:
	var sol := PackedStringArray()
	for item in d.solution:
		var r: Rect2i = item
		sol.append("%d,%d,%d,%d" % [r.position.x, r.position.y, r.size.x, r.size.y])
	var nums := PackedStringArray()
	for item in d.numbers:
		var p: Vector2i = item.pos
		nums.append("%d,%d,%d" % [p.x, p.y, int(item.value)])
	var pcs := PackedStringArray()
	for item in d.pieces:
		var v: Vector2i = item
		pcs.append("%d,%d" % [v.x, v.y])
	var out := "%dx%d|S:%s|N:%s|P:%s" % [int(d.cols), int(d.rows), ";".join(sol), ";".join(nums), ";".join(pcs)]
	# 19.5e: механика — как canonical в tools/make_expected.py (препятствия, закреплённые блоки, цветные клетки).
	var mods := PackedStringArray()
	for c: Vector2i in d.get("holes", []):
		mods.append("h%d,%d" % [c.x, c.y])
	for r: Rect2i in d.get("pinned", []):
		mods.append("p%d,%d,%d,%d" % [r.position.x, r.position.y, r.size.x, r.size.y])
	for t: Dictionary in d.get("tints", []):
		var tp: Vector2i = t.pos
		mods.append("t%d,%d,%d" % [tp.x, tp.y, int(t.value)])
	return out + ("|M:" + ";".join(mods) if not mods.is_empty() else "")


## Проверка сгенерированного уровня. "" — всё в порядке, иначе описание ошибки.
static func _validate_level(level: int, d: Dictionary, limit: int, max_side: int) -> String:
	var cols: int = d.cols
	var rows: int = d.rows
	var expected_size := LevelGenerator.grid_size(level)
	if Vector2i(cols, rows) != expected_size:
		return "размер %dx%d, ожидался %dx%d" % [cols, rows, expected_size.x, expected_size.y]
	var sol: Array = d.solution
	var nums: Array = d.numbers
	var pcs: Array = d.pieces
	if sol.is_empty() or nums.size() != sol.size() or pcs.size() != sol.size():
		return "прямоугольников %d, чисел %d, блоков %d" % [sol.size(), nums.size(), pcs.size()]
	var used := _mech_cells(d)
	if used.is_empty():
		return "механика выходит за поле или клетки механики пересекаются"
	var tints: Dictionary = ShikakuSolver.rules_of(d).tints
	var shapes := {}
	for i in sol.size():
		var r: Rect2i = sol[i]
		if r.position.x < 0 or r.position.y < 0 or r.end.x > cols or r.end.y > rows:
			return "прямоугольник %s выходит за поле" % str(r)
		var a := r.size.x * r.size.y
		if not ShikakuSolver.tint_ok(r, tints):
			return "прямоугольник %s накрывает цветную клетку другой площади" % str(r)
		if a < 2 or a > limit or maxi(r.size.x, r.size.y) > max_side:
			return "недопустимый прямоугольник %s (лимит площади %d, стороны %d)" % [str(r), limit, max_side]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if used[y * cols + x] != 0:
					return "пересечение в клетке (%d, %d)" % [x, y]
				used[y * cols + x] = 1
		var num: Dictionary = nums[i]
		var pos: Vector2i = num.pos
		if not r.has_point(pos):
			return "число в %s вне своего прямоугольника %s" % [str(pos), str(r)]
		if int(num.value) != a and int(num.value) != ShikakuSolver.ANY:
			return "число %d в прямоугольнике площади %d" % [int(num.value), a]
		var k := ShikakuSolver.shape_key(r.size)
		shapes[k] = int(shapes.get(k, 0)) + 1
	for c in used:
		if c == 0:
			return "поле покрыто не полностью"
	for item in pcs:
		var k := ShikakuSolver.shape_key(item)
		shapes[k] = int(shapes.get(k, 0)) - 1
	for k in shapes:
		if int(shapes[k]) != 0:
			return "набор блоков не совпадает с решением"
	return ""


## Проверка решения от решателя (порядок прямоугольников произвольный).
static func _validate_solution(d: Dictionary, solution: Array) -> String:
	var cols: int = d.cols
	var rows: int = d.rows
	if solution.size() != (d.pieces as Array).size():
		return "в решении %d прямоугольников, блоков %d" % [solution.size(), (d.pieces as Array).size()]
	var used := _mech_cells(d)
	if used.is_empty():
		return "механика выходит за поле или клетки механики пересекаются"
	var tints: Dictionary = ShikakuSolver.rules_of(d).tints
	var shapes := {}
	for item in solution:
		var r: Rect2i = item
		if r.position.x < 0 or r.position.y < 0 or r.end.x > cols or r.end.y > rows:
			return "прямоугольник %s выходит за поле" % str(r)
		if not ShikakuSolver.tint_ok(r, tints):
			return "прямоугольник %s накрывает цветную клетку другой площади" % str(r)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if used[y * cols + x] != 0:
					return "пересечение в клетке (%d, %d)" % [x, y]
				used[y * cols + x] = 1
		var inside := 0
		var value := 0
		for num in d.numbers:
			if r.has_point(num.pos):
				inside += 1
				value = int(num.value)
		if inside != 1 or (value != r.size.x * r.size.y and value != ShikakuSolver.ANY):
			return "прямоугольник %s нарушает правило (чисел внутри: %d)" % [str(r), inside]
		var k := ShikakuSolver.shape_key(r.size)
		shapes[k] = int(shapes.get(k, 0)) + 1
	for c in used:
		if c == 0:
			return "поле покрыто не полностью"
	for item in d.pieces:
		var k := ShikakuSolver.shape_key(item)
		shapes[k] = int(shapes.get(k, 0)) - 1
	for k in shapes:
		if int(shapes[k]) != 0:
			return "набор блоков не совпадает"
	return ""


## Клетки поля, занятые механикой до игры (19.5e): 1 — препятствие или закреплённый блок, 0 — свободна. Пустой
## массив — механика выходит за поле или её клетки пересекаются. У классического уровня — все 0.
static func _mech_cells(d: Dictionary) -> PackedByteArray:
	var cols: int = d.cols
	var rows: int = d.rows
	var used := PackedByteArray()
	used.resize(cols * rows)
	used.fill(0)
	for c: Vector2i in ShikakuSolver.rules_of(d).blocked:
		if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows or used[c.y * cols + c.x] != 0:
			return PackedByteArray()
		used[c.y * cols + c.x] = 1
	return used


## Все прямоугольники-кандидаты для первого хода (порядок как в tools/make_expected.py).
static func _first_moves(d: Dictionary) -> Array[Rect2i]:
	var cols: int = d.cols
	var rows: int = d.rows
	var all_num := {}
	for item in d.numbers:
		all_num[item.pos] = true
	var shapes := {}
	for item in d.pieces:
		var k := ShikakuSolver.shape_key(item)
		shapes[k] = int(shapes.get(k, 0)) + 1
	var out: Array[Rect2i] = []
	for item in d.numbers:
		var p: Vector2i = item.pos
		var v := int(item.value)
		for w in range(1, v + 1):
			if v % w != 0:
				continue
			@warning_ignore("integer_division")
			var h := v / w
			if w > cols or h > rows or int(shapes.get(ShikakuSolver.shape_key(Vector2i(w, h)), 0)) == 0:
				continue
			for y0 in range(maxi(0, p.y - h + 1), mini(p.y, rows - h) + 1):
				for x0 in range(maxi(0, p.x - w + 1), mini(p.x, cols - w) + 1):
					var r := Rect2i(x0, y0, w, h)
					if not _has_foreign(r, p, all_num):
						out.append(r)
	return out


static func _has_foreign(r: Rect2i, own: Vector2i, all_num: Dictionary) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if c != own and all_num.has(c):
				return true
	return false


## Строка статусов решателя для всех первых ходов: 0 — решается, 1 — тупик, 2 — лимит.
static func _first_move_statuses(d: Dictionary) -> String:
	var s := ""
	for item in _first_moves(d):
		var r: Rect2i = item
		var pieces: Array[Vector2i] = []
		pieces.assign(d.pieces)
		var k := ShikakuSolver.shape_key(r.size)
		for i in pieces.size():
			if ShikakuSolver.shape_key(pieces[i]) == k:
				pieces.remove_at(i)
				break
		var placed: Array[Rect2i] = [r]
		var sv := ShikakuSolver.run(d.cols, d.rows, d.numbers, placed, pieces)
		s += str(sv.status)
	return s


# --- 5. Очки и сохранения --------------------------------------------------------

func _test_scoring() -> void:
	_section("Очки и сохранения")
	GameState.reset_progress()
	_check(GameState.total_score == 0 and GameState.level == 1, "сброс прогресса не обнулил счёт")

	var gain := GameState.complete_level(1, 3, 300)
	_check(gain == 300 and GameState.total_score == 300, "первое прохождение: прирост %d, счёт %d (ждали 300/300)" % [gain, GameState.total_score])
	gain = GameState.complete_level(1, 2, 200)
	_check(gain == 0 and GameState.total_score == 300, "переигровка хуже рекорда изменила счёт: прирост %d, счёт %d" % [gain, GameState.total_score])
	_check(GameState.get_stars(1) == 3, "переигровка уменьшила звёзды")
	gain = GameState.complete_level(1, 3, 350)
	_check(gain == 50 and GameState.total_score == 350, "новый рекорд: прирост %d, счёт %d (ждали 50/350)" % [gain, GameState.total_score])
	_check(GameState.level == 2, "после уровня 1 открыт уровень %d" % GameState.level)

	# Сохранение v2 (до исправления): только общий счёт -> legacy_score.
	GameState.apply_save_data({"version": 2, "level": 5, "total_score": 1000, "sound_on": true,
			"level_stars": {"1": 3, "2": 2}})
	_check(GameState.total_score == 1000 and GameState.legacy_score == 1000 and GameState.level == 5,
			"миграция v2: счёт %d, legacy %d, уровень %d" % [GameState.total_score, GameState.legacy_score, GameState.level])
	_check(GameState.get_stars(2) == 2 and GameState.get_best(1) == 0, "миграция v2: звёзды или рекорды неверны")

	# Облако с другого устройства: берём лучшее по каждому уровню.
	var cloud := {"version": 3, "level": 7, "legacy_score": 500, "sound_on": true,
			"level_stars": {"2": 3, "6": 1}, "level_best": {"6": 120}}
	var changed := GameState.merge_save_data(cloud)
	_check(changed, "слияние облака не увидело изменений")
	_check(GameState.level == 7 and GameState.get_stars(2) == 3 and GameState.get_best(6) == 120,
			"слияние облака: уровень %d, звёзды(2) %d, рекорд(6) %d" % [GameState.level, GameState.get_stars(2), GameState.get_best(6)])
	_check(GameState.total_score == 1120, "слияние облака: счёт %d (ждали 1000 + 120)" % GameState.total_score)
	_check(not GameState.merge_save_data(cloud), "повторное слияние того же облака что-то изменило")

	# Круг «сохранить -> загрузить» не меняет прогресс.
	var data := GameState.get_save_data()
	var json_data: Variant = JSON.parse_string(JSON.stringify(data))  # как в облаке: ключи-строки, числа float
	GameState.reset_progress()
	GameState.apply_save_data(json_data)
	_check(GameState.total_score == 1120 and GameState.get_best(6) == 120 and GameState.level == 7,
			"после круга через JSON: счёт %d, рекорд(6) %d, уровень %d" % [GameState.total_score, GameState.get_best(6), GameState.level])
	GameState.reset_progress()
	print("  рекорды по уровням, миграция и слияние проверены")


func _test_daily() -> void:
	_section("Ежедневная задача (18.1)")
	var old := GameState.get_save_data()
	var d0 := "2026-10-08"
	var d1 := "2026-10-09"
	_check(DailyChallenge.is_valid_date(d0) and DailyChallenge.is_valid_date(d1), "валидная дата ежедневной задачи отклонена")
	_check(DailyChallenge.day_number(d1) == DailyChallenge.day_number(d0) + 1, "номер дня не увеличился на 1")
	var l0 := DailyChallenge.level_for_date(d0)
	_check(l0 >= DailyChallenge.FIRST_LEVEL and l0 <= DailyChallenge.LAST_LEVEL,
			"уровень дня вне диапазона: %d" % l0)
	_check(l0 == DailyChallenge.level_for_date(d0), "одна дата дала разные уровни")
	GameState.reset_progress()
	_check(GameState.complete_daily(d0, 3, 150) and GameState.daily_streak == 1,
			"первая ежедневная задача не начала серию: %d" % GameState.daily_streak)
	_check(GameState.daily_is_completed(d0) and GameState.daily_best_streak == 1,
			"ежедневная задача не сохранилась")
	GameState.complete_daily(d0, 2, 100)
	_check(GameState.daily_streak == 1 and GameState.daily_last_score == 150 and GameState.daily_last_stars == 3,
			"повтор в тот же день сбросил лучший результат")
	GameState.complete_daily(d1, 2, 100)
	_check(GameState.daily_streak == 2 and GameState.daily_best_streak == 2,
			"задача на следующий день не продолжила серию")
	GameState.apply_save_data(old)
	print("  UTC-дата, детерминированный уровень, серия и повтор в тот же день")


## Поколения прогресса: сброс из настроек не возвращается облаком, а облако
## нового поколения (сброс на другом устройстве) заменяет локальный прогресс.
func _test_epoch() -> void:
	_section("Поколения прогресса (сброс)")
	GameState.reset_progress()
	var e0 := GameState.epoch
	GameState.complete_level(1, 3, 300)
	var old_cloud := GameState.get_save_data()
	GameState.wipe_progress()
	_check(GameState.epoch == e0 + 1 and GameState.level == 1 and GameState.total_score == 0 and GameState.get_stars(1) == 0,
			"сброс: поколение %d (ждали %d), уровень %d, счёт %d" % [GameState.epoch, e0 + 1, GameState.level, GameState.total_score])
	var changed := GameState.merge_save_data(old_cloud)
	_check(not changed and GameState.level == 1 and GameState.total_score == 0,
			"облако до сброса вернуло прогресс: уровень %d, счёт %d" % [GameState.level, GameState.total_score])

	# Облако новее: заменяет локальный прогресс целиком, а не сливается с ним.
	GameState.complete_level(1, 3, 300)
	var new_cloud := {"version": 4, "epoch": e0 + 2, "level": 3, "legacy_score": 0,
			"level_stars": {"1": 1, "2": 2}, "level_best": {"1": 100, "2": 150}}
	_check(GameState.merge_save_data(new_cloud), "облако нового поколения не применилось")
	_check(GameState.epoch == e0 + 2 and GameState.get_best(1) == 100 and GameState.total_score == 250 and GameState.level == 3,
			"облако нового поколения: поколение %d, рекорд(1) %d, счёт %d, уровень %d (ждали %d/100/250/3)" % [
				GameState.epoch, GameState.get_best(1), GameState.total_score, GameState.level, e0 + 2])

	# Поколение переживает JSON (облако) и файл; в сохранениях до v4 его нет — 0.
	var json_data: Variant = JSON.parse_string(JSON.stringify(GameState.get_save_data()))
	GameState.apply_save_data({"version": 3, "level": 1})
	_check(GameState.epoch == 0, "сохранение v3 без поколения: epoch %d (ждали 0)" % GameState.epoch)
	GameState.apply_save_data(json_data)
	_check(GameState.epoch == e0 + 2, "поколение потерялось после круга через JSON: %d" % GameState.epoch)
	GameState.save_game()
	GameState.epoch = 0
	GameState.load_game()
	_check(GameState.epoch == e0 + 2, "поколение потерялось после записи в файл: %d" % GameState.epoch)
	GameState.reset_progress()
	print("  сброс не возвращается из облака, облако нового поколения заменяет прогресс")


## Подделка JS-моста YSDK (window.GodotYSDK) для 16.3: записывает вызовы вместо Яндекса.
class FakeBridge extends RefCounted:
	var scores: Array = []  # [таблица, значение] — вызовы setScore по порядку
	var other: Array = []   # прочие вызовы (их здесь быть не должно, кроме saveData)

	func setScore(board: String, value: int) -> void:
		scores.append([board, value])

	func saveData(_json: String) -> void:
		other.append("saveData")

	func gameplay(_active: bool) -> void:
		other.append("gameplay")

	func requestReview() -> void:
		other.append("requestReview")

	func checkReview() -> void:
		other.append("checkReview")

	func openAuth() -> void:
		other.append("openAuth")

	func loadFlags(defaults_json: String) -> void:
		other.append("loadFlags " + defaults_json)


## Таблицы лидеров после сброса прогресса (16.3a): лучшее, что Яндекс принял (GameState.leaderboard_sent), не
## сбрасывается, переживает JSON, файл и облако любого поколения; YSDK.submit_score не отправляет значение не больше
## принятого — после сброса счёт уходит в таблицу, только когда перерастёт прежний.
func _test_leaderboard_sent() -> void:
	_section("Таблицы лидеров после сброса (16.3)")
	var board := YSDK.LEADERBOARD_NAME
	var streak_board := YSDK.DAILY_LEADERBOARD_NAME
	var saved_sent := GameState.leaderboard_sent.duplicate()
	GameState.leaderboard_sent = {}
	GameState.reset_progress()
	_check(GameState.leaderboard_best(board) == 0 and GameState.SAVE_VERSION >= 7,
			"чистое сохранение: принято %d, версия %d (таблицы — с v7)" % [GameState.leaderboard_best(board), GameState.SAVE_VERSION])
	_check(GameState.note_leaderboard_sent(board, 500) and not GameState.note_leaderboard_sent(board, 300)
			and not GameState.note_leaderboard_sent(board, 500) and GameState.leaderboard_best(board) == 500,
			"принятое: только рост (500, затем 300 и 500) — %d" % GameState.leaderboard_best(board))
	_check(not GameState.note_leaderboard_sent("", 900) and not GameState.leaderboard_sent.has(""),
			"принятое без имени таблицы записалось")
	GameState.note_leaderboard_sent(streak_board, 4)
	GameState.complete_level(1, 3, 300)
	var e0 := GameState.epoch
	GameState.wipe_progress()
	GameState.reset_progress()
	_check(GameState.epoch == e0 + 1 and GameState.total_score == 0 and GameState.leaderboard_best(board) == 500
			and GameState.leaderboard_best(streak_board) == 4,
			"сброс прогресса тронул таблицы: счёт %d, принято %d / %d (ждали 0, 500 / 4)" % [GameState.total_score,
				GameState.leaderboard_best(board), GameState.leaderboard_best(streak_board)])
	# Круг через JSON (облако) и файл; старые сохранения и мусор — пусто.
	var json_data: Variant = JSON.parse_string(JSON.stringify(GameState.get_save_data()))
	GameState.leaderboard_sent = {}
	GameState.apply_save_data(json_data)
	_check(GameState.leaderboard_sent == {board: 500, streak_board: 4},
			"таблицы после круга через JSON: %s" % str(GameState.leaderboard_sent))
	GameState.save_game()
	GameState.leaderboard_sent = {}
	GameState.load_game()
	_check(GameState.leaderboard_sent == {board: 500, streak_board: 4},
			"таблицы после записи в файл: %s" % str(GameState.leaderboard_sent))
	var keep := GameState.get_save_data()
	GameState.apply_save_data({"version": 6, "level": 1})
	_check(GameState.leaderboard_sent.is_empty(), "сохранение v6 без таблиц: %s" % str(GameState.leaderboard_sent))
	GameState.apply_save_data({"version": 7, "level": 1, "leaderboard": {board: -5, streak_board: "7", "": 3, "x": 2.0}})
	_check(GameState.leaderboard_sent == {"x": 2}, "мусор в таблицах сохранения: %s" % str(GameState.leaderboard_sent))
	GameState.apply_save_data({"version": 7, "level": 1, "leaderboard": [1, 2]})
	_check(GameState.leaderboard_sent.is_empty(), "таблицы-массив в сохранении: %s" % str(GameState.leaderboard_sent))
	GameState.apply_save_data(keep)
	# Облако: таблицы по максимуму при любом поколении, прогресс — по прежним правилам.
	var e1 := GameState.epoch
	GameState.complete_level(1, 3, 300)
	var old_cloud := {"version": 7, "epoch": e1 - 1, "level": 9, "level_best": {"1": 900, "2": 900},
			"leaderboard": {board: 2000, streak_board: 2}}
	_check(GameState.merge_save_data(old_cloud) and GameState.leaderboard_best(board) == 2000
			and GameState.leaderboard_best(streak_board) == 4 and GameState.total_score == 300 and GameState.level == 2,
			"облако до сброса: принято %d / %d (ждали 2000 / 4), счёт %d, уровень %d (прогресс не должен вернуться)" % [
				GameState.leaderboard_best(board), GameState.leaderboard_best(streak_board), GameState.total_score, GameState.level])
	_check(not GameState.merge_save_data(old_cloud), "повторное слияние того же облака до сброса что-то изменило")
	var new_cloud := {"version": 7, "epoch": e1 + 1, "level": 3, "level_best": {"1": 100, "2": 150},
			"leaderboard": {board: 1000, streak_board: 6}}
	_check(GameState.merge_save_data(new_cloud) and GameState.epoch == e1 + 1 and GameState.total_score == 250
			and GameState.leaderboard_best(board) == 2000 and GameState.leaderboard_best(streak_board) == 6,
			"облако нового поколения: поколение %d, счёт %d, принято %d / %d (ждали %d, 250, 2000 / 6)" % [GameState.epoch,
				GameState.total_score, GameState.leaderboard_best(board), GameState.leaderboard_best(streak_board), e1 + 1])
	var same := GameState.get_save_data()
	same["leaderboard"] = {board: 2500}
	_check(GameState.merge_save_data(same) and GameState.leaderboard_best(board) == 2500 and GameState.total_score == 250,
			"облако того же поколения: принято %d (ждали 2500), счёт %d" % [GameState.leaderboard_best(board), GameState.total_score])

	# Отправка: подделка моста вместо Яндекса. Вне веба _process у YSDK выключен — мост сам никто не опрашивает.
	var saved_bridge: Variant = YSDK._bridge
	var saved_available := YSDK.is_available
	var saved_authorized := YSDK.is_authorized
	var saved_cloud := YSDK._cloud_ready
	var saved_resubmit := YSDK._resubmit_after_cloud
	var fake := FakeBridge.new()
	YSDK._bridge = fake
	YSDK.is_available = true
	YSDK.is_authorized = true
	YSDK._cloud_ready = false
	GameState.leaderboard_sent = {}
	GameState.reset_progress()
	GameState.complete_level(1, 3, 300)
	_check(fake.scores == [[board, 300]], "первый уровень: отправлено %s (ждали %s)" % [str(fake.scores), str([[board, 300]])])
	_check(GameState.leaderboard_best(board) == 0, "принятое выросло без ответа Яндекса: %d" % GameState.leaderboard_best(board))
	GameState.complete_level(1, 2, 200)
	_check(fake.scores.size() == 2 and fake.scores[1] == [board, 300],
			"переигровка до ответа Яндекса: непринятый счёт не отправлен снова — %s" % str(fake.scores))
	YSDK._handle_event("score_set", {"name": board, "score": 300.0})  # из JSON числа приходят float
	_check(GameState.leaderboard_best(board) == 300, "ответ Яндекса не записан: принято %d" % GameState.leaderboard_best(board))
	GameState.complete_level(1, 2, 200)
	_check(fake.scores.size() == 2, "переигровка без прироста отправила тот же счёт: %s" % str(fake.scores))
	GameState.complete_level(2, 3, 400)
	YSDK._handle_event("score_set", {"name": board, "score": 700})
	_check(fake.scores.back() == [board, 700] and GameState.leaderboard_best(board) == 700,
			"рост счёта: отправлено %s, принято %d (ждали 700)" % [str(fake.scores.back()), GameState.leaderboard_best(board)])
	# Сброс → уровень 1: 300 < 700 — в таблицу не идёт ни после уровня, ни после входа.
	var n := fake.scores.size()
	GameState.wipe_progress()
	GameState.complete_level(1, 3, 300)
	YSDK.submit_scores()
	_check(fake.scores.size() == n and GameState.leaderboard_best(board) == 700 and GameState.total_score == 300,
			"после сброса меньший счёт ушёл в таблицу: %s, принято %d" % [str(fake.scores.slice(n)), GameState.leaderboard_best(board)])
	GameState.complete_level(2, 3, 400)
	_check(fake.scores.size() == n, "после сброса равный прежнему счёт (700) отправлен повторно: %s" % str(fake.scores.slice(n)))
	GameState.complete_level(3, 3, 50)
	_check(fake.scores.slice(n) == [[board, 750]], "после сброса счёт перерос прежний — отправлено %s (ждали %s)" % [
			str(fake.scores.slice(n)), str([[board, 750]])])
	# Ответ старого вида (только имя) и чужой таблицы не ломают принятое.
	YSDK._handle_event("score_set", board)
	YSDK._handle_event("score_set", {"name": streak_board, "score": "9"})
	_check(GameState.leaderboard_best(board) == 700 and GameState.leaderboard_best(streak_board) == 0,
			"ответ без числа изменил принятое: %s" % str(GameState.leaderboard_sent))
	# Серия: меньшая принятой не уходит, большая — уходит.
	GameState.note_leaderboard_sent(streak_board, 2)
	n = fake.scores.size()
	GameState.complete_daily("2026-10-08", 3, 150)
	GameState.complete_daily("2026-10-09", 3, 150)
	_check(fake.scores.slice(n).is_empty() and GameState.daily_streak == 2,
			"серия 1 и 2 при принятой 2: отправлено %s" % str(fake.scores.slice(n)))
	GameState.complete_daily("2026-10-10", 3, 150)
	_check(fake.scores.slice(n) == [[streak_board, 3]], "серия 3 при принятой 2: отправлено %s" % str(fake.scores.slice(n)))
	# Гость и вне Яндекса: submit_scores молчит, submit_score без SDK — тоже.
	n = fake.scores.size()
	GameState.complete_level(4, 3, 500)
	YSDK.is_authorized = false
	YSDK.submit_scores()
	YSDK.is_available = false
	_check(not YSDK.submit_score(board, 99999) and fake.scores.size() == n + 1 and fake.other.is_empty(),
			"гость / без SDK: отправлено %s, прочие вызовы моста %s" % [str(fake.scores.slice(n)), str(fake.other)])
	YSDK._bridge = saved_bridge
	YSDK.is_available = saved_available
	YSDK.is_authorized = saved_authorized
	YSDK._cloud_ready = saved_cloud
	YSDK._resubmit_after_cloud = saved_resubmit
	GameState.leaderboard_sent = saved_sent
	GameState.reset_progress()
	print("  принятое Яндексом переживает сброс, JSON, файл и облако любого поколения; меньший и равный счёт и серия "
			+ "в таблицу не уходят, после сброса — только когда перерастут прежние; гость и без SDK — без отправки")


## Функции Яндекса (16.2a): флаги Remote Config и запрос отзыва — по событиям JS (мост — FakeBridge). Ярлык и
## tutorial_variant убраны 10.10 (16.2b, 16.2c): старый флаг, оставшийся в консоли, игра пропускает.
func _test_yandex_features() -> void:
	_section("Функции Яндекса: флаги и отзыв (16.2)")
	# Флаги: getFlags отдаёт строки; мусор — значение по умолчанию, вне пределов — край.
	var lo := YSDK.FLAG_FROM_LEVEL_MIN
	var hi := YSDK.FLAG_FROM_LEVEL_MAX
	var cases := [[{"k": "7"}, 7], [{"k": " 12 "}, 12], [{"k": "0"}, lo], [{"k": "-3"}, lo], [{"k": "5000"}, hi],
			[{"k": "abc"}, 4], [{"k": ""}, 4], [{"k": "1.5"}, 4], [{"k": 9}, 9], [{"k": null}, 4], [{}, 4],
			[{"k": [1]}, 4]]
	for c: Array in cases:
		_check(YSDK.flag_int(c[0], "k", 4, lo, hi) == c[1], "flag_int(%s) = %d, ждали %d" % [str(c[0]),
				YSDK.flag_int(c[0], "k", 4, lo, hi), c[1]])
	var defaults := YSDK.flag_defaults()
	_check(defaults == {"interstitial_from_level": str(YSDK.DEFAULT_INTERSTITIAL_FROM_LEVEL),
			"interstitial_interval_ms": str(YSDK.DEFAULT_INTERSTITIAL_INTERVAL_MS),
			"free_hints_per_level": str(YSDK.DEFAULT_FREE_HINTS_PER_LEVEL),
			"hearts": "3", "hearts_from_level": "4", "revive_max": "3", "revive_free_on_fail": "1"},
			"флаги по умолчанию: %s" % str(defaults))
	var saved_flags := [YSDK.interstitial_from_level, YSDK.interstitial_interval_ms, YSDK._free_hints,
			YSDK.flags_ready]
	# tutorial_variant — флаг, убранный в 16.2c: если он остался в консоли, игра его не читает и не падает.
	YSDK._handle_event("flags", {"interstitial_from_level": "6", "interstitial_interval_ms": "120000",
			"free_hints_per_level": "2", "tutorial_variant": " short "})
	_check(YSDK.interstitial_from_level == 6 and YSDK.interstitial_interval_ms == 120000
			and YSDK.free_hints_per_level() == 2 and YSDK.flags_ready,
			"флаги из консоли: %d / %d / %d" % [YSDK.interstitial_from_level, YSDK.interstitial_interval_ms,
				YSDK.free_hints_per_level()])
	YSDK._handle_event("flags", {"interstitial_from_level": "abc", "interstitial_interval_ms": "1000",
			"free_hints_per_level": "99"})
	_check(YSDK.interstitial_from_level == YSDK.DEFAULT_INTERSTITIAL_FROM_LEVEL
			and YSDK.interstitial_interval_ms == YSDK.FLAG_INTERVAL_MS_MIN
			and YSDK.free_hints_per_level() == YSDK.FLAG_FREE_HINTS_MAX,
			"мусорные флаги: %d / %d / %d" % [YSDK.interstitial_from_level, YSDK.interstitial_interval_ms,
				YSDK.free_hints_per_level()])
	YSDK._handle_event("flags", null)  # getFlags не ответил как надо — всё по умолчанию
	_check(YSDK.interstitial_from_level == YSDK.DEFAULT_INTERSTITIAL_FROM_LEVEL
			and YSDK.interstitial_interval_ms == YSDK.DEFAULT_INTERSTITIAL_INTERVAL_MS
			and YSDK.free_hints_per_level() == YSDK.DEFAULT_FREE_HINTS_PER_LEVEL, "флаги без ответа — не по умолчанию")
	# Сердца (20.1a): из консоли; мусор — по умолчанию, вне пределов — край; revive_free_on_fail — только 0 / 1.
	YSDK._handle_event("flags", {"hearts": "5", "hearts_from_level": "10", "revive_max": "0",
			"revive_free_on_fail": "0"})
	_check(YSDK.hearts() == 5 and YSDK.hearts_from_level() == 10 and YSDK.revive_max() == 0
			and not YSDK.revive_free_on_fail(), "флаги сердец из консоли: %d / %d / %d / %s" % [YSDK.hearts(),
			YSDK.hearts_from_level(), YSDK.revive_max(), YSDK.revive_free_on_fail()])
	YSDK._handle_event("flags", {"hearts": "9", "hearts_from_level": "abc", "revive_max": "99",
			"revive_free_on_fail": "7"})
	_check(YSDK.hearts() == YSDK.FLAG_HEARTS_MAX and YSDK.hearts_from_level() == YSDK.DEFAULT_HEARTS_FROM_LEVEL
			and YSDK.revive_max() == YSDK.FLAG_REVIVE_MAX and YSDK.revive_free_on_fail(),
			"мусорные флаги сердец: %d / %d / %d / %s" % [YSDK.hearts(), YSDK.hearts_from_level(), YSDK.revive_max(),
			YSDK.revive_free_on_fail()])
	YSDK._handle_event("flags", {"hearts": "0"})  # 0 — без предела (сердец не видно)
	_check(YSDK.hearts() == 0 and Hearts.max_for(20, false, false, YSDK.hearts(), YSDK.hearts_from_level()) == 0,
			"флаг hearts = 0: сердец %d" % YSDK.hearts())
	YSDK._handle_event("flags", null)
	_check(YSDK.hearts() == YSDK.DEFAULT_HEARTS and YSDK.hearts_from_level() == YSDK.DEFAULT_HEARTS_FROM_LEVEL
			and YSDK.revive_max() == YSDK.DEFAULT_REVIVE_MAX and YSDK.revive_free_on_fail(),
			"флаги сердец без ответа — не по умолчанию")
	YSDK.interstitial_from_level = saved_flags[0]
	YSDK.interstitial_interval_ms = saved_flags[1]
	YSDK._free_hints = saved_flags[2]
	YSDK.flags_ready = saved_flags[3]

	# Отзыв: победа на уровнях 11–15 (12.10b; было 5–7), одна просьба за сессию; запоминается, только когда окно показано
	# или отказ навсегда.
	var saved_bridge: Variant = YSDK._bridge
	var saved_available := YSDK.is_available
	var saved_cloud := YSDK._cloud_ready
	var saved_asked := YSDK._review_requested_this_session
	var saved_auto := YSDK._auto_review_tried
	var saved_after := YSDK._review_after_auth
	var saved_auth := [YSDK.auth_known, YSDK.is_authorized, YSDK.player_id, YSDK._auth_requested,
			YSDK._resubmit_after_cloud]
	var saved_prompted := GameState.review_prompted
	var saved_sent := GameState.leaderboard_sent.duplicate()
	var fake := FakeBridge.new()
	YSDK._bridge = fake
	YSDK._cloud_ready = false
	YSDK.is_available = false
	YSDK._review_requested_this_session = false
	YSDK._auto_review_tried = false
	YSDK._review_after_auth = false
	GameState.review_prompted = false
	GameState.reset_progress()
	_check(YSDK.REVIEW_FROM_LEVEL == 11 and YSDK.REVIEW_TO_LEVEL == 15,
			"просьба оценить — на уровнях %d–%d (ждали 11–15)" % [YSDK.REVIEW_FROM_LEVEL, YSDK.REVIEW_TO_LEVEL])
	for lvl in range(1, YSDK.REVIEW_FROM_LEVEL + 1):
		GameState.complete_level(lvl, 3, 100)
	_check(fake.other.is_empty() and not YSDK._review_requested_this_session and not YSDK._auto_review_tried
			and not GameState.review_prompted, "отзыв без SDK: вызовы %s, запрос в сессии %s, запомнен %s" % [
				str(fake.other), YSDK._review_requested_this_session, GameState.review_prompted])
	YSDK.is_available = true
	for lvl in range(1, YSDK.REVIEW_FROM_LEVEL):
		GameState.complete_level(lvl, 3, 100)
	_check(fake.other.is_empty(), "отзыв на уровнях 1–10: %s" % str(fake.other))
	GameState.complete_level(11, 3, 100)
	GameState.complete_level(12, 3, 100)
	_check(fake.other == ["requestReview"] and not GameState.review_prompted,
			"отзыв на уровнях 11 и 12: вызовы %s (ждали один запрос), запомнен до ответа %s" % [str(fake.other),
				GameState.review_prompted])
	YSDK._handle_event("review", {"value": false, "reason": "NO_AUTH"})
	_check(not GameState.review_prompted and _goal_params("review") == {"review": "no_auth"}
			and not YSDK._review_requested_this_session,
			"гость (NO_AUTH): запомнен %s, цель %s, запрос в сессии потрачен %s" % [GameState.review_prompted,
				str(Analytics.last("review")), YSDK._review_requested_this_session])
	GameState.complete_level(13, 3, 100)
	_check(fake.other == ["requestReview"], "после NO_AUTH игра просит снова в той же сессии: %s" % str(fake.other))
	YSDK._review_requested_this_session = false  # новая сессия
	YSDK._auto_review_tried = false
	fake.other.clear()
	GameState.complete_level(16, 3, 100)
	_check(fake.other.is_empty(), "отзыв на уровне 16: %s" % str(fake.other))
	GameState.complete_level(15, 3, 100)
	_check(fake.other == ["requestReview"], "новая сессия, уровень 15: вызовы %s" % str(fake.other))
	YSDK._handle_event("review", {"feedbackSent": false})
	_check(GameState.review_prompted and _goal_params("review") == {"review": "closed"},
			"окно отзыва закрыто: запомнен %s, цель %s" % [GameState.review_prompted, str(Analytics.last("review"))])
	YSDK._review_requested_this_session = false
	YSDK._auto_review_tried = false
	fake.other.clear()
	GameState.complete_level(12, 3, 100)
	_check(fake.other.is_empty(), "отзыв после показанного окна запрошен снова: %s" % str(fake.other))
	for c: Array in [[{"value": false, "reason": "GAME_RATED"}, true], [{"value": false, "reason": "UNKNOWN"}, false],
			[{"feedbackSent": true}, true], [null, false]]:
		GameState.review_prompted = false
		YSDK._handle_event("review", c[0])
		_check(GameState.review_prompted == c[1], "ответ отзыва %s: запомнен %s, ждали %s" % [str(c[0]),
				GameState.review_prompted, c[1]])
	# «Оценить игру» в настройках (12.10b): вошедшему — по ответу canReview; нажатие — тот же запрос, один за сессию.
	var saved_can := YSDK._can_review
	var saved_stub := YSDK.review_stub
	var saved_pending := YSDK.sdk_pending
	var avail := {"n": 0}
	var on_avail := _count.bind(avail, "n")
	YSDK.review_availability_changed.connect(on_avail)
	YSDK._review_requested_this_session = false
	YSDK._can_review = false
	YSDK.auth_known = true
	YSDK.is_authorized = true
	GameState.review_prompted = false
	fake.other.clear()
	YSDK._check_review()
	_check(fake.other == ["checkReview"] and not YSDK.can_offer_review() and not YSDK.request_review_by_player()
			and fake.other == ["checkReview"], "«Оценить игру» до разрешения canReview: вызовы %s" % str(fake.other))
	YSDK._handle_event("can_review", {"value": true})
	_check(YSDK.can_offer_review() and int(avail["n"]) == 1, "canReview разрешил, а кнопки нет (сигналов %d)" % int(avail["n"]))
	_check(YSDK.request_review_by_player() and fake.other == ["checkReview", "requestReview"] and not YSDK.can_offer_review()
			and int(avail["n"]) == 2, "нажатие «Оценить игру»: вызовы %s, сигналов %d" % [str(fake.other), int(avail["n"])])
	_check(not YSDK.request_review_by_player() and fake.other.size() == 2, "второй запрос оценки в сессии: %s" % str(fake.other))
	YSDK._handle_event("review", {"feedbackSent": true})
	_check(not YSDK.can_offer_review() and GameState.review_prompted, "после оценки кнопка осталась или не запомнено")
	YSDK._review_requested_this_session = false
	YSDK._handle_event("can_review", {"value": false, "reason": "GAME_RATED"})
	_check(not YSDK.can_offer_review(), "canReview отказал (GAME_RATED), а кнопка есть")
	# Гость (12.10b): кнопка видна, как только вход известен; нажатие — окно входа; отказался — кнопка вернулась;
	# вошёл — сразу запрос оценки (без лишнего canReview); окно оценки уже видел — кнопки нет.
	YSDK.auth_known = false
	YSDK.is_authorized = false
	YSDK._review_requested_this_session = false
	YSDK._can_review = false
	GameState.review_prompted = false
	_check(not YSDK.can_offer_review(), "гостю «Оценить игру» видна, пока вход не известен")
	fake.other.clear()
	avail["n"] = 0
	YSDK._handle_event("auth", {"authorized": false, "id": ""})
	_check(YSDK.can_offer_review() and fake.other == ["checkReview"] and int(avail["n"]) >= 1,
			"гость: нет кнопки, когда вход узнали (вызовы %s, сигналов %d)" % [str(fake.other), int(avail["n"])])
	YSDK._handle_event("can_review", {"value": false, "reason": "NO_AUTH"})
	_check(YSDK.can_offer_review(), "гость: ответ canReview NO_AUTH спрятал кнопку")
	fake.other.clear()
	_check(YSDK.request_review_by_player() and fake.other == ["openAuth"] and YSDK._auth_requested
			and not YSDK.can_offer_review(), "гость нажал «Оценить игру»: вызовы %s, кнопка %s" % [str(fake.other),
				YSDK.can_offer_review()])
	_check(not YSDK.request_review_by_player() and fake.other == ["openAuth"], "второе нажатие, пока открыт вход: %s"
			% str(fake.other))
	YSDK._handle_event("auth", {"authorized": false, "id": "", "cancelled": true})
	_check(YSDK.can_offer_review() and fake.other == ["openAuth"] and not YSDK._review_after_auth,
			"гость отказался от входа: кнопка %s, вызовы %s" % [YSDK.can_offer_review(), str(fake.other)])
	_check(YSDK.request_review_by_player() and fake.other == ["openAuth", "openAuth"], "гость нажал снова: %s"
			% str(fake.other))
	YSDK._handle_event("auth", {"authorized": true, "id": "p1"})
	_check(YSDK.is_authorized and fake.other == ["openAuth", "openAuth", "requestReview"] and not YSDK.can_offer_review(),
			"гость вошёл по «Оценить игру»: вызовы %s (ждали сразу requestReview), кнопка %s" % [str(fake.other),
				YSDK.can_offer_review()])
	YSDK._handle_event("review", {"value": false, "reason": "GAME_RATED"})
	_check(GameState.review_prompted and not YSDK.can_offer_review(), "вошёл, а игру уже оценивал: кнопка осталась")
	YSDK.is_authorized = false
	YSDK._review_requested_this_session = false
	_check(not YSDK.can_offer_review(), "гость, уже видевший окно оценки (review_prompted): кнопка есть")
	GameState.review_prompted = false
	YSDK._review_requested_this_session = false
	fake.other.clear()
	YSDK._auto_review_tried = false
	GameState.complete_level(14, 3, 100)
	YSDK._handle_event("review", {"value": false, "reason": "NO_AUTH"})
	_check(fake.other == ["requestReview"] and YSDK.can_offer_review(),
			"гость после просьбы на уровне 14 (NO_AUTH): вызовы %s, кнопка %s" % [str(fake.other), YSDK.can_offer_review()])
	# Вне Яндекс Игр — заглушка review_stub (отладочная сборка): видна, когда SDK уже не ждём; нажатие прячет её.
	YSDK.is_available = false
	YSDK.review_stub = true
	YSDK.sdk_pending = true
	_check(not YSDK.can_offer_review(), "заглушка «Оценить игру» видна, пока SDK ещё грузится")
	YSDK.sdk_pending = false
	fake.other.clear()
	_check(YSDK.can_offer_review() and YSDK.request_review_by_player() and not YSDK.can_offer_review()
			and fake.other.is_empty(), "заглушка «Оценить игру»: не спряталась после нажатия или вызвала мост %s" % str(fake.other))
	YSDK._review_requested_this_session = false
	YSDK.review_stub = false
	_check(not YSDK.can_offer_review(), "сборка для игроков вне Яндекс Игр: «Оценить игру» видна")
	YSDK.review_availability_changed.disconnect(on_avail)
	YSDK._can_review = saved_can
	YSDK.review_stub = saved_stub
	YSDK.sdk_pending = saved_pending
	YSDK._bridge = saved_bridge
	YSDK.is_available = saved_available
	YSDK._cloud_ready = saved_cloud
	YSDK._review_requested_this_session = saved_asked
	YSDK._auto_review_tried = saved_auto
	YSDK._review_after_auth = saved_after
	YSDK.auth_known = saved_auth[0]
	YSDK.is_authorized = saved_auth[1]
	YSDK.player_id = saved_auth[2]
	YSDK._auth_requested = saved_auth[3]
	YSDK._resubmit_after_cloud = saved_auth[4]
	YSDK._lb_cache.clear()
	GameState.review_prompted = saved_prompted
	GameState.save_settings()
	GameState.leaderboard_sent = saved_sent
	GameState.reset_progress()
	Analytics.journal.clear()
	print("  флаги: строки, мусор и пределы, по умолчанию — одни для JS и игры; отзыв: только 11–15, одна просьба за "
			+ "сессию, гость и сбой не запоминаются, показ и «уже оценил» — да; «Оценить игру»: вошедшему по canReview, "
			+ "гостю — вход, затем оценка; старый флаг tutorial_variant не мешает")


## Навыки обучения в сохранении (v5): биты переживают JSON и файл, облако
## сливается по OR, старые сохранения переносятся по уровню, сброс обнуляет.
func _test_tutorial_save() -> void:
	_section("Навыки обучения в сохранении")
	GameState.reset_progress()
	_check(GameState.tutorial == 0 and Tutorial.skill_for_level(1, 0) == Tutorial.DRAG,
			"после сброса навыки %d или уровню 1 не нужен DRAG" % GameState.tutorial)
	_check(Tutorial.skill_for_level(1, Tutorial.DRAG) == 0 and Tutorial.skill_for_level(Tutorial.GUARD_LEVELS + 1, 0) == 0,
			"skill_for_level: пройденный навык или уровень без навыка")
	GameState.learn(Tutorial.DRAG)
	_check(GameState.has_skill(Tutorial.DRAG) and not GameState.has_skill(Tutorial.ROTATE)
			and int(GameState.get_save_data().get("tutorial", 0)) == Tutorial.DRAG, "learn(DRAG) не попал в сохранение")
	_check(int(GameState.get_save_data().get("version", 0)) == GameState.SAVE_VERSION and GameState.SAVE_VERSION >= 5,
			"версия сохранения %d (навыки — с v5)" % GameState.SAVE_VERSION)

	# Облако того же поколения: навыки складываются, повтор ничего не меняет.
	var cloud := GameState.get_save_data()
	cloud["tutorial"] = Tutorial.ROTATE | Tutorial.UNDO
	_check(GameState.merge_save_data(cloud) and GameState.tutorial == (Tutorial.DRAG | Tutorial.ROTATE | Tutorial.UNDO),
			"облако: навыки не сложились (%d)" % GameState.tutorial)
	_check(not GameState.merge_save_data(cloud), "повторное слияние навыков что-то изменило")

	# JSON (облако) и файл.
	var json_data: Variant = JSON.parse_string(JSON.stringify(GameState.get_save_data()))
	var skills := GameState.tutorial
	GameState.apply_save_data({"version": 5, "level": 9, "tutorial": 0})
	_check(GameState.tutorial == 0, "v5 без навыков: навыки %d (ждали 0 — уровень не в счёт)" % GameState.tutorial)
	GameState.apply_save_data(json_data)
	_check(GameState.tutorial == skills, "навыки потерялись после круга через JSON: %d (ждали %d)" % [GameState.tutorial, skills])
	GameState.save_game()
	GameState.tutorial = 0
	GameState.load_game()
	_check(GameState.tutorial == skills, "навыки потерялись после записи в файл: %d" % GameState.tutorial)
	GameState.apply_save_data({"version": 5, "level": 1, "tutorial": 1024 | Tutorial.DRAG})
	_check(GameState.tutorial == Tutorial.DRAG, "лишние биты навыков не отброшены: %d" % GameState.tutorial)

	# До v5 навыков не было: прошёл обучающие уровни — обучен, нет — учим с начала.
	GameState.apply_save_data({"version": 4, "level": Tutorial.GUARD_LEVELS + 1})
	_check(GameState.tutorial == Tutorial.ALL, "перенос v4 (уровень %d): навыки %d (ждали все)" % [Tutorial.GUARD_LEVELS + 1, GameState.tutorial])
	GameState.apply_save_data({"version": 4, "level": Tutorial.GUARD_LEVELS})
	_check(GameState.tutorial == 0, "перенос v4 (уровень %d): навыки %d (ждали 0)" % [Tutorial.GUARD_LEVELS, GameState.tutorial])
	GameState.apply_save_data({"version": 2, "level": 30, "total_score": 100})
	_check(GameState.tutorial == Tutorial.ALL, "перенос v2 (уровень 30): навыки %d (ждали все)" % GameState.tutorial)
	GameState.reset_progress()
	_check(GameState.tutorial == 0, "сброс прогресса не обнулил навыки")
	print("  навыки: v5, облако (OR), JSON и файл, перенос v2–v4, сброс")


# --- 6. Настройки и окно настроек ------------------------------------------------

# --- Звук (этап 15) -------------------------------------------------------------------

## Ноты пентатоники и до мажора по модулю октавы (15.2).
const PENTATONIC: Array[int] = [0, 2, 4, 7, 9]
const C_MAJOR: Array[int] = [0, 2, 4, 5, 7, 9, 11]


## Полутоны от C5 для высоты pitch (pitch_scale = 2^(полутоны / 12)).
static func _semitones(pitch: float) -> int:
	return roundi(12.0 * log(maxf(pitch, 0.001)) / log(2.0))


## Звук (15.1–15.3, 15.6) без игры: голоса, ноты в тональности, запрос при выключенных звуках, приглушение музыки.
## Шина SFX на время проверки заглушена — слышно не будет.
func _test_audio() -> void:
	_section("Звук (15)")
	# 1. Голоса: у каждого звука VOICES штук, один файл и громкость, шина SFX, по одному звуку на голос.
	var bad_voices: Array[String] = []
	for sound in Audio.SOUNDS:
		var vs: Array[AudioStreamPlayer] = Audio.voices(sound)
		var want := int(Audio.VOICES.get(sound, Audio.DEFAULT_VOICES))
		var ok := vs.size() == want
		for v in vs:
			ok = ok and v.stream != null and v.stream == vs[0].stream and v.bus == GameState.BUS_SFX \
					and v.max_polyphony == 1 and is_equal_approx(v.volume_db, vs[0].volume_db)
		if not ok:
			bad_voices.append("%s (голосов %d, ждали %d)" % [sound, vs.size(), want])
	_check(bad_voices.is_empty(), "голоса звуков: у каждого VOICES копий узла с тем же файлом, громкостью, шиной SFX "
			+ "и max_polyphony 1 — не так у: " + ", ".join(bad_voices))
	var extra: Array[String] = []
	for child in Audio.get_children():
		if child is AudioStreamPlayer and String(child.name) != "Music":
			var found := false
			for sound in Audio.SOUNDS:
				found = found or Audio.voices(sound).has(child)
			if not found:
				extra.append(String(child.name))
	_check(extra.is_empty(), "в Audio узлы звука вне Audio.SOUNDS: " + ", ".join(extra))
	# 2. Нота постановки: пентатоника; больше блок — не выше; серия — не ниже; серия не больше PLACE_STREAK_MAX.
	var bad_notes: Array[String] = []
	for area in range(1, 31):
		for streak in range(0, Audio.PLACE_STREAK_MAX + 3):
			var st: int = Audio.place_semitones(area, streak)
			if not PENTATONIC.has(posmod(st, 12)):
				bad_notes.append("площадь %d, серия %d: %d — не пентатоника" % [area, streak, st])
			if streak > 0 and st < Audio.place_semitones(area, streak - 1):
				bad_notes.append("площадь %d: серия %d ниже серии %d" % [area, streak, streak - 1])
			if area > 1 and st > Audio.place_semitones(area - 1, streak):
				bad_notes.append("серия %d: площадь %d выше площади %d" % [streak, area, area - 1])
			if not is_equal_approx(Audio.place_pitch(area, streak), pow(2.0, st / 12.0)):
				bad_notes.append("площадь %d, серия %d: place_pitch не 2^(%d/12)" % [area, streak, st])
	_check(bad_notes.size() == 0, "нота постановки (15.2): " + "; ".join(bad_notes.slice(0, 5)))
	_check(Audio.place_semitones(1, 99) == Audio.place_semitones(1, Audio.PLACE_STREAK_MAX)
			and Audio.place_semitones(12, 0) < Audio.place_semitones(1, 0)
			and Audio.place_semitones(4, 1) > Audio.place_semitones(4, 0),
			"нота постановки: серия не ограничена PLACE_STREAK_MAX, или большой блок не ниже маленького, или серия не выше")
	# 3. Линия (тоника, квинта, октава) при любой силе и звёзды — в до мажоре.
	var cfg := Juice.shared_config()
	var off_key: Array[String] = []
	for st in cfg.combo_semitones:
		for k in [0, 7, 12]:
			if not C_MAJOR.has(posmod(st + k, 12)):
				off_key.append("линия +%d: нота %d" % [st, st + k])
	for st in cfg.star_semitones:
		if not C_MAJOR.has(posmod(st, 12)):
			off_key.append("звезда %d" % st)
	_check(off_key.is_empty(), "звуки не в до мажоре: " + ", ".join(off_key))
	# 4. Голоса в деле: каждая нота — на своём голосе со своей высотой; лишняя — на старейшем, остальные не трогает.
	var sfx_bus := AudioServer.get_bus_index(GameState.BUS_SFX)
	var was_mute := AudioServer.is_bus_mute(sfx_bus)
	var was_sfx := GameState.sfx_on
	AudioServer.set_bus_mute(sfx_bus, true)
	GameState.sfx_on = true
	var notes: Array[AudioStreamPlayer] = Audio.voices(Audio.NOTE)
	var want_p: Array[float] = []
	for k in notes.size():
		var p: float = Audio.place_pitch(1 + 3 * k, 0)  # площади 1, 4, 7, 10 — четыре разные ноты
		want_p.append(p)
		Audio.play_pitched(Audio.NOTE, p)
	var got_p: Array[float] = []
	for v in notes:
		got_p.append(v.pitch_scale)
	want_p.sort()
	got_p.sort()
	var same := want_p.size() == got_p.size()
	for k in mini(want_p.size(), got_p.size()):
		same = same and is_equal_approx(want_p[k], got_p[k])
	_check(same, "голоса ноты: высоты голосов %s, ждали %s (каждая нота — на своём голосе)" % [str(got_p), str(want_p)])
	Audio.play_pitched(Audio.NOTE, 2.0)
	var with_new := 0
	var kept := 0
	for v in notes:
		if is_equal_approx(v.pitch_scale, 2.0):
			with_new += 1
			continue
		for p in want_p:
			if is_equal_approx(p, v.pitch_scale):
				kept += 1
				break
	_check(with_new == 1 and kept == notes.size() - 1 and is_equal_approx(Audio.last_pitch(Audio.NOTE), 2.0),
			"голоса ноты: лишняя нота заняла %d голос(а), прежние высоты у %d из %d (ждали 1 и %d)" % [with_new, kept,
			notes.size() - 1, notes.size() - 1])
	for v in notes:
		v.stop()
	# 5. Звуки выключены: запрос считается (и сигнал есть), но голоса не трогает и музыку не приглушает.
	GameState.sfx_on = false
	var asked := int(Audio.requests.get(Audio.MISS, 0))
	_sound_log.clear()
	Audio.requested.connect(_on_test_sound)
	Audio.play(Audio.MISS)
	Audio.play(Audio.WIN, 0.0)
	Audio.requested.disconnect(_on_test_sound)
	var miss_playing := false
	for v in Audio.voices(Audio.MISS):
		miss_playing = miss_playing or v.playing
	_check(int(Audio.requests.get(Audio.MISS, 0)) == asked + 1 and _sound_log.size() == 2 and not miss_playing,
			"звуки выключены: запрос Miss не посчитан (%d → %d), сигналов %d (ждали 2) или голос играет" % [asked,
			int(Audio.requests.get(Audio.MISS, 0)), _sound_log.size()])
	await get_tree().create_timer(Audio.MUSIC_DUCK_IN + 0.05).timeout
	_check(not Audio.is_music_ducked(), "звуки выключены, а удар победы приглушил музыку")
	# 6. Приглушение (15.3): кнопка — нет; удар победы — да; возврат — за MUSIC_RESTORE_TIME.
	GameState.sfx_on = true
	Audio.play(Audio.CLICK)
	await get_tree().create_timer(Audio.MUSIC_DUCK_IN + 0.05).timeout
	var after_click: bool = Audio.is_music_ducked()
	Audio.play(Audio.WIN, 0.0)
	await get_tree().create_timer(Audio.MUSIC_DUCK_IN + 0.05).timeout
	var after_win: bool = Audio.is_music_ducked()
	Audio.duck_music(0.0)  # не ждать DUCK[WIN] целиком: сразу возврат
	await get_tree().create_timer(Audio.MUSIC_DUCK_IN + Audio.MUSIC_RESTORE_TIME + 0.25).timeout
	var restored: bool = not Audio.is_music_ducked()
	_check(not after_click and after_win and restored, "приглушение музыки: после кнопки %s (ждали нет), после удара "
			% ("да" if after_click else "нет") + "победы %s (ждали да), вернулась: %s" % ["да" if after_win else "нет",
			restored])
	for sound in [Audio.CLICK, Audio.WIN]:
		for v in Audio.voices(sound):
			v.stop()
	# 7. Вибрация (15.4; вернули 07.10): свой рисунок у постановки, линии, промаха, тупика, победы и звезды;
	# у остальных звуков нет. Рисунок [вкл, пауза, …, вкл] — короткий. Звук выключен — вибрация есть;
	# вибрация выключена — нет. Проба в настройках (Audio.vibrate) — один импульс.
	var bad_pat: Array[String] = []
	var seen_pat: Array = []
	for sound: StringName in Audio.HAPTICS:
		var pat: Array = Audio.HAPTICS[sound]
		var total := 0
		var ok := Audio.SOUNDS.has(sound) and pat.size() % 2 == 1 and not seen_pat.has(pat)
		for ms in pat:
			ok = ok and typeof(ms) == TYPE_INT and int(ms) >= 10 and int(ms) <= 150
			total += int(ms)
		seen_pat.append(pat)
		if not ok or total > 400:
			bad_pat.append("%s %s" % [sound, str(pat)])
	_check(bad_pat.is_empty(), "рисунки вибрации: нечётное число чисел (последнее — импульс), 10–150 мс, всего не больше "
			+ "400 мс, у каждого события свой — не так у: " + ", ".join(bad_pat))
	var buzz: Array[StringName] = [Audio.PLACE, Audio.LINE, Audio.MISS, Audio.ERROR, Audio.WIN, Audio.STAR]
	var was_vib := GameState.vibration_on
	GameState.sfx_on = false
	GameState.vibration_on = true
	Audio.vibration_requested.connect(_on_test_vibration)
	var bad_vib: Array[String] = []
	for sound in Audio.SOUNDS:
		_vib_log.clear()
		Audio.play(sound, 0.0)
		var want: Array = [Audio.HAPTICS[sound]] if buzz.has(sound) else []
		if _vib_log != want or buzz.has(sound) != Audio.HAPTICS.has(sound):
			bad_vib.append("%s: %s (ждали %s)" % [sound, str(_vib_log), str(want)])
	_check(bad_vib.is_empty(), "вибрация при выключенном звуке: " + "; ".join(bad_vib))
	_vib_log.clear()
	Audio.vibrate(40)
	var probe := _vib_log.duplicate()
	GameState.vibration_on = false
	_vib_log.clear()
	Audio.play(Audio.PLACE, 0.0)
	Audio.play(Audio.WIN, 0.0)
	Audio.vibrate(40)
	_check(probe == [[40]] and _vib_log.is_empty(), "проба вибрации %s (ждали [[40]]); при выключенной вибрации — %s"
			% [str(probe), str(_vib_log)])
	Audio.vibration_requested.disconnect(_on_test_vibration)
	GameState.vibration_on = was_vib
	GameState.sfx_on = was_sfx
	AudioServer.set_bus_mute(sfx_bus, was_mute)
	var all_voices := 0
	for sound in Audio.SOUNDS:
		all_voices += Audio.voices(sound).size()
	print("  звуков %d, голосов %d; нота постановки — пентатоника по площади и серии, линия и звёзды — до мажор; "
			% [Audio.SOUNDS.size(), all_voices] + "голоса, выключенные звуки, приглушение музыки, рисунки вибрации "
			+ "(%d) проверены" % Audio.HAPTICS.size())


## Audio.requested во время проверок звука: [звук, высота, кадр, музыка приглушена].
func _on_test_sound(sound: StringName, pitch: float) -> void:
	_sound_log.append([sound, pitch, Engine.get_process_frames(), Audio.is_music_ducked()])


## Audio.vibration_requested во время проверок вибрации.
func _on_test_vibration(pattern: Array) -> void:
	_vib_log.append(pattern)


## Звуки уровня сценария 14.8b (_sound_log с его начала до «Далее»): каждый удар блока — ровно одно из «нота» (не
## последний, без линии), «линия» (по силе хода), «победа» (последний); тупик — Error один раз, промахов нет; подсказка
## и отмена — по разу; победа → звёзды (по заработанным, до-ми-соль) → джингл, по разу; под звёздами и джинглом музыка
## приглушена, если звуки включены.
func _check_level_sounds(tag: String, stars: int) -> void:
	var cfg := Juice.shared_config()
	var count := {}
	var first := {}
	var last := {}
	var bad: Array[String] = []
	var star_pitches: Array[float] = []
	var line_pitches: Array[float] = []
	for power in cfg.combo_semitones.size():
		line_pitches.append(cfg.combo_pitch(power))
	for i in _sound_log.size():
		var e: Array = _sound_log[i]
		var sound: StringName = e[0]
		var pitch := float(e[1])
		count[sound] = int(count.get(sound, 0)) + 1
		if not first.has(sound):
			first[sound] = i
		last[sound] = i
		if sound == Audio.NOTE and not PENTATONIC.has(posmod(_semitones(pitch), 12)):
			bad.append("нота ×%.3f не в пентатонике" % pitch)
		if sound == Audio.LINE:
			var by_power := false
			for p in line_pitches:
				by_power = by_power or is_equal_approx(p, pitch)
			if not by_power:
				bad.append("линия ×%.3f не по силе хода" % pitch)
		if sound == Audio.STAR:
			star_pitches.append(pitch)
			if GameState.sfx_on and not bool(e[3]):
				bad.append("под звездой %d музыка не приглушена" % star_pitches.size())
		if sound == Audio.JINGLE and GameState.sfx_on and not bool(e[3]):
			bad.append("под джинглом музыка не приглушена")
	var places := int(count.get(Audio.PLACE, 0))
	var notes := int(count.get(Audio.NOTE, 0))
	var lines := int(count.get(Audio.LINE, 0))
	var wins := int(count.get(Audio.WIN, 0))
	if notes + lines + wins != places or places == 0:
		bad.append("ударов %d, а нот %d + линий %d + побед %d (у каждого удара — ровно одно)" % [places, notes, lines,
				wins])
	var expect := {Audio.ERROR: 1, Audio.MISS: 0, Audio.HINT: 1, Audio.UNDO: 1, Audio.WIN: 1, Audio.JINGLE: 1,
			Audio.STAR: stars}
	for sound: StringName in expect:
		if int(count.get(sound, 0)) != int(expect[sound]):
			bad.append("%s — %d раз (ждали %d)" % [sound, int(count.get(sound, 0)), int(expect[sound])])
	for i in mini(star_pitches.size(), stars):
		if not is_equal_approx(star_pitches[i], cfg.star_pitch(i)):
			bad.append("звезда %d ×%.3f (ждали ×%.3f)" % [i + 1, star_pitches[i], cfg.star_pitch(i)])
	if first.has(Audio.WIN) and first.has(Audio.STAR) and first.has(Audio.JINGLE) \
			and not (int(last[Audio.WIN]) < int(first[Audio.STAR]) and int(last[Audio.STAR]) < int(first[Audio.JINGLE])):
		bad.append("порядок не «победа → звёзды → джингл»")
	_check(bad.is_empty(), "%s, звук: %s" % [tag, "; ".join(bad.slice(0, 6))])


func _test_settings() -> void:
	_section("Настройки")
	var music_idx := AudioServer.get_bus_index(GameState.BUS_MUSIC)
	var sfx_idx := AudioServer.get_bus_index(GameState.BUS_SFX)
	if not _check(music_idx >= 0 and sfx_idx >= 0, "нет шин Music/SFX (индексы %d, %d)" % [music_idx, sfx_idx]):
		return
	var audio := get_node_or_null("/root/Audio")
	if audio != null:
		for child in audio.get_children():
			if child is AudioStreamPlayer:
				var want: StringName = GameState.BUS_MUSIC if child.name == &"Music" else GameState.BUS_SFX
				var bus: StringName = (child as AudioStreamPlayer).bus
				_check(bus == want, "звук %s идёт в шину %s (ждали %s)" % [child.name, bus, want])

	var was_music := GameState.music_on
	var was_sfx := GameState.sfx_on
	var was_vibration := GameState.vibration_on

	GameState.set_music(false)
	GameState.set_sfx(true)
	_check(AudioServer.is_bus_mute(music_idx) and not AudioServer.is_bus_mute(sfx_idx),
			"музыка выключена: шина Music должна молчать, SFX — нет")
	GameState.set_music(true)
	GameState.set_sfx(false)
	GameState.set_vibration(false)
	_check(not AudioServer.is_bus_mute(music_idx) and AudioServer.is_bus_mute(sfx_idx),
			"звуки выключены: шина SFX должна молчать, Music — нет")

	# Настройки лежат в settings.cfg и читаются обратно; в прогресс (облако) не попадают.
	var cfg := ConfigFile.new()
	if _check(cfg.load(GameState.SETTINGS_PATH) == OK, "settings.cfg не записан"):
		var ok: bool = bool(cfg.get_value("settings", "music_on", false)) \
				and not bool(cfg.get_value("settings", "sfx_on", true)) \
				and not bool(cfg.get_value("settings", "vibration_on", true))
		_check(ok, "в settings.cfg не те значения")
	GameState.music_on = false
	GameState.sfx_on = true
	GameState.vibration_on = true
	GameState.load_settings()
	_check(GameState.music_on and not GameState.sfx_on and not GameState.vibration_on,
			"load_settings() не вернул настройки из settings.cfg")
	var save_keys := GameState.get_save_data()
	_check(not save_keys.has("sound_on") and not save_keys.has("music_on") and not save_keys.has("sfx_on"),
			"настройки звука попали в сохранение прогресса (облако)")

	# Временное приглушение (реклама, скрытая вкладка) глушит всё, не трогая настройки.
	var had_reasons := GameState.is_audio_suspended()
	GameState.set_audio_suspended(&"selftest", true)
	_check(GameState.is_audio_suspended() and AudioServer.is_bus_mute(0), "приглушение не выключило шину Master")
	GameState.set_audio_suspended(&"selftest", false)
	_check(GameState.is_audio_suspended() == had_reasons and AudioServer.is_bus_mute(0) == had_reasons,
			"после снятия приглушения звук не вернулся")

	# Перенос: сохранение v3 со звуком выкл., settings.cfg ещё нет -> музыка и звуки выкл.
	var old := ConfigFile.new()
	var v3 := {"version": 3, "level": 4, "total_score": 0, "legacy_score": 0, "sound_on": false,
			"level_stars": {}, "level_best": {}}
	for key in v3:
		old.set_value("progress", key, v3[key])
	if _check(old.save(GameState.SAVE_PATH) == OK, "не удалось записать тестовое сохранение v3"):
		DirAccess.remove_absolute(GameState.SETTINGS_PATH)
		GameState._legacy_sound_on = true
		GameState.load_game()
		GameState.load_settings()
		_check(not GameState.music_on and not GameState.sfx_on and GameState.vibration_on,
				"перенос из v3: музыка %s, звуки %s, вибрация %s (ждали выкл./выкл./вкл.)" % [
					GameState.music_on, GameState.sfx_on, GameState.vibration_on])
		_check(GameState.level == 4 and GameState.epoch == 0, "перенос из v3: уровень %d, поколение %d" % [GameState.level, GameState.epoch])
		_check(FileAccess.file_exists(GameState.SETTINGS_PATH), "перенос из v3 не записал settings.cfg")
		GameState.save_game()
		var v4 := ConfigFile.new()
		if _check(v4.load(GameState.SAVE_PATH) == OK, "сохранение не перечитывается"):
			_check(int(v4.get_value("progress", "version", 0)) == GameState.SAVE_VERSION and not v4.has_section_key("progress", "sound_on"),
					"после переноса сохранение не v%d или в нём остался sound_on" % GameState.SAVE_VERSION)

	GameState.set_music(was_music)
	GameState.set_sfx(was_sfx)
	GameState.set_vibration(was_vibration)
	GameState.reset_progress()
	print("  шины, settings.cfg, приглушение и перенос из v3 проверены")


## Окно настроек (меню) и паузы (игра): переключатели, сброс с подтверждением, Esc.
func _test_settings_panel() -> void:
	_section("Окно настроек и паузы")
	var ps := load(SETTINGS_PANEL_SCENE) as PackedScene
	if not _check(ps != null, "окно настроек не загружается"):
		return
	var panel := ps.instantiate() as SettingsPanel
	if not _check(panel != null, "корень settings_panel.tscn — не SettingsPanel"):
		return
	add_child(panel)
	await _frames(2)
	var got := {"closed": 0, "home": 0, "wiped": 0}
	panel.closed.connect(_count.bind(got, "closed"))
	panel.home_pressed.connect(_count.bind(got, "home"))
	panel.progress_wiped.connect(_count.bind(got, "wiped"))

	var was_music := GameState.music_on
	var was_sfx := GameState.sfx_on
	var was_vibration := GameState.vibration_on
	panel.open(SettingsPanel.Mode.SETTINGS)
	_check(panel.visible and panel.reset_button.visible and not panel.home_button.visible and panel.title_label.text == tr("НАСТРОЙКИ"),
			"настройки: окно не открылось или не те кнопки (сброс: %s, «В меню»: %s)" % [panel.reset_button.visible, panel.home_button.visible])
	await _frames(2)
	_check_settings_look(panel, "настройки")
	# Язык сменился при открытом окне (YSDK уточняет язык уже после старта) — подписи таблеток на новом
	# языке: PillButton пересчитывает подпись на NOTIFICATION_TRANSLATION_CHANGED, «ГОТОВО» ставит SettingsPanel (13.5e).
	var loc0 := TranslationServer.get_locale()
	var pills := [[panel.close_button, "ГОТОВО"], [panel.reset_button, "Сбросить прогресс"],
			[panel.confirm_reset_button, "СБРОСИТЬ"], [panel.cancel_reset_button, "ОТМЕНА"],
			[panel.rate_button, "ОЦЕНИТЬ ИГРУ"], [panel.motion_button, "Меньше движения: вкл" if GameState.reduce_motion else "Меньше движения: выкл"]]
	for lang: String in ["en", "tr", "ru"]:
		TranslationServer.set_locale(lang)
		await _frames(2)
		for pair: Array in pills:
			var pb: PillButton = pair[0]
			_check(pb.caption.text == tr(pair[1]), "настройки, язык %s: на таблетке «%s» (ждали «%s»)" % [lang, pb.caption.text,
					tr(pair[1])])
	TranslationServer.set_locale(loc0)
	await _frames(2)
	_check(panel.vibration_toggle.visible == GameState.can_vibrate(), "переключатель вибрации показан не там, где есть вибрация")
	# 12.10: таблетки разработчика («Меньше движения», «Сбросить прогресс») — только в отладочной сборке.
	# Сборка для игроков (dev_tools = false): в настройках их нет, в паузе нет «Меньше движения»; карточка — по содержимому.
	_check(SettingsPanel.dev_tools == OS.is_debug_build() and panel.motion_button.visible == SettingsPanel.dev_tools,
			"таблетки разработчика: dev_tools %s при отладочной сборке %s" % [SettingsPanel.dev_tools, OS.is_debug_build()])
	var dev0 := SettingsPanel.dev_tools
	SettingsPanel.dev_tools = false
	panel.open(SettingsPanel.Mode.SETTINGS)
	_check(not panel.motion_button.visible and not panel.reset_button.visible and panel.close_button.visible
			and not panel.home_button.visible, "сборка для игроков, настройки: видна таблетка разработчика (движение: %s, сброс: %s)"
			% [panel.motion_button.visible, panel.reset_button.visible])
	await _frames(2)
	_check_settings_look(panel, "настройки у игроков")
	panel.open(SettingsPanel.Mode.PAUSE)
	_check(not panel.motion_button.visible and not panel.reset_button.visible and panel.home_button.visible,
			"сборка для игроков, пауза: видна «Меньше движения» или нет «В меню»")
	await _frames(2)
	_check_settings_look(panel, "пауза у игроков")
	SettingsPanel.dev_tools = true
	panel.open(SettingsPanel.Mode.SETTINGS)
	_check(panel.motion_button.visible and panel.reset_button.visible, "отладочная сборка: нет «Меньше движения» или «Сбросить прогресс»")
	SettingsPanel.dev_tools = dev0
	await _test_rate_button(panel)
	panel.open(SettingsPanel.Mode.SETTINGS)
	await _frames(2)
	panel.music_button.pressed.emit()
	var music_icon: Texture2D = SettingsPanel.MUSIC_ON if GameState.music_on else SettingsPanel.MUSIC_OFF
	_check(GameState.music_on != was_music and panel.music_button.face.texture == music_icon, "кнопка музыки не переключила настройку или иконку")
	panel.music_button.pressed.emit()
	_check(panel.home_button.theme_type_variation == &"CardLink" and panel.home_button.icon != null
			and panel.home_button.icon.resource_path.ends_with("home.png"), "«В меню» не ссылка CardLink с иконкой home.png")
	panel.sfx_button.pressed.emit()
	var sfx_icon: Texture2D = SettingsPanel.SFX_ON if GameState.sfx_on else SettingsPanel.SFX_OFF
	_check(GameState.sfx_on != was_sfx and panel.sfx_button.face.texture == sfx_icon, "кнопка звуков не переключила настройку или иконку")
	panel.sfx_button.pressed.emit()
	panel.vibration_button.pressed.emit()
	_check(GameState.vibration_on != was_vibration, "кнопка вибрации не переключила настройку")
	panel.vibration_button.pressed.emit()
	# «Меньше движения» (этап 14): таблетка переключает настройку и свою надпись.
	var was_motion := GameState.reduce_motion
	panel.motion_button.pressed.emit()
	var motion_text := tr("Меньше движения: вкл") if GameState.reduce_motion else tr("Меньше движения: выкл")
	_check(GameState.reduce_motion != was_motion and panel.motion_button.text == motion_text,
			"«Меньше движения» не переключилось или надпись «%s»" % panel.motion_button.text)
	panel.motion_button.pressed.emit()
	_check(GameState.music_on == was_music and GameState.sfx_on == was_sfx and GameState.vibration_on == was_vibration
			and GameState.reduce_motion == was_motion, "повторные нажатия не вернули настройки")

	# Сброс: сначала подтверждение; «Отмена» и Esc возвращают назад без сброса.
	GameState.reset_progress()
	GameState.complete_level(1, 3, 300)
	var e0 := GameState.epoch
	panel.reset_button.pressed.emit()
	_check(panel.confirm_box.visible and not panel.main_box.visible, "«Сбросить прогресс» не спросил подтверждения")
	_check(panel.title_label.text == tr("СБРОСИТЬ ПРОГРЕСС?"), "подтверждение: в шапке «%s»" % panel.title_label.text)
	await _frames(2)
	_check_settings_look(panel, "подтверждение")
	panel.cancel_reset_button.pressed.emit()
	_check(panel.main_box.visible and not panel.confirm_box.visible and GameState.total_score == 300,
			"«Отмена» не вернула к настройкам или сбросила прогресс")
	panel.reset_button.pressed.emit()
	panel._unhandled_input(_esc())
	_check(panel.visible and panel.main_box.visible and int(got["closed"]) == 0, "Esc в подтверждении не вернул к настройкам")
	panel.reset_button.pressed.emit()
	panel.confirm_reset_button.pressed.emit()
	_check(GameState.total_score == 0 and GameState.level == 1 and GameState.epoch == e0 + 1,
			"сброс: счёт %d, уровень %d, поколение %d (ждали 0/1/%d)" % [GameState.total_score, GameState.level, GameState.epoch, e0 + 1])
	_check(int(got["wiped"]) == 1 and int(got["closed"]) == 1 and not panel.visible,
			"после сброса окно не закрылось или не сообщило о сбросе")

	# Пауза: «Продолжить» и «В меню», без сброса; Esc закрывает.
	panel.open(SettingsPanel.Mode.PAUSE)
	_check(panel.home_button.visible and not panel.reset_button.visible and panel.close_button.text == tr("ПРОДОЛЖИТЬ")
			and panel.title_label.text == tr("ПАУЗА"), "пауза: не те кнопки или заголовок")
	await _frames(2)
	_check_settings_look(panel, "пауза")
	await _frames(2)  # _check_settings_look перебирал языки: ширина «В меню» встаёт по русской подписи кадром позже
	_check_link(panel.home_button, "«В меню»")
	panel._unhandled_input(_esc())
	_check(not panel.visible and int(got["closed"]) == 2, "Esc не закрыл окно паузы")
	panel.open(SettingsPanel.Mode.PAUSE)
	panel.home_button.pressed.emit()
	_check(int(got["home"]) == 1 and int(got["closed"]) == 2 and not panel.visible,
			"«В меню» не сработала (или пришёл лишний сигнал closed)")
	panel.queue_free()
	await _frames(1)

	# Меню: шестерёнка открывает настройки, после сброса уровень и счёт обновляются сразу.
	GameState.complete_level(1, 3, 300)
	var menu_ps := load(MENU_SCENE) as PackedScene
	if _check(menu_ps != null, "меню не загружается"):
		var menu = menu_ps.instantiate()  # без типа: у меню нет class_name
		add_child(menu)
		await _frames(2)
		var level_before: String = menu.play_button.subtitle
		menu.settings_button.pressed.emit()
		var mp: SettingsPanel = menu.settings_panel
		_check(mp.visible and mp.mode == SettingsPanel.Mode.SETTINGS, "шестерёнка в меню не открыла настройки")
		mp.reset_button.pressed.emit()
		mp.confirm_reset_button.pressed.emit()
		var level_after: String = menu.play_button.subtitle
		_check(level_before != level_after and level_after == tr("УРОВЕНЬ %d") % 1 and menu.score_label.text == "0",
				"меню не обновилось после сброса: «%s» -> «%s», счёт %s" % [level_before, level_after, menu.score_label.text])
		menu.queue_free()
		await _frames(1)
	GameState.reset_progress()
	print("  переключатели, сброс с подтверждением, Esc, «В меню» и шестерёнка в меню работают; вид карточки (13.5c)")


## «Оценить игру» (12.10b): золотая таблетка со звёздами — только в настройках (не в паузе), после обучения и пока
## YSDK.can_offer_review(); нажатие запрашивает оценку (гостю — окно входа) и прячет кнопку; окно следит за
## review_availability_changed. Вне Яндекс Игр — заглушка YSDK.review_stub (подменяем и возвращаем).
func _test_rate_button(panel: SettingsPanel) -> void:
	_check(SettingsPanel.rate_shown(SettingsPanel.Mode.SETTINGS, true, true)
			and not SettingsPanel.rate_shown(SettingsPanel.Mode.PAUSE, true, true)
			and not SettingsPanel.rate_shown(SettingsPanel.Mode.SETTINGS, false, true)
			and not SettingsPanel.rate_shown(SettingsPanel.Mode.SETTINGS, true, false), "«Оценить игру»: правило показа")
	var saved := [YSDK.review_stub, YSDK._review_requested_this_session, YSDK.is_available, YSDK.sdk_pending,
			SettingsPanel.dev_tools]
	YSDK.is_available = false
	YSDK.sdk_pending = false
	YSDK.review_stub = true
	YSDK._review_requested_this_session = false
	GameState.reset_progress()
	GameState.level = Tutorial.LEVELS
	panel.open(SettingsPanel.Mode.SETTINGS)
	_check(not panel.rate_box.visible and not GameState.tutorial_done(), "«Оценить игру» видна до конца обучения")
	GameState.level = Tutorial.LEVELS + 1
	panel.open(SettingsPanel.Mode.SETTINGS)
	_check(panel.rate_box.visible and panel.rate_button.tone == PillButton.Tone.GOLD and panel.rate_button.text == "ОЦЕНИТЬ ИГРУ",
			"после обучения нет золотой «Оценить игру» (видна %s, тон %d)" % [panel.rate_box.visible, panel.rate_button.tone])
	await _frames(2)
	_check_settings_look(panel, "настройки с «Оценить игру»")
	SettingsPanel.dev_tools = false
	panel.open(SettingsPanel.Mode.SETTINGS)
	await _frames(2)
	_check_settings_look(panel, "настройки у игроков с «Оценить игру»")
	# Звёзды — над верхним краем таблетки, в карточке и не перехватывают касания.
	var box := panel.rate_box.get_global_rect()
	var btn := panel.rate_button.get_global_rect()
	var card := panel.card.get_global_rect()
	var stars := panel.rate_box.get_node(^"RateStars").get_children()
	_check(stars.size() == 5 and absf(btn.end.y - box.end.y) < 1.0 and btn.position.y > box.position.y + 20.0,
			"«Оценить игру»: звёзд %d, кнопка %s в %s" % [stars.size(), str(btn), str(box)])
	for node: Node in stars:
		var st := node as TextureRect
		if not _check(st != null, "в RateStars не TextureRect: %s" % node.name):
			continue
		var r := st.get_global_rect()
		_check(st.mouse_filter == Control.MOUSE_FILTER_IGNORE and card.encloses(r) and r.position.y < btn.position.y
				and r.end.y > btn.position.y, "звезда %s: %s (кнопка %s), касания %d" % [st.name, str(r), str(btn), st.mouse_filter])
	panel.open(SettingsPanel.Mode.PAUSE)
	_check(not panel.rate_box.visible, "«Оценить игру» в паузе")
	panel.open(SettingsPanel.Mode.SETTINGS)
	panel.rate_button.pressed.emit()
	_check(panel.visible and not panel.rate_box.visible and YSDK._review_requested_this_session,
			"нажатие «Оценить игру»: окно %s, кнопка %s, запрос %s" % [panel.visible, panel.rate_box.visible,
			YSDK._review_requested_this_session])
	YSDK._review_requested_this_session = false
	YSDK.review_availability_changed.emit()
	_check(panel.rate_box.visible, "окно настроек не следит за review_availability_changed")
	YSDK.review_stub = false
	YSDK.review_availability_changed.emit()
	_check(not panel.rate_box.visible, "сборка для игроков вне Яндекс Игр: «Оценить игру» видна")
	# Гость в Яндекс Играх (мост — FakeBridge): кнопка видна; нажатие — окно входа, кнопка прячется; отказался от
	# входа — кнопка вернулась.
	var saved_ya := [YSDK._bridge, YSDK.auth_known, YSDK.is_authorized, YSDK._review_after_auth, YSDK._auth_requested,
			GameState.review_prompted]
	var fake := FakeBridge.new()
	YSDK._bridge = fake
	YSDK.is_available = true
	YSDK.auth_known = true
	YSDK.is_authorized = false
	YSDK._review_after_auth = false
	YSDK._review_requested_this_session = false
	GameState.review_prompted = false
	panel.open(SettingsPanel.Mode.SETTINGS)
	_check(panel.rate_box.visible, "гостю в Яндекс Играх «Оценить игру» не видна")
	panel.rate_button.pressed.emit()
	_check(panel.visible and not panel.rate_box.visible and fake.other == ["openAuth"],
			"гость нажал «Оценить игру»: окно %s, кнопка %s, вызовы %s" % [panel.visible, panel.rate_box.visible,
			str(fake.other)])
	YSDK._handle_event("auth", {"authorized": false, "id": "", "cancelled": true})
	_check(panel.rate_box.visible and fake.other == ["openAuth"], "гость отказался от входа: кнопка %s, вызовы %s"
			% [panel.rate_box.visible, str(fake.other)])
	YSDK._bridge = saved_ya[0]
	YSDK.auth_known = saved_ya[1]
	YSDK.is_authorized = saved_ya[2]
	YSDK._review_after_auth = saved_ya[3]
	YSDK._auth_requested = saved_ya[4]
	GameState.review_prompted = saved_ya[5]
	YSDK.review_stub = saved[0]
	YSDK._review_requested_this_session = saved[1]
	YSDK.is_available = saved[2]
	YSDK.sdk_pending = saved[3]
	SettingsPanel.dev_tools = saved[4]
	GameState.reset_progress()
	print("  «Оценить игру»: после обучения, только в настройках, прячется после нажатия; гостю — вход, отказ — "
			+ "кнопка вернулась (12.10b)")


## Вид окна настроек / паузы (13.5c): карточка CandyCard с фиолетовой шапкой шириной CARD_W, высота —
## по содержимому, целиком на экране; заголовок в шапке; кнопки — таблетки нужных тонов; заголовки
## влезают в шапку на ru / en / tr.
## Ссылка CardLink (13.5e): иконка своим размером (без expand_icon — иначе её нет в минимальном размере и
## в узкой кнопке она не рисуется), кнопка шириной по содержимому — иконка icon_max_width вплотную к тексту.
## Меню 13.6 (STYLE 11.1; логотип 07.10): логотип — только графика (надписей «ШИКАКУ», «БЛОКИ» и подвала нет),
## решённое мини-поле 4×3 из блоков 3, 2, 4, 3, симметричное, по центру колонны; двойка парит над местом и садится
## по касанию, при «Меньше движения» стоит над местом; «ИГРАТЬ» со второй строкой «УРОВЕНЬ N», верхний ряд у
## краёв экрана в портрете, альбоме и на высоком экране, колонна по центру, подписи влезают на ru / en / tr.
func _test_menu() -> void:
	_section("Меню")
	GameState.complete_level(1, 3, 300)
	var menu_ps := load(MENU_SCENE) as PackedScene
	if not _check(menu_ps != null, "меню не загружается"):
		return
	var menu = menu_ps.instantiate()  # без типа: у меню нет class_name
	add_child(menu)
	await _frames(2)
	# Логотип: блоки на своих местах закрывают поле 4×3 ровно по одному разу, площади по клеткам зеркальны.
	var logo: MenuLogo = menu.logo
	var grid := {}
	var cell_area := {}
	var areas: Array[int] = []
	for b in logo.blocks():
		areas.append(b.area)
		var at := Vector2i((logo.home(b) / Block.CELL).round())
		for y in b.cells.y:
			for x in b.cells.x:
				_count(grid, str(at + Vector2i(x, y)))
				cell_area[at + Vector2i(x, y)] = b.area
	areas.sort()
	var tiled := grid.size() == MenuLogo.GRID.x * MenuLogo.GRID.y
	for y in MenuLogo.GRID.y:
		for x in MenuLogo.GRID.x:
			tiled = tiled and int(grid.get(str(Vector2i(x, y)), 0)) == 1 \
					and int(cell_area.get(Vector2i(x, y), 0)) == int(cell_area.get(Vector2i(MenuLogo.GRID.x - 1 - x, y), -1))
	_check(areas == [2, 3, 3, 4] and tiled, "логотип: блоки %s не складываются в симметричное поле 4×3 (%s)" % [str(areas), str(grid)])
	_check(logo.size == Vector2(MenuLogo.GRID) * MenuLogo.CELL
			and absf(logo.position.x + logo.size.x * 0.5 - menu.content.size.x * 0.5) < 0.5
			and is_equal_approx(logo.blocks_root.scale.x, MenuLogo.CELL / Block.CELL),
			"логотип %s не по центру колонны или не того размера" % str(Rect2(logo.position, logo.size)))
	# Только графика: никаких надписей, кроме счёта (цифры блоков, «ИГРАТЬ» и окно настроек — не в счёт).
	var texts: Array[String] = []
	for n in menu.find_children("*", "Label", true, false):
		var l := n as Label
		if l != menu.score_label and not (menu.play_button as Node).is_ancestor_of(l) \
				and not (menu.daily_button as Node).is_ancestor_of(l) \
				and not (menu.levels_button as Node).is_ancestor_of(l) \
				and not (menu.lab_button != null and (menu.lab_button as Node).is_ancestor_of(l)) \
				and not (menu.settings_panel as Node).is_ancestor_of(l) and not (logo as Node).is_ancestor_of(l):
			texts.append("%s «%s»" % [l.name, l.text])
	_check(texts.is_empty(), "меню: лишние надписи %s" % str(texts))
	# 19.3: «ЛАБОРАТОРИЯ» — только в отладочной сборке, у игроков её нет.
	var lab_b: PillButton = menu.lab_button
	_check((lab_b != null) == OS.is_debug_build() and (lab_b == null or (lab_b.text == LabLevels.NAME
			and lab_b.get_parent() == menu.content)), "меню: кнопка «Лаборатории» %s в %s сборке" % [
			"есть" if lab_b != null else "нет", "отладочной" if OS.is_debug_build() else "выпускной"])
	# Двойка парит над своим местом «в руке»; касание — садится на место, через HOLD_TIME снова поднимается.
	var hero: Block = logo.hero
	_check(not GameState.reduce_motion and is_equal_approx(logo.hover, 1.0) and hero.lifted
			and hero.position.y < logo.home(hero).y - MenuLogo.HOVER_UP * 0.5
			and is_equal_approx(hero.scale.x, Block.LIFT_SCALE),
			"логотип: двойка не парит (hover %.2f, место %s, сейчас %s)" % [logo.hover, str(logo.home(hero)), str(hero.position)])
	logo.tap()
	await get_tree().create_timer(MenuLogo.DROP_TIME + 0.1).timeout
	_check(logo.landed and not hero.lifted and hero.position.distance_to(logo.home(hero)) < 0.5
			and is_equal_approx(hero.scale.x, 1.0) and is_zero_approx(hero.tilt),
			"логотип: после касания двойка не на месте (%s, место %s, hover %.2f)" % [str(hero.position),
			str(logo.home(hero)), logo.hover])
	await get_tree().create_timer(MenuLogo.HOLD_TIME + MenuLogo.LIFT_TIME + 0.1).timeout
	_check(not logo.landed and hero.lifted and logo.hover > 0.9, "логотип: двойка не поднялась снова (hover %.2f)" % logo.hover)
	# «Меньше движения»: двойка стоит над местом без парения, касание её не сажает.
	GameState.reduce_motion = true
	await _frames(2)
	var still_at := hero.position
	logo.tap()
	await get_tree().create_timer(MenuLogo.DROP_TIME + 0.1).timeout
	_check(not logo.landed and is_equal_approx(logo.hover, 1.0) and hero.position.distance_to(still_at) < 0.01
			and is_equal_approx(hero.position.y, logo.home(hero).y - MenuLogo.HOVER_UP),
			"логотип «меньше движения»: двойка двигается (%s → %s)" % [str(still_at), str(hero.position)])
	GameState.reduce_motion = false
	await _frames(1)
	# «ИГРАТЬ»: две строки, вторая — уровень; центры строк на TWO_LINE_Y высоты лица.
	var pb: PillButton = menu.play_button
	var fh := pb.size.y * (1.0 - PillButton.DEPTH_K)
	var c1: float = pb.caption.position.y + pb.caption.size.y * 0.5
	var c2: float = pb.sub_caption.position.y + pb.sub_caption.size.y * 0.5
	_check(pb.subtitle == tr("УРОВЕНЬ %d") % GameState.level and pb.sub_caption.visible
			and pb.sub_caption.text == pb.subtitle and pb.caption.text == tr("ИГРАТЬ"),
			"«ИГРАТЬ»: подписи «%s» / «%s» (уровень %d)" % [pb.caption.text, pb.sub_caption.text, GameState.level])
	var db: PillButton = menu.daily_button
	var lb: PillButton = menu.levels_button
	_check(db.caption.text == tr("ЗАДАЧА ДНЯ") and db.subtitle == tr("СЕРИЯ %d") % GameState.daily_current_streak()
			and db.sub_caption.visible and db.sub_caption.text == db.subtitle,
			"«ЗАДАЧА ДНЯ»: подписи «%s» / «%s»" % [db.caption.text, db.sub_caption.text])
	_check(lb.caption.text == tr("УРОВНИ") and lb.subtitle.is_empty() and not lb.sub_caption.visible
			and db.tone == PillButton.Tone.LIGHT and lb.tone == PillButton.Tone.LIGHT and pb.tone == PillButton.Tone.GREEN,
			"«УРОВНИ»: «%s», тоны ИГРАТЬ / ЗАДАЧА ДНЯ / УРОВНИ — %d / %d / %d" % [lb.caption.text, pb.tone, db.tone, lb.tone])
	# 18.1f: вторая строка «ЗАДАЧИ ДНЯ» — живая серия: вчера пройдена — серия идёт, сегодня — «· ГОТОВО»,
	# пропущен день — 0 (в сохранении серия остаётся до следующей победы).
	var saved_daily := [GameState.daily_last_date, GameState.daily_streak]
	var today := DailyChallenge.current_date_key()
	var base_t := Time.get_unix_time_from_datetime_string(today)
	var ago := func(k: int) -> String:
		return Time.get_date_string_from_unix_time(base_t - k * 86400)
	GameState.daily_streak = 3
	var subs: Array[String] = []
	for k in [1, 0, 2]:
		GameState.daily_last_date = ago.call(k)
		subs.append(menu.daily_subtitle())
	_check(subs == [tr("СЕРИЯ %d") % 3, tr("СЕРИЯ %d · ГОТОВО") % 3, tr("СЕРИЯ %d") % 0]
			and GameState.daily_current_streak(ago.call(-1)) == 0 and GameState.daily_streak == 3,
			"«ЗАДАЧА ДНЯ»: серия вчера / сегодня / позавчера — %s" % str(subs))
	GameState.daily_last_date = saved_daily[0]
	GameState.daily_streak = saved_daily[1]
	menu._refresh()
	_check(absf(c1 - PillButton.TWO_LINE_Y.x * fh) < 1.0 and absf(c2 - PillButton.TWO_LINE_Y.y * fh) < 1.0,
			"«ИГРАТЬ»: центры строк %.0f и %.0f, нужны %.0f и %.0f" % [c1, c2, PillButton.TWO_LINE_Y.x * fh,
			PillButton.TWO_LINE_Y.y * fh])
	_check(menu.score_label.text == HudHeader.format_score(GameState.total_score),
			"меню: счёт «%s», нужен %d" % [menu.score_label.text, GameState.total_score])
	# Раскладки: портрет, высокий портрет, альбом 16:9.
	for sz: Vector2 in [Vector2(720, 1280), Vector2(720, 1600), Vector2(2276, 1280)]:
		menu.size = sz
		await _frames(2)
		var tag := "меню %dx%d" % [int(sz.x), int(sz.y)]
		var gear: Control = menu.settings_button
		var gc: Vector2 = gear.position + gear.size * 0.5
		_check(gc.distance_to(Vector2(sz.x - 72.0, 84.0)) < 1.0, "%s: шестерёнка в %s, нужна (%.0f, 84)" % [tag, str(gc), sz.x - 72.0])
		var lr := logo.get_global_rect()
		_check(absf(lr.get_center().x - sz.x * 0.5) < 1.0, "%s: логотип %s не по центру экрана" % [tag, str(lr)])
		var cc: Vector2 = menu.content.position + menu.content.size * 0.5
		_check(cc.distance_to(sz * 0.5) < 1.0 and menu.content.size == Vector2(720, 1280),
				"%s: колонна %s не по центру" % [tag, str(Rect2(menu.content.position, menu.content.size))])
		# 18.2b: логотип, «ИГРАТЬ», «ЗАДАЧА ДНЯ», «УРОВНИ» — сверху вниз, без наложений, по центру колонны.
		var col: Array[Control] = [logo, pb, db, lb]
		var col_ok := true
		for i in col.size():
			var r := Rect2(col[i].position, col[i].size)
			col_ok = col_ok and absf(r.get_center().x - 360.0) < 0.5 and r.end.y <= 1280.0 - 100.0
			if i > 0:
				col_ok = col_ok and r.position.y >= col[i - 1].position.y + col[i - 1].size.y + 16.0
		_check(col_ok, "%s: колонна меню наложилась или ушла с центра: %s" % [tag,
				str(col.map(func(c: Control) -> Rect2: return Rect2(c.position, c.size)))])
		var ss: int = MenuScript.SCORE_SIZE
		var row_l: float = menu.star.position.x - HudHeader.STAR_X * ss
		var row_r: float = menu.score_label.position.x + menu.score_label.size.x
		var row_y: float = menu.score_row.position.y + menu.score_label.position.y + menu.score_label.size.y * 0.5
		_check(absf((row_l + row_r) * 0.5 - sz.x * 0.5) < 2.0 and absf(row_y - 84.0) < 1.0,
				"%s: счёт %.0f…%.0f на высоте %.0f — не по центру верхнего ряда" % [tag, row_l, row_r, row_y])
	menu.size = Vector2(720, 1280)
	# Языки: обе строки «ИГРАТЬ» влезают в кнопку; смена языка — сразу.
	var saved := TranslationServer.get_locale()
	var font: Font = pb.get_theme_font(&"font")
	for loc in ["ru", "en", "tr"]:
		TranslationServer.set_locale(loc)
		await _frames(1)
		_check(pb.sub_caption.text == tr("УРОВЕНЬ %d") % GameState.level and pb.caption.text == tr("ИГРАТЬ"),
				"%s: «ИГРАТЬ» не переведена: «%s» / «%s»" % [loc, pb.caption.text, pb.sub_caption.text])
		_check(db.caption.text == tr("ЗАДАЧА ДНЯ") and lb.caption.text == tr("УРОВНИ"),
				"%s: «ЗАДАЧА ДНЯ» / «УРОВНИ» не переведены: «%s» / «%s»" % [loc, db.caption.text, lb.caption.text])
		# 18.2b: светлые «ЗАДАЧА ДНЯ» (с самой длинной серией) и «УРОВНИ» — тоже без ужатия.
		for item: Array in [[pb, pb.caption.text, pb.subtitle], [db, db.caption.text, tr("СЕРИЯ %d · ГОТОВО") % 365],
				[lb, lb.caption.text, ""]]:
			var btn: PillButton = item[0]
			var light := btn.tone == PillButton.Tone.LIGHT
			var bfs := btn.get_theme_font_size(&"font_size")
			var room := btn.size.x - 2.0 * PillButton.FIT_PAD_K * btn.size.y
			var lines: Array = [[item[1], bfs]]
			if not (item[2] as String).is_empty():
				lines.append([item[2], PillButton.sub_size(bfs)])
			for line: Array in lines:
				var lfs := PillButton.caption_size(font, line[0], line[1], light, btn.size)
				var lw := font.get_string_size(line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x + PillButton.outline_for(lfs, light)
				_check(lfs == int(line[1]) and lw <= room, "%s: «%s» %.0f px при размере %d (место %.0f)" % [loc, line[0], lw, lfs, room])
	TranslationServer.set_locale(saved)
	await _frames(1)
	menu.queue_free()
	await _frames(1)
	GameState.reset_progress()
	print("  логотип 4×3 без надписей по центру, двойка парит и садится по касанию, «ИГРАТЬ» с уровнем, «ЗАДАЧА ДНЯ» с живой серией, «УРОВНИ», верхний ряд и колонна в портрете, высоком портрете и альбоме, ru / en / tr")


## Карта уровней 18.2 (STYLE 11.2): кружки на волне снизу вверх и находятся касанием, пройденные / текущий /
## закрытые, при входе текущий на FOCUS_AT высоты окна, рисуются только видимые, касание закрытого — дрожь без
## перехода, мышь — щелчок и перетаскивание, курсор, «Меньше движения» — без пульса и дрожи, альбом — дорога по
## центру экрана и верхний ряд у краёв, новый игрок — уровень 1 на экране.
func _test_level_map() -> void:
	_section("Карта уровней (18.2)")
	GameState.reset_progress()
	for i in range(1, 12):
		GameState.complete_level(i, 1 + i % 3, 100)
	var ps := load(MAP_SCENE) as PackedScene
	if not _check(ps != null and GameState.level == 12, "карта уровней не загружается (уровень %d)" % GameState.level):
		GameState.reset_progress()
		return
	var map := ps.instantiate() as LevelMap
	add_child(map)
	map.size = Vector2(720, 1280)
	await _frames(3)
	var path: MapPath = map.path
	_check(path.current == 12 and path.count == 12 + MapPath.AHEAD
			and is_equal_approx(path.size.y, MapPath.total_height(path.count)),
			"карта: текущий %d, кружков %d, высота %.0f" % [path.current, path.count, path.size.y])
	_check(map.score_label.text == HudHeader.format_score(GameState.total_score),
			"карта: счёт «%s», нужен %d" % [map.score_label.text, GameState.total_score])
	var wave_ok := true
	for n in range(1, path.count + 1):
		var at := path.node_pos(n)
		wave_ok = wave_ok and path.level_at(at) == n and absf(at.x - path.size.x * 0.5) <= MapPath.AMP + 0.5
		if n > 1:
			wave_ok = wave_ok and is_equal_approx(path.node_pos(n - 1).y - at.y, MapPath.STEP)
	_check(wave_ok, "карта: кружки не на волне снизу вверх или не находятся касанием")
	_check(path.level_at(path.node_pos(1) + Vector2(MapPath.NODE_D, 0.0)) == 0 and path.level_at(Vector2(-50.0, -50.0)) == 0,
			"карта: касание мимо кружков попало в уровень")
	_check(path.state_of(11) == MapPath.State.PASSED and path.state_of(12) == MapPath.State.CURRENT
			and path.state_of(13) == MapPath.State.LOCKED and is_equal_approx(path.diameter(12), MapPath.CURRENT_D),
			"карта: состояния кружков 11 / 12 / 13 — %d / %d / %d" % [path.state_of(11), path.state_of(12), path.state_of(13)])
	# Пройденные не зелёные: зелёный — только у текущего (тон от CURRENT_COLOR дальше 0,1).
	var hue_ok := true
	for n in range(1, 12):
		var dh := absf(path.node_color(n).h - MapPath.CURRENT_COLOR.h)
		hue_ok = hue_ok and minf(dh, 1.0 - dh) > 0.1
	_check(hue_ok, "карта: пройденный кружок того же зелёного, что и текущий")
	# 19.6b: кружки — картинки листа 6: по одной на цвет PASSED_AREAS (по кругу, как цвета), текущий — зелёная,
	# закрытый — белая; картинки 128–256 px в 34–140 px — с mipmaps.
	_check(MapPath.PASSED_TEX.size() == MapPath.PASSED_AREAS.size() and path.node_texture(12) == MapPath.CURRENT_TEX
			and path.node_texture(13) == MapPath.LOCKED_TEX and path.node_texture(1) == MapPath.PASSED_TEX[0]
			and path.node_texture(8) == MapPath.PASSED_TEX[0] and path.node_texture(11) == MapPath.PASSED_TEX[3]
			and path.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
			"карта: картинки кружков (лист 6) не по состояниям или фильтр без mipmaps")
	_check(int(path.stars.get(5, 0)) == GameState.get_stars(5) and GameState.get_stars(5) > 0,
			"карта: звёзды уровня 5 не из прогресса")
	# Вход: текущий уровень на FOCUS_AT высоты окна; рисуются только видимые кружки.
	var on_screen: float = path.node_pos(12).y - map.scroll.scroll_vertical
	_check(absf(on_screen - map.scroll.size.y * LevelMap.FOCUS_AT) <= 1.0,
			"карта: текущий на высоте %.0f окна %.0f (ждали %.0f)" % [on_screen, map.scroll.size.y,
			map.scroll.size.y * LevelMap.FOCUS_AT])
	var band := path.view_band()
	var vr := path.visible_range(band.x, band.y)
	_check(vr.x <= 12 and vr.y >= 12 and vr.y - vr.x <= int((band.y - band.x) / MapPath.STEP) + 5,
			"карта: видимые уровни %s при полосе %s" % [str(vr), str(band)])
	# Касания: открытый — level_pressed, закрытый — level_locked и дрожь (переход в игру в проверке не нужен).
	path.level_pressed.disconnect(map.open_level)
	var got: Array[int] = []
	var on_open := func(n: int) -> void: got.append(n)
	var on_locked := func(n: int) -> void: got.append(-n)
	path.level_pressed.connect(on_open)
	path.level_locked.connect(on_locked)
	path.tap(5)
	path.tap(12)
	path.tap(13)
	path.tap(path.count + 1)
	_check(got == [5, 12, -13], "карта: касания 5, 12, 13 и за краем — %s (ждали [5, 12, -13])" % str(got))
	_check(path._shake_level == 13, "карта: закрытый уровень не вздрогнул")
	map.open_level(13)
	_check(GameState.requested_level == 0 and not Transition.is_busy(), "карта: закрытый уровень открылся")
	# Мышь: щелчок (сдвиг до TAP_SLOP) — касание, перетаскивание дальше — нет. При прокрутке карта едет за
	# пальцем: на карте он стоит на месте, на экране уходит — касание по экранному сдвигу отменяется, в том числе
	# если палец вернулся (тянул вверх-вниз).
	got.clear()
	var at7 := path.node_pos(7)
	var drag := Vector2(0.0, MapPath.TAP_SLOP + 10.0)
	path._gui_input(_mouse_at(at7, true))
	path._gui_input(_mouse_at(at7 + Vector2(0.0, 6.0), false))
	path._gui_input(_mouse_at(at7, true))
	path._gui_input(_mouse_at(at7 + drag, false))
	path._gui_input(_mouse_at(at7, true))
	path._gui_input(_drag_at(at7, drag))
	path._gui_input(_mouse_at(at7, false, drag))
	path._gui_input(_mouse_at(at7, true))
	path._gui_input(_drag_at(at7, drag))
	path._gui_input(_drag_at(at7, Vector2.ZERO))
	path._gui_input(_mouse_at(at7, false))
	_check(got == [7], "карта: щелчок, перетаскивание, прокрутка с кружка, туда-обратно — %s (ждали [7])" % str(got))
	path.set_hovered(5)
	var hand := (path as Control).mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND
	path.set_hovered(13)
	_check(hand and (path as Control).mouse_default_cursor_shape == Control.CURSOR_ARROW,
			"карта: курсор над открытым — «рука», над закрытым — стрелка")
	path.set_hovered(0)
	# «Меньше движения»: пульс текущего стоит, закрытый не вздрагивает.
	await get_tree().create_timer(MapPath.SHAKE_TIME + 0.1).timeout
	GameState.reduce_motion = true
	await _frames(2)
	path.tap(14)
	await _frames(2)
	_check(is_zero_approx(path.pulse) and is_zero_approx(path._shake),
			"карта «меньше движения»: пульс %.2f, дрожь %.2f" % [path.pulse, path._shake])
	GameState.reduce_motion = false
	# Альбом 16:9: дорога по центру экрана, «домой» в левом верхнем углу, счёт по центру верхнего ряда.
	map.size = Vector2(2276, 1280)
	await _frames(2)
	var mid := path.size.x * 0.5
	_check(is_equal_approx(path.size.x, 2276.0) and absf(path.node_pos(12).x - mid) <= MapPath.AMP + 0.5
			and absf(path.node_pos(13).x - mid) <= MapPath.AMP + 0.5,
			"карта в альбоме: ширина %.0f, кружки не у середины" % path.size.x)
	var hc := map.home_button.position + map.home_button.size * 0.5
	var row_l: float = map.star.position.x - HudHeader.STAR_X * LevelMap.SCORE_SIZE
	var row_r: float = map.score_label.position.x + map.score_label.size.x
	_check(hc.distance_to(Vector2(72.0, 84.0)) < 1.0 and absf((row_l + row_r) * 0.5 - 1138.0) < 2.0,
			"карта в альбоме: «домой» в %s, счёт %.0f…%.0f" % [str(hc), row_l, row_r])
	map.queue_free()
	await _frames(1)
	# Новый игрок: уровень 1 у низа, но на экране (прокрутка упёрлась в низ карты).
	GameState.reset_progress()
	map = ps.instantiate() as LevelMap
	add_child(map)
	map.size = Vector2(720, 1280)
	await _frames(3)
	var y1: float = map.path.node_pos(1).y - map.scroll.scroll_vertical
	_check(map.path.current == 1 and map.path.count == 1 + MapPath.AHEAD
			and y1 > MapPath.CURRENT_D and y1 < map.scroll.size.y - MapPath.CURRENT_D * 0.5,
			"карта нового игрока: уровень 1 на высоте %.0f окна %.0f" % [y1, map.scroll.size.y])
	map.queue_free()
	await _frames(1)
	GameState.reset_progress()
	print("  волна снизу вверх, касание кружков, текущий на %.0f %% высоты, видимые уровни, закрытые вздрагивают, мышь, курсор, «Меньше движения», альбом, новый игрок" % (LevelMap.FOCUS_AT * 100.0))



## Главы 19.5c (Chapters, STYLE 11.6): таблицы (длины, начала с 1 по возрастанию, повтор с LOOP_FROM ровно по
## LOOP_SPAN), номера и начала глав на уровнях 1..CHAPTERS_LAST (образцы — из tools/chapters_model.py), тема фона
## у каждой главы, высоты карты MapPath.rise / level_below с зазором CHAPTER_GAP, плашка на карте (между кружками, не
## задевает их и звёзды, не ловит касание, текст влезает на ru / en / tr) и тема фона главы посреди экрана.
func _test_chapters() -> void:
	_section("Главы (19.5c)")
	var n_ch := Chapters.count()
	var total := LevelPack.count()
	var loop_from: int = clampi(LevelPack.DATA.LOOP_FROM, 1, total)
	_check(Chapters.NAMES.size() == n_ch and Chapters.IDEAS.size() == n_ch and Chapters.THEMES.size() == n_ch,
			"главы: длины FIRST / NAMES / IDEAS / THEMES — %d / %d / %d / %d" % [n_ch, Chapters.NAMES.size(),
			Chapters.IDEAS.size(), Chapters.THEMES.size()])
	var rising := n_ch > 0 and Chapters.FIRST[0] == 1 and Chapters.FIRST[n_ch - 1] <= total
	for i in range(1, n_ch):
		rising = rising and Chapters.FIRST[i] > Chapters.FIRST[i - 1]
	_check(rising, "главы: FIRST %s — не с 1 по возрастанию в пределах 1..%d" % [str(Chapters.FIRST), total])
	var k := Chapters.FIRST.find(loop_from)
	var span_ok := k >= 0
	for i in range(maxi(k, 0), n_ch):
		var nxt: int = total + 1
		if i + 1 < n_ch:
			nxt = Chapters.FIRST[i + 1]
		span_ok = span_ok and nxt - Chapters.FIRST[i] == Chapters.LOOP_SPAN
	_check(span_ok, "главы: с LOOP_FROM %d главы не по LOOP_SPAN %d уровней" % [loop_from, Chapters.LOOP_SPAN])
	var theme_ok := true
	for t: Dictionary in Chapters.THEMES:
		theme_ok = theme_ok and t.size() == Background.THEME_PARAMS.size()
		for key: String in Background.THEME_PARAMS:
			theme_ok = theme_ok and t.get(key) is Color
	var v1: Color = Chapters.theme_of(1)["vignette"]
	_check(theme_ok and is_equal_approx(v1.a, Chapters.VIGNETTE_ALPHA),
			"главы: у темы нет всех цветов %s или виньетка не с альфой шейдера (%.3f)" % [str(Background.THEME_PARAMS.keys()),
			v1.a])
	# Номера и начала глав подряд: заготовленные и три круга повтора. Начало — где сменился номер; номер растёт на 1;
	# у главы одна тема (index_of первого уровня); starts_upto — число начал на 2..уровень; у повтора нет идеи.
	var last := total + 3 * (total - loop_from + 1)
	var starts := 0
	var bad := 0
	for lv in range(1, last + 1):
		var num := Chapters.number_of(lv)
		var prev: int = Chapters.number_of(lv - 1) if lv > 1 else 0
		var start := Chapters.is_start(lv)
		if lv > 1 and start:
			starts += 1
		var fl := Chapters.first_level(lv)
		var ok := start == (num != prev) and (num == prev or num == prev + 1)
		ok = ok and fl <= lv and Chapters.is_start(fl) and Chapters.index_of(fl) == Chapters.index_of(lv)
		ok = ok and Chapters.starts_upto(lv) == starts and (lv <= total or Chapters.idea_of(lv) == "")
		if not ok:
			bad += 1
			if bad == 1:
				print("    первый сбой — уровень %d: глава %d, начало %s, первый уровень %d" % [lv, num, start, fl])
	_check(bad == 0, "главы: номера и начала не сходятся на %d уровнях из %d" % [bad, last])
	var got_samples: Array = []
	for s: Array in CHAPTER_SAMPLES:
		var lv0: int = s[0]
		got_samples.append([lv0, Chapters.index_of(lv0), Chapters.number_of(lv0), Chapters.is_start(lv0)])
	_check(got_samples == CHAPTER_SAMPLES, "главы: образцы (уровень, индекс, номер, начало) %s, ждали %s"
			% [str(got_samples), str(CHAPTER_SAMPLES)])
	# Высоты карты: шаг STEP, перед началом главы ещё CHAPTER_GAP; дорога в зазоре непрерывна; level_below — обратная.
	var rise_bad := 0
	if not is_zero_approx(MapPath.rise(1.0)):
		rise_bad += 1
	for lv in range(2, last + 1):
		var r0 := MapPath.rise(float(lv - 1))
		var r1 := MapPath.rise(float(lv))
		var step: float = MapPath.STEP + (MapPath.CHAPTER_GAP if Chapters.is_start(lv) else 0.0)
		var half := MapPath.rise(float(lv) - 0.5)
		if not is_equal_approx(r1 - r0, step) or not is_equal_approx(half, (r0 + r1) * 0.5) \
				or MapPath.level_below(r1, last) != lv or MapPath.level_below(r1 - 0.5, last) != lv - 1:
			rise_bad += 1
	_check(rise_bad == 0 and is_equal_approx(MapPath.rise(61.0), 60.0 * MapPath.STEP + MapPath.CHAPTER_GAP),
			"карта глав: высоты rise / level_below не сходятся на %d уровнях, rise(61) = %.0f" % [rise_bad,
			MapPath.rise(61.0)])
	# Карта игрока на уровне 58: впереди глава 2 (61).
	GameState.reset_progress()
	for i in range(1, 58):
		GameState.complete_level(i, 1 + i % 3, 100)
	var map := (load(MAP_SCENE) as PackedScene).instantiate() as LevelMap
	add_child(map)
	map.size = Vector2(720, 1280)
	await _frames(3)
	var path: MapPath = map.path
	var hit_ok := path.current == 58 and path.count == 58 + MapPath.AHEAD
	for n in range(1, path.count + 1):
		hit_ok = hit_ok and path.level_at(path.node_pos(n)) == n
	_check(hit_ok, "карта глав: текущий %d, кружков %d, кружки не находятся касанием через зазор"
			% [path.current, path.count])
	var p60 := path.node_pos(60)
	var p61 := path.node_pos(61)
	var bp := path.banner_pos(61)
	_check(is_equal_approx(p60.y - p61.y, MapPath.STEP + MapPath.CHAPTER_GAP)
			and is_equal_approx(bp.y, (p60.y + p61.y) * 0.5) and is_equal_approx(bp.x, path.size.x * 0.5)
			and path.level_at(bp) == 0,
			"карта глав: зазор 60–61 %.0f, плашка в %s (кружки %s, %s) или ловит касание" % [p60.y - p61.y, str(bp),
			str(p60), str(p61)])
	# Плашка (лицо, губа, тень) не задевает кружок 61 со звёздами сверху и текущий крупный кружок 60 с кольцом снизу.
	var b_top := bp.y - MapPath.BANNER_H * 0.5 - MapPath.BANNER_DEPTH * 0.5
	var b_bottom := bp.y + MapPath.BANNER_H * 0.5 + MapPath.BANNER_DEPTH * 0.5 + MapPath.BANNER_SHADOW
	var stars_bottom := p61.y + MapPath.NODE_D * 0.5 + MapPath.STAR_DROP * MapPath.STAR_SIZE + MapPath.STAR_SIZE
	var node_top := p60.y - MapPath.CURRENT_D * 0.5 - MapPath.PULSE_GROW * 0.5
	_check(b_top > stars_bottom and b_bottom < node_top,
			"карта глав: плашка %.0f…%.0f задевает звёзды 61 (низ %.0f) или кружок 60 (верх %.0f)" % [b_top, b_bottom,
			stars_bottom, node_top])
	var b1 := path.banner_pos(1)
	_check(b1.y - MapPath.BANNER_H * 0.5 > path.node_pos(1).y + MapPath.CURRENT_D * 0.5
			and b1.y + MapPath.BANNER_H * 0.5 + MapPath.BANNER_DEPTH + MapPath.BANNER_SHADOW <= path.map_height(),
			"карта глав: плашка главы 1 в %s — не под уровнем 1 или за низом карты %.0f" % [str(b1), path.map_height()])
	var r := path.visible_range(path.node_pos(61).y - 10.0, path.node_pos(60).y + 10.0)
	_check(r.x <= 60 and r.y >= 61, "карта глав: видимые уровни %s у плашки главы 2" % str(r))
	# Текст плашки на всех языках влезает без ужатия в 720 по ширине (с полями BANNER_PAD и отступом 20 с боков).
	var loc0 := TranslationServer.get_locale()
	var font := MapPath.FONT
	var wide := ""
	var wide_w := 0.0
	var fit_ok := true
	var heads: Array[int] = Chapters.FIRST.duplicate()
	heads.append_array([total + 1, total + 1 + Chapters.LOOP_SPAN * 5])
	for loc: String in ["ru", "en", "tr"]:
		TranslationServer.set_locale(loc)
		for lv in heads:
			var text := path.banner_text(lv)
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, MapPath.BANNER_FONT).x
			fit_ok = fit_ok and text.contains(str(Chapters.number_of(lv))) and not text.contains("%")
			if tw > wide_w:
				wide_w = tw
				wide = text
	TranslationServer.set_locale(loc0)
	_check(fit_ok and wide_w + 2.0 * MapPath.BANNER_PAD <= path.size.x - 40.0,
			"карта глав: плашка «%s» шириной %.0f не влезает в %.0f или без номера главы" % [wide, wide_w, path.size.x])
	# Тема фона — глава уровня посреди экрана: у входа (уровень 58) — глава 1, у верха карты — глава 2.
	_check(map.background.get_chapter_theme() == Chapters.theme_of(58),
			"карта глав: при входе фон не темы главы 1")
	map.scroll.scroll_vertical = 0
	await _frames(2)
	var band := path.view_band()
	var near := path.level_near((band.x + band.y) * 0.5)
	_check(near >= 61 and map.background.get_chapter_theme() == Chapters.theme_of(61),
			"карта глав: у верха карты посреди экрана уровень %d, фон не темы главы 2" % near)
	await get_tree().create_timer(Background.THEME_FADE + 0.1).timeout
	var top: Color = map.background.theme_colors().get("top", Color.BLACK)
	var top2: Color = Chapters.theme_of(61)["top"]
	_check(top.is_equal_approx(top2), "карта глав: после перехода верх фона %s, ждали %s" % [str(top), str(top2)])
	map.queue_free()
	await _frames(1)
	GameState.reset_progress()
	print("  таблицы, номера и начала глав 1..%d, образцы Python, высоты карты с зазором, плашка главы 2 между кружками, текст на ru / en / tr, тема фона посреди экрана" % last)


## Карточка начала главы 19.5d (ChapterCard, STYLE 11.6): когда нужна (wanted), игра на уровне 61 — карточка
## главы 2 с идеей над серединой поля, между FxLayer и DragLayer, нажатий не ловит; нажатие убирает её раньше,
## «Заново» и переигровка пройденного не повторяют, сама уходит за total_time; тексты глав на ru / en / tr не
## ужимаются.
func _test_chapter_card() -> void:
	_section("Карточка главы (19.5d)")
	var cases := [[61, 61, true, 0, true], [61, 61, true, 61, false], [61, 62, true, 0, false],
			[60, 60, true, 0, false], [1, 1, true, 0, false], [61, 61, false, 0, false], [501, 501, true, 0, true],
			[551, 551, true, 501, true]]
	var wrong: Array = []
	for c: Array in cases:
		var n: int = c[0]
		var current: int = c[1]
		var own: bool = c[2]
		var shown: int = c[3]
		if ChapterCard.wanted(n, current, own, shown) != c[4]:
			wrong.append(c)
	_check(wrong.is_empty(), "карточка главы: wanted ошибается на [уровень, текущий, свой, была, ждали] %s"
			% str(wrong))
	GameState.reset_progress()
	for i in range(1, 61):
		GameState.complete_level(i, 3, 100)
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	add_child(game)
	await _frames(3)
	var card: ChapterCard = game.chapter_card
	var board_r: Rect2 = game.layout.get("board", Rect2())
	var w := card.card_width()
	var h := card.card_height()
	var face_c := card.position + Vector2(w, h + ChapterCard.DEPTH) * 0.5
	_check(game.level == 61 and card.is_shown() and card.level == 61 and card.head == tr(ChapterCard.HEAD) % 2
			and card.title == tr(Chapters.name_of(61)) and not card.idea.is_empty()
			and card.idea == tr(Chapters.idea_of(61)),
			"карточка главы: уровень %d, видна %s, «%s · %s · %s»" % [game.level, card.is_shown(), card.head,
			card.title, card.idea])
	var card_i := game.get_children().find(card)
	_check(card.mouse_filter == Control.MOUSE_FILTER_IGNORE and card_i > game.fx_layer.get_index()
			and card_i < game.drag_layer.get_index(),
			"карточка главы: ловит нажатия или не между FxLayer и DragLayer (%d; %d…%d)" % [card_i,
			game.fx_layer.get_index(), game.drag_layer.get_index()])
	_check(board_r.has_area() and face_c.distance_to(board_r.get_center()) < 1.0
			and w <= board_r.size.x - 2.0 * ChapterCard.SIDE + 0.5 and h + ChapterCard.DEPTH <= board_r.size.y,
			"карточка главы: лицо %.0f×%.0f с центром %s, место поля %s" % [w, h, str(face_c), str(board_r)])
	# Нажатие убирает её раньше (и идёт дальше в игру — мимо всего, слот не берётся).
	game._input(_mouse_press(true))
	game._input(_mouse_press(false))
	_check(not card.is_shown(), "карточка главы: нажатие не убрало карточку")
	await get_tree().create_timer(ChapterCard.FADE_OUT + 0.15).timeout
	_check(not card.visible and is_equal_approx(card.modulate.a, 1.0),
			"карточка главы: после ухода видна или прозрачность не вернулась")
	# «Заново» — без карточки; переигровка пройденного начала главы (61 при текущем 62) — тоже.
	game._restart_same()
	await _frames(2)
	var again := card.visible
	GameState.complete_level(61, 3, 100)
	game.start_level(61)
	await _frames(2)
	_check(not again and not card.visible, "карточка главы: «Заново» (%s) или переигровка пройденного (%s) её повторили"
			% [again, card.visible])
	# Сама уходит: глава 9 без идеи — за total_time (у глав 4–8 с 19.5e есть идея — механика).
	card.show_chapter(401)
	var total := card.total_time()
	await get_tree().create_timer(total * 0.5).timeout
	var mid := card.is_shown()
	await get_tree().create_timer(total * 0.5 + 0.2).timeout
	_check(card.idea.is_empty() and mid and not card.visible,
			"карточка главы: без идеи (%s), видна посередине %s, через %.1f с видна %s" % [card.idea.is_empty(), mid,
			total, card.visible])
	# Тексты всех глав (и первой главы повтора) на ru / en / tr — без ужатия.
	var loc0 := TranslationServer.get_locale()
	var shrunk: Array = []
	var heads: Array[int] = Chapters.FIRST.duplicate()
	heads.append(LevelPack.count() + 1)
	for loc: String in ["ru", "en", "tr"]:
		TranslationServer.set_locale(loc)
		for lv in heads:
			var rows := [[tr(ChapterCard.HEAD) % Chapters.number_of(lv), ChapterCard.HEAD_FONT],
					[tr(Chapters.name_of(lv)), ChapterCard.NAME_FONT]]
			if not Chapters.idea_of(lv).is_empty():
				rows.append([tr(Chapters.idea_of(lv)), ChapterCard.IDEA_FONT])
			for row: Array in rows:
				var text: String = row[0]
				var fs: int = row[1]
				if card.font_size_for(text, fs) != fs:
					shrunk.append("%s «%s»" % [loc, text])
	TranslationServer.set_locale(loc0)
	_check(shrunk.is_empty(), "карточка главы: ужимаются %s" % str(shrunk))
	game.queue_free()
	await _frames(1)
	GameState.reset_progress()
	print("  wanted, карточка главы 2 над полем на уровне 61, нажатие убирает, «Заново» и переигровка без неё, уход за %.1f с, тексты ru / en / tr" % total)

## Уровни глав с механиками (19.5e): план механик (CHAPTER_MECH_PLAN), повтор, Chapters.rule_of и игра.
func _test_chapter_levels() -> void:
	_section("Уровни глав с механиками (19.5e)")
	var total := LevelPack.count()
	var first_mech: int = Chapters.FIRST[3]
	# План: механика каждого заготовленного уровня, одна на уровень.
	var off_plan: Array = []
	var off_n := 0
	var mixed: Array[int] = []
	var per_mech := {}
	for n in range(1, total + 1):
		var letter := "."
		var row := Chapters.index_of(n) - Chapters.FIRST.find(first_mech)
		if n >= first_mech and row < CHAPTER_MECH_PLAN.size():
			letter = CHAPTER_MECH_PLAN[row].substr(n - Chapters.first_level(n), 1)
		var d := LevelPack.get_level(n)
		var mech := LevelPack.mechanic_of(d)
		if mech != String(MECH_LETTERS.get(letter, "?")):
			off_n += 1
			if off_plan.size() < MAX_REPORTS:
				off_plan.append("%d: «%s» вместо %s" % [n, mech, letter])
		var kinds := 0
		for key: String in ["holes", "pinned", "tints"]:
			kinds += 0 if (d.get(key, []) as Array).is_empty() else 1
		for nm: Dictionary in d.numbers:
			if int(nm.value) == ShikakuSolver.ANY:
				kinds += 1
				break
		if kinds > 1:
			mixed.append(n)
		per_mech[mech] = int(per_mech.get(mech, 0)) + 1
	_check(off_n == 0, "механика %d уровней не по плану tools/chapter_levels.py: %s" % [off_n, str(off_plan)])
	_check(mixed.is_empty(), "в уровнях больше одной механики: %s" % str(mixed.slice(0, MAX_REPORTS)))
	# Повтор после count(): та же механика и столько же её клеток, что у исходного уровня.
	var span: int = total - LevelPack.DATA.LOOP_FROM + 1
	var bad_mirror: Array[int] = []
	for n in range(total + 1, 1001):
		var src := LevelPack.get_level(LevelPack.DATA.LOOP_FROM + (n - total - 1) % span)
		var d := LevelPack.get_level(n)
		var same := LevelPack.mechanic_of(d) == LevelPack.mechanic_of(src)
		for key: String in ["holes", "pinned", "tints"]:
			same = same and (d.get(key, []) as Array).size() == (src.get(key, []) as Array).size()
		if not same:
			bad_mirror.append(n)
	_check(bad_mirror.is_empty(), "повтор не сохранил механику исходного уровня: %s" % str(bad_mirror.slice(0, MAX_REPORTS)))
	# Главы, которые вводят механику, — по плану; их первые RULE_LEVELS уровней — вводные (все с механикой).
	var bad_ch: Array[String] = []
	for i in Chapters.FIRST.size():
		var m: String = Chapters.MECHANICS[i]
		var start: int = Chapters.FIRST[i]
		if m.is_empty():
			continue
		if Chapters.intro_first(m) != start or Chapters.idea_of(start).is_empty():
			bad_ch.append("глава %d: intro_first %d, идея «%s»" % [i + 1, Chapters.intro_first(m), Chapters.idea_of(start)])
		for n in range(start, start + Chapters.RULE_LEVELS):
			if LevelPack.mechanic_of(LevelPack.get_level(n)) != m:
				bad_ch.append("уровень %d без механики главы (%s)" % [n, m])
	_check(bad_ch.is_empty() and Chapters.intro_first("") == 0 and Chapters.intro_first("nope") == 0
			and Chapters.MECHANICS.size() == Chapters.FIRST.size(),
			"Chapters.MECHANICS / intro_first: %s" % str(bad_ch))
	# Правило над полем: [уровень, ежедневная, пройдено до (GameState.level), ждали].
	var cases := [[151, false, 151, "holes"], [155, false, 400, "holes"], [156, false, 156, ""], [157, false, 157, ""],
			[201, false, 201, "pinned"], [251, false, 251, "tints"], [301, false, 301, "unknown"],
			[305, false, 305, "unknown"], [306, false, 306, ""], [351, false, 351, ""], [150, false, 150, ""],
			[651, false, 651, ""], [351, true, 20, "holes"], [351, true, 155, "holes"], [351, true, 156, ""],
			[352, true, 205, "pinned"], [352, true, 206, ""], [353, true, 20, ""]]
	var wrong: Array = []
	for c: Array in cases:
		var got := Chapters.rule_of(c[0], LevelPack.get_level(c[0]), c[1], c[2])
		if got != c[3]:
			wrong.append([c[0], c[1], c[2], got])
	_check(wrong.is_empty(), "Chapters.rule_of ошибается на [уровень, ежедневная, пройдено, дал] %s" % str(wrong))

	# Игра: начало глав 4–7 — поле с механикой, правило над полем, идея на карточке; до победы.
	GameState.reset_progress()
	for i in range(1, first_mech):
		GameState.complete_level(i, 3, 100)
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	add_child(game)
	await _frames(3)
	var won := 0
	for lvl: int in [151, 201, 251, 301]:
		for i in range(GameState.level, lvl):
			GameState.complete_level(i, 3, 100)
		if game.level != lvl:
			game.start_level(lvl)
		await _frames(2)
		var m: String = Chapters.MECHANICS[Chapters.index_of(lvl)]
		var d := game.level_data
		var on_board := true
		match m:
			"holes":
				for h: Vector2i in d.get("holes", []):
					on_board = on_board and game.board.is_blocked(h)
			"pinned":
				on_board = game.board.pinned_blocks().size() == (d.get("pinned", []) as Array).size()
		var card: ChapterCard = game.chapter_card
		_check(game.level == lvl and LevelPack.mechanic_of(d) == m and on_board
				and game.coach_label.visible and game.coach_label.text == tr(LabLevels.rule(m))
				and card.is_shown() and card.idea == tr(Chapters.idea_of(lvl)),
				"L%d (%s): уровень %d, механика «%s», на поле %s, над полем «%s» (видно %s), карточка %s «%s»" % [lvl, m,
				game.level, LevelPack.mechanic_of(d), on_board, game.coach_label.text, game.coach_label.visible,
				card.is_shown(), card.idea])
		var before: int = game.moves.size()
		game.hints.give()
		var hinted: bool = game.moves.size() > before
		for _i in 80:
			if game.finished:
				break
			if _play_solution_move(game).is_empty():
				break
		if _check(hinted and game.finished and game.board.is_full() and GameState.get_stars(lvl) >= 1
				and GameState.level == lvl + 1,
				"L%d (%s): подсказка сработала %s, победа %s, звёзд %d, уровень игрока %d" % [lvl, m, hinted,
				game.finished, GameState.get_stars(lvl), GameState.level]):
			won += 1
	# Не вводные уровни и глава 8 — без правила (механика на поле есть).
	for lvl: int in [157, 351]:
		game.start_level(lvl)
		await _frames(1)
		_check(not game.coach_label.visible and not LevelPack.mechanic_of(game.level_data).is_empty(),
				"L%d: над полем «%s» (видно %s), механика «%s»" % [lvl, game.coach_label.text, game.coach_label.visible,
				LevelPack.mechanic_of(game.level_data)])
	# Ежедневная с механикой: правило, пока вводные уровни механики не пройдены.
	GameState.reset_progress()
	for i in range(1, 21):
		GameState.complete_level(i, 3, 100)
	game.start_level(351, true)
	await _frames(1)
	var early := game.coach_label.visible and game.coach_label.text == tr(LabLevels.rule("holes"))
	for i in range(21, first_mech + Chapters.RULE_LEVELS):
		GameState.complete_level(i, 3, 100)
	game.start_level(351, true)
	await _frames(1)
	_check(early and game.daily_mode and not game.coach_label.visible,
			"ежедневная 351 (препятствия): правило до вводных %s, после — видно %s" % [early, game.coach_label.visible])
	game.queue_free()
	await _frames(2)
	GameState.reset_progress()
	print("  план механик 1..%d (%s), повтор до 1000, rule_of — %d случаев, в игре до победы: %d из 4"
			% [total, str(per_mech), cases.size(), won])


## Экран лидеров 18.3: модель ответа YSDK, разрыв между топом и соседями, локальная строка вне SDK,
## гостевой статус и вход, вкладки, переводы и центрирование колонны. В Godot/YSDK экран проверяется отдельно.
func _test_leaders() -> void:
	_section("Экран лидеров (18.3)")
	# Модель не зависит от узлов и от наличия SDK.
	var answer := {"userRank": 10, "entries": [
		{"rank": 1, "score": 9000, "name": "Первый", "id": "a"},
		{"rank": 2, "score": 8000, "name": "", "id": "b"},
		{"rank": 2, "score": 7999, "name": "дубликат", "id": "dup"},
		{"rank": 3, "score": 7000, "name": "Очень длинное имя игрока", "id": "c"},
		{"rank": 10, "score": 1000, "name": "Я", "id": "me"},
		{"rank": 11, "score": 900, "name": "Сосед 1", "id": "d"},
		{"rank": 12, "score": 800, "name": "Сосед 2", "id": "e"},
		{"rank": 13, "score": 700, "name": "Сосед 3", "id": "f"},
	]}
	var rows := LeaderboardData.rows(answer, "me")
	var shape: Array[int] = []
	for row: Dictionary in rows:
		shape.append(0 if bool(row["gap"]) else int(row["rank"]))
	_check(shape == [1, 2, 3, 0, 10, 11, 12, 13], "лидеры: строки/разрыв/дубликат — %s" % str(shape))
	_check(LeaderboardData.my_rank(rows) == 10 and bool(rows[4]["me"]), "лидеры: своё место %d (ждали 10)" % LeaderboardData.my_rank(rows))
	_check(rows[1]["name"] == LeaderboardData.ANON_NAME and str(rows[2]["name"]).ends_with("…")
			and str(rows[2]["name"]).length() <= LeaderboardData.MAX_NAME,
			"лидеры: пустое или длинное имя не обработано: %s" % str(rows.slice(0, 3)))
	# Старый ответ с местами от 0: сдвиг на 1, место игрока тоже; userRank 0 — игрока в таблице нет.
	var old_api := {"userRank": 1, "entries": [
		{"rank": 0, "score": 50, "name": "", "id": ""},
		{"rank": 1, "score": 40, "name": "Второй", "id": ""},
	]}
	var old_rows := LeaderboardData.rows(old_api, "")
	_check(old_rows.size() == 2 and old_rows[0]["rank"] == 1 and not bool(old_rows[0]["me"])
			and old_rows[1]["rank"] == 2 and bool(old_rows[1]["me"]),
			"лидеры: старые места с нуля не сдвинуты: %s" % str(old_rows))
	old_api["userRank"] = 0
	_check(LeaderboardData.my_rank(LeaderboardData.rows(old_api, "")) == 0,
			"лидеры: userRank 0 подсветил чужую строку")
	# id игрока не нашёлся среди строк — своя строка по userRank.
	_check(LeaderboardData.my_rank(LeaderboardData.rows(answer, "нет-такого")) == 10,
			"лидеры: без совпадения id своя строка не взята по userRank")
	# Полный ответ YSDK (10 первых + по 3 соседа) не влезает в карточку: строка игрока остаётся всегда,
	# срезаются дальние соседи, затем хвост топа (LeaderboardData.fit_ranks).
	var cases := [[15, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0, 14, 15, 16]],
			[13, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]],
			[14, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]],
			[500, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0, 499, 500, 501]],
			[0, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]]]
	for c: Array in cases:
		var me_at: int = c[0]
		var full := _leaders_answer(me_at)
		var fit := LeaderboardData.rows(full, "me")
		var got: Array[int] = []
		for row: Dictionary in fit:
			got.append(0 if bool(row["gap"]) else int(row["rank"]))
		_check(got == c[1] and fit.size() <= LeaderboardData.MAX_ROWS
				and LeaderboardData.my_rank(fit) == me_at,
				"лидеры: игрок на %d — строки %s (ждали %s)" % [me_at, str(got), str(c[1])])
	var tight: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 18]
	_check(LeaderboardData.fit_ranks(tight, 15, 6) == [1, 2, 3, 14, 15],
			"лидеры: узкая карточка — %s" % str(LeaderboardData.fit_ranks(tight, 15, 6)))
	_check(LeaderRows.height_for(LeaderRows.MAX_ROWS) <= 640.0 + 0.5,
			"лидеры: %d строк выше карточки (%.0f px)" % [LeaderRows.MAX_ROWS, LeaderRows.height_for(LeaderRows.MAX_ROWS)])
	_check(LeaderboardData.status_text({"error": LeaderboardData.ERROR_NO_SDK}, false, [], false).begins_with("Таблица лидеров")
			and LeaderboardData.status_text({"error": "NETWORK"}, false, [], false).begins_with("Не удалось"),
			"лидеры: состояния NO_SDK / сеть")
	_check(LeaderboardData.status_text({}, false, rows, false).begins_with("Войдите")
			and LeaderboardData.status_text({}, true, [], true).begins_with("Пройдите задачу")
			and LeaderboardData.status_text({}, true, rows, false).is_empty(),
			"лидеры: состояния входа / ежедневной / своё место")

	var saved_available := YSDK.is_available
	var saved_pending := YSDK.sdk_pending
	var saved_auth_known := YSDK.auth_known
	var saved_authorized := YSDK.is_authorized
	var saved_player_id := YSDK.player_id
	var saved_total := GameState.total_score
	GameState.complete_level(1, 2, 321)
	YSDK.is_available = false
	YSDK.sdk_pending = false
	YSDK.auth_known = false
	YSDK.is_authorized = false
	YSDK.player_id = ""
	var ps := load(LEADERS_SCENE) as PackedScene
	var screen: LeadersScreen = null
	if ps:
		screen = ps.instantiate() as LeadersScreen
	_check(screen != null, "экран лидеров не загружается")
	if screen == null:
		YSDK.is_available = saved_available
		YSDK.sdk_pending = saved_pending
		YSDK.auth_known = saved_auth_known
		YSDK.is_authorized = saved_authorized
		YSDK.player_id = saved_player_id
		GameState.total_score = saved_total
		return
	add_child(screen)
	screen.size = Vector2(720, 1280)
	await _frames(2)
	_check(screen.shown.size() == 1 and screen.shown[0]["me"] and screen.shown[0]["rank"] == 0
			and screen.shown[0]["score"] == 321 and screen.rows_view.message.is_empty(),
			"лидеры вне Яндекса: локальная строка %s" % str(screen.shown))
	_check(screen.status_label.text == tr("Таблица лидеров — в Яндекс Играх") and not screen.login_button.visible,
			"лидеры вне Яндекса: статус «%s», кнопка входа %s" % [screen.status_label.text, screen.login_button.visible])
	# Успешный гостевой ответ: свой ряд подсвечен по userRank, кнопка входа появляется только при доступном SDK.
	YSDK.is_available = true
	YSDK.auth_known = true
	YSDK.is_authorized = false
	screen._on_leaderboard_loaded(YSDK.LEADERBOARD_NAME, answer)
	_check(screen.shown.size() == 8 and LeaderboardData.my_rank(screen.shown) == 10
			and screen.status_label.text == tr("Войдите, чтобы попасть в таблицу") and screen.login_button.visible,
			"лидеры гость: строки %d, место %d, статус «%s»" % [screen.shown.size(), LeaderboardData.my_rank(screen.shown), screen.status_label.text])
	# Вошедший игрок на 40-м месте: полный ответ (18 строк) — в карточке 14, своя строка видна и подсвечена.
	YSDK.is_authorized = true
	YSDK.player_id = "me"
	screen._on_leaderboard_loaded(YSDK.LEADERBOARD_NAME, _leaders_answer(40))
	var me_drawn := false
	for row: Dictionary in screen.rows_view.rows:
		me_drawn = me_drawn or (bool(row["me"]) and int(row["rank"]) == 40)
	_check(screen.rows_view.rows.size() == LeaderboardData.MAX_ROWS and me_drawn
			and screen.status_label.text.is_empty() and not screen.login_button.visible,
			"лидеры: игрок на 40-м — строк %d, своя видна %s, статус «%s»" % [screen.rows_view.rows.size(), me_drawn, screen.status_label.text])
	YSDK.is_authorized = false
	YSDK.player_id = ""
	screen.select_tab(LeadersScreen.Tab.STREAK, false)
	_check(screen.tab == LeadersScreen.Tab.STREAK and screen.score_tab.tone == PillButton.Tone.LIGHT
			and screen.streak_tab.tone == PillButton.Tone.GREEN,
			"лидеры: вкладка серии или её тоны не переключились")
	# Перевод подписей экрана и статуса, включая длинную турецкую кнопку входа.
	var saved_locale := TranslationServer.get_locale()
	for loc in ["en", "tr"]:
		TranslationServer.set_locale(loc)
		await _frames(1)
		_check(screen.score_tab.caption.text == tr("ОЧКИ") and screen.streak_tab.caption.text == tr("СЕРИЯ")
				and screen.login_button.caption.text == tr("ВОЙТИ"),
				"лидеры %s: подписи вкладок / входа — «%s», «%s», «%s»" % [loc, screen.score_tab.caption.text,
					screen.streak_tab.caption.text, screen.login_button.caption.text])
	TranslationServer.set_locale(saved_locale)
	screen.size = Vector2(2276, 1280)
	await _frames(2)
	_check(screen.content.get_global_rect().get_center().distance_to(Vector2(1138, 640)) < 1.0
			and screen.home_button.position.x == 24.0,
			"лидеры в альбоме: колонна не по центру или «домой» сместился: %s / %s" % [str(screen.content.get_global_rect()), str(screen.home_button.position)])
	screen.queue_free()
	await _frames(1)
	YSDK.is_available = saved_available
	YSDK.sdk_pending = saved_pending
	YSDK.auth_known = saved_auth_known
	YSDK.is_authorized = saved_authorized
	YSDK.player_id = saved_player_id
	GameState.total_score = saved_total
	GameState.reset_progress()
	print("  модель лидеров, разрыв и место игрока, 14 строк из 18 (своя остаётся), локальная строка вне SDK, гость, вкладки, ru / en / tr, альбом")


## Ответ YSDK как у Яндекса при LEADERBOARD_TOP / LEADERBOARD_AROUND: первые места и соседи игрока на месте me_at
## (0 — гость, только первые места). Строка игрока — id "me", очки убывают по месту.
func _leaders_answer(me_at: int) -> Dictionary:
	var ranks := {}
	for r in range(1, YSDK.LEADERBOARD_TOP + 1):
		ranks[r] = true
	if me_at > 0:
		for r in range(maxi(1, me_at - YSDK.LEADERBOARD_AROUND), me_at + YSDK.LEADERBOARD_AROUND + 1):
			ranks[r] = true
	var entries: Array = []
	for r: int in ranks.keys():
		entries.append({"rank": r, "score": 100000 - r * 10, "name": "Игрок %d" % r,
				"id": "me" if r == me_at else "p%d" % r})
	return {"userRank": me_at, "entries": entries}


## Кнопка мыши в точке at карты; screen_shift — насколько карта к этому моменту уехала по экрану вместе с пальцем
## (палец на карте стоит в at, на экране сдвинут; MapPath меряет касание по экранному сдвигу).
func _mouse_at(at: Vector2, pressed: bool, screen_shift := Vector2.ZERO) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = at
	ev.global_position = at + screen_shift
	return ev


## Движение мыши с зажатой левой кнопкой: на карте палец в at, на экране сдвинут на screen_shift от нажатия.
func _drag_at(at: Vector2, screen_shift: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.position = at
	ev.global_position = at + screen_shift
	return ev


## Уровень с карты и ежедневная задача в игре (18.1f, 18.2c): запрос карты — переигровка пройденного (закрытый не
## открывается), ежедневная — свой заголовок в шапке (влезает), очки в общий счёт не идут, рестарт после полуночи —
## та же дата; окно победы ежедневной — свой заголовок, серия вместо общего счёта, «В МЕНЮ»; обычной — «ДАЛЕЕ».
func _test_daily_game() -> void:
	_section("Уровень с карты и ежедневная задача в игре (18.1f, 18.2)")
	GameState.reset_progress()
	for i in range(1, 12):
		GameState.complete_level(i, 3, 100)
	var ps := load(GAME_SCENE) as PackedScene
	GameState.requested_level = 5
	var game := ps.instantiate() as Game
	add_child(game)
	await _frames(3)
	_check(game.level == 5 and not game.daily_mode and GameState.requested_level == 0
			and game.header.level_label.text == tr("УРОВЕНЬ %d") % 5,
			"с карты: уровень %d (ждали 5), запрос %d, заголовок «%s»" % [game.level, GameState.requested_level,
			game.header.level_label.text])
	# Ежедневная: заголовок, счёт, дата.
	var daily := DailyChallenge.current_level()
	game.start_level(daily, true)
	await _frames(1)
	_check(game.daily_mode and game.daily_date_key == DailyChallenge.current_date_key()
			and game.header.level_label.text == tr("ЗАДАЧА ДНЯ"),
			"ежедневная: режим %s, дата «%s», заголовок «%s»" % [str(game.daily_mode), game.daily_date_key,
			game.header.level_label.text])
	var saved := TranslationServer.get_locale()
	for loc in ["ru", "en", "tr"]:
		TranslationServer.set_locale(loc)
		game.update_hud()
		_check(game.header.fitted_title_size() > HudHeader.TITLE_MIN_SIZE,
				"%s: «%s» в шапке ужат до предела %d" % [loc, game.header.level_label.text, HudHeader.TITLE_MIN_SIZE])
	TranslationServer.set_locale(saved)
	game.level_score = 500
	_check(game.hud_score() == GameState.total_score, "ежедневная: очки задачи попали в общий счёт шапки")
	game.daily_date_key = "2026-10-08"
	game.start_level(daily, true)
	_check(game.daily_mode and game.daily_date_key == "2026-10-08", "рестарт ежедневной сменил дату: «%s»" % game.daily_date_key)
	game.start_level(daily)
	_check(not game.daily_mode and game.daily_date_key.is_empty(), "обычный уровень остался ежедневной задачей")
	# Окно победы: ежедневная и обычная.
	var wp: WinPanel = game.win_panel
	wp.show_daily(3, 150, 4)
	_check(wp.title_label.text.replace("\n", " ") == tr("ЕЖЕДНЕВНАЯ ЗАДАЧА ПРОЙДЕНА!")
			and wp.total_label.text == tr("Серия: %d") % 4 and wp.next_button.text == "В МЕНЮ",
			"победа ежедневной: «%s», «%s», «%s»" % [wp.title_label.text, wp.total_label.text, wp.next_button.text])
	wp.show_result(5, 3, 150, GameState.total_score, 0, 300)
	_check(wp.next_button.text == "ДАЛЕЕ" and wp.title_label.text.replace("\n", " ") == tr("УРОВЕНЬ %d ПРОЙДЕН!") % 5,
			"победа после ежедневной: «%s», «%s»" % [wp.title_label.text, wp.next_button.text])
	wp.hide()
	game.queue_free()
	await _frames(2)
	# Закрытый уровень с карты не открывается: игра с текущего.
	GameState.requested_level = 40
	game = ps.instantiate() as Game
	add_child(game)
	await _frames(3)
	_check(game.level == GameState.level and GameState.requested_level == 0,
			"запрос закрытого уровня 40: игра с %d (ждали %d)" % [game.level, GameState.level])
	game.queue_free()
	await _frames(2)
	GameState.reset_progress()
	print("  переигровка с карты, закрытый не открывается, ежедневная: заголовок, счёт, дата при рестарте, окно победы")


func _check_link(b: Button, what: String) -> void:
	var font := b.get_theme_font(&"font")
	var fs := b.get_theme_font_size(&"font_size")
	var want := float(b.get_theme_constant(&"icon_max_width") + b.get_theme_constant(&"h_separation")) \
			+ font.get_string_size(tr(b.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_check(not b.expand_icon, "%s: expand_icon включён — иконки нет в минимальном размере" % what)
	_check(absf(b.size.x - want) <= 2.0, "%s: ширина %.0f, по содержимому %.0f" % [what, b.size.x, want])


func _check_settings_look(panel: SettingsPanel, tag: String) -> void:
	var card := panel.card
	_check(card != null and card.head_style == CandyCard.Head.VIOLET, "%s: карточка не CandyCard с фиолетовой шапкой" % tag)
	_check(is_equal_approx(card.size.x, SettingsPanel.CARD_W) and absf(card.size.y - card.get_combined_minimum_size().y) < 1.0,
			"%s: карточка %s (ждали ширину %d и высоту по содержимому %.0f)" % [tag, str(card.size), int(SettingsPanel.CARD_W),
			card.get_combined_minimum_size().y])
	var screen := panel.get_global_rect().grow(-12.0)
	var r := card.get_global_rect()
	r.size.y += CandyCard.LIP
	_check(screen.encloses(r), "%s: карточка %s с губой не на экране %s" % [tag, str(r), str(screen)])
	# Шапка — в координатах карточки (14.8e): окно может ещё доигрывать появление (масштаб ×1,02).
	var t := panel.title_label.get_global_rect()
	var head := card.get_global_transform() * Rect2(Vector2.ZERO, Vector2(card.size.x, card.head_height))
	_check(t.position.y >= head.position.y - 0.5 and t.end.y <= head.end.y + 0.5,
			"%s: заголовок %s не в шапке карточки (%.0f…%.0f)" % [tag, str(t), head.position.y, head.end.y])
	var tones := {panel.close_button: PillButton.Tone.GREEN, panel.reset_button: PillButton.Tone.LIGHT,
			panel.confirm_reset_button: PillButton.Tone.RED, panel.cancel_reset_button: PillButton.Tone.LIGHT,
			panel.rate_button: PillButton.Tone.GOLD}
	for b: PillButton in tones:
		_check(b.tone == tones[b], "%s: «%s» — тон %d (ждали %d)" % [tag, b.text, b.tone, tones[b]])
		_check(b.caption.text == b.atr(b.text), "%s: подпись «%s» — не перевод «%s»" % [tag, b.caption.text, b.text])
	var captions := [["ГОТОВО", panel.close_button], ["ПРОДОЛЖИТЬ", panel.close_button],
			["Сбросить прогресс", panel.reset_button], ["СБРОСИТЬ", panel.confirm_reset_button],
			["ОТМЕНА", panel.cancel_reset_button], ["ОЦЕНИТЬ ИГРУ", panel.rate_button]]
	var font := panel.title_label.get_theme_font(&"font")
	var loc := TranslationServer.get_locale()
	for lang: String in ["ru", "en", "tr"]:
		TranslationServer.set_locale(lang)
		for pair: Array in captions:
			_check_pill_caption(pair[1], tr(pair[0]), "%s (%s)" % [tag, lang])
		for msg: String in ["НАСТРОЙКИ", "ПАУЗА", "СБРОСИТЬ ПРОГРЕСС?"]:
			var text := tr(msg)
			var fs := SettingsPanel.title_size(font, text)
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + SettingsPanel.TITLE_OUTLINE
			_check(w <= SettingsPanel.CARD_W - 2.0 * SettingsPanel.CARD_PAD and fs >= 36,
					"%s (%s): «%s» в шапке %.0f px при %d" % [tag, lang, text, w, fs])
	TranslationServer.set_locale(loc)


## Подпись таблетки (13.5e): размер PillButton.caption_size — не меньше MIN_FONT_K от темы, и с ним строка
## (с обводкой) влезает в кнопку без FIT_PAD_K·h с каждой стороны.
func _check_pill_caption(b: PillButton, text: String, tag: String) -> void:
	var font := b.get_theme_font(&"font")
	var fs0 := b.get_theme_font_size(&"font_size")
	var light := b.tone == PillButton.Tone.LIGHT
	var box := b.size if b.size.x > 0.0 and b.size.y > 0.0 else b.custom_minimum_size  # как PillButton (14.8e)
	var fs := PillButton.caption_size(font, text, fs0, light, box)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + PillButton.outline_for(fs, light)
	_check(w <= box.x - 2.0 * PillButton.FIT_PAD_K * box.y and fs >= ceili(fs0 * PillButton.MIN_FONT_K),
			"%s: «%s» %.0f px в кнопке %s при размере %d" % [tag, text, w, str(box), fs])


func _count(counter: Dictionary, key: String) -> void:
	counter[key] = int(counter.get(key, 0)) + 1


static func _esc() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	return ev


# --- 7. Игра целиком -------------------------------------------------------------

func _test_game() -> void:
	_section("Игра целиком")
	GameState.reset_progress()
	var ps := load(GAME_SCENE) as PackedScene
	if not _check(ps != null, "игровая сцена не загружается"):
		return
	var game := ps.instantiate() as Game  # с типом: check_gd сверяет обращения к Game и его компонентам
	add_child(game)
	await _frames(3)
	_check(game.level == 1 and not game.finished, "игра не запустила уровень 1")
	await _test_tutorial(game)
	_test_pause(game)
	await _test_game_layout(game)
	_test_hover(game)
	await _test_board_style(game)
	await _test_shelf(game)
	await _test_buttons(game)
	await _test_header(game)
	await _test_toast(game)
	await _test_juice(game)
	await _test_juice_moves(game)
	await _test_juice_close(game)
	await _test_juice_combo(game)
	await _test_juice_win(game)
	await _test_juice_intro(game)
	await _test_juice_dead_hint(game)
	await _test_quality(game)
	_test_effects_off(game)
	await _test_effects_logic(game)
	await _test_board_rows()
	GameState.reset_progress()

	var levels: Array[int] = [1, 2, 4, 7, 12, 20, 30, 49, 61, 101, 150]
	if _quick:
		levels = [1, 4, 12, 61]
	var dead_end_tested := 0
	for lvl in levels:
		game.start_level(lvl)
		await _frames(1)
		var total_pieces := (game.level_data.pieces as Array).size()
		var in_tray := 0
		for b in game.tray.blocks:
			if b != null:
				in_tray += 1
		_check(in_tray == mini(3, total_pieces), "L%d: в лотке %d блоков" % [lvl, in_tray])

		if dead_end_tested < 3:
			if await _test_dead_end(game, lvl):
				dead_end_tested += 1

		if not _solve_with_hints(game, lvl):
			continue
		_check(GameState.get_stars(lvl) >= 1 and GameState.get_best(lvl) > 0,
				"L%d: уровень не засчитан (звёзды %d, рекорд %d)" % [lvl, GameState.get_stars(lvl), GameState.get_best(lvl)])
	_check(dead_end_tested > 0, "не нашлось ни одного тупикового хода для проверки")
	print("  пройдено подсказками уровней: %d, проверок тупика: %d" % [levels.size(), dead_end_tested])

	# Переигровка: общий счёт растёт только на прирост к рекорду уровня.
	var lvl_r := levels[0]
	var old_total := GameState.total_score
	var old_best := GameState.get_best(lvl_r)
	game.start_level(lvl_r)
	await _frames(1)
	game.hints.give()
	_check(game.score_label.text == HudHeader.format_score(GameState.total_score),
			"при переигровке счёт в HUD вырос до рекорда: %s (всего %d)" % [game.score_label.text, GameState.total_score])
	if _solve_with_hints(game, lvl_r):
		var grow := GameState.total_score - old_total
		var best_grow := GameState.get_best(lvl_r) - old_best
		_check(grow == best_grow, "переигровка: счёт вырос на %d, рекорд на %d" % [grow, best_grow])
		print("  переигровка не накручивает счёт")

	if not _quick:
		await _test_win_flow(game)
	_test_stale_ads(game)

	game.queue_free()
	await _frames(2)


## Juice (14.1): тряска Content — в пределах shake_max · травма² и ровно назад, удары подряд — большая травма,
## hit-stop останавливает твины эффектов, но не твины игры, и не дольше hitstop_max; пул частиц — не больше
## pool_size узлов и particles_max частиц; «Меньше движения» — без тряски, частиц ×reduced_particles,
## настройка в settings.cfg.
func _test_juice(game: Game) -> void:
	_section("Juice")
	var juice := game.juice
	if not _check(juice != null and juice.config != null, "нет узла Juice или theme/juice.tres"):
		return
	var cfg := juice.config
	var content := juice.target()
	if not _check(content != null and content.name == &"Content", "Juice трясёт не Content: %s" % content):
		return
	var was_motion := GameState.reduce_motion
	GameState.set_reduce_motion(false)
	juice.reset()
	var base := content.position

	var before := int(juice.counts.get(&"placed", 0))
	juice.event(&"placed", Vector2(360, 640))
	_check(int(juice.counts.get(&"placed", 0)) == before + 1 and juice.trauma > 0.0, "событие placed не дошло до тряски")
	var peak := 0.0
	var t0 := Time.get_ticks_msec()
	while juice.trauma > 0.0 and Time.get_ticks_msec() - t0 < 1500:
		await get_tree().process_frame
		peak = maxf(peak, (content.position - base).length())
	var lim := cfg.shake_max * cfg.trauma_place * cfg.trauma_place * sqrt(2.0) + 0.01
	_check(juice.trauma == 0.0 and content.position == base, "после тряски Content не на месте: %s (было %s)" % [content.position, base])
	_check(peak > 0.0 and peak <= lim, "тряска поставки: %.2f px (ждали 0 … %.2f)" % [peak, lim])
	juice.add_trauma(0.6)
	juice.add_trauma(0.75)
	juice.add_trauma(0.3)
	_check(is_equal_approx(juice.trauma, 0.75), "удары подряд: травма %.2f (ждали большую — 0,75)" % juice.trauma)
	juice.reset()
	_check(juice.trauma == 0.0 and content.position == base, "reset() не вернул Content на место")

	var probe := Node.new()
	add_child(probe)
	var fx_tw := juice.tween(probe)
	fx_tw.tween_interval(0.6)
	var game_tw := probe.create_tween()
	game_tw.tween_interval(0.6)
	await get_tree().process_frame
	juice.hit_stop(cfg.hitstop_win)
	juice.hit_stop(10.0)
	_check(juice.is_stopped() and not fx_tw.is_running() and game_tw.is_running(),
			"hit-stop: твин эффекта идёт (%s) или твин игры стоит (%s)" % [fx_tw.is_running(), not game_tw.is_running()])
	var t1 := Time.get_ticks_msec()
	while juice.is_stopped() and Time.get_ticks_msec() - t1 < 1000:
		await get_tree().process_frame
	var stop_ms := Time.get_ticks_msec() - t1
	_check(not juice.is_stopped() and fx_tw.is_running(), "hit-stop не снялся или твин эффекта не пошёл дальше")
	_check(stop_ms <= int(cfg.hitstop_max * 1000.0) + 60, "hit-stop подряд длился %d мс (не дольше %d)" % [stop_ms,
			int(cfg.hitstop_max * 1000.0)])
	probe.queue_free()

	var shown := 0
	for i in cfg.pool_size + 4:
		if juice.burst(Juice.SPARKS, Vector2(360, 640)) != null:
			shown += 1
	_check(shown > 0 and juice.pool_size() <= cfg.pool_size and juice.live_particles() <= cfg.particles_max,
			"пул: вспышек %d, узлов %d (предел %d), частиц %d (предел %d)" % [shown, juice.pool_size(), cfg.pool_size,
			juice.live_particles(), cfg.particles_max])
	juice.reset()
	_check(juice.live_particles() == 0, "reset() не погасил частицы")

	GameState.set_reduce_motion(true)
	juice.add_trauma(1.0)
	_check(juice.trauma == 0.0 and content.position == base, "«Меньше движения»: тряска есть")
	var p := juice.burst(Juice.DUST, Vector2(360, 640))
	var want := int(round(cfg.dust_amount * cfg.reduced_particles))
	_check(p != null and p.amount == want, "«Меньше движения»: частиц %d (ждали %d)" % [p.amount if p else -1, want])
	var sc := ConfigFile.new()
	_check(sc.load(GameState.SETTINGS_PATH) == OK and bool(sc.get_value("settings", "reduce_motion", false)),
			"reduce_motion не записан в settings.cfg")
	GameState.reduce_motion = false
	GameState.load_settings()
	_check(GameState.reduce_motion, "reduce_motion не читается из settings.cfg")
	GameState.set_reduce_motion(was_motion)
	juice.reset()
	print("  тряска до %.1f px, hit-stop подряд %d мс, вспышек из пула %d" % [peak, stop_ms, shown])


## Juice основного цикла (14.2): удар — когда блок долетел до места, а не в миг броска (Board.landed, событие
## placed, пыль, сплющивание); отмена хода в полёте — без удара; возврат в лоток — по дуге; твин эффекта блока
## стоит в hit-stop; несомый блок — пружина (отставание ≈ 2 · затухание · v / ω) и наклон не больше tilt_max,
## в покое — ровно на месте и без наклона; поворот — с −90° и смазом края к 0° и чёткому краю; промах «мотает
## головой» и возвращается к 0°; «щелчок» места — призрак и гнездо подпрыгивают; ореол магнита пульсирует;
## «Меньше движения» — без пружины, наклона, «мотания» и пульса.
func _test_juice_moves(game: Game) -> void:
	_section("Juice: блок в руке (14.2)")
	var juice := game.juice
	var cfg := Block.cfg()
	if not _check(cfg != null and cfg == juice.config, "Block.cfg() — не тот же theme/juice.tres, что у Juice"):
		return
	_check(cfg.tilt_max <= 5.001 and cfg.land_time > 0.0 and cfg.land_time <= 0.2
			and cfg.land_squash.x > 1.0 and cfg.land_squash.y < 1.0,
			"juice.tres: наклон %.1f° (не больше 5), долёт %.2f с (не дольше 0,2), сплющивание %s" % [cfg.tilt_max,
			cfg.land_time, str(cfg.land_squash)])
	var was_motion := GameState.reduce_motion
	GameState.set_reduce_motion(false)
	game.start_level(12)
	await get_tree().create_timer(0.6).timeout  # блоки лотка и гнёзда появились
	juice.reset()
	var board := game.board
	var tray := game.tray
	var m := tray.find_move(game.level_data.solution, board)
	if not _check(not m.is_empty(), "уровень 12: в лотке нет блока для хода из решения"):
		GameState.set_reduce_motion(was_motion)
		return
	var slot: int = m.slot
	var r: Rect2i = m.rect
	var b: Block = tray.blocks[slot]
	if r.size != b.cells:
		b.rotate_cells()
	await get_tree().create_timer(cfg.rotate_time + 0.05).timeout

	# Удар — когда блок долетел: Board.landed и событие placed через land_time, сплющивание, пыль.
	_landed_log.clear()
	board.landed.connect(_on_test_landed)
	var before := int(juice.counts.get(&"placed", 0))
	var t0 := Time.get_ticks_msec()
	game.commit_place(b, slot, r)
	_check(_landed_log.is_empty() and int(juice.counts.get(&"placed", 0)) == before,
			"удар (тряска, пыль, звук) — в миг броска, а не когда блок долетел")
	var squash_max := 0.0
	var dust_seen := false
	var wait_ms := int((cfg.land_time + cfg.squash_time) * 1000.0) + 250
	while Time.get_ticks_msec() - t0 < wait_ms:
		await get_tree().process_frame
		squash_max = maxf(squash_max, absf(b.visual.scale.x - 1.0))
		if not _landed_log.is_empty():
			dust_seen = dust_seen or juice.live_particles() > 0
	var land_ms: int = int(_landed_log[0][2]) - t0 if _landed_log.size() > 0 else -1
	var fly_ms := int(cfg.land_time * 1000.0)
	_check(_landed_log.size() == 1 and _landed_log[0][0] == b and _landed_log[0][1] == r,
			"Board.landed: сигналов %d (ждали 1 — для поставленного блока)" % _landed_log.size())
	_check(land_ms >= fly_ms - 20 and land_ms <= fly_ms + 150, "блок долетел за %d мс (ждали ≈ %d)" % [land_ms, fly_ms])
	_check(int(juice.counts.get(&"placed", 0)) == before + 1 and dust_seen, "после удара нет события placed или пыли")
	_check(b.position.is_equal_approx(Vector2(r.position) * Board.CELL) and b.scale.is_equal_approx(Vector2.ONE),
			"блок после долёта не на месте: %s, масштаб %s" % [str(b.position), str(b.scale)])
	_check(squash_max > 0.01 and b.visual.scale.is_equal_approx(Vector2.ONE),
			"сплющивание при ударе: наибольшее %.3f, в конце %s" % [squash_max, str(b.visual.scale)])

	# Отмена хода: блок по дуге (не по прямой) возвращается в свой слот.
	game.undo_last()
	var p_start := b.position
	var path: Array[Vector2] = []
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < int(cfg.return_time * 1000.0) + 150:
		await get_tree().process_frame
		path.append(b.position)
	var p_end := b.position
	var arc := 0.0
	var chord := p_end - p_start
	if chord.length() > 1.0:
		for p in path:
			arc = maxf(arc, absf(chord.cross(p - p_start)) / chord.length())
	_check(tray.blocks[slot] == b and b.get_parent() == tray.slots[slot] and not b.lifted,
			"после отмены хода блок не вернулся в слот %d" % slot)
	_check(chord.length() <= 1.0 or arc >= cfg.return_arc_min * 0.5,
			"возврат в лоток не по дуге: отход от прямой %.1f px (ждали ≥ %.1f)" % [arc, cfg.return_arc_min * 0.5])
	_check(tray._arc_normal(b, Vector2.ZERO, Vector2(200.0, 0.0)).is_equal_approx(Vector2.UP)
			and absf(tray._arc_normal(b, Vector2(0.0, -600.0), Vector2.ZERO).x) > 0.99,
			"дуга возврата: вбок по лотку не вверх или отвесный путь не вбок")

	# Отмена в полёте: удара нет.
	game.commit_place(b, slot, r)
	game.undo_last()
	await get_tree().create_timer(maxf(cfg.land_time, cfg.return_time) + 0.15).timeout
	_check(_landed_log.size() == 1 and int(juice.counts.get(&"placed", 0)) == before + 1,
			"ход отменён в полёте, а удар всё равно случился")
	board.landed.disconnect(_on_test_landed)

	# Твин эффекта блока — через Juice: hit-stop его останавливает.
	b.squash()
	await get_tree().process_frame
	juice.hit_stop(0.05)
	_check(juice.is_stopped() and b._fx_tween != null and not b._fx_tween.is_running(),
			"hit-stop не остановил сплющивание блока (твин эффекта не через Juice)")
	juice.reset()
	await get_tree().create_timer(cfg.squash_time + 0.1).timeout

	# Несомый блок: пружина и наклон. Шаги _move_block по 1/60 с без кадров — настоящая мышь не мешает.
	var drag := game.drag
	var tilt_peak := 0.0
	drag._press_slot = slot
	drag._begin_drag()
	if _check(drag.is_dragging(), "блок не поднялся для проверки пружины"):
		var dt := 1.0 / 60.0
		var speed := 1000.0
		var start := b.global_position
		drag._pos = start
		drag._vel = Vector2.ZERO
		b.tilt = 0.0
		var want := start
		for k in 60:  # 1 с вправо, 1000 px/с
			want = start + Vector2(speed * dt * (k + 1), 0.0)
			drag._move_block(b, want, dt)
			tilt_peak = maxf(tilt_peak, b.tilt)
		var lag := want.x - b.global_position.x
		var lag_want := 2.0 * cfg.carry_damping * speed / cfg.carry_stiffness
		_check(lag > lag_want * 0.6 and lag < lag_want * 1.4,
				"пружина: отставание %.1f px при 1000 px/с (ждали ≈ %.1f)" % [lag, lag_want])
		_check(tilt_peak > 0.0 and tilt_peak <= deg_to_rad(cfg.tilt_max) + 0.0001,
				"наклон в сторону движения: %.2f° (ждали 0 … %.1f°)" % [rad_to_deg(tilt_peak), cfg.tilt_max])
		for _k in 90:  # 1,5 с на месте
			drag._move_block(b, want, dt)
		_check(b.global_position.distance_to(want) < 1.0 and absf(b.tilt) < deg_to_rad(0.2),
				"пружина в покое: до цели %.1f px, наклон %.2f°" % [b.global_position.distance_to(want), rad_to_deg(b.tilt)])
		GameState.set_reduce_motion(true)
		drag._move_block(b, want + Vector2(300.0, 0.0), dt)
		_check(b.global_position.is_equal_approx(want + Vector2(300.0, 0.0)) and b.tilt == 0.0,
				"«Меньше движения»: несомый блок на пружине или с наклоном")
		GameState.set_reduce_motion(false)
		drag.cancel()
		await get_tree().create_timer(maxf(cfg.return_time, cfg.tilt_return) + 0.15).timeout
		_check(not drag.is_busy() and b.get_parent() == tray.slots[slot] and absf(b.tilt) < 0.0001,
				"после отмены перетаскивания блок не в слоте %d или остался наклон" % slot)

	# Поворот: с −90° и со смазом края — к 0° и чёткому краю за rotate_time.
	var rs := -1
	for i in tray.blocks.size():
		var tb: Block = tray.blocks[i]
		if tb != null and tb.cells.x != tb.cells.y:
			rs = i
			break
	if rs >= 0:
		var rb: Block = tray.blocks[rs]
		var mat := rb.shape.material as ShaderMaterial
		tray.rotate_slot(rs)
		_check(absf(rb.visual.rotation + PI * 0.5) < 0.01
				and (cfg.rotate_smear <= 0.0 or float(mat.get_shader_parameter("smear")) > 0.0),
				"поворот начинается не с −90° или без смаза: %.1f°, смаз %.2f" % [rad_to_deg(rb.visual.rotation),
				float(mat.get_shader_parameter("smear"))])
		await get_tree().create_timer(cfg.rotate_time + 0.12).timeout
		_check(absf(rb.visual.rotation) < 0.001 and float(mat.get_shader_parameter("smear")) == 0.0,
				"после поворота: %.2f°, смаз %.2f (ждали 0 и 0)" % [rad_to_deg(rb.visual.rotation),
				float(mat.get_shader_parameter("smear"))])
		tray.rotate_slot(rs)  # обратно
		await get_tree().create_timer(cfg.rotate_time + 0.12).timeout

	# Промах: «мотает головой» не дальше miss_wobble и возвращается к 0°; «Меньше движения» — нет.
	b.refuse()
	var wob := 0.0
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < int(cfg.miss_time * 1000.0) + 150:
		await get_tree().process_frame
		wob = maxf(wob, absf(b.visual.rotation))
	var wob_max := deg_to_rad(cfg.miss_wobble)
	_check(wob > wob_max * 0.3 and wob <= wob_max + 0.01 and absf(b.visual.rotation) < 0.001,
			"промах: качание до %.1f° (ждали до %.1f°), в конце %.2f°" % [rad_to_deg(wob), cfg.miss_wobble,
			rad_to_deg(b.visual.rotation)])
	GameState.set_reduce_motion(true)
	b.refuse()
	await _frames(3)
	_check(absf(b.visual.rotation) < 0.0001, "«Меньше движения»: блок «мотает головой»")
	GameState.set_reduce_motion(false)

	# «Щелчок» места: призрак ×(1 + snap_hop) и обратно, гнездо под ним подпрыгивает; ореол пульсирует.
	var area := r.size.x * r.size.y
	var bpx := 1.0 / board.scale.x
	var ncell: Cell = null
	for c in board.cells_root.get_children():
		var cell := c as Cell
		var cp := Vector2i(roundi(cell.position.x / Board.CELL), roundi(cell.position.y / Board.CELL))
		if r.has_point(cp):
			ncell = cell
	board.emphasize_area(area)
	await get_tree().create_timer(Cell.MAGNET_TIME + 0.1).timeout
	board.show_preview(r, true, area)
	board.snap_preview(r, cfg.snap_hop, cfg.snap_time)
	_check(board.ghost.scale.x > 1.0 + cfg.snap_hop * 0.5, "«щелчок»: призрак не подпрыгнул (×%.3f)" % board.ghost.scale.x)
	_check(ncell != null and ncell.is_hopping(), "«щелчок»: гнездо числа под призраком не подпрыгнуло")
	var pulse_max := 0.0
	var t3 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t3 < 450:
		await get_tree().process_frame
		if ncell != null:
			pulse_max = maxf(pulse_max, ncell.pulse())
	_check(board.ghost.scale.is_equal_approx(Vector2.ONE) and (ncell == null or not ncell.is_hopping()),
			"после «щелчка» призрак ×%.3f или гнездо ещё прыгает" % board.ghost.scale.x)
	_check(_magnet_problem(board, area, bpx).is_empty(), "после «щелчка» магнит: " + _magnet_problem(board, area, bpx))
	_check(cfg.pulse_freq <= 0.0 or pulse_max > 0.3, "ореол магнита не пульсирует: пульс до %.2f" % pulse_max)
	board.clear_preview()
	board.clear_emphasis()
	await get_tree().create_timer(Cell.MAGNET_TIME + 0.1).timeout
	_check(ncell == null or ncell.pulse() == 0.0, "пульс ореола не погас со снятием магнита")
	GameState.set_reduce_motion(true)
	board.emphasize_area(area)
	await get_tree().create_timer(0.35).timeout
	_check(ncell == null or ncell.pulse() == 0.0, "«Меньше движения»: ореол магнита пульсирует")
	board.clear_emphasis()
	await get_tree().create_timer(Cell.MAGNET_TIME + 0.1).timeout
	GameState.set_reduce_motion(was_motion)
	juice.reset()
	print("  удар через %d мс, сплющивание %.3f, дуга %.0f px, наклон до %.1f°, качание до %.1f°, пульс до %.2f" % [
			land_ms, squash_max, arc, rad_to_deg(tilt_peak), rad_to_deg(wob), pulse_max])


## Закрытое число (14.3): в миг удара (не броска) цифра вспыхивает — больше и светлее, — сменяется галочкой
## (Visual/Check, check.gdshader, на месте цифры), галочка уходит, цифра остаётся как была; по клеткам проходит
## свет; hit-stop останавливает закрытие; отмена хода посреди закрытия гасит галочку и свет; «Меньше движения» —
## галочка есть, волны света нет.
func _test_juice_close(game: Game) -> void:
	_section("Juice: закрытое число (14.3)")
	var juice := game.juice
	var cfg := Block.cfg()
	_check(cfg.close_pop > 1.0 and cfg.close_flash >= 1.0 and cfg.close_hold > 0.0 and cfg.close_swap > 0.0
			and cfg.glow_strength >= 0.0 and cfg.glow_strength <= 1.0,
			"juice.tres, «Закрытое число»: вспышка ×%.2f, яркость ×%.2f, галочка %.2f с, смена %.2f с, свет %.2f" % [
			cfg.close_pop, cfg.close_flash, cfg.close_hold, cfg.close_swap, cfg.glow_strength])
	var was_motion := GameState.reduce_motion
	GameState.set_reduce_motion(false)
	game.start_level(12)
	await get_tree().create_timer(0.6).timeout
	juice.reset()
	var board := game.board
	var tray := game.tray
	var m := tray.find_move(game.level_data.solution, board)
	if not _check(not m.is_empty(), "уровень 12: в лотке нет блока для хода из решения"):
		GameState.set_reduce_motion(was_motion)
		return
	var slot: int = m.slot
	var r: Rect2i = m.rect
	var b: Block = tray.blocks[slot]
	if r.size != b.cells:
		b.rotate_cells()
		await get_tree().create_timer(cfg.rotate_time + 0.05).timeout
	var total := cfg.close_pop_time + cfg.close_swap * 2.0 + maxf(cfg.close_hold - cfg.close_swap, 0.0) \
			+ cfg.close_swap * 2.5
	game.commit_place(b, slot, r)
	_check(not b.is_closing() and b.check_alpha() == 0.0 and b.glow() == 0.0,
			"число закрылось в миг броска, а не когда блок долетел")
	var pop_max := 0.0
	var bright_max := 0.0
	var check_max := 0.0
	var glow_max := 0.0
	var digit_min := 1.0
	var closing := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int((cfg.land_time + total) * 1000.0) + 300:
		await get_tree().process_frame
		closing = closing or b.is_closing()
		pop_max = maxf(pop_max, b.number_label.scale.x)
		bright_max = maxf(bright_max, b.number_label.modulate.r)
		check_max = maxf(check_max, b.check_alpha())
		glow_max = maxf(glow_max, b.glow())
		digit_min = minf(digit_min, b.number_label.modulate.a)
	_check(closing and pop_max >= 1.0 + (cfg.close_pop - 1.0) * 0.5 and (cfg.close_flash <= 1.0 or bright_max > 1.05),
			"цифра не вспыхнула: масштаб до ×%.2f (ждали ≈ ×%.2f), яркость до ×%.2f" % [pop_max, cfg.close_pop,
			bright_max])
	_check(check_max > 0.95 and digit_min < 0.05,
			"цифра не сменилась галочкой: галочка видна до %.2f, цифра не прозрачнее %.2f" % [check_max, digit_min])
	_check(cfg.glow_strength <= 0.0 or glow_max > cfg.glow_strength * 0.5,
			"по клеткам блока не прошёл свет: сила до %.2f (в juice.tres %.2f)" % [glow_max, cfg.glow_strength])
	_check(not b.is_closing() and b.check_alpha() == 0.0 and b.glow() == 0.0
			and b.number_label.modulate.is_equal_approx(Color.WHITE) and b.number_label.scale.is_equal_approx(Vector2.ONE)
			and b.number_label.text == str(b.area),
			"после закрытия цифра не как была: «%s», ×%.2f, %s; галочка %.2f, свет %.2f" % [b.number_label.text,
			b.number_label.scale.x, str(b.number_label.modulate), b.check_alpha(), b.glow()])
	var chk := b.visual.get_node_or_null("Check") as ColorRect
	var chk_mat: ShaderMaterial = null
	if chk != null:
		chk_mat = chk.material as ShaderMaterial
	_check(chk_mat != null and chk_mat.shader == Block.CHECK_SHADER and chk.position == b.number_label.position
			and chk.size == b.number_label.size and chk.get_index() > b.number_label.get_index(),
			"галочка — не узел Visual/Check с check.gdshader поверх цифры и на её месте")
	var sm := b.shape.material as ShaderMaterial
	_check(float(sm.get_shader_parameter("glow")) == 0.0, "после закрытия в шейдере блока остался свет")

	# hit-stop останавливает и закрытие (твины — через Juice).
	b.close_number()
	await get_tree().process_frame
	juice.hit_stop(0.05)
	_check(juice.is_stopped() and b._close_tween != null and not b._close_tween.is_running()
			and (b._glow_tween == null or not b._glow_tween.is_running()),
			"hit-stop не остановил закрытие числа (твины не через Juice)")
	juice.reset()
	await get_tree().create_timer(total + 0.1).timeout
	_check(not b.is_closing() and b.check_alpha() == 0.0, "после hit-stop закрытие числа не закончилось")

	# Отмена хода посреди закрытия: галочка и свет гаснут сразу, цифра — по центру блока, как была.
	b.close_number()
	await get_tree().create_timer(cfg.close_pop_time + cfg.close_swap + 0.03).timeout
	var mid_check := b.check_alpha()
	game.undo_last()
	_check(mid_check > 0.5 and not b.is_closing() and b.check_alpha() == 0.0 and b.glow() == 0.0
			and b.number_label.modulate.is_equal_approx(Color.WHITE) and b.number_label.scale.is_equal_approx(Vector2.ONE)
			and b.number_cell == Vector2i(-1, -1) and b.number_label.size == b.size,
			"отмена хода посреди закрытия: галочка %.2f (была %.2f), свет %.2f, цифра ×%.2f %s" % [b.check_alpha(),
			mid_check, b.glow(), b.number_label.scale.x, str(b.number_label.modulate)])
	await get_tree().create_timer(cfg.return_time + 0.15).timeout

	# «Меньше движения»: галочка есть, волны света нет.
	GameState.set_reduce_motion(true)
	game.commit_place(b, slot, r)
	var glow_rm := 0.0
	var check_rm := 0.0
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < int((cfg.land_time + total) * 1000.0) + 300:
		await get_tree().process_frame
		glow_rm = maxf(glow_rm, b.glow())
		check_rm = maxf(check_rm, b.check_alpha())
	_check(check_rm > 0.95 and glow_rm == 0.0,
			"«Меньше движения»: галочка видна до %.2f (ждали 1), свет до %.2f (ждали 0)" % [check_rm, glow_rm])
	GameState.set_reduce_motion(was_motion)
	juice.reset()
	print("  цифра до ×%.2f и ×%.2f ярче, галочка до %.2f, свет до %.2f" % [pop_max, bright_max, check_max, glow_max])


## Juice: комбо и линии (14.4). Числа juice.tres и формулы (сила хода, высота звука); серия: ход без линии её
## обрывает, отмена хода возвращает прежнюю, отмена в полёте — без волны и текста; в миг броска — ни волны, ни
## текста, в миг удара — волна по каждой закрытой линии (из клеток блока к концам, сила по силе хода), блоки линии
## вспыхивают, Juice.lines (сила, событие line, тряска), звук линии выше по силе, текст комбо «штампом» (слово по
## силе, размер, влёт крупным, дожим, к 1); hit-stop останавливает волну и штамп; «Меньше движения» — волна и
## вспышка не сильнее reduced_wave, текст без штампа, без тряски.
func _test_juice_combo(game: Game) -> void:
	_section("Juice: комбо и линии (14.4)")
	var juice := game.juice
	var cfg := Block.cfg()
	var semis := cfg.combo_semitones
	var rising := semis.size() >= cfg.combo_max + 1 and semis.size() > 0 and semis[0] == 0
	for k in range(1, semis.size()):
		rising = rising and semis[k] > semis[k - 1]
	_check(cfg.combo_max >= 2 and rising and cfg.line_wave_time > 0.0 and cfg.line_wave_time <= 0.5
			and cfg.line_wave_strength > 0.0 and cfg.line_wave_strength <= 1.0
			and cfg.reduced_wave <= cfg.line_wave_strength and cfg.combo_slam > 1.0 and cfg.combo_slam_time > 0.0
			and cfg.combo_slam_time <= 0.3 and cfg.combo_text_size > 0,
			"juice.tres, «Линия и серия»: сила до %d, полутоны %s, волна %.2f с и сила %.2f («Меньше движения» %.2f), штамп ×%.2f за %.2f с" % [
			cfg.combo_max, str(semis), cfg.line_wave_time, cfg.line_wave_strength, cfg.reduced_wave, cfg.combo_slam,
			cfg.combo_slam_time])
	_check(cfg.combo_power(0, 3) == -1 and cfg.combo_power(1, 0) == 0 and cfg.combo_power(1, 1) == 0
			and cfg.combo_power(2, 1) == 1 and cfg.combo_power(1, 3) == 2 and cfg.combo_power(2, 2) == 2
			and cfg.combo_power(6, 9) == cfg.combo_max,
			"сила хода — не (линий − 1) + (серия − 1) в пределах 0…%d" % cfg.combo_max)
	var pitch_ok := is_equal_approx(cfg.combo_pitch(-1), 1.0) and is_equal_approx(cfg.combo_pitch(0), 1.0)
	for p in range(1, cfg.combo_max + 1):
		pitch_ok = pitch_ok and cfg.combo_pitch(p) > cfg.combo_pitch(p - 1) and is_equal_approx(cfg.combo_pitch(p),
				pow(2.0, float(semis[mini(p, semis.size() - 1)]) / 12.0))
	_check(pitch_ok and is_equal_approx(cfg.combo_pitch(cfg.combo_max + 5), cfg.combo_pitch(semis.size() - 1)),
			"звук линии не выше с каждой единицей силы (2^(полутоны / 12))")

	var was_motion := GameState.reduce_motion
	GameState.set_reduce_motion(false)
	var mv: Dictionary = {}
	for lvl in [12, 20, 30, 49]:
		game.start_level(lvl)
		await get_tree().create_timer(0.6).timeout
		juice.reset()
		mv = await _find_line_move(game)
		if not mv.is_empty():
			break
	if not _check(not mv.is_empty(), "уровни 12, 20, 30, 49: не нашлось хода, закрывающего линию"):
		GameState.set_reduce_motion(was_motion)
		return
	var n: int = mv.lines

	# Отмена в полёте: удара нет — нет ни волны, ни текста, ни события line; серия — как до хода.
	var slot: int = mv.slot
	var r: Rect2i = mv.rect
	var b: Block = game.tray.blocks[slot]
	if r.size != b.cells:
		b.rotate_cells()
		await get_tree().create_timer(cfg.rotate_time + 0.05).timeout
	var waves0 := _line_flashes(game.board).size()
	var texts0 := _slam_texts(game.fx_layer).size()
	var events0 := int(juice.counts.get(&"line", 0))
	game.line_streak = 1
	game.commit_place(b, slot, r)
	var streak_in := game.line_streak
	game.undo_last()
	await get_tree().create_timer(cfg.land_time + 0.15).timeout
	_check(streak_in == 2 and game.line_streak == 1 and _line_flashes(game.board).size() == waves0
			and _slam_texts(game.fx_layer).size() == texts0 and int(juice.counts.get(&"line", 0)) == events0,
			"отмена хода с линией в полёте: серия %d → %d (ждали 2 → 1), волн +%d, текстов +%d, событий line +%d" % [
			streak_in, game.line_streak, _line_flashes(game.board).size() - waves0,
			_slam_texts(game.fx_layer).size() - texts0, int(juice.counts.get(&"line", 0)) - events0])
	await get_tree().create_timer(cfg.return_time + 0.1).timeout

	# Ход с линией вторым в серии: сила (линий − 1) + 1; всё — в миг удара.
	var power := cfg.combo_power(n, 2)
	var res: Dictionary = await _play_line_move(game, mv, 1)
	var rec: Dictionary = res.move
	_check(int(res.streak) == 2 and int(rec.streak_before) == 1 and int(rec.power) == power and int(rec.lines) == n,
			"ход с линией: серия %d → %d, сила %d, линий %d (ждали 1 → 2, сила %d, линий %d)" % [int(rec.streak_before),
			int(res.streak), int(rec.power), int(rec.lines), power, n])
	_check(int(res.at_commit) == 0, "волна, текст комбо или событие line — в миг броска, а не когда блок долетел")
	var peak := clampf(cfg.line_wave_strength + cfg.combo_wave * power, 0.0, 1.0)
	_check(int(res.waves) == n and bool(res.waves_on_lines) and bool(res.from_block),
			"волн %d на %d линий (на своих местах: %s; из клеток блока: %s)" % [int(res.waves), n,
			str(res.waves_on_lines), str(res.from_block)])
	_check(bool(res.reached) and absf(float(res.peak) - peak) < 0.001 and float(res.strength) >= peak * 0.9,
			"волна: дошла до концов линии — %s, сила до %.2f из %.2f (ждали %.2f = %.2f + %.2f · %d)" % [
			str(res.reached), float(res.strength), float(res.peak), peak, cfg.line_wave_strength, cfg.combo_wave, power])
	var amount := cfg.line_block_flash + cfg.combo_flash * power
	_check(float(res.block_flash) > amount * 0.6 and float(res.block_flash) <= amount + 0.001,
			"блоки линии вспыхнули до %.2f (ждали ≈ %.2f)" % [float(res.block_flash), amount])
	var trauma := minf(cfg.trauma_line + cfg.combo_trauma * power, 1.0)
	_check(juice.last_power == power and int(res.events) == 1 and float(res.trauma) >= trauma - 0.15,
			"Juice.lines: сила %d (ждали %d), событий line %d (ждали 1), тряска до %.2f (ждали ≈ %.2f)" % [
			juice.last_power, power, int(res.events), float(res.trauma), trauma])
	if GameState.sfx_on:
		_check(is_equal_approx(float(res.pitch), cfg.combo_pitch(power)),
				"звук линии: высота %.3f (ждали %.3f — сила %d)" % [float(res.pitch), cfg.combo_pitch(power), power])
	var word := tr(Game.COMBO_WORDS[mini(power, Game.COMBO_WORDS.size() - 1)])
	var slam := cfg.combo_slam + cfg.combo_slam_grow * power
	_check(String(res.text) == word and int(res.text_size) == cfg.combo_text_size + cfg.combo_text_grow * power,
			"текст комбо «%s» %d px (ждали «%s» %d px)" % [String(res.text), int(res.text_size), word,
			cfg.combo_text_size + cfg.combo_text_grow * power])
	_check(float(res.scale_max) >= 1.0 + (slam - 1.0) * 0.8 and float(res.scale_min) <= FloatingText.SLAM_UNDER + 0.05
			and is_equal_approx(float(res.scale_end), 1.0),
			"штамп текста: ×%.2f → ×%.2f → ×%.2f (ждали ×%.2f → ×%.2f → ×1)" % [float(res.scale_max),
			float(res.scale_min), float(res.scale_end), slam, FloatingText.SLAM_UNDER])
	game.undo_last()
	_check(game.line_streak == 1, "отмена хода с линией не вернула серию: %d (ждали 1)" % game.line_streak)
	await get_tree().create_timer(cfg.return_time + 0.1).timeout
	print("  линий за ход %d, сила %d: волна до %.2f, блоки до %.2f, «%s» %d px, штамп ×%.2f → ×%.2f" % [n, power,
			float(res.strength), float(res.block_flash), String(res.text), int(res.text_size), float(res.scale_max),
			float(res.scale_min)])

	# Волна из середины линии (без блока) по столбцу; hit-stop останавливает волну и штамп текста.
	var board := game.board
	var col := Rect2i(0, 0, 1, board.rows)
	var fx := board.flash_line(col, 0.0)
	var ft := Fx.combo_text(game.fx_layer, "x", board.cell_center_global(col), Color.WHITE, 0)
	_check(absf(fx.arrival(fx.size * 0.5)) < 0.001 and absf(fx.arrival(Vector2(fx.size.x * 0.5, fx.size.y))
			- cfg.line_wave_time) < 0.001 and absf(fx.peak - cfg.line_wave_strength) < 0.001,
			"волна без блока: не из середины линии к концам за line_wave_time или сила не %.2f" % cfg.line_wave_strength)
	await get_tree().process_frame
	juice.hit_stop(0.05)
	_check(juice.is_stopped() and not fx.wave_tween().is_running() and ft.slam_tween != null
			and not ft.slam_tween.is_running(), "hit-stop не остановил волну линии или штамп текста (твины не через Juice)")
	juice.reset()
	await get_tree().create_timer(cfg.line_wave_time + cfg.line_fade + 0.1).timeout
	_check(not is_instance_valid(fx), "волна линии не удалилась, доиграв")

	# «Меньше движения»: при наибольшей силе волна и вспышка — не сильнее reduced_wave, текст без штампа, без тряски.
	GameState.set_reduce_motion(true)
	var res_rm: Dictionary = await _play_line_move(game, mv, cfg.combo_max)
	_check(float(res_rm.peak) <= cfg.reduced_wave + 0.001 and float(res_rm.strength) > 0.0
			and float(res_rm.block_flash) <= cfg.reduced_wave + 0.001 and float(res_rm.block_flash) > 0.0,
			"«Меньше движения»: волна до %.2f, блоки до %.2f (ждали не больше %.2f и не 0)" % [float(res_rm.strength),
			float(res_rm.block_flash), cfg.reduced_wave])
	_check(is_equal_approx(float(res_rm.scale_max), 1.0) and float(res_rm.trauma) == 0.0
			and String(res_rm.text) == tr(Game.COMBO_WORDS[Game.COMBO_WORDS.size() - 1]),
			"«Меньше движения»: текст «%s» влетел с ×%.2f (ждали без штампа, ×1), тряска %.2f (ждали 0)" % [
			String(res_rm.text), float(res_rm.scale_max), float(res_rm.trauma)])
	game.undo_last()
	await get_tree().create_timer(cfg.return_time + 0.1).timeout
	GameState.set_reduce_motion(was_motion)
	game.line_streak = 0
	juice.reset()


## Победа (14.5, PLAN 4.4; числа — группа «Победа» в JuiceConfig): удар — в миг касания последнего блока, а не броска:
## событие win, hit-stop (волна ждёт его конца), волна по полю (WinWave) от последнего блока до дальнего угла, через
## Juice; волн и текста линии на последнем ходу нет; блоки вспыхивают, подпрыгивают (кроме последнего) и сходятся в
## мозаику в порядке прихода фронта — к окну победы всё доиграло. Окно: заработанные звёзды — «штампом» по одной
## (удар — нота до-ми-соль, искры, карточка вздрагивает), незаработанная — тихо. «Меньше движения»: волна и вспышка
## не сильнее reduced_wave, без подскока и тряски, звёзды без штампа (нота и искры остаются), карточка не вздрагивает.
func _test_juice_win(game: Game) -> void:
	_section("Juice: победа (14.5)")
	var cfg := Block.cfg()
	var semis := cfg.star_semitones
	var pitch_ok := semis.size() >= 3 and semis[0] == 0
	for k in range(1, semis.size()):
		pitch_ok = pitch_ok and semis[k] > semis[k - 1]
	for i in mini(semis.size(), 3):
		pitch_ok = pitch_ok and is_equal_approx(cfg.star_pitch(i), pow(2.0, float(semis[i]) / 12.0))
	_check(pitch_ok and is_equal_approx(cfg.star_pitch(-1), 1.0),
			"ноты звёзд: полутоны %s — не 0 и выше с каждой звездой, или star_pitch — не 2^(полутоны / 12)" % str(semis))
	var settle := cfg.land_time + cfg.hitstop_win + cfg.win_wave_time
	if cfg.win_mosaic:  # мозаика с 14.8e убрана (win_mosaic = false)
		settle += cfg.win_merge_delay + cfg.win_merge_time
	_check(cfg.hitstop_win >= 0.06 and cfg.hitstop_win <= 0.08 and cfg.win_wave_time > 0.0
			and cfg.win_wave_strength > 0.0 and cfg.win_wave_strength <= 1.0 and cfg.reduced_wave <= cfg.win_wave_strength
			and cfg.win_merge_gap < 0.045 and cfg.win_merge_radius < 0.24 and settle <= Game.WIN_SHOW_AT,
			"juice.tres, «Победа»: hit-stop %.0f мс (PLAN: 60–80), волна %.2f с, сила %.2f, мозаика: зазор %.3f, скругление %.2f; волна и мозаика доигрывают через %.2f с, окно — через %.2f" % [
			cfg.hitstop_win * 1000.0, cfg.win_wave_time, cfg.win_wave_strength, cfg.win_merge_gap, cfg.win_merge_radius,
			settle, Game.WIN_SHOW_AT])
	var stars_end := WinPanel.STARS_AT + WinPanel.STAR_STEP * 2.0 + cfg.star_slam_time + cfg.star_settle_time
	_check(cfg.star_slam > 1.0 and cfg.star_slam_squash < 1.0 and cfg.star_slam_time > 0.0
			and cfg.star_slam_time < WinPanel.STAR_STEP and WinPanel.PUNCH_TIME <= WinPanel.STAR_STEP
			and stars_end <= WinPanel.BUTTONS_DELAY,
			"juice.tres, звёзды окна: ×%.2f → ×%.2f за %.2f с, толчок %.2f с (шаг %.2f), третья встаёт через %.2f с, кнопки — через %.2f" % [
			cfg.star_slam, cfg.star_slam_squash, cfg.star_slam_time, WinPanel.PUNCH_TIME, WinPanel.STAR_STEP, stars_end,
			WinPanel.BUTTONS_DELAY])

	var was_motion := GameState.reduce_motion
	GameState.set_reduce_motion(false)
	var res: Dictionary = await _play_win(game, 12, 1)
	if not res.is_empty():
		_check_win_run(res, false)
	GameState.set_reduce_motion(true)
	var res_rm: Dictionary = await _play_win(game, 20, 0)
	if not res_rm.is_empty():
		_check_win_run(res_rm, true)
	GameState.set_reduce_motion(was_motion)
	game.juice.reset()
	if not res.is_empty():
		var mosaic: String = "мозаика %.2f…%.2f с" % [float(res.merge_first), float(res.merge_last)] if cfg.win_mosaic \
				else "мозаики нет"
		print("  победа: волна до %.2f, блоков %d (%s), звёздочек удара %d, звёзд %d — удары %s, штамп ×%.2f, толчок %.1f px" % [
				float(res.strength), int(res.blocks), mosaic, cfg.stars_amount, int(res.stars),
				str(res.hits), float(res.star_max), float(res.punch)])


## Появление и переходы (14.6): числа «Появление и переходы» в JuiceConfig — в разумных пределах. Появление уровня:
## числа выпрыгивают по диагонали после своих ячеек, блоки выезжают по одному со стороны Tray.slide_dir, всё
## доигрывает ровно на место; ввод не ждёт (взятый на лету блок сразу в руке, ход на лету засчитан, новый блок
## тоже выезжает). Шторка (Transition.cover) ловит нажатия, закрывает экран до конца, зовёт действие один раз и
## уходит. Отскок кнопки — до ×button_release_peak и ровно в ×1. Дыхание лотка в простое — ±idle_breath со сдвигом
## фаз, вокруг середины гнезда, гаснет от касания, стоит, пока блок держат, на паузе, в тупике и в окне.
## «Меньше движения»: без прыжков, выезда, отскока и дыхания, шторка — ровное затемнение.
func _test_juice_intro(game: Game) -> void:
	_section("Juice: появление, переходы, кнопки, простой (14.6)")
	var cfg := Block.cfg()
	var intro_end := _intro_end()
	_check(cfg.intro_cell_step > 0.0 and cfg.intro_number_time > 0.0 and cfg.intro_number_from < 1.0
			and cfg.intro_number_rise > 0.0 and cfg.intro_block_from > 0.0 and cfg.intro_block_time > 0.0
			and cfg.intro_block_step > 0.0 and intro_end <= 1.0,
			"juice.tres, «Появление»: шаг ячеек %.3f с, число за %.2f с с ×%.2f, блок за %.2f с, шаг %.2f с; уровень появляется за %.2f с (ждали ≤ 1)" % [
			cfg.intro_cell_step, cfg.intro_number_time, cfg.intro_number_from, cfg.intro_block_time,
			cfg.intro_block_step, intro_end])
	_check(cfg.curtain_close > 0.0 and cfg.curtain_open > 0.0 and cfg.curtain_close + cfg.curtain_open <= 0.8
			and cfg.curtain_spread > 0.0 and cfg.curtain_spread < 1.0 and cfg.curtain_cell > 0.0
			and cfg.curtain_radius >= 0.0 and cfg.curtain_radius <= 0.5,
			"juice.tres, шторка: %.2f + %.2f с (ждали ≤ 0,8), волна %.2f, клетка %.2f экрана, скругление %.2f" % [
			cfg.curtain_close, cfg.curtain_open, cfg.curtain_spread, cfg.curtain_cell, cfg.curtain_radius])
	_check(cfg.button_release_peak > 1.0 and cfg.button_release_peak <= 1.08 and cfg.button_release_time > 0.0
			and cfg.button_release_time <= 0.2,
			"juice.tres, отскок кнопки: ×%.2f за %.2f с (ждали ×1…1,08 за ≤ 0,2 с)" % [cfg.button_release_peak,
			cfg.button_release_time])
	_check(cfg.idle_after >= 2.0 and cfg.idle_breath > 0.0 and cfg.idle_breath <= 0.03 and cfg.idle_period >= 1.0
			and cfg.idle_phase > 0.0 and cfg.idle_rise > 0.0 and cfg.idle_fade > 0.0 and cfg.idle_fade <= 0.3,
			"juice.tres, простой: через %.1f с, ±%.3f, период %.1f с, сдвиг %.2f с, нарастает %.2f с, гаснет %.2f с" % [
			cfg.idle_after, cfg.idle_breath, cfg.idle_period, cfg.idle_phase, cfg.idle_rise, cfg.idle_fade])
	_check(Tray.is_activity(_mouse_press(true)) and not Tray.is_activity(_mouse_press(false))
			and not Tray.is_activity(InputEventMouseMotion.new()) and Tray.is_activity(_mouse_drag())
			and Tray.is_activity(_key_press(false)) and not Tray.is_activity(_key_press(true)),
			"Tray.is_activity: простой гасят нажатие и ведение с кнопкой, а не отпускание, ход курсора и автоповтор")

	var was_motion := GameState.reduce_motion
	GameState.set_reduce_motion(false)
	await _intro_run(game, false)
	await _breath_run(game)
	await _intro_on_the_fly(game)
	await _curtain_run(false)
	await _release_run(game, false)
	GameState.set_reduce_motion(true)
	await _intro_run(game, true)
	await _breath_reduced(game)
	await _curtain_run(true)
	await _release_run(game, true)
	GameState.set_reduce_motion(was_motion)
	game.juice.reset()


## Когда появление уровня доигрывает, с: последний из трёх блоков выехал, число на дальней ячейке (поле до 5×5)
## выпрыгнуло.
func _intro_end() -> float:
	var cfg := Block.cfg()
	return maxf(cfg.intro_block_start + cfg.intro_block_step * 2.0 + cfg.intro_block_time,
			cfg.intro_cell_step * 8.0 + cfg.intro_number_delay + cfg.intro_number_time)


func _mouse_press(pressed: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = Vector2(-100.0, -100.0)  # мимо всего: Game._input → DragController без нажатого слота
	return ev


func _mouse_drag() -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	return ev


func _key_press(echo: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F13
	ev.pressed = true
	ev.echo = echo
	return ev


## Появление уровня 12 (rm — «Меньше движения»): замеры каждый кадр, пока всё не доиграет.
func _intro_run(game: Game, rm: bool) -> void:
	var cfg := Block.cfg()
	var tag := "появление" + (" («Меньше движения»)" if rm else "")
	var tray := game.tray
	var board := game.board
	game.start_level(12)
	var t0 := Time.get_ticks_msec()
	var dir := tray.slide_dir()
	var blocks: Array[Block] = []
	for b in tray.blocks:
		if b != null:
			blocks.append(b as Block)
	var cells: Array[Cell] = []
	for node in board.cells_root.get_children():
		cells.append(node as Cell)
	if not _check(blocks.size() >= 2 and cells.size() >= 3, "%s: в лотке %d блоков, чисел %d" % [tag, blocks.size(), cells.size()]):
		return
	var block_start: Array[float] = []
	block_start.resize(blocks.size())
	block_start.fill(-1.0)
	var cell_start: Array[float] = []
	cell_start.resize(cells.size())
	cell_start.fill(-1.0)
	var max_slide := 0.0
	var max_rise := 0.0
	var min_from := 1.0
	var dir_bad := ""
	var t := 0.0
	var frames := 0
	while true:
		await get_tree().process_frame
		frames += 1
		t = (Time.get_ticks_msec() - t0) / 1000.0
		var busy := false
		for k in blocks.size():
			var b := blocks[k]
			busy = busy or b.is_sliding()
			if block_start[k] < 0.0 and b.visual.modulate.a > 0.0:
				block_start[k] = t
			max_slide = maxf(max_slide, absf(b.slide_offset()))
			var vp := b.visual.position
			if vp.length() > 0.5 and absf(vp.normalized().dot(dir)) < 0.999:
				dir_bad = str(vp)
		for k in cells.size():
			var cell := cells[k]
			busy = busy or cell.is_appearing()
			if cell_start[k] < 0.0 and cell.modulate.a > 0.0:
				cell_start[k] = t
			max_rise = maxf(max_rise, cell.rise())
			min_from = minf(min_from, cell.scale.x)
		if (not busy and frames > 2) or t > _intro_end() + 1.0:
			break
	_check(t <= _intro_end() + 0.25, "%s: доигрывает за %.2f с (ждали ≈ %.2f)" % [tag, t, _intro_end()])
	if rm:
		_check(is_zero_approx(max_slide) and is_zero_approx(max_rise) and is_equal_approx(min_from, 1.0),
				"%s: блоки ехали (%.0f px) или числа прыгали (подъём %.1f px, ×%.2f)" % [tag, max_slide, max_rise, min_from])
	else:
		_check(max_slide >= cfg.intro_block_from * 0.95 and dir_bad.is_empty(),
				"%s: блоки выезжали на %.0f px из %.0f, не со стороны %s (сдвиг %s)" % [tag, max_slide, cfg.intro_block_from,
				str(dir), dir_bad])
		_check(max_rise >= cfg.intro_number_rise * 0.95 and min_from <= cfg.intro_number_from + 0.02,
				"%s: числа поднимались на %.1f px из %.1f, с ×%.2f (ждали ×%.2f)" % [tag, max_rise, cfg.intro_number_rise,
				min_from, cfg.intro_number_from])
	# По одному: слот i — через intro_block_start + intro_block_step · i.
	var order_ok := block_start[0] >= cfg.intro_block_start - 0.03
	for k in range(1, blocks.size()):
		order_ok = order_ok and block_start[k] > block_start[k - 1]
	_check(order_ok, "%s: блоки тронулись в %s с (ждали по одному с %.2f с)" % [tag, str(block_start), cfg.intro_block_start])
	# Числа — после своих ячеек, по диагонали (две диагонали разницы — уже позже, с запасом на кадр).
	var diag_bad := ""
	for a in cells.size():
		if cell_start[a] < cfg.intro_number_delay - 0.03:
			diag_bad = "число %d проявилось в %.2f с — раньше своей ячейки" % [cells[a].value, cell_start[a]]
		for b in cells.size():
			if _cell_diag(cells[a]) + 2 <= _cell_diag(cells[b]) and cell_start[a] > cell_start[b] + 0.02:
				diag_bad = "число %d (диагональ %d) проявилось позже числа %d (диагональ %d)" % [cells[a].value,
						_cell_diag(cells[a]), cells[b].value, _cell_diag(cells[b])]
	_check(diag_bad.is_empty(), "%s: %s" % [tag, diag_bad])
	# Доиграло ровно: блоки на месте в гнёздах, числа на своих клетках.
	var rest_bad := ""
	for k in blocks.size():
		var b := blocks[k]
		var slot := tray.blocks.find(b)
		if b.is_sliding() or not is_zero_approx(b.slide_offset()) or not b.visual.position.is_zero_approx() \
				or not is_equal_approx(b.visual.modulate.a, 1.0) or slot < 0 or b.get_parent() != tray.slots[slot]:
			rest_bad += " блок %d: сдвиг %s, видим %.2f;" % [k, str(b.visual.position), b.visual.modulate.a]
	for cell in cells:
		if cell.is_appearing() or not is_zero_approx(cell.rise()) or not cell.scale.is_equal_approx(Vector2.ONE) \
				or not is_equal_approx(cell.modulate.a, 1.0) or not cell.position.is_equal_approx(cell._home) \
				or not (cell.position / Board.CELL).is_equal_approx((cell.position / Board.CELL).round()):
			rest_bad += " число %d: место %s, ×%.2f, видно %.2f;" % [cell.value, str(cell.position), cell.scale.x,
					cell.modulate.a]
	_check(rest_bad.is_empty(), "%s: не доиграло до места:%s" % [tag, rest_bad])
	# Рамка поля: ячейки вырастают волной и доигрывают (униформа appear — «всё выросло»).
	var mat := board.frame.material as ShaderMaterial
	if mat != null:
		var frame_end := cfg.intro_cell_step * float(board.cols + board.rows) + 0.4
		if t < frame_end + 0.05:
			await get_tree().create_timer(frame_end + 0.05 - t).timeout
		_check(is_equal_approx(float(mat.get_shader_parameter("appear_step")), cfg.intro_cell_step)
				and float(mat.get_shader_parameter("appear")) >= 99.0,
				"%s: волна ячеек не доиграла (appear %.2f, шаг %.3f)" % [tag, float(mat.get_shader_parameter("appear")),
				float(mat.get_shader_parameter("appear_step"))])
	print("  %s: блоков %d, чисел %d, доиграло за %.2f с; выезд %.0f px, подъём чисел %.1f px" % [tag, blocks.size(),
			cells.size(), t, max_slide, max_rise])


## Номер диагонали клетки числа (x + y) — по её месту на поле.
func _cell_diag(cell: Cell) -> int:
	var p := (cell._home / Board.CELL).round()
	return int(p.x + p.y)


## Ввод не ждёт появления: взятый на лету блок сразу в руке (выезд погашен); ход, пока всё появляется,
## засчитан, новый блок в освободившемся гнезде тоже выезжает.
func _intro_on_the_fly(game: Game) -> void:
	var cfg := Block.cfg()
	var tray := game.tray
	game.start_level(12)
	await _frames(1)
	var slot := -1
	for i in tray.blocks.size():
		if tray.blocks[i] != null and slot < 0:
			slot = i
	if not _check(slot >= 0, "появление на лету: лоток пуст"):
		return
	var b: Block = tray.blocks[slot]
	_check(b.is_sliding(), "появление на лету: блок гнезда %d не выезжает" % slot)
	game.drag._press_slot = slot
	game.drag._begin_drag()
	_check(game.drag.is_dragging() and b.get_parent() == game.drag_layer and not b.is_sliding()
			and is_zero_approx(b.slide_offset()) and b.visual.position.is_zero_approx()
			and is_equal_approx(b.visual.modulate.a, 1.0),
			"взятый на лету блок: в руке %s, выезжает %s, сдвиг %s, видим %.2f" % [game.drag.is_dragging(), b.is_sliding(),
			str(b.visual.position), b.visual.modulate.a])
	game.drag.cancel()
	await get_tree().create_timer(cfg.return_time + 0.15).timeout
	_check(b.get_parent() == tray.slots[slot] and not b.is_sliding() and b.visual.position.is_zero_approx(),
			"взятый на лету блок не вернулся в гнездо %d ровно" % slot)

	game.start_level(12)
	await _frames(1)
	var before: int = game.moves.size()
	var queued := tray.queue.size()
	var m := _play_solution_move(game)
	if _check(not m.is_empty(), "появление на лету: нет хода по решению"):
		_check(game.moves.size() == before + 1, "ход, пока уровень появляется, не засчитан")
		var nb: Block = tray.blocks[int(m.slot)]
		_check(queued == 0 or (nb != null and nb.is_sliding() and nb.get_parent() == tray.slots[int(m.slot)]),
				"после хода новый блок в гнезде %d не выезжает" % int(m.slot))
	await get_tree().create_timer(maxf(_intro_end(), cfg.land_time + 0.12 + cfg.intro_block_time) + 0.3).timeout
	print("  на лету: блок взят посреди выезда, ход посреди появления, новый блок выехал")


var _cover_calls := 0
var _cover_seen := 0.0


func _on_test_cover() -> void:
	_cover_calls += 1
	_cover_seen = Transition.coverage()


## Шторка Transition.cover без смены сцены (rm — «Меньше движения», затемнение): ловит нажатия, закрывает экран
## до конца, зовёт действие один раз (второй вызов во время перехода — мимо) и уходит.
func _curtain_run(rm: bool) -> void:
	var cfg := Block.cfg()
	var tag := "шторка" + (" («Меньше движения»)" if rm else "")
	if not _check(not Transition.is_busy(), "%s: переход уже идёт" % tag):
		return
	_cover_calls = 0
	_cover_seen = 0.0
	var t0 := Time.get_ticks_msec()
	Transition.cover(_on_test_cover)
	var cur := Transition.curtain()
	_check(Transition.is_busy() and cur.visible and cur.mouse_filter == Control.MOUSE_FILTER_STOP
			and Transition.mode() == (Transition.MODE_FADE if rm else Transition.MODE_CELLS),
			"%s: не началась, не ловит нажатия или не тот вид (%d)" % [tag, Transition.mode()])
	Transition.cover(_on_test_cover)  # второй тап по «Играть», пока идёт переход
	var limit := (Transition.FADE_OUT + Transition.FADE_IN) if rm else (cfg.curtain_close + cfg.curtain_open)
	var last := 0.0
	var back := false
	var stop_bad := false
	while Transition.is_busy() and (Time.get_ticks_msec() - t0) / 1000.0 < limit + 1.0:
		await get_tree().process_frame
		var cov := Transition.coverage()
		if _cover_calls == 0:
			back = back or cov < last - 0.0001
		last = cov
		stop_bad = stop_bad or (Transition.is_busy() and cur.mouse_filter != Control.MOUSE_FILTER_STOP)
	var total := (Time.get_ticks_msec() - t0) / 1000.0
	_check(_cover_calls == 1, "%s: действие вызвано %d раз (второй вызов во время перехода — мимо)" % [tag, _cover_calls])
	_check(_cover_seen >= 0.999 and not back and not stop_bad,
			"%s: в миг действия экран закрыт на %.3f; закрытие шло назад %s; пропускала нажатия %s" % [tag, _cover_seen,
			back, stop_bad])
	_check(not Transition.is_busy() and not cur.visible and cur.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and Transition.mode() == Transition.MODE_NONE and is_zero_approx(Transition.coverage()),
			"%s: не ушла (идёт %s, видна %s)" % [tag, Transition.is_busy(), cur.visible])
	_check(total <= limit + 0.25, "%s: шла %.2f с (ждали ≈ %.2f)" % [tag, total, limit])
	if not rm:
		var mat := cur.material as ShaderMaterial
		var screen := cur.size if cur.size.x >= 1.0 and cur.size.y >= 1.0 else cur.get_viewport_rect().size
		var want := maxf(cfg.curtain_cell * minf(screen.x, screen.y), 8.0)
		_check(mat != null and mat.shader != null and mat.shader.resource_path == TRANSITION_SHADER_PATH
				and absf(float(mat.get_shader_parameter("cell")) - want) < 1.0
				and is_equal_approx(float(mat.get_shader_parameter("spread")), cfg.curtain_spread),
				"%s: не %s или клетка не %.0f px" % [tag, TRANSITION_SHADER_PATH, want])
	print("  %s: %.2f с, действие под закрытым экраном, повторный вызов — мимо" % [tag, total])


## Отпускание кнопки «Подсказка» (rm — «Меньше движения»): из ×PRESS_SCALE до ×button_release_peak и ровно в ×1.
func _release_run(game: Game, rm: bool) -> void:
	var cfg := Block.cfg()
	var tag := "отскок кнопки" + (" («Меньше движения»)" if rm else "")
	game.start_level(12)
	await _frames(2)
	var hint := game.hint_button as CandyButton
	if not _check(hint != null and not hint.disabled and hint.is_visible_in_tree(), "%s: «Подсказка» недоступна" % tag):
		return
	hint.toggle_mode = true
	hint.set_pressed_no_signal(true)
	hint.queue_redraw()
	await get_tree().create_timer(CandyButton.PRESS_TIME + 0.1).timeout
	var pressed_ok := hint.looks_pressed and is_equal_approx(hint.face.scale.x, CandyButton.PRESS_SCALE)
	hint.set_pressed_no_signal(false)
	hint.toggle_mode = false
	hint.queue_redraw()
	var peak := 0.0
	var badge_peak := 0.0
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < cfg.button_release_time + 0.2:
		await get_tree().process_frame
		peak = maxf(peak, hint.face.scale.x)
		for bd in hint.badges():
			badge_peak = maxf(badge_peak, bd.scale.x)
	_check(pressed_ok, "%s: нажатая кнопка не ×%.2f" % [tag, CandyButton.PRESS_SCALE])
	if rm:
		_check(peak <= 1.0001 and badge_peak <= 1.0001, "%s: лицо проскочило до ×%.3f" % [tag, peak])
	else:
		var want := 1.0 + (cfg.button_release_peak - 1.0) * 0.6
		_check(peak >= want and peak <= cfg.button_release_peak + 0.0001
				and (hint.badges().is_empty() or badge_peak >= want),
				"%s: лицо до ×%.3f, значки до ×%.3f (ждали ×%.3f…%.3f)" % [tag, peak, badge_peak, want, cfg.button_release_peak])
	var rest := is_equal_approx(hint.face.scale.x, 1.0) and not hint.looks_pressed
	for bd in hint.badges():
		rest = rest and is_equal_approx(bd.scale.x, 1.0)
	_check(rest, "%s: после отпускания лицо ×%.3f, не ×1" % [tag, hint.face.scale.x])
	print("  %s: лицо до ×%.3f и обратно ×1" % [tag, peak])


## Дыхание лотка (после _intro_run: уровень 12 появился, ввода не было).
func _breath_run(game: Game) -> void:
	var cfg := Block.cfg()
	var tray := game.tray
	if GameState.is_audio_suspended():
		print("  дыхание: игра приглушена (вкладка скрыта / реклама) — пропуск")
		return
	var used: Array[int] = []
	for i in tray.blocks.size():
		if tray.blocks[i] != null:
			used.append(i)
	if not _check(used.size() >= 2 and game._can_breathe(), "дыхание: блоков в лотке %d, дышать можно %s" % [used.size(),
			game._can_breathe()]):
		return
	_check(not tray.is_breathing() and tray.idle_time > 0.0 and tray.idle_time < cfg.idle_after,
			"дыхание: до простоя лоток дышит (простой %.2f с)" % tray.idle_time)
	tray.idle_time = cfg.idle_after  # простой «уже был» — не ждать idle_after
	await get_tree().create_timer(cfg.idle_rise + 0.15).timeout
	var full := true
	for i in used:
		full = full and is_equal_approx(tray.breath_level(i), 1.0)
	_check(full, "дыхание: за %.2f с сила не дошла до 1" % cfg.idle_rise)
	# Половина периода: |sin| каждого гнезда успевает дойти до 1.
	var dev: Array[float] = []
	dev.resize(tray.blocks.size())
	dev.fill(0.0)
	var phase_gap := 0.0
	var place_bad := ""
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < cfg.idle_period * 0.5 + 0.1:
		await get_tree().process_frame
		for i in used:
			var f := tray.breath_scale(i)
			dev[i] = maxf(dev[i], absf(f - 1.0))
			var b: Block = tray.blocks[i]
			var slot: Control = tray.slots[i]
			var mid := b.position + b.size * b.scale * 0.5
			if not mid.is_equal_approx(slot.size * 0.5) and mid.distance_to(slot.size * 0.5) > 0.5:
				place_bad = "гнездо %d: середина %s, ждали %s" % [i, str(mid), str(slot.size * 0.5)]
			if not Rect2(Vector2.ZERO, slot.size).grow(0.5).encloses(Rect2(b.position, b.size * b.scale)):
				place_bad = "гнездо %d: блок вылез из гнезда" % i
		phase_gap = maxf(phase_gap, absf(tray.breath_scale(used[0]) - tray.breath_scale(used[1])))
	var amp_bad := ""
	for i in used:
		if dev[i] < cfg.idle_breath * 0.9 or dev[i] > cfg.idle_breath + 0.0005:
			amp_bad += " %d: ±%.4f;" % [i, dev[i]]
	_check(amp_bad.is_empty(), "дыхание: размах по гнёздам%s (ждали ±%.3f)" % [amp_bad, cfg.idle_breath])
	_check(phase_gap > cfg.idle_breath * 0.3, "дыхание: гнёзда дышат в такт (разница %.4f) — нет сдвига фаз" % phase_gap)
	_check(place_bad.is_empty(), "дыхание: " + place_bad)

	# Касание гасит дыхание за idle_fade — блоки ровно в масштабе гнезда.
	game._input(_mouse_press(true))
	game._input(_mouse_press(false))
	await get_tree().create_timer(cfg.idle_fade + 0.1).timeout
	_check(not tray.is_breathing() and _tray_at_rest(tray).is_empty() and tray.idle_time < cfg.idle_after,
			"дыхание после касания не погасло: " + _tray_at_rest(tray))

	# Блок держат (нажат в гнезде) — простой не копится, лоток не дышит.
	tray.idle_time = cfg.idle_after
	game.drag._press_slot = used[0]
	await get_tree().create_timer(cfg.idle_rise * 0.5).timeout
	_check(not tray.is_breathing() and is_zero_approx(tray.idle_time), "дыхание, пока блок держат: сила %.2f, простой %.2f с" % [
			tray.breath_level(used[0]), tray.idle_time])
	game.drag._press_slot = -1
	# Пауза, тупик, окно победы, «Далее», рука-обучение — дышать нельзя.
	var states := ""
	game.paused = true
	states += "" if not game._can_breathe() else " пауза;"
	game.paused = false
	# 20.1a: тупика как состояния больше нет — ошибочный блок возвращается в гнездо, сердца могут кончиться.
	game._mistake = {"block": null, "slot": -1, "rect": Rect2i()}
	states += "" if not game._can_breathe() else " ошибочный блок;"
	game._mistake = {}
	var hearts_max := game.hearts.max_hearts
	game.hearts.reset(3)
	for _k in 3:
		game.hearts.lose()
	states += "" if not game._can_breathe() else " сердца кончились;"
	game.hearts.reset(hearts_max)
	game.finished = true
	states += "" if not game._can_breathe() else " победа;"
	game.finished = false
	game.tutorial_hand.visible = true
	states += "" if not game._can_breathe() else " рука;"
	game.tutorial_hand.visible = false
	_check(states.is_empty() and game._can_breathe(), "дыхание не запрещено:" + states)
	print("  дыхание: ±%.4f со сдвигом фаз %.4f, гаснет от касания, стоит в руке, на паузе, в тупике и в окне" % [
			dev[used[0]], phase_gap])


## "" — блоки лотка в покое: ровно в масштабе своего гнезда и посередине.
func _tray_at_rest(tray: Tray) -> String:
	for i in tray.blocks.size():
		var b: Block = tray.blocks[i]
		if b == null or b.get_parent() != tray.slots[i]:
			continue
		var slot: Control = tray.slots[i]
		var k := minf(tray.block_scale, minf((slot.size.x - Tray.SLOT_MARGIN) / b.size.x,
				(slot.size.y - Tray.SLOT_MARGIN) / b.size.y))
		if not is_equal_approx(b.scale.x, k) or not b.position.is_equal_approx((slot.size - b.size * k) * 0.5):
			return "гнездо %d: ×%.4f вместо ×%.4f, место %s" % [i, b.scale.x, k, str(b.position)]
	return ""


## Тупик и подсказка (14.6g): в миг предупреждения (0,45 с после хода) поле на миг темнеет и светлеет, неверный
## блок трескается (трещина — до отмены), лицо «Отмены» дважды подпрыгивает и встаёт на место; подсказка (12.10) —
## блок сразу летит из гнезда на место, искра — вместе с ним (по прямой, под блоком), в миг касания вспышка (ход
## засчитан сразу, «+очки» — в миг касания, новый блок в гнездо — через 0,12 с); отмена посреди полёта — искра тает
## без вспышки, блок в лотке; последний блок подсказкой — удар победы в миг касания, окно позже на полёт (Game.win_at);
## подсказка в начале уровня, пока блоки ещё выезжают в лоток, — её блок с первого шага полёта виден целиком и на
## месте (Block.end_slide); «Меньше движения» — трещина сразу, кнопка без прыжка, подсказка без искры.
func _test_juice_dead_hint(game: Game) -> void:
	_section("Juice: тупик и подсказка (14.6g)")
	var cfg := Block.cfg()
	_check(cfg.dead_dim > 0.0 and cfg.dead_dim <= 0.5 and cfg.dead_dim_in > 0.0 and cfg.dead_dim_out > 0.0
			and cfg.dead_dim_in + cfg.dead_dim_hold + cfg.dead_dim_out <= 0.8 and cfg.dead_crack_time > 0.0
			and cfg.dead_hop > 0.0 and cfg.dead_hop <= 30.0 and cfg.dead_hop_time > 0.0,
			"juice.tres, «Тупик»: темнее на %.2f за %.2f + %.2f + %.2f с, трещина %.2f с, прыжок %.0f px за %.2f с" % [
			cfg.dead_dim, cfg.dead_dim_in, cfg.dead_dim_hold, cfg.dead_dim_out, cfg.dead_crack_time, cfg.dead_hop,
			cfg.dead_hop_time])
	# 12.10: подсказка не тянется — от нажатия до касания не больше 0,4 с (было 0,78: искра, потом блок).
	_check(cfg.hint_float_time > cfg.land_time and cfg.hint_float_time <= 0.4,
			"juice.tres, «Подсказка»: блок летит на место %.2f с (ждали больше land_time %.2f и не больше 0,4)" % [
			cfg.hint_float_time, cfg.land_time])
	var was_motion := GameState.reduce_motion
	# 20.1a: урока отмены нет (прежде навык UNDO проходили заранее, чтобы обучение не тушило поле).
	for rm in [false, true]:
		GameState.set_reduce_motion(rm)
		await _dead_end_run(game, rm)
		await _hint_run(game, rm)
		await _hint_sliding_run(game, rm)
	GameState.set_reduce_motion(false)
	await _hint_undo_run(game)
	await _hint_last_run(game)
	GameState.set_reduce_motion(was_motion)
	game.juice.reset()


const DEAD_AT := 0.45  # Game._on_mistake: предупреждение тупика — через 0,45 с после хода (блок уже лёг)
const DEAD_LEVELS: Array[int] = [12, 15, 18, 21, 24, 27, 30, 35, 40]


## Ошибка (20.1a) по шагам: свой тупиковый ход — сердце гаснет в кадр хода, через DEAD_AT поле темнеет (слои, не
## board.modulate), блок трескается, сердца вздрагивают (Fx.hop → pulse); через Game.MISTAKE_RETURN блок сам
## возвращается в гнездо без трещины, место на поле свободно. rm — «Меньше движения»: трещина сразу.
func _dead_end_run(game: Game, rm: bool) -> void:
	var cfg := Block.cfg()
	var tag := "ошибка%s" % (", «Меньше движения»" if rm else "")
	var board := game.board
	var mv: Array = []
	for lvl in DEAD_LEVELS:
		game.start_level(lvl)
		await _frames(1)
		mv = _find_dead_end_move(game)
		if not mv.is_empty():
			break
	if not _check(not mv.is_empty(), "%s: на уровнях %s нет тупикового хода" % [tag, str(DEAD_LEVELS)]):
		return
	await get_tree().create_timer(_intro_end() + 0.1).timeout
	var bar := game.hearts_bar
	var slot: int = mv[0]
	var r: Rect2i = mv[1]
	var b: Block = game.tray.blocks[slot]
	var mod0 := board.modulate
	var left0 := game.hearts.left
	var moves0 := game.moves.size()
	_drop(game, slot, r)
	if not _check(game.has_mistake() and game.moves.size() == moves0, "%s: ход %s не стал ошибкой (ходов %d → %d)" % [
			tag, str(r), moves0, game.moves.size()]):
		return
	_check(game.hearts.is_limited() and game.hearts.left == left0 - 1 and bar.left == game.hearts.left,
			"%s: сердце не сгорело в кадр хода (было %d, стало %d, на полосе %d)" % [tag, left0, game.hearts.left,
			bar.left])
	var t0 := Time.get_ticks_msec()
	var dim_start := -1.0
	var max_dim := 0.0
	var crack_full := -1.0
	var crack_early := false
	var max_pulse := 1.0
	var back_at := -1.0
	var tint_bad := ""
	var board_mod_bad := false
	var end := DEAD_AT + maxf(cfg.dead_dim_in + cfg.dead_dim_hold + cfg.dead_dim_out, Game.MISTAKE_RETURN - DEAD_AT) + 0.25
	while true:
		await get_tree().process_frame
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		var d := board.dimmed()
		if d > 0.001 and dim_start < 0.0:
			dim_start = t
		max_dim = maxf(max_dim, d)
		var k := 1.0 - d
		var want := Color(k, k, minf(1.0, k + 0.35 * d))
		for layer in [board.frame, board.cells_root, board.blocks_root]:
			if tint_bad == "" and not (layer as CanvasItem).modulate.is_equal_approx(want):
				tint_bad = "%s %s при %.2f" % [(layer as Node).name, str((layer as CanvasItem).modulate), d]
		board_mod_bad = board_mod_bad or board.modulate != mod0
		if back_at < 0.0:
			var c := b.cracked()
			crack_early = crack_early or (c > 0.0 and t < DEAD_AT - 0.03)
			if c >= 0.999 and crack_full < 0.0:
				crack_full = t
			if not game.has_mistake():
				back_at = t
		max_pulse = maxf(max_pulse, bar.scale.x)
		if t > end:
			break
	_check(dim_start >= DEAD_AT - 0.03 and dim_start <= DEAD_AT + 0.1,
			"%s: поле темнеет через %.2f с после хода (ждали в миг предупреждения, %.2f с)" % [tag, dim_start, DEAD_AT])
	_check(max_dim >= cfg.dead_dim * 0.95 and max_dim <= cfg.dead_dim + 0.001 and is_zero_approx(board.dimmed()),
			"%s: поле темнее на %.3f (ждали %.2f), в конце %.3f" % [tag, max_dim, cfg.dead_dim, board.dimmed()])
	_check(tint_bad == "" and board.blocks_root.modulate.is_equal_approx(Color.WHITE),
			"%s: слои поля не в такт затемнению: %s" % [tag, tint_bad])
	_check(not board_mod_bad, "%s: вспышка тупика тронула board.modulate (его держит обучение)" % tag)
	var crack_by := DEAD_AT + (0.0 if rm else cfg.dead_crack_time) + 0.1
	_check(not crack_early and crack_full >= DEAD_AT - 0.03 and crack_full <= crack_by,
			"%s: трещина целиком через %.2f с (ждали %.2f…%.2f), раньше предупреждения %s" % [tag, crack_full, DEAD_AT,
			crack_by, crack_early])
	_check(max_pulse >= 1.15 and is_equal_approx(bar.scale.x, 1.0),
			"%s: сердца не вздрогнули (масштаб до %.2f, в конце %.2f)" % [tag, max_pulse, bar.scale.x])
	_check(back_at >= Game.MISTAKE_RETURN - 0.05 and back_at <= Game.MISTAKE_RETURN + 0.15,
			"%s: ошибочный блок вернулся через %.2f с (ждали %.2f)" % [tag, back_at, Game.MISTAKE_RETURN])
	_check(is_zero_approx(b.cracked()) and game.tray.blocks[slot] == b and b.get_parent() == game.tray.slots[slot]
			and board.check_rect(r) and game.moves.size() == moves0,
			"%s: после возврата трещина %.2f, блок не в гнезде %d или место занято" % [tag, b.cracked(), slot])
	await get_tree().create_timer(Block.cfg().return_time + 0.15).timeout


## Новые (не из before) всплывающие «+очки» на слое: id узлов FloatingText с текстом «+…». Старые тексты прошлых
## проверок гаснут сами, текст комбо («Супер!») — не очки: ни то, ни другое счёт не сбивает.
func _new_score_texts(layer: Control, before: Array[int]) -> Array[int]:
	var res: Array[int] = []
	for node in layer.get_children():
		var ft := node as FloatingText
		if ft == null or ft.is_queued_for_deletion() or before.has(ft.get_instance_id()):
			continue
		if ft.text_label != null and ft.text_label.text.begins_with("+"):
			res.append(ft.get_instance_id())
	return res


func _live_sparks() -> Array[HintSpark]:
	var res: Array[HintSpark] = []
	for node in get_tree().get_nodes_in_group(HintSpark.GROUP):
		if node is HintSpark and not node.is_queued_for_deletion():
			res.append(node as HintSpark)
	return res


## Середина блока b в глобальных координатах (с его масштабом) — туда смотрит искра подсказки.
func _block_center(b: Block) -> Vector2:
	return b.get_global_transform() * (Vector2(b.cells) * Block.CELL * 0.5)


## Подсказка (12.10): ход засчитан сразу, блок трогается в тот же миг и летит на место за hint_float_time; искра
## летит вместе с ним — из его середины в середину места, по прямой, каждый кадр в середине блока, под ним
## (z ниже FLOAT_Z), — и вспыхивает в миг касания; «+очки» — в миг касания, новый блок в гнездо — через 0,12 с.
func _hint_run(game: Game, rm: bool) -> void:
	var cfg := Block.cfg()
	var tag := "подсказка%s" % (", «Меньше движения»" if rm else "")
	var board := game.board
	var juice := game.juice
	game.start_level(12)
	await get_tree().create_timer(_intro_end() + 0.1).timeout
	var before := game.moves.size()
	var no_ids: Array[int] = []
	var texts0 := _new_score_texts(game.fx_layer, no_ids)
	var placed0 := int(juice.counts.get(&"placed", 0))
	var live0 := juice.live_particles()
	game.hints.give()
	if not _check(game.moves.size() == before + 1, "%s: ход не засчитан сразу" % tag):
		return
	var m: Dictionary = game.moves.back()
	var b: Block = m.block
	var r: Rect2i = m.rect
	var slot: int = m.slot
	var to := board.cell_center_global(r)
	var start := b.global_position
	var from := _block_center(b)
	var fly := cfg.hint_float_time
	_check(board.holds(b, r) and b.get_parent() == board.blocks_root and b.z_index == Board.FLOAT_Z,
			"%s: блок не на поле поверх лотка (z %d)" % [tag, b.z_index])
	_check(_new_score_texts(game.fx_layer, texts0).is_empty(), "%s: «+очки» раньше, чем блок долетел" % tag)
	var sparks := _live_sparks()
	var spark: HintSpark = null
	if rm:
		_check(sparks.is_empty(), "«Меньше движения»: у подсказки искра")
	elif _check(sparks.size() == 1, "подсказка: искр %d (ждали 1)" % sparks.size()):
		spark = sparks[0]
		_check(spark.head().distance_to(from) < 1.0 and spark.target().distance_to(to) < 1.0,
				"искра летит из %s в %s (ждали из середины блока %s в середину места %s)" % [str(spark.head()),
				str(spark.target()), str(from), str(to)])
		var mid := spark.point_at(0.5)
		_check(mid.distance_to((from + to) * 0.5) < 1.0,
				"искра летит не по прямой: середина хода %s (ждали %s)" % [str(mid), str((from + to) * 0.5)])
		_check(spark.z_index < Board.FLOAT_Z, "искра над летящим блоком (z %d, у блока %d) — ждали под ним" % [
				spark.z_index, Board.FLOAT_Z])
	var new_b: Block = game.tray.blocks[slot]
	var had_spark := spark != null  # удалённая искра в Godot 4.7 равна null (14.8e)
	var t0 := Time.get_ticks_msec()
	var moved_at := -1.0
	var lifted_seen := false
	var landed_at := -1.0
	var spark_gone := -1.0
	var burst_ok := false
	var prog_prev := 0.0
	var prog_bad := false
	var lag := 0.0  # наибольшее расхождение искры и середины блока в полёте, px
	var new_seen := -1.0
	while true:
		await get_tree().process_frame
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		if moved_at < 0.0 and b.global_position.distance_to(start) > 0.5:
			moved_at = t
		lifted_seen = lifted_seen or b.lifted
		if had_spark and spark_gone < 0.0:
			if is_instance_valid(spark) and not spark.is_queued_for_deletion():
				prog_bad = prog_bad or spark.progress() < prog_prev - 0.0001
				prog_prev = spark.progress()
				if landed_at < 0.0:
					lag = maxf(lag, spark.head().distance_to(_block_center(b)))
			else:
				spark_gone = t
				burst_ok = juice.live_particles() > live0
		if new_b != null and new_seen < 0.0 and new_b.visual.modulate.a > 0.0:
			new_seen = t
		if landed_at < 0.0 and int(juice.counts.get(&"placed", 0)) > placed0:
			landed_at = t
		if landed_at >= 0.0 and t > landed_at + 0.05 and (not had_spark or spark_gone >= 0.0):
			break
		if t > fly + 1.0:
			break
	_check(moved_at >= 0.0 and moved_at <= 0.1,
			"%s: блок тронулся через %.2f с (ждали сразу — подсказка не ждёт)" % [tag, moved_at])
	if not rm:
		_check(spark_gone >= fly - 0.03 and spark_gone <= fly + 0.1 and burst_ok and not prog_bad,
				"подсказка: искра долетела через %.2f с (ждали %.2f, вместе с блоком), вспышка %s, ход назад %s" % [
				spark_gone, fly, burst_ok, prog_bad])
		_check(lag < 3.0, "подсказка: искра отстаёт от середины летящего блока на %.1f px (ждали вместе)" % lag)
	_check(landed_at >= fly - 0.03 and landed_at <= fly + 0.1 and lifted_seen,
			"%s: блок долетел через %.2f с (ждали %.2f), тень «поднят» в полёте %s" % [tag, landed_at, fly, lifted_seen])
	_check(b.z_index == 0 and not b.lifted and b.position.is_equal_approx(Vector2(r.position) * Board.CELL)
			and b.scale.is_equal_approx(Vector2.ONE),
			"%s: блок встал не на место: z %d, поднят %s, %s, ×%s" % [tag, b.z_index, b.lifted, str(b.position),
			str(b.scale)])
	var texts := _new_score_texts(game.fx_layer, texts0)
	_check(texts.size() == 1, "%s: «+очки» в миг касания — %d (ждали 1)" % [tag, texts.size()])
	if new_b != null:
		_check(new_seen >= 0.12 - 0.03, "%s: новый блок в гнезде через %.2f с (ждали после 0,12)" % [tag, new_seen])


## Подсказка сразу после начала уровня, пока блоки ещё выезжают в лоток (14.6b): взятый ею блок с первого шага
## полёта виден целиком и стоит в себе — не выезжает из-под края экрана посреди пути (Block.end_slide в
## Board._float_start); долетает и ложится как обычно.
func _hint_sliding_run(game: Game, rm: bool) -> void:
	var cfg := Block.cfg()
	var tag := "подсказка, пока лоток выезжает%s" % (", «Меньше движения»" if rm else "")
	var juice := game.juice
	game.start_level(12)
	await get_tree().process_frame
	var placed0 := int(juice.counts.get(&"placed", 0))
	game.hints.give()
	if not _check(game.moves.size() == 1, "%s: подсказка не сделала ход" % tag):
		return
	var m: Dictionary = game.moves.back()
	var b: Block = m.block
	var r: Rect2i = m.rect
	var sliding0 := b.is_sliding()
	var start := b.global_position
	var t0 := Time.get_ticks_msec()
	var moved := false
	var bad := ""
	while (Time.get_ticks_msec() - t0) / 1000.0 < cfg.hint_float_time + 0.5:
		await get_tree().process_frame
		if not moved and b.global_position.distance_to(start) <= 0.5:
			continue
		moved = true
		if not b.is_moving():
			break
		if b.is_sliding() or b.visual.modulate.a < 0.999 or b.visual.position.length() > 0.5:
			bad = "выезжает %s, прозрачность %.2f, сдвиг %s" % [b.is_sliding(), b.visual.modulate.a,
					str(b.visual.position)]
			break
	_check(moved and bad.is_empty(), "%s (выезжал при подсказке: %s): блок в полёте %s" % [tag, sliding0,
			bad if moved else "не тронулся"])
	await get_tree().create_timer(0.15).timeout
	_check(int(juice.counts.get(&"placed", 0)) == placed0 + 1 and _board_rest(game.board, b, r),
			"%s: блок не лёг на место (ударов %d → %d)" % [tag, placed0, int(juice.counts.get(&"placed", 0))])


## Блок b лежит на поле на месте r и в покое: z 0, не поднят, позиция и масштаб — как у клетки, Visual на месте.
func _board_rest(board: Board, b: Block, r: Rect2i) -> bool:
	return board.holds(b, r) and b.z_index == 0 and not b.lifted and not b.is_sliding() \
			and b.position.is_equal_approx(Vector2(r.position) * Board.CELL) and b.scale.is_equal_approx(Vector2.ONE) \
			and b.visual.modulate.a >= 0.999


## Снятие хода посреди полёта подсказки (Game.undo_last; кнопки «Отмена» с 20.1a нет): ход снят, искра тает без вспышки, блок — в своё гнездо, на поле он не ложится.
func _hint_undo_run(game: Game) -> void:
	var cfg := Block.cfg()
	var tag := "подсказка, ход снят посреди полёта"
	var board := game.board
	var juice := game.juice
	game.start_level(12)
	await get_tree().create_timer(_intro_end() + 0.1).timeout
	var placed0 := int(juice.counts.get(&"placed", 0))
	game.hints.give()
	if not _check(game.moves.size() == 1, "%s: подсказка не сделала ход" % tag):
		return
	var m: Dictionary = game.moves.back()
	var b: Block = m.block
	var r: Rect2i = m.rect
	var slot: int = m.slot
	await get_tree().create_timer(cfg.hint_float_time * 0.5).timeout
	var live0 := juice.live_particles()
	game.undo_last()  # 20.1a: кнопки «Отмена» нет; ход снимает служебный undo_last (новая попытка, лаборатория)
	_check(game.moves.is_empty() and not board.holds(b, r) and b.z_index == 0 and b.get_parent() == game.tray.slots[slot],
			"%s: ход не снят (ходов %d), z %d, блок не в гнезде" % [tag, game.moves.size(), b.z_index])
	await get_tree().create_timer(maxf(cfg.return_time, cfg.hint_float_time) + 0.15).timeout
	_check(int(juice.counts.get(&"placed", 0)) == placed0, "%s: блок всё равно лёг на поле" % tag)
	_check(_live_sparks().is_empty() and juice.live_particles() <= live0,
			"%s: искра не растаяла (%d) или вспыхнула (частиц %d → %d)" % [tag, _live_sparks().size(), live0,
			juice.live_particles()])
	var rest := _tray_at_rest(game.tray)
	_check(rest.is_empty(), "%s: лоток не в покое: %s" % [tag, rest])


## Последний блок ставит подсказка: удар победы — в миг касания долетевшего блока, окно — через Game.win_at
## = WIN_SHOW_AT + полёт подсказки (hint_float_time) − land_time.
func _hint_last_run(game: Game) -> void:
	var cfg := Block.cfg()
	var juice := game.juice
	game.start_level(12)
	await get_tree().create_timer(_intro_end() + 0.1).timeout
	var total := (game.level_data.pieces as Array).size()
	for _i in 80:
		if game.moves.size() >= total - 1 or game.finished:
			break
		if _play_solution_move(game).is_empty():
			break
	if not _check(game.moves.size() == total - 1 and not game.finished,
			"последний блок подсказкой: не дошли до последнего хода (%d из %d)" % [game.moves.size(), total]):
		return
	await get_tree().create_timer(cfg.land_time + cfg.line_wave_time + cfg.line_fade + 0.3).timeout
	var win0 := int(juice.counts.get(&"win", 0))
	game.hints.give()
	var land := cfg.hint_float_time
	var want := Game.WIN_SHOW_AT + land - cfg.land_time
	_check(game.finished and is_equal_approx(game.win_at, want),
			"последний блок подсказкой: окно через %.2f с (ждали %.2f)" % [game.win_at, want])
	var t0 := Time.get_ticks_msec()
	var win_at := -1.0
	var panel_at := -1.0
	while true:
		await get_tree().process_frame
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		if win_at < 0.0 and int(juice.counts.get(&"win", 0)) > win0:
			win_at = t
		if panel_at < 0.0 and game.win_panel.visible:
			panel_at = t
		if panel_at >= 0.0 or t > want + 0.6:
			break
	_check(win_at >= land - 0.03 and win_at <= land + 0.12,
			"последний блок подсказкой: удар победы через %.2f с (ждали в миг касания, %.2f)" % [win_at, land])
	_check(panel_at >= want - 0.03 and panel_at <= want + 0.15,
			"последний блок подсказкой: окно через %.2f с (ждали %.2f)" % [panel_at, want])
	await get_tree().create_timer(WinPanel.BUTTONS_DELAY + 0.2).timeout


## «Меньше движения»: и после простоя лоток не дышит.
func _breath_reduced(game: Game) -> void:
	var tray := game.tray
	tray.idle_time = Block.cfg().idle_after + 1.0
	await get_tree().create_timer(0.4).timeout
	_check(not tray.is_breathing() and _tray_at_rest(tray).is_empty(),
			"«Меньше движения»: лоток дышит в простое " + _tray_at_rest(tray))


## Уровень lvl: hints подсказок (каждая — штраф: 1 → две звезды), остальное — ходы по решению; последний ход — сам,
## с замерами каждый кадр до конца анимации окна. {} — не дошли до последнего хода.
func _play_win(game: Game, lvl: int, hints: int) -> Dictionary:
	var cfg := Block.cfg()
	var juice := game.juice
	var board := game.board
	var wp: WinPanel = game.win_panel
	game.start_level(lvl)
	await get_tree().create_timer(0.6).timeout
	for _i in hints:
		game.hints.give()
	var total := (game.level_data.pieces as Array).size()
	for _i in 80:
		if game.moves.size() >= total - 1 or game.finished:
			break
		if _play_solution_move(game).is_empty():
			break
	var tag := "L%d%s" % [lvl, ", «Меньше движения»" if GameState.reduce_motion else ""]
	if not _check(game.moves.size() == total - 1 and not game.finished,
			"%s: не дошли до последнего хода (%d из %d)" % [tag, game.moves.size(), total]):
		return {}
	# Блоки подсказок долетают позже обычного (14.6g) — ждём и их удар с волнами линий.
	var late := cfg.hint_float_time if hints > 0 else 0.0
	await get_tree().create_timer(late + cfg.land_time + cfg.line_wave_time + cfg.line_fade + 0.3).timeout
	var s := game.solve(game.placed_rects(), game.remaining_pieces())
	var rects: Array = s.solution if s.status == ShikakuSolver.SOLVED else game.level_data.solution
	var m := game.tray.find_move(rects, game.board)
	if not _check(not m.is_empty(), "%s: последний блок некуда поставить" % tag):
		return {}
	var slot: int = m.slot
	var r: Rect2i = m.rect
	var b: Block = game.tray.blocks[slot]
	if r.size != b.cells:
		b.rotate_cells()
		await get_tree().create_timer(cfg.rotate_time + 0.05).timeout
	juice.reset()
	# Только новые волны линий и тексты (14.8e): старые за время прохода исчезают, разность счётчиков уходит в минус.
	var old_fx: Dictionary = {}
	for n: Node in _line_flashes(board):
		old_fx[n.get_instance_id()] = true
	for n: Node in _slam_texts(game.fx_layer):
		old_fx[n.get_instance_id()] = true
	var new_lines: Dictionary = {}
	var new_texts: Dictionary = {}
	var line_ev0 := int(juice.counts.get(&"line", 0))
	var win_ev0 := int(juice.counts.get(&"win", 0))
	var t0 := Time.get_ticks_msec()
	game.commit_place(b, slot, r)
	var res: Dictionary = {"tag": tag, "finished": game.finished,
			"at_commit": _win_waves(board).size() + int(juice.counts.get(&"win", 0)) - win_ev0}
	var wave: WinWave = null
	var wave_found := false  # удалённая волна в Godot 4.7 равна null (14.8e)
	var landed := false
	var stopped_at_land := false
	var held := true      # пока hit-stop: волна стоит (фронт 0, не видна, твин не идёт)
	var from_block := false
	var front := 0.0
	var reach := 0.0
	var strength := 0.0
	var peak := 0.0
	var trauma := 0.0
	var arrive: Dictionary = {}   # блок → приход фронта, с
	var flash: Dictionary = {}    # блок → наибольшая вспышка
	var pop: Dictionary = {}      # блок → наибольший масштаб Visual (кроме последнего)
	var merged_at: Dictionary = {}  # блок → с от броска, когда merge > 0,5
	var star_max: Array[float] = [0.0, 0.0, 0.0]
	var star_min: Array[float] = [9.0, 9.0, 9.0]
	var sparkled: Array[bool] = [false, false, false]
	var punch := 0.0
	var dur := Game.WIN_SHOW_AT + WinPanel.BUTTONS_DELAY + 0.3
	while Time.get_ticks_msec() - t0 < int(dur * 1000.0):
		await get_tree().process_frame
		var now := float(Time.get_ticks_msec() - t0) / 1000.0
		trauma = maxf(trauma, juice.trauma)
		if not landed and int(juice.counts.get(&"win", 0)) > win_ev0:
			landed = true
			stopped_at_land = juice.is_stopped()
		for n: Node in _line_flashes(board):
			if not old_fx.has(n.get_instance_id()):
				new_lines[n.get_instance_id()] = true
		for n: Node in _slam_texts(game.fx_layer):
			if not old_fx.has(n.get_instance_id()):
				new_texts[n.get_instance_id()] = true
		if not wave_found:
			for w in _win_waves(board):
				wave = w
				wave_found = true
				reach = w.reach()
				from_block = absf(w.arrival((Vector2(r.position) + Vector2(r.size) * 0.5) * Block.CELL)) < 0.001
				peak = w.peak
				for blk in board._blocks:
					var br: Rect2i = board._blocks[blk]
					arrive[blk] = w.arrival((Vector2(br.position) + Vector2(br.size) * 0.5) * Block.CELL)
		if wave_found and is_instance_valid(wave) and not wave.is_queued_for_deletion():
			if juice.is_stopped():
				held = held and wave.front == 0.0 and wave.strength == 0.0 and not wave.wave_tween().is_running()
			front = maxf(front, wave.front)
			strength = maxf(strength, wave.strength)
		for blk in board._blocks:
			var sm := (blk as Block).shape.material as ShaderMaterial
			if sm != null:
				flash[blk] = maxf(float(flash.get(blk, 0.0)), float(sm.get_shader_parameter("flash")))
			if blk != b:
				pop[blk] = maxf(float(pop.get(blk, 0.0)), (blk as Block).visual.scale.x)
			if (blk as Block).merged() > 0.5 and not merged_at.has(blk):
				merged_at[blk] = now
		if wp.visible:
			for i in wp.stars.size():
				star_max[i] = maxf(star_max[i], wp.stars[i].scale.x)
				if wp.stars[i].modulate.a > 0.01:
					star_min[i] = minf(star_min[i], wp.stars[i].scale.x)
				sparkled[i] = sparkled[i] or wp.sparkles[i].emitting
			if not wp.star_hits.is_empty():
				punch = maxf(punch, wp.card.position.y - wp.card_rect.position.y)
	var all_merged := true
	for blk in board._blocks:
		var sm := (blk as Block).shape.material as ShaderMaterial
		all_merged = all_merged and (blk as Block).merged() > 0.999 and sm != null \
				and float(sm.get_shader_parameter("merge")) > 0.999
	var order_ok := true
	for a in merged_at:
		for c in merged_at:
			if float(arrive.get(a, 0.0)) + 0.1 < float(arrive.get(c, 0.0)) and float(merged_at[a]) > float(merged_at[c]) + 0.02:
				order_ok = false
	var merge_first := 99.0
	var merge_last := 0.0
	for v in merged_at.values():
		merge_first = minf(merge_first, float(v))
		merge_last = maxf(merge_last, float(v))
	var at_rest := true
	for i in wp.stars.size():
		at_rest = at_rest and is_equal_approx(wp.stars[i].scale.x, 1.0) and wp.stars[i].modulate.a > 0.99 \
				and is_equal_approx(wp.stars[i].rotation_degrees, WinPanel.STAR_TILT[i])
	res.merge({"landed": landed, "stopped_at_land": stopped_at_land, "held": held, "wave": wave_found,
			"wave_gone": not is_instance_valid(wave), "from_block": from_block, "front": front,
			"reach": reach, "strength": strength, "peak": peak, "trauma": trauma,
			"line_waves": new_lines.size(), "line_texts": new_texts.size(),
			"line_events": int(juice.counts.get(&"line", 0)) - line_ev0,
			"win_events": int(juice.counts.get(&"win", 0)) - win_ev0, "blocks": board._blocks.size(),
			"flash": flash, "pop": pop, "merged": merged_at.size(), "all_merged": all_merged, "order_ok": order_ok,
			"merge_first": merge_first, "merge_last": merge_last, "stars": wp.star_count, "hits": wp.star_hits.duplicate(),
			"star_max": star_max.max(), "star_maxes": star_max, "star_mins": star_min, "sparkled": sparkled,
			"punch": punch, "at_rest": at_rest, "panel": wp.visible,
			"pitch": Audio.last_pitch(Audio.STAR)})  # голосов несколько (15.1b)
	return res


## Проверки одного прохода _play_win: rm — «Меньше движения».
func _check_win_run(res: Dictionary, rm: bool) -> void:
	var cfg := Block.cfg()
	var tag: String = res.tag
	_check(bool(res.finished) and int(res.at_commit) == 0,
			"%s: удар победы или волна по полю — в миг броска, а не когда последний блок долетел" % tag)
	_check(bool(res.landed) and int(res.win_events) == 1 and bool(res.stopped_at_land) and bool(res.held),
			"%s: удар победы (событие win %d, hit-stop: %s, волна ждёт его конца: %s)" % [tag, int(res.win_events),
			res.stopped_at_land, res.held])
	_check(int(res.line_waves) == 0 and int(res.line_texts) == 0 and int(res.line_events) == 0,
			"%s: на последнем ходу сыграла линия: волн +%d, текстов +%d, событий line +%d (их заменяет волна по полю)" % [
			tag, int(res.line_waves), int(res.line_texts), int(res.line_events)])
	var peak := minf(cfg.win_wave_strength, cfg.reduced_wave) if rm else cfg.win_wave_strength
	_check(bool(res.wave) and bool(res.from_block) and float(res.front) >= float(res.reach) * 0.97
			and absf(float(res.peak) - peak) < 0.001 and float(res.strength) > peak * 0.9 and bool(res.wave_gone),
			"%s: волна по полю (есть: %s, от последнего блока: %s, фронт %.0f из %.0f px, сила %.2f — ждали %.2f, удалилась: %s)" % [
			tag, res.wave, res.from_block, float(res.front), float(res.reach), float(res.strength), peak, res.wave_gone])
	var amount := minf(cfg.win_block_flash, cfg.reduced_wave) if rm else cfg.win_block_flash
	var flash_ok := true
	for v in (res.flash as Dictionary).values():
		flash_ok = flash_ok and float(v) >= amount * 0.8 and float(v) <= amount + 0.001
	var pop_ok := true
	for v in (res.pop as Dictionary).values():
		pop_ok = pop_ok and (float(v) <= 1.001 if rm else float(v) >= 1.0 + cfg.win_block_pop * 0.6)
	_check(flash_ok and pop_ok, "%s: блоки на волне — вспышка до %.2f (каждый: %s), подскок %s (%s)" % [tag, amount,
			flash_ok, "нет" if rm else "до ×%.2f" % (1.0 + cfg.win_block_pop), pop_ok])
	if cfg.win_mosaic:
		_check(bool(res.all_merged) and int(res.merged) == int(res.blocks) and bool(res.order_ok)
				and float(res.merge_last) <= Game.WIN_SHOW_AT + 0.1,
				"%s: мозаика — сошлись %d из %d блоков (до конца: %s, по приходу фронта: %s), последний — через %.2f с (окно — %.2f)" % [
				tag, int(res.merged), int(res.blocks), res.all_merged, res.order_ok, float(res.merge_last), Game.WIN_SHOW_AT])
	else:
		_check(int(res.merged) == 0, "%s: мозаика убрана (win_mosaic = false, 14.8e), а сошлись %d из %d блоков" % [
				tag, int(res.merged), int(res.blocks)])
	_check(rm == (float(res.trauma) == 0.0), "%s: тряска %.2f" % [tag, float(res.trauma)])
	var n: int = res.stars
	var hits_ok := (res.hits as Array).size() == n
	for i in (res.hits as Array).size():
		hits_ok = hits_ok and int(res.hits[i]) == i
	var stars_ok := true
	for i in 3:
		var mx: float = res.star_maxes[i]
		var mn: float = res.star_mins[i]
		if i < n and not rm:
			stars_ok = stars_ok and mx >= cfg.star_slam * 0.95 and mn <= 0.97 and bool(res.sparkled[i])
		else:
			stars_ok = stars_ok and mx <= 1.001 and mn >= WinPanel.STAR_QUIET_FROM - 0.01 and bool(res.sparkled[i]) == (i < n)
	_check(bool(res.panel) and n >= 1 and hits_ok and stars_ok and bool(res.at_rest),
			"%s: звёзды окна — заработано %d, удары %s, масштаб %s…%s, искры %s, в покое: %s" % [tag, n, str(res.hits),
			str(res.star_mins), str(res.star_maxes), str(res.sparkled), res.at_rest])
	_check((float(res.punch) <= 0.5) if rm else (float(res.punch) >= cfg.star_punch * 0.5),
			"%s: карточка вздрогнула на %.1f px (ждали %s)" % [tag, float(res.punch),
			"0" if rm else "до %.0f" % cfg.star_punch])
	if GameState.sfx_on and n >= 1:
		_check(is_equal_approx(float(res.pitch), cfg.star_pitch(n - 1)),
				"%s: нота последней звезды %.3f, ждали %.3f" % [tag, float(res.pitch), cfg.star_pitch(n - 1)])


## Ставит один блок по решению (как подсказка, но без штрафа): {slot, rect} или {} — некуда.
func _play_solution_move(game: Game) -> Dictionary:
	var s := game.solve(game.placed_rects(), game.remaining_pieces())
	var rects: Array = s.solution if s.status == ShikakuSolver.SOLVED else game.level_data.solution
	var m := game.tray.find_move(rects, game.board)
	if m.is_empty():
		return {}
	var slot: int = m.slot
	var r: Rect2i = m.rect
	var b: Block = game.tray.blocks[slot]
	if r.size != b.cells:
		b.rotate_cells()
	game.commit_place(b, slot, r)
	return m


## Волны по полю (WinWave) на поле board сейчас.
func _win_waves(board: Board) -> Array[WinWave]:
	var res: Array[WinWave] = []
	for node in board.fx_root.get_children():
		if node is WinWave and not node.is_queued_for_deletion():
			res.append(node as WinWave)
	return res


## Ставит блоки по решению, пока в лотке не найдётся ход, закрывающий линию и не последний на уровне (поле не
## заполнится): {slot, rect, lines} или {} — не нашлось. Попутно: ход без линии обрывает серию (сила −1, без волны).
func _find_line_move(game: Game) -> Dictionary:
	var cfg := Block.cfg()
	var sol: Array = game.level_data.solution
	var broke_checked := false
	while game.moves.size() + 2 <= sol.size():
		var placed := game.placed_rects()
		var closing: Array = []
		var others: Array = []
		for item in sol:
			var q: Rect2i = item
			if placed.has(q):
				continue
			if _lines_closed(game.board, placed, q) > 0:
				closing.append(q)
			else:
				others.append(q)
		var m := game.tray.find_move(closing, game.board)
		if not m.is_empty():
			m["lines"] = _lines_closed(game.board, placed, m.rect)
			return m
		m = game.tray.find_move(others, game.board)
		if m.is_empty():
			return {}
		var slot: int = m.slot
		var r: Rect2i = m.rect
		var b: Block = game.tray.blocks[slot]
		if r.size != b.cells:
			b.rotate_cells()
			await get_tree().create_timer(cfg.rotate_time + 0.05).timeout
		var waves := _line_flashes(game.board).size()
		game.line_streak = 2
		game.commit_place(b, slot, r)
		var last: Dictionary = game.moves.back()
		await get_tree().create_timer(cfg.land_time + 0.1).timeout
		if not broke_checked:
			broke_checked = true
			_check(game.line_streak == 0 and int(last.power) == -1 and int(last.lines) == 0
					and _line_flashes(game.board).size() == waves,
					"ход без линии: серия %d (ждали 0), сила %d (ждали −1), волн +%d (ждали 0)" % [game.line_streak,
					int(last.power), _line_flashes(game.board).size() - waves])
	return {}


## Сколько линий поля (строк и столбцов через r) станут полными, если к placed добавить r.
func _lines_closed(board: Board, placed: Array[Rect2i], r: Rect2i) -> int:
	var filled: Dictionary = {}
	var all: Array[Rect2i] = []
	all.append_array(placed)
	all.append(r)
	for q in all:
		for y in range(q.position.y, q.end.y):
			for x in range(q.position.x, q.end.x):
				filled[Vector2i(x, y)] = true
	var n := 0
	for y in range(r.position.y, r.end.y):
		var full := true
		for x in board.cols:
			full = full and filled.has(Vector2i(x, y))
		n += 1 if full else 0
	for x in range(r.position.x, r.end.x):
		var full := true
		for y in board.rows:
			full = full and filled.has(Vector2i(x, y))
		n += 1 if full else 0
	return n


## Волны линий (LineFlash) на поле сейчас.
func _line_flashes(board: Board) -> Array[LineFlash]:
	var res: Array[LineFlash] = []
	for node in board.fx_root.get_children():
		if node is LineFlash and not node.is_queued_for_deletion():
			res.append(node as LineFlash)
	return res


## Тексты комбо («штамп», FloatingText.slam) на слое layer сейчас.
func _slam_texts(layer: Control) -> Array[FloatingText]:
	var res: Array[FloatingText] = []
	for node in layer.get_children():
		if node is FloatingText and (node as FloatingText).slam_tween != null and not node.is_queued_for_deletion():
			res.append(node as FloatingText)
	return res


## Ход m (из _find_line_move) при серии streak до него: бросок, удар, волна, текст. Что было видно —
## {move, streak, at_commit (волн, текстов и событий line в миг броска), waves, waves_on_lines, from_block, reached,
## peak, strength, block_flash, events, trauma, pitch, text, text_size, scale_max, scale_min, scale_end}.
func _play_line_move(game: Game, m: Dictionary, streak: int) -> Dictionary:
	var cfg := Block.cfg()
	var board := game.board
	var juice := game.juice
	var slot: int = m.slot
	var r: Rect2i = m.rect
	var b: Block = game.tray.blocks[slot]
	if r.size != b.cells:
		b.rotate_cells()
		await get_tree().create_timer(cfg.rotate_time + 0.05).timeout
	juice.reset()
	var old_ids: Dictionary = {}  # instance_id волн и текстов до хода
	for node in _line_flashes(board):
		old_ids[node.get_instance_id()] = true
	for node in _slam_texts(game.fx_layer):
		old_ids[node.get_instance_id()] = true
	var waves0 := _line_flashes(board).size()
	var texts0 := _slam_texts(game.fx_layer).size()
	var events0 := int(juice.counts.get(&"line", 0))
	game.line_streak = streak
	game.commit_place(b, slot, r)
	var mv: Dictionary = game.moves.back()
	var res: Dictionary = {"move": mv, "streak": game.line_streak}
	res["at_commit"] = _line_flashes(board).size() - waves0 + _slam_texts(game.fx_layer).size() - texts0 \
			+ int(juice.counts.get(&"line", 0)) - events0
	var lines: Array[Rect2i] = []
	lines.assign(mv.get("line_rects", []))
	var on_line: Array[Block] = []
	for blk in board._blocks:
		var br: Rect2i = board._blocks[blk]
		for ln in lines:
			if br.intersects(ln):
				on_line.append(blk)
				break
	var seen: Dictionary = {}  # instance_id волны → [пик, путь фронта до, сила до, нужный путь]
	var on_lines := true
	var from_block := true
	var block_flash := 0.0
	var trauma := 0.0
	var text: FloatingText = null
	res.merge({"text": "", "text_size": 0, "scale_max": 0.0, "scale_min": 99.0, "scale_end": 0.0})
	var t0 := Time.get_ticks_msec()
	var dur := cfg.land_time + cfg.hitstop_max + cfg.combo_slam_time + 0.12 + FloatingText.SLAM_HOLD + 0.2
	while Time.get_ticks_msec() - t0 < int(dur * 1000.0) + 300:
		await get_tree().process_frame
		for fx in _line_flashes(board):
			var id := fx.get_instance_id()
			if old_ids.has(id):
				continue
			if not seen.has(id):
				var line := Rect2i(Vector2i((fx.position / Block.CELL).round()), Vector2i((fx.size / Block.CELL).round()))
				on_lines = on_lines and lines.has(line)
				var src := r.intersection(line)
				var origin := (Vector2(src.position - line.position) + Vector2(src.size) * 0.5) * Block.CELL
				from_block = from_block and src.has_area() and absf(fx.arrival(origin)) < 0.001
				var horiz := fx.size.x >= fx.size.y
				var along := origin.x if horiz else origin.y
				var span := fx.size.x if horiz else fx.size.y
				seen[id] = [fx.peak, 0.0, 0.0, maxf(along, span - along)]
			var st: Array = seen[id]
			st[1] = maxf(float(st[1]), fx.front)
			st[2] = maxf(float(st[2]), fx.strength)
		for blk in on_line:
			var sm := blk.shape.material as ShaderMaterial
			if sm != null:
				block_flash = maxf(block_flash, float(sm.get_shader_parameter("flash")))
		trauma = maxf(trauma, juice.trauma)
		if text == null:
			for f in _slam_texts(game.fx_layer):
				if not old_ids.has(f.get_instance_id()):
					text = f
					res["text"] = f.text_label.text
					res["text_size"] = f.text_label.get_theme_font_size(&"font_size")
		if text != null and is_instance_valid(text) and not text.is_queued_for_deletion():
			var sc := text.text_label.scale.x
			res["scale_max"] = maxf(float(res.scale_max), sc)
			res["scale_min"] = minf(float(res.scale_min), sc)
			res["scale_end"] = sc
	var reached := not seen.is_empty()
	var peak := 0.0
	var strength := 0.0
	for v in seen.values():
		var st: Array = v
		peak = maxf(peak, float(st[0]))
		strength = maxf(strength, float(st[2]))
		reached = reached and float(st[1]) >= float(st[3]) * 0.97
	res.merge({"waves": seen.size(), "waves_on_lines": on_lines, "from_block": from_block, "reached": reached,
			"peak": peak, "strength": strength, "block_flash": block_flash, "trauma": trauma,
			"events": int(juice.counts.get(&"line", 0)) - events0,
			"pitch": Audio.last_pitch(Audio.LINE)})  # голосов несколько (15.1b)
	return res


## Board.landed во время _test_juice_moves: [блок, место, мс].
func _on_test_landed(blk: Block, rr: Rect2i) -> void:
	_landed_log.append([blk, rr, Time.get_ticks_msec()])


## Обучение по навыкам (TutorialCoach, Tutorial): что видно на старте уровня, рука
## по навыку, подпись и причины красной подсветки, на уровне 4 — без напутствий, первый тупик
## без страховки, пульс подсказки. Ходы руки должны проходить уровни 1..GUARD_LEVELS.
func _test_tutorial(game: Game) -> void:
	var coach: TutorialCoach = game.coach
	var hand: TutorialHand = game.tutorial_hand
	var label: Label = game.coach_label
	var guard: int = Tutorial.GUARD_LEVELS
	# 13.4: рука — hand.png, кончик пальца (36, 2) из 120×120 стоит в начале координат руки (там, куда она указывает).
	var hr := hand.hand as TextureRect
	_check(hr != null and hr.texture != null and hr.texture.resource_path.ends_with("hand.png")
			and hr.position.is_equal_approx(Vector2(-36, -2)) and hr.size.is_equal_approx(Vector2(120, 120))
			and hr.pivot_offset.is_equal_approx(Vector2(36, 2)),
			"рука обучения: %s, место %s, размер %s, ось %s" % [hr.texture.resource_path if hr and hr.texture else "нет",
			str(hr.position) if hr else "", str(hr.size) if hr else "", str(hr.pivot_offset) if hr else ""])

	# Старт уровней: навык, отсчёт до руки, подпись над полем.
	GameState.reset_progress()
	game.start_level(1)
	var countdown0 := coach.countdown  # через кадры отсчёт уже идёт (14.8e)
	await _frames(2)  # раскладка поля отложена (call_deferred)
	_check(coach.skill == Tutorial.DRAG and not hand.visible and is_equal_approx(countdown0, TutorialCoach.FIRST_DELAY)
			and coach.countdown > 0.0 and coach.countdown <= TutorialCoach.FIRST_DELAY + 0.001,
			"L1: навык %d, рука видна: %s, отсчёт %.2f на старте и %.2f через 2 кадра (ждали DRAG, нет, FIRST_DELAY и не больше)" % [
			coach.skill, hand.visible, countdown0, coach.countdown])
	_check(label.visible and label.text == coach.caption() and not label.text.is_empty(), "L1: нет подписи над полем")
	_check(game.board.position.y >= Game.COACH_SPACE, "L1: поле наезжает на подпись (y = %.1f)" % game.board.position.y)
	game.start_level(2)
	# 07.10: на уровне 2 рука появляется так же сразу, как на уровне 1, и показывает первый блок лотка.
	_check(coach.skill == Tutorial.ROTATE and is_equal_approx(coach.countdown, TutorialCoach.FIRST_DELAY),
			"L2: навык %d, отсчёт %.2f (ждали ROTATE, FIRST_DELAY — рука сразу, как на L1)" % [coach.skill, coach.countdown])
	coach.postpone()
	_check(is_equal_approx(coach.countdown, TutorialCoach.IDLE_DELAY),
			"L2: после нажатия рука ждёт %.2f с (ждали IDLE_DELAY, как на L1)" % coach.countdown)
	game.start_level(guard)
	_check(coach.skill == Tutorial.ONE_NUMBER and label.visible, "L%d: навык %d или нет подписи" % [guard, coach.skill])
	# 07.10: на уровне 3 рука тоже сразу и первым показывает урок — блок первого гнезда на одно из двух одинаковых
	# соседних чисел. Игрок сам поставил блок не туда — рука по-прежнему частая; поставил на пару — только после
	# долгого простоя.
	_check(is_equal_approx(coach.countdown, TutorialCoach.FIRST_DELAY),
			"L%d: отсчёт %.2f (ждали FIRST_DELAY — рука сразу, как на L1–L2)" % [guard, coach.countdown])
	await _frames(1)
	var m3: Dictionary = coach.next_move()
	_check(not m3.is_empty() and int(m3.slot) == 0 and game.board.has_twin_next_to(m3.rect),
			"L%d: первый ход руки %s — не блок первого гнезда на одно из двух одинаковых чисел" % [guard, str(m3)])
	if not m3.is_empty():
		var far := Rect2i()
		for cand: Rect2i in game.level_data.solution:  # место решения без пары чисел: игрок начал не с урока
			if not game.board.has_twin_next_to(cand):
				far = cand
				break
		coach.postpone()
		coach.on_own_move(far)
		_check(far.has_area() and is_equal_approx(coach.countdown, TutorialCoach.IDLE_DELAY),
				"L%d: ход не на пару (%s) — отсчёт %.2f (ждали IDLE_DELAY)" % [guard, str(far), coach.countdown])
		coach.postpone()
		coach.on_own_move(m3.rect)
		var after_pair := coach.countdown
		coach.postpone()
		_check(is_equal_approx(after_pair, TutorialCoach.LONG_IDLE) and is_equal_approx(coach.countdown, TutorialCoach.LONG_IDLE)
				and coach.skill == Tutorial.ONE_NUMBER,
				"L%d: после хода на пару отсчёт %.2f, после нажатия %.2f, навык %d (ждали LONG_IDLE и ONE_NUMBER)" % [
				guard, after_pair, coach.countdown, coach.skill])
	game.start_level(guard + 1)
	await _frames(2)
	_check(coach.skill == 0 and not label.visible, "L%d: навык %d или видна подпись (страховка только до %d)" % [guard + 1, coach.skill, guard])
	_check(game.board.position.y < Game.COACH_SPACE, "L%d: без подписи поле всё равно сдвинуто вниз" % (guard + 1))

	# Причины: rect_issue согласован с check_rect, у каждой красной причины есть текст.
	game.start_level(guard)
	var board: Board = game.board
	var bad_texts := 0
	for h in range(1, board.rows + 1):
		for w in range(1, board.cols + 1):
			for y in range(0, board.rows - h + 1):
				for x in range(0, board.cols - w + 1):
					var r := Rect2i(x, y, w, h)
					var issue := board.rect_issue(r)
					if not _check((issue == Tutorial.Issue.OK) == board.check_rect(r), "rect_issue(%s) = %d не согласован с check_rect" % [str(r), issue]):
						return
					if issue != Tutorial.Issue.OK:
						var text := coach.reason_text(issue, board.number_in(r))
						_check(not text.is_empty(), "нет текста для причины %d (%s)" % [issue, str(r)])
						bad_texts += 1
	_check(coach.reason_text(Tutorial.Issue.WRONG_SIZE, 7).contains("7"), "причина «не тот размер» без числа")
	_check(not coach.reason_text(Tutorial.Issue.DEAD_END, 0).is_empty(), "нет текста для тупика")
	_check(coach.reason_text(Tutorial.Issue.OUTSIDE, 0).is_empty() and coach.reason_text(Tutorial.Issue.OK, 0).is_empty(),
			"для «не над полем» и «встанет» не должно быть причины")
	game.drag.hover_changed.emit(Tutorial.Issue.MANY_NUMBERS, 0)
	_check(label.text == coach.reason_text(Tutorial.Issue.MANY_NUMBERS, 0), "подпись не показала причину под блоком")
	game.drag.hover_changed.emit(Tutorial.Issue.OK, 2)
	_check(label.text == coach.caption(), "подпись не вернулась, когда блок над верным местом")

	# Самоучка: два своих хода на уровне 1 — навык пройден, рука больше не нужна.
	GameState.reset_progress()
	game.start_level(1)
	for _k in Tutorial.DRAG_OWN_MOVES:
		var m: Dictionary = coach.next_move()
		if not _check(not m.is_empty(), "L1: нет хода для руки"):
			return
		_drop(game, m.slot, m.rect)
	_check(GameState.has_skill(Tutorial.DRAG) and coach.skill == 0,
			"L1: после %d своих ходов навык не засчитан" % Tutorial.DRAG_OWN_MOVES)

	if GameState.is_audio_suspended():
		# Окно без фокуса (не headless): коуч ждёт, как при рекламе. Дальше проверять нечего.
		print("  (звук приглушён — окно без фокуса? Проверка руки пропущена)")
		GameState.reset_progress()
		return
	coach.countdown = 0.0
	coach.tick(0.016)
	_check(not hand.visible, "L1: рука появилась у игрока, который ходит сам")

	# Новичок на уровне 1: рука показывает простой ход без поворота.
	GameState.reset_progress()
	game.start_level(1)
	await _frames(1)
	coach.countdown = 0.0
	coach.tick(0.016)
	if not _check(hand.visible, "L1: рука не появилась после простоя"):
		return
	var r1: Rect2i = coach.target
	var mv: Dictionary = coach.next_move()
	_check(not mv.is_empty() and mv.rect == r1, "L1: рука показывает не тот ход, что даёт next_move()")
	_check(game.board.check_rect(r1) and not game.leads_to_dead_end(r1, r1.size), "L1: рука ведёт в тупик или на занятое место: %s" % str(r1))
	var taps := 0
	if not mv.is_empty():
		var b: Block = game.tray.blocks[mv.slot]
		taps = 0 if b.cells == r1.size else 1
		_check(taps == 0, "L1: первый показ руки — с поворотом, хотя есть ход без него")

	if not _quick:
		# Дошла до места — клетки подсвечены; закончила — ни руки, ни подсветки.
		var tap_time := (TutorialHand.TAP_TIME * 2.0 + TutorialHand.TAP_PAUSE) * taps
		await get_tree().create_timer(TutorialHand.FADE_TIME + tap_time + TutorialHand.TAP_TIME + TutorialHand.MOVE_TIME + 0.15).timeout
		_check(hand.visible and coach.preview_shown, "L1: рука дошла до места, а клетки не подсветились")
		await get_tree().create_timer(TutorialHand.TAP_TIME + TutorialHand.HOLD_TIME + TutorialHand.FADE_TIME * 1.25 + 0.3).timeout
		_check(not hand.visible and not coach.preview_shown, "L1: рука не исчезла после показа или осталась подсветка")

	# Любое нажатие прячет руку и начинает отсчёт простоя заново.
	coach.countdown = 0.0
	coach.tick(0.016)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	game._input(click)
	_check(not hand.visible and not coach.preview_shown and is_equal_approx(coach.countdown, TutorialCoach.IDLE_DELAY),
			"L1: рука не спряталась от нажатия (видна: %s, отсчёт %.2f)" % [hand.visible, coach.countdown])

	# Игрок делает только то, что показывает рука, — обучающие уровни проходятся;
	# на уровне 1 рука не просит поворотов, на уровне 2 хотя бы раз просит.
	for lvl in range(1, guard + 1):
		game.start_level(lvl)
		await _frames(1)
		var steps := 0
		var turns := 0
		var first_turn := false
		while not game.finished and steps < 40:
			var m: Dictionary = coach.next_move()
			if m.is_empty():
				break
			var b: Block = game.tray.blocks[m.slot]
			var mr: Rect2i = m.rect
			if b.cells != mr.size:
				turns += 1
				first_turn = first_turn or steps == 0
			_place(game, m.slot, mr)
			steps += 1
		_check(game.finished and game.board.is_full(), "L%d: ходы руки не довели уровень до конца (ходов %d)" % [lvl, steps])
		_check(not hand.visible and coach.skill == 0, "L%d: рука видна после победы или навык не засчитан" % lvl)
		if lvl == 1:
			_check(turns == 0, "L1: рука просит повернуть блок (%d раз)" % turns)
		elif lvl == 2:
			# Подпись «Нажми на блок, чтобы повернуть его» — и рука сразу про поворот.
			_check(first_turn, "L2: первый ход руки без поворота — рука показывает не тот блок, что подпись")
	_check(GameState.has_skill(Tutorial.DRAG | Tutorial.ROTATE | Tutorial.ONE_NUMBER),
			"после уровней 1–%d навыки не все: %d" % [guard, GameState.tutorial])

	# Уровень 2: не смог поставить блок, который надо повернуть, — рука сразу показывает поворот.
	GameState.reset_progress()
	game.start_level(2)
	await _frames(1)
	var turn_slot := -1
	for i in game.tray.blocks.size():
		if game.tray.blocks[i] != null and coach._needs_turn(i):
			turn_slot = i
			break
	_check(turn_slot == 0, "L2: блок, который надо повернуть, в слоте %d (ждали первым, 07.10)" % turn_slot)
	if _check(turn_slot >= 0, "L2: в лотке нет блока, который надо повернуть"):
		# Простой: рука выбирает именно этот блок (а не тот, что встаёт как есть).
		coach.countdown = 0.0
		coach.tick(0.016)
		_check(hand.visible and coach.target == coach._move_for_slot(turn_slot).get("rect", Rect2i()),
				"L2: после простоя рука показывает не блок, который надо повернуть")
		coach.postpone()
		game.drag.returned.emit(turn_slot, Tutorial.Issue.OUTSIDE, 0)
		_check(is_equal_approx(coach.countdown, TutorialCoach.TURN_DELAY), "L2: после неудачной попытки рука не спешит (%.2f)" % coach.countdown)
		coach.tick(TutorialCoach.TURN_DELAY + 0.01)
		var tb: Block = game.tray.blocks[turn_slot]
		_check(hand.visible and coach.target.size != tb.cells, "L2: рука не показала поворот этого блока")
		# Игрок сам поворачивает и ставит блок — навык пройден.
		game.drag._rotate_in_tray(turn_slot)
		var tm: Dictionary = coach._move_for_slot(turn_slot)
		if _check(not tm.is_empty(), "L2: нет места для повёрнутого блока"):
			_drop(game, turn_slot, tm.rect)
			_check(GameState.has_skill(Tutorial.ROTATE) and coach.skill == 0 and not hand.visible,
					"L2: сам повернул и поставил — навык не засчитан")

	# Причина после неудачного броска держится REASON_HOLD, потом — снова навык.
	game.start_level(guard)
	game.drag.returned.emit(0, Tutorial.Issue.DEAD_END, 0)
	_check(label.text == coach.reason_text(Tutorial.Issue.DEAD_END, 0), "L%d: подпись не объяснила неудачный бросок" % guard)
	coach.tick(TutorialCoach.REASON_HOLD + 0.1)
	_check(label.text == coach.caption(), "L%d: причина не сменилась подписью навыка" % guard)

	# Первый уровень без страховки: обучение кончилось — ни подписи, ни напутствий (07.10: «Дальше — сам!» убран).
	GameState.learn(Tutorial.DRAG | Tutorial.ROTATE | Tutorial.ONE_NUMBER)
	game.start_level(guard + 1)
	for _k in 5:
		coach.tick(0.5)
	_check(not label.visible and not game.toast.is_shown(),
			"L%d: напутствие или подпись после обучения («%s»)" % [guard + 1, game.toast.shown_text()])
	coach.countdown = 0.0
	coach.tick(0.016)
	_check(not hand.visible, "рука появилась на уровне %d (только 1–%d)" % [guard + 1, guard])

	# Первая ошибка без страховки (20.1a): урока отмены нет — поле не тускнеет, руки нет, блок вернётся сам.
	var dead_lvl := 0
	var dead: Array = []
	for lvl in range(guard + 1, guard + 20):
		game.start_level(lvl)
		dead = _find_dead_end_move(game)
		if not dead.is_empty():
			dead_lvl = lvl
			break
	if _check(dead_lvl > 0, "не нашлось уровня с тупиковым ходом после обучения"):
		_drop(game, dead[0], dead[1])
		coach.countdown = 0.0
		coach.tick(0.5)
		_check(game.has_mistake() and not hand.visible and game.board.modulate == Color.WHITE,
				"L%d: первая ошибка — рука или притушенное поле (урок отмены убран в 20.1a)" % dead_lvl)
		game.flush_mistake()
		coach.tick(0.016)
		_check(not game.has_mistake() and not hand.visible, "L%d: ошибочный блок не вернулся или появилась рука" % dead_lvl)

	# Долгий простой на уровнях HINT_FROM..HINT_TO — пульс подсказки, пока ей не пользовались.
	game.start_level(Tutorial.HINT_FROM)
	coach.idle = Tutorial.HINT_IDLE
	coach.tick(0.016)
	_check(coach.hint_offered, "L%d: после долгого простоя подсказку не предложили" % Tutorial.HINT_FROM)
	game.start_level(Tutorial.HINT_TO + 1)
	coach.idle = Tutorial.HINT_IDLE
	coach.tick(0.016)
	_check(not coach.hint_offered, "L%d: подсказку предлагают после уровня %d" % [Tutorial.HINT_TO + 1, Tutorial.HINT_TO])
	game.hints.give()
	_check(GameState.has_skill(Tutorial.HINT), "подсказка взята, а навык HINT не засчитан")
	game.start_level(Tutorial.HINT_FROM)
	coach.idle = Tutorial.HINT_IDLE
	coach.tick(0.016)
	_check(not coach.hint_offered, "подсказку предлагают тому, кто ей уже пользовался")
	GameState.reset_progress()
	print("  обучение: навыки 1–%d, рука, подпись и причины, уровень %d без напутствий, первая ошибка без урока, подсказка" % [
			guard, guard + 1])


## Ход игрока перетаскиванием: блок из слота отпущен на r (сигнал DragController.dropped → Game._on_dropped):
## тупиковый — ошибка (20.1a), остальные — commit_place.
func _drop(game: Game, slot: int, r: Rect2i) -> void:
	var b: Block = game.tray.blocks[slot]
	if b.cells != r.size:
		b.rotate_cells()
	game.drag.dropped.emit(b, slot, r)


## Пауза: окно открывается, рука прячется, подсказка не срабатывает, «Продолжить» снимает паузу.
func _test_pause(game: Game) -> void:
	GameState.reset_progress()  # на уровне 1 рука ещё нужна
	game.start_level(1)
	var hand: TutorialHand = game.tutorial_hand
	var suspended := GameState.is_audio_suspended()
	if not suspended:
		game.coach.countdown = 0.0
		game.coach.tick(0.016)
	game._on_pause_pressed()
	var pp: SettingsPanel = game.pause_panel
	_check(game.paused and pp.visible and pp.mode == SettingsPanel.Mode.PAUSE, "пауза не открылась")
	_check(not hand.visible, "рука осталась поверх окна паузы")
	game.coach.countdown = 0.0
	game.coach.tick(0.016)
	_check(not hand.visible, "рука появилась во время паузы")
	var moves_before: int = game.moves.size()
	game.hints.request()
	_check(game.moves.size() == moves_before, "подсказка сработала во время паузы")
	pp.close_button.pressed.emit()
	_check(not game.paused and not pp.visible, "«Продолжить» не сняло паузу")
	print("  пауза работает")


## Ошибка (20.1a) на уровне lvl: тупиковый свой ход не засчитан — ходов не прибавилось, гнездо пустое и новый блок в
## него не выдан, блок на поле; сердце сгорело (на уровне с сердцами), ошибка посчитана. flush_mistake — блок снова в
## своём гнезде, трещины нет, место свободно. Вторая ошибка — подсказка сначала возвращает блок, потом ставит верный.
## false — тупикового хода не нашлось.
func _test_dead_end(game: Game, lvl: int) -> bool:
	var mv := _find_dead_end_move(game)
	if mv.is_empty():
		return false
	var slot: int = mv[0]
	var r: Rect2i = mv[1]
	var b: Block = game.tray.blocks[slot]
	var moves_before: int = game.moves.size()
	var queue_before: int = game.tray.queue.size()
	var left_before := game.hearts.left
	var mistakes_before := game.hearts.mistakes
	_drop(game, slot, r)
	_check(game.has_mistake() and game.moves.size() == moves_before and game.tray.blocks[slot] == null
			and game.tray.queue.size() == queue_before and b.get_parent() == game.board.blocks_root
			and not game.board.check_rect(r),
			"L%d: тупиковый ход %s засчитан или блок не на поле (ходов %d → %d, в очереди %d → %d)" % [lvl, str(r),
			moves_before, game.moves.size(), queue_before, game.tray.queue.size()])
	var want_left := maxi(left_before - 1, 0) if game.hearts.is_limited() else 0
	_check(game.hearts.mistakes == mistakes_before + 1 and game.hearts.left == want_left,
			"L%d: после ошибки сердец %d (ждали %d), ошибок %d (ждали %d)" % [lvl, game.hearts.left, want_left,
			game.hearts.mistakes, mistakes_before + 1])
	game.flush_mistake()
	_check(not game.has_mistake() and game.tray.blocks[slot] == b and b.get_parent() == game.tray.slots[slot]
			and game.board.check_rect(r) and is_zero_approx(b.cracked()) and game.moves.size() == moves_before,
			"L%d: ошибочный блок не вернулся в гнездо %d (трещина %.2f)" % [lvl, slot, b.cracked()])
	await _frames(1)

	mv = _find_dead_end_move(game)
	if mv.is_empty():
		return _check(false, "L%d: после возврата тупиковый ход пропал" % lvl)
	_drop(game, mv[0], mv[1])
	game.hints.give()
	_check(not game.has_mistake() and game.moves.size() == moves_before + 1 and game.can_play(),
			"L%d: подсказка после ошибки не вернула блок или не поставила верный (ходов %d, ждали %d)" % [lvl,
			game.moves.size(), moves_before + 1])
	await _frames(1)
	return true


func _find_dead_end_move(game: Game) -> Array:
	var board: Board = game.board
	for i in game.tray.blocks.size():
		var b: Block = game.tray.blocks[i]
		if b == null:
			continue
		var dims_list: Array[Vector2i] = [b.cells]
		if b.cells.x != b.cells.y:
			dims_list.append(Vector2i(b.cells.y, b.cells.x))
		for dims in dims_list:
			for y in range(0, board.rows - dims.y + 1):
				for x in range(0, board.cols - dims.x + 1):
					var r := Rect2i(x, y, dims.x, dims.y)
					if board.check_rect(r) and game.leads_to_dead_end(r, dims):
						return [i, r]
	return []


func _place(game: Game, slot: int, r: Rect2i) -> void:
	var b: Block = game.tray.blocks[slot]
	if b.cells != r.size:
		b.rotate_cells()
	game.commit_place(b, slot, r)


## Проходит текущий уровень одними подсказками. true — уровень пройден.
func _solve_with_hints(game: Game, lvl: int) -> bool:
	var overflow := _tray_overflow(game)
	for _i in 60:
		if game.finished:
			break
		var before: int = game.moves.size()
		game.hints.give()
		if overflow.is_empty():
			overflow = _tray_overflow(game)
		if not game.finished and game.moves.size() == before:
			break  # подсказка ничего не сделала
	_check(overflow.is_empty(), "L%d: блок не помещается в слот лотка: %s" % [lvl, overflow])
	var ok := _check(game.finished and game.board.is_full(), "L%d: подсказки не довели уровень до конца (ходов %d)" % [lvl, game.moves.size()])
	return ok


## "" — все блоки лотка помещаются в свои слоты, иначе описание первого, что вылез.
func _tray_overflow(game: Game) -> String:
	for i in game.tray.blocks.size():
		var b: Block = game.tray.blocks[i]
		var slot: Control = game.tray.slots[i]
		if b == null or slot.size.x <= 0.0:
			continue
		var shown := b.size * b.scale
		if shown.x > slot.size.x + 0.5 or shown.y > slot.size.y + 0.5:
			return "блок %s в слоте %d: %s при слоте %s" % [str(b.cells), i, str(shown), str(slot.size)]
	return ""


## Окно победы (13.5b): лучи и конфетти за полем, поле переехало, панели ушли, карточка и заголовок — на
## местах раскладки (и после смены раскладки посреди показа); «Далее» и защита от нажатий, пока ждём
## рекламу; на новом уровне фон гаснет, поле и панели возвращаются.
func _test_win_flow(game: Game) -> void:
	var lvl: int = game.level
	var wp: WinPanel = game.win_panel
	# Последний блок поставила подсказка — окно позже на её искру и вплывание (Game.win_at, 14.6g).
	await get_tree().create_timer(game.win_at + 0.15).timeout
	_check(game.win_backdrop.visible and game.win_backdrop.confetti.is_active(),
			"L%d: через 0,15 с после показа победы за полем нет лучей и конфетти" % lvl)
	await get_tree().create_timer(WinPanel.BUTTONS_DELAY + 0.25).timeout
	if not _check(wp.visible, "L%d: окно победы не показалось" % lvl):
		return
	_check(not wp.next_button.disabled, "кнопка «Далее» не включилась")
	_check_win_layout(game, "победа")
	_check(is_equal_approx(game.background.get_light(), Background.LIGHT_WIN),
			"победа: свет фона %.3f, ждали %.3f" % [game.background.get_light(), Background.LIGHT_WIN])
	# 13.4: звёзды — star.png / star_empty.png по числу заработанных; 13.5b: «Переиграть» — ссылка CardLink
	# с иконкой restart.png, «Далее» — PillButton.
	var earned := 0
	for st: TextureRect in wp.stars:
		_check(st.texture == WinPanel.STAR_ON or st.texture == WinPanel.STAR_OFF, "звезда окна победы не из star.png / star_empty.png")
		earned += 1 if st.texture == WinPanel.STAR_ON else 0
	_check(earned >= 1 and wp.stars[0].texture == WinPanel.STAR_ON, "на победе нет ни одной заработанной звезды (%d)" % earned)
	_check(wp.replay_button.theme_type_variation == &"CardLink" and wp.replay_button.icon != null
			and wp.replay_button.icon.resource_path.ends_with("restart.png"),
			"«Переиграть» не ссылка CardLink с иконкой restart.png")
	_check_link(wp.replay_button, "«Переиграть»")
	var rb := wp.replay_button
	_check(absf(rb.position.x + rb.size.x * 0.5 - wp.card.size.x * 0.5) < 1.0 and rb.position.x >= 0.0,
			"«Переиграть» не по центру карточки: x %.0f, ширина %.0f из %.0f" % [rb.position.x, rb.size.x, wp.card.size.x])
	if _check(wp.next_button is PillButton, "«Далее» не PillButton"):
		_check(wp.next_button.caption.text == wp.next_button.atr(wp.next_button.text),
				"«Далее»: подпись «%s» — не перевод «%s»" % [wp.next_button.caption.text, wp.next_button.text])
		var loc := TranslationServer.get_locale()
		for lang: String in ["ru", "en", "tr"]:
			TranslationServer.set_locale(lang)
			_check_pill_caption(wp.next_button, tr("ДАЛЕЕ"), "победа (%s)" % lang)
		TranslationServer.set_locale(loc)
	_check(wp.head_label.text != "" and wp.score_label.text == "+" + HudHeader.format_score(wp.points),
			"карточка: шапка «%s», очки «%s» при %d" % [wp.head_label.text, wp.score_label.text, wp.points])
	_check(WinPanel.head_for_stars(0) == WinPanel.WIN_HEADS[0] and WinPanel.head_for_stars(3) == WinPanel.WIN_HEADS[2]
			and WinPanel.head_for_stars(9) == WinPanel.WIN_HEADS[2], "WinPanel.head_for_stars не по звёздам 1…3")
	# Смена раскладки посреди показа: альбом и обратно — всё переезжает в места новой раскладки.
	var real := game.size
	game.apply_layout(Vector2(2276, 1280))
	await _frames(2)
	if _check(game.landscape, "победа: 2276×1280 — не альбом"):
		_check_win_layout(game, "победа, альбом 16:9")
	game.apply_layout(real)
	await _frames(2)
	_check_win_layout(game, "победа, снова портрет")
	var next_level := GameState.level
	wp.next_button.pressed.emit()
	_check(wp.next_button.disabled and wp.visible, "после «Далее» окно должно остаться с выключенными кнопками")
	var session: int = game.session
	# Без флага ожидания «Домой» по-настоящему сменил бы сцену и оборвал самопроверку.
	if not _check(game._next_pending, "после «Далее» игра не ждёт рекламу (_next_pending = false)"):
		return
	game._on_restart_pressed()
	game._on_home_pressed()
	_check(game.session == session and game.is_inside_tree(), "«Заново»/«Домой» сработали во время ожидания рекламы")
	await _frames(2)
	_check(game.level == next_level and not wp.visible, "«Далее» не открыл уровень %d (сейчас %d, окно видно: %s)" % [next_level, game.level, wp.visible])
	_check(not game.win_backdrop.visible and not game.win_backdrop.confetti.is_active() and game.win_board_t == 0.0,
			"новый уровень: лучи / конфетти не погасли или поле не вернулось (win_board_t %.2f)" % game.win_board_t)
	_check(not game.background.is_win(), "новый уровень: свет фона остался победным")
	await get_tree().create_timer(Game.WIN_RETURN_TIME + 0.15).timeout
	_check(game.win_panels_t == 0.0 and game.top_bar.modulate.a > 0.99 and game.tray.modulate.a > 0.99,
			"новый уровень: панели не вернулись (win_panels_t %.2f)" % game.win_panels_t)
	_layout_matches(game, "после победы")
	print("  окно победы: переезд поля, лучи и конфетти, смена раскладки, «Далее»")


## Победа на экране: BoardArea в layout.win_board, рамка поля в нём; шапка, кнопки, «Осталось блоков» и
## лоток погасли; карточка и заголовок — в layout.win_card / win_title; поле не заходит на звёзды на кромке
## карточки (в портрете — над ними, в альбоме — левее карточки); лучи — за серединой поля.
func _check_win_layout(game: Game, tag: String) -> void:
	var l := game.layout
	var wp: WinPanel = game.win_panel
	_check(is_equal_approx(game.win_board_t, 1.0) and is_equal_approx(game.win_panels_t, 1.0),
			"%s: переезд не закончился (поле %.2f, панели %.2f)" % [tag, game.win_board_t, game.win_panels_t])
	var area := Rect2(game.board_area.position, game.board_area.size)
	_check(area.is_equal_approx(l.win_board), "%s: BoardArea %s, ждали win_board %s" % [tag, area, l.win_board])
	_check(is_equal_approx(game.board.max_scale, l.win_board_scale),
			"%s: наибольший масштаб поля %.2f, ждали %.2f" % [tag, game.board.max_scale, l.win_board_scale])
	var frame := game.board.frame_rect_global()
	_check(game.board_area.get_global_rect().grow(1.0).encloses(frame), "%s: поле %s вылезло из win_board" % [tag, frame])
	for c: Control in [game.top_bar, game.actions_bar, game.remaining_label, game.tray]:
		_check(c.modulate.a < 0.01, "%s: %s не погас (%.2f)" % [tag, c.name, c.modulate.a])
	var card := Rect2(wp.card.position, wp.card.size)
	_check(card.is_equal_approx(l.win_card), "%s: карточка %s, ждали %s" % [tag, card, l.win_card])
	_check(is_equal_approx(wp.card.scale.x, 1.0) and wp.card.modulate.a > 0.99, "%s: карточка не в покое" % tag)
	var title := Rect2(wp.title_label.position, wp.title_label.size)
	_check(title.is_equal_approx(l.win_title) and wp.title_label.modulate.a > 0.99,
			"%s: заголовок %s, ждали %s" % [tag, title, l.win_title])
	_check(wp.title_label.text.count("\n") < (2 if l.landscape else 1),
			"%s: заголовок «%s» — лишние строки" % [tag, wp.title_label.text])
	var card_g := wp.card.get_global_rect()
	var star_top := card_g.position.y + WinPanel.STAR_CENTERS[1].y - WinPanel.STAR_R[1]
	if l.landscape:
		_check(frame.end.x <= card_g.position.x and frame.end.x <= wp.title_label.get_global_rect().position.x,
				"%s: поле %s заходит на столбик с карточкой %s" % [tag, frame, card_g])
	else:
		_check(frame.end.y <= star_top + 1.0, "%s: низ поля %.0f ниже верха звёзд карточки %.0f" % [tag, frame.end.y, star_top])
	_check(game.background.is_win(), "%s: свет фона не победный" % tag)
	_check(game.background.get_rect_size().is_equal_approx(game.background.size),
			"%s: шейдер фона знает размер %s, у фона %s" % [tag, game.background.get_rect_size(), game.background.size])
	var bd := game.win_backdrop
	var center := frame.get_center() - bd.global_position
	_check(bd.visible and bd.get_center().distance_to(center) < 1.0,
			"%s: лучи за %s, середина поля %s" % [tag, bd.get_center(), center])


## Ответ рекламы от прошлого запуска уровня не должен ничего менять.
func _test_stale_ads(game: Game) -> void:
	var old_session: int = game.session
	game.start_level(game.level)
	var lvl: int = game.level
	game._go_to_next_level(old_session)
	_check(game.level == lvl and game.session == old_session + 1, "устаревший ответ межстраничной рекламы сменил уровень")
	game.hints._on_ad_finished(true, old_session)
	_check(game.moves.is_empty(), "устаревший ответ рекламы за награду поставил подсказку")
	print("  устаревшие ответы рекламы игнорируются")


# --- Аналитика (16.1) ----------------------------------------------------------

## Аналитика (16.1, autoload/analytics.gd; README «Аналитика»): интервалы и ключи, журнал целей в игре — попытка
## уровня от начала до итога, задача дня, «Лаборатория», навык обучения; итоги рекламы и отзыва из YSDK.
func _test_analytics() -> void:
	_section("Аналитика: цели Метрики (16.1)")
	# Интервалы секунд и ключи уровней — те же, что в web/shell.html (сверяет tools/check_shell.py).
	var spans := [[0.0, "0-3"], [2.99, "0-3"], [3.0, "3-5"], [19.9, "10-20"], [59.9, "30-60"], [299.0, "120-300"],
			[300.0, "300+"], [5000.0, "300+"]]
	for sp: Array in spans:
		_check(Analytics.span(sp[0]) == sp[1], "Analytics.span(%s) = «%s», ждали «%s»" % [str(sp[0]),
				Analytics.span(sp[0]), sp[1]])
	_check(Analytics.level_key(12) == "L0012" and Analytics.level_key(1000) == "L1000",
			"ключи уровней: «%s», «%s»" % [Analytics.level_key(12), Analytics.level_key(1000)])
	_check(not Analytics.is_enabled() and Analytics.sent == 0,
			"вне веба цели ушли в Метрику (включена %s, отправлено %d)" % [str(Analytics.is_enabled()), Analytics.sent])
	Analytics.journal.clear()
	for i in Analytics.JOURNAL_SIZE + 5:
		Analytics.goal("selftest", {"n": i})
	_check(Analytics.journal.size() == Analytics.JOURNAL_SIZE
			and int(Analytics.journal[0]["params"]["n"]) == 5 and Analytics.count("selftest") == Analytics.JOURNAL_SIZE,
			"журнал целей: %d записей (ждали %d, старые — в начале)" % [Analytics.journal.size(), Analytics.JOURNAL_SIZE])
	Analytics.journal.clear()

	# Навык обучения: цель один раз на навык, вне уровня — "menu" (попытку, если её оставил прошлый раздел, закрываем).
	Analytics.run_end(&"exit", -1, -1)
	GameState.reset_progress()
	GameState.learn(Tutorial.UNDO)
	GameState.learn(Tutorial.UNDO)
	_check(Analytics.count("tutorial_step") == 1
			and Analytics.last("tutorial_step").get("params", {}) == {"tutorial_step": {"undo": "menu"}},
			"навык обучения: целей %d, последняя %s" % [Analytics.count("tutorial_step"), str(Analytics.last("tutorial_step"))])
	GameState.reset_progress()
	Analytics.journal.clear()

	# Попытка уровня: игра стартует с уровня 1, переход на 12 закрывает её выходом.
	var ps := load(GAME_SCENE) as PackedScene
	var game := ps.instantiate() as Game
	add_child(game)
	await _frames(3)
	_check(_goal_params("level_start") == {"level_start": {"L0001": "new"}},
			"начало уровня 1: %s" % str(Analytics.last("level_start")))
	var total1 := (game.level_data.pieces as Array).size()
	game.start_level(LOGIC_LEVEL)
	await _frames(1)
	var key := Analytics.level_key(LOGIC_LEVEL)
	var total := (game.level_data.pieces as Array).size()
	var exit1: Dictionary = _goal_params("level_exit").get("level_exit", {}).get("L0001", {})
	_check(_is_span(exit1.get("time")) and exit1.get("undo", -1) == 0 and exit1.get("hint", -1) == 0
			and exit1.get("dead", -1) == 0 and exit1.get("placed", "") == "0/%d" % total1 and exit1.size() == 5
			and Analytics.run_key == key,
			"смена уровня не закрыла попытку уровня 1 выходом: %s, открыта «%s»" % [str(Analytics.last("level_exit")),
			Analytics.run_key])
	_check(_goal_params("level_start") == {"level_start": {key: "new"}}, "начало уровня %d: %s" % [LOGIC_LEVEL,
			str(Analytics.last("level_start"))])
	# Свой ход — first_move один раз; подсказка своим ходом не считается.
	var m := _solution_slot(game)
	if _check(not m.is_empty(), "уровень %d: нет хода из решения" % LOGIC_LEVEL):
		_drop(game, m.slot, m.rect)
	m = _solution_slot(game)
	if not m.is_empty():
		_drop(game, m.slot, m.rect)
	_check(Analytics.count("first_move") == 1 and _is_span(_goal_params("first_move").get("first_move", {}).get(key)),
			"первый ход: целей %d, последняя %s" % [Analytics.count("first_move"), str(Analytics.last("first_move"))])
	# Тупик и отмена — по разу за попытку, сколько всего — в итоге.
	for _k in 2:
		var mv := _find_dead_end_move(game)
		if not _check(not mv.is_empty(), "уровень %d: нет тупикового хода" % LOGIC_LEVEL):
			break
		_drop(game, mv[0], mv[1])
		game._on_undo_pressed()
		await _frames(1)
	_check(Analytics.count("dead_end") == 1 and _goal_params("dead_end") == {"dead_end": {key: 1}}
			and Analytics.count("undo") == 1 and _goal_params("undo") == {"undo": {key: 1}},
			"тупик и отмена: целей %d и %d (ждали по одной)" % [Analytics.count("dead_end"), Analytics.count("undo")])
	# Подсказка: каждая, бесплатная и за рекламу.
	game.hints.give()
	_check(Analytics.count("hint") == 1 and _goal_params("hint") == {"hint": {key: "free"}},
			"бесплатная подсказка: %s" % str(Analytics.last("hint")))
	game.hints.ad_pending = true
	game.hints._on_ad_finished(true, game.session)
	_check(Analytics.count("hint") == 2 and _goal_params("hint") == {"hint": {key: "ad"}},
			"подсказка за рекламу: %s" % str(Analytics.last("hint")))
	game.hints.give()
	_check(_goal_params("hint") == {"hint": {key: "free"}},
			"бесплатная подсказка после подсказки за рекламу: %s" % str(Analytics.last("hint")))
	# «Заново» посреди уровня: итог попытки с числами и новая попытка того же уровня.
	var placed: int = game.moves.size()
	game._on_restart_pressed()
	await _frames(1)
	var want := {"undo": 2, "hint": 3, "dead": 2, "placed": "%d/%d" % [placed, total]}
	var got_restart: Dictionary = _goal_params("level_restart").get("level_restart", {}).get(key, {}).duplicate()
	var restart_time: Variant = got_restart.get("time")
	got_restart.erase("time")
	_check(got_restart == want and _is_span(restart_time),
			"«Заново»: %s, ждали %s и время интервалом" % [str(Analytics.last("level_restart")), str(want)])
	_check(Analytics.count("level_start") == 3 and _goal_params("level_start") == {"level_start": {key: "new"}},
			"после «Заново» нет новой попытки: начал %d, %s" % [Analytics.count("level_start"),
			str(Analytics.last("level_start"))])
	# Победа подсказками: звёзды, отмены и подсказки — как в игре; первого своего хода не было.
	if _solve_with_hints(game, LOGIC_LEVEL):
		var info: Dictionary = _goal_params("level_win").get("level_win", {}).get(key, {})
		var stars := GameState.get_stars(LOGIC_LEVEL)
		_check(info.get("stars", -1) == stars and info.get("hint", -1) == game.hints.used
				and info.get("undo", -1) == 0 and info.get("dead", -1) == 0 and _is_span(info.get("time"))
				and info.size() == 5 and Analytics.run_key.is_empty(),
				"победа: %s (звёзд %d, подсказок %d), попытка «%s»" % [str(info), stars, game.hints.used, Analytics.run_key])
		_check(Analytics.count("first_move") == 1, "подсказки посчитались первым ходом")
		# «Заново» после победы — не попытка; переигровка — replay.
		var restarts := Analytics.count("level_restart")
		game._on_replay_pressed()
		await _frames(1)
		_check(Analytics.count("level_restart") == restarts and Analytics.count("level_exit") == 1,
				"«Заново» из окна победы закрыло попытку: «Заново» %d, выходов %d" % [
				Analytics.count("level_restart"), Analytics.count("level_exit")])
		_check(_goal_params("level_start") == {"level_start": {key: "replay"}},
				"переигровка пройденного: %s" % str(Analytics.last("level_start")))
	# «Лаборатория» не считается: её уровень закрывает открытую попытку, своей нет.
	var lab_ok := not LabLevels.get_level(LabLevels.mechanics()[0], 1).is_empty()
	if lab_ok:
		var starts := Analytics.count("level_start")
		game.start_lab(LabLevels.mechanics()[0], 1)
		await _frames(1)
		_check(Analytics.count("level_start") == starts and Analytics.run_key.is_empty()
				and _goal_params("level_exit").get("level_exit", {}).has(key),
				"«Лаборатория»: начал %d (было %d), попытка «%s», выход %s" % [Analytics.count("level_start"), starts,
				Analytics.run_key, str(Analytics.last("level_exit"))])
		game.start_level(LOGIC_LEVEL)
		await _frames(1)
	# Уход со сцены посреди уровня — выход, блоков на поле 0.
	var exits := Analytics.count("level_exit")
	game.queue_free()
	await _frames(2)
	_check(Analytics.count("level_exit") == exits + 1 and Analytics.run_key.is_empty()
			and _goal_params("level_exit").get("level_exit", {}).get(key, {}).get("placed", "") == "0/%d" % total,
			"уход со сцены: выходов %d (ждали %d), %s" % [Analytics.count("level_exit"), exits + 1,
			str(Analytics.last("level_exit"))])

	# Задача дня: daily_* с ключом "day", в победе — серия; повтор — replay; выход — daily_exit.
	GameState.reset_progress()
	Analytics.journal.clear()
	GameState.daily_requested = true
	game = ps.instantiate() as Game
	add_child(game)
	await _frames(3)
	var day := Analytics.DAILY_KEY
	_check(game.daily_mode and _goal_params("daily_start") == {"daily_start": {day: "new"}}
			and Analytics.count("level_start") == 0, "начало задачи дня: %s" % str(Analytics.last("daily_start")))
	if _solve_with_hints(game, game.level):
		var dinfo: Dictionary = _goal_params("daily_win").get("daily_win", {}).get(day, {})
		_check(dinfo.get("streak", -1) == GameState.daily_streak and GameState.daily_streak == 1
				and dinfo.get("stars", -1) == GameState.daily_last_stars and Analytics.count("level_win") == 0,
				"победа задачи дня: %s (серия %d)" % [str(dinfo), GameState.daily_streak])
		game.start_level(game.level, true)
		await _frames(1)
		_check(_goal_params("daily_start") == {"daily_start": {day: "replay"}},
				"повтор задачи дня: %s" % str(Analytics.last("daily_start")))
	game.queue_free()
	await _frames(2)
	_check(_goal_params("daily_exit").get("daily_exit", {}).has(day) and Analytics.count("level_exit") == 0,
			"выход из задачи дня: %s" % str(Analytics.last("daily_exit")))
	GameState.reset_progress()

	# Итоги рекламы: по событиям JS (вне веба SDK нет — зовём обработчик напрямую) и по таймауту.
	_check(YSDK.ad_result(YSDK.AD_INTERSTITIAL, true, false) == "shown"
			and YSDK.ad_result(YSDK.AD_INTERSTITIAL, false, false) == "not_shown"
			and YSDK.ad_result(YSDK.AD_REWARDED, true, true) == "rewarded"
			and YSDK.ad_result(YSDK.AD_REWARDED, true, false) == "closed"
			and YSDK.ad_result(YSDK.AD_REWARDED, false, false) == "not_shown", "YSDK.ad_result: итоги рекламы")
	var last_inter: int = YSDK._last_interstitial_ms
	var got: Array = []
	var on_rew := func(rewarded: bool) -> void: got.append(rewarded)
	var on_inter := func() -> void: got.append("inter")
	var ad_cases := [
		[YSDK.AD_REWARDED, [["rew_open", null], ["rew_reward", null], ["rew_close", null]], "rewarded", true],
		[YSDK.AD_REWARDED, [["rew_open", null], ["rew_close", null]], "closed", false],
		[YSDK.AD_REWARDED, [["rew_close", null]], "not_shown", false],
		[YSDK.AD_INTERSTITIAL, [["inter_open", null], ["inter_close", true]], "shown", "inter"],
		[YSDK.AD_INTERSTITIAL, [["inter_close", false]], "not_shown", "inter"],
		[YSDK.AD_REWARDED, [], "timeout", false],
	]
	for c: Array in ad_cases:
		got.clear()
		var kind: StringName = c[0]
		YSDK._start_ad(kind, on_rew if kind == YSDK.AD_REWARDED else on_inter)
		var events: Array = c[1]
		for e: Array in events:
			YSDK._handle_event(e[0], e[1])
		if events.is_empty():
			YSDK._finish_ad("timeout")
		var goal_id := "ad_" + String(kind)
		_check(_goal_params(goal_id) == {goal_id: c[2]} and got == [c[3]] and YSDK._ad_kind == YSDK.AD_NONE,
				"реклама %s %s: цель %s, колбэк %s (ждали «%s», %s)" % [kind, str(events), str(Analytics.last(goal_id)),
				str(got), c[2], str(c[3])])
	YSDK._last_interstitial_ms = last_inter
	# Отзыв: ответ feedback → итог; запрос в этом запуске уже был — повторно не просим.
	var asked: bool = YSDK._review_requested_this_session
	var review_cases := [[{"feedbackSent": true}, "sent"], [{"feedbackSent": false}, "closed"],
			[{"value": false, "reason": "NO_AUTH"}, "no_auth"], [{"value": false, "reason": "GAME_RATED"}, "game_rated"],
			[{"value": false, "reason": "TypeError: x is undefined"}, "error"], [null, "error"]]
	for c: Array in review_cases:
		_check(YSDK.review_result(c[0]) == c[1], "отзыв %s: «%s», ждали «%s»" % [str(c[0]), YSDK.review_result(c[0]), c[1]])
	YSDK._handle_event("review", {"feedbackSent": true})
	_check(_goal_params("review") == {"review": "sent"}, "цель отзыва: %s" % str(Analytics.last("review")))
	YSDK._review_requested_this_session = asked
	Analytics.journal.clear()
	print("  интервалы, журнал; уровень: начало, первый ход, тупик и отмена по разу, подсказки, «Заново», победа, "
			+ "переигровка, выход; задача дня; «Лаборатория» не считается; навык; реклама и отзыв")


## v — интервал секунд Analytics.span ("0-3", …, "300+").
func _is_span(v: Variant) -> bool:
	if not v is String:
		return false
	var spans: Array[String] = ["0-%d" % Analytics.SPAN_EDGES[0], "%d+" % Analytics.SPAN_EDGES.back()]
	for k in range(1, Analytics.SPAN_EDGES.size()):
		spans.append("%d-%d" % [Analytics.SPAN_EDGES[k - 1], Analytics.SPAN_EDGES[k]])
	return v in spans


## Параметры последней цели goal_id в журнале Analytics ({} — не было).
func _goal_params(goal_id: String) -> Dictionary:
	return Analytics.last(goal_id).get("params", {})


## Ход из решения от текущей расстановки: {slot, rect} ({} — нет).
func _solution_slot(game: Game) -> Dictionary:
	var s := game.solve(game.placed_rects(), game.remaining_pieces())
	var rects: Array = s.solution if s.status == ShikakuSolver.SOLVED else game.level_data.solution
	return game.tray.find_move(rects, game.board)


# --- 7в. «Лаборатория» (19.3) ----------------------------------------------------

## Механики «Лаборатории» 19.3 (PLAN, этап 19.3; docs/STYLE.md, раздел 11.5): формат уровня, 40 уровней, решатель,
## правила на поле, уровень в игре до победы, экран «Лаборатории».
func _test_lab() -> void:
	_section("Механики и «Лаборатория» (19.3)")
	_test_lab_format()
	_test_lab_solver()
	await _test_lab_board()
	await _test_lab_game()
	await _test_lab_screen()
	LabLevels.done = {}
	LabLevels.requested_mechanic = ""
	LabLevels.requested_index = 0
	print("  формат и 40 уровней (у каждой механики только её метки), решатель находит эталон, правила механик в " +
			"решателе и на поле, уровень «Лаборатории» до победы без очков, «Далее» подряд, экран: карточки, ряды, " +
			"касания, ru / en / tr, альбом")


## Формат (LevelPack.decode, LabLevels): механики по порядку и по 10 уровней; у уровня механики — только её метки
## (h — препятствия, p — закреплённый блок, q — «?», t — цветные клетки), блоки — ровно формы решения; образец
## LAB_SYN читается полностью, испорченные метки LAB_BROKEN — нет; обычные уровни без меток; шапка, «Далее» по
## порядку, первый непройденный, лучший результат.
func _test_lab_format() -> void:
	var order := LabLevels.mechanics()
	_check(order == ["unknown", "holes", "tints", "pinned"], "«Лаборатория»: механики %s" % str(order))
	var tags := {"unknown": "q", "holes": "h", "tints": "t", "pinned": "p"}
	for m in order:
		_check(LabLevels.count(m) == 10 and not LabLevels.title(m).is_empty() and not LabLevels.rule(m).is_empty(),
				"«Лаборатория» %s: уровней %d, название «%s», правило «%s»" % [m, LabLevels.count(m),
				LabLevels.title(m), LabLevels.rule(m)])
		for i in range(1, LabLevels.count(m) + 1):
			var d := LabLevels.get_level(m, i)
			var tag := "«Лаборатория» %s %d" % [m, i]
			if not _check(not d.is_empty() and String(d.get("mechanic", "")) == m and int(d.get("lab_index", 0)) == i,
					"%s: уровень не читается" % tag):
				continue
			var any := 0
			for n: Dictionary in d.numbers:
				if int(n.value) == ShikakuSolver.ANY:
					any += 1
			var got := {"q": any, "h": (d.holes as Array).size(), "t": (d.tints as Array).size(),
					"p": (d.pinned as Array).size()}
			var own := true
			for k: String in got:
				own = own and ((int(got[k]) > 0) == (k == tags[m]))
			_check(own, "%s: метки механик %s (нужна только «%s»)" % [tag, str(got), tags[m]])
			var want: Array[Vector2i] = []
			for r: Rect2i in d.solution:
				want.append(ShikakuSolver.shape_key(r.size))
			var have: Array[Vector2i] = []
			for p: Vector2i in d.pieces:
				have.append(ShikakuSolver.shape_key(p))
			want.sort()
			have.sort()
			_check(want == have and (d.numbers as Array).size() == have.size(),
					"%s: блоки %s не формы решения %s" % [tag, str(have), str(want)])
	_check(LabLevels.get_level("holes", 0).is_empty() and LabLevels.get_level("holes", 11).is_empty()
			and LabLevels.get_level("nope", 1).is_empty() and LabLevels.count("nope") == 0,
			"«Лаборатория»: уровни вне 1…10 или чужой механики читаются")
	var s := LevelPack.decode(LAB_SYN)
	var syn_ok := not s.is_empty()
	if syn_ok:
		var q: Array[Vector2i] = []
		for n: Dictionary in s.numbers:
			if int(n.value) == ShikakuSolver.ANY:
				q.append(n.pos)
		var tints: Array = s.tints
		syn_ok = s.holes == [Vector2i(2, 0)] and s.pinned == [Rect2i(3, 0, 1, 2)] and q == [Vector2i(1, 2)] \
				and tints.size() == 1 and tints[0].pos == Vector2i(1, 1) and int(tints[0].value) == 4
	_check(syn_ok, "образец механик %s прочитан как %s" % [LAB_SYN, str(s)])
	var read: Array[String] = []
	for b in LAB_BROKEN:
		if not LevelPack.decode(b).is_empty():
			read.append(b)
	_check(read.is_empty(), "испорченные метки механик прочитаны: %s" % str(read))
	var plain := LevelPack.get_level(1)
	_check(not plain.is_empty() and not plain.has("holes") and not plain.has("tints") and not plain.has("pinned"),
			"обычный уровень 1 с метками механик: %s" % str(plain.keys()))
	_check(LabLevels.header("unknown", 3) == "ЧИСЛО «?» · 3/10" and LabLevels.header("pinned", 10) == "ЗАКРЕПЛЁН · 10/10",
			"шапка «Лаборатории»: «%s», «%s»" % [LabLevels.header("unknown", 3), LabLevels.header("pinned", 10)])
	var nx: Array[Dictionary] = [LabLevels.next_after("holes", 3), LabLevels.next_after("unknown", 10),
			LabLevels.next_after("pinned", 10)]
	_check(nx[0] == {"mechanic": "holes", "index": 4} and nx[1] == {"mechanic": "holes", "index": 1} and nx[2].is_empty(),
			"«Далее» в «Лаборатории»: после holes 3, unknown 10, pinned 10 — %s" % str(nx))
	LabLevels.done = {}
	var first: Array[Dictionary] = [LabLevels.first_open()]
	for i in range(1, 11):
		LabLevels.mark_done("unknown", i, 3)
	for st in [1, 3, 2]:
		LabLevels.mark_done("holes", 1, st)
	first.append(LabLevels.first_open())
	_check(first[0] == {"mechanic": "unknown", "index": 1} and first[1] == {"mechanic": "holes", "index": 2}
			and LabLevels.stars_of("holes", 1) == 3 and LabLevels.done_count("unknown") == 10
			and LabLevels.done_count("tints") == 0, "отметки «Лаборатории»: первый непройденный %s, holes 1 — %d звёзд"
			% [str(first), LabLevels.stars_of("holes", 1)])
	for m in order:
		for i in range(1, 11):
			LabLevels.mark_done(m, i, 1)
	_check(LabLevels.first_open() == {"mechanic": "unknown", "index": 1},
			"всё пройдено: первый непройденный %s (ждали unknown 1)" % str(LabLevels.first_open()))
	LabLevels.done = {}


## Решатель (ShikakuSolver.rules_of, run_level, tint_ok): правила образца; без них LAB_SYN_41 и LAB_SYN_T2 решаются,
## с ними — нет; каждый уровень «Лаборатории» с пустого поля решается ровно в эталон (решение одно — make_lab.py).
func _test_lab_solver() -> void:
	var s := LevelPack.decode(LAB_SYN)
	if not _check(not s.is_empty(), "образец механик не читается"):
		return
	var rules := ShikakuSolver.rules_of(s)
	var blocked: Array[Vector2i] = []
	blocked.assign(rules.blocked)
	blocked.sort()
	var tints: Dictionary = rules.tints
	_check(blocked == [Vector2i(2, 0), Vector2i(3, 0), Vector2i(3, 1)] and tints == {Vector2i(1, 1): 4},
			"правила образца: занято %s, цветные %s" % [str(blocked), str(tints)])
	var plain := ShikakuSolver.rules_of(LevelPack.get_level(1))
	_check((plain.blocked as Array).is_empty() and (plain.tints as Dictionary).is_empty(),
			"правила обычного уровня 1 не пустые: %s" % str(plain))
	_check(ShikakuSolver.tint_ok(Rect2i(0, 0, 2, 2), tints) and not ShikakuSolver.tint_ok(Rect2i(1, 1, 1, 2), tints)
			and ShikakuSolver.tint_ok(Rect2i(2, 1, 1, 2), tints) and ShikakuSolver.tint_ok(Rect2i(1, 1, 1, 2), {}),
			"tint_ok: цветную клетку «4» накрывает не только блок площади 4")
	var none: Array[Rect2i] = []
	var r0 := ShikakuSolver.run_level(s, none, s.pieces)
	_check(r0.status == ShikakuSolver.SOLVED and _same_rects(r0.solution, s.solution),
			"образец: решатель %d, %s (эталон %s)" % [r0.status, str(r0.solution), str(s.solution)])
	for item: Array in [[LAB_SYN_41, "4×1 через препятствие и закреплённый блок"],
			[LAB_SYN_T2, "2×2 на цветную клетку «2»"]]:
		var d := LevelPack.decode(item[0])
		if not _check(not d.is_empty(), "%s не читается" % item[0]):
			continue
		var with_rules := ShikakuSolver.run_level(d, none, d.pieces)
		var without := ShikakuSolver.run(int(d.cols), int(d.rows), d.numbers, none, d.pieces)
		_check(with_rules.status == ShikakuSolver.UNSOLVABLE and without.status == ShikakuSolver.SOLVED,
				"%s: с правилами %d, без правил %d (ждали UNSOLVABLE и SOLVED)" % [item[1], with_rules.status, without.status])
	var bad: Array[String] = []
	var worst := 0
	for m in LabLevels.mechanics():
		for i in range(1, LabLevels.count(m) + 1):
			var d := LabLevels.get_level(m, i)
			if d.is_empty():
				continue  # уже в _test_lab_format
			var r := ShikakuSolver.run_level(d, none, d.pieces)
			worst = maxi(worst, r.steps)
			if r.status != ShikakuSolver.SOLVED or not _same_rects(r.solution, d.solution):
				bad.append("%s %d (%d)" % [m, i, r.status])
	_check(bad.is_empty(), "решатель с правилами механик не пришёл к эталону: %s" % ", ".join(bad))
	print("  уровни «Лаборатории»: решатель — до %d шагов" % worst)


## Одинаковые наборы прямоугольников (порядок любой; в решении прямоугольники не повторяются).
static func _same_rects(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for r in a:
		if not b.has(r):
			return false
	return true


## Правила на поле (Board): знаки образца (препятствие, цветная клетка, закреплённый блок с заклёпками, «?»),
## rect_issue / check_rect по каждому правилу, занятые клетки, «?» подсвечивается под любой блок, поле с
## препятствием и закреплённым блоком после решения заполнено.
func _test_lab_board() -> void:
	var board_ps := load(BOARD_SCENE) as PackedScene
	var block_ps := load(BLOCK_SCENE) as PackedScene
	var data := LevelPack.decode(LAB_SYN)
	if not _check(board_ps != null and block_ps != null and not data.is_empty(), "образец механик: нет поля или уровня"):
		return
	var board := board_ps.instantiate() as Board
	add_child(board)
	board.setup(data)
	await _frames(2)
	var hole_marks := 0
	var tint_areas: Array[int] = []
	for n in board.cells_root.get_children():
		var mark := n as CellMark
		if mark == null:
			continue
		if mark.kind == CellMark.Kind.HOLE:
			hole_marks += 1
		elif mark.kind == CellMark.Kind.TINT:
			tint_areas.append(mark.area)
	var pins := board.pinned_blocks()
	var pin_ok := pins.size() == 1
	if pin_ok:
		var pb := pins[0]
		var rivets := 0
		for n in pb.get_children():
			if n is CellMark and (n as CellMark).kind == CellMark.Kind.PIN:
				rivets += 1
		pin_ok = pb.cells == Vector2i(1, 2) and pb.position == Vector2(3, 0) * Block.CELL and not pb.show_number \
				and pb.fixed_color == Palette.PINNED and rivets == 1
	_check(hole_marks == 1 and tint_areas == [4] and pin_ok, "образец на поле: препятствий %d, цветные %s, закреплённый блок %s"
			% [hole_marks, str(tint_areas), "на месте" if pin_ok else "не тот (%d)" % pins.size()])
	var q_cell: Cell = board._cells[2 * board.cols + 1]
	var four: Cell = board._cells[0]
	_check(q_cell != null and q_cell.number_label.text == "?" and q_cell.badge.visible,
			"«?» на поле: «%s»" % (q_cell.number_label.text if q_cell != null else "нет ячейки"))
	var cases: Array = [
		[Rect2i(0, 0, 2, 2), Tutorial.Issue.OK, "2×2 на 4 с цветной клеткой «4»"],
		[Rect2i(0, 0, 1, 2), Tutorial.Issue.WRONG_SIZE, "1×2 на 4"],
		[Rect2i(2, 0, 1, 2), Tutorial.Issue.BLOCKED, "1×2 на препятствие"],
		[Rect2i(3, 1, 1, 2), Tutorial.Issue.BLOCKED, "1×2 на закреплённый блок"],
		[Rect2i(1, 1, 1, 2), Tutorial.Issue.WRONG_COLOR, "1×2 на «?» через цветную клетку «4»"],
		[Rect2i(1, 2, 1, 1), Tutorial.Issue.OK, "1×1 на «?»"],
		[Rect2i(0, 2, 2, 1), Tutorial.Issue.OK, "2×1 на «?»"],
		[Rect2i(2, 1, 1, 2), Tutorial.Issue.OK, "1×2 на 2"],
	]
	var wrong: Array[String] = []
	for c: Array in cases:
		var r: Rect2i = c[0]
		var issue := board.rect_issue(r)
		if issue != int(c[1]) or board.check_rect(r) != (int(c[1]) == Tutorial.Issue.OK):
			wrong.append("%s — %d, check_rect %s (ждали %d)" % [c[2], issue, board.check_rect(r), c[1]])
	_check(wrong.is_empty(), "правила механик на поле: %s" % "; ".join(wrong))
	_check(board.is_blocked(Vector2i(2, 0)) and board.is_blocked(Vector2i(3, 1)) and not board.is_blocked(Vector2i(1, 1))
			and not board.is_blocked(Vector2i(9, 9)) and board.number_in(Rect2i(0, 2, 2, 1)) == ShikakuSolver.ANY
			and not board.can_fit_anywhere(Vector2i(4, 1)) and board.can_fit_anywhere(Vector2i(2, 2)),
			"образец: занятые клетки, число под «?» или «блок 4×1 некуда» не так")
	board.emphasize_area(3)
	_check(q_cell._emphasis == Cell.EMPHASIS_MATCH and four._emphasis == Cell.EMPHASIS_DIM,
			"блок 3 в руке: «?» и 4 подсвечены как %d и %d (ждали «подходит» и «нет»)" % [q_cell._emphasis, four._emphasis])
	board.clear_emphasis()
	for r: Rect2i in data.solution:
		var b := block_ps.instantiate() as Block
		add_child(b)
		b.cells = r.size
		board.place_block(b, r)
	await _frames(1)
	_check(board.is_full(), "образец: после решения поле с препятствием и закреплённым блоком не заполнено")
	board.queue_free()
	await _frames(1)


## Уровень «Лаборатории» в игре (Game.start_lab): запрос экрана, шапка и правило над полем, по уровню каждой механики
## до победы (у «?» — с подсказкой: 2 звезды), очки и уровень игрока не меняются, отметка — LabLevels; шапка с
## «10/10» в портрете и альбоме не ужата до предела; причины BLOCKED и WRONG_COLOR; «Далее» — следующий уровень
## без рекламы, «Заново» — тот же; переводы правил en / tr.
func _test_lab_game() -> void:
	GameState.reset_progress()
	for i in range(1, 6):
		GameState.complete_level(i, 3, 100)
	var level0 := GameState.level
	var score0 := GameState.total_score
	LabLevels.done = {}
	var ps := load(GAME_SCENE) as PackedScene
	LabLevels.requested_mechanic = "holes"
	LabLevels.requested_index = 2
	var game := ps.instantiate() as Game
	add_child(game)
	await _frames(3)
	_check(game.lab_mechanic == "holes" and game.lab_index == 2 and game.level == Game.LAB_LEVEL and not game.daily_mode
			and LabLevels.requested_mechanic.is_empty() and String(game.level_data.get("mechanic", "")) == "holes",
			"«Лаборатория»: по запросу holes 2 — «%s» %d, уровень %d" % [game.lab_mechanic, game.lab_index, game.level])
	for m in LabLevels.mechanics():
		game.start_lab(m, 1)
		await _frames(2)
		var tag := "«Лаборатория» %s 1" % m
		_check(game.header.level_label.text == LabLevels.header(m, 1) and game.coach_label.visible
				and game.coach_label.text == tr(LabLevels.rule(m)),
				"%s: шапка «%s», над полем «%s»" % [tag, game.header.level_label.text, game.coach_label.text])
		var hints := 1 if m == "unknown" else 0
		for _i in hints:
			game.hints.give()
		for _i in 80:
			if game.finished:
				break
			if _play_solution_move(game).is_empty():
				break
		var want := 2 if hints > 0 else 3
		_check(game.finished and game.board.is_full() and LabLevels.stars_of(m, 1) == want,
				"%s: победа %s, звёзд %d (ждали %d)" % [tag, game.finished, LabLevels.stars_of(m, 1), want])
		_check(GameState.level == level0 and GameState.total_score == score0 and game.hud_score() == score0
				and GameState.get_stars(Game.LAB_LEVEL) == 0,
				"%s: уровень игрока %d → %d, счёт %d → %d" % [tag, level0, GameState.level, score0, GameState.total_score])
	# Окно победы последнего прохода (pinned 1): «ДАЛЕЕ» — сразу pinned 2, без рекламы; «Заново» — снова pinned 2.
	await get_tree().create_timer(Game.WIN_SHOW_AT + WinPanel.BUTTONS_DELAY + 0.3).timeout
	var wp: WinPanel = game.win_panel
	_check(wp.visible and wp.next_button.text == "ДАЛЕЕ", "«Лаборатория»: окно победы %s, кнопка «%s»"
			% [wp.visible, wp.next_button.text])
	game._on_next_pressed()
	await _frames(2)
	_check(game.lab_mechanic == "pinned" and game.lab_index == 2 and not game.finished and game.moves.is_empty()
			and not game._next_pending and game.header.level_label.text == LabLevels.header("pinned", 2),
			"«Далее» после pinned 1: «%s» %d, окно ждёт %s" % [game.lab_mechanic, game.lab_index, game._next_pending])
	_play_solution_move(game)
	game._restart_same()
	await _frames(2)
	_check(game.lab_mechanic == "pinned" and game.lab_index == 2 and game.moves.is_empty() and game.level == Game.LAB_LEVEL,
			"«Заново» в «Лаборатории»: «%s» %d, ходов %d" % [game.lab_mechanic, game.lab_index, game.moves.size()])
	# Шапка: самые длинные названия с «10/10» не ужаты до TITLE_MIN_SIZE ни в портрете, ни в альбоме.
	var real := game.size
	for sz: Vector2 in [real, Vector2(2276, 1280)]:
		game.apply_layout(sz)
		await _frames(2)
		var squeezed: Array[String] = []
		for m in LabLevels.mechanics():
			game.header.show_values(10, score0, LabLevels.header(m, 10))
			if game.header.fitted_title_size() <= HudHeader.TITLE_MIN_SIZE:
				squeezed.append("«%s» %d" % [game.header.level_label.text, game.header.fitted_title_size()])
		_check(squeezed.is_empty(), "шапка «Лаборатории» %s: ужата до предела %s"
				% ["альбом" if game.landscape else "портрет", ", ".join(squeezed)])
	game.apply_layout(real)
	game.update_hud()
	# Причины «не встаёт» и правила механик переведены.
	var saved := TranslationServer.get_locale()
	var ru_reasons := [game.coach.reason_text(Tutorial.Issue.BLOCKED, 0), game.coach.reason_text(Tutorial.Issue.WRONG_COLOR, 0)]
	_check(not (ru_reasons[0] as String).is_empty() and not (ru_reasons[1] as String).is_empty(),
			"причины BLOCKED / WRONG_COLOR пустые: %s" % str(ru_reasons))
	for loc in ["en", "tr"]:
		TranslationServer.set_locale(loc)
		await _frames(1)
		var missing: Array[String] = []
		for m in LabLevels.mechanics():
			if tr(LabLevels.rule(m)) == LabLevels.rule(m):
				missing.append(LabLevels.rule(m))
		for k in 2:
			var issue: int = [Tutorial.Issue.BLOCKED, Tutorial.Issue.WRONG_COLOR][k]
			if game.coach.reason_text(issue, 0) == ru_reasons[k]:
				missing.append(ru_reasons[k])
		_check(missing.is_empty() and game.coach_label.text == tr(LabLevels.rule("pinned")),
				"%s: не переведено %s, над полем «%s»" % [loc, str(missing), game.coach_label.text])
	TranslationServer.set_locale(saved)
	await _frames(1)
	game.queue_free()
	await _frames(2)
	GameState.reset_progress()
	LabLevels.done = {}


## Экран «Лаборатории» (LabScreen, LabRow): карточки по механикам (название, правило, ряд из 10), отметки и звёзды
## пройденных, кружок под точкой, касание — отпускание на том же кружке, курсор; раскладка: карточки в колонне над
## пояснением, правило в две строки на ru / en / tr, «Домой» в углу; альбом — колонна по центру.
func _test_lab_screen() -> void:
	LabLevels.done = {}
	LabLevels.mark_done("holes", 2, 3)
	LabLevels.mark_done("unknown", 10, 2)
	var ps := load(LabLevels.SCENE) as PackedScene
	if not _check(ps != null, "экран «Лаборатории» не загружается"):
		return
	var lab := ps.instantiate() as LabScreen
	add_child(lab)
	lab.size = Vector2(720, 1280)
	await _frames(3)
	var order := LabLevels.mechanics()
	_check(lab.title_label.text == LabLevels.NAME and lab.cards_box.get_child_count() == order.size()
			and lab.rows.size() == order.size(), "«Лаборатория»: заголовок «%s», карточек %d"
			% [lab.title_label.text, lab.cards_box.get_child_count()])
	var rules: Array[Label] = []
	for k in mini(order.size(), lab.cards_box.get_child_count()):
		var m := order[k]
		var card := lab.cards_box.get_child(k) as CandyCard
		var title: Label = null
		var rule: Label = null
		if card != null:
			title = card.get_node_or_null("Box/Title") as Label
			rule = card.get_node_or_null("Box/Rule") as Label
		var row := lab.row_of(m)
		if rule != null:
			rules.append(rule)
		_check(title != null and rule != null and row != null and title.text == LabLevels.title(m).to_upper()
				and rule.text == LabLevels.rule(m) and row.count == LabLevels.count(m) and row.mechanic == m
				and row.get_parent() == card.get_node("Box"), "«Лаборатория»: карточка %d не %s" % [k + 1, m])
	var hr := lab.row_of("holes")
	var ur := lab.row_of("unknown")
	if not _check(hr != null and ur != null, "«Лаборатория»: нет рядов holes / unknown"):
		lab.queue_free()
		return
	_check(hr.stars[1] == 3 and hr.stars.count(0) == 9 and ur.stars[9] == 2 and lab.row_of("tints").stars.count(0) == 10,
			"«Лаборатория»: звёзды holes %s, unknown %s" % [str(hr.stars), str(ur.stars)])
	# 19.6b: кружки — картинки листа 6 (192 px в 52 px) — фильтр с mipmaps.
	_check(hr.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
			"ряд «Лаборатории»: фильтр картинок без mipmaps")
	var hit_ok := true
	for i in range(1, hr.count + 1):
		hit_ok = hit_ok and hr.index_at(hr.node_pos(i)) == i
	_check(hit_ok and hr.index_at(Vector2(-1.0, 10.0)) == 0 and hr.index_at(Vector2(hr.size.x + 1.0, 10.0)) == 0
			and hr.index_at(Vector2(10.0, hr.size.y + 1.0)) == 0, "ряд «Лаборатории»: кружок под точкой не тот")
	# Касание: переход в игру отключаем — ловим только level_pressed.
	for c: Dictionary in hr.level_pressed.get_connections():
		hr.level_pressed.disconnect(c.callable)
	var got: Array[int] = []
	hr.level_pressed.connect(func(i: int) -> void: got.append(i))
	hr._gui_input(_mouse_at(hr.node_pos(3), true))
	hr._gui_input(_mouse_at(hr.node_pos(3), false))
	hr._gui_input(_mouse_at(hr.node_pos(4), true))
	hr._gui_input(_mouse_at(hr.node_pos(5), false))
	hr.set_hovered(7)
	var hand := hr.mouse_default_cursor_shape
	hr.set_hovered(0)
	_check(got == [3] and hand == Control.CURSOR_POINTING_HAND and hr.mouse_default_cursor_shape == Control.CURSOR_ARROW,
			"ряд «Лаборатории»: касания %s (ждали [3]), курсор %d / %d" % [str(got), hand, hr.mouse_default_cursor_shape])
	lab.open_level("holes", 11)
	lab.open_level("nope", 1)
	_check(LabLevels.requested_mechanic.is_empty() and not Transition.is_busy(),
			"«Лаборатория»: уровень вне ряда открылся («%s»)" % LabLevels.requested_mechanic)
	var saved := TranslationServer.get_locale()
	for loc in ["ru", "en", "tr"]:
		TranslationServer.set_locale(loc)
		await _frames(2)
		var long: Array[String] = []
		for rule in rules:
			if rule.get_line_count() > 2 or rule.size.y > LabScreen.RULE_H + 0.5:
				long.append("«%s» — %d строки" % [rule.text, rule.get_line_count()])
		var last := lab.cards_box.get_child(lab.cards_box.get_child_count() - 1) as Control
		var cards_end := last.position.y + last.size.y + lab.cards_box.position.y + CandyCard.LIP
		_check(long.is_empty() and cards_end <= lab.note_label.position.y + 0.5 and lab.note_label.get_line_count() == 2,
				"«Лаборатория» %s: правила %s, карточки до %.0f, пояснение с %.0f (%d строк)" % [loc, str(long), cards_end,
				lab.note_label.position.y, lab.note_label.get_line_count()])
	TranslationServer.set_locale(saved)
	for sz: Vector2 in [Vector2(720, 1280), Vector2(2276, 1280)]:
		lab.size = sz
		await _frames(2)
		var cc := lab.content.position + lab.content.size * 0.5
		var hc := lab.home_button.position + lab.home_button.size * 0.5
		_check(cc.distance_to(sz * 0.5) < 1.0 and lab.content.size == Vector2(720, 1280) and hc.distance_to(Vector2(72, 84)) < 1.0,
				"«Лаборатория» %dx%d: колонна %s, «Домой» в %s" % [int(sz.x), int(sz.y),
				str(Rect2(lab.content.position, lab.content.size)), str(hc)])
	lab.queue_free()
	await _frames(1)
	LabLevels.done = {}


# --- Десктоп: раскладки, клавиши, наведение (этап 13.0) ------------------------------

## GameLayout без сцены: те же проверки, что в tools/layout_model.py (Python-двойник).
# --- 13.7. Фон ------------------------------------------------------------------

## Background (scenes/ui/background.tscn, STYLE 9): материал с background.gdshader; rect_size шейдера — размер
## узла после каждого resize (портрет, альбом); у двух экземпляров разные материалы (resource_local_to_scene:
## свет победы не переходит в другую сцену); set_win — свет LIGHT ↔ LIGHT_WIN сразу и плавно; нажатия не ловит;
## темп вихря (19.7): целый, SPEED, при «Меньше движения» — SPEED_CALM.
func _test_background() -> void:
	_section("Фон")
	var ps := load(BACKGROUND_SCENE) as PackedScene
	var bg := ps.instantiate() as Background
	if not _check(bg != null, "background.tscn: корень не Background"):
		return
	var other := ps.instantiate() as Background
	add_child(bg)
	add_child(other)
	await _frames(1)
	var mat := bg.material as ShaderMaterial
	_check(mat != null and mat.shader != null and mat.shader.resource_path.ends_with("background.gdshader"),
			"фон: материал не ShaderMaterial с background.gdshader")
	_check(bg.material != other.material, "фон: два экземпляра делят один материал")
	_check(bg.mouse_filter == Control.MOUSE_FILTER_IGNORE, "фон ловит нажатия")
	# Темп вихря: целый (TIME сбрасывается каждые 3600 с — иначе скачок узора), по настройке «Меньше движения».
	_check(is_zero_approx(fmod(Background.SPEED, 1.0)) and is_zero_approx(fmod(Background.SPEED_CALM, 1.0))
			and Background.SPEED > Background.SPEED_CALM and Background.SPEED_CALM >= 1.0,
			"фон: темп SPEED %.2f / SPEED_CALM %.2f — не целые или не SPEED > SPEED_CALM ≥ 1" % [Background.SPEED,
			Background.SPEED_CALM])
	var was_motion := GameState.reduce_motion
	GameState.reduce_motion = false
	GameState.settings_changed.emit()
	var fast := bg.get_speed()
	GameState.reduce_motion = true
	GameState.settings_changed.emit()
	var calm := bg.get_speed()
	GameState.reduce_motion = was_motion
	GameState.settings_changed.emit()
	_check(is_equal_approx(fast, Background.SPEED) and is_equal_approx(calm, Background.SPEED_CALM),
			"фон: темп вихря %.1f, при «Меньше движения» %.1f (ждали %.1f / %.1f)" % [fast, calm, Background.SPEED,
			Background.SPEED_CALM])
	bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	for sz: Vector2 in [Vector2(720, 1280), Vector2(2276, 1280), Vector2(720, 1560)]:
		bg.size = sz
		await _frames(1)
		_check(bg.get_rect_size().is_equal_approx(sz), "фон %s: шейдер знает размер %s" % [sz, bg.get_rect_size()])
	_check(is_equal_approx(bg.get_light(), Background.LIGHT) and not bg.is_win(),
			"фон: свет при запуске %.3f, ждали %.3f" % [bg.get_light(), Background.LIGHT])
	bg.set_win(true, false)
	_check(is_equal_approx(bg.get_light(), Background.LIGHT_WIN) and bg.is_win(),
			"фон: set_win(true, false) — свет %.3f, ждали %.3f" % [bg.get_light(), Background.LIGHT_WIN])
	_check(is_equal_approx(other.get_light(), Background.LIGHT), "фон: свет победы перешёл на другой экземпляр")
	bg.set_win(false)
	await get_tree().create_timer(Background.LIGHT_FADE * 0.5).timeout
	var mid := bg.get_light()
	_check(mid < Background.LIGHT_WIN - 0.001 and mid > Background.LIGHT + 0.001,
			"фон: свет не переходит плавно (%.3f на середине перехода)" % mid)
	await get_tree().create_timer(Background.LIGHT_FADE * 0.5 + 0.1).timeout
	_check(is_equal_approx(bg.get_light(), Background.LIGHT) and not bg.is_win(),
			"фон: после set_win(false) свет %.3f, ждали %.3f" % [bg.get_light(), Background.LIGHT])
	bg.queue_free()
	other.queue_free()
	await _frames(1)
	# Шторка перехода, очистка кадра и экран загрузки — средний цвет фона (#7B53E0), иначе вспышка на стыке.
	var clear: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	var splash: Color = ProjectSettings.get_setting("application/boot_splash/bg_color")
	_check(clear.is_equal_approx(Transition.COLOR) and splash.is_equal_approx(Transition.COLOR),
			"фон: цвет очистки %s / загрузки %s — не цвет шторки %s" % [clear, splash, Transition.COLOR])
	print("  фон: шейдер, размер в портрете и альбоме, свой материал у сцены, свет победы, темп вихря, цвет шторки")


func _test_layout() -> void:
	_section("Раскладки (GameLayout)")
	# Гистерезис: в альбом при ≥ 1,15, обратно при < 1,10.
	var was := false
	var seq: Array[bool] = []
	for w in [1400, 1450, 1471, 1472, 1440, 1409, 1408, 1407, 1450, 1472]:
		was = GameLayout.pick(Vector2(w, 1280), was)
		seq.append(was)
	var want: Array[bool] = [false, false, false, true, true, true, true, false, false, true]
	_check(seq == want, "гистерезис раскладки: %s, ждали %s" % [seq, want])
	_check(GameLayout.pick(Vector2.ZERO, true) and not GameLayout.pick(Vector2.ZERO, false),
			"нулевой размер экрана сменил раскладку")
	var screens: Array[Vector2] = [Vector2(720, 1280), Vector2(720, 1560), Vector2(720, 1680),
			Vector2(960, 1280), Vector2(1280, 1280), Vector2(1408, 1280), Vector2(1472, 1280),
			Vector2(1600, 1280), Vector2(1707, 1280), Vector2(2048, 1280), Vector2(2276, 1280),
			Vector2(2987, 1280), Vector2(4551, 1280)]
	var bad := 0
	for screen in screens:
		for land in [false, true]:
			var ratio := screen.x / screen.y
			if (land and ratio < GameLayout.TO_PORTRAIT) or (not land and ratio >= GameLayout.TO_LANDSCAPE):
				continue
			for msg in _layout_problems(screen, land):
				bad += 1
				if bad <= MAX_REPORTS:
					_check(false, msg)
	_check(bad == 0, "раскладки: проблем %d" % bad)
	var board16: Rect2 = GameLayout.compute(Vector2(2276, 1280), true).board
	_check(is_equal_approx(board16.size.x, GameLayout.BOARD_MAX),
			"16:9: поле %s, ждали %.0f" % [board16.size, GameLayout.BOARD_MAX])
	print("  раскладки: %d экранов, гистерезис 1,15 / 1,10" % screens.size())


## Список нарушений раскладки land на экране screen (пустой — всё хорошо).
func _layout_problems(screen: Vector2, land: bool) -> Array[String]:
	var res: Array[String] = []
	var l := GameLayout.compute(screen, land)
	var tag := "%dx%d %s" % [screen.x, screen.y, "альбом" if land else "портрет"]
	# С 13.2a лоток окружён корпусом полки (shelf): на перекрытия проверяем полку, а не ряд гнёзд.
	var keys: Array[String] = ["top_bar", "board", "remaining", "actions", "shelf"]
	var area := Rect2(Vector2.ZERO, screen).grow(0.01)
	for k in keys + ["tray", "toast"]:
		_place_ok(res, area.encloses(l[k]), "%s: %s %s вылезает за экран" % [tag, k, l[k]])
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if not land and keys[i] == "remaining" and keys[j] == "actions":
				continue  # в портрете подпись стоит между кнопками внутри полосы ActionsBar
			var a: Rect2 = l[keys[i]]
			var b: Rect2 = l[keys[j]]
			_place_ok(res, not a.grow(-0.01).intersects(b.grow(-0.01)), "%s: %s и %s перекрываются" % [tag, keys[i], keys[j]])
	var slot: Vector2 = l.slot
	var sep := float(l.separation)
	var need := Vector2(slot.x, slot.y * 3.0 + sep * 2.0) if l.vertical else Vector2(slot.x * 3.0 + sep * 2.0, slot.y)
	var tray: Rect2 = l.tray
	_place_ok(res, need.x <= tray.size.x + 0.01 and need.y <= tray.size.y + 0.01,
			"%s: гнёзда %s не влезают в лоток %s" % [tag, need, tray.size])
	var shelf: Rect2 = l.shelf
	var pad := float(l.shelf_pad)
	_place_ok(res, shelf.position.is_equal_approx(tray.position - Vector2(pad, pad))
			and shelf.size.is_equal_approx(tray.size + Vector2(2.0, 2.0) * pad),
			"%s: полка %s — не лоток %s + отступ %.0f" % [tag, shelf, tray, pad])
	if land:
		var board: Rect2 = l.board
		_place_ok(res, is_equal_approx(board.size.x, board.size.y), "%s: поле не квадрат" % tag)
		_place_ok(res, board.size.x >= 676.0, "%s: поле %.0f меньше портретного 676" % [tag, board.size.x])
	_win_layout_problems(res, l, screen, tag)
	return res


## Победа (13.5b): заголовок, поле и карточка с губой — на экране; карточка 512×428; звёзды на кромке
## карточки (зона WIN_STARS над ней) не заходят на поле и заголовок; в портрете строка заголовка (середина
## + половина размера) выше поля; в альбоме поле на месте, заголовок и карточка — в столбике справа.
func _win_layout_problems(res: Array[String], l: Dictionary, screen: Vector2, tag: String) -> void:
	var area := Rect2(Vector2.ZERO, screen).grow(0.01)
	var title: Rect2 = l.win_title
	var wb: Rect2 = l.win_board
	var card: Rect2 = l.win_card
	var stars := Rect2(card.position.x, card.position.y - GameLayout.WIN_STARS, card.size.x, GameLayout.WIN_STARS)
	for pair in [["win_title", title], ["win_board", wb], ["win_card + губа", card.grow_side(SIDE_BOTTOM, CandyCard.LIP)]]:
		_place_ok(res, area.encloses(pair[1]), "%s: %s %s вылезает за экран" % [tag, pair[0], pair[1]])
	_place_ok(res, card.size.is_equal_approx(GameLayout.WIN_CARD), "%s: карточка победы %s" % [tag, card.size])
	_place_ok(res, not wb.grow(-0.01).intersects(stars), "%s: поле победы %s заходит на звёзды карточки" % [tag, wb])
	_place_ok(res, not title.grow(-0.01).intersects(stars) and not title.grow(-0.01).intersects(card),
			"%s: заголовок победы %s заходит на карточку" % [tag, title])
	if l.landscape:
		_place_ok(res, wb.is_equal_approx(l.board), "%s: в альбоме поле на победе сдвинулось" % tag)
		var col := wb.end.x + GameLayout.SIDE_GAP - 0.01
		_place_ok(res, title.position.x >= col and card.position.x >= col, "%s: заголовок или карточка победы не в столбике" % tag)
	else:
		_place_ok(res, title.get_center().y + l.win_title_size * 0.5 <= wb.position.y + 0.01,
				"%s: строка заголовка победы заходит на поле %s" % [tag, wb])
		_place_ok(res, wb.size.y >= 400.0, "%s: поле победы низкое (%.0f)" % [tag, wb.size.y])


func _place_ok(res: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		res.append(msg)


## Desktop.key_pressed: клавиша по месту (physical_keycode), а не по букве раскладки.
func _test_keys() -> void:
	_section("Клавиши по месту на клавиатуре")
	var ru_r := _key(KEY_R, 0x041A)  # русская раскладка: на месте R буква «К»
	_check(Desktop.key_pressed(ru_r, KEY_R), "R в русской раскладке не распознана")
	_check(not Desktop.key_pressed(_key(KEY_Q, KEY_R), KEY_R), "буква R на чужом месте (AZERTY и т. п.) сработала как R")
	_check(Desktop.key_pressed(_key(KEY_NONE, KEY_H), KEY_H), "клавиша без физического кода не распознана по keycode")
	var echo := _key(KEY_Z, KEY_Z)
	echo.echo = true
	_check(not Desktop.key_pressed(echo, KEY_Z), "автоповтор клавиши засчитан как нажатие")
	var up := _key(KEY_Z, KEY_Z)
	up.pressed = false
	_check(not Desktop.key_pressed(up, KEY_Z), "отпускание клавиши засчитано как нажатие")
	_check(not Desktop.key_pressed(InputEventMouseButton.new(), KEY_Z), "не клавиша засчитана как клавиша")
	print("  клавиши по physical_keycode")


func _key(physical: Key, code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = physical
	k.keycode = code as Key
	k.pressed = true
	return k


## «Без эффектов» (14.8a): списки JuiceConfig.OFF / KEEP_ON_OFF покрывают все числа ровно по разу (новое число без
## решения — ошибка здесь и в tools/check_gd.py); set_effects_off(true) ставит OFF и не трогает KEEP_ON_OFF, повтор —
## ничего; без эффектов нет частиц, конфетти, тряски и hit-stop; set_effects_off(false) возвращает ровно прежние числа
## (и изменённые руками до выключения); F5 — только при показанном счётчике кадров, в нём «эффекты: выкл.».
## Прогон уровня целиком в режимах — 14.8b.
func _test_effects_off(game: Game) -> void:
	_section("Без эффектов (14.8a)")
	var cfg := Juice.shared_config()
	var errs := cfg.off_list_errors()
	_check(errs.is_empty(), "списки «без эффектов»: %s" % "; ".join(errs))
	if not _check(not cfg.effects_off(), "эффекты выключены с запуска"):
		cfg.set_effects_off(false)
	var names := cfg.number_names()
	_check(names.size() == JuiceConfig.OFF.size() + JuiceConfig.KEEP_ON_OFF.size() and names.size() > 100,
			"чисел конфига %d, в OFF %d, в KEEP_ON_OFF %d" % [names.size(), JuiceConfig.OFF.size(),
			JuiceConfig.KEEP_ON_OFF.size()])
	_check(Juice.shared_config() == cfg and Block.cfg() == cfg, "у Juice и Block — разные ресурсы чисел")
	var confetti_was := game.win_backdrop.confetti.default_count()
	# Число, изменённое руками до выключения, тоже возвращается.
	var land_was := cfg.land_time
	cfg.land_time = 0.5
	var before := {}
	for n in names:
		before[n] = cfg.get(n)
	cfg.set_effects_off(true)
	var bad: Array[String] = []
	for n in names:
		var want: Variant = JuiceConfig.OFF[n] if JuiceConfig.OFF.has(n) else before[n]
		if not _same_value(cfg.get(n), want):
			bad.append(String(n))
	_check(cfg.effects_off() and bad.is_empty(), "без эффектов: не те числа %s" % [bad])
	cfg.set_effects_off(true)
	_check(cfg.effects_off() and is_equal_approx(cfg.land_time, 0.0), "повторное set_effects_off(true) что-то сменило")
	# Без эффектов — ни частиц, ни конфетти, ни тряски, ни hit-stop (а события засчитаны, как обычно).
	var juice := game.juice
	var counts_was := juice.counts.duplicate()
	var power_was := juice.last_power
	var was_motion := GameState.reduce_motion
	GameState.set_reduce_motion(false)
	juice.reset()
	var at := Vector2(360, 640)
	var p1 := juice.burst(Juice.SPARKS, at, Color.WHITE, 40)
	juice.event(&"line", at)
	juice.landed(Rect2(at, Vector2(160, 80)), Vector2i(2, 1), Color.WHITE)
	var rects: Array[Rect2] = [Rect2(at, Vector2(400, 80))]
	var lens: Array[int] = [5]
	juice.lines(rects, lens, 3)
	_check(p1 == null and juice.live_particles() == 0, "без эффектов: частиц в воздухе %d" % juice.live_particles())
	_check(is_zero_approx(juice.trauma) and not juice.is_stopped(), "без эффектов: тряска %.2f, hit-stop %s" % [
			juice.trauma, juice.is_stopped()])
	_check(game.win_backdrop.confetti.default_count() == 0, "без эффектов: конфетти %d" %
			game.win_backdrop.confetti.default_count())
	juice.reset()
	juice.counts = counts_was
	juice.last_power = power_was
	GameState.set_reduce_motion(was_motion)
	cfg.set_effects_off(false)
	bad.clear()
	for n in names:
		if not _same_value(cfg.get(n), before[n]):
			bad.append(String(n))
	_check(not cfg.effects_off() and bad.is_empty() and is_equal_approx(cfg.land_time, 0.5),
			"эффекты вернулись не теми числами %s" % [bad])
	cfg.set_effects_off(false)
	cfg.land_time = land_was
	_check(game.win_backdrop.confetti.default_count() == confetti_was, "конфетти после возврата эффектов: %d (было %d)"
			% [game.win_backdrop.confetti.default_count(), confetti_was])
	# F5: только при показанном счётчике кадров; в счётчике — «эффекты: выкл.»; второй F5 — вернуть.
	var meter := Quality.meter
	if _check(meter != null, "счётчика кадров нет"):
		var shown := meter.visible
		meter.set_shown(false)
		Quality._input(_key(KEY_F5, KEY_F5))
		_check(not cfg.effects_off(), "F5 без счётчика выключил эффекты")
		meter.set_shown(true)
		_check(not meter.meter_text().contains("эффекты"), "в счётчике «эффекты» при включённых эффектах")
		Quality._input(_key(KEY_F5, KEY_F5))
		_check(cfg.effects_off() and meter.meter_text().ends_with(" · эффекты: выкл."),
				"F5: эффекты %s, текст «%s»" % ["выкл." if cfg.effects_off() else "вкл.", meter.meter_text()])
		Quality._input(_key(KEY_F5, KEY_F5))
		_check(not cfg.effects_off() and not meter.meter_text().contains("эффекты"),
				"второй F5 не вернул эффекты (текст «%s»)" % meter.meter_text())
		meter.set_shown(shown)
	cfg.set_effects_off(false)


## «Эффекты не держат логику» (14.8b): один сценарий уровня LOGIC_LEVEL с чистого прогресса (_play_logic_level) в
## четырёх режимах LOGIC_MODES — обычный; «Меньше движения» + низкое качество; без эффектов (14.8a); эффекты заморожены
## (hit-stop на LOGIC_FREEZE_SEC с первого кадра — ни один эффект не доигрывает). Итоги во всех режимах одинаковы:
## очки уровня, звёзды, общий счёт, ходов, отмен, подсказок и сам путь ходов. В --quick — два последних режима.
## 14.8c: в том же сценарии — пробы ввода (_probe_input) в тот же кадр после каждого события и в разгар эффектов;
## перед сценарием — проба в покое (_probe_calm): доходят ли настоящие нажатия вообще.
func _test_effects_logic(game: Game) -> void:
	_section("Эффекты и логика (14.8)")
	var t0 := Time.get_ticks_msec()
	var cfg := Juice.shared_config()
	var was_motion := GameState.reduce_motion
	var max_was := cfg.hitstop_max
	var modes: Array[int] = [0, 1, 2, 3]
	if _quick:
		modes = [2, 3]
	var results := {}
	var took := {}
	var infos := {}
	await _probe_calm(game)
	for mode in modes:
		var tag := "14.8, %s" % LOGIC_MODES[mode]
		GameState.set_reduce_motion(mode == 1)
		Quality.set_level(Quality.LOW if mode == 1 else Quality.HIGH)
		cfg.set_effects_off(mode == 2)
		cfg.hitstop_max = LOGIC_FREEZE_SEC if mode == 3 else max_was
		await _frames(2)  # низкое качество меняет разрешение 2D — раскладка успевает пересчитаться
		var info := {}
		# 15.6: звуки уровня — кроме «эффекты заморожены» (удары блоков там ждут конца hit-stop).
		var listen := mode != 3
		_sound_log.clear()
		if listen:
			Audio.requested.connect(_on_test_sound)
		results[mode] = await _play_logic_level(game, tag, mode == 3, info)
		if listen:
			Audio.requested.disconnect(_on_test_sound)
			if not (results[mode] as Dictionary).is_empty():
				_check_level_sounds(tag, int((results[mode] as Dictionary).get("звёзды", 0)))
		took[mode] = info.get("next_after", -1.0)
		infos[mode] = info
		cfg.hitstop_max = max_was
		game.juice.reset()
	cfg.set_effects_off(false)
	GameState.set_reduce_motion(was_motion)
	Quality.set_level(Quality.HIGH)
	await _frames(2)
	# Сверка итогов с первым режимом.
	var ref_mode: int = modes[0]
	var ref: Dictionary = results[ref_mode]
	for mode in modes:
		var res: Dictionary = results[mode]
		if mode == ref_mode or res.is_empty() or ref.is_empty():
			continue
		for key: String in ref:
			_check(str(res.get(key)) == str(ref[key]), "14.8: %s — «%s» %s, а в режиме «%s» — %s" % [key,
					LOGIC_MODES[mode], str(res.get(key)), LOGIC_MODES[ref_mode], str(ref[key])])
	GameState.reset_progress()
	var times := ""
	for mode in modes:
		times += " %.2f" % float(took[mode])
	print("  эффекты и логика: уровень %d в %d режимах — %s; «Далее» через%s с; %d мс" % [LOGIC_LEVEL, modes.size(),
			"очки %s, звёзды %s, ходов %s" % [ref.get("очки уровня"), ref.get("звёзды"), ref.get("ходов")]
			if not ref.is_empty() else "итогов нет", times, Time.get_ticks_msec() - t0])
	_check_probes(modes, infos)


## 14.8c, итоги проб ввода по режимам (info из _play_logic_level): в обычном и замороженном режимах пробы застали
## все эффекты из списка (иначе «в разгар» не проверен), под заморозкой каждая проба — под hit-stop.
func _check_probes(modes: Array[int], infos: Dictionary) -> void:
	var need: Array[String] = ["«+очки»", "линия", "сообщение", "искра подсказки", "поле темнеет", "лучи", "конфетти"]
	var total := 0
	var stopped := 0
	var bad := 0
	var seen_all: Dictionary = {}
	for mode in modes:
		var info: Dictionary = infos.get(mode, {})
		var n := int(info.get("проб", 0))
		total += n
		stopped += int(info.get("под hit-stop", 0))
		bad += int(info.get("сбоев", 0))
		var seen: Dictionary = info.get("эффекты", {})
		seen_all.merge(seen)
		if mode == 0 or mode == 3:
			var missed: Array[String] = []
			for kind in need:
				if not seen.has(kind):
					missed.append(kind)
			_check(missed.is_empty(), "14.8c, %s: пробы ввода не застали эффекты: %s" % [LOGIC_MODES[mode],
					", ".join(missed)])
		if mode == 3:
			_check(n > 0 and int(info.get("под hit-stop", 0)) == n, "14.8c, %s: под hit-stop %d проб из %d"
					% [LOGIC_MODES[mode], int(info.get("под hit-stop", 0)), n])
	var kinds: Array[String] = []
	for kind: String in seen_all:
		kinds.append(kind)
	print("  ввод не ждёт эффектов: %d проб в тот же кадр (под hit-stop %d, с ошибкой %d)%s; блоки лотка, «Отмена»,"
			% [total, stopped, bad, "" if _probe_push else ", без настоящих нажатий"]
			+ " «Подсказка», «Далее»; застали: %s" % ", ".join(kinds))


## Сценарий 14.8b на уровне LOGIC_LEVEL с чистого прогресса: ход игрока через drag.dropped сразу после старта (блоки ещё
## выезжают); подсказка (бесплатная); тупиковый ход и отмена; остальное — по решению (решатель от текущего поля);
## победа засчитана в кадр последнего хода; «Далее» включается через win_at + BUTTONS_DELAY (допуск +0,25 с) и
## открывает следующий уровень. frozen — hit-stop на весь уровень (после start_level: он гасит hit-stop).
## Ответ — итоги для сверки режимов ({} — сценарий оборвался); info.next_after — через сколько секунд включилась «Далее».
## 14.8c: после каждого события — проба ввода в тот же кадр (_probe_input; счёт проб и застанные эффекты — в info),
## а в разгар тупика (до 0,8 с, пока поле не потемнеет) и первой линии (до 0,5 с, пока не пойдёт волна) — ещё раз.
func _play_logic_level(game: Game, tag: String, frozen: bool, info: Dictionary) -> Dictionary:
	GameState.reset_progress()
	game.start_level(LOGIC_LEVEL)
	if frozen:
		game.juice.hit_stop(LOGIC_FREEZE_SEC)
		_check(game.juice.is_stopped(), "%s: hit-stop на весь уровень не включился" % tag)
	var tray := game.tray
	var board := game.board
	var pieces := (game.level_data.pieces as Array).size()
	var path: Array[String] = []
	# 1. Ход сразу после старта — без ожидания появления.
	var m := tray.find_move(game.level_data.solution, board)
	if not _check(not m.is_empty(), "%s: в лотке нет блока для хода из решения" % tag):
		return {}
	_drop(game, int(m.slot), m.rect)
	path.append(str(m.rect))
	_check(game.moves.size() == 1 and not game.has_mistake(), "%s: ход сразу после старта не засчитан (ходов %d)" % [tag,
			game.moves.size()])
	_probe_input(game, tag, "ход сразу после старта", info, true)
	# 2. Подсказка.
	game.hints.request()
	if _check(game.moves.size() == 2 and game.hints.used == 1, "%s: подсказка не поставила блок (ходов %d, подсказок %d)"
			% [tag, game.moves.size(), game.hints.used]):
		path.append("подсказка " + str(game.moves.back().rect))
	_probe_input(game, tag, "подсказка", info, true)
	# 3. Ошибка (20.1a): тупиковый ход не засчитан, сердце сгорело; блок возвращается в гнездо (здесь — сразу,
	# как от нажатия на лоток: при hit-stop на весь уровень таймер возврата не ждём).
	var mv := _find_dead_end_move(game)
	if _check(not mv.is_empty(), "%s: тупикового хода нет" % tag):
		var before := game.moves.size()
		_drop(game, int(mv[0]), mv[1])
		_check(game.has_mistake() and game.moves.size() == before and game.hearts.mistakes == 1,
				"%s: тупиковый ход %s не стал ошибкой (ходов %d, ошибок %d)" % [tag, str(mv[1]), game.moves.size(),
				game.hearts.mistakes])
		path.append("ошибка " + str(mv[1]))
		_probe_input(game, tag, "тупиковый ход", info, true)
		# В разгар тупика: через 0,45 с — звук ошибки, поле темнеет, трещина (без эффектов не темнеет — ждём до 0,8 с).
		# Проба с нажатием (_probe_push) уже вернула блок в гнездо (нажатие на лоток — flush_mistake): тогда поле не
		# темнеет, ждём 0,8 с — это тоже проверка, что ввод после ошибки не ломается.
		var dead_ms := Time.get_ticks_msec()
		while game.board.dimmed() <= 0.0 and Time.get_ticks_msec() < dead_ms + 800:
			await get_tree().process_frame
		_probe_input(game, tag, "тупик через %.2f с" % ((Time.get_ticks_msec() - dead_ms) / 1000.0), info, true)
		game.flush_mistake()
		_check(not game.has_mistake() and game.moves.size() == before and game.hearts.mistakes == 1,
				"%s: ошибочный блок не вернулся (ходов %d, ошибок %d)" % [tag, game.moves.size(), game.hearts.mistakes])
		_probe_input(game, tag, "блок вернулся", info, true)
	# 4. Остальное — по решению от текущего поля; победа — в кадр последнего хода. 14.8c: пока линии не было — ход,
	# закрывающий линию (не последний), если такой есть в лотке; после него ждём волну линии и пробуем ввод в её разгар.
	var last_ms := 0
	var line_done := false
	for _i in pieces + 4:
		if game.finished:
			break
		var sv := game.solve(game.placed_rects(), game.remaining_pieces())
		var rects: Array = sv.solution if sv.status == ShikakuSolver.SOLVED else game.level_data.solution
		var mm: Dictionary = {}
		if not line_done and game.moves.size() + 1 < pieces:
			var placed := game.placed_rects()
			var closing: Array = []
			for item in rects:
				var q: Rect2i = item
				if not placed.has(q) and _lines_closed(board, placed, q) > 0:
					closing.append(q)
			mm = tray.find_move(closing, board)
		if mm.is_empty():
			mm = tray.find_move(rects, board)
		if not _check(not mm.is_empty(), "%s: ход %d — в лотке нет блока из решения" % [tag, game.moves.size() + 1]):
			return {}
		var flashes := _line_flashes(board).size()
		last_ms = Time.get_ticks_msec()
		_drop(game, int(mm.slot), mm.rect)
		path.append(str(mm.rect))
		var lines := int(game.moves.back().get("lines", 0))
		if game.finished:
			_probe_input(game, tag, "последний ход (победа)", info, false)
			continue
		_probe_input(game, tag, "ход %d%s" % [game.moves.size(), ", линия" if lines > 0 else ""], info, true)
		if lines > 0 and not line_done:
			line_done = true
			var line_until := Time.get_ticks_msec() + 500
			while _line_flashes(board).size() <= flashes and Time.get_ticks_msec() < line_until:
				await get_tree().process_frame
			_probe_input(game, tag, "линия, в разгар", info, true)
	_check(line_done, "%s: до последнего хода ни один ход не закрыл линию — проба в разгар линии не сделана" % tag)
	if not _check(game.finished and board.is_full() and game.moves.size() == pieces,
			"%s: уровень не пройден (ходов %d из %d)" % [tag, game.moves.size(), pieces]):
		return {}
	var res := {"очки уровня": GameState.get_best(LOGIC_LEVEL), "звёзды": GameState.get_stars(LOGIC_LEVEL),
			"общий счёт": GameState.total_score, "ходов": game.moves.size(), "ошибок": game.hearts.mistakes,
			"подсказок": game.hints.used, "путь": " ".join(path)}
	# Звёзды (20.1a, Hearts.stars): 3 − 1 ошибка − 1 подсказка = 1.
	_check(GameState.level == LOGIC_LEVEL + 1 and int(res["звёзды"]) == 1 and int(res["очки уровня"]) > 0
			and int(res["общий счёт"]) == int(res["очки уровня"]),
			"%s: победа не засчитана в кадр последнего хода (уровень %d, звёзды %d, очки %d, счёт %d)" % [tag,
			GameState.level, int(res["звёзды"]), int(res["очки уровня"]), int(res["общий счёт"])])
	# «Далее» — через win_at + BUTTONS_DELAY от последнего хода (допуск +0,25 с; раньше — не больше чем на кадр-другой).
	var wp := game.win_panel
	var want := game.win_at + WinPanel.BUTTONS_DELAY
	var limit_ms := last_ms + int((want + 1.0) * 1000.0)
	while not (wp.visible and not wp.next_button.disabled) and Time.get_ticks_msec() < limit_ms:
		await get_tree().process_frame
	var after := (Time.get_ticks_msec() - last_ms) / 1000.0
	info["next_after"] = after
	if not _check(wp.visible and not wp.next_button.disabled, "%s: «Далее» не включилась за %.2f с" % [tag, after]):
		return res
	_check(after >= want - 0.2 and after <= want + 0.25, "%s: «Далее» включилась через %.2f с (ждали %.2f, допуск +0,25)"
			% [tag, after, want])
	_probe_input(game, tag, "окно победы, «Далее» включилась", info, false, wp.next_button)
	if frozen:
		_check(game.juice.is_stopped(), "%s: hit-stop кончился до конца уровня — эффекты не были заморожены" % tag)
	wp.next_button.pressed.emit()
	for _i in 10:
		if game.level == LOGIC_LEVEL + 1:
			break
		await get_tree().process_frame
	_check(game.level == LOGIC_LEVEL + 1 and not game.finished and not wp.visible,
			"%s: «Далее» не открыл уровень %d (сейчас %d, окно видно: %s)" % [tag, LOGIC_LEVEL + 1, game.level, wp.visible])
	if frozen:
		_check(not game.juice.is_stopped(), "%s: новый уровень начался под hit-stop" % tag)
	return res


# --- 14.8c: ввод не ждёт эффектов ----------------------------------------------------

## Проба в покое: уровень LOGIC_LEVEL доиграл появление, эффектов нет — настоящее нажатие (Viewport.push_input)
## доходит до каждого блока лотка и до «Подсказки». Не дошло — сломан ввод или такие нажатия в этом запуске не
## работают: тогда в сценарии пробы — без настоящих нажатий (логика и Control поверх), а здесь [FAIL].
func _probe_calm(game: Game) -> void:
	GameState.reset_progress()
	game.start_level(LOGIC_LEVEL)
	await get_tree().create_timer(_intro_end() + 0.2).timeout
	game.juice.reset()
	_probe_push = true
	var problems: Array[String] = []
	for i in game.tray.blocks.size():
		if game.tray.blocks[i] == null:
			continue
		_push_press(game.tray.slots[i])
		var took := game.drag._press_slot == i
		game.drag._press_slot = -1
		_push_release()
		if not took:
			problems.append("блок в гнезде %d%s" % [i, _over_text(game.tray.slots[i])])
	if not _press_reaches(game.hint_button):
		problems.append("«Подсказка»%s" % _over_text(game.hint_button))
	var stray := _stray_catchers(game)
	if not _check(problems.is_empty() and stray.is_empty(), "14.8c, в покое: нажатие (Viewport.push_input) не дошло до: %s%s"
			% [", ".join(problems), "; ловят нажатия: " + ", ".join(stray) if not stray.is_empty() else ""]):
		_probe_push = problems.is_empty()
	GameState.reset_progress()


## Проба ввода в этот кадр (без await): что не так — _input_problems; play — уровень идёт (лоток, «Отмена» и
## «Подсказка» должны принимать нажатия), extra — ещё кнопка, до которой должно дойти нажатие («Далее»). В info:
## проб, под hit-stop, сбоев и эффекты {вид: в скольких пробах застали} (_alive_effects). Сбои — не больше
## MAX_REPORTS строк [FAIL] на режим, остальные только считаются.
func _probe_input(game: Game, tag: String, when: String, info: Dictionary, play: bool, extra: BaseButton = null) -> void:
	var problems := _input_problems(game, play, extra)
	info["проб"] = int(info.get("проб", 0)) + 1
	if game.juice.is_stopped():
		info["под hit-stop"] = int(info.get("под hit-stop", 0)) + 1
	var seen: Dictionary = info.get("эффекты", {})
	for kind in _alive_effects(game):
		seen[kind] = int(seen.get(kind, 0)) + 1
	info["эффекты"] = seen
	if problems.is_empty():
		_check(true, "")
		return
	var n := int(info.get("сбоев", 0)) + 1
	info["сбоев"] = n
	if n <= MAX_REPORTS:
		_check(false, "%s, %s: ввод ждёт эффектов — %s" % [tag, when, "; ".join(problems)])
	else:
		_fails += 1
		_checks += 1


## Что мешает вводу сейчас (пусто — ничего). play: каждое гнездо с блоком берёт нажатие (DragController._press_slot —
## нажатие сразу снимается, без поворота и перетаскивания), «Отмена» и «Подсказка» сработали бы (can_undo, can_request,
## кнопка не выключена) и нажатие доходит до них (их gui_input; отпускание — мимо кнопки, она не срабатывает).
## Всегда: шторки нет и в игре нет Control поверх, ловящего нажатия (_stray_catchers).
func _input_problems(game: Game, play: bool, extra: BaseButton = null) -> Array[String]:
	var res: Array[String] = []
	if Transition.is_busy():
		res.append("шторка перехода закрывает экран")
	if play:
		var tray := game.tray
		var blocks := 0
		for i in tray.blocks.size():
			if tray.blocks[i] == null:
				continue
			blocks += 1
			if not _probe_push:
				if game.finished or game.drag.is_busy():
					res.append("блок в гнезде %d не взять (уровень кончился: %s, блок в руке: %s)" % [i, game.finished,
							game.drag.is_busy()])
				continue
			_push_press(tray.slots[i])
			var took := game.drag._press_slot == i
			game.drag._press_slot = -1
			_push_release()
			if not took:
				res.append("нажатие на блок в гнезде %d не взято%s" % [i, _over_text(tray.slots[i])])
		if blocks == 0:
			res.append("в лотке нет блоков")
		if not game.can_play():
			res.append("ходить нельзя (сердца кончились: %s, уровень кончился: %s)" % [game.hearts.is_out(),
					game.finished])
		if not game.hints.can_request() or game.hint_button.disabled:
			res.append("«Подсказка» не сработала бы (can_request: %s, кнопка выключена: %s)" % [game.hints.can_request(),
					game.hint_button.disabled])
		elif _probe_push and not _press_reaches(game.hint_button):
			res.append("нажатие не дошло до «Подсказки»%s" % _over_text(game.hint_button))
	if extra != null:
		if extra.disabled or not extra.is_visible_in_tree():
			res.append("«%s» выключена или не видна" % extra.name)
		elif _probe_push and not _press_reaches(extra):
			res.append("нажатие не дошло до «%s»%s" % [extra.name, _over_text(extra)])
	for path in _stray_catchers(game):
		res.append("ловит нажатия: " + path)
	return res


## Середина target в координатах окна (как у событий мыши после растяжения).
func _probe_point(target: Control) -> Vector2:
	return target.get_global_transform_with_canvas() * (target.size * 0.5)


## Нажатие ЛКМ в середину target настоящим событием: Viewport.push_input — сначала _input (Game, Quality), потом GUI
## (Control под точкой). _probe_hits — сколько нажатий дошло до gui_input самого target.
func _push_press(target: Control) -> void:
	var at := _probe_point(target)
	_probe_hits = 0
	target.gui_input.connect(_on_probe_input)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.pressed = true
	ev.position = at
	ev.global_position = at
	get_viewport().push_input(ev, true)
	target.gui_input.disconnect(_on_probe_input)


func _on_probe_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_probe_hits += 1


## Отпускание после _push_press — мимо всего: сначала движение с зажатой кнопкой за край (кнопка, которую нажали,
## перестаёт считать нажатие своим), потом отпускание там же; фокус клавиатуры, взятый нажатием, — снять.
func _push_release() -> void:
	var away := Vector2(-100.0, -100.0)
	var mm := InputEventMouseMotion.new()
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm.position = away
	mm.global_position = away
	get_viewport().push_input(mm, true)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = away
	ev.global_position = away
	get_viewport().push_input(ev, true)
	get_viewport().gui_release_focus()


## Нажатие в середину target до него доходит (кнопка при этом не срабатывает — см. _push_release).
func _press_reaches(target: Control) -> bool:
	_push_press(target)
	var got := _probe_hits > 0
	_push_release()
	return got


## Видимые Control игры, которые ловят нажатия (mouse_filter не IGNORE), а не должны: всё, кроме кнопок, гнёзд лотка,
## окон победы и паузы (с тем, что в них), и контейнеров, в которых они лежат. Пути — от game.
func _stray_catchers(game: Game) -> Array[String]:
	var roots: Array[Control] = []
	roots.append_array(game.tray.slots)
	roots.append(game.win_panel)
	roots.append(game.pause_panel)
	for node in game.find_children("*", "BaseButton", true, false):
		roots.append(node as Control)
	var res: Array[String] = []
	_collect_catchers(game, game, roots, res)
	return res


func _collect_catchers(node: Node, game: Game, roots: Array[Control], res: Array[String]) -> void:
	for child in node.get_children():
		if child is Viewport:
			continue  # у SubViewport свой ввод
		var ci := child as CanvasItem
		if ci != null and not ci.is_visible_in_tree():
			continue
		var c := child as Control
		if c != null and roots.has(c):
			continue
		if c != null and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			var holder := false
			for r in roots:
				if c.is_ancestor_of(r):
					holder = true
					break
			if not holder:
				res.append(str(game.get_path_to(c)))
		_collect_catchers(child, game, roots, res)


## Для сообщения об ошибке: какие ещё Control (вся сцена) под серединой target ловят нажатия — « (под точкой: …)».
func _over_text(target: Control) -> String:
	var at := _probe_point(target)
	var found: Array[String] = []
	for node in get_tree().root.find_children("*", "Control", true, false):
		var c := node as Control
		if c == target or c.is_ancestor_of(target) or c.mouse_filter == Control.MOUSE_FILTER_IGNORE \
				or not c.is_visible_in_tree():
			continue
		var local: Vector2 = c.get_global_transform_with_canvas().affine_inverse() * at
		if Rect2(Vector2.ZERO, c.size).has_point(local):
			found.append(str(c.get_path()).trim_prefix("/root/"))
	if found.is_empty():
		return " (поверх ничего не нашлось)"
	return " (под точкой ещё: %s)" % ", ".join(found.slice(0, 4))


## Какие эффекты сейчас идут (для сообщения, что пробы ввода застали их в разгаре).
func _alive_effects(game: Game) -> Array[String]:
	var res: Array[String] = []
	var none: Array[int] = []
	if not _new_score_texts(game.fx_layer, none).is_empty():
		res.append("«+очки»")
	if not _slam_texts(game.fx_layer).is_empty():
		res.append("текст комбо")
	if not _line_flashes(game.board).is_empty():
		res.append("линия")
	if game.toast.is_shown():
		res.append("сообщение")
	if not _live_sparks().is_empty():
		res.append("искра подсказки")
	if game.board.dimmed() > 0.0:
		res.append("поле темнеет")
	if game.win_backdrop.visible:
		res.append("лучи")
	if game.win_backdrop.confetti.is_active():
		res.append("конфетти")
	return res


## Значения равны и одного типа (сравнение Vector2 с float в GDScript — ошибка, а не false).
func _same_value(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b


## Раскладки на живой игре: альбом, полоса гистерезиса, обратно в портрет. Лоток, поле,
## рука встаёт по GameLayout; ход в альбоме работает.
func _test_game_layout(game: Game) -> void:
	_section("Раскладки в игре")
	var real := game.size
	game.start_level(4)
	await _frames(2)
	var portrait_cell := game.board.get_global_transform().get_scale().x * Board.CELL
	game.apply_layout(Vector2(2276, 1280))
	await _frames(2)
	_check(game.landscape and game.tray.vertical, "16:9: не альбом (landscape %s, лоток вертикальный %s)" % [game.landscape, game.tray.vertical])
	_layout_matches(game, "16:9")
	var land_cell := game.board.get_global_transform().get_scale().x * Board.CELL
	_check(land_cell > portrait_cell * 1.3, "альбом: клетка %.0f не крупнее портретной %.0f" % [land_cell, portrait_cell])
	# Подписи «ПКМ или R — повернуть блок» больше нет (11.10): вся игра — нажать и перетащить, поворот — нажатием.
	_check(game.get_node_or_null("%RotateHintLabel") == null and not game.layout.has("rotate_hint"),
			"альбом: вернулась подпись про ПКМ / R")
	_check(not game.tutorial_hand.visible, "рука осталась на старом месте после смены раскладки")
	# Ход в альбоме: блок из гнезда встаёт на поле.
	var mv := game.tray.find_move(game.level_data.solution, game.board)
	if _check(not mv.is_empty(), "альбом: нет хода по решению"):
		var before: int = game.moves.size()
		_drop(game, int(mv.slot), mv.rect)
		await _frames(1)
		_check(game.moves.size() == before + 1, "альбом: ход не засчитан")
	# Полоса гистерезиса: 1,125 держит альбом, 1,09 — уже портрет.
	game.apply_layout(Vector2(1440, 1280))
	await _frames(1)
	_check(game.landscape, "1440×1280 из альбома: раскладка дёрнулась в портрет")
	game.apply_layout(Vector2(1395, 1280))
	await _frames(2)
	_check(not game.landscape and not game.tray.vertical, "1395×1280: не вернулись в портрет")
	game.apply_layout(Vector2(720, 1280))
	await _frames(2)
	_layout_matches(game, "9:16")
	game.apply_layout(real)
	await _frames(2)
	print("  альбом ↔ портрет: лоток, поле, без подписи про ПКМ, ход")


## Узлы игры стоят в прямоугольниках game.layout, гнёзда — нужного размера, блоки — в гнёздах.
func _layout_matches(game: Game, tag: String) -> void:
	var l := game.layout
	var nodes := {"top_bar": game.top_bar, "board": game.board_area, "actions": game.actions_bar,
			"remaining": game.remaining_label, "tray": game.tray}
	for key in nodes:
		var c: Control = nodes[key]
		var want: Rect2 = l[key]
		var got := Rect2(c.position, c.size)
		_check(got.position.is_equal_approx(want.position) and got.size.is_equal_approx(want.size),
				"%s: %s стоит в %s, ждали %s" % [tag, key, got, want])
	var shelf := game.tray.shelf_rect()
	shelf.position += game.tray.position
	var want_shelf: Rect2 = l.shelf
	_check(shelf.position.is_equal_approx(want_shelf.position) and shelf.size.is_equal_approx(want_shelf.size),
			"%s: полка лотка %s, ждали %s" % [tag, shelf, want_shelf])
	for i in game.tray.slots.size():
		var slot: Control = game.tray.slots[i]
		_check(slot.size.is_equal_approx(l.slot), "%s: гнездо %d размером %s, ждали %s" % [tag, i, slot.size, l.slot])
		var b: Block = game.tray.blocks[i]
		if b != null and b.get_parent() == slot:
			var r := Rect2(b.position, b.size * b.scale)
			_check(Rect2(Vector2.ZERO, slot.size).grow(0.5).encloses(r), "%s: блок %s вылез из гнезда %d" % [tag, b.cells, i])
	# Рамка поля (клетки + PAD с каждой стороны + губа снизу; рамка в логических px) — внутри BoardArea.
	var frame := game.board.frame_rect_global()
	_check(game.board_area.get_global_rect().grow(1.0).encloses(frame),
			"%s: поле %s вылезло из BoardArea %s" % [tag, frame, game.board_area.get_global_rect()])


## Наведение: ×1,05 и «рука» от настоящей мыши; касание (эмуляция мыши), зажатая кнопка
## и выключенная кнопка не увеличивают.
func _test_hover(game: Game) -> void:
	_section("Наведение мышью")
	var btn: Button = game.restart_button
	_check(btn.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND, "у кнопки нет курсора-«руки»")
	var touch := InputEventMouseMotion.new()
	touch.device = InputEvent.DEVICE_ID_EMULATION
	btn.gui_input.emit(touch)
	_check(not Desktop.is_hovered(btn), "касание (эмуляция мыши) включило наведение")
	var held := InputEventMouseMotion.new()
	held.button_mask = MOUSE_BUTTON_MASK_LEFT
	btn.gui_input.emit(held)
	_check(not Desktop.is_hovered(btn), "движение с зажатой кнопкой включило наведение")
	btn.gui_input.emit(InputEventMouseMotion.new())
	_check(Desktop.is_hovered(btn), "мышь над кнопкой: нет наведения")
	btn.mouse_exited.emit()
	_check(not Desktop.is_hovered(btn), "мышь ушла: наведение осталось")
	var off: Button = game.hint_button  # 20.1a: «Отмены» нет; «Подсказка» выключена, когда сердца кончились
	var off_was := off.disabled
	off.disabled = true
	off.gui_input.emit(InputEventMouseMotion.new())
	_check(not Desktop.is_hovered(off), "выключенная кнопка откликается на наведение")
	off.mouse_exited.emit()
	off.disabled = off_was
	var tray := game.tray
	var empty := tray.blocks.find(null)
	var full := 0 if tray.blocks[0] != null else (1 if tray.blocks[1] != null else 2)
	tray.slots[full].gui_input.emit(InputEventMouseMotion.new())
	_check(tray.blocks[full] == null or Desktop.is_hovered(tray.slots[full]), "гнездо с блоком не откликается на наведение")
	tray.slots[full].mouse_exited.emit()
	if empty >= 0:
		tray.slots[empty].gui_input.emit(InputEventMouseMotion.new())
		_check(not Desktop.is_hovered(tray.slots[empty]), "пустое гнездо откликается на наведение")
		tray.slots[empty].mouse_exited.emit()
	print("  наведение только от мыши, только на живые кнопки и гнёзда с блоком")


# --- 9. Поле и блоки в новом стиле (этап 13.1) ---------------------------------------

## Палитра и шрифт цифр, гнёзда, рамка поля, призрак, магнит, подъём блока и возврат в лоток
## (docs/STYLE.md, разделы 2, 5–7). Уровень 12 — без обучения.
func _test_board_style(game: Game) -> void:
	_section("Поле и блоки (13.1)")
	_check(Palette.BLOCK_COLORS.size() == 12, "в палитре %d цветов вместо 12" % Palette.BLOCK_COLORS.size())
	_check(Palette.color_for(0) == Palette.color_for(1) and Palette.color_for(99) == Palette.color_for(12),
			"Palette.color_for не ограничивает площадь 1..12")
	var digits := load(DIGIT_FONT_PATH) as Font
	if _check(digits != null, "шрифт цифр не загружается: " + DIGIT_FONT_PATH):
		var miss := ""
		for ch in "0123456789":
			if not digits.has_char(ch.unicode_at(0)):
				miss += ch
		_check(miss.is_empty(), "в шрифте цифр нет: " + miss)

	game.start_level(12)
	await get_tree().create_timer(0.6).timeout  # блоки лотка и гнёзда появились
	var board := game.board
	var bpx := 1.0 / board.scale.x

	# Гнёзда: только на клетках с числом, цвет площади.
	var want := {}
	for n in game.level_data.numbers:
		want[n.pos] = int(n.value)
	_check(board.cells_root.get_child_count() == want.size(),
			"гнёзд на поле %d, чисел в уровне %d" % [board.cells_root.get_child_count(), want.size()])
	var bad_nest := ""
	for c in board.cells_root.get_children():
		var cell := c as Cell
		if cell == null:
			bad_nest = "не Cell: " + str(c)
			continue
		var p := Vector2i(roundi(cell.position.x / Board.CELL), roundi(cell.position.y / Board.CELL))
		if int(want.get(p, -1)) != cell.value or cell.nest.color != Palette.color_for(cell.value):
			bad_nest = "клетка %s (число %d)" % [str(p), cell.value]
	_check(bad_nest.is_empty(), "гнездо не на своём числе или не того цвета: " + bad_nest)

	# Рамка: узел Frame под масштаб поля, рамка и тени — в логических px.
	var fmat := board.frame.material as ShaderMaterial
	if _check(fmat != null, "у рамки поля нет шейдера"):
		_check(fmat.get_shader_parameter("grid") == Vector2(board.cols, board.rows), "шейдер поля: grid не совпадает с полем")
		var fpx := float(fmat.get_shader_parameter("px"))
		_check(absf(fpx - bpx) < 0.001, "шейдер поля: px %.3f, нужно 1 / масштаб = %.3f" % [fpx, bpx])
		var m := (Board.FRAME_MARGIN + Board.PAD) * bpx
		var fsize := Vector2(board.cols, board.rows) * Board.CELL + Vector2(2.0 * m, 2.0 * m + Board.FRAME_DEPTH * bpx)
		_check(board.frame.position.is_equal_approx(Vector2(-m, -m)) and board.frame.size.is_equal_approx(fsize),
				"узел Frame %s %s, нужно %s %s" % [str(board.frame.position), str(board.frame.size), str(Vector2(-m, -m)), str(fsize)])

	# Призрак места.
	var ghost := board.ghost
	var gr := Rect2i(0, 0, 2, 1)
	board.show_preview(gr, true, 2)
	_check(ghost.visible and ghost.position == Vector2.ZERO and ghost.size == Vector2(2, 1) * Board.CELL
			and ghost.color == Palette.color_for(2), "призрак верного места: не там или не цвета площади")
	board.show_preview(gr, false, 2)
	_check(ghost.visible and ghost.color == Palette.GHOST_BAD, "призрак места, куда нельзя, не красный")
	board.show_preview(Rect2i(board.cols, 0, 1, 1), true, 1)
	_check(not ghost.visible, "призрак за краем поля виден")
	board.show_preview(gr, true, 2)
	board.clear_preview()
	_check(not ghost.visible, "clear_preview не прячет призрак")

	# Магнит: гнёзда той же площади ×1,08, выше на 4 px, ореол; остальные приглушены.
	var area: int = int(game.level_data.numbers[0].value)
	board.emphasize_area(area)
	await get_tree().create_timer(maxf(Cell.MAGNET_TIME, 0.15) + 0.1).timeout
	_check(_magnet_problem(board, area, bpx).is_empty(), "магнит: " + _magnet_problem(board, area, bpx))
	board.clear_emphasis()
	await get_tree().create_timer(maxf(Cell.MAGNET_TIME, 0.15) + 0.1).timeout
	_check(_magnet_problem(board, -1, bpx).is_empty(), "магнит не снялся: " + _magnet_problem(board, -1, bpx))

	# Блок в лотке: цифра по центру, тень «лежит», тень в логических px.
	var slot := -1
	for i in game.tray.blocks.size():
		if game.tray.blocks[i] != null:
			slot = i
			break
	if not _check(slot >= 0, "уровень 12: лоток пуст"):
		return
	var b: Block = game.tray.blocks[slot]
	_check(b.number_cell == Vector2i(-1, -1) and b.number_label.size == b.size, "в лотке цифра блока не по центру")
	_check(_shadow_problem(b, false).is_empty(), "блок в лотке: " + _shadow_problem(b, false))

	# Подъём: слой перетаскивания, непрозрачный, ×LIFT_SCALE от масштаба поля, тень «поднят».
	game.drag._press_slot = slot
	game.drag._begin_drag()
	_check(game.drag.is_dragging() and b.get_parent() == game.drag_layer, "блок не поднялся в слой перетаскивания")
	_check(b.lifted and b.modulate == Color.WHITE, "поднятый блок прозрачный, подкрашен или не «поднят»")
	# Цвет — это площадь: несомый блок не подкрашивается и над местом, куда нельзя (DRAG_TINT_BAD убран 02.10).
	var dc_consts: Dictionary = (game.drag.get_script() as Script).get_script_constant_map()
	_check(not dc_consts.has("DRAG_TINT_BAD"), "DragController.DRAG_TINT_BAD вернулся — несомый блок не подкрашивать")
	await get_tree().create_timer(DragController.LIFT_TIME + 0.2).timeout
	var want_s := board.get_global_transform().get_scale().x * Block.LIFT_SCALE
	var got_s := b.get_global_transform().get_scale().x
	_check(absf(got_s - want_s) < 0.01 * want_s, "поднятый блок: масштаб %.3f, нужно поле ×%.2f = %.3f" % [got_s, Block.LIFT_SCALE, want_s])
	_check(_shadow_problem(b, true).is_empty(), "поднятый блок: " + _shadow_problem(b, true))
	var magnet_on := false
	var has_area := false
	for c in board.cells_root.get_children():
		var cell := c as Cell
		if cell.value == b.area:
			has_area = true
			magnet_on = magnet_on or float((cell.nest.material as ShaderMaterial).get_shader_parameter("ring")) > 0.99
	_check(not has_area or magnet_on, "несут блок площади %d — гнёзда этой площади без ореола" % b.area)

	# Отпустить мимо (cancel): блок в своём гнезде лотка, тень снова «лежит», магнит снят.
	game.drag.cancel()
	await get_tree().create_timer(0.45).timeout
	_check(not game.drag.is_busy() and b.get_parent() == game.tray.slots[slot] and not b.lifted,
			"после отмены перетаскивания блок не вернулся в гнездо %d" % slot)
	_check(_shadow_problem(b, false).is_empty(), "вернувшийся блок: " + _shadow_problem(b, false))
	_check(_magnet_problem(board, -1, bpx).is_empty(), "после отмены магнит не снялся: " + _magnet_problem(board, -1, bpx))
	_check(not board.ghost.visible, "после отмены перетаскивания остался призрак")
	print("  гнёзда, рамка, призрак, магнит, подъём ×%.2f и возврат в лоток" % Block.LIFT_SCALE)


## Полка лотка (13.2a): шейдер на самом Tray, корпус = ряд гнёзд + отступ, гнёзда шейдера = слоты,
## пустое гнездо (нет блока или его несут) со штриховкой, слоты без своей рамки, блоки в лотке крупнее.
func _test_shelf(game: Game) -> void:
	_section("Полка лотка (13.2a)")
	var tray := game.tray
	var mat := tray.material as ShaderMaterial
	if not _check(mat != null and mat.shader != null and mat.shader.resource_path == SHELF_SHADER_PATH,
			"у лотка нет материала с " + SHELF_SHADER_PATH):
		return
	for slot in tray.slots:
		_check(slot.get_theme_stylebox(&"panel") is StyleBoxEmpty, "у слота %s своя рамка — гнездо рисует полка" % slot.name)
	game.start_level(12)
	await get_tree().create_timer(0.6).timeout  # блоки выданы, полка обновлена (отложенно)
	_check(_shelf_problem(tray).is_empty(), "полка после выдачи: " + _shelf_problem(tray))
	var full := 0
	for i in tray.slots.size():
		if not tray.is_slot_empty(i):
			full += 1
	_check(full == mini(3, (game.level_data.pieces as Array).size()), "уровень 12: полных гнёзд %d" % full)

	# Блок в лотке: масштаб = клетка лотка (TRAY_SCALE), ужат только под гнездо.
	var k_bad := ""
	for i in tray.slots.size():
		var b: Block = tray.blocks[i]
		if b == null:
			continue
		var slot: Control = tray.slots[i]
		var k := minf(tray.block_scale, minf((slot.size.x - Tray.SLOT_MARGIN) / b.size.x,
				(slot.size.y - Tray.SLOT_MARGIN) / b.size.y))
		if absf(b.scale.x - k) > 0.001:
			k_bad += " %d: %.3f вместо %.3f" % [i, b.scale.x, k]
	_check(k_bad.is_empty(), "масштаб блоков в лотке:" + k_bad)
	var want_scale := GameLayout.TRAY_SCALE_LANDSCAPE if game.landscape else GameLayout.TRAY_SCALE_PORTRAIT
	_check(is_equal_approx(tray.block_scale, want_scale), "клетка лотка %.2f, ждали %.2f" % [tray.block_scale, want_scale])

	# Подняли блок — его гнездо пустое (штриховка); вернули — снова полное.
	var slot_i := -1
	for i in tray.blocks.size():
		if tray.blocks[i] != null:
			slot_i = i
			break
	if not _check(slot_i >= 0, "уровень 12: лоток пуст"):
		return
	game.drag._press_slot = slot_i
	game.drag._begin_drag()
	await _frames(2)
	_check(tray.is_slot_empty(slot_i) and _shelf_problem(tray).is_empty(),
			"несут блок из гнезда %d — гнездо не пустое на полке: %s" % [slot_i, _shelf_problem(tray)])
	game.drag.cancel()
	await get_tree().create_timer(0.45).timeout
	_check(not tray.is_slot_empty(slot_i) and _shelf_problem(tray).is_empty(),
			"блок вернулся в гнездо %d — полка не обновилась: %s" % [slot_i, _shelf_problem(tray)])

	# Ход: блок ушёл на поле, гнездо пустое, пока очередь не выдаст новый.
	var mv := tray.find_move(game.level_data.solution, game.board)
	if _check(not mv.is_empty(), "уровень 12: нет хода по решению"):
		_drop(game, int(mv.slot), mv.rect)
		await _frames(2)
		_check(_shelf_problem(tray).is_empty(), "после хода: " + _shelf_problem(tray))
	print("  полка: корпус и гнёзда по слотам, пустые гнёзда, клетка лотка %.0f px" % (Block.CELL * tray.block_scale))


## "" — униформы полки совпадают со слотами и блоками лотка.
func _shelf_problem(tray: Tray) -> String:
	var mat := tray.material as ShaderMaterial
	var r := tray.shelf_rect()
	var size_v: Vector2 = mat.get_shader_parameter(&"shelf_size")
	if not size_v.is_equal_approx(r.size):
		return "shelf_size %s, корпус %s" % [size_v, r.size]
	var empty: Vector3 = mat.get_shader_parameter(&"well_empty")
	for i in tray.slots.size():
		var s: Control = tray.slots[i]
		var w: Vector4 = mat.get_shader_parameter(StringName("well%d" % i))
		var want := Vector4(s.position.x - r.position.x, s.position.y - r.position.y, s.size.x, s.size.y)
		if not w.is_equal_approx(want):
			return "гнездо %d %s, слот %s" % [i, w, want]
		var b: Block = tray.blocks[i]
		var is_empty := b == null or b.get_parent() != s
		if (empty[i] > 0.5) != is_empty:
			return "гнездо %d: на полке %s, а оно %s" % [i, "пустое" if empty[i] > 0.5 else "полное",
					"пустое" if is_empty else "с блоком"]
	return ""


## "" — гнёзда в нужном виде: area — площадь магнита (-1 — магнита нет, всё обычное).
func _magnet_problem(board: Board, area: int, bpx: float) -> String:
	for c in board.cells_root.get_children():
		var cell := c as Cell
		var ring := float((cell.nest.material as ShaderMaterial).get_shader_parameter("ring"))
		var on := area > 0 and cell.value == area
		var dim := area > 0 and cell.value != area
		var want_y := -Cell.MAGNET_LIFT * bpx if on else 0.0
		if absf(ring - (1.0 if on else 0.0)) > 0.01:
			return "число %d: ореол %.2f" % [cell.value, ring]
		if absf(cell.badge.scale.x - (Cell.MAGNET_SCALE if on else 1.0)) > 0.01:
			return "число %d: масштаб гнезда %.3f" % [cell.value, cell.badge.scale.x]
		if absf(cell.badge.position.y - want_y) > 0.5:
			return "число %d: гнездо по высоте %.1f, нужно %.1f" % [cell.value, cell.badge.position.y, want_y]
		if absf(cell.badge.modulate.a - (Cell.DIM_COLOR.a if dim else 1.0)) > 0.02:
			return "число %d: прозрачность %.2f" % [cell.value, cell.badge.modulate.a]
	return ""


## "" — тень блока в состоянии lifted: смещение, размытие, цвет, поля узла Shape и px шейдера.
func _shadow_problem(b: Block, lifted: bool) -> String:
	var mat := b.shape.material as ShaderMaterial
	if mat == null:
		return "нет шейдера"
	var off: Vector2 = mat.get_shader_parameter("shadow_offset")
	var blur := float(mat.get_shader_parameter("shadow_blur"))
	var col: Color = mat.get_shader_parameter("shadow_color")
	var px := float(mat.get_shader_parameter("px"))
	var margin := float(mat.get_shader_parameter("margin"))
	var gs := b.get_global_transform().get_scale().x
	if not off.is_equal_approx(Block.SHADOW_LIFTED if lifted else Block.SHADOW_REST):
		return "смещение тени %s" % str(off)
	if not is_equal_approx(blur, Block.BLUR_LIFTED if lifted else Block.BLUR_REST):
		return "размытие тени %.1f" % blur
	if not col.is_equal_approx(Palette.SHADE_LIFTED if lifted else Palette.SHADE):
		return "цвет тени %s" % str(col)
	if absf(px * gs - 1.0) > 0.025:
		return "px шейдера %.3f при масштабе на экране %.3f (тень не в логических px)" % [px, gs]
	var want_m := (Block.MARGIN_LIFTED if lifted else Block.MARGIN_REST) * px
	if absf(margin - want_m) > 0.5 or absf(-b.shape.offset_left - want_m) > 0.5:
		return "поля под тень %.1f / узел %.1f, нужно %.1f" % [margin, -b.shape.offset_left, want_m]
	return ""


# --- 11. Кнопки и значки из PNG (этап 13.2b) ----------------------------------------

## Пауза, заново, подсказка — CandyButton (20.1a: «Отмены» нет) (STYLE, разделы 4, 7, 8): лицо из PNG на 256/240
## больше видимого круга, тень SoftShadow, состояния «выключена» и «нажата», значки подсказки.
func _test_buttons(game: Game) -> void:
	_section("Кнопки (13.2b)")
	game.start_level(12)
	await _frames(3)
	var bad := ""
	for b: Button in [game.pause_button, game.restart_button, game.hint_button]:
		var p := _candy_problem(b)
		if p != "":
			bad += " %s: %s;" % [b.name, p]
	if not _check(bad == "", "кнопки:" + bad):
		return

	# Выключена: лицо 45 %, без тени; включилась — обратно. 20.1a: «Отмены» нет — выключаем «Подсказку»: сердца
	# кончились (Game.update_hud), потом снова есть.
	var off := game.hint_button as CandyButton
	var hearts_max := game.hearts.max_hearts
	game.hearts.reset(3)
	for _k in 3:
		game.hearts.lose()
	game.update_hud()
	await _frames(3)
	_check(off.disabled and off.looks_disabled and is_equal_approx(off.face.modulate.a, CandyButton.DISABLED_ALPHA)
			and not off.face_shadow.visible, "выключенная «Подсказка» (сердца кончились): лицо %.2f, тень %s" % [
			off.face.modulate.a, off.face_shadow.visible])
	game.hearts.reset(hearts_max)
	game.update_hud()
	await _frames(3)
	_check(not off.disabled and not off.looks_disabled and is_equal_approx(off.face.modulate.a, 1.0)
			and off.face_shadow.visible, "«Подсказка» включилась, а вид остался выключенным")

	# Нажата: лицо ×0,92, тень вдвое ближе (через перерисовку Button и твин), отпустили — обратно.
	var hint := game.hint_button as CandyButton
	hint.toggle_mode = true
	hint.set_pressed_no_signal(true)
	hint.queue_redraw()
	await get_tree().create_timer(0.25).timeout
	_check(hint.looks_pressed and is_equal_approx(hint.face.scale.x, CandyButton.PRESS_SCALE)
			and is_equal_approx(hint.face_shadow.near, CandyButton.PRESS_NEAR),
			"нажатая кнопка: лицо ×%.2f, тень ×%.2f" % [hint.face.scale.x, hint.face_shadow.near])
	# Значки сжимаются вместе с лицом — вокруг центра кнопки (иначе «отъезжают» от сжатого круга).
	var squeezed := true
	for bd in hint.badges():
		squeezed = squeezed and is_equal_approx(bd.scale.x, CandyButton.PRESS_SCALE) \
				and (bd.position + bd.pivot_offset).is_equal_approx(hint.size * 0.5)
	_check(squeezed, "нажатая кнопка: значки не сжались вокруг её центра")
	hint.set_pressed_no_signal(false)
	hint.toggle_mode = false
	hint.queue_redraw()
	await get_tree().create_timer(0.25).timeout
	_check(not hint.looks_pressed and is_equal_approx(hint.face.scale.x, 1.0) and is_equal_approx(hint.face_shadow.near, 1.0)
			and is_equal_approx(game.hint_counter.scale.x, 1.0),
			"отпущенная кнопка: лицо ×%.2f, тень ×%.2f, счётчик ×%.2f"
			% [hint.face.scale.x, hint.face_shadow.near, game.hint_counter.scale.x])

	# Значки подсказки: счётчик бесплатных → «реклама» (только если она есть) → ничего.
	game.start_level(12)
	await _frames(2)
	var badges := hint.badges()
	_check(badges.size() == 2 and badges.has(game.hint_counter) and badges.has(game.hint_ad_badge), "у подсказки не два значка")
	var c := hint.size * 0.5 + Vector2(1.0, -1.0) * hint.diameter() * CandyButton.BADGE_SHIFT
	for bd in badges:
		var want := float(bd.get_meta(&"badge_d")) * CandyButton.BADGE_OVERSCAN
		_check(bd.size.is_equal_approx(Vector2.ONE * want) and (bd.position + bd.size * 0.5).is_equal_approx(c),
				"%s: место %s, размер %s" % [bd.name, str(bd.position + bd.size * 0.5), str(bd.size)])
		var sh := bd.get_child(0, true) as SoftShadow
		_check(sh != null and sh.visible and is_equal_approx(sh.offset.y, CandyButton.BADGE_SHADOW_OFFSET)
				and is_equal_approx(sh.blur, CandyButton.BADGE_SHADOW_BLUR), "%s: нет тени значка" % bd.name)
	var free := game.hints.free_left()
	_check(free == HintController.FREE_PER_LEVEL and game.hint_counter.visible and game.hint_count.text == str(free)
			and not game.hint_ad_badge.visible, "начало уровня: счётчик %s «%s», реклама %s"
			% [game.hint_counter.visible, game.hint_count.text, game.hint_ad_badge.visible])
	for _k in HintController.FREE_PER_LEVEL:
		game.hints.give()
	await _frames(2)
	_check(not game.hint_counter.visible and game.hint_ad_badge.visible == game.hints.needs_ad(),
			"бесплатные кончились: счётчик %s, реклама %s (нужна %s)"
			% [game.hint_counter.visible, game.hint_ad_badge.visible, game.hints.needs_ad()])
	print("  4 кнопки из PNG с тенью, «выключена» и «нажата», счётчик и реклама на подсказке")


## "" — кнопка как в STYLE: CandyButton без подложки, лицо PNG с mipmaps, тень нужной силы под лицом.
func _candy_problem(b: Button) -> String:
	var cb := b as CandyButton
	if cb == null:
		return "не CandyButton"
	if cb.icon != null or cb.face == null or cb.face.texture == null or not cb.face.texture.resource_path.ends_with(".png"):
		return "лицо не из PNG"
	for st in [&"normal", &"hover", &"pressed", &"disabled"]:
		if not (b.get_theme_stylebox(st) is StyleBoxEmpty):
			return "подложка %s" % st
	if cb.face.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		return "лицо без фильтра с mipmaps"
	var d := cb.diameter()
	if d < 96.0:
		return "Ø %.0f < 96" % d
	if not cb.face.size.is_equal_approx(Vector2.ONE * d * CandyButton.FACE_OVERSCAN) \
			or not (cb.face.position + cb.face.size * 0.5).is_equal_approx(b.size * 0.5):
		return "лицо %s в %s" % [str(cb.face.size), str(cb.face.position)]
	var sh := cb.face_shadow
	var m := sh.material as ShaderMaterial
	if m == null or m.shader == null or m.shader.resource_path != SOFT_SHADOW_SHADER_PATH or not sh.show_behind_parent \
			or sh.get_parent() != cb.face:
		return "тень не " + SOFT_SHADOW_SHADER_PATH + " за лицом"
	if not is_equal_approx(sh.offset.y, d * CandyButton.SHADOW_OFFSET) or not is_equal_approx(sh.blur, d * CandyButton.SHADOW_BLUR) \
			or not is_equal_approx(sh.get_strength(), CandyButton.SHADOW_STRENGTH):
		return "тень: смещение %.1f, размытие %.1f, сила %.2f" % [sh.offset.y, sh.blur, sh.get_strength()]
	var lo: Vector2 = m.get_shader_parameter(&"shape_lo")
	var hi: Vector2 = m.get_shader_parameter(&"shape_hi")
	if not (hi - lo).is_equal_approx(cb.face.size * CandyButton.FACE_SHAPE) or not sh.size.is_equal_approx(m.get_shader_parameter(&"rect_size")):
		return "форма тени %s" % str(hi - lo)
	return ""


# --- 12. Шапка и плашка «Осталось блоков» (этап 13.2c) ------------------------------

## «УРОВЕНЬ N» и счёт со звездой (HudHeader), плашка-таблетка под «Осталось блоков» (PillLabel):
## шрифт, обводка, тень, места строк из раскладки, ужатие длинного заголовка, разряды счёта.
func _test_header(game: Game) -> void:
	_section("Шапка (13.2c)")
	var real := game.size
	game.start_level(7)
	await _frames(3)
	var h := game.header
	if not _check(h != null and h.get_parent() == game.top_bar, "нет узла Header (HudHeader) в TopBar"):
		return
	# Разряды счёта: по-русски неразрывный пробел, по-английски запятая, по-турецки точка.
	var loc := TranslationServer.get_locale()
	var nb := String.chr(0xA0)
	TranslationServer.set_locale("ru")
	_check(HudHeader.format_score(2340) == "2" + nb + "340" and HudHeader.format_score(999) == "999"
			and HudHeader.format_score(1234567) == "1%s234%s567" % [nb, nb] and HudHeader.format_score(0) == "0",
			"разряды (ru): «%s», «%s»" % [HudHeader.format_score(2340), HudHeader.format_score(1234567)])
	TranslationServer.set_locale("en")
	_check(HudHeader.format_score(2340) == "2,340", "разряды (en): «%s»" % HudHeader.format_score(2340))
	TranslationServer.set_locale("tr")
	_check(HudHeader.format_score(1000) == "1.000", "разряды (tr): «%s»" % HudHeader.format_score(1000))
	TranslationServer.set_locale(loc)
	game.update_hud()
	await _frames(1)

	for screen: Vector2 in [Vector2(720, 1280), Vector2(2276, 1280)]:
		game.apply_layout(screen)
		await _frames(2)
		var tag := "альбом" if game.landscape else "портрет"
		var l := game.layout
		# Тексты, шрифт, цвета.
		_check(game.level_label.text == tr("УРОВЕНЬ %d") % game.level, "%s: заголовок «%s»" % [tag, game.level_label.text])
		_check(game.score_label.text == HudHeader.format_score(game.hud_score()),
				"%s: счёт «%s», ждали %s" % [tag, game.score_label.text, HudHeader.format_score(game.hud_score())])
		for lab: Label in [game.level_label, game.score_label]:
			var f := lab.get_theme_font(&"font")
			_check(f != null and f.resource_path == DIGIT_FONT_PATH, "%s: %s не Nunito Black (%s)" % [tag, lab.name, f.resource_path if f else "нет"])
		var ts := game.level_label.get_theme_font_size(&"font_size")
		var ss := game.score_label.get_theme_font_size(&"font_size")
		_check(ts == int(l.title_size) and ss == int(l.score_size),
				"%s: размеры заголовка / счёта %d / %d, ждали %d / %d" % [tag, ts, ss, l.title_size, l.score_size])
		_check(game.score_label.get_theme_color(&"font_color").is_equal_approx(Palette.SCORE), "%s: цвет счёта не SCORE" % tag)
		for pair: Array in [[game.level_label, ts, HudHeader.TITLE_OUTLINE, HudHeader.TITLE_SHADOW, HudHeader.TITLE_SHADOW_ALPHA],
				[game.score_label, ss, HudHeader.SCORE_OUTLINE, HudHeader.SCORE_SHADOW, HudHeader.SCORE_SHADOW_ALPHA]]:
			var lab: Label = pair[0]
			var fs: int = pair[1]
			var sh := lab.get_theme_color(&"font_shadow_color")
			_check(lab.get_theme_constant(&"outline_size") == roundi(2.0 * float(pair[2]) * fs)
					and lab.get_theme_color(&"font_outline_color").is_equal_approx(Palette.INK)
					and lab.get_theme_constant(&"shadow_offset_y") == roundi(float(pair[3]) * fs)
					and Color(sh.r, sh.g, sh.b).is_equal_approx(Palette.DEEP) and is_equal_approx(sh.a, float(pair[4])),
					"%s: обводка / тень %s: %d, %s, вниз %d" % [tag, lab.name, lab.get_theme_constant(&"outline_size"),
					str(sh), lab.get_theme_constant(&"shadow_offset_y")])
		# Места строк: середины по высоте — из раскладки, по ширине — середина шапки.
		var tc := game.level_label.position + game.level_label.size * 0.5
		var sc_y := game.score_label.position.y + game.score_label.size.y * 0.5
		_check(absf(tc.y - float(l.title_y)) < 1.0 and absf(sc_y - float(l.score_y)) < 1.0 and absf(tc.x - h.size.x * 0.5) < 1.0,
				"%s: заголовок в %s, счёт на y %.1f; ждали y %s / %s" % [tag, str(tc), sc_y, l.title_y, l.score_y])
		var hc := h.get_global_rect().get_center().x
		var bar: Rect2 = l.top_bar
		_check(absf(hc - (game.global_position.x + bar.get_center().x)) < 1.0, "%s: шапка не по центру TopBar" % tag)
		# Звезда слева от числа, строка «звезда + число» по центру; тень звезды по её форме.
		var star := h.star
		var row_l := star.position.x - HudHeader.STAR_X * ss
		var row_r := game.score_label.position.x + game.score_label.size.x
		_check(star.texture != null and star.texture.resource_path == STAR_PNG_PATH, "%s: звезда не %s" % [tag, STAR_PNG_PATH])
		_check(star.position.x + star.size.x <= game.score_label.position.x + 1.0 and absf((row_l + row_r) * 0.5 - h.size.x * 0.5) < 1.5,
				"%s: строка счёта %.0f…%.0f не по центру %.0f" % [tag, row_l, row_r, h.size.x])
		_check(star.size.is_equal_approx(Vector2.ONE * HudHeader.STAR_W * ss / HudHeader.STAR_FIT),
				"%s: звезда %s" % [tag, str(star.size)])
		var tsh := h.star_shadow
		var tm: ShaderMaterial = tsh.material as ShaderMaterial if tsh != null else null
		_check(tsh != null and tsh.get_parent() == star and tsh.show_behind_parent and tm != null
				and tm.shader.resource_path == TEX_SHADOW_SHADER_PATH and tm.get_shader_parameter(&"src") == star.texture
				and is_equal_approx(tsh.offset.y, 0.14 * HudHeader.STAR_R * ss) and is_equal_approx(tsh.blur, 0.18 * HudHeader.STAR_R * ss)
				and is_equal_approx(tsh.get_strength(), HudHeader.STAR_SHADOW_ALPHA)
				and Rect2(tsh.position, tsh.size).encloses(Rect2(Vector2.ZERO, star.size)),
				"%s: тень звезды (TexShadow) не на месте" % tag)
		# Плашка «Осталось блоков»: таблетка шириной в текст + поля, по центру узла, текст в размер раскладки.
		var rem := game.remaining_label
		var fs_r := rem.get_theme_font_size(&"font_size")
		_check(fs_r == int(l.remaining_size), "%s: «Осталось блоков» размером %d, ждали %d" % [tag, fs_r, l.remaining_size])
		_pill_matches(rem, tag)

	# Длинный заголовок ужимается по ширине шапки (обводка с обеих сторон тоже влезает).
	game.apply_layout(Vector2(720, 1280))
	await _frames(1)
	h.show_values(123456789, 987654321)
	await _frames(1)
	var fts := game.level_label.get_theme_font_size(&"font_size")
	var tw := game.level_label.get_theme_font(&"font").get_string_size(game.level_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fts).x
	_check(fts < int(game.layout.title_size) and fts >= HudHeader.TITLE_MIN_SIZE
			and tw + 2.0 * HudHeader.TITLE_OUTLINE * fts <= h.size.x + 1.0,
			"длинный заголовок: размер %d, ширина %.0f при шапке %.0f" % [fts, tw, h.size.x])
	game.update_hud()
	await _frames(1)
	_check(game.level_label.get_theme_font_size(&"font_size") == int(game.layout.title_size), "заголовок не вернул размер после ужатия")

	# Ход: число в плашке уменьшилось, плашка подогналась под новый текст.
	var mv := game.tray.find_move(game.level_data.solution, game.board)
	if _check(not mv.is_empty(), "шапка: нет хода по решению"):
		var before := game.remaining_label.text
		_drop(game, int(mv.slot), mv.rect)
		await _frames(2)
		_check(game.remaining_label.text != before, "«Осталось блоков» не изменилось после хода")
		_pill_matches(game.remaining_label, "после хода")
	game.apply_layout(real)
	await _frames(2)
	print("  заголовок, счёт со звездой, плашка: портрет и альбом, ужатие, разряды")


## Сообщение (13.5d): тёмная плотная капсула с тенью (без розовой рамки), текст ToastText; ширина по тексту,
## не шире места GameLayout «toast», низ — по низу места, по центру; все сообщения на ru / en / tr — не больше
## двух строк (по концу предложения или поровну, строка не с тире); смена раскладки при показе; появление,
## «тычок», уход, скрытие по времени.
func _test_toast(game: Game) -> void:
	_section("Сообщения (13.5d)")
	var real := game.size
	game.start_level(7)
	await _frames(2)
	var t := game.toast
	var sb := t.get_theme_stylebox(&"panel") as StyleBoxFlat
	if _check(sb != null, "у Toast стиль не StyleBoxFlat"):
		_check(sb.bg_color.a >= 0.85 and sb.bg_color.get_luminance() < 0.15, "капсула не тёмная или не плотная: %s" % sb.bg_color)
		_check(sb.border_width_left == 0 and sb.border_width_right == 0 and sb.border_width_bottom == 0
				and sb.border_width_top <= 2 and sb.border_color.r < 0.6, "у капсулы рамка (была розовая): %s" % sb.border_color)
		_check(sb.shadow_size >= 8 and sb.shadow_offset.y > 0 and sb.shadow_color.a > 0.2, "у капсулы нет мягкой тени вниз")
		_check(sb.corner_radius_top_left * 2 >= int(t.get_theme_stylebox(&"panel").get_minimum_size().y + 40.0),
				"капсула в строку не круглая по краям (радиус %d)" % sb.corner_radius_top_left)
	var label: Label = t.get_node("ToastLabel")
	var font := label.get_theme_font(&"font")
	var fs := label.get_theme_font_size(&"font_size")
	_check(label.theme_type_variation == &"ToastText" and label.autowrap_mode == TextServer.AUTOWRAP_OFF
			and font != null and font.resource_path == FONT_PATH and fs == 30
			and label.get_theme_color(&"font_color").is_equal_approx(Color.WHITE),
			"текст сообщения не ToastText (Nunito 800, 30, белый, строки режет Toast)")
	var msgs: Array[String] = ["Тупик: так поле не заполнить. Отмени ход", "Нет ходов! Отмени ошибку",
			"Всё ещё тупик — отмени ещё ход", "Сначала отмени ошибочный ход", "Подсказка откроется после просмотра рекламы",
			"Подсказка: убраны неверные блоки (%d)", "Так остальные блоки не поместятся"]  # = TOAST_TEXTS в tools/layout_model.py
	var line_h := font.get_height(fs)
	var pad := t.get_theme_stylebox(&"panel").get_minimum_size()
	var loc := TranslationServer.get_locale()
	for screen: Vector2 in [Vector2(720, 1280), Vector2(2276, 1280)]:
		game.apply_layout(screen)
		await _frames(1)
		var tag := "альбом" if game.landscape else "портрет"
		var area: Rect2 = game.layout.toast
		var room := t.text_room()
		_check(is_equal_approx(room, area.size.x - pad.x), "%s: место текста %.0f (ждали %.0f)" % [tag, room, area.size.x - pad.x])
		var widest := 0
		for lang: String in ["ru", "en", "tr"]:
			TranslationServer.set_locale(lang)
			for msg in msgs:
				var text := tr(msg)
				if text.contains("%d"):
					text = text % 12
				t.show_text(text)
				var lines := t.shown_text().split("\n")
				var r := Rect2(t.position, t.size)
				widest = maxi(widest, int(r.size.x))
				var want_h := lines.size() * line_h + (lines.size() - 1) * label.get_theme_constant(&"line_spacing") + pad.y
				_check(lines.size() <= 2 and t.shown_text().replace("\n", " ") == text,
						"%s (%s): «%s» — %d строки: %s" % [tag, lang, text, lines.size(), t.shown_text()])
				for ln in lines:
					_check(font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= room + 0.5 and not ln.begins_with("—"),
							"%s (%s): строка «%s» шире места или с тире" % [tag, lang, ln])
				_check(r.size.x <= area.size.x + 0.5 and absf(r.get_center().x - area.get_center().x) <= 1.0
						and absf(r.end.y - area.end.y) <= 1.0 and r.position.y >= area.position.y - 0.5
						and absf(r.size.y - want_h) <= 2.0,
						"%s (%s): капсула «%s» %s, место %s (высота по тексту %.0f)" % [tag, lang, text, r, area, want_h])
		TranslationServer.set_locale(loc)
		t.show_text("OK")
		_check(t.size.x < 200.0 and t.size.x < widest - 200, "%s: ширина не по тексту («OK» — %.0f, самое широкое %d)" % [tag, t.size.x, widest])
	TranslationServer.set_locale(loc)
	# Разбивка строк: по концу предложения; без тире в начале строки. Образец — бывшее «Дальше — сам!» (убрано
	# из игры 07.10), здесь просто строка из двух предложений.
	var two := Toast.balance_lines("Дальше — сам! Ошибки больше не подсвечиваются", font, fs, t.text_room())
	_check(two == "Дальше — сам!\nОшибки больше не подсвечиваются", "разбивка не по концу предложения: %s" % two.replace("\n", " / "))
	var dash := Toast.balance_lines("Всё ещё тупик — отмени ещё ход", font, fs, 380.0)
	_check(dash.split("\n").size() == 2 and not dash.contains("\n—"), "строка начинается с тире: %s" % dash.replace("\n", " / "))
	# Смена раскладки при показе: капсула на новом месте.
	game.apply_layout(Vector2(720, 1280))
	await _frames(1)
	t.show_text(tr("Подсказка откроется после просмотра рекламы"))
	game.apply_layout(Vector2(2276, 1280))
	await _frames(1)
	var a2: Rect2 = game.layout.toast
	var r2 := Rect2(t.position, t.size)
	_check(absf(r2.get_center().x - a2.get_center().x) <= 1.0 and absf(r2.end.y - a2.end.y) <= 1.0,
			"после смены раскладки капсула %s не на месте %s" % [r2, a2])
	# Появление, «тычок», уход, скрытие по времени.
	t.dismiss()
	await get_tree().create_timer(Toast.FADE_OUT + 0.1).timeout
	_check(not t.visible, "сообщение не скрылось")
	t.show_text("A")
	_check(t.is_shown() and t.scale.x < 1.0 and t.modulate.a < 0.5, "появление не с ×%.1f и прозрачности" % Toast.POP_FROM)
	await get_tree().create_timer(Toast.POP_TIME + 0.1).timeout
	_check(is_equal_approx(t.modulate.a, 1.0) and t.scale.is_equal_approx(Vector2.ONE), "сообщение не проявилось до конца")
	t.show_text("B")
	_check(t.scale.x > 1.0 and is_equal_approx(t.modulate.a, 1.0), "новый текст на видимом — без «тычка»")
	t.dismiss()
	_check(t.visible and not t.is_shown(), "уход не плавный")
	await get_tree().create_timer(Toast.FADE_OUT + 0.1).timeout
	_check(not t.visible and t.scale.is_equal_approx(Vector2.ONE), "сообщение не ушло")
	t.show_text("C", 0.2)
	await get_tree().create_timer(0.2 + Toast.FADE_OUT + 0.15).timeout
	_check(not t.visible, "сообщение с duration не скрылось само")
	game.apply_layout(real)
	await _frames(1)
	print("  капсула, ширина по тексту, строки на ru/en/tr, раскладки, появление и уход")


## Плашка PillLabel подогнана под нынешний текст: шейдер, размер, место.
func _pill_matches(rem: PillLabel, tag: String) -> void:
	var pill := rem.pill
	var pm: ShaderMaterial = pill.material as ShaderMaterial if pill != null else null
	if not _check(pill != null and pill.get_parent() == rem and pill.show_behind_parent and pm != null
			and pm.shader.resource_path == PILL_SHADER_PATH, "%s: у «Осталось блоков» нет плашки %s" % [tag, PILL_SHADER_PATH]):
		return
	var want := rem.pill_rect()
	var fs := rem.get_theme_font_size(&"font_size")
	var tw := rem.get_theme_font(&"font").get_string_size(rem.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var rs: Vector2 = pm.get_shader_parameter(&"rect_size")
	_check(pill.visible and Rect2(pill.position, pill.size).is_equal_approx(want)
			and is_equal_approx(want.size.x, ceilf(tw + 2.0 * PillLabel.PAD_X)) and is_equal_approx(want.size.y, roundf(fs * PillLabel.HEIGHT_K))
			and absf(want.get_center().x - rem.size.x * 0.5) <= 1.0
			and rs.is_equal_approx(want.size),
			"%s: плашка %s, ждали %s (текст %.0f px)" % [tag, Rect2(pill.position, pill.size), want, tw])

## Отдельное поле 2×3: блоки, поставленные в любом порядке, рисуются по рядам (нижний поверх
## тени верхнего); цифра блока — на клетке с числом; тень «лежит».
func _test_board_rows() -> void:
	var board_ps := load(BOARD_SCENE) as PackedScene
	var block_ps := load(BLOCK_SCENE) as PackedScene
	if not _check(board_ps != null and block_ps != null, "не загружаются сцены поля или блока"):
		return
	var board := board_ps.instantiate() as Board
	add_child(board)
	board.setup({"cols": 2, "rows": 3, "numbers": [
		{"pos": Vector2i(1, 0), "value": 2}, {"pos": Vector2i(0, 1), "value": 2}, {"pos": Vector2i(1, 2), "value": 2}]})
	var rects: Array[Rect2i] = [Rect2i(0, 2, 2, 1), Rect2i(0, 0, 2, 1), Rect2i(0, 1, 2, 1)]  # ставим 3-й, 1-й, 2-й ряд
	var want_cell: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 0), Vector2i(0, 0)]
	var blocks: Array[Block] = []
	for k in rects.size():
		var b := block_ps.instantiate() as Block
		add_child(b)
		b.cells = Vector2i(2, 1)
		b.set_lifted(true, 0.0)
		board.place_block(b, rects[k])
		blocks.append(b)
	await get_tree().create_timer(0.3).timeout
	var order: Array[int] = []
	for k in blocks.size():
		order.append(blocks[k].get_index())
	_check(order[1] < order[2] and order[2] < order[0], "блоки на поле не по рядам: индексы рядов 3, 1, 2 = %s" % str(order))
	for k in blocks.size():
		var b := blocks[k]
		_check(b.number_cell == want_cell[k], "ряд %d: цифра на клетке %s, нужно %s" % [rects[k].position.y + 1, str(b.number_cell), str(want_cell[k])])
		_check(b.number_label.position.x == want_cell[k].x * Block.CELL, "ряд %d: цифра блока не над числом" % (rects[k].position.y + 1))
		_check(not b.lifted and _shadow_problem(b, false).is_empty(), "ряд %d: тень после установки: %s" % [rects[k].position.y + 1, _shadow_problem(b, false)])
	_check(board.is_full(), "поле 2×3 из трёх блоков не заполнено")
	board.queue_free()
	await _frames(1)
	print("  блоки на поле по рядам, цифра на клетке с числом")


# --- 12. Качество (14.7) ---------------------------------------------------------

## Решатель автоснижения (QualityGovernor, 14.7b) на синтетических кадрах — все сценарии tools/quality_model.py
## с теми же ожиданиями (шум — свой генератор, а не Python random: ожидания от шума не зависят).
func _test_quality_governor() -> void:
	_section("Качество: решатель (14.7)")
	var t0 := Time.get_ticks_msec()
	var r := _qm_run("ровные 60", 300.0)
	var g: QualityGovernor = r[0]
	var ch: Array = r[1]
	_check(g.level == 2 and ch.is_empty(), "ровные 60: уровень сменился: %s" % [ch])
	r = _qm_run("слабый", 300.0)
	g = r[0]
	ch = r[1]
	_check(g.level == 0 and not g.locked, "слабый 35/45/60: не дошли до низкого (уровень %d, замок %s)" % [g.level, g.locked])
	_check(ch.size() >= 2 and ch[0][1] == 1 and ch[1][1] == 0, "слабый: шаги не 2→1→0: %s" % [ch])
	_check(g.probed, "слабый: пробы вверх не было")
	var weak_t: float = ch[1][0] if ch.size() >= 2 else -1.0
	r = _qm_run("средний", 300.0)
	g = r[0]
	_check(g.level == 1 and not g.locked, "средний 42/60: не остались на среднем: %s" % [r[1]])
	r = _qm_run("потолок", 300.0)
	g = r[0]
	ch = r[1]
	_check(g.level == 2 and g.locked, "потолок 30: не вернулись на высокое с замком: %s" % [ch])
	_check(_qm_levels(ch) == [1, 0, 2], "потолок: смены %s (ждали 2→1→0 и откат)" % [ch])
	r = _qm_run("рывки", 300.0)
	g = r[0]
	_check(g.level == 2 and (r[1] as Array).is_empty(), "рывки: уровень сменился: %s" % [r[1]])
	r = _qm_run("120 Гц", 300.0)
	g = r[0]
	_check(g.level == 2 and (r[1] as Array).is_empty(), "120 Гц: уровень сменился: %s" % [r[1]])
	r = _qm_run("победы", 300.0)
	g = r[0]
	_check(g.level >= 1, "победы: опустились до низкого: %s" % [r[1]])
	r = _qm_run("нагрев", 300.0)
	g = r[0]
	ch = r[1]
	_check(g.level == 1 and not ch.is_empty() and float(ch[0][0]) > 120.0, "нагрев: %s" % [ch])
	r = _qm_run("потолок", 200.0, 2, [50.0, 100.0])
	g = r[0]
	ch = r[1]
	_check(g.level == 2 and g.locked and ch.size() == 3, "замок не пережил смену сцены: %s" % [ch])
	r = _qm_run("без ступенек", 300.0)
	g = r[0]
	_check(g.level == 0 and not g.locked, "без ступенек 38/46/58: %s" % [r[1]])
	r = _qm_run("почти не помогает", 300.0)
	g = r[0]
	_check(g.level == 2 and g.locked, "почти не помогает (30/31/32): %s" % [r[1]])
	r = _qm_run("ровные 60", 200.0, 1)
	g = r[0]
	_check(g.level == 2 and (r[1] as Array).size() == 1, "сохранён 1, телефон сильный: проба вверх не вернула высокое: %s" % [r[1]])
	print("  12 сценариев модели: слабый телефон на низком к %.1f с, потолок 30 к/с — откат и замок; %d мс" % [weak_t,
			Time.get_ticks_msec() - t0])


## Прогон решателя, как run() в tools/quality_model.py: кадры сценария name, seconds секунд с уровня start_level;
## resets — секунды, когда «сменилась сцена» (reset()). Ответ: [решатель, смены [[t, уровень, к/с окна]]].
func _qm_run(name: String, seconds: float, start_level := 2, resets: Array = []) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var g := QualityGovernor.new(Juice.shared_config(), start_level)
	var pending := resets.duplicate()
	var changes: Array = []
	var t := 0.0
	while t < seconds:
		while not pending.is_empty() and float(pending[0]) <= t:
			pending.pop_front()
			g.reset()
		var dt := _qm_dt(name, t, g.level, rng)
		t += dt
		var lv := g.push(dt)
		if lv >= 0:
			changes.append([snappedf(t, 0.1), lv, snappedf(g.last_fps, 0.1)])
	return [g, changes]


static func _qm_levels(changes: Array) -> Array:
	var out := []
	for c in changes:
		out.append(int(c[1]))
	return out


## Кадр сценария name во время t на уровне lv, с (числа — из tools/quality_model.py; costs — [низкое, среднее, высокое]).
static func _qm_dt(name: String, t: float, lv: int, rng: RandomNumberGenerator) -> float:
	var costs: Array = []
	match name:
		"ровные 60":
			costs = [0.006, 0.008, 0.010]
			return _qm_vsync(60.0, costs[lv], 0.08, rng)
		"слабый":
			costs = [0.0150, 1.0 / 46.0, 1.0 / 36.0]
			return _qm_vsync(60.0, costs[lv], 0.02, rng)
		"средний":
			costs = [0.010, 0.0140, 1.0 / 43.0]
			return _qm_vsync(60.0, costs[lv], 0.03, rng)
		"потолок":
			return (1.0 / 30.0) * (1.0 + rng.randf_range(-0.01, 0.01))
		"рывки":
			if fmod(t, 20.0) < 0.02:
				return 0.6  # вкладка в фоне
			return 0.050 if fmod(t, 3.0) < 0.3 else 1.0 / 60.0
		"120 Гц":
			costs = [0.007, 0.009, 0.012]
			return _qm_vsync(120.0, costs[lv], 0.2, rng)
		"победы":
			costs = [1.0 / 62.0, 1.0 / 55.0, 1.0 / 40.0]
			var cost: float = costs[lv] if fmod(t, 30.0) < 3.0 else 0.012
			return maxf(cost, 1.0 / 60.0)
		"нагрев":
			if t < 120.0:
				return 1.0 / 60.0
			costs = [1.0 / 70.0, 1.0 / 61.0, 1.0 / 42.0]
			return maxf(costs[lv], 1.0 / 60.0)
		"без ступенек":
			costs = [1.0 / 58.0, 1.0 / 46.0, 1.0 / 38.0]
			return float(costs[lv]) * (1.0 + rng.randf_range(-0.03, 0.03))
		"почти не помогает":
			costs = [1.0 / 32.0, 1.0 / 31.0, 1.0 / 30.0]
			return costs[lv]
	return 1.0 / 60.0


## Кадр — работа cost (с шумом ±noise), округлённая вверх до интервала vsync частоты hz.
static func _qm_vsync(hz: float, cost: float, noise: float, rng: RandomNumberGenerator) -> float:
	var period := 1.0 / hz
	var work := cost * (1.0 + rng.randf_range(-noise, noise))
	return maxf(1.0, ceilf(work / period - 1e-9)) * period


## Что снижается на каждом уровне (14.7c) на живой игре: частицы Juice и их предел, конфетти, искры звёзд, след
## искры подсказки, отсчёты тени звезды, фон в SubViewport (размер, частота, каждый кадр на смене света),
## разрешение 2D на низком; «Меньше движения» — произведение долей; уровень в settings.cfg; счётчик кадров (14.7d):
## F3, F4 и касание счётчика — по кругу, 5 быстрых касаний заголовка «Настройки».
func _test_quality(game: Game) -> void:
	_section("Качество (14.7)")
	var cfg := Juice.shared_config()
	var juice := game.juice
	var bg := game.background
	var shadow := game.header.star_shadow
	var confetti := game.win_backdrop.confetti
	var root := get_tree().root
	var canvas_mode := root.content_scale_mode
	var was_motion := GameState.reduce_motion
	GameState.set_reduce_motion(false)
	Quality.set_level(Quality.HIGH)
	juice.reset()
	var at := Vector2(360, 640)
	var shares := {Quality.HIGH: 1.0, Quality.MID: cfg.quality_particles_mid, Quality.LOW: cfg.quality_particles_low}
	var counts := []
	var bake_info := ""
	for lv in [Quality.HIGH, Quality.MID, Quality.LOW]:
		Quality.set_level(lv)
		var tag := "качество «%s»" % Quality.level_name()
		var k: float = shares[lv]
		_check(Quality.level == lv and is_equal_approx(Quality.particles(), k),
				"%s: доля частиц %.2f (ждали %.2f)" % [tag, Quality.particles(), k])
		# Частицы: число во вспышке и предел в воздухе.
		var p := juice.burst(Juice.SPARKS, at, Color.WHITE, 40)
		_check(p != null and p.amount == int(round(40 * k)), "%s: частиц во вспышке %d (ждали %d)" % [tag,
				p.amount if p else -1, int(round(40 * k))])
		juice.reset()
		_check(juice.particles_cap() == int(round(cfg.particles_max * k)), "%s: предел частиц %d (ждали %d)" % [tag,
				juice.particles_cap(), int(round(cfg.particles_max * k))])
		for i in cfg.pool_size + 4:
			juice.burst(Juice.SPARKS, at)
		_check(juice.live_particles() <= juice.particles_cap(), "%s: в воздухе %d частиц при пределе %d" % [tag,
				juice.live_particles(), juice.particles_cap()])
		juice.reset()
		GameState.set_reduce_motion(true)
		p = juice.burst(Juice.SPARKS, at, Color.WHITE, 40)
		var want_rm := int(round(40 * k * cfg.reduced_particles))
		_check(p != null and p.amount == want_rm, "%s + «Меньше движения»: частиц %d (ждали %d — произведение долей)" % [
				tag, p.amount if p else -1, want_rm])
		_check(confetti.default_count() == roundi(Confetti.COUNT * k * cfg.reduced_particles),
				"%s + «Меньше движения»: конфетти %d" % [tag, confetti.default_count()])
		GameState.set_reduce_motion(false)
		juice.reset()
		_check(confetti.default_count() == roundi(Confetti.COUNT * k), "%s: конфетти %d (ждали %d)" % [tag,
				confetti.default_count(), roundi(Confetti.COUNT * k)])
		counts.append(confetti.default_count())
		# Искры звезды окна победы (WinPanel._on_star_hit): star_sparks × доля.
		var wp := game.win_panel
		wp._on_star_hit(0)
		var st := roundi(cfg.star_sparks * k)
		_check(wp.sparkles[0].amount == st, "%s: искр звезды окна %d (ждали %d)" % [tag, wp.sparkles[0].amount, st])
		wp.sparkles[0].emitting = false
		wp.star_hits.clear()
		# След искры подсказки.
		var spark := HintSpark.fly(game.fx_layer, Vector2(100, 900), Vector2(400, 500), 0.3, 0.3, null)
		var trail := maxi(HintSpark.TRAIL_MIN, roundi(HintSpark.TRAIL * k))
		_check(spark.trail_length() == trail, "%s: след искры %d точек (ждали %d)" % [tag, spark.trail_length(), trail])
		spark.queue_free()
		# Тень звезды счёта (TexShadow): 49 отсчётов, на низком 9.
		var taps := 9 if lv == Quality.LOW else 49
		_check(shadow != null and shadow.samples() == taps, "%s: тень звезды — %d отсчётов (ждали %d)" % [tag,
				shadow.samples() if shadow else -1, taps])
		# Разрешение 2D: на низком — базовое (VIEWPORT), иначе как в проекте.
		var mode := Window.CONTENT_SCALE_MODE_VIEWPORT if lv == Quality.LOW and cfg.quality_low_res else canvas_mode
		_check(root.content_scale_mode == mode, "%s: content_scale_mode %d (ждали %d)" % [tag, root.content_scale_mode, mode])
		# Фон: на высоком — прямо на экране, на среднем и низком — картинка SubViewport.
		await _frames(2)
		if lv == Quality.HIGH:
			_check(not bg.is_baked() and bg.bake_size() == Vector2i.ZERO, "%s: фон в SubViewport" % tag)
			continue
		var sc := get_viewport().get_final_transform().get_scale().x * bg.get_global_transform_with_canvas().get_scale().x
		var want_w := ceili(bg.size.x * clampf(cfg.quality_bg_scale * sc, 0.1, 4.0))
		_check(bg.is_baked() and bg.bake_size().x == want_w, "%s: фон не в SubViewport или ширина %d (ждали %d)" % [tag,
				bg.bake_size().x, want_w])
		var fps := cfg.quality_bg_fps_low if lv == Quality.LOW else cfg.quality_bg_fps_mid
		_check(is_equal_approx(bg.bake_fps(), fps), "%s: фон %.0f раз в секунду (ждали %.0f)" % [tag, bg.bake_fps(), fps])
		var f0 := bg.bake_frames()
		var t0 := Time.get_ticks_msec()
		await get_tree().create_timer(0.5).timeout
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		var n := bg.bake_frames() - f0
		_check(n >= floori(secs * fps * 0.5) and n <= ceili(secs * fps * 1.5) + 1,
				"%s: фон перерисован %d раз за %.2f с (ждали около %.0f)" % [tag, n, secs, secs * fps])
		# Смена света победы — каждый кадр.
		bg.set_win(false, false)
		f0 = bg.bake_frames()
		bg.set_win(true)
		await _frames(6)
		_check(bg.bake_frames() - f0 >= 4, "%s: на смене света фон перерисован %d раз за 6 кадров" % [tag,
				bg.bake_frames() - f0])
		bg.set_win(false, false)
		bake_info += " %s %s / %.0f в с;" % [Quality.level_name(), bg.bake_size(), fps]
	Quality.set_level(Quality.HIGH)
	await _frames(2)
	_check(not bg.is_baked() and bg.bake_size() == Vector2i.ZERO and root.content_scale_mode == canvas_mode
			and shadow.samples() == 49, "назад на высокое: фон, разрешение или тень не вернулись")

	# Уровень — в settings.cfg; следующий запуск начинается с него.
	Quality.set_level(Quality.MID)
	var cf := ConfigFile.new()
	_check(cf.load(GameState.SETTINGS_PATH) == OK and int(cf.get_value("settings", "quality_level", -1)) == Quality.MID,
			"уровень качества не записан в settings.cfg")
	GameState.quality_level = Quality.HIGH
	GameState.load_settings()
	_check(GameState.quality_level == Quality.MID, "уровень качества не читается из settings.cfg")
	Quality.set_level(Quality.HIGH)

	# Счётчик кадров: F3 — показать, F4 и касание — уровень по кругу, F3 — спрятать.
	var meter := Quality.meter
	if _check(meter != null and not meter.visible, "счётчика кадров нет или он виден с запуска"):
		Quality._input(_key(KEY_F4, KEY_F4))
		_check(Quality.level == Quality.HIGH, "F4 без счётчика сменил уровень")
		Quality._input(_key(KEY_F3, KEY_F3))
		var txt := meter.meter_text()
		_check(meter.visible and txt.contains("к/с") and txt.contains("качество: высокое") and txt.contains("частиц"),
				"F3: счётчик не показан или текст «%s»" % txt)
		Quality._input(_key(KEY_F4, KEY_F4))
		_check(Quality.level == Quality.MID and not Quality.auto and meter.meter_text().contains("среднее (вручную)"),
				"F4: уровень %s, текст «%s» (ждали среднее, вручную)" % [Quality.level_name(), meter.meter_text()])
		meter._on_label_input(_mouse_press(true))
		_check(Quality.level == Quality.LOW, "касание счётчика: уровень %s (ждали низкое)" % Quality.level_name())
		Quality.cycle_level()
		_check(Quality.level == Quality.HIGH, "по кругу после низкого — %s (ждали высокое)" % Quality.level_name())
		Quality._input(_key(KEY_F3, KEY_F3))
		_check(not meter.visible, "F3 второй раз не спрятал счётчик")
		# 5 быстрых касаний заголовка «Настройки».
		var panel := (load(SETTINGS_PANEL_SCENE) as PackedScene).instantiate() as SettingsPanel
		add_child(panel)
		await _frames(1)
		_check(panel.title_label.mouse_filter == Control.MOUSE_FILTER_PASS, "заголовок настроек не ловит касания")
		var base := Time.get_ticks_msec() - 100000  # метки в прошлом: настоящие касания ниже — после перерыва
		var hits := []
		for ms in [0, 200, 400, 600, 800]:
			hits.append(panel.count_tap(base + ms))
		_check(hits == [false, false, false, false, true], "5 касаний по 0,2 с: %s (ждали только пятое)" % [hits])
		hits.clear()
		for ms in [10000, 10200, 10400, 10600, 11400, 11600, 11800, 12000]:
			hits.append(panel.count_tap(base + ms))
		_check(not hits.has(true), "касания с перерывом 0,8 с засчитаны подряд: %s" % [hits])
		for i in SettingsPanel.METER_TAPS:
			panel._on_title_input(_mouse_press(true))
		_check(meter.visible, "5 касаний заголовка не показали счётчик")
		Quality.toggle_meter()
		_check(not meter.visible, "toggle_meter() не спрятал счётчик")
		# 12.10b: сборка для игроков (dev_tools = false) — ни клавиш F3 / F4 / F5, ни касаний заголовка: счётчик не
		# появляется; даже если он остался виден (отладка), F4 и F5 не меняют уровень и эффекты.
		var dev0 := Quality.dev_tools
		Quality.dev_tools = false
		for i in SettingsPanel.METER_TAPS:
			panel._on_title_input(_mouse_press(true))
		Quality._input(_key(KEY_F3, KEY_F3))
		Quality.toggle_meter()
		var stayed_hidden := not meter.visible
		meter.set_shown(true)
		var lvl0 := Quality.level
		var fx0 := Quality._cfg.effects_off()
		Quality._input(_key(KEY_F4, KEY_F4))
		Quality._input(_key(KEY_F5, KEY_F5))
		_check(stayed_hidden and Quality.level == lvl0 and Quality._cfg.effects_off() == fx0,
				"сборка для игроков: сработали F3 / касания (счётчик скрыт: %s) или F4 / F5 (уровень %s, эффекты выкл. %s)"
				% [stayed_hidden, Quality.level_name(), Quality._cfg.effects_off()])
		meter.set_shown(false)
		Quality.dev_tools = dev0
		panel.queue_free()
	Quality.set_auto(false)
	Quality.set_level(Quality.HIGH)
	GameState.set_reduce_motion(was_motion)
	juice.reset()
	print("  конфетти %s; тень 49 / 49 / 9;%s счётчик F3 / F4 / касания" % [counts, bake_info])
