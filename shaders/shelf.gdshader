shader_type canvas_item;
// Полка лотка (docs/STYLE.md, раздел 10): корпус, три гнезда, штриховка пустого гнезда.
// Тени корпуса и гнёзд — внутренние по всей кромке (07.10; до этого — только в скруглённых углах, как на эталоне:
// пользователь — «странные тени у ячеек, некрасиво»).
// Рисует сам Tray: Tray._draw() кладёт прямоугольник полки (ряд гнёзд + shelf_pad со всех сторон)
// с этим материалом. Единицы — логические px экрана (полка в Content, масштаба нет).
// Гнёзда — прямоугольники слотов Slot0..2 в координатах полки (Tray.update_shelf).
// Эталон — Style.shelf в tools/style_a3.py (кадры A3B_game, A3B_desktop).

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 shelf_size = vec2(696.0, 256.0);
uniform vec4 well0 = vec4(12.0, 12.0, 216.0, 232.0);   // x, y, ширина, высота
uniform vec4 well1 = vec4(240.0, 12.0, 216.0, 232.0);
uniform vec4 well2 = vec4(468.0, 12.0, 216.0, 232.0);
uniform vec3 well_empty = vec3(0.0);                    // 1 — гнездо пустое (штриховка)
uniform float well_radius = 30.0;
uniform vec4 body_top : source_color = vec4(0.133, 0.055, 0.471, 0.59);
uniform vec4 body_bottom : source_color = vec4(0.204, 0.086, 0.588, 0.55);
uniform vec4 shade : source_color = vec4(0.055, 0.016, 0.235, 1.0);   // #0E043C
uniform vec2 body_shadow_offset = vec2(0.0, 7.0);
uniform float body_shadow_blur = 9.0;
uniform float body_shadow_alpha = 0.25;   // 07.10: тень по всей кромке (было 0,60 только в углах)
uniform float edge = 2.5;                               // белый кант по нижнему краю корпуса (как на A3B)
uniform float edge_alpha = 0.45;
uniform vec4 well_fill : source_color = vec4(0.627, 0.510, 1.0, 1.0); // rgba(160, 130, 255)
uniform float well_alpha = 0.15;
uniform float well_alpha_empty = 0.086;
uniform vec2 well_shadow_offset = vec2(0.0, 4.0);
uniform float well_shadow_blur = 5.0;
uniform float well_shadow_alpha = 0.30;   // 07.10: тень по всей кромке (было 0,45 только в углах)
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

vec4 draw_well(vec4 o, vec2 p, vec4 w, float is_empty, float aa) {
	vec2 lo = w.xy;
	vec2 hi = w.xy + w.zw;
	float d = sd_box(p, lo, hi, well_radius);
	float m = fill(d, aa);
	o = over(o, well_fill.rgb, m * mix(well_alpha, well_alpha_empty, is_empty));
	float sh = inset_sh(p - well_shadow_offset, lo, hi, well_radius, well_shadow_blur);
	o = over(o, shade.rgb, well_shadow_alpha * m * sh);
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
	vec2 p = UV * shelf_size;
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	// Корпус концентричен гнёздам: радиус гнезда + отступ гнезда от края полки.
	float inset = min(well0.x, well0.y);
	float rb = well_radius + inset;
	float d = sd_box(p, vec2(0.0), shelf_size, rb);
	float m = fill(d, aa);
	float t = clamp(p.y / shelf_size.y, 0.0, 1.0);
	vec4 bc = mix(body_top, body_bottom, t);
	vec4 o = vec4(bc.rgb, bc.a * m);
	float sh = inset_sh(p - body_shadow_offset, vec2(0.0), shelf_size, rb, body_shadow_blur);
	o = over(o, shade.rgb, body_shadow_alpha * m * sh);
	// Кант: корпус минус корпус, поднятый на edge, — полоска у нижнего края.
	float d_up = sd_box(p + vec2(0.0, edge), vec2(0.0), shelf_size, rb);
	o = over(o, vec3(1.0), edge_alpha * m * (1.0 - fill(d_up, aa)));
	o = draw_well(o, p, well0, well_empty.x, aa);
	o = draw_well(o, p, well1, well_empty.y, aa);
	o = draw_well(o, p, well2, well_empty.z, aa);
	COLOR = vec4(o.rgb, o.a * COLOR.a);
}
