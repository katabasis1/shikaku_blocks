shader_type canvas_item;
// Фон меню и игры «шёлковый вихрь» (10.10, docs/STYLE.md, раздел 9): широкие мягкие витки и тонкие светлые
// прожилки, как у шёлковой ленты или сливок, закрученных в сиропе, вращаются вокруг точки за полем.
// Свой код, не фон Balatro: нет «краски» из итераций искажения (пятна, тёмные червячки, мраморные разводы) —
// здесь гладкие логарифмические спирали: светлые прожилки вместо тёмных, чёткие витки вместо пятен, крупный
// масштаб. Интерфейс тот же, что был у фигур: Background (scenes/ui/background.gd) ставит rect_size, light,
// speed и цвета темы главы (градиент, виньетка, deep / cool / warm); Bake на среднем и низком качестве —
// use_baked / baked. Экран загрузки веб-сборки (web/shell.html) — только градиент, свет и виньетка в CSS.
//
// Слои: градиент фона -> витки (светлая полоса с тоном: вверху холоднее, внизу теплее; между ними — чуть темнее)
// -> светлые прожилки у края витка (то ярче, то бледнее вдоль него) -> тонкие прожилки второго ряда -> пятно света
// -> виньетка -> дизеринг ±0,5/255. Все размеры — в виртуальных пикселях (в альбоме витки того же размера).
// Движение: «часовой» темп × speed. При speed 1 вихрь поворачивается на spin_turns оборотов за 3600 с (оборот за
// 20 мин), витки смещаются в среднем на 1 px/с — глазом не видно (так было 08.10). Игра ставит speed 8
// (Background.SPEED, 10.10: «движется неразличимо глазу, надо ускорить»): оборот за 2,5 мин, витки — в среднем
// ≈ 9 px/с, у 99 % экрана — до 30–40 (tools/window_preview.py --background); при «Меньше движения» — speed 1.
// Искажение «течёт», яркость прожилок бежит вдоль витков.
// Все частоты — целое число оборотов за 3600 с, speed — целое, а TIME в Godot сбрасывается каждые 3600 с,
// поэтому скачка нет: кадры при 3600 и 0 с совпадают.

uniform vec2 rect_size = vec2(720.0, 1280.0);
uniform vec4 top_color : source_color = vec4(0.290196, 0.211765, 0.878431, 1.0);    // #4A36E0
uniform vec4 mid_color : source_color = vec4(0.415686, 0.258824, 0.894118, 1.0);    // #6A42E4
uniform vec4 bottom_color : source_color = vec4(0.603922, 0.298039, 0.858824, 1.0); // #9A4CDB
uniform float light = 0.188235;                 // 48/255; на победе 70/255 (Background.set_win)
uniform vec2 light_center = vec2(0.5, 0.2);
uniform float light_radius = 0.75;              // доля длинной стороны
uniform vec4 vignette_color : source_color = vec4(0.078431, 0.023529, 0.274510, 0.470588); // #14064A, 120/255
uniform vec2 vignette_center = vec2(0.5, 0.45);
uniform float vignette_radius = 0.62;           // доля диагонали
uniform float vignette_start = 0.6;
uniform bool use_baked = false;                 // Bake (14.7): узел только растягивает готовую картинку
uniform sampler2D baked : filter_linear, repeat_disable;
// Вихрь. Цвета deep / cool / warm — тема главы (Chapters.THEMES; здесь — глава 1).
uniform vec4 deep_color : source_color = vec4(0.203922, 0.086275, 0.560784, 1.0);   // SHADE #34168F — между витками
uniform vec4 cool_color : source_color = vec4(0.501961, 0.549020, 1.0, 1.0);        // #808CFF — тон витка вверху
uniform vec4 warm_color : source_color = vec4(0.854902, 0.360784, 0.941176, 1.0);   // #DA5CF0 — тон витка внизу
uniform vec2 swirl_center = vec2(0.5, 0.45);    // доля экрана: за полем и логотипом
uniform float arms = 3.0;                       // витков (целое)
uniform float wind = 1.3;                       // закрутка: оборотов на e-кратный рост (1 + r / core)
uniform float core = 120.0;                     // px: ядро — внутри витки не сгущаются в точку
uniform float tint = 0.30;                      // тон витка
uniform float groove = 0.22;                    // темнее между витками
uniform float streak = 0.38;                    // светлая прожилка у края витка
uniform float streak_sharp = 10.0;              // тоньше / толще
uniform float fine = 0.18;                      // тонкие прожилки второго ряда
uniform float fine_arms = 7.0;                  // (целое)
uniform float fine_wind = 2.3;
uniform float warp = 90.0;                      // px: «течение» — плавное искажение витков
uniform float spin_turns = 3.0;                 // оборотов вихря за 3600 с при speed 1 (целое)
uniform float speed = 8.0;                      // темп (целое; Background.SPEED, при «Меньше движения» — 1)

void fragment() {
	if (use_baked) {
		COLOR = vec4(texture(baked, UV).rgb, 1.0);
	} else {
		vec2 pos = UV * rect_size;
		float gy = clamp(UV.y, 0.0, 1.0);
		vec3 col = mix(mix(top_color.rgb, mid_color.rgb, clamp(gy * 2.0, 0.0, 1.0)), bottom_color.rgb,
				clamp(gy * 2.0 - 1.0, 0.0, 1.0));
		// Течение: искажение двумя волнами по каждой оси, целое число оборотов за 3600 с.
		// fract: фаза в оборотах 0..1 — синусы не теряют точность float32 при speed × частота до 112.
		float ph = TAU * fract(mod(TIME, 3600.0) * speed / 3600.0);
		vec2 d = pos - swirl_center * rect_size;
		d += warp * vec2(sin(d.y / 230.0 + ph * 4.0) + 0.5 * sin(d.x / 130.0 - ph * 7.0),
				cos(d.x / 210.0 - ph * 5.0) + 0.5 * cos(d.y / 150.0 + ph * 6.0));
		float r = max(length(d), 0.001);
		float th = atan(d.y, d.x);
		float lr = log(1.0 + r / core);
		// Витки: фаза логарифмической спирали; arms и fine_arms целые — на разрыве atan шва нет.
		float phi = arms * (th + ph * spin_turns) - wind * TAU * lr;
		float band = smoothstep(0.2, 0.8, 0.5 + 0.5 * cos(phi));
		float edge = pow(max(0.5 + 0.5 * cos(phi - 1.9), 0.0), streak_sharp);   // max: pow от «-0» на GPU — NaN
		float along = 0.5 + 0.5 * sin(3.0 * th + r / 110.0 + ph * 12.0);
		float phi2 = fine_arms * (th + ph * spin_turns) - fine_wind * TAU * lr + 1.3 * sin(phi);
		float thin = pow(max(0.5 + 0.5 * cos(phi2), 0.0), 16.0) * (0.5 + 0.5 * sin(5.0 * th - r / 90.0 - ph * 14.0));
		float fade = smoothstep(30.0, 180.0, r);   // в самом центре (за полем) — ровный фон
		vec3 tone = mix(cool_color.rgb, warm_color.rgb, gy);
		col = mix(col, tone, tint * band * fade);
		col = mix(col, deep_color.rgb, groove * (1.0 - band) * fade);
		col = mix(col, vec3(1.0), streak * edge * along * fade);
		col = mix(col, vec3(1.0), fine * thin * fade);
		// Пятно света и виньетка (STYLE 9).
		float ld = length(pos - light_center * rect_size) / (light_radius * max(rect_size.x, rect_size.y));
		col = mix(col, vec3(1.0), light * (1.0 - clamp(ld, 0.0, 1.0)));
		float vr = length(pos - vignette_center * rect_size) / (vignette_radius * length(rect_size));
		float va = clamp((vr - vignette_start) / (1.0 - vignette_start), 0.0, 1.0);
		col = mix(col, vignette_color.rgb, vignette_color.a * va);
		// Дизеринг: плавные переходы без полос на 8 битах (хэш Hoskins, без sin).
		vec3 p3 = fract(vec3(pos.xyx) * 0.1031);
		p3 += dot(p3, p3.yzx + 33.33);
		col += (fract((p3.x + p3.y) * p3.z) - 0.5) / 255.0;
		COLOR = vec4(col, 1.0);
	}
}
