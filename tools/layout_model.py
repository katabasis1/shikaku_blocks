#!/usr/bin/env python3
"""Python-двойник scripts/game_layout.gd: проверка раскладок на любой ширине и схемы.

Проверяет для набора экранов (логические px, высота 1280 у любого широкого окна):
  - всё внутри экрана, отступ от краёв не меньше EDGE;
  - панель, поле, «Осталось блоков», кнопки, лоток и подпись не перекрываются
    (всплывающее сообщение лежит поверх поля — так задумано);
  - три гнезда помещаются в лоток; корпус полки (shelf) = лоток + shelf_pad со всех сторон (13.2a),
    внутри экрана и не задевает кнопки и подпись; поле в альбоме не меньше портретного;
  - группа «поле + столбик» по центру; на 16:9 она занимает ≥ 70 % ширины (требование 1.10);
  - гистерезис: у порога раскладка не прыгает;
  - победа (13.5b, STYLE 11): заголовок, поле и карточка с губой на экране, звёзды на кромке карточки не
    заходят на поле и заголовок, в альбоме поле на месте, заголовок и карточка в столбике; надписи окна
    («УРОВЕНЬ 300 ПРОЙДЕН!», шапка карточки, «+очки», «Всего очков», «ДАЛЕЕ», «Переиграть уровень»)
    влезают на всех языках; клетка поля на победе не мельче WIN_CELL_MIN.
Числа должны совпадать с game_layout.gd — при правке менять оба файла.

  python3 tools/layout_model.py            # проверки
  python3 tools/layout_model.py --png DIR  # ещё и схемы раскладок в DIR (docs/layout)
Код выхода 0 — всё хорошо.
"""
import pathlib
import re
import sys

TO_LANDSCAPE, TO_PORTRAIT = 1.15, 1.10
COLUMN = 720.0
SIDE_W, SIDE_GAP, MARGIN, BOARD_MAX, HEIGHT = 560.0, 64.0, 40.0, 1168.0, 1280.0
EDGE = 8.0
CELL, PAD, FRAME_DEPTH = 100.0, 26.0, 12.0  # board.gd; PAD и губа — логические px (13.1c), не масштабируются
BOARD_SCALE = {False: 1.35, True: 2.4}
TRAY_SCALE = {False: 0.62, True: 0.78}   # 13.2a: клетка в лотке 62 px в портрете (было 46)
SHELF_PAD = {False: 12.0, True: 14.0}
# Шапка (13.2c): размеры шрифта и центры строк от верха top_bar; подпись на плашке «Осталось блоков».
TITLE_SIZE = {False: 50, True: 48}
SCORE_SIZE = 38
TITLE_Y = {False: 34.0, True: 30.0}
SCORE_Y = {False: 88.0, True: 90.0}
REMAINING_SIZE = {False: 27, True: 29}
# Плашка (scripts/pill_label.gd) и шапка (scenes/game/hud_header.gd).
PILL_PAD_X, PILL_HEIGHT_K, PILL_TEXT_RISE = 24.0, 1.9, 1.0
TITLE_OUTLINE, TITLE_MIN_SIZE, BUTTON, BAR_SEP = 0.13, 24, 96.0, 12.0
# Победа (13.5b): GameLayout.WIN_* и места внутри карточки (scenes/ui/win_panel.gd / .tscn, тема).
WIN_CARD = (512.0, 428.0)
WIN_TITLE_SIZE = {False: 46, True: 50}
WIN_TITLE_Y, WIN_BOARD_TOP, WIN_CARD_BOTTOM, WIN_STARS = 94.0, 130.0, 494.0, 120.0
WIN_BOARD_SCALE = {False: 1.0, True: 2.4}
CARD_LIP = 14.0                    # CandyCard.LIP: губа под лицом карточки
WIN_TITLE_MIN, WIN_TITLE_OUTLINE = 28, 0.13   # WinPanel.TITLE_MIN_SIZE, HudHeader.TITLE_OUTLINE
LINE_K = 1.364                     # высота строки Nunito / размер шрифта (ascent + descent)
WIN_CELL_MIN = 50.0                # клетка поля 7×8 на победе не мельче (на 9:16 — 59)
# Звёзды на кромке (WinPanel.STAR_CENTERS / STAR_R / STAR_FIT / STAR_CY): верх средней — над лицом.
STAR_CENTERS = [(128.0, -8.0), (256.0, -26.0), (384.0, -8.0)]
STAR_R = [54.0, 73.0, 54.0]
STAR_FIT, STAR_CY = 240.0 / 256.0, 0.54
# Надписи карточки: (шрифт, размер, ширина места, обводка с каждой стороны).
HEAD_W, HEAD_SIZE, HEAD_OUTLINE = 488.0, 34, 9         # %Head: 12…500
TOTAL_W, TOTAL_SIZE = 480.0, 27                        # %TotalLabel: 16…496, CardText 27
SCORE_SIZE_WIN, SCORE_OUTLINE, SCORE_STAR, SCORE_GAP = 48, 11, 54.0, 12.0
NEXT_W, NEXT_SIZE, NEXT_PAD = 380.0, 46, 40.0          # %NextButton 380×110, PillButton 46; поля у краёв
LINK_W, LINK_SIZE, LINK_ICON, LINK_SEP = 420.0, 26, 34.0, 10.0  # %ReplayButton, CardLink
# Всплывающее сообщение (13.5d): GameLayout.TOAST / TOAST_BOTTOM_*, поля капсулы (тема, StyleBoxFlat «toast»),
# ToastText (Nunito 800 30, line_spacing 2), тень капсулы вниз (shadow_offset 8 + shadow_size 16).
TOAST = (640.0, 124.0)
TOAST_BOTTOM = {False: 414.0, True: 66.0}
TOAST_PAD_X, TOAST_PAD_Y, TOAST_SIZE, TOAST_SPACING, TOAST_SHADOW = 32.0, 18.0, 30, 2, 24.0
TOAST_NO_LINE_START = ("—", "–")
TOAST_SENTENCE_END = ".!?…"
TOAST_MAX_LINES = 3
# Все тексты сообщений (toast.show_text в коде; у обучения — причина тупика TutorialCoach.reason_text).
TOAST_TEXTS = [
    "Тупик: так поле не заполнить. Отмени ход", "Нет ходов! Отмени ошибку", "Всё ещё тупик — отмени ещё ход",
    "Сначала отмени ошибочный ход", "Подсказка откроется после просмотра рекламы",
    "Подсказка: убраны неверные блоки (%d)", "Так остальные блоки не поместятся",
]
ROOT = pathlib.Path(__file__).resolve().parent.parent


def R(x, y, w, h):
    return (float(x), float(y), float(w), float(h))


def pick(w, h, was):
    if w <= 0 or h <= 0:
        return was
    return w / h >= (TO_PORTRAIT if was else TO_LANDSCAPE)


def portrait(w, h):
    x = (w - COLUMN) * 0.5
    return {
        "landscape": False,
        "top_bar": R(x + 24, 28, 672, 108),
        "board": R(x + 22, 160, 676, h - 564),
        "actions": R(x + 28, h - 390, 664, 100),
        "remaining": R(x + 138, h - 390, 444, 100),
        "tray": R(x + 24, h - 268, 672, 232),
        "shelf": R(x + 12, h - 280, 696, 256),
        "toast": R(x + (COLUMN - TOAST[0]) / 2, h - TOAST_BOTTOM[False] - TOAST[1], *TOAST),
        "slot": (216.0, 232.0), "separation": 12, "shelf_pad": SHELF_PAD[False], "vertical": False,
        "title_size": TITLE_SIZE[False], "score_size": SCORE_SIZE, "title_y": TITLE_Y[False],
        "score_y": SCORE_Y[False], "remaining_size": REMAINING_SIZE[False],
        "win_title": R(x + 20, WIN_TITLE_Y - 44, 680, 88), "win_title_size": WIN_TITLE_SIZE[False],
        "win_board": R(x + 40, WIN_BOARD_TOP, 640, max(200.0, h - WIN_CARD_BOTTOM - WIN_STARS - WIN_BOARD_TOP)),
        "win_board_scale": WIN_BOARD_SCALE[False],
        "win_card": R(x + (COLUMN - WIN_CARD[0]) / 2, h - WIN_CARD_BOTTOM, *WIN_CARD),
    }


def landscape(w, h):
    s = min(BOARD_MAX, w - 2 * MARGIN - SIDE_GAP - SIDE_W, h - (HEIGHT - BOARD_MAX))
    left = (w - (s + SIDE_GAP + SIDE_W)) * 0.5
    board = R(left, (h - s) * 0.5, s, s)
    x = left + s + SIDE_GAP
    y = (h - HEIGHT) * 0.5
    return {
        "landscape": True,
        "top_bar": R(x, y + 48, SIDE_W, 100),
        "board": board,
        "remaining": R(x, y + 204, SIDE_W, 44),  # 44: строка Nunito 29 — 41 px (14.8e)
        "tray": R(x + 14, y + 276, 532, 792),
        "shelf": R(x, y + 262, SIDE_W, 820),
        "actions": R(x + 118, y + 1116, 324, 96),
        "toast": R(board[0] + (s - TOAST[0]) / 2, board[1] + s - TOAST_BOTTOM[True] - TOAST[1], *TOAST),
        "slot": (532.0, 256.0), "separation": 12, "shelf_pad": SHELF_PAD[True], "vertical": True,
        "title_size": TITLE_SIZE[True], "score_size": SCORE_SIZE, "title_y": TITLE_Y[True],
        "score_y": SCORE_Y[True], "remaining_size": REMAINING_SIZE[True],
        "win_title": R(x, y + 240, SIDE_W, 180), "win_title_size": WIN_TITLE_SIZE[True],
        "win_board": board, "win_board_scale": WIN_BOARD_SCALE[True],
        "win_card": R(x + (SIDE_W - WIN_CARD[0]) / 2, y + 560, *WIN_CARD),
    }


def compute(w, h, land):
    return landscape(w, h) if land else portrait(w, h)


def overlap(a, b):
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def slots(L):
    tx, ty, tw, th = L["tray"]
    sw, sh = L["slot"]
    sep = L["separation"]
    out = []
    if L["vertical"]:
        y0 = ty + (th - (3 * sh + 2 * sep)) / 2
        for i in range(3):
            out.append(R(tx + (tw - sw) / 2, y0 + i * (sh + sep), sw, sh))
    else:
        x0 = tx + (tw - (3 * sw + 2 * sep)) / 2
        for i in range(3):
            out.append(R(x0 + i * (sw + sep), ty + (th - sh) / 2, sw, sh))
    return out


def board_fit(L, cols, rows, top=0.0, win=False):
    """Как Board.fit_in: прямоугольник рамки поля и размер клетки (win — на победе, в win_board)."""
    bx, by, bw, bh = L["win_board" if win else "board"]
    bh -= top
    add = (2 * PAD, 2 * PAD + FRAME_DEPTH)  # рамка в px, масштабируются только клетки
    top_scale = L["win_board_scale"] if win else BOARD_SCALE[L["landscape"]]
    s = min((bw - add[0]) / (cols * CELL), (bh - add[1]) / (rows * CELL), top_scale)
    fw, fh = cols * CELL * s + add[0], rows * CELL * s + add[1]
    return R(bx + (bw - fw) / 2, by + top + (bh - fh) / 2, fw, fh), CELL * s


SCREENS = [  # (подпись, ширина, высота) — логические px
    ("телефон 9:16", 720, 1280), ("телефон 9:19.5", 720, 1560), ("телефон 9:21", 720, 1680),
    ("планшет 3:4", 960, 1280), ("окно 1:1", 1280, 1280), ("окно 1.09", 1395, 1280),
    ("порог 1.10", 1408, 1280), ("порог 1.15", 1472, 1280), ("5:4", 1600, 1280),
    ("4:3", 1707, 1280), ("16:10", 2048, 1280), ("16:9", 2276, 1280), ("21:9", 2987, 1280),
    ("32:9", 4551, 1280),
]

problems = []


def check(cond, msg):
    if not cond:
        problems.append(msg)


def check_screen(name, w, h, land):
    L = compute(w, h, land)
    tag = "%s %dx%d %s" % (name, w, h, "альбом" if land else "портрет")
    keys = ["top_bar", "board", "remaining", "actions", "shelf"]
    for k in keys + ["tray", "toast"]:
        x, y, rw, rh = L[k]
        check(x >= EDGE - 1e-6 and y >= EDGE - 1e-6 and x + rw <= w - EDGE + 1e-6 and y + rh <= h - EDGE + 1e-6,
              "%s: %s %s вылезает за экран" % (tag, k, L[k]))
    for i, a in enumerate(keys):
        for b in keys[i + 1:]:
            if {a, b} == {"remaining", "actions"} and not land:
                continue  # в портрете подпись стоит между кнопками внутри полосы ActionsBar
            check(not overlap(L[a], L[b]), "%s: %s и %s перекрываются" % (tag, a, b))
    if not land:  # подпись между кнопками: не задевает «Отмену» и «Подсказку» (по 96)
        ax, ay, aw, ah = L["actions"]
        rx, ry, rw, rh = L["remaining"]
        check(rx >= ax + 96 and rx + rw <= ax + aw - 96, "%s: «Осталось блоков» на кнопках" % tag)
    tray = L["tray"]
    pad = L["shelf_pad"]
    want = R(tray[0] - pad, tray[1] - pad, tray[2] + 2 * pad, tray[3] + 2 * pad)
    check(all(abs(a - b) < 1e-6 for a, b in zip(want, L["shelf"])),
          "%s: полка %s, а лоток + отступ %s" % (tag, L["shelf"], want))
    sl = slots(L)
    gaps = [sl[0][0] - tray[0], sl[0][1] - tray[1]]
    check(all(abs(g) < 1e-6 for g in gaps), "%s: гнёзда не от края лотка (%s): у полки разные отступы" % (tag, gaps))
    for sr in sl:
        check(sr[0] >= tray[0] - 1e-6 and sr[1] >= tray[1] - 1e-6 and sr[0] + sr[2] <= tray[0] + tray[2] + 1e-6
              and sr[1] + sr[3] <= tray[1] + tray[3] + 1e-6, "%s: гнездо %s не в лотке %s" % (tag, sr, tray))
    if land:
        s = L["board"][2]
        check(abs(L["board"][2] - L["board"][3]) < 1e-6, "%s: поле не квадрат" % tag)
        check(s >= 676, "%s: поле %.0f меньше портретного 676" % (tag, s))
        group_l = L["board"][0]
        group_r = L["tray"][0] - 14 + SIDE_W
        check(abs((group_l - 0) - (w - group_r)) < 1e-6, "%s: группа не по центру" % tag)
        if name == "16:9":
            share = (group_r - group_l) / w
            check(share >= 0.70, "%s: группа занимает %.0f %% ширины (< 70)" % (tag, share * 100))
    check_header(tag, L, w, h)
    check_win(tag, L, w, h)
    check_toast(tag, L)
    return L


def texts(msgid):
    """Строка интерфейса на всех языках: русский исходник и переводы из locale/*.po."""
    out = [msgid]
    for po in sorted((ROOT / "locale").glob("*.po")):
        t = po.read_text(encoding="utf-8")
        i = t.find('msgid "%s"' % msgid)
        if i >= 0:
            j = t.find('msgstr "', i) + len('msgstr "')
            out.append(t[j:t.find('"', j)])
    return out


def lab_heads():
    """Шапки уровней «Лаборатории» с «10/10»: короткие названия LabLevels.HEADS (scripts/lab_levels.gd)."""
    src = (ROOT / "scripts/lab_levels.gd").read_text(encoding="utf-8")
    block = re.search(r"const HEADS := \{(.*?)\}", src, re.S)
    heads = re.findall(r'"\w+": "([^"]+)"', block.group(1)) if block else []
    check(len(heads) == 4, "LabLevels.HEADS: прочитано %d названий (ждали 4)" % len(heads))
    return [h + " · 10/10" for h in heads]


def check_header(tag, L, w, h):
    """Шапка и плашка (13.2c, STYLE 13): строки на местах эталона, заголовок «УРОВЕНЬ 300» на любом
    языке влезает в середину шапки не мельче TITLE_MIN_SIZE, плашка «Осталось блоков: 12» —
    между кнопками (портрет) или в столбике (альбом)."""
    try:
        from PIL import ImageFont
    except ImportError:
        return
    land = L["landscape"]
    bx, by, bw, bh = L["top_bar"]
    cx = bx + bw / 2
    if land:
        x0 = bx
        want_t, want_s, want_r = (x0 + 280, (h - HEIGHT) / 2 + 78), (x0 + 280, (h - HEIGHT) / 2 + 138), (x0 + 280, (h - HEIGHT) / 2 + 226)
    else:
        want_t, want_s, want_r = (w / 2, 62.0), (w / 2, 116.0), (w / 2, h - 342.0)
    got_t, got_s = (cx, by + L["title_y"]), (cx, by + L["score_y"])
    rx, ry, rw, rh = L["remaining"]
    got_r = (rx + rw / 2, ry + rh / 2 + PILL_TEXT_RISE)
    for nm, a, b in (("заголовок", got_t, want_t), ("счёт", got_s, want_s), ("плашка", got_r, want_r)):
        check(abs(a[0] - b[0]) < 0.5 and abs(a[1] - b[1]) <= 3.0, "%s: %s в %s, по STYLE 13 — %s" % (tag, nm, a, b))
    nunito = ImageFont.truetype(str(ROOT / "assets/fonts/nunito_black.ttf"), L["title_size"])
    room = bw - 2 * (BUTTON + BAR_SEP)
    for t in texts("УРОВЕНЬ %d"):
        s = t.replace("%d", "300")
        tw = nunito.getlength(s)
        fs = L["title_size"] if tw <= room - 2 * TITLE_OUTLINE * L["title_size"] else \
            int(L["title_size"] * (room - 2 * TITLE_OUTLINE * L["title_size"]) / tw)
        check(fs >= TITLE_MIN_SIZE, "%s: «%s» ужат до %d" % (tag, s, fs))
        check(fs >= L["title_size"] - 4, "%s: «%s» ужат до %d (заметно мельче %d)" % (tag, s, fs, L["title_size"]))
    for s in texts("ЗАДАЧА ДНЯ"):    # 18.1f: заголовок шапки в задаче дня (HudHeader ужимает до TITLE_MIN_SIZE)
        tw = nunito.getlength(s)
        fs = L["title_size"] if tw <= room - 2 * TITLE_OUTLINE * L["title_size"] else \
            int(L["title_size"] * (room - 2 * TITLE_OUTLINE * L["title_size"]) / tw)
        check(fs > TITLE_MIN_SIZE, "%s: «%s» ужат до %d" % (tag, s, fs))
        if s == "ЗАДАЧА ДНЯ":
            check(fs >= L["title_size"] - 4, "%s: «%s» ужат до %d (заметно мельче %d)" % (tag, s, fs, L["title_size"]))
    for s in lab_heads():    # 19.3c: шапка уровня «Лаборатории» (LabLevels.header, без перевода) — не до предела
        tw = nunito.getlength(s)
        fs = L["title_size"] if tw <= room - 2 * TITLE_OUTLINE * L["title_size"] else \
            int(L["title_size"] * (room - 2 * TITLE_OUTLINE * L["title_size"]) / tw)
        check(fs > TITLE_MIN_SIZE, "%s: «%s» ужат до %d" % (tag, s, fs))
    font = ImageFont.truetype(str(ROOT / "assets/fonts/nunito_extrabold.ttf"), L["remaining_size"])
    for t in texts("Осталось блоков: %d"):
        s = t.replace("%d", "12")
        pw = font.getlength(s) + 2 * PILL_PAD_X
        ph = round(L["remaining_size"] * PILL_HEIGHT_K)
        check(pw <= rw, "%s: плашка «%s» %.0f шире места %.0f" % (tag, s, pw, rw))
        if not land:
            ax, ay, aw, ah = L["actions"]
            check(rx + (rw - pw) / 2 >= ax + BUTTON + 8 and ry + (rh - ph) / 2 >= ay, "%s: плашка «%s» задевает кнопки" % (tag, s))
        else:
            sh = L["shelf"]
            check(ry + rh / 2 + PILL_TEXT_RISE + ph / 2 <= sh[1] - 4, "%s: плашка «%s» налезает на полку" % (tag, s))


def inside(a, b, eps=1e-6):
    return a[0] >= b[0] - eps and a[1] >= b[1] - eps and a[0] + a[2] <= b[0] + b[2] + eps \
        and a[1] + a[3] <= b[1] + b[3] + eps


def star_box(card, i):
    """Квадрат TextureRect звезды i на кромке карточки (WinPanel._place_card_content), без наклона."""
    box = 1.75 * STAR_R[i] / STAR_FIT
    cx, cy = STAR_CENTERS[i]
    return R(card[0] + cx - box / 2, card[1] + cy - box * STAR_CY, box, box)


def check_win(tag, L, w, h):
    """Победа (13.5b, STYLE 11) — те же правила, что selftest `_win_layout_problems`, и надписи окна."""
    screen = R(EDGE, EDGE, w - 2 * EDGE, h - 2 * EDGE)
    title, wb, card = L["win_title"], L["win_board"], L["win_card"]
    stars = R(card[0], card[1] - WIN_STARS, card[2], WIN_STARS)
    with_lip = R(card[0], card[1], card[2], card[3] + CARD_LIP)
    for nm, r in (("win_title", title), ("win_board", wb), ("win_card + губа", with_lip)):
        check(inside(r, screen), "%s: %s %s вылезает за экран" % (tag, nm, r))
    check(abs(card[2] - WIN_CARD[0]) < 1e-6 and abs(card[3] - WIN_CARD[1]) < 1e-6, "%s: карточка победы %s" % (tag, card))
    # Звёзды (их квадраты) — в зоне WIN_STARS над карточкой и не шире её.
    for i in range(3):
        sb = star_box(card, i)
        reach = R(card[0], card[1] - WIN_STARS, card[2], WIN_STARS + card[3])
        check(inside(sb, reach), "%s: звезда %d %s выходит из зоны над карточкой" % (tag, i + 1, sb))
    check(not overlap(wb, stars), "%s: поле победы %s заходит на звёзды карточки" % (tag, wb))
    check(not overlap(title, stars) and not overlap(title, card), "%s: заголовок победы %s заходит на карточку" % (tag, title))
    if L["landscape"]:
        check(all(abs(a - b) < 1e-6 for a, b in zip(wb, L["board"])), "%s: в альбоме поле на победе сдвинулось" % tag)
        col = wb[0] + wb[2] + SIDE_GAP - 1e-6
        check(title[0] >= col and card[0] >= col, "%s: заголовок или карточка победы не в столбике" % tag)
    else:
        check(title[1] + title[3] / 2 + L["win_title_size"] / 2 <= wb[1] + 1e-6,
              "%s: строка заголовка победы заходит на поле %s" % (tag, wb))
        check(wb[3] >= 400, "%s: поле победы низкое (%.0f)" % (tag, wb[3]))
    # Поле на победе: рамка внутри win_board, клетка 7×8 не мельче WIN_CELL_MIN.
    frame, cell = board_fit(L, 7, 8, win=True)
    check(inside(frame, wb, 0.5), "%s: рамка поля %s вылезла из win_board" % (tag, frame))
    check(cell >= WIN_CELL_MIN, "%s: клетка 7×8 на победе %.0f (< %.0f)" % (tag, cell, WIN_CELL_MIN))
    check_win_texts(tag, L)


def wrap_words(text, font, room, max_lines):
    """WinPanel.wrap_words: жадно по словам, строк не больше max_lines (остаток — в последнюю)."""
    out, cur = [], ""
    for word in text.split():
        probe = word if not cur else cur + " " + word
        if not cur or len(out) >= max_lines - 1 or font.getlength(probe) <= room:
            cur = probe
        else:
            out.append(cur)
            cur = word
    out.append(cur)
    return out


_fonts = {}


def font(name, size):
    from PIL import ImageFont
    key = (name, size)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(str(ROOT / "assets/fonts" / name), size)
    return _fonts[key]


SEP = {0: "\u00a0", 1: ",", 2: "."}  # разряды: ru (неразрывный пробел), en, tr (HudHeader.format_score)


def fmt(n, lang):
    s = "{:,}".format(n)
    return s.replace(",", SEP[lang])


def check_win_texts(tag, L):
    """Надписи окна победы на ru / en / tr: заголовок (WinPanel._layout_title — ужатие до WIN_TITLE_MIN),
    шапка карточки, «+очки» со звездой, «Всего очков» с приростом, «ДАЛЕЕ», ссылка «Переиграть уровень»."""
    try:
        import PIL  # noqa: F401
    except ImportError:
        return
    title = L["win_title"]
    lines_max = 2 if L["landscape"] else 1
    for t in texts("УРОВЕНЬ %d ПРОЙДЕН!"):
        s = t.replace("%d", "300")
        fs = L["win_title_size"]
        while True:
            f = font("nunito_black.ttf", fs)
            room = title[2] - 2 * WIN_TITLE_OUTLINE * fs
            lines = wrap_words(s, f, room, lines_max)
            if all(f.getlength(x) <= room for x in lines) or fs <= WIN_TITLE_MIN:
                break
            fs -= 2
        ok = all(font("nunito_black.ttf", fs).getlength(x) <= title[2] - 2 * WIN_TITLE_OUTLINE * fs for x in lines)
        check(ok, "%s: «%s» не влезает в заголовок победы даже при %d" % (tag, s, fs))
        check(fs >= L["win_title_size"] - 8, "%s: «%s» ужат до %d (заметно мельче %d)" % (tag, s, fs, L["win_title_size"]))
        check(len(lines) * LINE_K * fs <= title[3] + 1, "%s: «%s» в %d строки выше места %.0f" % (tag, s, len(lines), title[3]))
    if L["landscape"] or tag.startswith("телефон 9:16"):  # надписи карточки не зависят от экрана — один раз на режим
        heads = [x for m in ("ХОРОШО!", "ОТЛИЧНО!", "ИДЕАЛЬНО!", "НОВЫЙ РЕКОРД!") for x in texts(m)]
        for s in heads:
            tw = font("nunito_black.ttf", HEAD_SIZE).getlength(s) + 2 * HEAD_OUTLINE
            check(tw <= HEAD_W, "%s: шапка карточки «%s» %.0f шире %.0f" % (tag, s, tw, HEAD_W))
        for lang, (t1, t2, t3) in enumerate(zip(texts("Всего очков: %s"), texts("Всего очков: %s (+%s)"),
                                                 texts("Рекорд уровня: %s"))):
            for s in (t1 % fmt(999999, lang), t2 % (fmt(999999, lang), fmt(9999, lang)), t3 % fmt(9999, lang)):
                tw = font("nunito_extrabold.ttf", TOTAL_SIZE).getlength(s)
                check(tw <= TOTAL_W, "%s: «%s» %.0f шире %.0f (обрежется «…»)" % (tag, s, tw, TOTAL_W))
            s = "+" + fmt(9999, lang)
            tw = SCORE_STAR + SCORE_GAP + font("nunito_black.ttf", SCORE_SIZE_WIN).getlength(s) + 2 * SCORE_OUTLINE
            check(tw <= WIN_CARD[0] - 2 * 40, "%s: строка очков «%s» %.0f шире карточки без полей" % (tag, s, tw))
        for s in texts("ДАЛЕЕ"):
            tw = font("nunito_black.ttf", NEXT_SIZE).getlength(s) + 2 * round(2 * 0.12 * NEXT_SIZE)
            check(tw <= NEXT_W - 2 * NEXT_PAD, "%s: «%s» на кнопке %.0f шире %.0f" % (tag, s, tw, NEXT_W - 2 * NEXT_PAD))
        for s in texts("Переиграть уровень"):
            tw = LINK_ICON + LINK_SEP + font("nunito_extrabold.ttf", LINK_SIZE).getlength(s)
            check(tw <= LINK_W, "%s: ссылка «%s» %.0f шире %.0f" % (tag, s, tw, LINK_W))


def toast_lines(text, f, room):
    """Toast.balance_lines: одна строка, если влезает; иначе две — по концу предложения, если можно, и как
    можно ровнее (вторая не с тире); иначе жадно."""
    if f.getlength(text) <= room:
        return [text]
    words = text.split()
    best, best_w, best_sentence = None, float("inf"), False
    for i in range(1, len(words)):
        if words[i] in TOAST_NO_LINE_START:
            continue
        a, b = " ".join(words[:i]), " ".join(words[i:])
        w = max(f.getlength(a), f.getlength(b))
        sentence = a[-1] in TOAST_SENTENCE_END
        if w > room or (best_sentence and not sentence):
            continue
        if w < best_w or (sentence and not best_sentence):
            best, best_w, best_sentence = [a, b], w, sentence
    if best:
        return best
    out, cur = [], ""
    for word in words:
        probe = word if not cur else cur + " " + word
        if not cur or len(out) >= TOAST_MAX_LINES - 1 or f.getlength(probe) <= room:
            cur = probe
        else:
            out.append(cur)
            cur = word
    out.append(cur)
    return out


def toast_code_texts():
    """Тексты toast.show_text(tr("…")) в коде — все должны быть в TOAST_TEXTS."""
    import re
    found = set()
    for p in sorted((ROOT / "scenes").rglob("*.gd")) + sorted((ROOT / "scripts").rglob("*.gd")):
        found |= set(re.findall(r'toast\.show_text\(tr\("([^"]+)"\)', p.read_text(encoding="utf-8")))
    return found


def check_toast(tag, L):
    """Сообщение (13.5d): место — по центру столбика над кнопками (портрет; тень не задевает кнопки) или над
    низом поля (альбом); каждый текст на ru / en / tr — не больше двух строк, капсула не выше места."""
    t = L["toast"]
    if L["landscape"]:
        check(inside(t, L["board"]), "%s: место сообщения %s не над полем" % (tag, t))
    else:
        check(t[1] + t[3] + TOAST_SHADOW <= L["actions"][1] + 1e-6, "%s: тень сообщения задевает кнопки" % tag)
        check(abs(t[0] + t[2] / 2 - (L["actions"][0] + L["actions"][2] / 2)) < 1e-6, "%s: сообщение не по центру" % tag)
    if not (L["landscape"] or tag.startswith("телефон 9:16")):
        return  # тексты от экрана не зависят — один раз на режим
    try:
        import PIL  # noqa: F401
    except ImportError:
        return
    f = font("nunito_extrabold.ttf", TOAST_SIZE)
    room = t[2] - 2 * TOAST_PAD_X
    for m in sorted(toast_code_texts() - set(TOAST_TEXTS)):
        check(False, "%s: сообщения «%s» нет в TOAST_TEXTS (layout_model.py)" % (tag, m))
    for m in TOAST_TEXTS:
        for x in texts(m):
            x = x.replace("%d", "12")
            lines = toast_lines(x, f, room * 0.98)  # запас 2 % на разницу PIL и Godot
            w = max(f.getlength(y) for y in lines)
            h = len(lines) * LINE_K * TOAST_SIZE + (len(lines) - 1) * TOAST_SPACING + 2 * TOAST_PAD_Y
            check(len(lines) <= 2, "%s: сообщение «%s» в %d строки" % (tag, x, len(lines)))
            check(w <= room, "%s: строка сообщения «%s» %.0f шире %.0f" % (tag, x, w, room))
            check(h <= t[3] + 0.5, "%s: капсула «%s» %.0f выше места %.0f" % (tag, x, h, t[3]))


def check_hysteresis():
    was = False
    seq = []
    for w in [1400, 1450, 1471, 1472, 1440, 1409, 1408, 1407, 1450, 1472]:
        was = pick(w, 1280, was)
        seq.append(was)
    want = [False, False, False, True, True, True, True, False, False, True]
    check(seq == want, "гистерезис: %s, ждали %s" % (seq, want))


def render(dirpath, items):
    from PIL import Image, ImageDraw, ImageFont
    font_path = pathlib.Path(__file__).resolve().parent.parent / "docs/fonts/cand/Nunito-ExtraBold.ttf"
    font = ImageFont.truetype(str(font_path), 15) if font_path.exists() else ImageFont.load_default()
    dirpath = pathlib.Path(dirpath)
    dirpath.mkdir(parents=True, exist_ok=True)
    colors = {"top_bar": "#FFE45C", "board": "#B8A5F6", "remaining": "#FFFFFF", "actions": "#2FCF78",
              "tray": "#34168F", "shelf": "#7A5EE0", "toast": "#FF4D6D"}
    names = {"top_bar": "TopBar", "board": "BoardArea", "remaining": "Осталось", "actions": "Actions",
             "tray": "Tray", "shelf": "", "toast": "Toast"}
    for fname, item in items.items():
        label, w, h, land, cols, rows = item[:6]
        win = len(item) > 6 and item[6]
        L = compute(w, h, land)
        k = 0.4
        im = Image.new("RGB", (int(w * k), int(h * k)), "#5A3CE2")
        d = ImageDraw.Draw(im)

        def box(r, outline, width=2, fill=None):
            x, y, rw, rh = r
            d.rectangle([x * k, y * k, (x + rw) * k, (y + rh) * k], outline=outline, width=width, fill=fill)

        frame, cell = board_fit(L, cols, rows, win=win)
        box(frame, "#FFFFFF", 2, "#EDE6FF")
        fx, fy = frame[0] + PAD, frame[1] + PAD
        for yy in range(rows):
            for xx in range(cols):
                box(R(fx + xx * cell + 3, fy + yy * cell + 3, cell - 6, cell - 6), "#C6B6F9", 1, "#DDD3FD")
        if win:  # победа: заголовок, поле, карточка с губой и звёзды на кромке (13.5b)
            card = L["win_card"]
            for key, r, col, nm in (("win_title", L["win_title"], "#FFE45C", "WinTitle"),
                                    ("win_board", L["win_board"], "#B8A5F6", "win_board"),
                                    ("stars", R(card[0], card[1] - WIN_STARS, card[2], WIN_STARS), "#FFC247", "звёзды"),
                                    ("win_card", R(card[0], card[1], card[2], card[3] + CARD_LIP), "#FF7B3A", "Card")):
                box(r, col, 3)
                d.text((r[0] * k + 6, r[1] * k + 2), nm, fill=col, font=font)
            for i in range(3):
                sx, sy, sw, sh = star_box(card, i)
                c = (sx + sw / 2, sy + sh * STAR_CY)
                rr = STAR_R[i]
                d.ellipse([(c[0] - rr) * k, (c[1] - rr) * k, (c[0] + rr) * k, (c[1] + rr) * k], outline="#FFE45C", width=2)
            d.text((8, im.height - 22), "%s, победа: клетка %dx%d %.0f" % (
                label, cols, rows, cell), fill="#FFFFFF", font=font)
            im.save(dirpath / fname)
            print("  схема", dirpath / fname)
            continue
        for key in ["top_bar", "board", "remaining", "actions", "shelf", "tray", "toast"]:
            r = L.get(key)
            if r:
                box(r, colors[key], 3)
                d.text((r[0] * k + 6, r[1] * k + 2), names[key], fill=colors[key], font=font)
        for sr in slots(L):
            box(sr, "#9A4CDB", 2, "#3B1FA0")
        ts = TRAY_SCALE[land]
        d.text((8, im.height - 22), "%s  %dx%d  поле %dx%d: клетка %.0f, в лотке %.0f" % (
            label, w, h, cols, rows, cell, CELL * ts), fill="#FFFFFF", font=font)
        im.save(dirpath / fname)
        print("  схема", dirpath / fname)


def main():
    for name, w, h in SCREENS:
        land = pick(w, h, False)
        check_screen(name, w, h, land)
        if TO_PORTRAIT <= w / h < TO_LANDSCAPE:
            check_screen(name, w, h, True)  # в полосе гистерезиса бывает и альбом
    check_hysteresis()
    for name, w, h in SCREENS:
        land = pick(w, h, False)
        L = compute(w, h, land)
        _, cell = board_fit(L, 7, 8)
        _, cell6 = board_fit(L, 6, 6)
        _, cellw = board_fit(L, 7, 8, win=True)
        print("  %-15s %4dx%-4d %-7s поле %4.0f  клетка 7x8: %3.0f, 6x6: %3.0f, на победе 7x8: %3.0f" % (
            name, w, h, "альбом" if land else "портрет", L["board"][2], cell, cell6, cellw))
    if "--png" in sys.argv:
        out = sys.argv[sys.argv.index("--png") + 1]
        render(out, {
            "portrait_9x16.png": ("телефон 9:16", 720, 1280, False, 7, 8),
            "portrait_9x19.png": ("телефон 9:19.5", 720, 1560, False, 7, 8),
            "landscape_16x9.png": ("16:9", 2276, 1280, True, 7, 8),
            "landscape_5x4.png": ("5:4", 1600, 1280, True, 7, 8),
            "landscape_21x9.png": ("21:9", 2987, 1280, True, 6, 6),
            "landscape_min.png": ("порог 1.10", 1408, 1280, True, 4, 4),
            "win_portrait_9x16.png": ("телефон 9:16", 720, 1280, False, 7, 8, True),
            "win_portrait_9x19.png": ("телефон 9:19.5", 720, 1560, False, 7, 8, True),
            "win_landscape_16x9.png": ("16:9", 2276, 1280, True, 7, 8, True),
            "win_landscape_min.png": ("порог 1.10", 1408, 1280, True, 6, 6, True),
        })
    if problems:
        print("ПРОБЛЕМЫ (%d):" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("раскладки: проблем не найдено")
    return 0


if __name__ == "__main__":
    sys.exit(main())
