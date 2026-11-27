shader_type canvas_item;
// Волна света по полю на победе (14.5, WinWave; docs/STYLE.md, раздел 12, «Победа»). Узел — ColorRect во всё поле
// (px поля). От origin (середина последнего блока) расходится кольцо света, радиус фронта — front, полоса — band
// (px); strength — сила (0 — нет). Цвет узла белый; modulate — в COLOR.
// Вид — по картинке-референсу (20.8: docs/shader_refs/win_wave.jpg, П11 в PROMPTS.md): свет живёт только в блоках,
// а не ровной белой дымкой поверх всего поля, — зазоры между блоками и рамка не светятся, блоки не бледнеют:
//   - форма — тела блоков (лицо + губа, как в block.gdshader: зазор gap, скругление radius, губа depth). Блок
//     ищется по клетке: cells[строка · grid.x + столбец] — прямоугольник блока этой клетки в клетках (x, y, w, h),
//     cell — клетка, px (ставит WinWave.play из Board.celebrate; на победе заняты все клетки). grid.x = 0 (клеток
//     не дали) — всё поле скруглённым прямоугольником radius, как раньше;
//   - гребень — тонкая дуга кольца: горячее белое ядро (Гаусс шириной core от band) и мягкое свечение вокруг
//     (шириной glow_w от band, сила glow_gain, у краёв блока чуть ярче);
//   - позади фронта — свет по кромке блоков (rim_gain × trail, гаснет вглубь за rim px) и лёгкая дымка trail_fill;
//   - по нижней кромке губы — тонкая яркая полоса блика (streak_*): ярче всего у гребня, позади него —
//     streak_trail. На нижних скруглениях сужается и тает (нормаль контура вниз), как в line_wave.gdshader.

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 rect_size = vec2(600.0, 600.0);
uniform float radius = 24.0;
uniform vec2 origin = vec2(300.0, 300.0);
uniform float front = 0.0;
uniform float band = 160.0;
uniform float trail = 0.3;
uniform float strength = 0.0;
uniform vec4 cells[81];
uniform vec2 grid = vec2(0.0, 0.0);
uniform float cell = 100.0;
uniform float gap = 4.5;
uniform float depth = 7.5;
uniform float core = 0.06;
uniform float glow_w = 0.38;
uniform float glow_gain = 0.8;
uniform float rim = 13.0;
uniform float rim_gain = 1.0;
uniform float trail_fill = 0.05;
uniform float streak_in = 3.0;
uniform float streak_w = 2.4;
uniform float streak_gain = 1.0;
uniform float streak_trail = 0.6;
uniform vec4 wave_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 p = UV * rect_size;
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	// Блок клетки под пикселем: расстояние до его тела (минус — внутри) и нормаль контура губы.
	vec2 cp = clamp(floor(p / max(cell, 1.0)), vec2(0.0), max(grid - vec2(1.0), vec2(0.0)));
	int idx = int(cp.y * grid.x + cp.x);
	vec4 q = cells[clamp(idx, 0, 80)];
	vec2 lo = q.xy * cell + vec2(gap);
	vec2 hi = (q.xy + q.zw) * cell - vec2(gap);
	float d = min(sd_box(p, lo, hi - vec2(0.0, depth), radius), sd_box(p, lo + vec2(0.0, depth), hi, radius));
	vec2 n = box_normal(p, lo + vec2(0.0, depth), hi, radius);
	float none = 1.0 - step(0.5, grid.x);
	d = mix(d, sd_box(p, vec2(0.0), rect_size, radius), none);
	n = mix(n, box_normal(p, vec2(0.0), rect_size, radius), none);
	float mask = fill(d, aa);

	// Путь от фронта в долях band: 0 — гребень, минус — позади (ближе к origin).
	float x = (length(p - origin) - front) / max(band, 1.0);
	float glow = exp(-8.0 * x * x / max(glow_w * glow_w, 0.0001));
	float hot = exp(-8.0 * x * x / max(core * core, 0.0001));
	float behind = 1.0 - smoothstep(-0.35, 0.0, x);
	float inside = max(-d, 0.0);
	float edge = exp(-inside / max(rim, 0.001));
	float crest = hot + glow * (glow_gain + 0.4 * edge);
	float bw = smoothstep(0.3, 0.97, n.y);
	float t = (inside - streak_in) / max(streak_w, 0.001);
	float streak = exp(-0.5 * t * t) * bw * max(exp(-2.0 * x * x), streak_trail * behind);
	float a = crest + trail * behind * (rim_gain * edge + trail_fill) + streak_gain * streak;
	a = strength * clamp(a, 0.0, 1.0) * mask;
	COLOR = vec4(wave_color.rgb * COLOR.rgb, wave_color.a * a * COLOR.a);
}
