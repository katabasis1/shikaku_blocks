# Референсы шейдеров (этап 20.8)

Правило пользователя (27.11): визуальный шейдер — сначала картинка. Генератор изображений рисует, как эффект выглядит
в стиле игры; картинка с промптом ложится сюда, шейдер пишется по ней, кадр шейдера сравнивается с картинкой рядом:
`python3 tools/shader_ref_compare.py board` (области: board, blocks, yellow, tray, top, full).

## Картинки

| Файл | Что | Вход генератора | Промпт |
|---|---|---|---|
| `game_scene.jpg` | экран уровня целиком: блоки, поле, гнёзда, лоток, фон | кадр шейдеров `tools/shader_preview.py` (720×1280) | П1 |
| `block_20_8_cmp.jpg` | сравнение: референс / шейдеры после переделки `block.gdshader` (27.11) | — | — |
| `board_20_8_cmp.jpg` | сравнение после переделки `board.gdshader` (27.11) | — | — |

**П1** (9:16, генератор изображений Dust, 27.11): «Redraw this mobile puzzle game screen (Shikaku Blocks) keeping
EXACTLY the same layout, composition, colors, block positions, digits and UI elements, but render the materials more
beautifully, like a premium polished casual mobile game. Blocks: translucent glossy candy-jelly (marmalade) material
with depth — soft subsurface glow inside, a crisp curved white specular highlight along the top edge, a soft secondary
reflection at the bottom, a darker rounded lip underneath that shows thickness, gently rounded corners, very subtle
cell seams. Board: thick glossy white rounded frame with a soft lavender inner tray, empty cells slightly recessed with
soft inner shadows. Number nests: small rounded squares with a colored rim and soft light fill. Bottom tray: a dark
translucent violet shelf with three rounded recessed slots, soft inner shadows. Background: smooth deep violet-to-purple
gradient with soft silky swirling light ribbons. Clean, crisp, vector-like, soft studio lighting from the top, no extra
objects, no extra text.»

## Шейдеры: что сделано

Порядок — по заметности на экране. «Референс» — по какой картинке; «Сделано» — дата и что поменялось.

| # | Шейдер | Где | Референс | Сделано |
|---|---|---|---|---|
| 1 | `block.gdshader` | блоки (`Block`) | `game_scene.jpg` | 27.11: насыщенная глубина (×1,3), светлый ободок у кромки, тёмная кромка снаружи, глубина у края, свет над губой, глянец, серп ярче, искры в верхних углах, блик по низу губы; униформы и эффекты (glow, crack, merge, flash, smear) — как были |
| 2 | `board.gdshader` | рамка и клетки поля | `game_scene.jpg` | 27.11: бортик — сиреневая кромка снаружи, белый блик по верху, скос к лотку; клетки — подушки вместо ямок: мягкая тень под клеткой, светлый верх, белый скос сверху, сиреневый снизу, тонкая кромка. Цвета лотка — как в STYLE (их сверяет `layout_model.py`) |
| 3 | `nest.gdshader` | гнёзда чисел | `game_scene.jpg` | — |
| 4 | `shelf.gdshader` | полка лотка | `game_scene.jpg` | — (кадр уже близок к референсу) |
| 5 | `background.gdshader` | фон | `game_scene.jpg` | — |
| 6 | `card.gdshader` | карточки окон | нужен свой (окно победы, пауза) | — |
| 7 | `pill.gdshader` | подписи-таблетки | нужен свой | — |
| 8 | `win_rays.gdshader` | лучи победы | нужен свой | — |
| 9 | `ghost.gdshader` | место несомого блока | нужен свой | — |
| 10 | `check.gdshader` | галочка | нужен свой | — |
| 11 | `line_wave.gdshader` | волна света по ряду | нужен свой | — |
| 12 | `win_wave.gdshader` | волна света победы | нужен свой | — |
| 13 | `transition.gdshader` | шторка | нужен свой | — |
| 14 | `soft_shadow.gdshader` | мягкие тени | служебный — менять, только если референс покажет другую тень | — |
| 15 | `tex_shadow.gdshader` | тени картинок | служебный | — |

Godot в Компьютере нет: шейдер проверяется переводчиком `tools/shader_preview.py` (тот же код на numpy). Ошибки
типов Godot (int вместо float и т. п.) он не ловит — писать `1.0`, а не `1`; прогон в Godot — у пользователя (20.7).
