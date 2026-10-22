shader_type canvas_item;
// Волна света по закрытой линии (14.4, LineFlash; docs/STYLE.md, раздел 12, «Линия и серия»). Узел — ColorRect
// во всю линию (строка или столбец поля, px поля). От origin к обоим концам вдоль длинной стороны бежит полоса
// света шириной band (профиль Гаусса), путь фронта от origin — front; позади фронта — ровный след силы trail
// от полосы. Форма — скруглённый прямоугольник radius, как прежняя вспышка линии. strength — сила (0 — нет).
// Цвет узла белый; modulate — в COLOR.

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 rect_size = vec2(600.0, 100.0);
uniform float radius = 24.0;
uniform vec2 origin = vec2(300.0, 50.0);
uniform float front = 0.0;
uniform float band = 120.0;
uniform float trail = 0.35;
uniform float strength = 0.0;
uniform vec4 wave_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 p = UV * rect_size;
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	float mask = fill(sd_box(p, vec2(0.0), rect_size, radius), aa);
	// Путь от точки старта вдоль линии: по x у строки, по y у столбца.
	float horiz = step(rect_size.y, rect_size.x);
	float d = mix(abs(p.y - origin.y), abs(p.x - origin.x), horiz);
	float x = (d - front) / max(band, 1.0);
	float crest = exp(-8.0 * x * x);
	float behind = trail * (1.0 - smoothstep(-0.35, 0.0, x));
	float a = strength * max(crest, behind) * mask;
	COLOR = vec4(wave_color.rgb * COLOR.rgb, wave_color.a * a * COLOR.a);
}
