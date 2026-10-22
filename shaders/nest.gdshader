shader_type canvas_item;
// «Гнездо» числа (docs/STYLE.md, раздел 6): квадрат 0,7 C в ячейке, скругление концентрично ячейке;
// заливка светлее(цвет, 0,78) -> светлее(цвет, 0,6), внутренняя тень вниз 3 px (размытие 3 px,
// темнее(цвет, 0,25) 55 %), кант 4 px цветом площади. Магнит (ring = 1): ореол цвета площади
// (размытие 11 px) и белое кольцо от 2,5 до 7 px снаружи гнезда; ×1,08 и подъём на 4 px — узел Badge.
// Узел Nest шире клетки на margin (локальные px поля) с каждой стороны — под ореол.
// Цвет площади — COLOR (ColorRect.color, ставит Cell.set_value); px = 1 / масштаб поля.

#include "res://shaders/sdf.gdshaderinc"

uniform float cell = 100.0;
uniform float margin = 48.0;       // поля узла вокруг клетки, локальные px поля
uniform float radius = 0.24;       // RC ячейки
uniform float gap = 0.045;         // GC ячейки
uniform float side = 0.7;          // сторона гнезда, доля клетки
uniform float px = 1.0;            // локальных px поля в логическом px экрана
uniform float ring = 0.0;          // магнит: 0 — нет, 1 — ореол и кольцо
uniform float pulse = 0.0;         // 14.2: пульс ореола магнита 0…1 (Cell): ореол шире и прозрачнее
uniform float halo_blur = 11.0;    // px
uniform float ring_in = 2.5;       // px снаружи гнезда
uniform float ring_out = 7.0;      // px
uniform float edge = 4.0;          // кант, px
uniform vec2 shadow_offset = vec2(0.0, 3.0);
uniform float shadow_blur = 3.0;

void fragment() {
	vec2 p = UV * vec2(cell + 2.0 * margin) - vec2(margin);
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	vec3 col = COLOR.rgb;
	float s = side * cell;
	float inset = (cell * (1.0 - 2.0 * gap) - s) * 0.5;
	float rp = max(radius * cell - inset, s * 0.14);
	vec2 lo = vec2((cell - s) * 0.5);
	vec2 hi = lo + vec2(s);
	float d = sd_box(p, lo, hi, rp);
	vec4 o = vec4(col, 0.0);

	// Магнит: ореол (размытая форма гнезда, наложена трижды) и белое кольцо.
	if (ring > 0.001) {
		float h = fill(d, max(1.9 * halo_blur * (1.0 + 0.45 * pulse) * px, aa));
		float a_halo = 1.0 - pow(1.0 - h, 3.0);
		o = over(o, col, a_halo * ring * (1.0 - 0.35 * pulse));
		float m_ring = fill(d - ring_out * px, aa) * (1.0 - fill(d - ring_in * px, aa));
		o = over(o, vec3(1.0), m_ring * ring);
	}

	// Гнездо: заливка, внутренняя тень, кант.
	float m_pad = fill(d, aa);
	float t = clamp((p.y - lo.y) / s, 0.0, 1.0);
	vec3 fill_c = mix(lighten(col, 0.78), lighten(col, 0.6), mix(0.176, 0.824, t));
	o = over(o, fill_c, m_pad);
	float d_sh = sd_box(p - shadow_offset * px, lo, hi, rp);
	float a_sh = 0.55 * m_pad * (1.0 - fill(d_sh, max(1.9 * shadow_blur * px, 0.0001)));
	o = over(o, darken(col, 0.25), a_sh);
	float m_edge = m_pad * (1.0 - fill(d + edge * px, aa));
	o = over(o, col, m_edge);

	COLOR = vec4(o.rgb, o.a * COLOR.a);
}
