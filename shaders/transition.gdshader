shader_type canvas_item;
// Шторка перехода между сценами (14.6c, PLAN 4.4: «шторка из клеток в стиле игры»; Transition/Curtain; числа —
// группа «Появление и переходы» в JuiceConfig: curtain_cell, curtain_radius, curtain_close / open, curtain_spread).
// Экран закрывают скруглённые клетки цвета фона: каждая вырастает из точки в центре своей клетки до квадрата
// со стороной клетка + 2·скругление — углы соседей перекрываются, к концу щелей нет и экран залит ровно.
// Волна идёт по диагонали из левого верхнего угла: клетка (i, j) стартует через spread · (i + j) / (ni + nj − 2)
// хода и растёт остаток. Открытие — тем же путём: первой тает клетка, закрывшаяся первой.
// Форма каждой клетки задевает соседние, поэтому пиксель берёт покрытие своей клетки и восьми соседей.

#include "res://shaders/sdf.gdshaderinc"

uniform vec4 color : source_color = vec4(0.482, 0.325, 0.878, 1.0);
uniform vec2 rect_size = vec2(720.0, 1280.0);  // размер шторки (= экран), px
uniform float cell = 80.0;                     // сторона клетки, px
uniform float radius = 0.24;                   // скругление, доля клетки (как у блока)
uniform float spread = 0.5;                    // доля хода на волну по диагонали
uniform float progress = 0.0;                  // 0…1 — ход закрытия или открытия
uniform bool opening = false;                  // false — клетки растут (закрытие), true — тают (открытие)

// Размер клетки (0 — нет, 1 — во всю клетку с перекрытием) по её месту на диагонали diag (0…1).
float grow(float diag) {
	float w = clamp((progress - diag * spread) / max(1.0 - spread, 0.001), 0.0, 1.0);
	float k = opening ? 1.0 - w : w;
	return k * k * (3.0 - 2.0 * k);
}

void fragment() {
	vec2 p = UV * rect_size;
	vec2 n = max(ceil(rect_size / cell), vec2(1.0));
	vec2 origin = (rect_size - n * cell) * 0.5;  // сетка по центру экрана
	vec2 q = p - origin;
	vec2 own = floor(q / cell);
	float r = radius * cell;
	float diag_max = max(n.x + n.y - 2.0, 1.0);
	float aa = max(fwidth(p.x), 0.5);
	vec2 home = clamp(own, vec2(0.0), n - 1.0);
	// Своя клетка выросла целиком — покрыта наверняка (квадрат со скруглением r и полустороной 0,5·cell + r
	// накрывает всю клетку вместе с углами).
	float m = grow((home.x + home.y) / diag_max) >= 1.0 ? 1.0 : 0.0;
	for (int dy = -1; dy <= 1 && m < 1.0; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			vec2 idx = clamp(own + vec2(float(dx), float(dy)), vec2(0.0), n - 1.0);
			float k = grow((idx.x + idx.y) / diag_max);
			if (k <= 0.0) {
				continue;
			}
			vec2 c = (idx + 0.5) * cell;
			float h = k * (0.5 * cell + r);
			float d = sd_box(q, c - vec2(h), c + vec2(h), min(r, h));
			m = max(m, clamp(0.5 - d / aa, 0.0, 1.0));
		}
	}
	COLOR = vec4(color.rgb, color.a * m);
}
