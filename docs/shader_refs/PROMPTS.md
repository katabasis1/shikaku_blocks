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
| `card_windows.jpg` | карточки окон: победа (оранжевая шапка) и пауза (фиолетовая) — толстая карточка-«леденец»: линия блика по контуру шапки, глянец, тень шапки на лицо, ободок по бокам лица, губа темнее у лица со светлой кромкой по низу, мягкая тень | кадры окна победы и паузы старым шейдером рядом, 1480×1280 (`card_windows_input.jpg`) | П5 |
| `card_windows_cmp.jpg` | сравнение: референс / до (`main`) / после переделки `card.gdshader` (27.11, утро) | — | — |
| `pill_label.jpg` | плашка «Осталось блоков» на экране игры — мягкая лунка-таблетка: глубокая внутренняя тень сверху, узкая по торцам, светлая кромка по низу (ярче на нижних скруглениях) | низ экрана игры (поле, кнопки, плашка, полка) старым шейдером, 720×580 (`pill_label_input.jpg`) | П6 |
| `pill_label_cmp.jpg` | сравнение: референс / до (`main`) / после переделки `pill.gdshader` (27.11, утро); снизу — плашка крупно | — | — |

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

**П5** (5:4, генератор изображений Dust, 27.11, утро; вход — кадры окна победы и паузы старым шейдером рядом,
1480×1280, `card_windows_input.jpg`; дословно): «Redraw these two popup window cards of a mobile puzzle game (Shikaku
Blocks) - left: the level-complete card with an orange header, right: the pause card with a violet header - keeping
EXACTLY the same layout, proportions, card sizes and positions, corner radius, header height, all text, digits, stars,
icons, buttons and the background. Only render the card material more beautifully, like a premium polished casual
mobile game: each card is a thick soft candy slab. The white face has a very subtle lavender gradient toward the
bottom, a soft light inner rim along its edge and gentle soft inner shading near the sides and bottom, so it does not
look flat. The header is a glossy candy band in the same colors: a crisp thin white highlight line running just inside
its top edge that follows the rounded top corners and fades out down the sides, a soft gloss on its upper half, and a
slightly darker rounded underside where it meets the white face, casting a soft short shadow onto the face instead of
a hard flat stripe. Under each card a visible rounded lavender lip (thickness) with a thin soft light rim along its
bottom edge that fades smoothly on the rounded corners, and a soft violet drop shadow under the card. All highlights
follow the rounded shapes and fade smoothly, no stuck-on ovals or abruptly cut lines. Clean, crisp, vector-like, soft
studio lighting from the top, no extra objects, no extra text.» Раскладку, тексты и кнопки генератор сохранил,
места чуть сдвинул (карточка паузы выше ростом) — из референса взят только материал карточки.

**П6** (5:4, генератор изображений Dust, 27.11, утро; вход — низ экрана игры старым шейдером, 720×580,
`pill_label_input.jpg`; дословно): «Redraw this screenshot of a mobile puzzle game (Shikaku Blocks) keeping EXACTLY
the same layout, proportions, positions and sizes of everything: the board, all blocks and numbers, the round undo and
hint buttons, the tray below with its slots and blocks, the violet background, and the text "Осталось блоков: 2" (same
white font, same size and position). Change only the small dark translucent pill-shaped label plate behind the text
"Осталось блоков: 2" in the middle: render it more beautifully, like a premium polished casual mobile game, as a soft
pill-shaped recess pressed into the violet background, matching the material of the tray below: a translucent deep
violet glassy fill, slightly darker near the top, a soft inner shadow under its top edge that follows the rounded ends,
a thin soft light rim along its bottom edge that fades smoothly on the rounded ends, and a very faint lighter outline.
Subtle and calm: it must stay secondary to the buttons and must not look like a button. All highlights follow the
rounded shape and fade smoothly, no stuck-on ovals or abruptly cut lines. Clean, crisp, vector-like, soft studio
lighting from the top, no extra objects, no extra text.» Всё, кроме плашки, генератор сохранил; заливка посередине
плашки — та же, что была (совпала до единиц), светлого контура сверху он не нарисовал.

## Шейдеры: что сделано

Порядок — по заметности на экране. «Референс» — по какой картинке; «Сделано» — дата и что поменялось.

| # | Шейдер | Где | Референс | Сделано |
|---|---|---|---|---|
| 1 | `block.gdshader` | блоки (`Block`) | `game_scene.jpg`, блики — `block_highlights.jpg` | 27.11: насыщенная глубина (×1,3), светлый ободок у кромки, тёмная кромка снаружи, глубина у края, свет над губой, глянец, серп ярче, искры в верхних углах, блик по низу губы; униформы и эффекты (glow, crack, merge, flash, smear) — как были. 27.11, ночь (по жалобе): искры-овалы убраны — вместо них тонкая линия блика по контуру верха, гаснет на боках; блик губы идёт по её контуру и тает на скруглениях (вес — нормаль контура, функция `box_normal`), тон губы — от её края; нижний край серпа мягче. Ручки: сила линии `0.92`, длина на боках `0.42 * k`, толщина `0.009` |
| 2 | `board.gdshader` | рамка и клетки поля | `game_scene.jpg` | 27.11: бортик — сиреневая кромка снаружи, белый блик по верху, скос к лотку; клетки — подушки вместо ямок: мягкая тень под клеткой, светлый верх, белый скос сверху, сиреневый снизу, тонкая кромка. Цвета лотка — как в STYLE (их сверяет `layout_model.py`) |
| 3 | `nest.gdshader` | гнёзда чисел | `nest.jpg` | 27.11 (до ночи; строку дописали позже, по шапке шейдера): кант — глянцевая «трубка» цвета площади (сверху светлее, снизу гуще, блик по верху, искра в левом верхнем углу), внутри светлая подушка, чуть утопленная; мягкая тень на клетку |
| 4 | `shelf.gdshader` | полка лотка | `shelf_tray.jpg` | 27.11, ночь: лицо плотнее (альфа 0,7 / 0,66) и светлее; выпуклый ободок по кромке (светлее у края, сверху ярче) с тёмной бороздкой по внутреннему краю; линия блика по верху — огибает скругления, гаснет на боках; губа-толщина 9 px под лицом и тень под полкой — в полях `outer` (Tray рисует прямоугольник шире корпуса на `Tray.SHELF_OUTER` = 24 px); гнёзда — тень под верхним краем, светлая кромка по низу, тает на скруглениях. Цвета сверены с референсом по пробам (лицо, гнездо, губа — расхождение ≤ 6 по каналу; верх ободка чуть менее синий, до 14) |
| 5 | `background.gdshader` | фон | `background.jpg` | **Не менять — решение пользователя 27.11 (04:30): «шейдер фона оставляем таким, каким он был, мне он нравится больше».** Переделка по П4 (складки атласа: 5 витков, линия по гребню, тёмные ложбины) была сделана ночью 27.11 и откачена: шейдер, `background.gd`, `shader_ref_compare.py` и кадры `G13_7` / `G14_7` — снова прежние, STYLE 9 — прежний. `background_p4*.jpg` и П4 оставлены как запись отклонённого направления |
| 6 | `card.gdshader` | карточки окон (`CandyCard`) | `card_windows.jpg` | 27.11, утро: толстая карточка-«леденец», все блики и тени — по контуру (вес — нормаль `box_normal`), тают на скруглениях. Шапка: вместо блика-серпа — линия блика по контуру верха (14 px от края, полуширина 6 px), огибает верхние скругления и гаснет на боках, слева ярче; глянец верхней половины сильнее (0,42), светлая кромка по краю, низ темнее к разделителю, короткая мягкая тень шапки на лицо (вместо плоской полосы). Лицо: по бокам выпуклый ободок 7 px (лавандовый у края, светлая линия по гребню, мягкая бороздка), на нижних скруглениях сужается в узкое скругление низа в губу; низ лица `#ECE6FF` (был `#F2ECFF`). Губа: у лица `#9A80F2`, к низу светлеет до `#C4B0FF`, по низу светлая кромка, тает на скруглениях. Без шапки ободок идёт и по верху. Сверено в предпросмотре на победе и паузе (яркость по вертикали и горизонтали: тень шапки и ободок — в пределах нескольких единиц из 255; линия блика — на глаз); пересобраны `G13_5_win`, `G13_5_panels`, `G18_3_leaders`, `G19_3_lab`, `G20_1b_hearts`. Униформы, которые ставит `CandyCard`, — прежние |
| 7 | `pill.gdshader` | плашка «Осталось блоков» (`PillLabel`) | `pill_label.jpg` | 27.11, утро: мягкая лунка-таблетка, тени и блики по контуру (вес — `box_normal`). Внутренняя тень у верхнего края глубже (45 %, гаснет за 12 px вместо 2 px), по торцам вдвое слабее и узкая (4 px), к низу торцов гаснет; низ чуть светлее; по нижнему краю тонкая светлая кромка `#E0D4FF` — ярче на нижних скруглениях, посередине слабее, вверх по торцам гаснет. Заливка прежняя. Сверено по яркости в столбцах плашки с референсом: тень сверху и кромка — в пределах нескольких единиц из 255; пересобраны кадры `tools/shader_preview.py` (`G13_1_game` и др.) и `G20_1b_hearts`. Униформы, которые ставит `PillLabel`, — прежние |
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
