// Общие функции шейдеров поля и блоков (docs/STYLE.md): скруглённые прямоугольники через SDF.
// Подключение: #include "res://shaders/sdf.gdshaderinc"

// Расстояние до скруглённого прямоугольника [lo, hi] со скруглением r (минус — внутри).
float sd_box(vec2 p, vec2 lo, vec2 hi, float r) {
	vec2 c = (lo + hi) * 0.5;
	vec2 b = max((hi - lo) * 0.5, vec2(0.0));
	float rr = min(r, min(b.x, b.y));
	vec2 q = abs(p - c) - b + vec2(rr);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - rr;
}

// Покрытие формы с мягким краем полушириной s. Для размытия Гаусса с сигмой σ берём s ≈ 1,9σ.
float fill(float d, float s) {
	return 1.0 - smoothstep(-s, s, d);
}

vec3 lighten(vec3 c, float t) {
	return mix(c, vec3(1.0), t);
}

vec3 darken(vec3 c, float t) {
	return mix(c, vec3(0.0), t);
}

// Наложить цвет rgb с силой a поверх dst (обычное смешивание, без премультипликации).
vec4 over(vec4 dst, vec3 rgb, float a) {
	float oa = a + dst.a * (1.0 - a);
	vec3 oc = (rgb * a + dst.rgb * dst.a * (1.0 - a)) / max(oa, 0.0001);
	return vec4(oc, oa);
}
