#!/usr/bin/env python3
"""Модель сердец попытки (этап 20.1a, PLAN 20.1) — те же правила, что в scripts/hearts.gd, и окно «Сердца
закончились» (20.1b) — те же правила, что HeartsPanel.offer_for / after_ad в scenes/ui/hearts_panel.gd.

Правила:
- Сколько сердец на попытку (max_for): «Лаборатория» и флаг hearts = 0 — без предела (0); основной путь до
  hearts_from_level — тоже без предела (обучение со страховкой); задача дня — с сердцами всегда.
- Ошибка (lose) — ход, после которого поле уже не заполнить: сгорает сердце, ошибка считается. Без предела сердца
  не горят, ошибки считаются.
- Сердца кончились (out) — ходить нельзя. Возрождение за рекламу — если возрождений меньше revive_max (флаг).
  Бесплатное продолжение (реклама не показалась) — ещё и флаг revive_free_on_fail и только раз за попытку.
  Возрождение даёт +1 сердце, поле как есть.
- Звёзды за победу: после возрождения — 1, иначе 3 − ошибки − подсказки, не ниже 1.
- Окно (offer_for): возрождения исчерпаны — LIMIT (только «Заново»); реклама есть — AD («Продолжить» за рекламу);
  рекламы нет — FREE, если бесплатное продолжение ещё можно, иначе NO_AD.
- После рекламы за сердце (after_ad): награда — REVIVE; закрыл до награды — NOTE_CLOSED (окно остаётся, бесплатного
  нет); не показалась (not_shown, timeout) — FREE, если бесплатное ещё можно, иначе NOTE_FAILED (окно остаётся).

Сверка с кодом (без Godot): STARS_MAX и список функций scripts/hearts.gd — как в модели; флаги по умолчанию
в autoload/ysdk.gd — как в PLAN 20.1 (hearts 3, hearts_from_level 4, revive_max 3, revive_free_on_fail 1);
перечисления Offer и After в hearts_panel.gd — как OFFERS и AFTERS; tests/selftest.gd читает эталон, знает все
события и строки W и D. Поменяли hearts.gd или hearts_panel.gd — повторите правку здесь.

Эталон для самопроверки — tests/hearts_expected.txt (selftest, раздел «Сердца: правила»):
  python3 tools/hearts_model.py           — проверить модель и что эталон свежий;
  python3 tools/hearts_model.py --write   — пересобрать эталон (после правки правил здесь и в hearts.gd).

Строки эталона:
  M уровень задача_дня лаборатория hearts hearts_from_level = сердец
  R имя сердец revive_max revive_free_on_fail события = шаг шаг … stars=N
  W можно_возродиться реклама_есть бесплатное_можно = ПРЕДЛОЖЕНИЕ        (HeartsPanel.offer_for, имя из Offer)
  D награда итог_рекламы бесплатное_можно = ДЕЙСТВИЕ                       (HeartsPanel.after_ad, имя из After)
События: L — ошибка, H — подсказка, A — возрождение за рекламу, F — бесплатное продолжение, «-» — ничего.
Шаг — состояние после события: «осталось.ошибок.возрождений.ОВБР», где О — сердца кончились, В — можно возродиться,
Б — можно продолжить бесплатно, Р — событие сработало (0 / 1). stars — звёзды при победе после всех событий.
"""
import os
import re
import sys

STARS_MAX = 3
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "hearts_expected.txt")
HEARTS_GD = os.path.join(ROOT, "scripts", "hearts.gd")
YSDK_GD = os.path.join(ROOT, "autoload", "ysdk.gd")
SELFTEST_GD = os.path.join(ROOT, "tests", "selftest.gd")
PANEL_GD = os.path.join(ROOT, "scenes", "ui", "hearts_panel.gd")

# Флаги по умолчанию, которые обещает PLAN 20.1 (константы autoload/ysdk.gd).
PLAN_DEFAULTS = {"DEFAULT_HEARTS": 3, "DEFAULT_HEARTS_FROM_LEVEL": 4, "DEFAULT_REVIVE_MAX": 3,
                 "DEFAULT_REVIVE_FREE_ON_FAIL": 1}
# Функции Hearts в scripts/hearts.gd — у модели те же (появилась новая — перенести сюда и в сценарии).
GD_FUNCS = {"max_for", "reset", "is_limited", "lose", "is_out", "can_revive", "can_continue_free", "revive",
            "try_revive", "stars"}
EVENTS = "LHAF"
# Окно 20.1b: перечисления HeartsPanel.Offer и HeartsPanel.After — те же имена в том же порядке; итоги рекламы за
# награду — YSDK.last_ad_result (YSDK.ad_result и таймаут).
OFFERS = ["AD", "FREE", "NO_AD", "LIMIT"]
AFTERS = ["REVIVE", "NOTE_CLOSED", "FREE", "NOTE_FAILED"]
AD_RESULTS = ["rewarded", "closed", "not_shown", "timeout"]
PANEL_FUNCS = {"offer_for", "after_ad"}


class Hearts:
    def __init__(self):
        self.max_hearts = 0
        self.left = 0
        self.mistakes = 0
        self.revives = 0
        self.free_used = False

    @staticmethod
    def max_for(level, is_daily, is_lab, hearts, from_level):
        if is_lab or hearts <= 0:
            return 0
        if not is_daily and level < from_level:
            return 0
        return hearts

    def reset(self, n_max):
        self.max_hearts = max(n_max, 0)
        self.left = self.max_hearts
        self.mistakes = 0
        self.revives = 0
        self.free_used = False

    def is_limited(self):
        return self.max_hearts > 0

    def lose(self):
        self.mistakes += 1
        if self.max_hearts > 0 and self.left > 0:
            self.left -= 1

    def is_out(self):
        return self.max_hearts > 0 and self.left <= 0

    def can_revive(self, revive_max):
        return self.is_out() and self.revives < revive_max

    def can_continue_free(self, allow):
        return allow and not self.free_used

    def revive(self, free=False):
        self.revives += 1
        if free:
            self.free_used = True
        self.left += 1

    def try_revive(self, revive_max, free, allow_free):
        if not self.can_revive(revive_max) or (free and not self.can_continue_free(allow_free)):
            return False
        self.revive(free)
        return True

    def stars(self, hints_used):
        if self.revives > 0:
            return 1
        return min(max(STARS_MAX - self.mistakes - max(hints_used, 0), 1), STARS_MAX)


def offer_for(can_revive, ad_available, can_free):
    """Что предложить в окне «Сердца закончились» (HeartsPanel.offer_for)."""
    if not can_revive:
        return "LIMIT"
    if ad_available:
        return "AD"
    return "FREE" if can_free else "NO_AD"


def after_ad(rewarded, result, can_free):
    """Что делать, когда реклама за сердце закончилась (HeartsPanel.after_ad); result — YSDK.last_ad_result."""
    if rewarded:
        return "REVIVE"
    if result == "closed":
        return "NOTE_CLOSED"
    return "FREE" if can_free else "NOTE_FAILED"


def state(h, revive_max, allow_free, ok):
    flags = [h.is_out(), h.can_revive(revive_max), h.can_continue_free(allow_free), ok]
    return "%d.%d.%d.%s" % (h.left, h.mistakes, h.revives, "".join("1" if f else "0" for f in flags))


def run(n_max, revive_max, allow_free, events):
    """Прогон сценария; итог — строка после « = » в эталоне. selftest считает то же (_hearts_run)."""
    h = Hearts()
    h.reset(n_max)
    hints = 0
    steps = []
    for ev in events:
        if ev == "-":
            continue
        ok = True
        if ev == "L":
            h.lose()
        elif ev == "H":
            hints += 1
        elif ev == "A":
            ok = h.try_revive(revive_max, False, allow_free)
        elif ev == "F":
            ok = h.try_revive(revive_max, True, allow_free)
        else:
            raise ValueError("неизвестное событие %r" % ev)
        steps.append(state(h, revive_max, allow_free, ok))
    steps.append("stars=%d" % h.stars(hints))
    return " ".join(steps), h, hints


# Сценарии: имя, сердец, revive_max, revive_free_on_fail, события. Флаги по умолчанию — 3, 3, 1 (YSDK).
SCENARIOS = [
    ("чисто", 3, 3, 1, "-"),
    ("одна_ошибка", 3, 3, 1, "L"),
    ("две_ошибки", 3, 3, 1, "LL"),
    ("ошибка_и_подсказка", 3, 3, 1, "LH"),
    ("подсказка", 3, 3, 1, "H"),
    ("две_подсказки_и_ошибка", 3, 3, 1, "HHL"),
    ("сердца_кончились", 3, 3, 1, "LLL"),
    ("возрождение_за_рекламу", 3, 3, 1, "LLLA"),
    ("возрождение_рано", 3, 3, 1, "LA"),
    ("бесплатно_рано", 3, 3, 1, "LLF"),
    ("бесплатно_один_раз", 3, 3, 1, "LLLFLF"),
    ("бесплатно_потом_реклама", 3, 3, 1, "LLLFLA"),
    ("реклама_потом_бесплатно", 3, 3, 1, "LLLALF"),
    ("флаг_без_бесплатного", 3, 3, 0, "LLLFA"),
    ("три_возрождения", 3, 3, 1, "LLLALALALA"),
    ("одно_возрождение", 3, 1, 1, "LLLALA"),
    ("без_возрождений", 3, 0, 1, "LLLAF"),
    ("одно_сердце", 1, 3, 1, "LALA"),
    ("пять_сердец", 5, 3, 1, "LL"),
    ("пять_сердец_кончились", 5, 3, 1, "LLLLLA"),
    ("без_предела", 0, 3, 1, "LLLLAF"),
    ("без_предела_подсказки", 0, 3, 1, "HHHH"),
    ("ошибка_после_нуля", 2, 3, 1, "LLL"),
    ("возрождение_и_подсказка", 3, 3, 1, "LLLAH"),
    # Как selftest _test_hearts_out на живой игре: бесплатное, «есть сердце», второе бесплатное, реклама, предел.
    ("как_в_игре", 3, 2, 1, "LLLFALFALAF"),
]

MAX_FOR_LEVELS = [1, 3, 4, 5, 12, 1000]
MAX_FOR_HEARTS = [0, 1, 3, 5]
MAX_FOR_FROM = [1, 4, 10]


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return None


def gd_consts(text):
    """const ИМЯ := число / const ИМЯ: int = число → {ИМЯ: число}."""
    return {m.group(1): int(m.group(2))
            for m in re.finditer(r"^const\s+(\w+)\s*(?::\s*\w+\s*)?:?=\s*(-?\d+)\s*(?:#.*)?$", text, re.M)}


def gd_funcs(text):
    return set(re.findall(r"^(?:static\s+)?func\s+(\w+)\s*\(", text, re.M))


def gd_enum(text, name):
    """enum Имя { A, B, C } → ["A", "B", "C"]; нет — None."""
    m = re.search(r"^enum\s+%s\s*\{([^}]*)\}" % name, text, re.M)
    if not m:
        return None
    return [x.split("=")[0].strip() for x in m.group(1).split(",") if x.strip()]


def check_sources(expect):
    """Модель и код говорят об одном: константы, функции, флаги по умолчанию, самопроверка читает эталон."""
    hearts = read(HEARTS_GD)
    expect(hearts is not None, "нет scripts/hearts.gd")
    if hearts is not None:
        consts = gd_consts(hearts)
        expect(consts.get("STARS_MAX") == STARS_MAX,
               "STARS_MAX в hearts.gd = %s, в модели %d" % (consts.get("STARS_MAX"), STARS_MAX))
        funcs = gd_funcs(hearts)
        expect(funcs == GD_FUNCS, "функции hearts.gd не как в модели: лишние %s, нет %s" % (
            sorted(funcs - GD_FUNCS), sorted(GD_FUNCS - funcs)))
    ysdk = read(YSDK_GD)
    expect(ysdk is not None, "нет autoload/ysdk.gd")
    if ysdk is not None:
        consts = gd_consts(ysdk)
        for name, want in PLAN_DEFAULTS.items():
            expect(consts.get(name) == want, "ysdk.gd: %s = %s, PLAN 20.1 — %d" % (name, consts.get(name), want))
        defaults = (consts.get("DEFAULT_HEARTS"), consts.get("DEFAULT_REVIVE_MAX"),
                    consts.get("DEFAULT_REVIVE_FREE_ON_FAIL"))
        expect(any(sc[1:4] == defaults for sc in SCENARIOS),
               "нет сценария с флагами по умолчанию (hearts, revive_max, revive_free_on_fail = %s)" % (defaults,))
    selftest = read(SELFTEST_GD)
    expect(selftest is not None, "нет tests/selftest.gd")
    if selftest is not None:
        expect('"res://tests/hearts_expected.txt"' in selftest and "\t_test_hearts()" in selftest,
               "selftest не читает tests/hearts_expected.txt (_test_hearts не вызывается)")
        body = selftest.split("func _hearts_run(", 1)[-1].split("\nfunc ", 1)[0]
        for ev in EVENTS:
            expect('"%s":' % ev in body, "selftest _hearts_run не знает событие %s" % ev)
        test = selftest.split("func _test_hearts()", 1)[-1].split("\nfunc ", 1)[0]
        expect('f[0] == "W"' in test and 'f[0] == "D"' in test,
               "selftest _test_hearts не читает строки W и D (окно «Сердца закончились»)")
    panel = read(PANEL_GD)
    expect(panel is not None, "нет scenes/ui/hearts_panel.gd")
    if panel is not None:
        expect(gd_enum(panel, "Offer") == OFFERS, "hearts_panel.gd: enum Offer %s, в модели %s" % (
            gd_enum(panel, "Offer"), OFFERS))
        expect(gd_enum(panel, "After") == AFTERS, "hearts_panel.gd: enum After %s, в модели %s" % (
            gd_enum(panel, "After"), AFTERS))
        missing = PANEL_FUNCS - set(re.findall(r"^static\s+func\s+(\w+)\s*\(", panel, re.M))
        expect(not missing, "hearts_panel.gd: нет static func %s" % sorted(missing))


def build():
    lines = [
        "# Эталон сердец (20.1a) для selftest: python3 tools/hearts_model.py --write. Руками не править.",
        "# M уровень задача_дня лаборатория hearts hearts_from_level = сердец",
        "# R имя сердец revive_max revive_free_on_fail события = шаг ... stars=N; шаг — осталось.ошибок.возрождений.ОВБР",
        "# W можно_возродиться реклама_есть бесплатное_можно = ПРЕДЛОЖЕНИЕ (окно 20.1b, HeartsPanel.Offer)",
        "# D награда итог_рекламы бесплатное_можно = ДЕЙСТВИЕ (окно 20.1b, HeartsPanel.After)",
    ]
    for lvl in MAX_FOR_LEVELS:
        for daily in (0, 1):
            for lab in (0, 1):
                for hearts in MAX_FOR_HEARTS:
                    for frm in MAX_FOR_FROM:
                        n = Hearts.max_for(lvl, bool(daily), bool(lab), hearts, frm)
                        lines.append("M %d %d %d %d %d = %d" % (lvl, daily, lab, hearts, frm, n))
    for name, n_max, rmax, free, events in SCENARIOS:
        res, _h, _hints = run(n_max, rmax, bool(free), events)
        lines.append("R %s %d %d %d %s = %s" % (name, n_max, rmax, free, events, res))
    for can_revive in (0, 1):
        for ad in (0, 1):
            for can_free in (0, 1):
                lines.append("W %d %d %d = %s" % (can_revive, ad, can_free,
                                                   offer_for(bool(can_revive), bool(ad), bool(can_free))))
    for rewarded in (0, 1):
        for result in AD_RESULTS:
            for can_free in (0, 1):
                lines.append("D %d %s %d = %s" % (rewarded, result, can_free,
                                                  after_ad(bool(rewarded), result, bool(can_free))))
    return "\n".join(lines) + "\n"


def main():
    ok = True

    def expect(cond, what):
        nonlocal ok
        if not cond:
            ok = False
            print("  ✗", what)

    # Правила, которые обещает PLAN 20.1 (а не только «как написано в коде»).
    expect(Hearts.max_for(3, False, False, 3, 4) == 0, "уровни 1–3 — без сердец (страховка обучения)")
    expect(Hearts.max_for(4, False, False, 3, 4) == 3, "с 4-го уровня — 3 сердца")
    expect(Hearts.max_for(1, True, False, 3, 4) == 3, "задача дня — с сердцами всегда")
    expect(Hearts.max_for(50, False, True, 3, 4) == 0, "«Лаборатория» — без сердец")
    expect(Hearts.max_for(50, True, False, 0, 4) == 0, "флаг hearts = 0 — без предела")
    for name, n_max, rmax, free, events in SCENARIOS:
        res, h, hints = run(n_max, rmax, bool(free), events)
        st = h.stars(hints)
        expect(1 <= st <= STARS_MAX, "%s: звёзд %d" % (name, st))
        expect(h.left <= max(h.max_hearts, 0) + h.revives, "%s: сердец больше, чем было и дали" % name)
        expect(h.left >= 0, "%s: сердец меньше нуля" % name)
        expect(h.revives <= rmax, "%s: возрождений %d при revive_max %d" % (name, h.revives, rmax))
        if not h.is_limited():
            expect(not h.is_out() and h.revives == 0, "%s: без предела сердца кончились или было возрождение" % name)
        if h.revives == 0 and h.max_hearts == STARS_MAX and hints == 0:
            expect(st == max(h.left, 1), "%s: звёзды (%d) не равны оставшимся сердцам (%d)" % (name, st, h.left))
        print("  %-26s %-11s → %s" % (name, events, res))
    expect(run(3, 3, True, "LLLFLF")[0].split()[-2].endswith("0"), "бесплатное продолжение — только раз за попытку")
    expect(run(3, 3, True, "LLLA")[0].endswith("stars=1"), "после возрождения — 1 звезда")
    # Окно «Сердца закончились» (20.1b): правила PLAN 20.1.
    expect(all(offer_for(False, ad, fr) == "LIMIT" for ad in (False, True) for fr in (False, True)),
           "окно: возрождения исчерпаны — только «Заново»")
    expect(offer_for(True, True, False) == "AD" and offer_for(True, True, True) == "AD",
           "окно: реклама есть — «Продолжить» за рекламу")
    expect(offer_for(True, False, True) == "FREE" and offer_for(True, False, False) == "NO_AD",
           "окно: рекламы нет — бесплатно, пока можно, потом «Заново»")
    expect(all(after_ad(False, "closed", fr) == "NOTE_CLOSED" for fr in (False, True)),
           "окно: закрыл рекламу до награды — окно остаётся, бесплатного нет")
    expect(all(after_ad(False, r, True) == "FREE" and after_ad(False, r, False) == "NOTE_FAILED"
               for r in ("not_shown", "timeout")), "окно: реклама не показалась — бесплатно один раз, потом пояснение")
    expect(all(after_ad(True, r, fr) == "REVIVE" for r in AD_RESULTS for fr in (False, True)),
           "окно: награда пришла — возрождение")
    # Как в игре: 3 сердца, revive_max 3, бесплатное разрешено; реклама не показалась → бесплатно, снова кончились и
    # снова не показалась → пояснение, досмотрел → возрождение, третий раз → возрождение, дальше — предел.
    h = Hearts()
    h.reset(3)
    flow = []
    for ad_result in ("not_shown", "not_shown", "rewarded", "closed", "rewarded", None):
        while not h.is_out():
            h.lose()
        o = offer_for(h.can_revive(3), True, h.can_continue_free(True))
        flow.append(o)
        if o != "AD":
            break
        a = after_ad(ad_result == "rewarded", ad_result, h.can_continue_free(True))
        flow.append(a)
        if a in ("REVIVE", "FREE"):
            expect(h.try_revive(3, a == "FREE", True), "окно: %s не сработало" % a)
    expect(flow == ["AD", "FREE", "AD", "NOTE_FAILED", "AD", "REVIVE", "AD", "NOTE_CLOSED", "AD", "REVIVE", "LIMIT"],
           "окно, как в игре: %s" % flow)
    print("  окно, как в игре: %s" % " ".join(flow))

    check_sources(expect)

    text = build()
    if "--write" in sys.argv:
        with open(OUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("записан %s (%d строк)" % (os.path.relpath(OUT, ROOT), text.count("\n")))
    else:
        try:
            with open(OUT, encoding="utf-8") as f:
                fresh = f.read() == text
        except FileNotFoundError:
            fresh = False
        expect(fresh, "tests/hearts_expected.txt устарел или его нет — python3 tools/hearts_model.py --write")

    print("модель: всё сходится" if ok else "модель: ЕСТЬ ОШИБКИ")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
