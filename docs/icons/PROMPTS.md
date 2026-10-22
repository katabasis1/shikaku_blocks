# Иконки через нейросеть: промпты (этап 12.3f)

Иконки из `tools/make_icons_a2.py` пользователь отклонил 01.10 («корявые»). Теперь иконки генерирует
нейросеть (ChatGPT Image или Nano Banana) по промптам ниже, а я их нарезаю и подключаю.
Промпты на английском: обе модели точнее выполняют английские описания. Каждый промпт самодостаточный:
блоки STYLE и SHEET RULES в них одинаковые, так листы получаются в одном стиле.

## Как генерировать
1. **Лист 1 первым.** Сделайте 3–5 попыток и выберите лучшую: она станет эталоном стиля.
2. **Листы 2–4 — в том же чате, с эталоном.** Приложите лучший лист 1 и оставьте первую строку промпта
   («Match the attached icon sheet exactly…»). Без вложения эту строку удалите.
3. **Формат.** ChatGPT: альбомный 3:2 (1536×1024). Nano Banana: в AI Studio выберите 3:2, в приложении
   Gemini хватит слов «landscape 3:2» из промпта. Если есть Nano Banana Pro или вывод 2K — берите их.
4. **Фон.** Белый подходит, потому что у каждой иконки сплошной тёмный контур и нет теней снаружи:
   так её чисто вырезать даже у белых кнопок. Мягкую фиолетовую тень добавит игра, одинаковую у всех.
   ChatGPT умеет настоящую прозрачность: можно заменить «Pure flat white background (#FFFFFF)» на
   «Transparent background». Nano Banana прозрачность не умеет: он рисует «шахматку», поэтому для него только белый.
5. **Что прислать.** Исходный PNG, как скачали: без обрезки, скриншота и сжатия. Если фон вышел
   кремовым (у ChatGPT бывает тёплый оттенок), ничего страшного, я выровняю.
6. **По желанию, для цвета:** приложите `docs/style_frames/A2_game.png` и допишите:
   «Use the attached screenshot only for colors and the glossy candy material of the blocks; do not copy its icons.»

## Правки в том же чате (если что-то не так)
- `Remove all text, numbers and labels. Keep everything else exactly the same.`
- `Remove every shadow and glow on the background; the background must be pure flat white. Keep the icons unchanged.`
- `Make all buttons exactly the same diameter and perfectly round, straight front view, no perspective.`
- `Make the glyphs bolder and chunkier, with the same stroke weight as the Pause icon.`
- `Make the dark outer outline continuous and equally thick on every icon.`
- `Only change icon N: <что исправить>. Keep all other icons exactly the same.`

## Что сделаю с результатом (docs/icons/raw → assets/icons)
Вырежу каждую иконку, уберу белую кайму, выровняю размер и центр и сохраню PNG 256×256. Затем проверю
читаемость на фиолетовом фоне при 96 px (кнопки) и 48 px (значок рекламы) и соберу лист «A2 / новые».
Если OFF-версии не совпадут с ON по положению знака, соберу их сам: ON + приглушение + отдельная полоса
с листа 3. Для руки измерю кончик пальца и поправлю `pivot_offset` в `scenes/ui/tutorial_hand.tscn`.
В игру PNG попадут на этапе 13 вместо SVG.

---

## Лист 1. Кнопки игры (6)
```
Create a game UI icon sheet: 6 round buttons for a mobile puzzle game, arranged in a 3 x 2 grid on a landscape 3:2 canvas.

STYLE (identical for every icon)
Premium mobile casual puzzle game UI, polished and playful cartoon style, like the glossy "candy" buttons of top-grossing match-3 and block-puzzle games. Soft 2D game illustration with gentle 3D volume: clean vector-like edges, smooth gradients, no texture, no noise, no photorealism.
Shapes are chunky, rounded and friendly. No sharp corners anywhere; all strokes are thick, with round caps and round joins.
Button material: a thick glossy candy disc seen straight from the front, with no perspective and no tilt. The face has a vertical gradient, lighter at the top and richer at the bottom. Under the face, a darker "lip" of the same hue shows the button's thickness (about 8% of its height, visible only at the bottom). A large soft curved highlight covers the upper third of the face and follows its curve. One small white sparkle sits at the upper left. A faint bounce light glows along the bottom inner edge.
Glyph: bold, simple and readable even at 48 px. It is centered, about 55% of the button diameter, built from thick rounded shapes with its own subtle gradient and a small highlight. Violet glyphs have a deep indigo outline.
Outline: every icon has one continuous, clean deep indigo outer outline (#2E1678, about 3% of the icon width) around its whole silhouette.
Light comes from the top left, the same on every icon.
Palette (saturated, clean): deep indigo #2E1678 for outlines; violet glyphs #8F72FF to #5B3FD9; white buttons #FFFFFF to #E6DDFF with a lavender lip #B49CF5; sky-blue buttons #6FD8FF to #1E9BEF with a lip #1170C4; yellow-orange buttons #FFE36B to #FFB01F with a lip #E07F00; green #7BEFA6 to #25C46C with a lip #15924C; pink-red #FF9BB0 to #FF4F6D with a lip #D12A4B; gold #FFF27A to #FFB300. The icons will be used on a saturated violet game background (#6A42E4).

SHEET RULES
Pure flat white background (#FFFFFF): no gradient, vignette, texture, floor, scenery or decoration. One icon per square cell of an invisible grid; all buttons have exactly the same diameter (about 80% of the cell) and are centered with generous white space, so nothing touches or overlaps. No drop shadow, cast shadow or glow outside the icon outline. No text, letters, numbers, labels, captions, watermark or grid lines.

ICONS
Top row, left to right:
1. Pause: white button; violet glyph of two thick vertical bars with fully rounded ends.
2. Restart: white button; violet glyph of a thick circular arrow running clockwise around about 300 degrees of a circle, with a big rounded arrowhead at the top right.
3. Undo: sky-blue button; white glyph of a thick U-turn arrow: the big rounded arrowhead at the upper left points left, the shaft runs to the right, curves down around the right side like a hook and ends at the lower middle. Deep blue glyph outline (#0B4F8F).
Bottom row, left to right:
4. Hint: yellow-orange button; glyph of a chubby cream-white light bulb with a rounded two-band screw base, a tiny shine on the glass and three short white rays above it. Brown-orange glyph outline (#A85400).
5. Home: white button; violet glyph of a chunky cartoon house with a rounded triangular roof, a small chimney and a rounded door cut-out.
6. Settings: white button; violet glyph of a chunky gear with 8 rounded teeth and a round hole in the center.
```

## Лист 2. Настройки: вкл / выкл (6)
```
Match the attached icon sheet exactly: the same button shape, candy material, outline thickness, glyph weight, colors and lighting.

Create a game UI icon sheet: 6 round toggle buttons for the settings screen of a mobile puzzle game, arranged in a 3 x 2 grid on a landscape 3:2 canvas. The top row is the ON state; the bottom row is the OFF state of the icon directly above it.

STYLE (identical for every icon)
Premium mobile casual puzzle game UI, polished and playful cartoon style, like the glossy "candy" buttons of top-grossing match-3 and block-puzzle games. Soft 2D game illustration with gentle 3D volume: clean vector-like edges, smooth gradients, no texture, no noise, no photorealism.
Shapes are chunky, rounded and friendly. No sharp corners anywhere; all strokes are thick, with round caps and round joins.
Button material: a thick glossy candy disc seen straight from the front, with no perspective and no tilt. The face has a vertical gradient, lighter at the top and richer at the bottom. Under the face, a darker "lip" of the same hue shows the button's thickness (about 8% of its height, visible only at the bottom). A large soft curved highlight covers the upper third of the face and follows its curve. One small white sparkle sits at the upper left. A faint bounce light glows along the bottom inner edge.
Glyph: bold, simple and readable even at 48 px. It is centered, about 55% of the button diameter, built from thick rounded shapes with its own subtle gradient and a small highlight. Violet glyphs have a deep indigo outline.
Outline: every icon has one continuous, clean deep indigo outer outline (#2E1678, about 3% of the icon width) around its whole silhouette.
Light comes from the top left, the same on every icon.
Palette (saturated, clean): deep indigo #2E1678 for outlines; violet glyphs #8F72FF to #5B3FD9; white buttons #FFFFFF to #E6DDFF with a lavender lip #B49CF5; sky-blue buttons #6FD8FF to #1E9BEF with a lip #1170C4; yellow-orange buttons #FFE36B to #FFB01F with a lip #E07F00; green #7BEFA6 to #25C46C with a lip #15924C; pink-red #FF9BB0 to #FF4F6D with a lip #D12A4B; gold #FFF27A to #FFB300. The icons will be used on a saturated violet game background (#6A42E4).

SHEET RULES
Pure flat white background (#FFFFFF): no gradient, vignette, texture, floor, scenery or decoration. One icon per square cell of an invisible grid; all buttons have exactly the same diameter (about 80% of the cell) and are centered with generous white space, so nothing touches or overlaps. No drop shadow, cast shadow or glow outside the icon outline. No text, letters, numbers, labels, captions, watermark or grid lines.

ICONS
Top row (ON), left to right:
1. Music on: white button; violet glyph of a chunky beamed pair of eighth notes with round note heads.
2. Sound on: white button; violet glyph of a rounded loudspeaker with two curved sound waves on its right.
3. Vibration on: white button; violet glyph of an upright rounded smartphone with a pale screen, with two short curved vibration marks on each side.
Bottom row (OFF), left to right: music off, sound off, vibration off. Each is an exact copy of the icon directly above it (the same button, glyph, size and position) with only two changes: the glyph is faded to pale lavender grey (#C9BEEF) with a softer outline (#8F7FD0), and a thick glossy pink-red diagonal slash (#FF4F6D, fully rounded ends, white border, deep indigo outline) crosses the glyph from top left to bottom right and stays inside the button.
```

## Лист 3. Звёзды, реклама, рука обучения (6)
```
Match the attached icon sheet exactly: the same candy material, outline thickness, colors and lighting.

Create a game UI icon sheet: 6 game items for a mobile puzzle game, arranged in a 3 x 2 grid on a landscape 3:2 canvas.

STYLE (identical for every icon)
Premium mobile casual puzzle game UI, polished and playful cartoon style, like the glossy "candy" items of top-grossing match-3 and block-puzzle games. Soft 2D game illustration with gentle 3D volume: clean vector-like edges, smooth gradients, no texture, no noise, no photorealism.
Shapes are chunky, rounded and friendly. No sharp corners anywhere; all strokes are thick, with round caps and round joins.
Material: thick glossy candy seen straight from the front, with no perspective. Every shape has a vertical gradient, lighter at the top and richer at the bottom, and a darker "lip" of the same hue at the bottom edge that shows its thickness. A large soft curved highlight covers the upper part and follows the shape. One small white sparkle sits at the upper left. A faint bounce light glows along the bottom inner edge.
Outline: every icon has one continuous, clean deep indigo outer outline (#2E1678, about 3% of the icon width) around its whole silhouette.
Light comes from the top left, the same on every icon.
Palette (saturated, clean): deep indigo #2E1678 for outlines; violet #8F72FF to #5B3FD9; white #FFFFFF to #E6DDFF with lavender shading #B49CF5; green #7BEFA6 to #25C46C with a lip #15924C; pink-red #FF9BB0 to #FF4F6D with a lip #D12A4B; gold #FFF27A to #FFB300 with an orange edge #D97A00. The icons will be used on a saturated violet game background (#6A42E4).

SHEET RULES
Pure flat white background (#FFFFFF): no gradient, vignette, texture, floor, scenery or decoration. One icon per square cell of an invisible grid; each icon is centered with generous white space, so nothing touches or overlaps. No drop shadow, cast shadow or glow outside the icon outline. No text, letters, numbers, labels, captions, watermark or grid lines.

ICONS
Top row, left to right:
1. Gold star (level rating), no button behind it: a chunky five-pointed star with softly rounded points, glossy gold gradient, a darker orange edge at the bottom for thickness, a big curved highlight and one sparkle; brown-orange outline (#A85400). About 85% of the cell.
2. Empty star slot (star not earned): the same star shape and size, but as an empty socket in flat muted violet (#6B5BC0) with a soft inner shadow and no shine.
3. Video ad badge, no round button: a green candy rounded square like a small TV screen, with a big white play triangle with rounded corners and a dark green glyph outline (#0E6636). It must stay readable at 48 px, so keep it very simple.
Bottom row, left to right:
4. Tutorial pointing hand: a classic cartoon white glove hand (four puffy fingers, like in old cartoons), seen from the back of the hand. The index finger points up, tilted about 15 degrees to the left, like pressing a phone screen; the other fingers are curled into the palm and the thumb rests on them. A rolled violet cuff (#8F72FF) at the wrist sits at the bottom. White with soft lavender shading, deep indigo outline, a soft highlight along the index finger. The fingertip touches the top edge of the icon area. About 85% of the cell height.
5. Counter badge: a small glossy pink-red candy circle with a thick white ring border and a deep indigo outline, blank inside (no number), about 45% of the cell.
6. OFF slash: a standalone thick glossy pink-red diagonal bar (#FF4F6D) with fully rounded ends, a white border and a deep indigo outline, running from top left to bottom right at 45 degrees, about 70% of the cell.
```

## Лист 4, по желанию: на будущее (карта уровней, лидеры, ежедневная задача)
```
Match the attached icon sheet exactly: the same button shape, candy material, outline thickness, glyph weight, colors and lighting.

Create a game UI icon sheet: 6 icons for a mobile puzzle game, arranged in a 3 x 2 grid on a landscape 3:2 canvas.

STYLE (identical for every icon)
Premium mobile casual puzzle game UI, polished and playful cartoon style, like the glossy "candy" buttons of top-grossing match-3 and block-puzzle games. Soft 2D game illustration with gentle 3D volume: clean vector-like edges, smooth gradients, no texture, no noise, no photorealism.
Shapes are chunky, rounded and friendly. No sharp corners anywhere; all strokes are thick, with round caps and round joins.
Material: thick glossy candy seen straight from the front, with no perspective and no tilt. Vertical gradient, lighter at the top and richer at the bottom; a darker "lip" of the same hue at the bottom edge shows the thickness; a large soft curved highlight on the upper part; one small white sparkle at the upper left; a faint bounce light along the bottom inner edge.
Glyphs on buttons: bold, simple, readable even at 48 px, centered, about 55% of the button diameter, with their own subtle gradient, highlight and outline.
Outline: every icon has one continuous, clean deep indigo outer outline (#2E1678, about 3% of the icon width) around its whole silhouette.
Light comes from the top left, the same on every icon.
Palette (saturated, clean): deep indigo #2E1678; violet #8F72FF to #5B3FD9; white buttons #FFFFFF to #E6DDFF with a lavender lip #B49CF5; green #7BEFA6 to #25C46C with a lip #15924C; pink-red #FF9BB0 to #FF4F6D with a lip #D12A4B; gold #FFF27A to #FFB300 with an orange edge #D97A00. The icons will be used on a saturated violet game background (#6A42E4).

SHEET RULES
Pure flat white background (#FFFFFF): no gradient, vignette, texture, floor, scenery or decoration. One icon per square cell of an invisible grid; round buttons all have the same diameter (about 80% of the cell); every icon is centered with generous white space, so nothing touches or overlaps. No drop shadow, cast shadow or glow outside the icon outline. No text, letters, numbers, labels, captions, watermark or grid lines.

ICONS
Top row, left to right:
1. Close: white round button; violet glyph of a chunky X with fully rounded ends.
2. Confirm: green round button; white check mark glyph with a dark green outline (#0E6636).
3. Play: green round button; white play triangle with rounded corners and a dark green outline (#0E6636).
Bottom row, left to right, no buttons behind them:
4. Lock (locked level): a chunky golden padlock with a thick rounded shackle and a violet keyhole.
5. Trophy (leaderboard): a chunky gold cup with two round handles on a short violet base.
6. Daily puzzle: a chubby calendar page with a pink-red top band and two round rings, a white page and a small gold star in the center.
```

## Лист 5. Этапы 18–19: лидеры, карта, механики на поле (8)
Сессия 99 (10.10): пользователь попросил переделать картинки этапов 18–19 в стиле листов 1–3. Сейчас их рисует
код или Python, а не нейросеть: кубок в меню (`tools/make_trophy.py` → `trophy.png`), замок закрытого уровня на
карте (`MapPath`), медали 1–3 у лидеров (`LeaderRows`), белая плитка препятствия, рамка цветной клетки и заклёпки
закреплённого блока (`CellMark`). Сетка 4 × 2 (ячейка 384 × 512 на листе 1536 × 1024), фон прозрачный (ChatGPT).
Если делаете в новом чате, приложите `docs/icons/icons_check.png` как эталон стиля.
Кружки уровней на карте и в «Лаборатории», плашки и карточка глав в лист не входят: это фигуры с числами
и текстом, которые игра рисует сама в цвете уровня или главы. (Кружки потом всё же заказаны — лист 6, пустые,
номер рисует игра.)
```
Match the attached icon sheet exactly: the same candy material, button shape, outline thickness, glyph weight, colors and lighting.

Create a game UI icon sheet: 8 icons for a mobile puzzle game, arranged in a 4 x 2 grid on a landscape 3:2 canvas.

STYLE (identical for every icon)
Premium mobile casual puzzle game UI, polished and playful cartoon style, like the glossy "candy" buttons of top-grossing match-3 and block-puzzle games. Soft 2D game illustration with gentle 3D volume: clean vector-like edges, smooth gradients, no texture, no noise, no photorealism.
Shapes are chunky, rounded and friendly. No sharp corners anywhere; all strokes are thick, with round caps and round joins.
Material: thick glossy candy seen straight from the front, with no perspective and no tilt. Every shape has a vertical gradient, lighter at the top and richer at the bottom, and a darker "lip" of the same hue at the bottom edge that shows its thickness (about 8% of its height, visible only at the bottom). A large soft curved highlight covers the upper part and follows the shape. One small white sparkle sits at the upper left. A faint bounce light glows along the bottom inner edge.
Glyph on a button: bold, simple and readable even at 48 px, centered, about 55% of the button diameter, built from thick rounded shapes with its own subtle gradient and a small highlight. Violet glyphs have a deep indigo outline.
Outline: every icon has one continuous, clean deep indigo outer outline (#2E1678, about 3% of the icon width) around its whole silhouette.
Light comes from the top left, the same on every icon.
Palette (saturated, clean): deep indigo #2E1678 for outlines; violet glyphs #8F72FF to #5B3FD9; white #FFFFFF to #E6DDFF with a lavender lip #B49CF5; gold #FFF27A to #FFC83D with a lip #E07F00; silver #F4F7FF to #AEBBD8 with a lip #7F8BAA; bronze #FFC9A0 to #E8955A with a lip #A9572A; cool grey-violet #C4BEE0 to #7D75A8 with a lip #5B5480. The icons will be used on a saturated violet game background (#6A42E4) and on a pale lavender game board (#EEE8FF).

SHEET RULES
Transparent background: no color, gradient, vignette, texture, floor, scenery or decoration behind the icons. One icon per cell of an invisible 4 x 2 grid, centered in its cell with generous empty space, so nothing touches or overlaps. Sizes are given as a share of the cell width. No drop shadow, cast shadow or glow outside the icon outline. No text, letters, numbers, labels, captions, watermark or grid lines.

ICONS
Top row, left to right:
1. Leaderboard button: a white round candy button, about 80% of the cell width, exactly like the white buttons on the attached sheet; violet glyph of a chunky trophy cup with two round loop handles, a short stem and a wide rounded base, with a small white five-pointed star on the cup.
2. Padlock (locked level), no button behind it: a chunky white padlock with a thick rounded shackle and a rounded-square body with a small violet keyhole, lavender lip at the bottom of the body. About 60% of the cell width.
3. Gold medal (1st place), no button: a glossy gold candy disc with a thick white ring border, completely blank inside (no number, no ribbon, no star). About 45% of the cell width.
4. Silver medal (2nd place): exactly the same disc, ring, size and lighting as icon 3, only in silver.
Bottom row, left to right:
5. Bronze medal (3rd place): exactly the same disc, ring, size and lighting as icon 3, only in bronze.
6. Obstacle tile: a raised square candy tile with well-rounded corners (corner radius about 20% of its side), white face, lavender lip at the bottom, big soft highlight; plain, with no glyph and no number. About 70% of the cell width.
7. Colored-cell frame: a thick rounded-square ring with exactly the same outer size and corners as tile 6; the ring is about 12% of its side wide and the inside is completely empty and transparent. Neutral glossy white-to-light-grey material (#FFFFFF to #C8C8D2) with no color hue at all, because the game recolors it; deep indigo outline on both the outer and the inner edge.
8. Rivet: a small round domed bolt head in cool grey-violet with a bright highlight dot, no slot or cross. About 25% of the cell width.
```

Правки в том же чате (если что-то не так):
- `Make icons 3, 4 and 5 exactly the same disc, size and white ring; only the color differs.`
- `Make the inside of icon 7 fully transparent; keep the ring white-grey with no color.`
- `Make icon 6 and the outer edge of icon 7 exactly the same size and shape.`
- `Only change icon N: <что исправить>. Keep all other icons exactly the same.`

**Сделано 10.10** (сессии 100–101). Лист пришёл на белом фоне, а не на прозрачном, и в просвете дужки замка
нарисована серая «шахматка» — `tools/cut_icons.py` вырезает и то и другое (`HOLES`). Нарезано в `assets/icons/`
(`trophy`, `lock`, `medal_gold`, `medal_silver`, `medal_bronze`, `obstacle`, `tint_frame`, `rivet`), подключено
вместо рисования в коде (`MapPath`, `LeaderRows`, `CellMark`, кнопка лидеров в меню), `tools/make_trophy.py`
удалён. Подробности — `docs/icons/README.md`, «Лист 5»; вид — `docs/STYLE.md`, 8, 11.1–11.3, 11.5.

## Лист 6. Кружки уровней: карта и «Лаборатория» (10)
Сессия 102 (10.10): пользователь (00:52) — «кружки уровней на карте и в «Лаборатории» тоже понадобятся». Сейчас их
рисует код (`MapPath._draw_node`, `LabRow._draw_node`): плоский круг цвета уровня, губа темнее на 0,3, блик-эллипс
22 %, без обводки. Номер уровня, звёзды под кружком, тень и белое кольцо-пульс у текущего игра рисует сама —
на картинке кружок пустой. Нужно 10 кружков: 7 цветов пройденных уровней (цвета блоков площадей 2, 3, 4, 6, 8,
12, 7 — `MapPath.PASSED_AREAS`), зелёный (текущий уровень на карте и пройденный в «Лаборатории»), фиолетовый
(непройденный в «Лаборатории»), белый (закрытый уровень: игра нарисует его полупрозрачным и положит сверху замок
листа 5). Сетка 5 × 2 (ячейка 307 × 512 на листе 1536 × 1024), фон — ровный белый (лист 5 тоже пришёл на белом,
`tools/cut_icons.py` его вырезает). Лучше в том же чате, где делали лист 5; в новом чате приложите лист 5
(`docs/icons/raw/sheet5_marks.png`) как эталон стиля.
```
Match the attached icon sheet exactly: the same candy material, outline thickness, colors and lighting as its round buttons and medals.

Create a game UI sheet: 10 blank round level buttons for a mobile puzzle game level map, arranged in a 5 x 2 grid on a landscape 3:2 canvas.

STYLE (identical for every disc)
Premium mobile casual puzzle game UI, polished and playful cartoon style, like the glossy "candy" level buttons on the map of top-grossing match-3 and block-puzzle games. Soft 2D game illustration with gentle 3D volume: clean vector-like edges, smooth gradients, no texture, no noise, no photorealism.
Material: a thick glossy candy disc seen straight from the front, with no perspective and no tilt. The face has a vertical gradient, lighter at the top and richer at the bottom. Under the face, a darker "lip" of the same hue shows the disc's thickness (about 8% of its height, visible only at the bottom). A soft curved highlight covers the upper third of the face and follows its curve. One small white sparkle sits at the upper left, close to the edge. A faint bounce light glows along the bottom inner edge. The center of the face stays clean and evenly colored, because the game prints a big white level number with a dark outline there.
Outline: every disc has one continuous, clean deep indigo outer outline (#2E1678, about 3% of the disc width) around its whole silhouette, including the lip.
Light comes from the top left, the same on every disc.
All 10 discs are exactly identical in size, shape, outline, lip, highlight, sparkle and bounce light. Only the color differs.
The discs will be used on a saturated violet game background (#6A42E4).

SHEET RULES
Pure flat white background (#FFFFFF): no gradient, vignette, texture, floor, scenery or decoration. One disc per cell of an invisible 5 x 2 grid; every disc is about 80% of the cell width and centered in its cell with generous white space, so nothing touches or overlaps. No drop shadow, cast shadow or glow outside the outline. Every disc face is completely blank: no numbers, letters, stars, symbols, icons or glyphs. No text, labels, captions, watermark or grid lines.

DISCS (face gradient top to bottom, then lip)
Top row, left to right:
1. Red: #FF8F87 to #F0463A, lip #C42E26.
2. Orange: #FFC07D to #F0912B, lip #D46A00.
3. Yellow: #FFE388 to #F5C53B, lip #E09A00.
4. Sky blue: #7DDDFA to #2BBCE8, lip #1F8FB8.
5. Blue: #88ADFF to #3B74F0, lip #2C56B2.
Bottom row, left to right:
6. Pink: #FF9CC9 to #F0599E, lip #B24276.
7. Magenta: #EF94E6 to #D74DC9, lip #A03996.
8. Green: #7BEFA6 to #25C46C, lip #15924C.
9. Violet: #B7A4F9 to #8366E7, lip #614CAC.
10. White: #FFFFFF to #E6DDFF, lip #B49CF5, exactly like the white buttons on the attached sheet.
```

Правки в том же чате (если что-то не так):
- `Remove every number, letter and symbol from the discs; all 10 faces must be completely blank.`
- `Make all 10 discs exactly the same size, shape and lighting; only the color differs.`
- `Keep the center of every face clean: move the highlight to the upper third and the sparkle closer to the upper-left edge.`
- `Only change disc N: <что исправить>. Keep all other discs exactly the same.`

Что сделаю с результатом: нарежу в `assets/icons/` (`node_red`, `node_orange`, `node_yellow`, `node_sky`,
`node_blue`, `node_pink`, `node_magenta`, `node_green`, `node_violet`, `node_white`), подключу в `MapPath` и
`LabRow` вместо кругов кодом (тень, номер, звёзды и пульс останутся кодом; номер — по центру лица, губа его
смещает), подберу прозрачность белого кружка закрытого уровня под замок, пересоберу `G18_2_map` и `G19_3_lab`
и покажу «было / стало».

**Сделано 10.10** (сессия 103). Лист пришёл на белом фоне, все 10 кружков пустые и одинаковые (середина лица —
разброс 1 px), правки в чате не понадобились. Нарезано в `assets/icons/` (`node_red` … `node_white`, 192 px),
подключено в `MapPath` и `LabRow` вместо кругов кодом; закрытый уровень — белый кружок на 50 % с замком.
Подробности — `docs/icons/README.md`, «Лист 6»; вид — `docs/STYLE.md`, 8, 11.2, 11.5, 14.
