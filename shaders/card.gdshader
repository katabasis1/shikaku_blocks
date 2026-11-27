shader_type canvas_item;
// Карточка окна (docs/STYLE.md, раздел 11): лицо с вертикальным градиентом, губа снизу (то же скругление,
// сдвинута вниз на lip), мягкая тень губы, цветная шапка высотой head с разделителем line px под ней.
// head = 0 — карточка без шапки.
// Вид — по картинке-референсу (20.8: docs/shader_refs/card_windows.jpg, промпт П5 в PROMPTS.md):
// толстая карточка-«леденец». Все блики и тени идут по контуру и тают на скруглениях, без наклеенных пятен:
// - лицо: по бокам выпуклый ободок (лавандовый у края, по гребню светлая линия, за ним мягкая бороздка), он
//   огибает нижние скругления и переходит в узкое скругление низа лица в губу;
// - губа: у лица темнее, к нижнему краю светлее, по низу тонкая светлая кромка (тает на скруглениях);
// - шапка: мягкий глянец сверху, светлая линия блика по контуру верха (огибает верхние скругления и гаснет
//   на боках, слева ярче), светлая кромка по краю, низ темнее к разделителю; шапка бросает на лицо короткую тень.
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
uniform vec4 face_bottom : source_color = vec4(0.925, 0.902, 1.0, 1.0);      // #ECE6FF
uniform vec4 lip_color : source_color = vec4(0.769, 0.69, 1.0, 1.0);         // #C4B0FF — губа у нижнего края
uniform vec4 lip_shade : source_color = vec4(0.604, 0.502, 0.949, 1.0);      // #9A80F2 — губа под лицом
uniform float head = 104.0;
uniform vec4 head_top : source_color = vec4(1.0, 0.761, 0.278, 1.0);         // #FFC247
uniform vec4 head_bottom : source_color = vec4(1.0, 0.482, 0.227, 1.0);      // #FF7B3A
uniform vec4 head_line : source_color = vec4(0.878, 0.376, 0.165, 1.0);      // #E0602A
uniform float line = 5.0;
// gloss — сила глянца и линии блика шапки: 1 — как задумано.
uniform float gloss = 1.0;
uniform vec4 shadow_color : source_color = vec4(0.118, 0.043, 0.361, 0.55);  // DEEP #1E0B5C, 55 %
uniform vec2 shadow_offset = vec2(0.0, 18.0);
uniform float shadow_blur = 26.0;                                             // σ, px
// Ободок лица по бокам (px от края лица): лавандовый у края -> 0 к гребню rim_width, по гребню светлая линия,
// за гребнем бороздка (тон губы), гаснет внутрь за groove_fall.
uniform float rim_width = 7.0;
uniform float rim_alpha = 0.7;
uniform float crest_alpha = 0.4;
uniform float groove_alpha = 0.46;
uniform float groove_fall = 4.5;
uniform float groove_flat = 2.5;       // бороздка держится groove_flat px, потом гаснет
// Низ лица: узкое скругление в губу (тон lip_shade) и тонкая светлая кромка над ним.
uniform float edge_width = 2.6;
uniform float edge_alpha = 0.6;
uniform float edge_crest = 0.4;
// Губа: светлая кромка по низу.
uniform float lip_rim_alpha = 0.3;
// Шапка.
uniform float sheen = 0.42;            // мягкий глянец верхней половины
uniform float spec_inset = 14.0;       // линия блика: центр от верхнего края, px
uniform float spec_width = 6.0;        // полуширина (Гаусс), px
uniform float spec_alpha = 0.95;
uniform float head_edge = 0.3;         // светлая кромка по краю шапки
uniform float head_under = 0.35;       // низ шапки темнее к разделителю (тон head_line)
uniform float line_dark = 0.1;         // разделитель темнее head_line
uniform float head_shadow = 0.5;       // тень шапки на лицо: сила у разделителя
uniform float head_shadow_fall = 5.5;  // и спад, px

// Тонкая линия вдоль контура на глубине inset (din — глубина точки внутри формы, px), полуширина hw.
float contour_line(float din, float inset, float hw, float aa) {
	return 1.0 - smoothstep(hw - aa, hw + aa, abs(din - inset));
}

void fragment() {
	vec2 p = UV * rect_size;
	vec2 lo = face_lo;
	vec2 hi = face_hi;
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	vec2 down = vec2(0.0, lip);
	float d_face = sd_box(p, lo, hi, radius);
	float d_lip = sd_box(p, lo + down, hi + down, radius);
	float m_face = fill(d_face, aa);
	float m_lip = fill(d_lip, aa);
	float m_body = max(m_face, m_lip);
	float din = -d_face;
	vec2 n = box_normal(p, lo, hi, radius);

	// 1. Губа: тон — от её края (на скруглениях тот же, что посередине): у лица lip_shade, к низу lip_color.
	float lip_in = -d_lip;
	float tl = clamp(lip_in / max(lip, 1.0), 0.0, 1.0);
	vec3 lc = mix(lip_color.rgb, lip_shade.rgb, tl * (1.7 - 0.7 * tl));
	// Светлая кромка по низу губы: идёт по контуру, на нижних скруглениях сужается и тает.
	vec2 n_lip = box_normal(p, lo + down, hi + down, radius);
	float lw = smoothstep(0.3, 0.97, n_lip.y);
	lc = mix(lc, lighten(lip_color.rgb, 0.5), lip_rim_alpha * lw * contour_line(lip_in, 2.0, mix(0.3, 1.0, lw), aa));

	// 2. Лицо: face_top -> face_bottom на всю высоту карточки с губой.
	float t = clamp((p.y - lo.y) / max(hi.y + lip - lo.y, 1.0), 0.0, 1.0);
	vec3 face = mix(face_top.rgb, face_bottom.rgb, t);
	// Ободок: по бокам широкий (rim_width), к низу через скругления сужается в скругление низа (edge_width).
	// Вес — по нормали контура: бока 1, низ — wb; верх — только у карточки без шапки.
	float wb = smoothstep(0.3, 0.97, n.y);
	float ws = smoothstep(0.2, 0.9, abs(n.x));
	float wt = head > 0.5 ? 0.0 : smoothstep(0.2, 0.9, -n.y);
	float w_rim = max(max(ws, wb), wt);
	float rw = mix(rim_width, edge_width, wb);
	float band = clamp(1.0 - din / rw, 0.0, 1.0);
	face = mix(face, mix(lip_color.rgb, lip_shade.rgb, wb), mix(rim_alpha, edge_alpha, wb) * band * w_rim);
	face = mix(face, vec3(1.0), mix(crest_alpha, edge_crest, wb) * w_rim * contour_line(din, rw + 0.6, 0.8, aa));
	float groove = smoothstep(rw + 0.5, rw + 2.5, din) * exp(-max(din - rw - 2.5 - groove_flat, 0.0) / groove_fall);
	face = mix(face, lip_color.rgb, groove_alpha * groove * max(ws, wt) * (1.0 - wb));

	// 3. Шапка.
	if (head > 0.5) {
		float y = p.y - lo.y;
		float k = head;
		vec3 hc = mix(head_top.rgb, head_bottom.rgb, clamp(y / k, 0.0, 1.0));
		// Мягкий глянец: верхняя половина шапки, белый sheen у края -> 0 на 65 % высоты, край мягкий.
		float d_sheen = sd_box(p, lo + vec2(0.08 * k, 0.06 * k), vec2(hi.x - 0.08 * k, lo.y + 0.5 * k), radius * 0.8);
		float sheen_a = sheen * clamp(1.0 - y / (0.65 * k), 0.0, 1.0);
		hc = mix(hc, vec3(1.0), fill(d_sheen, 1.9 * 0.06 * k) * sheen_a * gloss);
		// Низ шапки скруглён: к разделителю темнее.
		hc = mix(hc, head_line.rgb, head_under * smoothstep(0.55 * k, k, y));
		// Светлая кромка по краю шапки: сверху 1,5 px, по бокам 3,5 px.
		hc = mix(hc, vec3(1.0), head_edge * (1.0 - smoothstep(0.0, mix(1.5, 3.5, abs(n.x)), din)));
		// Линия блика: по контуру верха на глубине spec_inset, огибает верхние скругления и, спускаясь по бокам,
		// сужается и гаснет; слева чуть ярче (как у блоков, block.gdshader).
		float y_side = min(radius, 0.5 * k);
		float sw = (1.0 - smoothstep(y_side - 6.0, y_side + 0.3 * k, y))
				* smoothstep(-0.2, 0.25, 0.35 - n.y)
				* mix(1.0, 0.75, smoothstep(lo.x + radius, hi.x - radius, p.x));
		float sd = (din - spec_inset) / mix(1.2, spec_width, sw);
		hc = mix(hc, vec3(1.0), spec_alpha * gloss * sw * exp(-sd * sd));
		float in_head = 1.0 - smoothstep(-aa, aa, y - k);
		float in_line = (1.0 - smoothstep(-aa, aa, y - k - line)) * (1.0 - in_head);
		face = mix(face, hc, in_head);
		face = mix(face, darken(head_line.rgb, line_dark), in_line);
		// Тень шапки на лицо: от разделителя вниз, мягко гаснет.
		float dy = y - k - line;
		face = mix(face, head_line.rgb, head_shadow * smoothstep(-aa, aa, dy) * exp(-max(dy, 0.0) / head_shadow_fall));
	}
	vec3 c = mix(lc, face, m_face);

	// Тень — губа (низ карточки), сдвинутая и размытая; карточка поверх неё.
	float d_sh = sd_box(p - shadow_offset, lo + down, hi + down, radius);
	float a_sh = shadow_color.a * fill(d_sh, max(1.9 * shadow_blur, aa));
	float a = m_body + a_sh * (1.0 - m_body);
	vec3 rgb = (c * m_body + shadow_color.rgb * a_sh * (1.0 - m_body)) / max(a, 0.0001);
	COLOR = vec4(rgb, a * COLOR.a);
}
