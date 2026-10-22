shader_type canvas_item;
// Плашка-таблетка под подписью (docs/STYLE.md, разделы 4 и 13; «Осталось блоков»): тёмная полупрозрачная
// заливка, радиус = высота / 2, внутренняя тень у верхнего края (плашка «утоплена» в фон).
// Рисует PillLabel (узел Pill за текстом); rect_size — размер узла в px.

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 rect_size = vec2(320.0, 52.0);
uniform vec4 fill_color : source_color = vec4(0.094, 0.031, 0.376, 0.275);   // (24, 8, 96), 70 / 255
uniform vec4 shade : source_color = vec4(0.063, 0.016, 0.275, 1.0);          // (16, 4, 70)
uniform float shade_strength = 0.35;
uniform vec2 shade_offset = vec2(0.0, 2.0);             // px
uniform float shade_blur = 3.0;                         // σ, px

void fragment() {
	vec2 p = UV * rect_size;
	vec2 lo = vec2(0.5);
	vec2 hi = rect_size - vec2(0.5);
	float r = (hi.y - lo.y) * 0.5;
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	float body = fill(sd_box(p, lo, hi, r), aa);
	// Внутренняя тень: всё, что вне формы, сдвинутой вниз и размытой, — в тени (только внутри формы).
	float shifted = fill(sd_box(p - shade_offset, lo, hi, r), max(1.9 * shade_blur, aa));
	vec4 c = over(fill_color, shade.rgb, (1.0 - shifted) * shade_strength);
	COLOR = vec4(c.rgb, c.a * body * COLOR.a);
}
