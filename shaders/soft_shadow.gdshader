shader_type canvas_item;
// Мягкая тень под картинкой (docs/STYLE.md, раздел 7): размытый скруглённый прямоугольник цвета shade.
// Рисует SoftShadow (ColorRect за родителем-картинкой, show_behind_parent): узел больше родителя
// на поля под размытие и смещение, форма — видимая часть картинки (shape_lo…shape_hi, px узла).
// Размытие — как у Гаусса с сигмой blur (fill с мягким краем 1,9σ, sdf.gdshaderinc).

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 rect_size = vec2(132.0, 140.0);
uniform vec2 shape_lo = vec2(18.0, 18.0);
uniform vec2 shape_hi = vec2(114.0, 114.0);
uniform float radius = 48.0;                            // px; половина меньшей стороны — круг / таблетка
uniform vec2 offset = vec2(0.0, 4.3);                   // px; нажатая кнопка — вдвое ближе (SoftShadow.near)
uniform float blur = 3.8;                               // σ, px
uniform vec4 shade : source_color = vec4(0.204, 0.086, 0.561, 1.0);   // SHADE #34168F
uniform float strength = 0.38;

void fragment() {
	vec2 p = UV * rect_size - offset;
	float d = sd_box(p, shape_lo, shape_hi, radius);
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	float m = fill(d, max(1.9 * blur, aa));
	COLOR = vec4(shade.rgb, strength * m * COLOR.a);
}
