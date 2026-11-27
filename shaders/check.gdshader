shader_type canvas_item;
// Галочка «число закрыто» (14.3, Block.close_number; docs/STYLE.md, раздел 12). В шрифте Nunito галочки нет,
// поэтому она — две «капсулы» pt_a → pt_b → pt_c. Узел — ColorRect на месте цифры (клетка 100 × 100 px блока),
// цвет узла белый; modulate (прозрачность, вспышка) — в COLOR.
// Вид — по картинке-референсу (20.8: docs/shader_refs/check.jpg, промпт П9 в PROMPTS.md): толстая глянцевая
// белая «конфета» с обводкой и мягкой тенью цвета площади (Palette.block_digit_*, как у цифры блока):
//   - линия толще и галочка крупнее, чем была (stroke 15,5 вместо 10; точки — по референсу);
//   - белая заливка; к нижней кромке — лавандовая тень shade_color с примесью цвета блока (tint_color, доля
//     shade_tint). Вес — сдвиг пикселя вниз от оси линии в долях полутолщины (shade_from → shade_to): верх
//     линии белый, тень огибает концы и сильнее всего у низа «V», без обрыва;
//   - обводка outline (полная ширина, как Label.outline_size у цифры);
//   - тень мягкая: сдвиг shadow_offset, Гаусс σ shadow_blur от края обводки, сила shadow_color.a × shadow_gain.
// Всё помещается в узел 100 × 100: верх обводки — y ≈ 21, низ тени — y ≈ 87, правый край — x ≈ 90.

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 rect_size = vec2(100.0, 100.0);
// Точки галочки, px узла (имена не a/b/c: язык шейдеров Godot не даёт локальным именам sd_box и over
// перекрывать униформы).
uniform vec2 pt_a = vec2(29.5, 50.0);
uniform vec2 pt_b = vec2(42.0, 64.0);
uniform vec2 pt_c = vec2(69.5, 33.0);
uniform float stroke = 15.5;        // толщина белой линии, px блока (было 10)
uniform float outline = 9.0;        // обводка — полная ширина (по половине на сторону), как Label.outline_size
uniform vec2 shadow_offset = vec2(4.0, 6.5);
uniform float shadow_blur = 2.0;    // σ Гаусса тени от края обводки, px
uniform float shadow_gain = 0.85;   // сила тени — shadow_color.a × shadow_gain
uniform float shade_from = 0.0;     // тень заливки: от оси линии (0) …
uniform float shade_to = 0.7;       // … до 0,7 полутолщины вниз — полная
uniform float shade_alpha = 1.0;
uniform float shade_tint = 0.27;    // доля цвета блока в тени заливки
uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shade_color : source_color = vec4(0.55, 0.48, 0.86, 1.0);   // #8C7ADB
uniform vec4 tint_color : source_color = vec4(0.18, 0.784, 0.969, 1.0);  // цвет площади (Palette.color_for)
uniform vec4 outline_color : source_color = vec4(0.55, 0.16, 0.13, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.4, 0.12, 0.1, 0.47);

// Вектор от ближайшей точки отрезка [a, b] к p (длина — расстояние до отрезка).
vec2 seg_vec(vec2 p, vec2 a0, vec2 b0) {
	vec2 pa = p - a0;
	vec2 ba = b0 - a0;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
	return pa - ba * h;
}

void fragment() {
	vec2 p = UV * rect_size;
	float aa = max(fwidth(p.x), 0.0001) * 0.7;
	vec2 v1 = seg_vec(p, pt_a, pt_b);
	vec2 v2 = seg_vec(p, pt_b, pt_c);
	float d1 = length(v1);
	float d2 = length(v2);
	vec2 v = mix(v1, v2, step(d2, d1));
	float d = min(d1, d2);
	float hw = stroke * 0.5;
	float ho = hw + outline * 0.5;

	// Мягкая тень: Гаусс от края обводки, сдвинутой на shadow_offset.
	vec2 q = p - shadow_offset;
	float ds = min(length(seg_vec(q, pt_a, pt_b)), length(seg_vec(q, pt_b, pt_c))) - ho;
	float sd = max(ds, 0.0) / max(shadow_blur, 0.0001);
	float a_sh = min(shadow_color.a * shadow_gain, 1.0) * exp(-0.5 * sd * sd);
	vec4 col = vec4(shadow_color.rgb, a_sh);
	col = over(col, outline_color.rgb, outline_color.a * fill(d - ho, aa));

	// Заливка: белая сверху, к нижней кромке — лавандовая тень с примесью цвета блока.
	float w = smoothstep(shade_from, shade_to, v.y / max(hw, 0.0001));
	vec3 sc = mix(shade_color.rgb, tint_color.rgb, shade_tint);
	vec3 fc = mix(fill_color.rgb, sc, w * shade_alpha);
	col = over(col, fc, fill_color.a * fill(d - hw, aa));
	COLOR = vec4(col.rgb * COLOR.rgb, col.a * COLOR.a);
}
