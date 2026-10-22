# Промпты для ChatGPT Image: обложка и иконка (16.5b, 11.10)

Своя иконка и обложки рисуются `tools/promo_art.py` (`docs/PROMO.md`, «Картинки») — это запасной вариант, он всегда
верен игре. Здесь промпты, чтобы ChatGPT нарисовал более «сочную» иллюстрированную версию того же сюжета: поле почти
собрано, красная двойка поднята над своим гнездом, рука обучения тащит её на место.

## Как пользоваться
1. **Прикрепите к сообщению картинку-образец** из `docs/promo/`: для обложки — `cover_800x470_notext.png`, для
   иконки — `icon_512.png`. Без образца ChatGPT придумает свою игру, а обложка должна показывать эту (модерация
   проверяет, что промо соответствует игре).
2. Вставьте общий блок «Стиль и правило игры» и промпт нужной картинки — одним сообщением, промпты на английском
   (так точнее), надписи на картинке — по-русски в кавычках.
3. Попросите 3–4 варианта, выберите лучший, мелочи правьте промптами-правками (ниже).
4. **Проверьте глазами** (чек-лист ниже), обрежьте под размер консоли — или пришлите картинку в чат: обрежу и
   проверю.

Размеры: ChatGPT рисует 1536×1024 (альбом) и 1024×1024 (квадрат). Обложка консоли 800×470 (1,70:1) — из 1536×1024
вырезается полоса 1536×903 по центру (по ~60 px сверху и снизу), затем уменьшение до 800×470. Иконка 1024 → 512. PNG
без прозрачности.

## Стиль и правило игры (вставлять в начало каждого промпта)
```text
Reference: the attached image is from my game. Keep its board, blocks, colors and composition, but redraw it as polished, juicy key art for a game catalog.

Style: premium casual mobile puzzle game art. Glossy 3D candy-like blocks with rounded corners, soft bevels, bright highlights and soft drop shadows. A white rounded board frame with a light grey square grid. Vivid saturated colors, soft studio lighting, high contrast, crisp clean edges. Background: rich violet-purple gradient (#5B4DCA to #A16AD9) with soft radial light rays and a bright glow behind the board, a few small white four-point sparkles. Few large shapes and strong silhouettes so it reads at thumbnail size.

Game rule (must be correct): this is a "shikaku" number puzzle. Every block is a rectangle made of square cells. Each block shows exactly ONE white number with a dark outline, and that number equals the number of cells in the block. No other numbers anywhere. Block colors: 2 = red #FF4B3E, 3 = orange #FF9A2E, 4 = yellow #FFD23F, 6 = sky blue #2EC8F7, 9 = teal #14CDB8.
```

## 1. Обложка без текста (основная)
```text
Landscape image 1536x1024. It will be cropped to 800x470, so keep everything important inside the central horizontal band and leave about 8% of plain background at the top and at the bottom.

Center: a big puzzle board, 6 cells wide and 4 cells tall, tilted about 3 degrees, seen from the front with slight 3D depth. Board layout:
- left: sky blue block, 2 wide x 3 tall, number 6;
- top middle: teal block, 3 x 3, number 9;
- right edge: yellow block, 1 wide x 4 tall, number 4;
- bottom middle: orange block, 3 wide x 1 tall, number 3;
- bottom left: an EMPTY 2 x 1 spot — two empty grid cells with a small red rounded outline and a red number 2 (the target).
A red block, 2 wide x 1 tall, number 2, floats above and slightly to the right of the empty spot, lifted, tilted about 7 degrees, slightly bigger, with a deeper shadow — it is being dragged into place. A cartoon white glove hand (casual game tutorial style, index finger up) touches the right part of the red block from below.
No text, no letters, no logos, no buttons or UI, no extra numbers.
```

## 2. Обложка с названием (ru)
```text
Landscape image 1536x1024, cropped later to 800x470: keep everything inside the central band, 8% empty background at top and bottom.

Left 60%: the same puzzle board and scene as in the reference (6 x 4 board, the floating red block 2 and the white glove hand), the board may be slightly cut by the left edge.
Right 40%: the game title in three centered lines, huge bold rounded font like Nunito Black, white letters with a thick dark indigo outline (#2E1678) and a soft shadow; the third line is yellow (#FFD23F):
"РАССТАВЬ"
"БЛОКИ"
"ПО ЧИСЛАМ"
Spell the Russian words exactly, letter by letter: Р-А-С-С-Т-А-В-Ь, Б-Л-О-К-И, П-О Ч-И-С-Л-А-М. No other text anywhere.
```
Английская и турецкая — тот же промпт, строки: `"BLOCKS"` / `"BY NUMBERS"` (вторая жёлтая) и `"BLOKLARI"` /
`"SAYILARLA"` / `"YERLEŞTİR"` (вторая жёлтая; попросите писать «Ş» и «İ» с точкой).

## 3. Иконка
```text
Square app icon 1024x1024, no text. Close-up of a small puzzle board, 3 x 3 cells, white rounded frame, tilted about -5 degrees, filling about 75% of the icon. Layout:
- left column: orange block, 1 wide x 3 tall, number 3;
- top right: yellow block, 2 x 2, number 4;
- bottom right: an EMPTY 2 x 1 spot with a red rounded outline and a red number 2.
A glossy red block, 2 wide x 1 tall, number 2, floats just above that spot, lifted and tilted, with a soft shadow. A cartoon white glove hand points at it from the bottom right.
Keep all key elements away from the corners (the icon gets rounded corners). No text, no letters, no frame around the icon, no logos.
```

## 4. Иконка, вариант «крупно» (без поля)
```text
Square app icon 1024x1024, no text. Three big glossy candy blocks fill the icon, stacked diagonally with depth: a yellow 2 x 2 block with number 4 at the back, an orange 1 x 3 block with number 3 in the middle, and a red 2 x 1 block with number 2 in front, flying slightly up and tilted, with a cartoon white glove hand touching it from below. Each block shows its cells as soft grooves. Violet-purple background with radial rays and glow, a few sparkles. Keep everything away from the corners. No text, no letters, no logos.
```

## Правки (отдельным сообщением после генерации)
```text
Keep everything identical, only fix the numbers: every block shows exactly one number equal to its number of cells (2x3 = 6, 3x3 = 9, 1x4 = 4, 3x1 = 3, 2x1 = 2). Remove any other numbers.
```
```text
Make it juicier: more saturated colors, stronger glossy highlights, brighter glow and light rays behind the board, more contrast between the blocks and the background. Add a few tiny confetti squares in the block colors around the floating red block. Keep the layout.
```
```text
Zoom out a little: nothing important may touch the edges; leave about 8% plain background at the top and the bottom.
```
```text
Make the hand a simple cartoon white glove with four fingers, index finger pointing — like a casual game tutorial hand, no realistic skin.
```

## Чек-лист перед загрузкой
- Число на каждом блоке = числу его клеток; одно число на блок; других чисел нет.
- Поле, блоки и цвета узнаются как наша игра (сравните со скриншотом); нет чужих персонажей и предметов.
- Надпись — слово в слово, без лишних и перепутанных букв (кириллица у генератора ломается чаще всего); других
  надписей нет.
- Ничего важного у краёв: обложку потом режут до 800×470, у иконки в каталоге скругляют углы.
- В миниатюре (уменьшить до ~190 px шириной обложку и до 64 px иконку) понятно, что это блоки с числами.
- PNG 800×470 и 512×512, без прозрачности.
