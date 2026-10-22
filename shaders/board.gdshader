shader_type canvas_item;
// Поле (docs/STYLE.md, раздел 6): тень, бортик с губой, утопленный лоток, ячейки с внутренней тенью.
// Один ColorRect на всё поле (Board/Frame). Единицы — локальные px поля: клетка = cell (100).
// Величины из STYLE в логических px экрана (pad, rim, тени) умножаются на px = 1 / масштаб поля,
// поэтому рамка и тени одинаковы на экране при любом размере поля. Узел Frame шире рамки на margin
// с каждой стороны (поля под тень). Числа-«гнёзда», призрак и блоки — отдельные узлы поверх.

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 frame_size = vec2(1000.0, 1000.0);   // размер узла Frame, локальные px
uniform vec2 grid = vec2(6.0, 6.0);               // клеток по горизонтали и вертикали
uniform float cell = 100.0;
uniform float px = 1.0;                           // локальных px в логическом px экрана
uniform float margin = 72.0;                      // поля под тень вокруг рамки, px
uniform float pad = 26.0;                         // от ячеек до наружного края бортика, px
uniform float rim = 15.0;                         // ширина бортика, px
uniform float lip = 12.0;                         // губа бортика под полем, px
uniform float radius = 0.24;                      // RC: скругление ячейки, доля клетки
uniform float gap = 0.045;                        // GC: зазор от края клетки до ячейки
// Секунды с начала появления: ячейки вырастают волной по диагонали, ячейка (x, y) — через appear_step · (x + y)
// (JuiceConfig.intro_cell_step; число выпрыгивает после своей ячейки — Cell.appear). Большое значение — все на месте.
uniform float appear = 100.0;
uniform float appear_step = 0.03;
uniform vec4 shadow_color : source_color = vec4(0.133, 0.055, 0.431, 0.50);
uniform vec2 shadow_offset = vec2(0.0, 16.0);
uniform float shadow_blur = 22.0;
uniform vec4 lip_top : source_color = vec4(0.718, 0.635, 0.965, 1.00);
uniform vec4 lip_bottom : source_color = vec4(0.616, 0.518, 0.933, 1.00);
uniform vec4 face_top : source_color = vec4(1.000, 1.000, 1.000, 1.00);
uniform vec4 face_bottom : source_color = vec4(0.929, 0.902, 1.000, 1.00);
uniform vec4 tray_top : source_color = vec4(0.722, 0.647, 0.965, 1.00);
uniform vec4 tray_bottom : source_color = vec4(0.776, 0.714, 0.976, 1.00);
uniform vec4 tray_shadow : source_color = vec4(0.290, 0.184, 0.722, 0.62);
uniform vec2 tray_shadow_offset = vec2(0.0, 7.0);
uniform float tray_shadow_blur = 8.0;
uniform float tray_edge = 2.0;                    // белый кант под нижним краем лотка, px
uniform float tray_edge_alpha = 0.9;
uniform vec4 well_top : source_color = vec4(0.867, 0.827, 0.992, 1.00);
uniform vec4 well_bottom : source_color = vec4(0.914, 0.886, 1.000, 1.00);
uniform vec4 well_shadow : source_color = vec4(0.478, 0.369, 0.878, 0.50);
uniform vec2 well_shadow_offset = vec2(0.0, 3.5);
uniform float well_shadow_blur = 3.0;

// Кривая Godot TRANS_BACK + EASE_OUT (перелёт ~10 %), как у Tween в Cell.appear.
float back_out(float t) {
	float c1 = 1.70158;
	float u = t - 1.0;
	return 1.0 + (c1 + 1.0) * u * u * u + c1 * u * u;
}

// Внутренняя тень формы со знаковым расстоянием d_shifted (форма, сдвинутая на смещение тени):
// сила тени внутри формы — размытая «внешность» сдвинутой формы.
float inner_sh(float d_shifted, float blur) {
	return 1.0 - fill(d_shifted, max(1.9 * blur, 0.0001));
}

void fragment() {
	float m = margin * px;
	float pd = pad * px;
	float rm = rim * px;
	float lp = lip * px;
	vec2 size = grid * cell;
	// p — от левого верхнего угла сетки клеток.
	vec2 p = UV * frame_size - vec2(m + pd);
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	float g = gap * cell;
	float rw = radius * cell;                     // ячейка
	float rt = rw + (pd - rm) + g;                // лоток: концентричен ячейке
	float rb = rt + rm;                           // бортик: концентричен лотку
	vec2 lo = vec2(-pd);
	vec2 hi = size + vec2(pd);
	float full_h = hi.y + lp - lo.y;              // высота рамки вместе с губой
	float t = clamp((p.y - lo.y) / full_h, 0.0, 1.0);

	// 1. Тень всей рамки (с губой).
	float d_lip = sd_box(p, lo + vec2(0.0, lp), hi + vec2(0.0, lp), rb);
	float d_lip_sh = sd_box(p - shadow_offset * px, lo + vec2(0.0, lp), hi + vec2(0.0, lp), rb);
	vec4 o = vec4(shadow_color.rgb, shadow_color.a * fill(d_lip_sh, max(1.9 * shadow_blur * px, aa)));

	// 2. Губа бортика: та же форма ниже на lip.
	vec3 lip_c = mix(lip_top.rgb, lip_bottom.rgb, clamp((t - 0.6) / 0.4, 0.0, 1.0));
	o = over(o, lip_c, fill(d_lip, aa));

	// 3. Лицо бортика.
	float d_face = sd_box(p, lo, hi, rb);
	o = over(o, mix(face_top.rgb, face_bottom.rgb, t), fill(d_face, aa));

	// 4. Утопленный лоток: заливка, внутренняя тень сверху, белый кант под нижним краем.
	vec2 tlo = lo + vec2(rm);
	vec2 thi = hi - vec2(rm);
	float d_tray = sd_box(p, tlo, thi, rt);
	float m_tray = fill(d_tray, aa);
	o = over(o, mix(tray_top.rgb, tray_bottom.rgb, t), m_tray);
	float d_tray_sh = sd_box(p - tray_shadow_offset * px, tlo, thi, rt);
	o = over(o, tray_shadow.rgb, tray_shadow.a * m_tray * inner_sh(d_tray_sh, tray_shadow_blur * px));
	float d_edge = sd_box(p - vec2(0.0, tray_edge * px), tlo, thi, rt);
	o = over(o, vec3(1.0), tray_edge_alpha * fill(d_edge, aa) * (1.0 - m_tray));

	// 5. Ячейка той клетки, над которой пиксель.
	vec2 idx = floor(p / cell);
	if (idx.x >= 0.0 && idx.y >= 0.0 && idx.x < grid.x && idx.y < grid.y) {
		vec2 q = p - idx * cell;
		vec2 ctr = vec2(cell * 0.5);
		// Появление: масштаб 0,3 -> 1 с перелётом за 0,35 с, задержка appear_step на шаг диагонали.
		float u = clamp((appear - appear_step * (idx.x + idx.y)) / 0.35, 0.0, 1.0);
		float k = max(mix(0.3, 1.0, back_out(u)), 0.01);
		float vis = clamp(u * 2.5, 0.0, 1.0);
		vec2 qs = (q - ctr) / k + ctr;
		float d_well = sd_box(qs, vec2(g), vec2(cell - g), rw) * k;
		float m_well = fill(d_well, aa) * vis;
		float tw = clamp((qs.y - g) / (cell - 2.0 * g), 0.0, 1.0);
		o = over(o, mix(well_top.rgb, well_bottom.rgb, tw), m_well);
		float d_well_sh = sd_box(qs - well_shadow_offset * px / k, vec2(g), vec2(cell - g), rw) * k;
		o = over(o, well_shadow.rgb, well_shadow.a * m_well * inner_sh(d_well_sh, well_shadow_blur * px));
	}

	COLOR = vec4(o.rgb, o.a * COLOR.a);
}
