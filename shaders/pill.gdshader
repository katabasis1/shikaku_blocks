shader_type canvas_item;
// Плашка-таблетка под подписью (docs/STYLE.md, раздел 3; «Осталось блоков»): тёмная полупрозрачная
// заливка, радиус = высота / 2, плашка «утоплена» в фон.
// Вид — по картинке-референсу (20.8: docs/shader_refs/pill_label.jpg, промпт П6 в PROMPTS.md): мягкая лунка-
// таблетка, как ячейки полки. Тени и блики идут по контуру (вес — нормаль box_normal) и тают на скруглениях:
// - внутренняя тень: у верхнего края глубокая (shade_depth px, мягко гаснет), по торцам узкая и слабее
//   (side_depth, side_strength), к низу торцов гаснет, у нижнего края её нет;
// - низ чуть светлее (отражённый свет);
// - по нижнему краю тонкая светлая кромка: ярче всего на нижних скруглениях, посередине низа слабее,
//   вверх по торцам гаснет к середине высоты.
// Рисует PillLabel (узел Pill за текстом); rect_size — размер узла в px.

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 rect_size = vec2(320.0, 52.0);
uniform vec4 fill_color : source_color = vec4(0.094, 0.031, 0.376, 0.275);   // (24, 8, 96), 70 / 255
uniform vec4 shade : source_color = vec4(0.063, 0.016, 0.275, 1.0);          // (16, 4, 70)
uniform float shade_strength = 0.45;    // внутренняя тень у верхнего края
uniform float shade_depth = 12.0;       // глубина тени сверху, px
uniform float side_strength = 0.5;      // тень на торцах — доля силы сверху
uniform float side_depth = 4.0;         // глубина тени на торцах, px
uniform vec4 rim_color : source_color = vec4(0.878, 0.831, 1.0, 1.0);        // #E0D4FF
uniform float rim_alpha = 0.85;         // кромка на нижних скруглениях
uniform float rim_bottom = 0.7;         // посередине низа — доля rim_alpha
uniform float rim_width = 0.7;          // полуширина кромки, px
uniform float floor_light = 0.08;       // низ светлее: белый у края -> 0 за floor_depth px
uniform float floor_depth = 6.0;

void fragment() {
	vec2 p = UV * rect_size;
	vec2 lo = vec2(0.5);
	vec2 hi = rect_size - vec2(0.5);
	float r = (hi.y - lo.y) * 0.5;
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	float d = sd_box(p, lo, hi, r);
	float body = fill(d, aa);
	float din = max(-d, 0.0);
	vec2 n = box_normal(p, lo, hi, r);
	// Внутренняя тень: вес верха wt (1 на верхней прямой -> 0 к середине торца), к низу торцов гаснет.
	float wt = smoothstep(0.0, 1.0, -n.y);
	float ws = 1.0 - smoothstep(0.0, 0.6, n.y);
	float depth = mix(side_depth, shade_depth, wt);
	float ramp = pow(clamp(1.0 - din / depth, 0.0, 1.0), 1.3);
	vec4 c = over(fill_color, shade.rgb, shade_strength * mix(side_strength, 1.0, wt) * ws * ramp);
	// Низ светлее.
	float wb = smoothstep(0.2, 0.9, n.y);
	c = over(c, vec3(1.0), floor_light * wb * (1.0 - smoothstep(0.0, floor_depth, din)));
	// Светлая кромка по низу: ярче на нижних скруглениях, вверх по торцам гаснет.
	float wr = smoothstep(0.2, 0.75, n.y) * mix(rim_bottom, 1.0, 1.0 - smoothstep(0.75, 1.0, n.y));
	float line = 1.0 - smoothstep(rim_width - aa, rim_width + aa, abs(din - 0.6));
	c = over(c, rim_color.rgb, rim_alpha * wr * line);
	COLOR = vec4(c.rgb, c.a * body * COLOR.a);
}
