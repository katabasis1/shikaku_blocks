#!/usr/bin/env python3
"""Генерирует locale/en.po и locale/tr.po из таблицы ниже и проверяет,
что каждая строка из tr(...) в .gd и каждый text/tooltip в .tscn переведены.

Исходный язык — русский (fallback="ru" в project.godot), поэтому ru.po не нужен.
Запуск из корня проекта:  python3 tools/make_po.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# msgid (русский) -> (en, tr)
STRINGS = {
    # game.gd и компоненты (drag_controller, hint_controller)
    "УРОВЕНЬ %d": ("LEVEL %d", "SEVİYE %d"),
    "Осталось блоков: %d": ("Blocks left: %d", "Kalan blok: %d"),
    "Отлично!": ("Great!", "Harika!"),
    "Супер!": ("Super!", "Süper!"),
    "Невероятно!": ("Incredible!", "İnanılmaz!"),
    # Сердца (20.1a): отмены хода нет — тексты «Отмени ход» убраны. Это сообщение — до окна 20.1b.
    "Сердца кончились — начни заново": ("Out of hearts — start over", "Canın kalmadı — baştan başla"),
    "Подсказка откроется после просмотра рекламы": (
        "Watch the ad to unlock the hint",
        "İpucu için reklamı izle"),
    # tutorial_coach.gd: подпись над полем, причины красной подсветки, подсказки обучения
    "Число — это размер блока. Перетащи блок на его число": (
        "The number is the block's size. Drag each block onto its number",
        "Sayı, bloğun boyutudur. Her bloğu kendi sayısına sürükle"),
    "Нажми на блок, чтобы повернуть его": ("Tap a block to rotate it", "Döndürmek için bloğa dokun"),
    "В каждом блоке — ровно одно число": (
        "Each block covers exactly one number",
        "Her blok tam olarak bir sayıyı kaplar"),
    "Блок накрывает одно число, и его размер равен этому числу": (
        "A block covers one number, and its size equals that number",
        "Blok tek bir sayıyı kaplar ve boyutu o sayıya eşittir"),
    "Блоки не должны накладываться": ("Blocks can't overlap", "Bloklar üst üste binemez"),
    "В блоке должно быть ровно одно число": (
        "A block must cover exactly one number",
        "Blok tam olarak bir sayıyı kaplamalı"),
    "Здесь нужен блок из %d клеток": ("This spot needs a block of %d cells", "Buraya %d hücrelik bir blok gerekir"),
    "Так остальные блоки не поместятся": ("Then the other blocks won't fit", "O zaman diğer bloklar sığmaz"),
    # механики 19.3 («Лаборатория»): правило над полем и причины, почему блок не встаёт
    "Эта клетка занята с самого начала": ("This cell is taken from the start", "Bu hücre baştan beri dolu"),
    "Цветную клетку накрывает только блок того же цвета": ("A colored cell takes only a block of the same color",
                                                           "Renkli hücreye yalnızca aynı renkte blok konur"),
    "Белые плитки — препятствия: на них блок не встанет": ("White tiles are obstacles: blocks can't go there",
                                                           "Beyaz karolar engeldir: üzerlerine blok konmaz"),
    "Серый блок закреплён: строй вокруг него": ("The gray block is fixed: build around it",
                                               "Gri blok sabit: etrafına yerleştir"),
    "«?» — размер неизвестен: подойдёт любой блок, но решение одно": (
        "\u201c?\u201d hides the size: any block may fit, but only one way works",
        "\u201c?\u201d boyutu gizler: her blok sığabilir ama tek bir çözüm var"),
    # окно победы (13.5b): заголовок над полем, надпись в шапке карточки (WIN_HEADS — по звёздам), строки
    "УРОВЕНЬ %d ПРОЙДЕН!": ("LEVEL %d COMPLETE!", "SEVİYE %d TAMAMLANDI!"),
    "НОВЫЙ РЕКОРД!": ("NEW RECORD!", "YENİ REKOR!"),
    "ИДЕАЛЬНО!": ("PERFECT!", "MÜKEMMEL!"),
    "ОТЛИЧНО!": ("GREAT!", "HARİKA!"),
    "ХОРОШО!": ("GOOD!", "İYİ!"),
    "Всего очков: %s": ("Total score: %s", "Toplam puan: %s"),
    "Всего очков: %s (+%s)": ("Total score: %s (+%s)", "Toplam puan: %s (+%s)"),
    "Рекорд уровня: %s": ("Level record: %s", "Seviye rekoru: %s"),
    # сцены
    "Нет ходов!": ("No moves!", "Hamle yok!"),
    "ИГРАТЬ": ("PLAY", "OYNA"),
    "СЕРИЯ %d": ("STREAK %d", "SERİ %d"),
    "СЕРИЯ %d · ГОТОВО": ("STREAK %d · DONE", "SERİ %d · TAMAM"),  # 18.1f: задача дня уже пройдена
    # 18.1f: заголовок шапки задачи дня; с 12.10 — и кнопка меню (была «ЕЖЕДНЕВНАЯ» / DAILY / GÜNLÜK). Кнопка
    # 440×110, шрифт 44, без ужатия (selftest 18.2b): «GÜNLÜK BULMACA» ≈ 431 px не влезает в 385 — «GÜNÜN GÖREVİ».
    "ЗАДАЧА ДНЯ": ("DAILY PUZZLE", "GÜNÜN GÖREVİ"),
    # Экран лидеров (18.3)
    "ЛИДЕРЫ": ("LEADERS", "LİDERLER"),
    "Лидеры": ("Leaderboard", "Liderler"),
    "ОЧКИ": ("SCORE", "PUAN"),
    "СЕРИЯ": ("STREAK", "SERİ"),
    "ВОЙТИ": ("SIGN IN", "GİRİŞ YAP"),
    "Загрузка…": ("Loading…", "Yükleniyor…"),
    "Пока пусто — будьте первым!": ("Empty so far — be the first!", "Henüz boş — ilk sen ol!"),
    "Игрок": ("Player", "Oyuncu"),
    "Вы": ("You", "Sen"),
    "Таблица лидеров — в Яндекс Играх": ("The leaderboard lives on Yandex Games", "Liderlik tablosu Yandex Games'te"),
    "Не удалось загрузить. Проверьте интернет": ("Couldn't load. Check your connection", "Yüklenemedi. İnternetini kontrol et"),
    "Войдите, чтобы попасть в таблицу": ("Sign in to get on the leaderboard", "Tabloya girmek için giriş yap"),
    "Пройдите задачу дня, чтобы попасть в таблицу": ("Solve the daily puzzle to get on the board", "Tabloya girmek için günlük bulmacayı çöz"),
    "Пройдите уровень, чтобы попасть в таблицу": ("Complete a level to get on the board", "Tabloya girmek için bir seviye geç"),
    "ЕЖЕДНЕВНАЯ ЗАДАЧА ПРОЙДЕНА!": ("DAILY PUZZLE SOLVED!", "GÜNLÜK BULMACA ÇÖZÜLDÜ!"),
    "Серия: %d": ("Streak: %d", "Seri: %d"),
    "В МЕНЮ": ("MENU", "MENÜ"),  # 18.1f: кнопка окна победы задачи дня
    "УРОВНИ": ("LEVELS", "SEVİYELER"),  # 18.2b: кнопка меню — карта уровней
    "ДАЛЕЕ": ("NEXT", "DEVAM"),
    "Переиграть уровень": ("Replay level", "Seviyeyi tekrar oyna"),
    # settings_panel (настройки в меню и пауза в игре; заголовки в шапке карточки — 13.5c), кнопки меню и игры
    "НАСТРОЙКИ": ("SETTINGS", "AYARLAR"),
    "ПАУЗА": ("PAUSE", "DURAKLATILDI"),
    "СБРОСИТЬ ПРОГРЕСС?": ("RESET PROGRESS?", "İLERLEMEYİ SIFIRLA?"),
    # подсказки кнопок: шестерёнка в меню, пауза в игре
    "Настройки": ("Settings", "Ayarlar"),
    "Пауза": ("Pause", "Duraklat"),
    "ПРОДОЛЖИТЬ": ("CONTINUE", "DEVAM ET"),
    "ГОТОВО": ("DONE", "TAMAM"),
    "Музыка": ("Music", "Müzik"),
    "Звуки": ("Sounds", "Sesler"),
    "Вибрация": ("Vibration", "Titreşim"),
    "Сбросить прогресс": ("Reset progress", "İlerlemeyi sıfırla"),
    "ОЦЕНИТЬ ИГРУ": ("RATE THE GAME", "OYUNU PUANLA"),  # 12.10b: золотая таблетка в настройках после обучения
    "В меню": ("Main menu", "Ana menü"),
    "Уровни, звёзды и очки начнутся с нуля. Вернуть их будет нельзя.": (
        "Levels, stars and points will start from zero. This can't be undone.",
        "Seviyeler, yıldızlar ve puanlar sıfırdan başlar. Bu işlem geri alınamaz."),
    "ОТМЕНА": ("CANCEL", "İPTAL"),
    "СБРОСИТЬ": ("RESET", "SIFIRLA"),
    # окно настроек и пауза: таблетка «Меньше движения» (этап 14.1, settings_panel.gd)
    "Меньше движения: выкл": ("Reduce motion: off", "Az hareket: kapalı"),
    "Меньше движения: вкл": ("Reduce motion: on", "Az hareket: açık"),
    # главы (19.5c, scripts/chapters.gd): плашка на карте и карточка начала главы, названия, новые идеи
    "ГЛАВА %d · %s": ("CHAPTER %d · %s", "BÖLÜM %d · %s"),
    "ГЛАВА %d": ("CHAPTER %d", "BÖLÜM %d"),  # 19.5d: карточка начала главы (ChapterCard.HEAD)
    "СУМЕРКИ": ("TWILIGHT", "ALACAKARANLIK"),
    "ЗВЁЗДЫ": ("STARS", "YILDIZLAR"),
    "ПОЛНОЧЬ": ("MIDNIGHT", "GECE YARISI"),
    "ЛУНА": ("MOON", "AY"),
    "КОМЕТА": ("COMET", "KOMET"),
    "СИЯНИЕ": ("AURORA", "KUTUP IŞIĞI"),
    "ТУМАННОСТЬ": ("NEBULA", "BULUTSU"),
    "ГАЛАКТИКА": ("GALAXY", "GALAKSİ"),
    "КОСМОС": ("COSMOS", "KOZMOS"),
    "РАССВЕТ": ("DAWN", "ŞAFAK"),
    "Новое: длинные блоки 5 и 10": ("New: long blocks 5 and 10", "Yeni: uzun bloklar 5 ve 10"),
    "Новое: большой блок 12": ("New: big block 12", "Yeni: büyük blok 12"),
    # 19.5e: идеи глав 4–8 — механики (Chapters.IDEAS, MECHANICS)
    "Новое: препятствия": ("New: obstacles", "Yeni: engeller"),
    "Новое: закреплённый блок": ("New: fixed block", "Yeni: sabit blok"),
    "Новое: цветные клетки": ("New: colored cells", "Yeni: renkli hücreler"),
    "Новое: число «?»": ("New: the \u201c?\u201d number", "Yeni: \u201c?\u201d sayısı"),
    "Все новинки вперемешку": ("All the new ideas, mixed", "Tüm yenilikler karışık"),
}

# Тексты-заглушки в сценах, которые код перезаписывает до первого кадра.
PLACEHOLDERS = re.compile(r"^(УРОВЕНЬ 1|Уровень 1|Осталось блоков: 0|Всего очков: 0|УРОВЕНЬ 1 ПРОЙДЕН!|[+\d]+)$")

LANGS = {"en": 0, "tr": 1}


def po_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def write_po(lang: str, idx: int) -> None:
    lines = [
        'msgid ""',
        'msgstr ""',
        '"Project-Id-Version: Shikaku Blocks\\n"',
        '"MIME-Version: 1.0\\n"',
        '"Content-Type: text/plain; charset=UTF-8\\n"',
        '"Content-Transfer-Encoding: 8bit\\n"',
        f'"Language: {lang}\\n"',
        "",
    ]
    for src, tr in STRINGS.items():
        lines.append(f'msgid "{po_escape(src)}"')
        lines.append(f'msgstr "{po_escape(tr[idx])}"')
        lines.append("")
    out = ROOT / "locale" / f"{lang}.po"
    out.write_text("\n".join(lines), encoding="utf-8")
    print("written", out.relative_to(ROOT), len(STRINGS), "strings")


def collect_used() -> set:
    used = set()
    for gd in ROOT.rglob("*.gd"):
        text = gd.read_text(encoding="utf-8")
        for m in re.finditer(r'\btr\("((?:[^"\\]|\\.)*)"\)', text):
            used.add(m.group(1).encode().decode("unicode_escape").encode("latin-1").decode("utf-8"))
        # Подписи таблеток из кода (PillButton переводит text сам — atr): next_button.text = "В МЕНЮ" (18.1f).
        for m in re.finditer(r'\b\w+_button\.text = "((?:[^"\\]|\\.)*)"', text):
            used.add(m.group(1))
        # Строки-константы и return "…", которые переводятся через tr(переменная) позже: строка с меткой
        # «# msgid» в конце (экран лидеров, 18.3).
        for line in text.splitlines():
            if line.rstrip().endswith("# msgid"):
                used.update(re.findall(r'"((?:[^"\\]|\\.)+)"', line))
        # Списки строк, которые переводятся через tr(список[i]): слова комбо, надписи окна победы.
        for m in re.finditer(r"(?:COMBO_WORDS|WIN_HEADS)[^=]*=\s*\[([^\]]*)\]", text):
            used.update(re.findall(r'"([^"]*)"', m.group(1)))
    for tscn in ROOT.rglob("*.tscn"):
        text = tscn.read_text(encoding="utf-8")
        for m in re.finditer(r'^(?:text|tooltip_text) = "((?:[^"\\]|\\.)*)"', text, re.M | re.S):
            s = m.group(1)
            if not PLACEHOLDERS.match(s):
                used.add(s)
    return used


def main() -> int:
    for lang, idx in LANGS.items():
        write_po(lang, idx)
    used = collect_used()
    unused = sorted(s for s in STRINGS if s not in used)
    if unused:
        print("в таблице, но не используются (проверь, не устарели ли):")
        for s in unused:
            print("  ", repr(s))
    missing = sorted(s for s in used if s not in STRINGS)
    if missing:
        print("НЕТ ПЕРЕВОДА:")
        for s in missing:
            print("  ", repr(s))
        return 1
    print("все строки переведены")
    return 0


if __name__ == "__main__":
    sys.exit(main())
