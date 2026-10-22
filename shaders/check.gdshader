shader_type canvas_item;
// Галочка «число закрыто» (14.3, Block.close_number; docs/STYLE.md, раздел 12): белая линия с обводкой и тенью
// цвета площади — как цифра блока (Label: outline_size 9, тень вниз 4 px, Palette.block_digit_*). В шрифте Nunito
// галочки нет, поэтому она — две «капсулы» pt_a → pt_b → pt_c. Узел — ColorRect на месте цифры (клетка 100 × 100 px блока),
// цвет узла белый; modulate (прозрачность, вспышка) — в COLOR.

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 rect_size = vec2(100.0, 100.0);
// Точки галочки, px узла (имена не a/b/c: язык шейдеров Godot не даёт локальным именам sd_box и over
// перекрывать униформы).
uniform vec2 pt_a = vec2(31.0, 52.0);
uniform vec2 pt_b = vec2(44.0, 64.0);
uniform vec2 pt_c = vec2(69.0, 37.0);
uniform float stroke = 10.0;        // толщина белой линии, px блока
uniform float outline = 9.0;        // обводка — полная ширина (по половине на сторону), как Label.outline_size
uniform vec2 shadow_offset = vec2(0.0, 4.0);
uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 outline_color : source_color = vec4(0.55, 0.16, 0.13, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.4, 0.12, 0.1, 0.47);

// Расстояние до отрезка [a, b].
float sd_seg(vec2 p, vec2 a0, vec2 b0) {
	vec2 pa = p - a0;
	vec2 ba = b0 - a0;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	return length(pa - ba * h);
}

void fragment() {
	vec2 p = UV * rect_size;
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	float d = min(sd_seg(p, pt_a, pt_b), sd_seg(p, pt_b, pt_c));
	vec2 q = p - shadow_offset;
	float ds = min(sd_seg(q, pt_a, pt_b), sd_seg(q, pt_b, pt_c));
	float hw = stroke * 0.5;
	float ho = hw + outline * 0.5;
	vec4 col = vec4(shadow_color.rgb, shadow_color.a * fill(ds - ho, aa));
	col = over(col, outline_color.rgb, outline_color.a * fill(d - ho, aa));
	col = over(col, fill_color.rgb, fill_color.a * fill(d - hw, aa));
	COLOR = vec4(col.rgb * COLOR.rgb, col.a * COLOR.a);
}
