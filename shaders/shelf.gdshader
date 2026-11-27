shader_type canvas_item;
// Полка лотка (docs/STYLE.md, раздел 10): корпус, три гнезда, штриховка пустого гнезда.
// Вид — по картинке-референсу (20.8, правило 27.11: docs/shader_refs/shelf_tray.jpg, промпт П3 в PROMPTS.md):
// толстая полка из тёмного полупрозрачного фиолетового «леденца» — выпуклый ободок по кромке лица (светлее сверху)
// с тонкой линией блика по верху (огибает верхние скругления и гаснет на боках), губа-толщина под лицом и мягкая
// тень под полкой; гнёзда утоплены — тень под верхним краем, светлая кромка по низу (тает на скруглениях).
// Рисует сам Tray: Tray._draw() кладёт прямоугольник корпуса (ряд гнёзд + shelf_pad со всех сторон), расширенный
// на outer (Tray.SHELF_OUTER) — в этих полях губа и тень. Единицы — логические px экрана (полка в Content,
// масштаба нет). Гнёзда — прямоугольники слотов Slot0..2 в координатах корпуса (Tray.update_shelf).

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 shelf_size = vec2(696.0, 256.0);           // корпус (лицо) полки
uniform float outer = 0.0;                               // поля прямоугольника рисования вокруг корпуса, px
uniform vec4 well0 = vec4(12.0, 12.0, 216.0, 232.0);   // x, y, ширина, высота
uniform vec4 well1 = vec4(240.0, 12.0, 216.0, 232.0);
uniform vec4 well2 = vec4(468.0, 12.0, 216.0, 232.0);
uniform vec3 well_empty = vec3(0.0);                    // 1 — гнездо пустое (штриховка)
uniform float well_radius = 30.0;
uniform vec4 body_top : source_color = vec4(0.227, 0.11, 0.549, 0.7);
uniform vec4 body_bottom : source_color = vec4(0.275, 0.133, 0.635, 0.66);
uniform vec4 shade : source_color = vec4(0.055, 0.016, 0.235, 1.0);   // #0E043C
// Губа — толщина полки: корпус, опущенный на lip, виден полоской под лицом.
uniform float lip = 9.0;
uniform vec4 lip_color : source_color = vec4(0.2, 0.09, 0.5, 0.76);
// Тень под полкой (снаружи корпуса и губы).
uniform vec2 drop_offset = vec2(0.0, 11.0);
uniform float drop_blur = 7.0;
uniform float drop_alpha = 0.55;
// Выпуклый ободок по кромке лица: светлее у внешнего края, сверху ярче, на боках и снизу слабее (свет сверху).
uniform float rim_width = 10.0;
uniform vec4 rim_color : source_color = vec4(0.72, 0.56, 1.0, 1.0);
uniform float rim_alpha = 0.40;
uniform float groove_alpha = 0.16;                      // тёмная бороздка по внутреннему краю ободка
// Линия блика по верху ободка.
uniform float spec_inset = 2.5;                          // центр линии от края лица, px
uniform float spec_width = 2.4;                          // полуширина линии посередине верха, px
uniform float spec_alpha = 0.72;
// Кант по нижнему краю лица — светлая кромка над губой.
uniform float edge = 2.5;
uniform float edge_alpha = 0.28;
// Гнездо: чуть темнее лица (тон shade), тень под верхним краем, светлая кромка по низу.
uniform float well_tint = 0.04;
uniform float well_tint_empty = 0.03;
uniform vec2 well_shadow_offset = vec2(0.0, 6.0);
uniform float well_shadow_blur = 5.0;
uniform float well_shadow_alpha = 0.42;
uniform float well_rim_inset = 2.2;                      // центр кромки от края гнезда, px
uniform float well_rim_width = 1.3;                      // полуширина кромки посередине низа, px
uniform float well_rim_alpha = 0.55;
uniform float dash_inset = 10.0;                        // штриховка: рамка от 10 до 13 px внутри гнезда
uniform float dash_width = 3.0;
uniform float dash_period = 22.0;                       // рамку режут диагональные полосы x + y = 22·n
uniform float dash_fill = 0.58;                         // доля периода под штрихом (полоса 9 px поперёк)
uniform float dash_alpha = 0.22;

// Внутренняя тень утопленной формы (как у ячеек поля, board.gdshader): форма, сдвинутая на смещение тени,
// закрывает свет; там, где она не достаёт, — тень. Сверху полоса во всю кромку, изогнутая по скруглению
// углов; по бокам тонкая, снизу её нет. p_sh — точка, сдвинутая на смещение тени.
float inset_sh(vec2 p_sh, vec2 lo, vec2 hi, float r, float blur) {
	return 1.0 - fill(sd_box(p_sh, lo, hi, r), max(1.9 * blur, 0.0001));
}

// Тонкая линия вдоль контура на глубине inset (din — глубина точки внутри формы, px), полуширина hw.
float contour_line(float din, float inset, float hw, float aa) {
	return 1.0 - smoothstep(hw - aa, hw + aa, abs(din - inset));
}

vec4 draw_well(vec4 o, vec2 p, vec4 w, float is_empty, float aa) {
	vec2 lo = w.xy;
	vec2 hi = w.xy + w.zw;
	float d = sd_box(p, lo, hi, well_radius);
	float m = fill(d, aa);
	o = over(o, shade.rgb, m * mix(well_tint, well_tint_empty, is_empty));
	float sh = inset_sh(p - well_shadow_offset, lo, hi, well_radius, well_shadow_blur);
	o = over(o, shade.rgb, well_shadow_alpha * m * sh);
	// Светлая кромка по низу: идёт по контуру гнезда, на нижних скруглениях сужается и тает (вес — нормаль вниз).
	vec2 n = box_normal(p, lo, hi, well_radius);
	float rw = smoothstep(0.3, 0.97, n.y);
	float rim = contour_line(-d, well_rim_inset, mix(0.3, well_rim_width, rw), aa);
	o = over(o, rim_color.rgb, well_rim_alpha * rim * rw * m);
	if (is_empty > 0.5) {
		// Рамка шириной dash_width внутрь от скруглённого прямоугольника с отступом dash_inset.
		float di = sd_box(p, lo + vec2(dash_inset), hi - vec2(dash_inset), well_radius - dash_inset);
		float line = 1.0 - smoothstep(dash_width * 0.5 - aa, dash_width * 0.5 + aa, abs(di + dash_width * 0.5));
		// Штрихи — по полосам x + y = dash_period·n (от угла гнезда), полоса по центру штриха.
		vec2 q = p - lo;
		float f = fract((q.x + q.y) / dash_period + dash_fill * 0.5);
		float k = aa / dash_period;
		float dash = smoothstep(0.0, k * 2.0, f) * (1.0 - smoothstep(dash_fill - k * 2.0, dash_fill, f));
		o = over(o, vec3(1.0), dash_alpha * line * dash);
	}
	return o;
}

void fragment() {
	vec2 p = UV * (shelf_size + vec2(2.0 * outer)) - vec2(outer);
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	// Корпус концентричен гнёздам: радиус гнезда + отступ гнезда от края полки.
	float inset = min(well0.x, well0.y);
	float rb = well_radius + inset;
	vec2 lo = vec2(0.0);
	vec2 hi = shelf_size;
	float d = sd_box(p, lo, hi, rb);
	float m = fill(d, aa);
	// 1. Губа и тень под полкой — только снаружи лица: лицо полупрозрачное, сквозь него их не видно.
	float m_lip = fill(sd_box(p - vec2(0.0, lip), lo, hi, rb), aa);
	float drop = fill(sd_box(p - drop_offset, lo, hi, rb), 1.9 * drop_blur);
	vec4 o = vec4(shade.rgb, drop_alpha * drop * (1.0 - max(m, m_lip)));
	o = over(o, lip_color.rgb, lip_color.a * m_lip * (1.0 - m));
	// 2. Лицо.
	float t = clamp(p.y / shelf_size.y, 0.0, 1.0);
	vec4 bc = mix(body_top, body_bottom, t);
	o = over(o, bc.rgb, bc.a * m);
	// 3. Ободок: светлее у внешнего края лица, к rim_width гаснет; сила — по нормали контура (сверху 1, бока и низ 0,5).
	float din = -d;
	vec2 n = box_normal(p, lo, hi, rb);
	float lit = mix(0.5, 1.0, smoothstep(-0.2, 0.9, -n.y));
	float rim = 1.0 - smoothstep(0.0, rim_width, din);
	o = over(o, rim_color.rgb, rim_alpha * rim * lit * m);
	o = over(o, shade.rgb, groove_alpha * contour_line(din, rim_width, 0.8, aa) * m);
	// 4. Линия блика по верху (как у блоков, block.gdshader): идёт по всему верху, огибает верхние скругления
	// и, спускаясь по бокам, сужается и гаснет; слева чуть ярче.
	float y_side = min(rb, shelf_size.y * 0.5);
	float sw = (1.0 - smoothstep(y_side - 10.0, y_side + min(rb * 0.5, shelf_size.y * 0.2), p.y))
			* smoothstep(-0.2, 0.25, 0.35 - n.y)
			* mix(1.0, 0.8, smoothstep(rb, shelf_size.x - rb, p.x));
	float spec = contour_line(din, spec_inset, mix(0.3, spec_width, sw), aa);
	o = over(o, lighten(rim_color.rgb, 0.4), spec_alpha * spec * sw * m);
	// 5. Кант по нижнему краю лица: лицо минус лицо, поднятое на edge, — серп у низа, на скруглениях сходит на нет.
	float d_up = sd_box(p + vec2(0.0, edge), lo, hi, rb);
	o = over(o, rim_color.rgb, edge_alpha * m * (1.0 - fill(d_up, aa)));
	// 6. Гнёзда.
	o = draw_well(o, p, well0, well_empty.x, aa);
	o = draw_well(o, p, well1, well_empty.y, aa);
	o = draw_well(o, p, well2, well_empty.z, aa);
	COLOR = vec4(o.rgb, o.a * COLOR.a);
}
