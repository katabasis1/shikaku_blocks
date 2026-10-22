shader_type canvas_item;
// Карточка окна (docs/STYLE.md, раздел 11; стиль-кадр A3B_win): лицо с вертикальным градиентом, губа
// снизу (то же скругление, сдвинута вниз на lip), мягкая тень губы, цветная шапка высотой head с глянцем
// как у блоков и разделителем line px под ней. head = 0 — карточка без шапки.
// Рисует CandyCard (узел Body за карточкой, show_behind_parent): узел больше карточки на поля под тень
// и губу, лицо — face_lo…face_hi (px узла). Градиент лица — на всю высоту с губой, как в стиль-кадре.
// COLOR.a — прозрачность карточки целиком (modulate предков: проявление окна).

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 rect_size = vec2(704.0, 634.0);
uniform vec2 face_lo = vec2(96.0, 96.0);
uniform vec2 face_hi = vec2(608.0, 524.0);
uniform float radius = 46.0;
uniform float lip = 14.0;
uniform vec4 face_top : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 face_bottom : source_color = vec4(0.949, 0.925, 1.0, 1.0);      // #F2ECFF
uniform vec4 lip_color : source_color = vec4(0.769, 0.69, 1.0, 1.0);         // #C4B0FF
uniform float head = 104.0;
uniform vec4 head_top : source_color = vec4(1.0, 0.761, 0.278, 1.0);         // #FFC247
uniform vec4 head_bottom : source_color = vec4(1.0, 0.482, 0.227, 1.0);      // #FF7B3A
uniform vec4 head_line : source_color = vec4(0.878, 0.376, 0.165, 1.0);      // #E0602A
uniform float line = 5.0;
// Глянец шапки — как у блоков и кнопок (block.gdshader, шаги 5 и 6, клетка k = head): мягкий глянец на верхней
// половине и изогнутый блик-серп по верхнему краю (07.10: прежняя ровная полоса со скруглёнными углами смотрелась
// плоско). gloss — сила обоих: 1 — как у блоков.
uniform float gloss = 1.0;
uniform vec4 shadow_color : source_color = vec4(0.118, 0.043, 0.361, 0.55);  // DEEP #1E0B5C, 55 %
uniform vec2 shadow_offset = vec2(0.0, 18.0);
uniform float shadow_blur = 26.0;                                             // σ, px

void fragment() {
	vec2 p = UV * rect_size;
	vec2 lo = face_lo;
	vec2 hi = face_hi;
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	vec2 down = vec2(0.0, lip);
	float m_face = fill(sd_box(p, lo, hi, radius), aa);
	float m_lip = fill(sd_box(p, lo + down, hi + down, radius), aa);
	float m_body = max(m_face, m_lip);

	// Лицо: face_top -> face_bottom на всю высоту карточки с губой.
	float t = clamp((p.y - lo.y) / max(hi.y + lip - lo.y, 1.0), 0.0, 1.0);
	vec3 face = mix(face_top.rgb, face_bottom.rgb, t);
	if (head > 0.5) {
		float y = p.y - lo.y;
		vec3 hc = mix(head_top.rgb, head_bottom.rgb, clamp(y / head, 0.0, 1.0));
		float k = head;
		// Глянец: верхняя половина шапки, белый 31 % у края -> 0 на 55 % высоты, край мягкий.
		float d_sheen = sd_box(p, lo + vec2(0.08 * k, 0.06 * k), vec2(hi.x - 0.08 * k, lo.y + 0.5 * k), radius * 0.8);
		float sheen_a = 0.31 * clamp(1.0 - y / (0.55 * k), 0.0, 1.0);
		hc = mix(hc, vec3(1.0), fill(d_sheen, 1.9 * 0.06 * k) * sheen_a * gloss);
		// Серп: шапка, ужатая на ins, минус она же, сдвинутая вниз на t; ярче у края, к середине шапки гаснет.
		float ins = 0.06 * k;
		float t = 0.15 * k;
		float ri = max(1.0, radius - ins);
		float s_c = max(1.9 * 0.014 * k, aa);
		vec2 c_lo = lo + vec2(ins);
		vec2 c_hi = vec2(hi.x - ins, lo.y + k - ins);
		float cres = fill(sd_box(p, c_lo, c_hi, ri), s_c) * (1.0 - fill(sd_box(p - vec2(0.0, t), c_lo, c_hi, ri), s_c));
		float y_a = ins + t;
		float y_b = 0.5 * k;
		float cres_a = y < y_a
				? mix(0.53, 0.37, clamp(y / y_a, 0.0, 1.0))
				: mix(0.37, 0.05, clamp((y - y_a) / (y_b - y_a), 0.0, 1.0));
		hc = mix(hc, vec3(1.0), cres * cres_a * gloss);
		float in_head = 1.0 - smoothstep(-aa, aa, y - head);
		float in_line = (1.0 - smoothstep(-aa, aa, y - head - line)) * (1.0 - in_head);
		face = mix(face, hc, in_head);
		face = mix(face, head_line.rgb, in_line);
	}
	vec3 c = mix(lip_color.rgb, face, m_face);

	// Тень — губа (низ карточки), сдвинутая и размытая; карточка поверх неё.
	float d_sh = sd_box(p - shadow_offset, lo + down, hi + down, radius);
	float a_sh = shadow_color.a * fill(d_sh, max(1.9 * shadow_blur, aa));
	float a = m_body + a_sh * (1.0 - m_body);
	vec3 rgb = (c * m_body + shadow_color.rgb * a_sh * (1.0 - m_body)) / max(a, 0.0001);
	COLOR = vec4(rgb, a * COLOR.a);
}
