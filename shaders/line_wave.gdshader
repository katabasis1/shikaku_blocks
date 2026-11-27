shader_type canvas_item;
// Волна света по закрытой линии (14.4, LineFlash; docs/STYLE.md, раздел 12, «Линия и серия»). Узел — ColorRect
// во всю линию (строка или столбец поля, px поля). От origin к обоим концам вдоль длинной стороны бежит полоса
// света шириной band, путь фронта от origin — front; strength — сила (0 — нет). Цвет узла белый; modulate — в COLOR.
// Вид — по картинке-референсу (20.8: docs/shader_refs/line_wave.jpg, П10 в PROMPTS.md): свет живёт только в блоках
// линии, а не ровной белой плашкой поверх всей линии, поэтому блоки не бледнеют и зазоры между ними не светятся:
//   - форма — тела блоков линии (лицо + губа, как в block.gdshader: зазор gap, скругление radius, губа depth).
//     parts — прямоугольники блоков, задевающих линию (целиком, px узла; ставит Board.flash_line), part_count —
//     сколько их. Блоков нет (part_count = 0) — вся линия скруглённым прямоугольником radius, как раньше;
//   - гребень: белое ядро (Гаусс шириной core от band) и мягкое свечение вокруг (glow_gain), к низу строки ярче
//     (across_min вверху); у краёв узла поперёк линии гаснет за soft_edge — блок, который идёт дальше линии, не
//     режется по прямой;
//   - позади фронта вместо плашки — свет по кромке блоков (rim_gain × trail, гаснет вглубь за rim px) и лёгкая
//     дымка к низу строки (trail_fill);
//   - по нижней кромке губы — тонкая яркая полоса блика (streak_*): ярче всего у гребня, позади него — streak_trail.
//     На нижних скруглениях сужается и тает (нормаль контура вниз), как блик губы у блока.

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 rect_size = vec2(600.0, 100.0);
uniform float radius = 24.0;
uniform vec2 origin = vec2(300.0, 50.0);
uniform float front = 0.0;
uniform float band = 120.0;
uniform float trail = 0.35;
uniform float strength = 0.0;
uniform vec4 parts[16];
uniform int part_count = 0;
uniform float gap = 4.5;
uniform float depth = 7.5;
uniform float core = 0.55;
uniform float glow_gain = 0.6;
uniform float across_min = 0.75;
uniform float soft_edge = 22.0;
uniform float rim = 13.0;
uniform float rim_gain = 1.8;
uniform float trail_fill = 0.35;
uniform float streak_in = 3.0;
uniform float streak_w = 2.4;
uniform float streak_gain = 1.0;
uniform float streak_trail = 0.9;
uniform vec4 wave_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 p = UV * rect_size;
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	// Ближайший блок линии: расстояние до его тела (минус — внутри) и нормаль контура губы.
	float d = 100000.0;
	vec2 n = vec2(0.0, 1.0);
	for (int i = 0; i < part_count; i++) {
		vec4 q = parts[i];
		vec2 lo = q.xy + vec2(gap);
		vec2 hi = q.xy + q.zw - vec2(gap);
		float di = min(sd_box(p, lo, hi - vec2(0.0, depth), radius), sd_box(p, lo + vec2(0.0, depth), hi, radius));
		vec2 ni = box_normal(p, lo + vec2(0.0, depth), hi, radius);
		float k = step(di, d);
		n = mix(n, ni, k);
		d = min(d, di);
	}
	float none = step(float(part_count), 0.5);
	d = mix(d, sd_box(p, vec2(0.0), rect_size, radius), none);
	n = mix(n, box_normal(p, vec2(0.0), rect_size, radius), none);
	float mask = fill(d, aa);

	// Путь от точки старта вдоль линии (по x у строки, по y у столбца) в долях band: 0 — гребень, минус — позади.
	float horiz = step(rect_size.y, rect_size.x);
	float s = mix(abs(p.y - origin.y), abs(p.x - origin.x), horiz);
	float x = (s - front) / max(band, 1.0);
	float glow = exp(-8.0 * x * x);
	float hot = exp(-8.0 * x * x / max(core * core, 0.0001));
	float behind = 1.0 - smoothstep(-0.35, 0.0, x);
	float inside = max(-d, 0.0);
	float edge = exp(-inside / max(rim, 0.001));
	// Поперёк линии: 0 — верх строки, 1 — низ (у столбца — везде 1); до края узла поперёк — cut, px.
	float acr = mix(1.0, smoothstep(-0.2, 1.0, p.y / max(rect_size.y, 1.0)), horiz);
	float cut = mix(min(p.x, rect_size.x - p.x), min(p.y, rect_size.y - p.y), horiz);
	float crest = (hot + glow * (glow_gain + 0.4 * edge)) * mix(across_min, 1.0, acr) * smoothstep(0.0, soft_edge, cut);
	float bw = smoothstep(0.3, 0.97, n.y);
	float t = (inside - streak_in) / max(streak_w, 0.001);
	float streak = exp(-0.5 * t * t) * bw * max(exp(-2.0 * x * x), streak_trail * behind);
	float a = crest + trail * behind * (rim_gain * edge + trail_fill * acr * acr) + streak_gain * streak;
	a = strength * clamp(a, 0.0, 1.0) * mask;
	COLOR = vec4(wave_color.rgb * COLOR.rgb, wave_color.a * a * COLOR.a);
}
