shader_type canvas_item;
// Фон победы за полем (docs/STYLE.md, раздел 11; стиль-кадр A3B_win; 13.5b): лучи от центра поля и мягкое
// розоватое свечение. Рисует WinBackdrop (узел Rays на весь экран, за полем и HUD).
//   Лучи: rays клиньев по половине периода, белые с силой ray_alpha, сплошные до 0,15·radius и линейно
//   гаснут к radius; поворачиваются на spin рад/с (STYLE 12, «Фон»: цикл от 20 с, линейно; 0 — стоят).
//   Свечение: эллипс с полуосями glow_radius, размытый на glow_blur (σ), цвет и сила — glow_color.
// COLOR.a — прозрачность целиком (modulate узла: проявление).

uniform vec2 rect_size = vec2(720.0, 1280.0);
uniform vec2 center = vec2(360.0, 405.0);
uniform float rays = 20.0;
uniform float radius = 760.0;
uniform float ray_alpha = 0.09;
uniform float turn = 0.1047;                                       // начальный поворот, рад (6°)
uniform float spin = 0.1047;                                       // рад/с (оборот за 60 с)
uniform vec2 glow_radius = vec2(330.0, 335.0);
uniform float glow_blur = 70.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.882, 1.0, 0.4); // (255, 225, 255), 40 %

void fragment() {
	vec2 p = UV * rect_size;
	vec2 d = p - center;
	float r = length(d);

	// Лучи: k — угол в периодах лучей, u — расстояние до оси ближайшего луча (−0,5…0,5 периода).
	float k = (atan(d.y, d.x) - turn - TIME * spin) * rays / TAU;
	float u = abs(fract(k + 0.25) - 0.5);
	// Полуширина сглаживания — 1,5 px на этом радиусе (без fwidth: у atan разрыв на −x).
	float w = 1.5 * rays / (TAU * max(r, 1.0));
	float in_ray = 1.0 - smoothstep(0.25 - w, 0.25 + w, u);
	float fade = clamp((radius - r) / (0.85 * radius), 0.0, 1.0);
	float a_ray = ray_alpha * in_ray * fade;

	// Свечение: расстояние до эллипса (приближённо), размытый край ±2σ.
	float gd = (length(d / glow_radius) - 1.0) * min(glow_radius.x, glow_radius.y);
	float a_glow = glow_color.a * (1.0 - smoothstep(-2.0 * glow_blur, 2.0 * glow_blur, gd));

	// Свечение поверх лучей, как в кадре.
	float a = a_glow + a_ray * (1.0 - a_glow);
	vec3 rgb = (glow_color.rgb * a_glow + vec3(1.0) * a_ray * (1.0 - a_glow)) / max(a, 0.0001);
	COLOR = vec4(rgb, a * COLOR.a);
}
