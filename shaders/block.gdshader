shader_type canvas_item;
// Блок из материала «мармелад» (docs/STYLE.md, раздел 5) и его тень (раздел 7) — за один проход.
// Единицы — пиксели блока: клетка = cell (100). Узел Shape шире блока на margin с каждой стороны,
// в эти поля ложится тень. Цвет площади — COLOR (ColorRect.color; modulate предков в нём уже учтён:
// красное предупреждение и подсветка «нельзя» окрашивают весь материал).

uniform vec2 rect_size = vec2(200.0, 100.0);   // размер блока без полей под тень
uniform vec2 cells = vec2(2.0, 1.0);
uniform float margin = 24.0;
uniform float cell = 100.0;
uniform float radius = 0.24;    // скругление RC, доля клетки
uniform float gap = 0.045;      // зазор от края клетки GC
uniform float depth = 0.075;    // глубина губы
uniform vec2 num_center = vec2(100.0, 45.5);   // центр цифры: вокруг неё швы прерываются
uniform float seams = 1.0;
uniform float flash = 0.0;
// Смаз края при повороте (14.2, Block.rotate_cells), px блока: край лица и губы мягче на столько; 0 — чёткий.
uniform float smear = 0.0;
// Свет по клеткам, когда число закрыто (14.3, Block.close_number): от цифры (num_center) расходится волна радиусом
// glow_r, px блока; за ней лицо коротко светлеет к светлому тону площади. glow — сила (0 — нет).
uniform float glow = 0.0;
uniform float glow_r = 0.0;
// Мозаика на победе (14.5, Block.merge): 0 — обычный блок, 1 — зазор до merge_gap, скругление до merge_radius (доли
// клетки), швы между клетками погасли — блоки поля сходятся в одну картинку.
uniform float merge = 0.0;
uniform float merge_gap = 0.006;
uniform float merge_radius = 0.07;
// Трещина тупика (14.6g, Block.crack): от цифры (num_center) по лицу расходятся 4 ломаных луча — тёмная бороздка
// с бликом снизу; crack — сколько прошли (0 — нет, 1 — до дальнего угла).
uniform float crack = 0.0;
uniform vec2 shadow_offset = vec2(0.0, 7.0);
uniform float shadow_blur = 7.0;
uniform vec4 shadow_color : source_color = vec4(0.204, 0.086, 0.561, 0.34);
// Пикселей блока в одном логическом px экрана (1 / масштаб блока на экране, ставит Block):
// смещение и размытие тени заданы в логических px (STYLE, раздел 7) и не зависят от масштаба поля и лотка.
uniform float px = 1.0;

#include "res://shaders/sdf.gdshaderinc"

void fragment() {
	vec2 full = rect_size + vec2(2.0 * margin);
	vec2 p = UV * full - vec2(margin);
	vec3 col = COLOR.rgb;
	float k = cell;
	float g = mix(gap, merge_gap, merge) * k;
	float r = mix(radius, merge_radius, merge) * k;
	float dep = depth * k;
	float x0 = g;
	float y0 = g;
	float x1 = rect_size.x - g;
	float y1 = rect_size.y - g;
	float fy1 = y1 - dep;
	float fh = max(fy1 - y0, 1.0);
	// Сглаживание — около пикселя экрана при любом масштабе блока.
	float aa = max(fwidth(p.x), 0.0001) * 0.7;

	// 1. Губа: та же форма, сдвинута вниз на глубину.
	float d_face = sd_box(p, vec2(x0, y0), vec2(x1, fy1), r);
	float d_lip = sd_box(p, vec2(x0, y0 + dep), vec2(x1, y1), r);
	float ae = max(aa, smear);
	float m_face = fill(d_face, ae);
	float m_body = max(m_face, fill(d_lip, ae));
	float tl = clamp((p.y - y0) / max(y1 - y0, 1.0), 0.0, 1.0);
	vec3 c = mix(darken(col, 0.34), darken(col, 0.22), tl);

	// 2. Лицо: светлее(0,3) сверху -> цвет посередине -> темнее(0,07) снизу.
	float tf = clamp((p.y - y0) / fh, 0.0, 1.0);
	vec3 face = tf < 0.5 ? mix(lighten(col, 0.3), col, tf * 2.0) : mix(col, darken(col, 0.07), tf * 2.0 - 1.0);

	// 3. Объём по краю: кайма снаружи размытого ядра.
	float d_core = sd_box(p, vec2(x0 + 0.1 * k, y0 + 0.1 * k), vec2(x1 - 0.1 * k, fy1 - 0.1 * k), r * 0.8);
	face = mix(face, darken(col, 0.14), 0.32 * (1.0 - fill(d_core, 1.9 * 0.08 * k)));

	// 4. Свечение снизу: полоса над губой (40 %: с 07.10 чуть тише — под приглушённый блик сверху).
	float d_band = sd_box(p, vec2(x0 + 0.16 * k, fy1 - 0.2 * k), vec2(x1 - 0.16 * k, fy1 - 0.06 * k), 0.07 * k);
	face = mix(face, lighten(col, 0.55), 0.4 * fill(d_band, 1.9 * 0.05 * k));

	// 5. Глянец: верхняя половина лица, белый 31 % у края -> 0 на 55 % высоты.
	float d_sheen = sd_box(p, vec2(x0 + 0.08 * k, y0 + 0.06 * k), vec2(x1 - 0.08 * k, y0 + fh * 0.5), r * 0.8);
	float sheen_a = 0.31 * clamp(1.0 - (p.y - y0) / (fh * 0.55), 0.0, 1.0);
	face = mix(face, vec3(1.0), fill(d_sheen, 1.9 * 0.06 * k) * sheen_a);

	// 6. Изогнутый блик: серп по верхнему краю (внутренняя форма минус она же, сдвинутая вниз).
	float ins = 0.06 * k;
	float t = min(0.15 * k, fh * 0.28);
	float ri = max(1.0, r - ins);
	float s_c = max(1.9 * 0.014 * k, aa);
	float d_in = sd_box(p, vec2(x0 + ins, y0 + ins), vec2(x1 - ins, fy1 - ins), ri);
	float d_in_down = sd_box(p - vec2(0.0, t), vec2(x0 + ins, y0 + ins), vec2(x1 - ins, fy1 - ins), ri);
	float cres = fill(d_in, s_c) * (1.0 - fill(d_in_down, s_c));
	float y_a = y0 + ins + t;
	float y_b = y0 + fh * 0.5;
	float cres_a = p.y < y_a
			? mix(0.53, 0.37, clamp((p.y - y0) / max(y_a - y0, 1.0), 0.0, 1.0))
			: mix(0.37, 0.05, clamp((p.y - y_a) / max(y_b - y_a, 1.0), 0.0, 1.0));
	face = mix(face, vec3(1.0), cres * cres_a);

	c = mix(c, face, m_face);

	// 7. Швы между клетками: тёмная линия и белая рядом — под горизонтальной, справа от вертикальной (07.10: раньше
	// белая и у вертикальных лежала со сдвигом вниз, то есть на самой тёмной — они гасили друг друга, и шов домино
	// был почти не виден). Не доходят до краёв, дыра вокруг цифры. seams — их сила (0 — нет: таблетки кнопок);
	// в мозаике гаснут.
	float seam_k = clamp(seams, 0.0, 1.0) * (1.0 - merge);
	if (seam_k > 0.0) {
		float hw = max(0.01 * k, aa);
		float off = max(1.6, 0.016 * k);
		float drk = 0.0;
		float lit = 0.0;
		int nx = int(cells.x + 0.5);
		int ny = int(cells.y + 0.5);
		for (int i = 1; i < nx; i++) {
			float sx = float(i) * k;
			vec2 lo = vec2(sx - hw, 0.24 * k);
			vec2 hi = vec2(sx + hw, rect_size.y - dep - 0.22 * k);
			drk = max(drk, fill(sd_box(p, lo, hi, 0.0), aa));
			lit = max(lit, fill(sd_box(p - vec2(off, 0.0), lo, hi, 0.0), aa));
		}
		for (int j = 1; j < ny; j++) {
			float sy = float(j) * k - dep * float(j) / cells.y;
			vec2 lo = vec2(0.24 * k, sy - hw);
			vec2 hi = vec2(rect_size.x - 0.24 * k, sy + hw);
			drk = max(drk, fill(sd_box(p, lo, hi, 0.0), aa));
			lit = max(lit, fill(sd_box(p - vec2(0.0, off), lo, hi, 0.0), aa));
		}
		float hole = fill(length(p - num_center) - 0.34 * k, 1.9 * 0.03 * k);
		float keep = (1.0 - hole) * m_face * seam_k;
		c = mix(c, vec3(1.0), 0.16 * lit * keep);
		c = mix(c, darken(col, 0.35), 0.2 * drk * keep);
	}

	if (glow > 0.0) {
		float dn = length(p - num_center);
		float front = 1.0 - smoothstep(0.0, 0.35 * k, abs(dn - glow_r));
		float behind = 1.0 - smoothstep(glow_r - 0.15 * k, glow_r + 0.15 * k, dn);
		c = mix(c, lighten(col, 0.85), glow * max(front, 0.5 * behind) * m_face);
	}

	if (crack > 0.0) {
		vec2 dc = p - num_center;
		float far = max(max(length(num_center), length(num_center - vec2(rect_size.x, 0.0))),
				max(length(num_center - vec2(0.0, rect_size.y)), length(num_center - rect_size)));
		float seed = 0.6 + cells.x * 0.9 + cells.y * 1.3;
		float groove = 0.0;
		float shine = 0.0;
		for (int i = 0; i < 4; i++) {
			float fi = float(i);
			float h = fract(sin(fi * 12.9898 + seed * 78.233) * 43758.5453);
			float ang = seed + fi * 1.5708 + (h - 0.5) * 0.9;
			vec2 u = vec2(cos(ang), sin(ang));
			vec2 n = vec2(-u.y, u.x);
			float reach = crack * far * (0.6 + 0.4 * h);
			float along = dot(dc, u);
			// Излом каждые 0,2 клетки: смещение поперёк луча — между случайными узлами.
			float sg = max(along, 0.0) / (0.2 * k);
			float z0 = fract(sin((floor(sg) + fi * 7.0 + seed) * 12.9898) * 43758.5453) - 0.5;
			float z1 = fract(sin((floor(sg) + 1.0 + fi * 7.0 + seed) * 12.9898) * 43758.5453) - 0.5;
			float off = mix(z0, z1, fract(sg)) * 0.16 * k * clamp(along / (0.3 * k), 0.0, 1.0);
			float w = 0.026 * k * (1.0 - 0.6 * clamp(along / max(reach, 0.001), 0.0, 1.0)) + 0.5 * aa;
			float on = step(0.0, along) * (1.0 - smoothstep(reach - 0.06 * k, reach, along));
			float dist = abs(dot(dc, n) - off);
			groove = max(groove, on * (1.0 - smoothstep(w - aa, w + aa, dist)));
			float dist_lit = abs(dot(dc - vec2(0.0, 0.03 * k), n) - off);
			shine = max(shine, on * (1.0 - smoothstep(w - aa, w + aa, dist_lit)));
		}
		c = mix(c, lighten(col, 0.55), 0.7 * max(shine - groove, 0.0) * m_face);
		c = mix(c, darken(col, 0.62), 0.9 * groove * m_face);
	}

	c = mix(c, vec3(1.0), flash);

	// Тень — вся форма блока (с губой), смещённая и размытая; блок поверх неё.
	float d_all = sd_box(p - shadow_offset * px, vec2(x0, y0), vec2(x1, y1), r);
	float a_sh = shadow_color.a * fill(d_all, max(1.9 * shadow_blur * px, aa)) * COLOR.a;
	float a_body = m_body * COLOR.a;
	float a = a_body + a_sh * (1.0 - a_body);
	vec3 rgb = (c * a_body + shadow_color.rgb * a_sh * (1.0 - a_body)) / max(a, 0.0001);
	COLOR = vec4(rgb, a);
}
