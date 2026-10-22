extends CanvasLayer
## Переходы между сценами: экран закрывает шторка, сцена меняется, шторка уходит. Пока идёт переход,
## шторка ловит нажатия — второй тап по «Играть» или «В меню» ничего не сломает.
## 14.6c (PLAN 4.4: «шторка из клеток в стиле игры»): экран закрывают скруглённые клетки цвета фона, вырастая
## волной по диагонали, и тем же путём уходят (shaders/transition.gdshader; числа — группа «Появление
## и переходы» в JuiceConfig). «Меньше движения» — прежнее ровное затемнение (FADE_OUT / FADE_IN).

## Средний цвет фона (scenes/ui/background.tscn, STYLE 9; 13.7) — #7B53E0: шторка не темнее и не светлее
## сцены, стык не заметен. Тот же цвет — у экрана загрузки и очистки кадра (project.godot).
const COLOR := Color(0.482, 0.325, 0.878, 1)
const FADE_OUT := 0.18
const FADE_IN := 0.22
const SHADER: Shader = preload("res://shaders/transition.gdshader")
## Режимы шторки: нет перехода, клетки (14.6c), ровное затемнение («Меньше движения»).
const MODE_NONE := 0
const MODE_CELLS := 1
const MODE_FADE := 2

var _curtain: ColorRect
var _material: ShaderMaterial
var _tween: Tween
var _busy: bool = false
## Каким видом идёт нынешний переход: выбирается в начале и не меняется до конца (настройку могут
## переключить, пока шторка закрыта, — уйти она должна так же, как пришла).
var _mode: int = MODE_NONE
## Ход шторки сейчас: 0…1 закрытия или открытия (selftest).
var _progress: float = 0.0
var _opening: bool = false


func _ready() -> void:
	layer = 100  # поверх всех сцен и окон
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("color", COLOR)
	_curtain = ColorRect.new()
	_curtain.name = "Curtain"
	_curtain.color = COLOR
	_curtain.material = _material
	_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain.modulate.a = 0.0
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.visible = false
	add_child(_curtain)


## Идёт ли сейчас переход.
func is_busy() -> bool:
	return _busy


## Вид нынешнего перехода (MODE_*; selftest).
func mode() -> int:
	return _mode


## Насколько экран закрыт сейчас, 0…1: клетки — по ходу шторки, затемнение — по прозрачности (selftest).
func coverage() -> float:
	if not _curtain.visible:
		return 0.0
	if _mode == MODE_CELLS:
		return 1.0 - _progress if _opening else _progress
	return _curtain.modulate.a


## Узел шторки (selftest).
func curtain() -> ColorRect:
	return _curtain


## Меняет сцену через шторку. Повторный вызов во время перехода игнорируется.
func change_scene(path: String) -> void:
	cover(_swap.bind(path))


## Закрывает экран шторкой, под закрытым экраном зовёт action (смена сцены; selftest — проверка шторки без смены
## сцены) и со следующего кадра открывает экран. Повторный вызов во время перехода игнорируется.
func cover(action: Callable) -> void:
	if _busy:
		return
	_busy = true
	_mode = MODE_FADE if GameState.reduce_motion else MODE_CELLS
	_curtain.visible = true
	_curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	_restart_tween()
	if _mode == MODE_CELLS:
		var c := Juice.shared_config()
		_curtain.modulate.a = 1.0
		_set_cells(0.0, false)
		_tween.tween_method(_set_cells.bind(false), 0.0, 1.0, maxf(c.curtain_close, 0.01))
	else:
		_set_cells(1.0, false)  # шейдер заливает всё, видимость ведёт прозрачность
		_tween.tween_property(_curtain, "modulate:a", 1.0, FADE_OUT)
	_tween.tween_callback(_covered.bind(action))


## Экран закрыт: действие, затем открытие.
func _covered(action: Callable) -> void:
	action.call()
	# Новая сцена добавляется в конце кадра; открываем её со следующего.
	await get_tree().process_frame
	_restart_tween()
	if _mode == MODE_CELLS:
		var c := Juice.shared_config()
		_set_cells(0.0, true)
		_tween.tween_method(_set_cells.bind(true), 0.0, 1.0, maxf(c.curtain_open, 0.01))
	else:
		_tween.tween_property(_curtain, "modulate:a", 0.0, FADE_IN)
	_tween.tween_callback(_finish)


func _swap(path: String) -> void:
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_warning("Transition: не удалось открыть %s (%s)" % [path, error_string(err)])


## Шаг шторки из клеток: opening — открытие (клетки тают), t — ход 0…1. Размеры — по нынешнему экрану
## (его могут повернуть посреди перехода).
func _set_cells(t: float, opening: bool) -> void:
	_progress = t
	_opening = opening
	var c := Juice.shared_config()
	var screen := _curtain.size
	if screen.x < 1.0 or screen.y < 1.0:
		screen = _curtain.get_viewport_rect().size
	_material.set_shader_parameter("rect_size", screen)
	_material.set_shader_parameter("cell", maxf(c.curtain_cell * minf(screen.x, screen.y), 8.0))
	_material.set_shader_parameter("radius", clampf(c.curtain_radius, 0.0, 0.5))
	_material.set_shader_parameter("spread", clampf(c.curtain_spread, 0.0, 0.95))
	_material.set_shader_parameter("progress", t)
	_material.set_shader_parameter("opening", opening)


func _finish() -> void:
	_curtain.visible = false
	_curtain.modulate.a = 0.0
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
	_mode = MODE_NONE
	_progress = 0.0
	_opening = false


func _restart_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
