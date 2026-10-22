class_name LogoSparkles
extends Control
## Искры логотипа меню (07.10, MenuLogo): четырёхлучевые звёздочки sparkle.png (tools/make_sparkle.py) тёплого
## белого COLOR. Каждая мерцает в своей фазе: размер ×(1 − TWINKLE … 1), прозрачность ALPHA_MIN … 1, период
## TWINKLE_PERIOD с (у каждой свой множитель скорости). burst (0…1) — всплеск посадки двойки: крупнее на
## BURST_SCALE и ярче. still («Меньше движения») — стоят полным размером, без мерцания.
## Места (POINTS) — в координатах логотипа 480×360 (x, y, радиус px, фаза рад); рисует себя сама (_draw).

const TEXTURE: Texture2D = preload("res://assets/icons/sparkle.png")
const COLOR := Color(1.0, 0.97, 0.85)
const TWINKLE := 0.45
const ALPHA_MIN := 0.45
const TWINKLE_PERIOD := 1.8
const BURST_SCALE := 0.6
const POINTS: Array[Vector4] = [
	Vector4(-52.0, 30.0, 26.0, 0.0),
	Vector4(540.0, 250.0, 19.0, 2.1),
	Vector4(408.0, -32.0, 14.0, 4.0),
	Vector4(35.0, 385.0, 15.0, 1.2),
	Vector4(490.0, 30.0, 10.0, 3.1),
]
## Множители скорости мерцания по искрам (не в такт друг другу).
const SPEEDS: Array[float] = [1.0, 0.83, 1.21, 0.92, 1.37]

var burst := 0.0:
	set(v):
		burst = v
		queue_redraw()
var still := false
var _t := 0.0


func _process(delta: float) -> void:
	if still:
		return
	_t += delta
	queue_redraw()


## Мерцание искры i сейчас: 0 — самая мелкая и тусклая, 1 — полная.
func twinkle(i: int) -> float:
	if still:
		return 1.0
	return 0.5 + 0.5 * sin(_t * TAU / TWINKLE_PERIOD * SPEEDS[i % SPEEDS.size()] + POINTS[i].w)


func _draw() -> void:
	for i in POINTS.size():
		var p := POINTS[i]
		var tw := twinkle(i)
		var r := p.z * (1.0 - TWINKLE * (1.0 - tw)) * (1.0 + BURST_SCALE * burst)
		var a := clampf(lerpf(ALPHA_MIN, 1.0, tw) + burst, 0.0, 1.0)
		draw_texture_rect(TEXTURE, Rect2(Vector2(p.x, p.y) - Vector2.ONE * r, Vector2.ONE * 2.0 * r), false,
				Color(COLOR, a))
