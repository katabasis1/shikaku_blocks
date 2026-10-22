shader_type canvas_item;
// Мягкая тень по форме картинки (docs/STYLE.md, раздел 7; звёзды): альфа текстуры src, размытая
// Гауссом с сигмой blur, сдвинутая на offset, одного цвета shade. Рисует TexShadow (ColorRect за
// родителем-TextureRect, show_behind_parent): узел больше родителя на поля под размытие и смещение,
// картинка занимает в нём tex_lo … tex_lo + tex_size (px узла).
// Размытие — сетка 7×7 отсчётов с шагом 0,75σ по mip-уровню, близкому к экранному размеру картинки. На низком
// качестве (14.7, TexShadow) — 3×3 с шагом 1,25σ (reach 1, step_k 1,25) по mip-уровню на log2(σ) − 0,5 выше
// (lod_bias): мелкий mip сам размывает между отсчётами. Модель (14.7c): отклонение от 7×7 вдвое меньше, чем у
// 3×3 с шагом σ без сдвига mip, — тень та же, чуть мягче по краю лучей.

uniform sampler2D src : filter_linear_mipmap, repeat_disable;
uniform vec2 rect_size = vec2(66.0, 66.0);
uniform vec2 tex_lo = vec2(13.0, 13.0);
uniform vec2 tex_size = vec2(42.0, 42.0);
uniform vec2 offset = vec2(0.0, 3.2);                   // px
uniform float blur = 4.1;                               // σ, px
uniform vec4 shade : source_color = vec4(0.353, 0.165, 0.0, 1.0);   // #5A2A00
uniform float strength = 0.35;
uniform int reach = 3;                                  // отсчётов в каждую сторону
uniform float step_k = 0.75;                            // шаг, доля σ
uniform float lod_bias = 0.0;                           // добавка к mip-уровню

float alpha_at(vec2 p, float lod) {
	vec2 uv = p / tex_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return textureLod(src, uv, lod).a;
}

void fragment() {
	vec2 p = UV * rect_size - tex_lo - offset;
	vec2 ts = vec2(textureSize(src, 0));
	float lod = log2(max(ts.x / max(tex_size.x, 1.0), 1.0)) + lod_bias;
	float step_px = max(blur, 0.001) * step_k;
	float wk = step_k * step_k * 0.5;
	float a = 0.0;
	float wsum = 0.0;
	for (int j = -reach; j <= reach; j++) {
		for (int i = -reach; i <= reach; i++) {
			vec2 k = vec2(float(i), float(j));
			float w = exp(-dot(k, k) * wk);                // exp(−(step_k·k)² / 2)
			a += alpha_at(p + k * step_px, lod) * w;
			wsum += w;
		}
	}
	COLOR = vec4(shade.rgb, strength * a / wsum * COLOR.a);
}
