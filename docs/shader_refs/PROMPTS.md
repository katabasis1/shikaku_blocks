# Референсы шейдеров (этап 20.8)

Правило пользователя (27.11): визуальный шейдер — сначала картинка. Генератор изображений рисует, как эффект выглядит
в стиле игры; картинка с промптом ложится сюда, шейдер пишется по ней, кадр шейдера сравнивается с картинкой рядом:
`python3 tools/shader_ref_compare.py board` (области: board, blocks, yellow, tray, top, full; со своим референсом —
nest, shelf, background).

## Картинки

| Файл | Что | Вход генератора | Промпт |
|---|---|---|---|
| `game_scene.jpg` | экран уровня целиком: блоки, поле, гнёзда, лоток, фон | кадр шейдеров `tools/shader_preview.py` (720×1280) | П1 |
| `block_20_8_cmp.jpg` | сравнение: референс / шейдеры после переделки `block.gdshader` (27.11) | — | — |
| `board_20_8_cmp.jpg` | сравнение после переделки `board.gdshader` (27.11) | — | — |
| `block_highlights.jpg` | блики блока: тонкая белая линия по контуру верха, гаснет на боках; блик губы по нижнему контуру, тает на скруглениях | кадр блоков старым шейдером, 1500×1000 (`block_highlights_input.jpg`) | П2 |
| `block_highlights_cmp.jpg` | сравнение: референс / шейдер до / после правки бликов `block.gdshader` (27.11, ночь) | — | — |
| `nest.jpg`, `shelf.jpg`, `background.jpg` | гнёзда, полка, фон (27.11, до ночи) | вырезки кадра шейдеров | не записаны |
| `shelf_tray.jpg` | полка лотка: выпуклый ободок с бликом по верху, губа-толщина, тень под полкой, утопленные гнёзда со светлой кромкой по низу | вырезка кадра (0, 971)–(720, 1280) ×2, 1440×618 (`shelf_tray_input.jpg`) | П3 |
| `shelf_tray_cmp.jpg` | сравнение: референс / шейдер до / после переделки `shelf.gdshader` (27.11, ночь) | — | — |
| `background_p4.jpg` | **отклонено пользователем** (27.11): фон — 5 витков-складок атласа, каждая светлеет к гребню, по гребню — чёткая тонкая светлая линия, за ней тень; ложбины тёмно-фиолетовые; виньетка | кадр фона старым шейдером, 720×1280 (`background_p4_input.jpg`) | П4 |
| `background_p4_cmp.jpg` | **отклонено**: референс / шейдер до / после переделки `background.gdshader` (27.11, ночь; откачена) | — | — |

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

**П2** (3:2, генератор изображений Dust, 27.11, ночь; по жалобе пользователя: блики-овалы в углах «налеплены поверх»,
светлая полоса губы «резко обрывается» с обоих концов). Дословный текст не сохранился: Компьютер сбросился раньше, чем
промпт записали сюда. Суть (по картинке и описанию правки): перерисовать эти блоки той же раскладкой, цветами и
материалом «мармелад», но без отдельных овальных бликов — тонкая белая линия блика идёт внутри кромки по всему верху,
огибает верхние скругления и, спускаясь по бокам, сужается и гаснет; светлая полоса по нижней кромке губы следует
контуру и плавно тает на нижних скруглениях, без обрыва.

**П3** (21:9, генератор изображений Dust, 27.11, ночь): «Redraw this bottom tray of a mobile puzzle game (Shikaku
Blocks) keeping EXACTLY the same layout, proportions, shelf size and position, three slots, the orange block 3 and the
yellow block 4, the dashed outline of the empty left slot, the violet background and colors. Only render the tray
shelf more beautifully, like a premium polished casual mobile game: the shelf is a thick slab of dark translucent
violet glass-candy — a soft glossy light-lavender highlight line running along the inside of its top edge and fading
down the rounded sides, a visible rounded bottom thickness (a slightly darker violet lip under the face) and a soft
violet drop shadow under the shelf onto the background. The three slots are gently recessed into the shelf: slightly
darker than the shelf face, a soft inner shadow under their top edge, a thin soft light rim along their bottom edge,
corners rounded concentric to the shelf. All highlights follow the rounded shapes and fade smoothly, no stuck-on ovals
or abruptly cut lines. Clean, crisp, vector-like, soft studio lighting from the top, no extra objects, no extra text.»

**П4** (9:16, генератор изображений Dust, medium, 27.11, ночь; вход — кадр фона `tools/shader_preview.py` 720×1280,
`background_p4_input.jpg`; дословно): «Redraw this mobile puzzle game background (Shikaku Blocks) keeping EXACTLY the
same composition: the same swirl center position, three spiral arms winding in the same direction, the same color
gradient from blue-violet at the top to magenta-purple at the bottom. Only render it more beautifully, like a premium
polished casual mobile game: a smooth deep violet backdrop with soft silky satin ribbons of light spiralling around the
center - each ribbon has a crisp thin glowing light edge on one side that fades softly into the fold, with gently
darker deep-violet grooves between the ribbons giving depth; the ribbons stay clean and continuous, no blur, no mist,
no washed-out haze. Richer, more saturated colors, slightly darker toward the edges and corners (soft vignette), a calm
even area in the very center. Clean, crisp, vector-like, soft studio lighting from the top, no objects, no text, no
UI.» Генератор нарисовал не 3, а около 5 витков, закрученных туже, — так и взято в шейдер. Референс заметно темнее,
чем можно сделать в игре: средний цвет кадра держится у #7B53E0 (шторка перехода и экран загрузки, иначе вспышка
при смене экранов). **Отклонено пользователем 27.11 (04:30):** прежний фон нравится больше, шейдер по П4 откачен.

## Шейдеры: что сделано

Порядок — по заметности на экране. «Референс» — по какой картинке; «Сделано» — дата и что поменялось.

| # | Шейдер | Где | Референс | Сделано |
|---|---|---|---|---|
| 1 | `block.gdshader` | блоки (`Block`) | `game_scene.jpg`, блики — `block_highlights.jpg` | 27.11: насыщенная глубина (×1,3), светлый ободок у кромки, тёмная кромка снаружи, глубина у края, свет над губой, глянец, серп ярче, искры в верхних углах, блик по низу губы; униформы и эффекты (glow, crack, merge, flash, smear) — как были. 27.11, ночь (по жалобе): искры-овалы убраны — вместо них тонкая линия блика по контуру верха, гаснет на боках; блик губы идёт по её контуру и тает на скруглениях (вес — нормаль контура, функция `box_normal`), тон губы — от её края; нижний край серпа мягче. Ручки: сила линии `0.92`, длина на боках `0.42 * k`, толщина `0.009` |
| 2 | `board.gdshader` | рамка и клетки поля | `game_scene.jpg` | 27.11: бортик — сиреневая кромка снаружи, белый блик по верху, скос к лотку; клетки — подушки вместо ямок: мягкая тень под клеткой, светлый верх, белый скос сверху, сиреневый снизу, тонкая кромка. Цвета лотка — как в STYLE (их сверяет `layout_model.py`) |
| 3 | `nest.gdshader` | гнёзда чисел | `nest.jpg` | 27.11 (до ночи; строку дописали позже, по шапке шейдера): кант — глянцевая «трубка» цвета площади (сверху светлее, снизу гуще, блик по верху, искра в левом верхнем углу), внутри светлая подушка, чуть утопленная; мягкая тень на клетку |
| 4 | `shelf.gdshader` | полка лотка | `shelf_tray.jpg` | 27.11, ночь: лицо плотнее (альфа 0,7 / 0,66) и светлее; выпуклый ободок по кромке (светлее у края, сверху ярче) с тёмной бороздкой по внутреннему краю; линия блика по верху — огибает скругления, гаснет на боках; губа-толщина 9 px под лицом и тень под полкой — в полях `outer` (Tray рисует прямоугольник шире корпуса на `Tray.SHELF_OUTER` = 24 px); гнёзда — тень под верхним краем, светлая кромка по низу, тает на скруглениях. Цвета сверены с референсом по пробам (лицо, гнездо, губа — расхождение ≤ 6 по каналу; верх ободка чуть менее синий, до 14) |
| 5 | `background.gdshader` | фон | `background.jpg` | **Не менять — решение пользователя 27.11 (04:30): «шейдер фона оставляем таким, каким он был, мне он нравится больше».** Переделка по П4 (складки атласа: 5 витков, линия по гребню, тёмные ложбины) была сделана ночью 27.11 и откачена: шейдер, `background.gd`, `shader_ref_compare.py` и кадры `G13_7` / `G14_7` — снова прежние, STYLE 9 — прежний. `background_p4*.jpg` и П4 оставлены как запись отклонённого направления |
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
