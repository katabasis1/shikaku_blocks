shader_type canvas_item;
// Волна света по полю на победе (14.5, WinWave; docs/STYLE.md, раздел 12, «Победа»). Узел — ColorRect во всё поле
// (px поля). От origin (середина последнего блока) расходится кольцо света шириной band (профиль Гаусса), радиус
// фронта — front; внутри кольца — ровный след силы trail от полосы. Форма — скруглённый прямоугольник radius.
// strength — сила (0 — нет). Цвет узла белый; modulate — в COLOR.

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 rect_size = vec2(600.0, 600.0);
uniform float radius = 24.0;
uniform vec2 origin = vec2(300.0, 300.0);
uniform float front = 0.0;
uniform float band = 160.0;
uniform float trail = 0.3;
uniform float strength = 0.0;
uniform vec4 wave_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 p = UV * rect_size;
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	float mask = fill(sd_box(p, vec2(0.0), rect_size, radius), aa);
	float x = (length(p - origin) - front) / max(band, 1.0);
	float crest = exp(-8.0 * x * x);
	float behind = trail * (1.0 - smoothstep(-0.35, 0.0, x));
	float a = strength * max(crest, behind) * mask;
	COLOR = vec4(wave_color.rgb * COLOR.rgb, wave_color.a * a * COLOR.a);
}
