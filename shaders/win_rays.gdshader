shader_type canvas_item;
// Фон победы за полем (docs/STYLE.md, раздел 11; стиль-кадр A3B_win; 13.5b): лучи от центра поля и мягкое
// розово-лавандовое свечение вокруг поля. Рисует WinBackdrop (узел Rays на весь экран, за полем и HUD); тот же
// шейдер — свечение и лучи за логотипом меню (MenuLogo, узел Halo) и в промо-картинках (tools/promo_art.py): там
// прежний вид (белые клинья по половине периода, свечение-эллипс) задан явно.
// Вид на победе — по картинке-референсу (20.8: docs/shader_refs/win_rays.jpg, промпт П7 в PROMPTS.md):
//   Лучи: rays мягких клиньев цвета ray_color с силой ray_alpha. Поперёк луча: ядро — ray_core периода от оси,
//   дальше за ray_soft периода плавно гаснет (без резкого края), между лучами — фон. Каждый второй луч слабее
//   (×ray_alt; rays чётное, иначе на −x шов). Вдоль луча — сплошные до 0,15·radius и линейно гаснут к radius.
//   Поворачиваются на spin рад/с (STYLE 12, «Фон»: цикл от 20 с, линейно; 0 — стоят).
//   Свечение: по форме поля — скруглённый прямоугольник с полуосями glow_radius и скруглением glow_corner
//   (glow_corner < 0 — эллипс, как раньше), край размыт на glow_blur (σ, ±2σ), цвет и сила — glow_color.
//   Свечение поверх лучей: у самого поля лучи тонут в нём, дальше видны.
// COLOR.a — прозрачность целиком (modulate узла: проявление).

#include "res://shaders/sdf.gdshaderinc"

uniform vec2 rect_size = vec2(720.0, 1280.0);
uniform vec2 center = vec2(360.0, 405.0);
uniform float rays = 20.0;
uniform float radius = 600.0;
uniform float ray_alpha = 0.9;
uniform vec4 ray_color : source_color = vec4(1.0, 0.843, 1.0, 1.0);     // (255, 215, 255)
uniform float ray_core = 0.06;                                         // доля периода; 0,25 и ray_soft 0 — клин
uniform float ray_soft = 0.26;                                         // по половине периода, резкий край
uniform float ray_alt = 0.6;                                           // каждый второй луч ×ray_alt (1 — все равны)
uniform float turn = 0.1047;                                           // начальный поворот, рад (6°)
uniform float spin = 0.1047;                                           // рад/с (оборот за 60 с)
uniform vec2 glow_radius = vec2(332.0, 338.0);                         // рамка поля + 70 px (WinBackdrop)
uniform float glow_corner = 250.0;
uniform float glow_blur = 28.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.78, 1.0, 0.92);   // (255, 199, 255), 92 %

void fragment() {
	vec2 p = UV * rect_size;
	vec2 d = p - center;
	float r = length(d);

	// Лучи: k — угол в периодах лучей, луч n — с осью на k = n + 0,25; u — расстояние до оси (0…0,5 периода).
	float k = (atan(d.y, d.x) - turn - TIME * spin) * rays / TAU + 0.25;
	float u = abs(fract(k) - 0.5);
	float weight = mix(1.0, ray_alt, mod(floor(k), 2.0));
	// Сглаживание — не уже 1,5 px на этом радиусе (без fwidth: у atan разрыв на −x).
	float w = 1.5 * rays / (TAU * max(r, 1.0));
	float in_ray = 1.0 - smoothstep(ray_core - w, ray_core + ray_soft + w, u);
	float fade = clamp((radius - r) / (0.85 * radius), 0.0, 1.0);
	float a_ray = ray_alpha * weight * in_ray * fade;

	// Свечение: расстояние до скруглённого прямоугольника (или до эллипса, приближённо), размытый край ±2σ.
	float gd = glow_corner < 0.0
			? (length(d / glow_radius) - 1.0) * min(glow_radius.x, glow_radius.y)
			: sd_box(p, center - glow_radius, center + glow_radius, glow_corner);
	float a_glow = glow_color.a * (1.0 - smoothstep(-2.0 * glow_blur, 2.0 * glow_blur, gd));

	// Свечение поверх лучей, как в кадре.
	float a = a_glow + a_ray * (1.0 - a_glow);
	vec3 rgb = (glow_color.rgb * a_glow + ray_color.rgb * a_ray * (1.0 - a_glow)) / max(a, 0.0001);
	COLOR = vec4(rgb, a * COLOR.a);
}
