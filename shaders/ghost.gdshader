shader_type canvas_item;
// Призрак места (docs/STYLE.md, раздел 6): форма блока, скругление RC, цвет — COLOR (ColorRect.color, его ставит
// Board.show_preview: цвет площади или GHOST_BAD). Узел Board/Ghost шире места на margin с каждой стороны (поля под
// свечение, Board.GHOST_GLOW логических px); единицы — локальные px поля, толщины — в логических px (× px).
// Вид — по картинке-референсу (20.8: docs/shader_refs/ghost.jpg, промпт П8 в PROMPTS.md): светящийся прозрачный
// «слот» цвета блока. Все переходы идут по контуру и тают плавно:
//   - заливка: цвет места body_alpha, к низу плотнее (× body_grad у нижнего края) — клетки и число под призраком
//     видны; у верха (спад top_fall px) и вдоль рамки цвет светлее: ярче (× 1 + top_light) и чуть белее (top_white);
//   - внутреннее свечение: вдоль рамки изнутри заливка плотнее на inner_alpha, спад inner_fall px (на верхней стороне
//     × inner_top — там светлый верх);
//   - рамка: белая полоса frame_px, отступив frame_inset от края (в отступе — заливка), чёткая;
//   - снаружи свечение цвета места, осветлённого на glow_light (у красного — glow_bad): Гаусс от края
//     (σ glow_sigma), сила glow_alpha.
// bad = 1 — место, куда нельзя (красный): заливка, внутреннее свечение и рамка тусклее (*_bad).
// COLOR.a — прозрачность призрака целиком.

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 rect_size = vec2(200.0, 100.0);   // место (без полей)
uniform float margin = 0.0;                     // поля узла под свечение, локальные px
uniform float cell = 100.0;
uniform float radius = 0.24;
uniform float gap = 0.045;
uniform float px = 1.0;                         // локальных px поля в логическом px экрана
uniform float bad = 0.0;
uniform float body_alpha = 0.6;
uniform float body_alpha_bad = 0.46;
uniform float body_grad = 1.18;
uniform float top_light = 0.2;
uniform float top_white = 0.1;
uniform float top_fall = 10.0;
uniform float inner_alpha = 0.18;
uniform float inner_alpha_bad = 0.05;
uniform float inner_fall = 6.5;
uniform float inner_top = 0.4;                  // доля внутреннего свечения на верхней стороне
uniform float frame_px = 4.4;                   // белая рамка, логические px
uniform float frame_inset = 0.8;                // рамка отступает от края, логические px (снаружи — заливка)
uniform float frame_alpha = 1.0;
uniform float frame_alpha_bad = 0.6;
uniform float glow_alpha = 0.9;
uniform float glow_sigma = 9.0;                 // логические px
uniform float glow_light = 0.2;
uniform vec4 glow_bad : source_color = vec4(1.0, 0.463, 0.565, 1.0);  // #FF7690 — свечение красного призрака

void fragment() {
	vec2 p = UV * (rect_size + vec2(2.0 * margin)) - vec2(margin);
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	float g = gap * cell;
	float r = radius * cell;
	vec2 lo = vec2(g);
	vec2 hi = rect_size - vec2(g);
	float d = sd_box(p, lo, hi, r);
	float m_body = fill(d, aa);
	float din = -d / px;                         // глубина внутри формы, логические px
	vec2 n = box_normal(p, lo, hi, r);
	vec3 c = COLOR.rgb;

	// Заливка: к низу плотнее; у верха и вдоль рамки цвет светлее («светящийся»: ярче и чуть белее).
	float fw = frame_inset + frame_px;
	float t = clamp((p.y - lo.y) / max(hi.y - lo.y, 1.0), 0.0, 1.0);
	float a_body = mix(body_alpha, body_alpha_bad, bad) * mix(1.0, body_grad, t);
	float w_top = exp(-max((p.y - lo.y) / px - fw, 0.0) / top_fall);
	// Внутреннее свечение вдоль рамки: заливка плотнее (на верхней стороне слабее).
	float w_in = exp(-max(din - fw, 0.0) / inner_fall);
	a_body += mix(inner_alpha, inner_alpha_bad, bad) * w_in * mix(1.0, inner_top, smoothstep(0.2, 0.9, -n.y));
	vec3 c_hi = lighten(min(c * (1.0 + top_light), vec3(1.0)), top_white);
	vec3 cb = mix(c, c_hi, max(w_top, w_in));
	vec4 o = vec4(cb, clamp(a_body, 0.0, 1.0) * m_body);

	// Рамка: полоса frame_px, отступив frame_inset от края (внутренняя форма концентрична).
	float m_frame = fill(d + frame_inset * px, aa) * (1.0 - fill(d + fw * px, aa));
	o = over(o, vec3(1.0), mix(frame_alpha, frame_alpha_bad, bad) * m_frame);

	// Свечение снаружи: Гаусс от края формы, под призраком.
	float dout = max(d, 0.0) / px / glow_sigma;
	float a_glow = glow_alpha * exp(-0.5 * dout * dout) * (1.0 - m_body);
	vec3 gc = mix(lighten(c, glow_light), glow_bad.rgb, bad);
	vec4 res = over(vec4(gc, a_glow), o.rgb, o.a);
	COLOR = vec4(res.rgb, res.a * COLOR.a);
}
