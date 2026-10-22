#!/usr/bin/env python3
"""Модель решателя автоснижения качества (этап 14.7b) — та же логика, что в scripts/quality_governor.gd.

Решатель кормится длительностью кадров (push(dt)) и отвечает новым уровнем качества (2 «высокое»,
1 «среднее», 0 «низкое») или None — «ничего не менять». Правила:
- кадры дольше HITCH (сборка мусора, вкладка в фоне, загрузка) не считаются;
- первые WARMUP секунд после старта / смены сцены (reset) — не считаются (компиляция шейдеров);
- кадры копятся в окно WINDOW секунд; к/с окна = кадров / время;
- окно ниже FPS_LOW BAD_WINDOWS раз подряд — уровень вниз (если есть куда); так начинается «спуск»,
  запоминаются его исходные уровень и к/с;
- после любой смены: SETTLE секунд не считаем, затем одно окно проверки:
  * после шага вниз стало ≥ FPS_LOW — спуск удался, остаёмся;
  * всё ещё мало и есть куда — спуск продолжается (следующее плохое окно — ещё шаг). Отдельный шаг может
    не дать ничего: браузер подгоняет кадр под vsync, и 22 мс работы — те же 30 к/с, что и 28 мс;
  * дошли до низкого, а к/с не выросли на GAIN от исходных — узкое место не в эффектах (браузер сам
    держит 30 к/с — энергосбережение iOS, — или занят процессор): откат к исходному уровню и «замок»
    до конца сессии;
  * проба вверх просела ниже FPS_LOW — назад вниз, проб больше нет;
- вверх — одна проба за сессию: на сниженном уровне PROBE_AFTER секунд подряд окна ≥ FPS_GOOD.

Запуск: python3 tools/quality_model.py — прогоняет сценарии и печатает, что решил решатель.
Числа — как в JuiceConfig (группа «Качество»).
"""
import random

FPS_LOW = 50.0
FPS_GOOD = 57.0
WINDOW = 2.0
BAD_WINDOWS = 2
WARMUP = 1.5
SETTLE = 1.0
GAIN = 0.08
PROBE_AFTER = 60.0
HITCH = 0.25
LEVEL_MAX = 2

WARM, MEASURE, SETTLING, VERIFY, LOCKED = "warm", "measure", "settle", "verify", "locked"


class Governor:
    def __init__(self, level=LEVEL_MAX):
        self.level = level
        self.phase = WARM
        self.locked = False
        self.probed = False
        self.wait = 0.0      # разогрев / пауза после смены
        self.w_time = 0.0
        self.w_frames = 0
        self.bad = 0
        self.good_time = 0.0
        self.dir = 0
        self.chain = False      # идёт спуск
        self.chain_level = 0    # уровень до спуска
        self.chain_fps = 0.0    # к/с до спуска
        self.last_fps = 0.0

    # Новая сцена, окно вернулось в фокус и т. п.: разогрев заново, окно — с нуля (замок остаётся).
    def reset(self):
        self.phase = LOCKED if self.locked else WARM
        self.wait = 0.0
        self._clear_window()
        self.bad = 0
        self.good_time = 0.0

    # Пропуск (шторка, окно не в фокусе): незаконченное окно выбросить, чтобы оно не перешагнуло дыру.
    def skip(self):
        self._clear_window()

    def _clear_window(self):
        self.w_time = 0.0
        self.w_frames = 0

    def push(self, dt):
        if self.phase == LOCKED or dt <= 0.0 or dt > HITCH:
            return None
        if self.phase in (WARM, SETTLING):
            self.wait += dt
            limit = WARMUP if self.phase == WARM else SETTLE
            if self.wait >= limit:
                self.phase = VERIFY if self.phase == SETTLING else MEASURE
                self.wait = 0.0
                self._clear_window()
            return None
        self.w_time += dt
        self.w_frames += 1
        if self.w_time < WINDOW:
            return None
        fps = self.w_frames / self.w_time
        self.last_fps = fps
        self._clear_window()
        if self.phase == VERIFY:
            return self._verify(fps)
        return self._measure(fps)

    def _measure(self, fps):
        self.bad = self.bad + 1 if fps < FPS_LOW else 0
        if fps >= FPS_LOW:
            self.chain = False
        if self.bad >= BAD_WINDOWS and self.level > 0:
            if not self.chain:
                self.chain = True
                self.chain_level = self.level
                self.chain_fps = fps
            return self._change(-1)
        if self.level < LEVEL_MAX and not self.probed and fps >= FPS_GOOD:
            self.good_time += WINDOW
            if self.good_time >= PROBE_AFTER:
                self.probed = True
                return self._change(+1)
        else:
            self.good_time = 0.0
        return None

    def _verify(self, fps):
        self.phase = MEASURE
        self.bad = 0
        self.good_time = 0.0
        if fps >= FPS_LOW:
            self.chain = False
            return None
        if self.dir > 0:
            self.level -= 1  # проба вверх не выдержала
            return self.level
        if self.level > 0:
            self.bad = 1  # спуск продолжается: следующее плохое окно — ещё шаг
            return None
        self.chain = False
        if fps < self.chain_fps * (1.0 + GAIN):
            self.locked = True  # весь спуск ничего не дал — эффекты ни при чём
            self.phase = LOCKED
            self.level = self.chain_level
            return self.level
        return None  # помогло, хоть и не до порога — остаёмся на низком

    def _change(self, d):
        self.dir = d
        self.level += d
        self.phase = SETTLING
        self.wait = 0.0
        self.bad = 0
        self.good_time = 0.0
        return self.level


# --- Сценарии --------------------------------------------------------------------------------------

def run(name, seconds, frame_fn, start_level=LEVEL_MAX, events=None, seed=1):
    """frame_fn(t, level, rng) -> dt кадра. events: {секунда: 'reset' | 'skip'}."""
    rng = random.Random(seed)
    g = Governor(start_level)
    t = 0.0
    log = []
    pending = sorted((events or {}).items())
    while t < seconds:
        while pending and pending[0][0] <= t:
            what = pending.pop(0)[1]
            getattr(g, what)()
        dt = frame_fn(t, g.level, rng)
        t += dt
        new = g.push(dt)
        if new is not None:
            log.append((round(t, 1), new, round(g.last_fps, 1)))
    print(f"{name}: уровень {g.level}, замок {g.locked}, смены {log}")
    return g, log


def vsync(fps_cap, cost_by_level, noise=0.08):
    """Кадр — работа cost (с по уровню) с шумом, округлённая вверх до интервала vsync."""
    period = 1.0 / fps_cap

    def f(t, level, rng):
        work = cost_by_level[level] * (1.0 + rng.uniform(-noise, noise))
        n = max(1, -(-work // period))  # ceil
        return n * period
    return f


def main():
    ok = True

    def expect(cond, what):
        nonlocal ok
        if not cond:
            ok = False
            print("  ОШИБКА:", what)

    # 1. Сильный телефон: 60 к/с ровно — ничего не трогаем.
    g, log = run("ровные 60", 300, vsync(60, {2: 0.010, 1: 0.008, 0: 0.006}))
    expect(g.level == 2 and not log, "ровные 60: уровень сменился")

    # 2. Слабый: высокое 35 к/с, среднее 45, низкое 60 — вниз до 0, проба вверх проваливается, остаёмся на 0.
    g, log = run("слабый 35/45/60", 300, vsync(60, {2: 1 / 36, 1: 1 / 46, 0: 0.0150}, noise=0.02))
    expect(g.level == 0 and not g.locked, "слабый: не дошли до низкого")
    expect([lv for _, lv, _ in log][:2] == [1, 0], "слабый: шаги не 2→1→0: %s" % log)
    expect(g.probed, "слабый: пробы вверх не было")

    # 3. Средний: высокое 42 к/с, среднее 60 — остаётся на среднем, проба вверх → назад.
    g, log = run("средний 42/60", 300, vsync(60, {2: 1 / 43, 1: 0.0140, 0: 0.010}, noise=0.03))
    expect(g.level == 1 and not g.locked, "средний: не остались на среднем")

    # 4. «Потолок» 30 к/с (энергосбережение): снижение не помогает — откат и замок на высоком.
    g, log = run("потолок 30", 300, lambda t, lv, rng: (1 / 30) * (1 + rng.uniform(-0.01, 0.01)))
    expect(g.level == 2 and g.locked, "потолок: не вернулись на высокое с замком")
    expect([lv for _, lv, _ in log] == [1, 0, 2], "потолок: смены %s (ждали 2→1→0 и откат)" % log)

    # 5. Рывки: 60 к/с, каждые 3 с «ход» — 6 кадров по 50 мс, раз в 20 с — 0,6 с (вкладка) — не снижаем.
    def hitches(t, level, rng):
        ph = t % 3.0
        if t % 20.0 < 0.02:
            return 0.6
        return 0.050 if ph < 0.3 else 1 / 60
    g, log = run("рывки", 300, hitches)
    expect(g.level == 2 and not log, "рывки: уровень сменился: %s" % log)

    # 6. 120 Гц, тяжёлые моменты 75 к/с — выше порога, не трогаем.
    g, log = run("120 Гц", 300, vsync(120, {2: 0.012, 1: 0.009, 0: 0.007}, noise=0.2))
    expect(g.level == 2 and not log, "120 Гц: уровень сменился")

    # 7. Победа на среднем телефоне: 3 с по 40 к/с раз в 30 с (конфетти), иначе 60 — одно плохое окно
    #    не опускает; два подряд (3 с перекрывают 2 окна) — может опустить, проба вернёт.
    def wins(t, level, rng):
        heavy = (t % 30.0) < 3.0
        cost = {2: 1 / 40, 1: 1 / 55, 0: 1 / 62}[level] if heavy else 0.012
        return max(cost, 1 / 60)
    g, log = run("победы", 300, wins)
    expect(g.level >= 1, "победы: опустились до низкого: %s" % log)

    # 8. Нагрев посреди сессии: 60 к/с 120 с, затем высокое 42 — вниз на среднее (60), там и остаться.
    def thermal(t, level, rng):
        if t < 120:
            return 1 / 60
        return max({2: 1 / 42, 1: 1 / 61, 0: 1 / 70}[level], 1 / 60)
    g, log = run("нагрев", 300, thermal)
    expect(g.level == 1 and log and log[0][0] > 120, "нагрев: %s" % log)

    # 9. Смена сцены сбрасывает окно и разогрев; замок переживает смену сцены.
    g, log = run("потолок + смены сцены", 200, lambda t, lv, rng: 1 / 30, events={50: "reset", 100: "reset"})
    expect(g.level == 2 and g.locked and len(log) == 3, "замок не пережил смену сцены: %s" % log)

    # 11. Без vsync-ступенек (к/с = 1 / работа): 38 → 46 → 58 — спуск до низкого, там и остаться.
    g, log = run("без ступенек 38/46/58", 300,
                 lambda t, lv, rng: {2: 1 / 38, 1: 1 / 46, 0: 1 / 58}[lv] * (1 + rng.uniform(-0.03, 0.03)))
    expect(g.level == 0 and not g.locked, "без ступенек: %s" % log)

    # 12. Слабо помогает (30 → 31 → 32): ниже GAIN — откат и замок.
    g, log = run("почти не помогает", 300, lambda t, lv, rng: {2: 1 / 30, 1: 1 / 31, 0: 1 / 32}[lv])
    expect(g.level == 2 and g.locked, "почти не помогает: %s" % log)

    # 10. Сохранённый уровень 1 на сильном телефоне: проба вверх через ~60 с — и остаёмся на высоком.
    g, log = run("сохранён 1, телефон сильный", 200, vsync(60, {2: 0.010, 1: 0.008, 0: 0.006}), start_level=1)
    expect(g.level == 2 and len(log) == 1, "проба вверх не вернула высокое: %s" % log)

    print("модель: всё сходится" if ok else "модель: ЕСТЬ ОШИБКИ")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
