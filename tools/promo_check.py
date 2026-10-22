#!/usr/bin/env python3
"""Проверка страницы игры: тексты docs/PROMO.md (этап 16.5a) и картинки docs/promo/ (16.5b).

  python3 tools/promo_check.py            проверить, напечатать длины полей
  python3 tools/promo_check.py --print    ещё и вывести тексты полей (для копирования)
  python3 tools/promo_check.py --need-shots   скриншоты обязательны (перед загрузкой в консоль)

Что проверяет:
  1. все поля на всех языках есть и не пусты (FIELDS — вкладка языка в консоли), общие поля COMMON (ключевые слова,
     комментарий разработчика — одни на все языки) есть; длина в пределах консоли (LIMITS, COMMON — по консоли
     11.10), перевод строки считается за два символа — на случай, если так считает счётчик консоли;
  2. запрещённое: ссылки, эмодзи, слова целиком капсом, названия других игр, призывы оценить, упоминание рекламы
     (в комментарии разработчика — только ссылки и эмодзи: его читают модераторы, про рекламу там нужно; в ключевых
     словах названия игр можно — подсказка консоли сама просит конкурентов и похожие игры, платформы — нельзя);
  3. языки согласованы: одни и те же числа в каждом поле, одинаковое число абзацев, пунктов и шагов; ключевые
     слова без повторов;
  4. факты сверены с кодом: число уровней (LevelPack), глав (Chapters.NAMES), наименьшее и наибольшее поле,
     механики глав — теми же словами, что в игре (переводы locale/*.po), термины игры (тупик, серия, главы…),
     правило трёх звёзд — как в game.gd; управление — в комментарии разработчика (клавиши и кнопки мыши есть в коде);
     «Как играть» — коротко (HOW_MAX) и для одного пальца / левой кнопки мыши: поворот — нажатием на блок, теми же
     словами, что в обучении (ROTATE_TAP), без клавиш, правой кнопки, колеса, второго пальца (HOW_EXTRA);
  5. название на обложке (tools/promo_art.py, TITLES; 1–3 строки) — те же слова и в том же порядке, что в поле
     «Название», прописными;
  6. картинки docs/promo/ (рисует tools/promo_art.py): иконка и обложки на каждый язык и без текста есть, PNG
     нужного размера (ICON, COVER) без прозрачности; не устарели — отпечаток docs/promo/SOURCES.txt совпадает:
     источники ART_SOURCES (логотип, блок, фон, шрифт, палитра, сам promo_art с TITLES) не менялись после
     рисования, картинки — те самые, что он нарисовал. Без Pillow: размер читается из заголовка PNG.
  7. скриншоты (снимает сцена tests/promo_shots.tscn в Godot): настройки витрины — языки те же, форматы: портрет
     для телефона и альбом строго 16:9 шириной SHOT_DESKTOP_W для компьютера, логический экран — как у окна игры
     (база project.godot, растяжение expand), раскладка не на пороге гистерезиса GameLayout; кадров не меньше
     SHOT_MIN, уровни в паке, разные главы, не первый уровень главы и не уровень с правилом механики, поле
     заполнено частично. Файлы docs/promo/shots/<формат>_<язык>_<N>.png: все на месте, PNG нужного размера без
     прозрачности, не почти однотонные (байт на пиксель ≥ SHOT_MIN_BPP — пустой кадр SubViewport ловится так),
     лишних нет. Скриншотов ещё нет совсем — не проблема, а строка «не сняты» (с --need-shots — проблема).
Выход 0 — проблем нет, 1 — есть (список выше).
"""
import ast
import hashlib
import os
import re
import struct
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
PROMO = os.path.join(ROOT, "docs", "PROMO.md")

LANGS = ["ru", "en", "tr"]
# Поля вкладки языка («Описание и продвижение») и пределы — как в консоли (черновик, скриншоты 11.10).
FIELDS = ["Название", "Описание для SEO", "Об игре", "Короткое описание", "Как играть"]
LIMITS = {"Название": 50, "Описание для SEO": 160, "Об игре": 1000, "Короткое описание": 70, "Как играть": 1000}
# Поля «Общего» — одни на все языки («### Поле» без языка в PROMO.md).
COMMON = {"Ключевые слова": 100, "Комментарий разработчика": 2048}

# Другие игры — нельзя в тексте страницы, можно в «Ключевых словах» (подсказка консоли: «основные конкуренты, известные
# игры в похожем стиле»). Платформы и магазины — нельзя нигде.
GAMES = ["block blast", "1010", "tetris", "тетрис", "candy crush", "sudoku", "судоку", "nonogram", "японский кроссворд",
         "woodoku", "blockudoku"]
PLATFORMS = ["google play", "app store", "android", "ios"]
CALLS = ["оцени", "поставь", "лайк", "rate us", "rate the", "like us", "puan ver", "beğen", "реклам", "advert",
         " ads", "reklam", "бесплатн", "free", "ücretsiz"]
# Термины игры: (язык, слово в тексте, msgid, где искать в переводе). В тексте страницы — те же слова, что в игре.
TERMS = {
    "ru": [("тупик", "Тупик: так поле не заполнить. Отмени ход"), ("сери", "СЕРИЯ"), ("лидер", "ЛИДЕРЫ"),
           ("глав", "ГЛАВА %d"), ("ежедневная задача", "ЕЖЕДНЕВНАЯ ЗАДАЧА ПРОЙДЕНА!")],
    "en": [("dead end", "Тупик: так поле не заполнить. Отмени ход"), ("streak", "СЕРИЯ"), ("leader", "ЛИДЕРЫ"),
           ("chapter", "ГЛАВА %d"), ("daily puzzle", "ЕЖЕДНЕВНАЯ ЗАДАЧА ПРОЙДЕНА!")],
    "tr": [("çıkmaz", "Тупик: так поле не заполнить. Отмени ход"), ("seri", "СЕРИЯ"), ("lider", "ЛИДЕРЫ"),
           ("bölüm", "ГЛАВА %d"), ("günlük bulmaca", "ЕЖЕДНЕВНАЯ ЗАДАЧА ПРОЙДЕНА!")],
}
# Клавиши и кнопки мыши из «Комментария разработчика» (управление для модераторов) -> что должно быть в коде игры
# (scenes/, scripts/, autoload/). В «Как играть» их нет: игра целиком управляется одним пальцем / левой кнопкой мыши.
KEYS = {"R": r"KEY_R\b", "H": r"KEY_H\b", "Backspace": r"KEY_BACKSPACE\b", "Ctrl+Z": r"KEY_Z\b.*is_command_or_control",
        "Esc": r"KEY_ESCAPE\b|ui_cancel", "wheel": r"MOUSE_BUTTON_WHEEL_UP", "right": r"MOUSE_BUTTON_RIGHT"}
KEY_WORDS = {"wheel": {"ru": "колесо", "en": "wheel", "tr": "tekerle"},
             "right": {"ru": "правая кнопка", "en": "right mouse button", "tr": "sağ tuş"}}
# «Как играть» (правка пользователя 11.10): игроки много не читают, а всё управление — нажать и перетащить.
HOW_MAX = 500   # символов (переводы строк — за два); предел консоли — 1000, но длинный текст не прочтут
# Поворот — нажатием на блок, той же фразой, что в обучении игры: (фраза в тексте, msgid обучения).
ROTATE_TAP = {"ru": ("нажми на блок", "Нажми на блок, чтобы повернуть его"),
              "en": ("tap a block", "Нажми на блок, чтобы повернуть его"),
              "tr": ("bloğa dokun", "Нажми на блок, чтобы повернуть его")}
# Лишнее для игрока: клавиши (KEYS), правая кнопка, колесо, второй палец, отдельное управление на компьютере.
HOW_EXTRA = {"ru": ["правая кнопк", "правой кнопк", "колес", "пальц", "палец", "клавиш", "мыш", "компьютер", "лотк"],
             "en": ["right mouse", "right-click", "right click", "wheel", "finger", "key", "mouse", "computer", "tray"],
             "tr": ["sağ tuş", "teker", "parmak", "tuş", "fare", "bilgisayar", "tepsi"]}
STAR_RULE = {"ru": "без отмен и подсказок", "en": "without undos or hints", "tr": "geri almadan ve ipucusuz"}

# Скриншоты (п. 7): сцена-витрина и требования консоли (docs/DESKTOP.md, раздел 1; PROMO.md «Картинки»).
SHOTS_GD = "tests/promo_shots.gd"
SHOT_MIN = 2                    # кадров на платформу, не меньше
SHOT_DESKTOP_W = (1280, 2560)   # ширина кадра для компьютера (только 16:9)
SHOT_MIN_BPP = 0.02             # байт PNG на пиксель: однотонный 1920×1080 — ≈0,005, настоящий кадр игры — в разы больше

problems = []


def bad(msg: str) -> None:
    problems.append(msg)


def low(lang: str, s: str) -> str:
    if lang == "tr":
        s = s.replace("İ", "i").replace("I", "ı")
    return s.lower()


def read(rel: str) -> str:
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        return fh.read()


def parse_promo(text: str) -> dict:
    """{(язык, поле): текст} из заголовков «### ru · Поле» и блока ```text под каждым."""
    out = {}
    pat = re.compile(r"^### (\w\w) · ([^\n]+)\n```text\n(.*?)\n```\s*$", re.M | re.S)
    for m in pat.finditer(text):
        key = (m.group(1), m.group(2).strip())
        if key in out:
            bad(f"поле {key[0]} · {key[1]} встречается дважды")
        out[key] = m.group(3).strip("\n")
    return out


def parse_common(text: str) -> dict:
    """{поле: текст} из заголовков «### Поле» (без языка) с блоком ```text под ним."""
    out = {}
    pat = re.compile(r"^### ([^\n·]+?)\n```text\n(.*?)\n```\s*$", re.M | re.S)
    for m in pat.finditer(text):
        key = m.group(1).strip()
        if key in out:
            bad(f"общее поле {key} встречается дважды")
        out[key] = m.group(2).strip("\n")
    return out


def counted(s: str) -> int:
    """Длина для пределов консоли: перевод строки — за два символа (с запасом на счётчик консоли)."""
    return len(s) + s.count("\n")


def po(lang: str) -> dict:
    """msgid -> msgstr из locale/<lang>.po (только однострочные записи — других в проекте нет)."""
    d, mid = {}, None
    for line in read(f"locale/{lang}.po").splitlines():
        if line.startswith("msgid "):
            mid = line[6:].strip().strip('"')
        elif line.startswith("msgstr ") and mid is not None:
            d[mid] = line[7:].strip().strip('"')
            mid = None
    return d


def game_facts() -> dict:
    pack = read("scripts/level_pack_data.gd")
    sizes = re.findall(r'^\t"(\d)(\d):', pack, re.M)
    chapters = read("scripts/chapters.gd")
    names = re.search(r"const NAMES: Array\[String\] = \[(.*?)\]", chapters, re.S).group(1)
    ideas = re.search(r"const IDEAS: Array\[String\] = \[(.*?)\n\]", chapters, re.S).group(1)
    mech = re.search(r"const MECHANICS: Array\[String\] = \[(.*?)\]", chapters).group(1)
    by_area = sorted(sizes, key=lambda cr: int(cr[0]) * int(cr[1]))
    mech_list = [m for m in re.findall(r'"(\w*)"', mech) if m]
    mech_ideas = [i for i in re.findall(r'"(Новое: [^"]+)"', ideas)]
    return {
        "levels": len(sizes),
        "chapters": len(re.findall(r'"[^"]+"', names)),
        "min": "%s×%s" % by_area[0], "max": "%s×%s" % by_area[-1],
        "mechanics": mech_list,
        # Идеи глав с механиками — последние len(mech_list) идей «Новое: …» (длинные блоки и блок 12 — не механики).
        "mech_ideas": mech_ideas[-len(mech_list):] if mech_list else [],
    }


def code_text() -> str:
    parts = []
    for top in ("scenes", "scripts", "autoload"):
        for d, _, files in os.walk(os.path.join(ROOT, top)):
            for f in files:
                if f.endswith(".gd"):
                    parts.append(open(os.path.join(d, f), encoding="utf-8").read())
    return "\n".join(parts)


def numbers(s: str) -> list:
    return sorted(set(re.findall(r"\d+(?:×\d+)?", s)))


def is_emoji(ch: str) -> bool:
    o = ord(ch)
    return o >= 0x1F000 or 0x2600 <= o <= 0x27BF or 0x2B00 <= o <= 0x2BFF or o == 0xFE0F


def art_consts() -> dict:
    """Константы-литералы tools/promo_art.py (ICON, COVER, TITLES, ART_SOURCES, SOURCES_TXT) — через ast, без импорта:
    promo_art тянет numpy и рисовалки, а проверке они не нужны."""
    out = {}
    for node in ast.parse(read("tools/promo_art.py")).body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            try:
                out[node.targets[0].id] = ast.literal_eval(node.value)
            except ValueError:
                pass
    return out


def sha1(path: str) -> str:
    """Как promo_art.sha1: текст — с переводами строк \\n."""
    with open(path, "rb") as fh:
        data = fh.read()
    if not path.endswith((".png", ".ttf")):
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha1(data).hexdigest()


def png_info(path: str):
    """(ширина, высота, есть прозрачность) из заголовка PNG; не PNG — None."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return None
    w, h = struct.unpack(">II", data[16:24])
    idat = data.find(b"IDAT")
    alpha = data[25] in (4, 6) or b"tRNS" in data[:idat if idat > 0 else len(data)]
    return w, h, alpha


def read_sources(path: str) -> tuple:
    """docs/promo/SOURCES.txt -> ({путь источника: sha1}, {картинка: sha1})."""
    src, img, cur = {}, {}, None
    with open(path, encoding="utf-8") as fh:
        for line in fh.read().splitlines():
            if line.startswith("# источники"):
                cur = src
            elif line.startswith("# картинки"):
                cur = img
            elif line.strip() and not line.startswith("#") and cur is not None and "  " in line:
                h, rel = line.split("  ", 1)
                cur[rel.strip()] = h.strip()
    return src, img


def check_art(art: dict) -> list:
    """Пункт 6: картинки docs/promo. Возвращает строки для печати (что есть)."""
    info = []
    need = [k for k in ("ICON", "COVER", "TITLES", "ART_SOURCES", "SOURCES_TXT") if k not in art]
    if need:
        bad(f"tools/promo_art.py: нет констант {need} (или они не литералы)")
        return info
    promo = os.path.join(ROOT, "docs", "promo")
    cw, ch = art["COVER"]
    want = {"icon_%d.png" % art["ICON"]: (art["ICON"], art["ICON"])}
    for lang in list(art["TITLES"]) + ["notext"]:
        want["cover_%dx%d_%s.png" % (cw, ch, lang)] = (cw, ch)
    for lang in LANGS:
        if lang not in art["TITLES"]:
            bad(f"{lang}: нет обложки с названием (promo_art.TITLES — {sorted(art['TITLES'])})")
    for name, size in want.items():
        path = os.path.join(promo, name)
        if not os.path.isfile(path):
            bad(f"docs/promo/{name}: нет — python3 tools/promo_art.py")
            continue
        pi = png_info(path)
        if pi is None:
            bad(f"docs/promo/{name}: не PNG")
        elif pi[:2] != size:
            bad(f"docs/promo/{name}: {pi[0]}×{pi[1]}, нужно {size[0]}×{size[1]}")
        elif pi[2]:
            bad(f"docs/promo/{name}: есть прозрачность (promo_art сохраняет без альфа-канала — фон на всю картинку)")
        else:
            info.append(f"{name} {pi[0]}×{pi[1]} {os.path.getsize(path) // 1024} КБ")
    sources = os.path.join(promo, art["SOURCES_TXT"])
    if not os.path.isfile(sources):
        bad(f"docs/promo/{art['SOURCES_TXT']}: нет — python3 tools/promo_art.py (без --icon)")
        return info
    rec_src, rec_img = read_sources(sources)
    stale = []
    for rel in art["ART_SOURCES"]:
        path = os.path.join(ROOT, rel)
        if not os.path.isfile(path):
            bad(f"promo_art.ART_SOURCES: нет файла {rel}")
        elif rec_src.get(rel) != sha1(path):
            stale.append(rel)
    if stale:
        bad(f"картинки docs/promo устарели — после рисования изменились {stale}: python3 tools/promo_art.py")
    for rel in sorted(set(rec_src) - set(art["ART_SOURCES"])):
        bad(f"{art['SOURCES_TXT']}: источник {rel} больше не в ART_SOURCES — python3 tools/promo_art.py")
    for name in want:
        path = os.path.join(promo, name)
        if os.path.isfile(path) and rec_img.get(name) != sha1(path):
            bad(f"docs/promo/{name}: не та картинка, что нарисовал promo_art (заменена или от прошлого запуска) — "
                f"python3 tools/promo_art.py")
    for name in sorted(set(rec_img) - set(want)):
        bad(f"{art['SOURCES_TXT']}: лишняя картинка {name} (нет в TITLES / не тот размер) — python3 tools/promo_art.py")
    extra = sorted(f for f in os.listdir(promo) if f.endswith(".png") and f not in want)
    if extra:
        bad(f"docs/promo: лишние картинки {extra} — удалите (старые размеры или языки?)")
    if not stale:
        info.append(f"отпечаток {art['SOURCES_TXT']}: {len(art['ART_SOURCES'])} источников не менялись")
    return info


def gd_block(text: str, name: str) -> str:
    """Тело константы-массива GDScript «const NAME…= [ … ]» (до «]» в начале строки или в той же строке)."""
    m = re.search(r"^const %s\b[^=]*= \[(.*?)\]$" % name, text, re.M) or \
        re.search(r"^const %s\b[^=]*= \[\n(.*?)^\]" % name, text, re.M | re.S)
    return m.group(1) if m else ""


def shots_consts() -> dict:
    """LANGS, FORMATS, SHOTS, OUT_DIR из tests/promo_shots.gd. Запись, которую не разобрали, — проблема (а не пропуск)."""
    gd = read(SHOTS_GD)
    out = {"LANGS": re.findall(r'"(\w+)"', gd_block(gd, "LANGS"))}
    body = gd_block(gd, "FORMATS")
    fm = re.findall(r'\{"name": "(\w+)", "size": Vector2i\((\d+), (\d+)\), "logical": Vector2i\((\d+), (\d+)\)\}', body)
    out["FORMATS"] = [{"name": n, "size": (int(a), int(b)), "logical": (int(c), int(d))} for n, a, b, c, d in fm]
    if len(fm) != body.count("{"):
        bad(f"{SHOTS_GD}: FORMATS — разобрано {len(fm)} из {body.count('{')} записей (вид: "
            '{"name": …, "size": Vector2i(…), "logical": Vector2i(…)})')
    body = gd_block(gd, "SHOTS")
    sh = re.findall(r'\{"level": (\d+), "placed": ([\d.]+)\}', body)
    out["SHOTS"] = [(int(lv), float(pl)) for lv, pl in sh]
    if len(sh) != body.count("{"):
        bad(f"{SHOTS_GD}: SHOTS — разобрано {len(sh)} из {body.count('{')} записей (вид: " '{"level": N, "placed": 0.5})')
    m = re.search(r'^const OUT_DIR := "res://([^"]+)"', gd, re.M)
    out["OUT_DIR"] = m.group(1) if m else ""
    return out


def check_shots(levels: int, need: bool) -> list:
    """Пункт 7: сцена-витрина tests/promo_shots.gd и снятые ею кадры. Возвращает строки для печати."""
    info = []
    if not os.path.isfile(os.path.join(ROOT, SHOTS_GD)):
        bad(f"{SHOTS_GD}: нет сцены-витрины скриншотов")
        return info
    c = shots_consts()
    empty = [k for k, v in c.items() if not v]
    if empty:
        bad(f"{SHOTS_GD}: не разобраны {empty}")
        return info
    # 7а. Настройки витрины.
    if c["LANGS"] != LANGS:
        bad(f"{SHOTS_GD}: LANGS {c['LANGS']}, а языки страницы {LANGS}")
    proj = read("project.godot")
    base = tuple(int(re.search(r"window/size/viewport_%s=(\d+)" % k, proj).group(1)) for k in ("width", "height"))
    expand = 'window/stretch/aspect="expand"' in proj
    lay = read("scripts/game_layout.gd")
    to_land, to_port = (float(re.search(r"const %s := ([\d.]+)" % k, lay).group(1)) for k in ("TO_LANDSCAPE", "TO_PORTRAIT"))
    kinds = {"phone": 0, "desktop": 0}
    names = [f["name"] for f in c["FORMATS"]]
    if len(set(names)) != len(names):
        bad(f"{SHOTS_GD}: повтор имени формата {names}")
    for f in c["FORMATS"]:
        (w, h), (lw, lh), n = f["size"], f["logical"], f["name"]
        k = min(w / base[0], h / base[1])  # expand: меньшая сторона базы вписывается, длинная — растёт
        if not expand:
            bad("project.godot: растяжение не expand — пересчитайте logical в FORMATS promo_shots.gd")
        elif abs(lw - w / k) > 1 or abs(lh - h / k) > 1:
            bad(f"{SHOTS_GD}: {n} logical {lw}×{lh}, а окно {w}×{h} игра видит как {w / k:.0f}×{h / k:.0f} "
                f"(база {base[0]}×{base[1]}, expand)")
        r = lw / lh
        if to_port <= r < to_land:
            bad(f"{SHOTS_GD}: {n} — отношение {r:.3f} между порогами GameLayout ({to_port}…{to_land}): "
                "раскладка зависела бы от прошлого кадра")
        if r >= to_land:
            kinds["desktop"] += 1
            if w * 9 != h * 16:
                bad(f"{SHOTS_GD}: {n} {w}×{h} — для компьютера только 16:9")
            if not SHOT_DESKTOP_W[0] <= w <= SHOT_DESKTOP_W[1]:
                bad(f"{SHOTS_GD}: {n} ширина {w} — для компьютера {SHOT_DESKTOP_W[0]}…{SHOT_DESKTOP_W[1]} px")
        else:
            kinds["phone"] += 1
            if w >= h:
                bad(f"{SHOTS_GD}: {n} {w}×{h} — для телефона нужен портрет")
    for kind, cnt in kinds.items():
        if not cnt:
            bad(f"{SHOTS_GD}: нет формата для {'телефона (портрет)' if kind == 'phone' else 'компьютера (16:9)'}")
    shots = c["SHOTS"]
    if len(shots) < SHOT_MIN:
        bad(f"{SHOTS_GD}: кадров {len(shots)} — консоль просит не меньше {SHOT_MIN} на платформу")
    chap = read("scripts/chapters.gd")
    first = [int(x) for x in re.findall(r"\d+", gd_block(chap, "FIRST"))]
    mech = re.findall(r'"(\w*)"', gd_block(chap, "MECHANICS"))
    rule = int(re.search(r"const RULE_LEVELS := (\d+)", chap).group(1))
    pack = re.findall(r'^\t"(\d\d:\d+:\d+)(?::\w*)?",?$', read("scripts/level_pack_data.gd"), re.M)
    seen = {}
    for i, (lv, placed) in enumerate(shots, 1):
        where = f"{SHOTS_GD}: кадр {i} (уровень {lv})"
        if not 1 <= lv <= levels:
            bad(f"{where}: уровня нет в паке (1…{levels})")
            continue
        ch = max(j for j, f0 in enumerate(first) if f0 <= lv)
        if lv == first[ch]:
            bad(f"{where}: первый уровень главы {ch + 1} — над полем карточка главы")
        elif ch < len(mech) and mech[ch] and lv - first[ch] < rule:
            bad(f"{where}: уровень {lv - first[ch] + 1} главы {ch + 1} — над полем правило механики «{mech[ch]}» "
                f"(первые {rule})")
        if ch in seen:
            bad(f"{where}: та же глава {ch + 1}, что у кадра {seen[ch]} — одна тема фона, возьмите другую главу")
        seen.setdefault(ch, i)
        if not 0.0 < placed < 1.0:
            bad(f"{where}: placed {placed} — нужно 0 < placed < 1 (пустое поле или уже победа)")
        elif len(pack) == levels:
            # Как в витрине: round(placed · блоков решения), GDScript round — половина от нуля.
            n = len(pack[lv - 1].split(":")[1]) // 6
            k = int(placed * n + 0.5)
            if not 1 <= k <= n - 1:
                bad(f"{where}: placed {placed} из {n} блоков — на поле {k}: нужно от 1 до {n - 1} "
                    "(пустое поле или уже победа)")
    # 7б. Снятые кадры.
    out = os.path.join(ROOT, c["OUT_DIR"])
    want = {"%s_%s_%d.png" % (f["name"], lang, i): f["size"]
            for f in c["FORMATS"] for lang in LANGS for i in range(1, len(shots) + 1)}
    have = sorted(f for f in os.listdir(out) if f.endswith(".png")) if os.path.isdir(out) else []
    if not have:
        msg = (f"скриншоты не сняты — откройте tests/promo_shots.tscn в Godot и F6 (файлов: {len(want)} → "
               f"{c['OUT_DIR']}/)")
        if need:
            bad(msg)
        else:
            info.append(msg)
        return info
    sizes = []
    for name, (w, h) in sorted(want.items()):
        path = os.path.join(out, name)
        if not os.path.isfile(path):
            bad(f"{c['OUT_DIR']}/{name}: нет — снимите заново (tests/promo_shots.tscn)")
            continue
        pi = png_info(path)
        size = os.path.getsize(path)
        if pi is None:
            bad(f"{c['OUT_DIR']}/{name}: не PNG")
        elif pi[:2] != (w, h):
            bad(f"{c['OUT_DIR']}/{name}: {pi[0]}×{pi[1]}, нужно {w}×{h}")
        elif pi[2]:
            bad(f"{c['OUT_DIR']}/{name}: есть прозрачность (витрина сохраняет RGB)")
        elif size < SHOT_MIN_BPP * w * h:
            bad(f"{c['OUT_DIR']}/{name}: {size // 1024} КБ — почти однотонный, пустой кадр? (запуск без окна или "
                "без видеокарты)")
        else:
            sizes.append(size)
    extra = sorted(set(have) - set(want))
    if extra:
        bad(f"{c['OUT_DIR']}: лишние кадры {extra} — от прежних SHOTS / FORMATS? Удалите")
    if sizes:
        fmts = ", ".join("%s %d×%d" % (f["name"], *f["size"]) for f in c["FORMATS"])
        info.append(f"скриншоты: в порядке {len(sizes)} из {len(want)} ({fmts}; кадров {len(shots)}, языков "
                    f"{len(LANGS)}), {min(sizes) // 1024}…{max(sizes) // 1024} КБ")
    return info


def main() -> int:
    show = "--print" in sys.argv
    if not os.path.isfile(PROMO):
        print(f"Нет {PROMO}")
        return 1
    t = parse_promo(read("docs/PROMO.md"))
    common = parse_common(read("docs/PROMO.md"))
    facts = game_facts()
    pos = {lang: po(lang) for lang in ("en", "tr")}
    code = code_text()

    # 1. Поля и длина.
    for lang in LANGS:
        for f in FIELDS:
            s = t.get((lang, f), "")
            if not s.strip():
                bad(f"{lang} · {f}: нет поля или пусто")
            elif counted(s) > LIMITS[f]:
                bad(f"{lang} · {f}: {counted(s)} символов (переводы строк — за два) > {LIMITS[f]}")
    for key in t:
        if key[0] not in LANGS or key[1] not in FIELDS:
            bad(f"лишнее поле {key[0]} · {key[1]} (языки {LANGS}, поля {FIELDS})")
    for f, limit in COMMON.items():
        s = common.get(f, "")
        if not s.strip():
            bad(f"общее поле {f}: нет или пусто")
        elif counted(s) > limit:
            bad(f"общее поле {f}: {counted(s)} символов (переводы строк — за два) > {limit}")
    for f in common:
        if f not in COMMON:
            bad(f"лишнее общее поле {f} (общие поля {list(COMMON)})")

    # 2. Запрещённое. Общие поля — как русский текст; комментарий разработчика — только ссылки и эмодзи.
    fields = list(t.items()) + [(("ru", f), s) for f, s in common.items()]
    for (lang, f), s in fields:
        ls = low(lang, s)
        if re.search(r"https?://|www\.|\.(ru|com|net|org|io)\b", ls):
            bad(f"{lang} · {f}: ссылка")
        em = sorted({ch for ch in s if is_emoji(ch)})
        if em:
            bad(f"{lang} · {f}: эмодзи {''.join(em)}")
        if f == "Комментарий разработчика":
            continue
        caps = [w for w in re.findall(r"[^\W\d_]{4,}", s) if w.isupper()]
        if caps:
            bad(f"{lang} · {f}: капсом {caps}")
        for w in PLATFORMS + ([] if f == "Ключевые слова" else GAMES):
            if re.search(r"(?<!\w)" + re.escape(w) + r"(?!\w)", ls):
                bad(f"{lang} · {f}: чужое название / платформа «{w}»")
        for w in CALLS:
            if w in ls:
                bad(f"{lang} · {f}: «{w.strip()}» (призыв оценить, реклама или «бесплатно» — на странице не нужно)")
        if "  " in s or s != s.strip():
            bad(f"{lang} · {f}: двойной пробел или пробел по краям")

    # 3. Согласованность языков (эталон — ru).
    for f in FIELDS:
        base = t.get(("ru", f))
        if base is None:
            continue
        for lang in LANGS[1:]:
            s = t.get((lang, f))
            if s is None:
                continue
            if f != "Название" and numbers(s) != numbers(base):
                bad(f"{lang} · {f}: числа {numbers(s)}, в ru {numbers(base)}")
            for what, rx in (("абзацев", r"\n\s*\n"), ("пунктов «•»", r"^• "), ("шагов «N.»", r"^\d+\. ")):
                a, b = len(re.findall(rx, s, re.M)), len(re.findall(rx, base, re.M))
                if a != b:
                    bad(f"{lang} · {f}: {what} {a}, в ru {b}")
    kw = [w.strip() for w in common.get("Ключевые слова", "").split(",") if w.strip()]
    if len(set(map(str.lower, kw))) != len(kw):
        bad("Ключевые слова: повторы")
    if "\n" in common.get("Ключевые слова", ""):
        bad("Ключевые слова: одной строкой, через запятую")

    # 4. Факты из кода.
    for lang in LANGS:
        desc = t.get((lang, "Об игре"), "")
        short = t.get((lang, "Описание для SEO"), "")
        how = t.get((lang, "Как играть"), "")
        ld = low(lang, desc)
        for where, s in (("Об игре", desc), ("Описание для SEO", short)):
            if str(facts["levels"]) not in numbers(s):
                bad(f"{lang} · {where}: нет числа уровней {facts['levels']} (LevelPack)")
        if not re.search(r"(?<!\d)%d (глав|chapters|bölüm)" % facts["chapters"], ld):
            bad(f"{lang} · Об игре: нет «{facts['chapters']} глав» (Chapters.NAMES — {facts['chapters']})")
        for k in ("min", "max"):
            if facts[k] not in desc:
                bad(f"{lang} · Об игре: нет поля {facts[k]} (уровни: от {facts['min']} до {facts['max']})")
        for idea in facts["mech_ideas"]:
            name = idea.split(": ", 1)[1] if lang == "ru" else pos[lang].get(idea, "").split(": ", 1)[-1]
            name = re.sub(r"^the ", "", name)
            if not name or low(lang, name) not in ld:
                bad(f"{lang} · Об игре: механика «{name or idea}» не теми словами, что в игре ({idea})")
        for word, msgid in TERMS[lang]:
            game = msgid if lang == "ru" else pos[lang].get(msgid, "")
            if low(lang, word) not in low(lang, game):
                bad(f"{lang}: термин «{word}» не из игры (перевод «{msgid}» — «{game}»)")
            if low(lang, word) not in ld + low(lang, how):
                bad(f"{lang}: в описании и «Как играть» нет термина игры «{word}»")
        # «Как играть»: коротко, поворот — нажатием (как в обучении), без клавиш и лишних способов управления.
        if counted(how) > HOW_MAX:
            bad(f"{lang} · Как играть: {counted(how)} символов > {HOW_MAX} (HOW_MAX: длинное не прочтут)")
        phrase, msgid = ROTATE_TAP[lang]
        game = msgid if lang == "ru" else pos[lang].get(msgid, "")
        if low(lang, phrase) not in low(lang, game):
            bad(f"{lang}: «{phrase}» не из обучения (перевод «{msgid}» — «{game}»)")
        if low(lang, phrase) not in low(lang, how):
            bad(f"{lang} · Как играть: нет поворота нажатием «{phrase}» (слова обучения)")
        lh = low(lang, how)
        for w in HOW_EXTRA[lang]:
            if re.search(r"(?<!\w)" + re.escape(w), lh):
                bad(f"{lang} · Как играть: «{w}» — лишнее для игрока (всё управление — нажать и перетащить)")
        for key in KEYS:
            if key not in KEY_WORDS and re.search(r"(?<![\w+])" + re.escape(key) + r"(?![\w+])", how):
                bad(f"{lang} · Как играть: клавиша «{key}» — клавиши только в комментарии разработчика")
    # Управление для модераторов — в «Комментарии разработчика» (он один, по-русски); всё названное есть в коде.
    note = common.get("Комментарий разработчика", "")
    for key, rx in KEYS.items():
        word = KEY_WORDS.get(key, {}).get("ru", key)
        if not re.search(rx, code):
            bad(f"клавиша / кнопка {key}: в коде нет {rx}")
        if key in KEY_WORDS:
            found = word in note.lower()
        else:  # клавиша — отдельным словом и с учётом регистра («H», а не буква в слове)
            found = re.search(r"(?<![\w+])" + re.escape(key) + r"(?![\w+])", note) is not None
        if not found:
            bad(f"Комментарий разработчика: нет «{word}» (управление на компьютере — для модераторов)")
    if "левой кнопкой мыши" not in note:
        bad("Комментарий разработчика: нет «левой кнопкой мыши» — главное: вся игра управляется ею")
    for lang in LANGS:
        how = t.get((lang, "Как играть"), "")
        ld = low(lang, t.get((lang, "Об игре"), ""))
        if STAR_RULE[lang] not in low(lang, how) or STAR_RULE[lang] not in ld:
            bad(f"{lang}: правило трёх звёзд «{STAR_RULE[lang]}» — и в описании, и в «Как играть»")
    if not re.search(r"var stars := 3 if penalty == 0", code) or "undos_used + hints.used" not in code:
        bad("правило трёх звёзд в game.gd изменилось — сверьте «без отмен и подсказок» в текстах")

    # 5. Название на обложке (tools/promo_art.py, TITLES) — слова поля «Название» прописными (турецкие правила).
    art = art_consts()
    titles = art.get("TITLES", {})
    for lang in LANGS:
        name = t.get((lang, "Название"), "")
        if lang == "tr":
            name = name.replace("i", "İ").replace("ı", "I")
        want = tuple(re.findall(r"[^\W\d_]+", name.upper()))
        lines = titles.get(lang, ())
        got = tuple(w for line in lines for w in re.findall(r"[^\W\d_]+", line))
        if got != want:
            bad(f"{lang}: на обложке (promo_art.TITLES) {lines}, а название — {want}")
        elif not 1 <= len(lines) <= 3:
            bad(f"{lang}: на обложке {len(lines)} строк — помещается 1–3 (promo_art.TITLES)")

    # 6. Картинки docs/promo.
    art_info = check_art(art)

    # 7. Скриншоты: сцена-витрина и её кадры.
    shot_info = check_shots(facts["levels"], "--need-shots" in sys.argv)

    for lang in LANGS:
        print(lang + ": " + ", ".join(f"{f} {counted(t.get((lang, f), ''))}/{LIMITS[f]}" for f in FIELDS))
        if show:
            for f in FIELDS:
                print(f"\n--- {lang} · {f} ---\n{t.get((lang, f), '')}")
            print()
    print("общие: " + ", ".join(f"{f} {counted(common.get(f, ''))}/{n}" for f, n in COMMON.items()) +
          f" (ключевых слов {len(kw)})")
    if show:
        for f in COMMON:
            print(f"\n--- {f} ---\n{common.get(f, '')}")
        print()
    print(f"факты игры: уровней {facts['levels']}, глав {facts['chapters']}, поле {facts['min']}…{facts['max']}, "
          f"механики {facts['mechanics']}")
    print("картинки: " + (", ".join(art_info) if art_info else "—"))
    for line in shot_info:
        print(line)
    for p in problems:
        print("ПРОБЛЕМА:", p)
    print(f"проблем: {len(problems)}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
