shader_type canvas_item;
// Призрак места (docs/STYLE.md, раздел 6): форма блока, цвет площади 35 % + белая рамка 5 px внутри,
// скругление RC. Узел Board/Ghost стоит ровно на прямоугольнике места (локальные px поля);
// цвет — COLOR (ColorRect.color, его ставит Board.show_preview), рамка — в логических px (× px).

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 rect_size = vec2(200.0, 100.0);
uniform float cell = 100.0;
uniform float radius = 0.24;
uniform float gap = 0.045;
uniform float px = 1.0;            // локальных px поля в логическом px экрана
uniform float body_alpha = 0.35;
uniform float frame_px = 5.0;      // белая рамка, логические px
uniform float frame_alpha = 1.0;

void fragment() {
	vec2 p = UV * rect_size;
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	float g = gap * cell;
	float r = radius * cell;
	float d = sd_box(p, vec2(g), rect_size - vec2(g), r);
	float m_body = fill(d, aa);
	// Рамка: полоса frame_px внутри края (внутренняя форма концентрична — радиус r - рамка).
	float m_frame = m_body * (1.0 - fill(d + frame_px * px, aa));
	vec4 o = vec4(COLOR.rgb, body_alpha * m_body);
	o = over(o, vec3(1.0), frame_alpha * m_frame);
	COLOR = vec4(o.rgb, o.a * COLOR.a);
}
