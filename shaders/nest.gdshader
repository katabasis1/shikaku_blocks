shader_type canvas_item;
// «Гнездо» числа (docs/STYLE.md, раздел 6): квадрат 0,7 C в ячейке, скругление концентрично ячейке.
// Вид — по картинке-референсу (20.8, правило 27.11: docs/shader_refs/nest.jpg): кант — глянцевая «трубка»
// цвета площади (сверху светлее, снизу гуще, блик по верху, искра в левом верхнем углу), внутри — светлая
// подушка, чуть утопленная: тень под верхним кантом, отсвет у нижнего; под гнездом — мягкая тень на клетку.
// Магнит (ring = 1): тёплый ореол цвета площади и кремово-белое кольцо снаружи; ×1,08 и подъём на 4 px — узел Badge.
// Узел Nest шире клетки на margin (локальные px поля) с каждой стороны — под ореол.
// Цвет площади — COLOR (ColorRect.color, ставит Cell.set_value; у приглушённых альфа меньше); px = 1 / масштаб поля.

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
uniform float ring_in = 1.0;       // px снаружи гнезда
uniform float ring_out = 5.5;      // px
uniform float edge = 9.0;          // кант («трубка»), px
uniform vec2 shadow_offset = vec2(0.0, 3.0);   // внутренняя тень под верхним кантом
uniform float shadow_blur = 3.0;

void fragment() {
	vec2 p = UV * vec2(cell + 2.0 * margin) - vec2(margin);
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	vec3 col = COLOR.rgb;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 deep = clamp(mix(vec3(luma), col, 1.15), vec3(0.0), vec3(1.0));
	// Густой тон площади: цвет, умноженный на себя, — темнее и насыщеннее (жёлтый уходит в оранжевый, а не в олив).
	vec3 rich = mix(deep, deep * deep, 0.85);
	float s = side * cell;
	float inset = (cell * (1.0 - 2.0 * gap) - s) * 0.5;
	float rp = max(radius * cell - inset, s * 0.14);
	vec2 lo = vec2((cell - s) * 0.5);
	vec2 hi = lo + vec2(s);
	float d = sd_box(p, lo, hi, rp);
	vec4 o = vec4(col, 0.0);

	// 1. Тень гнезда на клетку: та же форма ниже на 2 px, мягкая (у магнита её закрывает кольцо).
	float d_drop = sd_box(p - vec2(0.0, 2.0) * px, lo, hi, rp);
	o = over(o, darken(deep, 0.5), 0.2 * fill(d_drop, max(1.9 * 2.5 * px, aa)));

	// 2. Магнит: тёплый ореол (размытая форма гнезда, светлее цвета площади) и кремово-белое кольцо с бликом.
	if (ring > 0.001) {
		// Ореол: узкий яркий у кольца и широкий мягкий; пульс расширяет широкий.
		float h_near = fill(d - ring_out * px, max(1.9 * 2.5 * px, aa));
		float h_far = fill(d - ring_out * px, max(1.9 * halo_blur * (1.0 + 0.45 * pulse) * px, aa));
		float a_far = (1.0 - pow(1.0 - h_far, 3.0)) * (1.0 - 0.35 * pulse);
		o = over(o, lighten(deep, 0.35), 0.75 * a_far * ring);
		o = over(o, lighten(deep, 0.45), 0.85 * h_near * ring);
		float m_ring = fill(d - ring_out * px, aa) * (1.0 - fill(d - ring_in * px, aa));
		float ty = clamp((p.y - lo.y + ring_out * px) / (s + 2.0 * ring_out * px), 0.0, 1.0);
		o = over(o, mix(vec3(1.0), lighten(deep, 0.9), smoothstep(0.6, 1.0, ty)), m_ring * ring);
	}

	// 3. Кант-«трубка»: поперёк канта u от -1 (снаружи) до 1 (внутри); нормаль трубки наклонена наружу у внешнего
	// края и внутрь у внутреннего; свет сверху и чуть на зрителя. ny — вертикальная доля нормали контура.
	float e = edge * px;
	float u = clamp(-d / e, 0.0, 1.0) * 2.0 - 1.0;
	float ny = sd_box(p + vec2(0.0, 0.5), lo, hi, rp) - sd_box(p - vec2(0.0, 0.5), lo, hi, rp);
	float nz = sqrt(max(1.0 - u * u, 0.0));
	float lam = clamp(0.55 * u * ny + 0.835 * nz, 0.0, 1.0);
	vec3 tube = lam < 0.65 ? mix(rich, deep, lam / 0.65) : mix(deep, lighten(deep, 0.35), (lam - 0.65) / 0.35);
	// Блик по верху канта и тонкий отсвет у внутреннего края снизу.
	float spec = pow(lam, 14.0) * mix(0.25, 0.9, clamp(-ny, 0.0, 1.0));
	tube = mix(tube, vec3(1.0), spec);
	// Тонкая тёмная кромка снаружи — гнездо отделяется от клетки (снизу заметнее).
	float outer = 1.0 - smoothstep(0.0, 1.2 * px, -d);
	tube = mix(tube, darken(rich, 0.12), outer * mix(0.2, 0.55, clamp(ny * 0.5 + 0.5, 0.0, 1.0)));

	// 4. Подушка: светлый тон площади, тень под верхним кантом (внутренняя), отсвет над нижним, тёмный шов у канта.
	float d_pad = d + e;
	float t = clamp((p.y - lo.y) / s, 0.0, 1.0);
	vec3 pad = mix(lighten(col, 0.8), lighten(col, 0.74), t);
	float d_sh = sd_box(p - shadow_offset * px, lo + vec2(e), hi - vec2(e), max(rp - e, 1.0));
	float a_sh = 0.7 * (1.0 - fill(d_sh, max(1.9 * shadow_blur * px, aa)));
	pad = mix(pad, mix(lighten(col, 0.45), rich, 0.25), a_sh);
	float d_up = sd_box(p + vec2(0.0, 2.5) * px, lo + vec2(e), hi - vec2(e), max(rp - e, 1.0));
	pad = mix(pad, vec3(1.0), 0.35 * (1.0 - fill(d_up, max(1.9 * 1.5 * px, aa))) * step(0.5, t));
	float seam = 1.0 - smoothstep(0.0, 1.4 * px, -d_pad);
	pad = mix(pad, darken(rich, 0.18), 0.5 * seam);

	vec3 nest = mix(tube, pad, fill(d_pad, aa));

	o = over(o, nest, fill(d, aa));

	// 5. Искра в левом верхнем углу канта: четырёхлучевая звёздочка с ярким ядром; у магнита крупнее и ярче.
	vec2 sc = lo + vec2(rp * 0.34 + e * 0.3);
	vec2 q = (p - sc) / (px * (1.0 + 0.35 * ring));
	float rays = max(exp(-abs(q.x) * 1.1) * (1.0 - smoothstep(0.0, 11.0, abs(q.y))),
			exp(-abs(q.y) * 1.1) * (1.0 - smoothstep(0.0, 11.0, abs(q.x))));
	float star = clamp(max(rays, exp(-dot(q, q) * 0.07)), 0.0, 1.0);
	o = over(o, vec3(1.0), star * mix(0.7, 0.95, ring));

	COLOR = vec4(o.rgb, o.a * COLOR.a);
}
