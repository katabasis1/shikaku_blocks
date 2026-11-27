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
| `win_rays.jpg` | окно победы — фон за полем: около 20 мягких розово-лавандовых лучей с размытыми краями (каждый второй слабее), гаснут примерно в 200 px от поля; плотное розовое свечение по форме поля, на углах слабее | кадр окна победы старым шейдером, 720×1280 (`win_rays_input.jpg`) | П7 |
| `win_rays_cmp.jpg` | сравнение: референс / до (`main`) / после переделки `win_rays.gdshader` (27.11, вечер); верх кадра победы, y 0…1000 | — | — |
| `ghost.jpg` | призрак места: жёлтый (верное место, блок 4) и красный (нельзя) — светящийся прозрачный «слот» цвета блока: заливка плотнее и светлее к верху, внутреннее свечение вдоль рамки, чёткая белая рамка, мягкое свечение цвета блока снаружи; клетки и гнездо числа под ним видны | правый верх поля из кадров `tools/shader_preview.py` (обычный и `--bad`) старым шейдером рядом, ×2, 1920×1080 (`ghost_input.jpg`) | П8 |
| `ghost_cmp.jpg` | сравнение: референс / до (`main`) / после переделки `ghost.gdshader` (27.11, вечер); сверху — жёлтый, снизу — красный | — | — |
| `check.jpg` | галочка «число закрыто» на четырёх блоках (жёлтый 4, голубой 6, красный 2, оранжевый 3) — толстая глянцевая белая «конфета» со скруглёнными концами: обводка цвета блока, мягкая короткая тень вниз-вправо, к нижней кромке линии — лавандовая тень, сильнее у низа «V» | кадр `tools/check_preview.py` старым шейдером: поле 5×3, клетка 150 px, 1200×800 (`check_input.jpg`) | П9 |
| `check_cmp.jpg` | сравнение: референс / до (`main`) / после переделки `check.gdshader` (27.11, вечер); снизу — галочки крупно (жёлтый, голубой; красный, оранжевый) | — | — |
| `line_wave.jpg` | волна света по закрытой нижней строке (поле 6×3: оранжевый 3, красный 2 — закрыл строку, голубой 6) в миг, когда гребень на голубом: свет только в блоках — белая полоса с мягким свечением, к низу ярче; тонкая яркая полоса блика по нижней кромке блоков; жёлтый светится от нижней кромки; блоки сочные, без белой плашки поверх линии | кадр `tools/line_wave_preview.py` старым шейдером: клетка 170 px, 1500×1000, 0,14 с после удара (`line_wave_input.jpg`) | П10 |
| `line_wave_cmp.jpg` | сравнение: референс / до (`main`) / после переделки `line_wave.gdshader` (27.11, вечер); снизу — линия крупно | — | — |
| `win_wave.jpg` | волна света победы (поле 6×4, последний блок 2 встал в правый нижний угол) в миг, когда гребень посередине поля: свет только в блоках — тонкая дуга с горячим белым ядром и мягким свечением; зазоры между блоками и рамка не светятся; блоки сочные, без белой дымки поверх поля | кадр `tools/win_wave_preview.py` старым шейдером: клетка 170 px, 1500×1000, 0,21 с после касания поля (`win_wave_input.jpg`) | П11 |
| `win_wave_cmp.jpg` | сравнение: референс / до (`main`) / после переделки `win_wave.gdshader` (27.11, вечер); снизу — поле крупно | — | — |

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

**П7** (9:16, генератор изображений Dust, 27.11, утро; вход — кадр окна победы старым шейдером, 720×1280,
`win_rays_input.jpg`; дословно): «Redraw this level-complete screen of a mobile puzzle game (Shikaku Blocks) keeping
EXACTLY the same layout, proportions, positions and sizes of everything: the title "УРОВЕНЬ 20 ПРОЙДЕН!", the board
with all its blocks and numbers, the three stars, the card with the orange header and all its text, the green button,
the confetti and the violet background colors. Change only the celebratory light behind the board: render it more
beautifully, like a premium polished casual mobile game. A sunburst of about 20 soft light rays radiating from the
center of the board: each ray is a long tapering wedge of soft white-lavender light with gently feathered edges (no
hard cut edges), brightest close to the board and fading smoothly into the background toward the screen edges, with a
subtle alternation of brighter and fainter rays. Around the board a soft warm pink-lavender glow halo that fades
smoothly. Subtle and calm: the rays stay behind the board and the card, do not cover any UI and do not wash out the
violet background. No lens flares, no extra sparkles, no extra objects, no extra text. Clean, crisp, vector-like, soft
studio lighting.» Раскладку генератор сохранил; лучи он повернул по-своему, поэтому сверялось не по пикселям, а по
полосам удалённости от поля. Под самой кромкой поля на референсе нет тени поля (свечение её «залило») — в игре тень
рисует поле поверх свечения, там кадр темнее.

**П8** (16:9, генератор изображений Dust, 27.11, вечер; вход — `ghost_input.jpg`: правый верх поля, слева призрак
верного места — жёлтый, блок 4, справа места, куда нельзя, — красный). Дословный текст не сохранился: первый заход
агента оборвался раньше, чем промпт записали сюда (как с П2). Суть (по картинке): перерисовать только призрак, сохранив
раскладку, клетки, гнездо числа и блоки, — светящийся прозрачный «слот» цвета блока: заливка плотнее, к верху светлее,
мягкое внутреннее свечение вдоль рамки, чёткая белая рамка по скруглённому контуру, мягкое свечение цвета блока
снаружи; клетки и число под призраком видны; у красного — то же, тусклее, свечение розово-красное.

**П9** (3:2, генератор изображений Dust, 27.11, вечер; вход — кадр `tools/check_preview.py` старым шейдером,
1200×800, `check_input.jpg`; дословно): «Redraw this close-up of a mobile puzzle game board (Shikaku Blocks) keeping
EXACTLY the same layout, proportions, positions and sizes of everything: the white board frame, the four candy blocks
(yellow, cyan, red, orange) with their cell seams, the violet background, and the four check marks - same position,
size, angle and stroke thickness of each check mark. Change only the four check marks: render them more beautifully,
like a premium polished casual mobile game, as thick glossy white candy strokes with rounded ends and a rounded inner
corner. Each check keeps a darker outline in the color of its block (dark amber on yellow, dark teal on cyan, dark red
on red, dark brown-orange on orange) and a soft short drop shadow below in the same darker tone. Give the white stroke
volume: a crisp thin bright highlight line running along the upper edge of the stroke that follows its shape and fades
toward the ends, a very subtle cool lavender shading toward the lower edge of the stroke, a thin lighter inner rim
just inside the outline. All highlights follow the stroke shape and fade smoothly, no stuck-on ovals or abruptly cut
lines. Clean, crisp, vector-like, soft studio lighting from the top, no sparkles, no extra objects, no extra text.»
Раскладку и блоки генератор сохранил, галочки сделал толще и крупнее (это и взято). Отдельной линии блика на белом не
видно — верх линии просто белый; лавандовая тень к нижней кромке заметнее, чем просили. Галочки на красном и оранжевом
он нарисовал иначе, чем на жёлтом и голубом (ни при каком сдвиге окно не совпадает лучше ≈16 из 255), — форма в игре
одна на все блоки, подбиралась по жёлтому и голубому.

**П10** (3:2, генератор изображений Dust, 27.11, вечер; вход — кадр `tools/line_wave_preview.py` старым шейдером,
1500×1000, `line_wave_input.jpg`: поле 6×3, блок 2 закрыл нижнюю строку, 0,14 с после удара — гребень на голубом
блоке 6). Дословный текст не сохранился: агенты, которые генерировали картинку, оборвались раньше, чем записали
промпт сюда (как с П2 и П8). Вариантов было два, оба остались в файлах беседы h3uDh6xF5o: `line_wave_ref.png` и
`line_wave_ref_p10.png`; в референс (`line_wave.jpg`) взят второй. Что на нём (по картинке): раскладка, поле и
блоки — как на входе; свет только внутри блоков линии — на голубом вертикальная белая полоса с мягким свечением,
к низу ярче; по нижней кромке блоков через всю строку — тонкая яркая полоса блика; жёлтый светится от нижней
кромки вверх; блоки сочные, белой плашки поверх линии и зазоров нет. Не взято: звёздочка-блик в зазоре между красным
и голубым (к волне не привязана) и сочный красный блок 2 — бледность красного даёт вспышка блока (`flash` в
`block.gdshader`, `line_block_flash` 0,55), а не этот шейдер.

**П11** (3:2, генератор изображений Dust, 27.11, вечер; вход — кадр `tools/win_wave_preview.py` старым шейдером,
1500×1000, `win_wave_input.jpg`: поле 6×4 из `tools/win_preview.py`, последний блок 2 встал в правый нижний угол,
0,21 с после касания поля — фронт посередине поля; исходник картинки — `win_wave_ref_p11.png` в файлах беседы
h3uDh6xF5o): «Redraw this mobile puzzle game board (Shikaku Blocks) at the moment of winning the level, keeping
EXACTLY the same layout, proportions, positions and sizes of everything: the white board frame with its lavender tray,
the seven candy-jelly blocks (cyan 6, orange 3, orange 3, red 2, yellow 4 at right, long yellow 4 at bottom, red 2
with a white check mark at bottom right), their digits, cell seams and gaps between them, and the violet background.
A ring-shaped wave of light is spreading over the board from the last placed block at the bottom right toward the far
top-left corner; right now its crest crosses the middle of the board diagonally. Render this victory light wave more
beautifully, like a premium polished casual mobile game: the light lives only inside the candy blocks, as if each
block lights up from within when the crest passes it — a bright soft white glowing band following the arc of the
ring with a crisp hot white core, the gaps between blocks and the board frame stay clean and do not glow, no flat
white haze over the board. Behind the crest each lit block keeps a soft inner glow along its rounded edges and a thin
bright highlight line along its bottom edge; blocks ahead of the crest are normal. Keep the blocks juicy and
saturated, not washed out. Clean, crisp, vector-like, soft studio lighting from the top, no sparkles, no stars, no
extra objects, no extra text.»
Раскладку, поле и блоки генератор сохранил. Взято: свет только в блоках, зазоры и рамка чистые; гребень — тонкая
дуга, горячее белое ядро и мягкое свечение вокруг. Профиль поперёк дуги снят по картинке (голубой блок, доля пути к
белому, px кадра с клеткой 170): 0,94 в 3 px от оси, 0,76 в 12, 0,58 в 20, 0,43 в 30, 0,25 в 40, 0,05 в 60 — по нему
подобраны ширины ядра и свечения. Не взято: дуга лежит не там, где фронт на входе (через голубой 6 в жёлтый 4, а не
через оранжевый 3 и нижний жёлтый 4), и выгнута не как кольцо из угла — в игре форма задана кольцом из последнего
блока; сочные блоки — бледность в кадре даёт вспышка блока (`flash` в `block.gdshader`, `win_block_flash` 0,7), а не
этот шейдер. Светлые ободки блоков на референсе есть и впереди гребня — это материал блоков, не волна.

**П12 — отклонено пользователем (28.11).** (9:16, генератор изображений Dust, 28.11, ночь; вход — кадр
`G13_1_game.png` под шторкой нынешним шейдером, закрытие 45 %; исходник картинки — `curtain_ref_p12.png` в файлах
беседы S8OJFOZGVw, дословный промпт — `backups/P12_prompt_curtain.txt` в Pod `vlt_tCyvJFiQXbcNvl`.) Суть: та же сетка
плиток шторки на тех же местах, но каждая плитка — мармеладная: глянец светлее к верху, тонкая лавандовая линия
блика по верхней кромке, тёмная скруглённая губа-толщина снизу, короткая мягкая тень на экран игры; слитая область —
ровная, без швов. По картинке был написан черновик шейдера; пользователь отклонил его вид («новый выглядит
отвратительно»), шторка прежняя. Не повторять: объёмные плитки с бликом, губой и тенью.

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
| 8 | `win_rays.gdshader` | лучи и свечение победы (`WinBackdrop`); тот же шейдер — свечение логотипа меню и промо | `win_rays.jpg` | 27.11, вечер: лучи — мягкие клинья вместо белых клиньев с резким краем: ядро 0,06 периода от оси, дальше плавно гаснут за 0,26 периода; каждый второй ×0,6; цвет (255, 215, 255); сила 0,9 (была 0,09), радиус 600 px (был 760). Свечение — скруглённый прямоугольник по рамке поля вместо эллипса: на 70 px шире рамки с каждой стороны при любом размере поля (`WinBackdrop.GLOW_MARGIN`; `play` и `set_center` теперь получают размер рамки, на альбомном поле тоже 70 px), скругление 250, край σ 28 px, (255, 199, 255) 92 % (было (255, 225, 255) 40 %, σ 70). Сверено с референсом по полосам удалённости от поля: от 30 px и дальше — в пределах ±7 единиц яркости из 255; у самой кромки поля темнее на ~30 (тень поля поверх свечения); разброс яркости лучей у края экрана 11 против 9 у референса, у карточки 3,1 против 3,3. Меню и промо — прежний вид, задан явно (`MenuLogo._make_halo`, `RAYS_CLASSIC` в `shader_preview.py`): кадр меню и промо-картинки совпали со старым шейдером до пикселя. Пересобраны `G13_5_win` и промо (они устарели ещё после строк 1–3; `promo_check` — 0 проблем) |
| 9 | `ghost.gdshader` | место несомого блока | `ghost.jpg` | 27.11, вечер: светящийся «слот» вместо плоской заливки 35 % с рамкой 5 px. Заливка 60 %, к низу плотнее (×1,18); у верха (спад 10 px) и вдоль рамки цвет ярче (×1,2) и белее на 10 %; вдоль рамки изнутри заливка плотнее на 18 % (спад 6,5 px, на верхней стороне ×0,4); белая рамка 4,4 px, отступив 0,8 px от края; снаружи свечение цвета площади, осветлённого на 20 %: Гаусс σ 9 px, 90 % у края. Красный (униформа `bad`, раньше — `frame_alpha` 0,6 из кода): заливка 46 %, внутреннее свечение 5 %, рамка 60 %, свечение `#FF7690`. Узел `Board/Ghost` шире места на `Board.GHOST_GLOW` = 28 px с каждой стороны (поля под свечение, `Board._place_ghost`; пересчёт при смене масштаба). В `board.tscn` стояли старые `body_alpha` 0,35 и `frame_px` 5 — исправлены (иначе в Godot был бы прежний вид). Сверено с референсом по зонам (свечение над призраком, клетки, перекрестье, весь призрак): средний цвет — в пределах 7 из 255 (до переделки 18–45). Пересобраны `G13_1_game`, `G13_1_compare`; промо не изменились |
| 10 | `check.gdshader` | галочка «число закрыто» (`Block.close_number`) | `check.jpg` | 27.11, вечер: толстая глянцевая белая «конфета» вместо тонкой белой линии. Линия 15,5 px блока (была 10), галочка крупнее: точки (29,5; 50) → (42; 64) → (69,5; 33) (были (31; 52) → (44; 64) → (69; 37)). Заливка белая, к нижней кромке — лавандовая тень `#8C7ADB` с примесью цвета площади 27 % (новая униформа `tint_color`, её ставит `Block._check_node`): вес — сдвиг пикселя вниз от оси линии, от 0 до 0,7 полутолщины, поэтому тень огибает концы и сильнее всего у низа «V». Обводка прежняя (9, `Palette.block_digit_outline`). Тень мягкая: сдвиг (4; 6,5) вместо (0; 4), Гаусс σ 2 px от края обводки, сила 0,47 × 0,85. Всё помещается в узел 100 × 100 — размер узла прежний. Сверено с референсом (`tools/check_preview.py --cmp`, среднее отличие в окне 150 × 150 вокруг галочки, из 255): жёлтый 15,7 → 7,0, голубой 17,7 → 6,8; красный и оранжевый ≈17 до и после — там генератор нарисовал галочку иначе (см. П9). Пересобран `G14_3_close` |
| 11 | `line_wave.gdshader` | волна света по ряду (`LineFlash`) | `line_wave.jpg` | 27.11, вечер: свет только в блоках линии вместо белой плашки во всю линию (след 0,35 бледнил блоки и светил в зазорах). Новые униформы `parts[16]` / `part_count` — прямоугольники блоков, задевающих линию (их передаёт `Board.flash_line` через `LineFlash.play(…, parts)`); форма — тела блоков (лицо + губа, как в `block.gdshader`: зазор 4,5, губа 7,5, скругление 24 px); без блоков — вся линия, как раньше. Гребень: белое ядро (Гаусс, 0,55 ширины полосы) и свечение 0,6 вокруг, к низу строки ярче (вверху ×0,75), у края узла поперёк линии гаснет за 22 px. Позади фронта вместо ровного следа — свет по кромке блоков (след × 1,8, гаснет вглубь за 13 px) и дымка к низу (0,35). По нижней кромке губы — полоса блика (3 px от края, σ 2,4 px), у гребня ярче всего, позади — 0,9. Сверено с референсом (`tools/line_wave_preview.py --cmp`, среднее отличие по лицам блоков в линии, из 255): оранжевый 19,3 → 17,5, голубой 16,4 → 14,2, красный 53,7 → 50,2 — красный бледнее референса из-за вспышки блока (`flash`), см. П10. Переводчик `shader_preview.py` понимает массивы униформ. Пересобран `G14_4_line` |
| 12 | `win_wave.gdshader` | волна света победы (`WinWave`) | `win_wave.jpg` | 27.11, вечер: свет только в блоках вместо белой дымки по всему полю (полоса 1,6 клетки, гребень σ ≈ 40 px поля, след 0,3 — бледнили всё поле и светили в зазорах и по рамке). Новые униформы `cells[81]` / `grid` / `cell`: у каждой клетки поля — прямоугольник её блока в клетках (`Board.celebrate` передаёт блоки в `WinWave.play(…, blocks, grid)`, заполняет `WinWave._set_cells`); пиксель берёт блок своей клетки — одно чтение, без цикла по блокам; форма — тела блоков (лицо + губа, как в `block.gdshader` и строке 11); поле больше 81 клетки или без блоков — всё поле, как раньше. Гребень — тонкая дуга кольца: горячее белое ядро (Гаусс, 0,06 полосы — σ ≈ 2,4 px поля) и свечение 0,8 (0,38 полосы — σ ≈ 15 px), у кромки блока ярче. Позади фронта — свет по кромке блоков (след × 1,0, гаснет вглубь за 13 px) и лёгкая дымка 0,05; по нижней кромке губы — полоса блика, как в строке 11 (позади — 0,6). Сверено с референсом (`tools/win_wave_preview.py --cmp`, среднее отличие из 255): лица блоков 36,2 → 26,6, зазоры 32,0 → 22,8; профиль дуги — по замеру на референсе (см. П11). Бледность блоков — вспышка блока (`win_block_flash` 0,7), не этот шейдер. Переводчик `shader_preview.py` понимает индекс массива униформ, свой у каждого пикселя. В selftest — проверка, что волна знает блок каждой клетки (`_wave_cells_ok`). Пересобран `G14_5_win` |
| 13 | `transition.gdshader` | шторка (`Transition`) | П12 — **отклонён** | **Не менять — решение пользователя 28.11 (02:18): «верни этот шейдер как был раньше, новый выглядит отвратительно»; 02:23: «шторка остаётся как есть».** Черновик по П12 в проект не попал, шейдер — как в `main`. П12 оставлен как запись отклонённого направления |
| 14 | `soft_shadow.gdshader` | мягкие тени | служебный — менять, только если референс покажет другую тень | — |
| 15 | `tex_shadow.gdshader` | тени картинок | служебный | — |

Godot в Компьютере нет: шейдер проверяется переводчиком `tools/shader_preview.py` (тот же код на numpy). Ошибки
типов Godot (int вместо float и т. п.) он не ловит — писать `1.0`, а не `1`; прогон в Godot — у пользователя (20.7).
