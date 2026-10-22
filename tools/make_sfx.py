#!/usr/bin/env python3
"""Звуки игры под материал «Мармелад» (этап 15, PLAN 15.1–15.3; docs/STYLE.md, раздел 16), версия 3.

Все звуки — синтез: мягкие, округлые, «желейные», без резких верхов; ноты — до мажор, как музыка.
44,1 кГц, моно, 16 бит, тишина на краях (без щелчков). Результат одинаковый при каждом запуске.

Версия 3 (10.10) — звуки из тех же инструментов, что и музыка (tools/compose_music.py, версия 3):
  * маримба, колокольчик, окарина, электропиано и бочка — функции синтеза музыки (общий код, не копия):
    моды бруска и резонатор у маримбы, подъезд к ноте и дыхание у окарины, язычок и звукосниматель
    у электропиано. Ноты звуков ровно в строе (compose_music.DETUNE = 0), высота не «гуляет»;
  * «желе» вместо голых синусов: мягкое тело из трёх мод (как у мембраны), влажная текстура — рой мелких
    пузырьков (у каждого тон растёт, как у всплывающего пузырька), а не полоса шума; «вжух» — шум
    с турбулентностью; «фьють» и вихрь подсказки — тон с дыханием, как у окарины;
  * общая короткая комната — та же, что у ударных в музыке (RT ≈ 0,5 с), у каждого звука свой посыл.
Длительности, высоты и тайминги — как в версии 2 (искра подсказки 0,42 с, волна победы, джингл).
Версия 3.1 (10.10, сессия 107) — джингл мягче (был резким): затакт G5-C6-E6 тихий и мягкий (на 4–5 dB ниже аккорда,
а не вровень с ним), у нот мягкая колотушка, аккорд взят арпеджато снизу вверх, колокольчики тише и после аккорда,
верх джингла приглушён. Остальные звуки не менялись.
Версия 3.2 (12.10) — подсказка короче: блок сразу летит на место за hint_float_time (0,3 с, без отдельной искры
0,42 с), перелив и вихрь — за время полёта, «искры» — в миг касания, колокольчиков прилёта нет. Остальные — как в 3.1.

    python3 tools/make_sfx.py            # перезаписать assets/sfx/*.wav и autoload/audio.tscn (громкость — TARGET)
    python3 tools/make_sfx.py --check    # только напечатать параметры (длина, пик, «телефонная» громкость)
    python3 tools/sfx_preview.py         # затем: предпрослушка уровня под музыку (docs/sfx/*.mp3)

Ноты-сэмплы (высоту в игре меняет pitch_scale, см. autoload/audio.gd):
  note.wav  — маримба C5: нота постановки (Audio.place_semitones: пентатоника G4…C6);
  line.wav  — перелив C5-G5-C6 (корень, квинта, октава): при сдвиге на 0/2/4/5/7 полутонов — в до мажоре;
  star.wav  — колокольчик C6: звёзды до-ми-соль (JuiceConfig.star_semitones).
Прежние звуки: до этапа 15 — docs/sfx_old/ (make_sfx_v1.py), версия 2 — docs/sfx_old/v2/ (make_sfx_v2.py).

Нужны numpy и scipy.
"""
import os
import re
import sys
import wave

import numpy as np
from scipy.signal import butter, oaconvolve, sosfilt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compose_music as cm  # noqa: E402  — инструменты музыки

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "sfx")
SEED = 20261010
assert cm.SR == SR
cm.DETUNE = 0.0          # ноты звуков — ровно в строе


def rng(name):
    """Свой детерминированный шум у каждого звука: правка одного не меняет другие."""
    return np.random.default_rng(SEED + sum(ord(c) * (i + 1) for i, c in enumerate(name)))


def use(name):
    """Инструментам музыки — свой генератор случайностей на каждый звук."""
    cm.rng = rng("cm" + name)


# --- Ноты ------------------------------------------------------------------------

A4 = 440.0
NOTE_INDEX = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}


def midi(name):
    """'C5' -> 72 (только белые клавиши — до мажор)."""
    return 69 + NOTE_INDEX[name[0]] + 12 * (int(name[1:]) - 4)


def hz(name):
    """'C5' -> 523.25 Гц."""
    return A4 * 2 ** ((midi(name) - 69) / 12)


# --- Основа ------------------------------------------------------------------------

def t_axis(dur):
    return np.arange(int(round(SR * dur))) / SR


def env(t, attack, decay):
    """Атака attack с (полусинус), затем экспоненциальный спад с постоянной decay."""
    a = np.where(t < attack, np.sin(0.5 * np.pi * np.clip(t / max(attack, 1e-6), 0, 1)), 1.0)
    return a * np.exp(-np.maximum(t - attack, 0.0) / decay)


def glide(t, f0, f1, time, curve="exp"):
    """Частота f0 -> f1 за time с (дальше f1); фаза интегрируется — без разрывов."""
    k = np.clip(t / max(time, 1e-6), 0, 1)
    if curve == "exp":
        f = f0 * (f1 / f0) ** k
    else:
        f = f0 + (f1 - f0) * (1 - (1 - k) ** 2)
    return f


def osc(freq, phase=0.0):
    """Синус по массиву мгновенных частот."""
    return np.sin(2 * np.pi * np.cumsum(freq) / SR + phase)


def wobble(t, rate, depth, fade, phase=0.0):
    """Множитель частоты «желе»: дрожание rate Гц глубиной depth (доля), гаснет за fade с."""
    return 1.0 + depth * np.sin(2 * np.pi * rate * t + phase) * np.exp(-t / fade)


def lowpass(x, cutoff, order=2):
    return sosfilt(butter(order, cutoff, "low", fs=SR, output="sos"), x)


def highpass(x, cutoff, order=2):
    return sosfilt(butter(order, cutoff, "high", fs=SR, output="sos"), x)


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def silence(dur):
    return np.zeros(len(t_axis(dur)))


def noise(name, n):
    return rng(name).standard_normal(n)


def place_at(out, x, at):
    """Добавить x в out с момента at, с."""
    i = int(round(at * SR))
    j = min(len(out), i + len(x))
    if j > i:
        out[i:j] += x[: j - i]
    return out


def smooth_random(r, n, rate):
    """Плавная случайная кривая (σ≈1), меняется примерно rate раз в секунду."""
    m = int(n / SR * rate) + 3
    return np.interp(np.arange(n) / SR * rate, np.arange(m), r.standard_normal(m))


# --- Инструменты музыки (compose_music) -------------------------------------------

def soft_mallet(x, attack):
    """Мягкая колотушка: нота набирает громкость за attack с (а не за доли миллисекунды) — удар без щелчка."""
    t = t_axis(len(x) / SR)
    return x * np.sin(0.5 * np.pi * np.clip(t / attack, 0, 1)) ** 2


def high_shelf(x, f0, gain_db):
    """Плавно приглушить верх: всё выше f0 Гц — на gain_db (полка 1-го порядка, без резонанса)."""
    lo = lowpass(x, f0, order=1)
    return lo + (x - lo) * 10 ** (gain_db / 20)


def marimba(note, v, damp=None, name="m"):
    """Маримба музыки; damp — приглушить брусок рукой (с), чтобы частая нота не тянулась."""
    use(name)
    x = cm.syn_marimba(midi(note), 0.0, v)
    if damp:
        x = x * np.exp(-t_axis(len(x) / SR) / damp)
    return x


def bell(note, v, damp=None, name="b"):
    """Колокольчик музыки (металлофон)."""
    use(name)
    x = cm.syn_bell(midi(note), 0.0, v)
    if damp:
        x = x * np.exp(-t_axis(len(x) / SR) / damp)
    return x


def ocarina(note, dur, v, droop_cents=0.0, name="o"):
    """Окарина музыки; droop_cents — «опускание» тона к концу (вниз, в центах)."""
    use(name)
    x = cm.syn_ocarina(midi(note), dur, v)
    if droop_cents:
        t = t_axis(len(x) / SR)
        cents = -droop_cents * np.clip(t / (dur + 0.07), 0, 1) ** 2
        pos = np.cumsum(2 ** (cents / 1200))           # читаем медленнее — тон ниже
        pos = pos[pos < len(x) - 1]
        x = np.interp(pos, np.arange(len(x)), x)
    return x


def epiano(note, dur, v, name="e"):
    """Электропиано музыки (аккорды)."""
    use(name)
    return cm.syn_epiano(midi(note), dur, v)


def kick(v, name="k"):
    """Бочка музыки."""
    use(name)
    return cm.syn_kick(v)


# --- «Желе» -------------------------------------------------------------------------

JELLY_MODES = [(1.0, 1.0, 1.0), (1.594, 0.20, 0.5), (2.136, 0.07, 0.3)]   # мягкое тело: моды мембраны


def jelly(t, f, attack, decay, r, levels=1.0):
    """Тело «желе»: основная мода по кривой частоты f и две слабые неровные моды над ней."""
    out = np.zeros_like(t)
    for k, (ratio, amp, dk) in enumerate(JELLY_MODES):
        a = amp if k == 0 else amp * levels
        out += a * osc(f * ratio * (1 + r.normal(0, 0.004)), r.uniform(0, 0.4)) * env(t, attack, decay * dk)
    return out


def fizz(name, dur, at, spread, count, lo, hi):
    """Рой мелких пузырьков вместо полосы шума: count затухающих тонов в полосе lo…hi, моменты — около
    at (разброс spread с). У каждого тон растёт (всплывает), мелкий — выше, тише и короче."""
    r = rng(name)
    out = silence(dur)
    for _ in range(count):
        f0 = np.exp(r.uniform(np.log(lo), np.log(hi)))
        tau = 1 / (np.pi * f0 * r.uniform(0.02, 0.05))        # затухание пузырька в воде
        tt = t_axis(min(6 * tau, 0.08))
        f = f0 * (1 + r.uniform(0.1, 0.35) * tt / (3 * tau))
        g = osc(f, r.uniform(0, 6.28)) * np.exp(-tt / tau) * (1 - np.exp(-tt / 0.0003))
        place_at(out, g * r.uniform(0.4, 1.0) * (lo / f0) ** 0.4, at + abs(r.normal(0, spread)))
    return out / (np.abs(out).max() + 1e-12)


def whoosh(name, t, lo0, hi0, lo1, hi1, time):
    """«Вжух»: воздух из полосы lo0…hi0 в lo1…hi1 за time с, с турбулентностью (неровная плотность)."""
    r = rng(name)
    n = r.standard_normal(len(t))
    a = bandpass(n, lo0, hi0)
    b = bandpass(n, lo1, hi1)
    k = np.clip(t / time, 0, 1)
    x = a * (1 - k) + b * k
    x *= 1 + 0.45 * smooth_random(r, len(t), 60)
    x = x / (np.abs(x).max() + 1e-12)
    return x * np.sin(np.pi * k) ** 2


def whistle(name, t, f, attack, decay):
    """Тон с дыханием (как у окарины): почти синус + узкая полоса воздуха вокруг тона + «чифф» в атаке."""
    r = rng(name)
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.06 * np.sin(2 * ph + 0.4) + 0.02 * np.sin(3 * ph + 1.1)
    air = lowpass(r.standard_normal(len(t)), 120)
    air = air / (np.std(air) + 1e-12) * np.sin(ph + 1.3) * 0.12        # шум вокруг тона, ≈ −20 дБ
    chiff = highpass(r.standard_normal(len(t)), 1500) * np.exp(-t / 0.015) * 0.05
    return (tone + air) * env(t, attack, decay) + chiff * np.clip(t / 0.002, 0, 1)


def wood(t, f, decay, r):
    """«Ток»: короткий деревянный брусок (основная + неровная 2,76×) и мягкий удар."""
    x = osc(f) * env(t, 0.001, decay)
    x += 0.25 * osc(f * 2.76 * (1 + r.normal(0, 0.005))) * env(t, 0.0008, decay * 0.45)
    k = int(0.006 * SR)
    x[:k] += 0.15 * lowpass(r.standard_normal(k), 3000) * np.exp(-t[:k] / 0.0012)
    return x


# --- Комната --------------------------------------------------------------------------

_IR = []


def room(x, wet, tail=0.25):
    """Та же короткая комната, что у ударных музыки (RT ≈ 0,5 с); хвост — tail с сверху."""
    if not _IR:
        cm.rng = np.random.default_rng(SEED)
        _IR.append(cm.room_ir(length=1.0, er_share=0.6, rt_scale=cm.DRUM_ROOM_RT)[0])
    y = np.concatenate([x, np.zeros(int(tail * SR))])
    if wet > 0:
        w = oaconvolve(y, _IR[0])[: len(y)]
        w = lowpass(highpass(w, 180), 8000)
        y = y + wet * w
    return y


def finish(x, peak_db, fade_ms=6.0, hp=60.0, lp=10000.0):
    """Убрать постоянную составляющую и самый низ, мягкие края, нормализовать пик."""
    x = highpass(x, hp)
    x = lowpass(x, lp)
    n_in = 16
    n_fade = max(1, int(SR * fade_ms / 1000))
    x[:n_in] *= np.linspace(0, 1, n_in)
    x[-n_fade:] *= np.linspace(1, 0, n_fade) ** 2
    return x / (np.abs(x).max() + 1e-12) * 10 ** (peak_db / 20)


# --- Звуки -------------------------------------------------------------------------

def make_pick():
    """Подъём: мягкое «блюп» вверх — желе отлипло от лотка."""
    r = rng("pick")
    t = t_axis(0.13)
    f = glide(t, 300, 640, 0.06) * wobble(t, 26, 0.03, 0.05)
    body = jelly(t, f, 0.004, 0.04, r)
    slurp = fizz("pick", 0.13, 0.004, 0.018, 7, 900, 2600) * env(t, 0.004, 0.03) * 0.22
    return finish(room(body + slurp, 0.08, 0.08), -4.0, fade_ms=20)


def make_place():
    """Удар: мягкий «плюх» — желе легло на поле (без ноты: нота — note.wav)."""
    r = rng("place")
    t = t_axis(0.22)
    f = glide(t, 210, 105, 0.05) * wobble(t, 17, 0.06, 0.06)
    thump = jelly(t, f, 0.002, 0.06, r)
    tok = wood(t, glide(t, 600, 380, 0.03), 0.026, r) * 0.9         # «ток» — его и слышно в телефоне
    splat = fizz("place", 0.22, 0.003, 0.014, 16, 450, 2000) * env(t, 0.002, 0.03) * 0.4
    jiggle = jelly(t, 330 * wobble(t, 19, 0.08, 0.05), 0.03, 0.05, r, 0.6) * 0.18 * (t > 0.02)
    return finish(room(thump + tok + splat + jiggle, 0.10, 0.12), -3.0, fade_ms=25)


def make_note():
    """Нота постановки: маримба музыки C5, приглушённая рукой (выше и ниже — pitch_scale, пентатоника G4…C6)."""
    x = marimba("C5", 0.85, damp=0.25, name="note")[: int(0.75 * SR)]
    return finish(room(x, 0.16, 0.2), -3.0, fade_ms=120)


def make_rotate():
    """Поворот: короткое «вжух» и «виль» желе на E5 (с деревом маримбы)."""
    r = rng("rotate")
    dur = 0.16
    t = t_axis(dur)
    swish = whoosh("rotate", t, 700, 1800, 1500, 3800, 0.09)
    tt = t_axis(dur - 0.045)
    wib = jelly(tt, hz("E5") * wobble(tt, 22, 0.05, 0.05), 0.01, 0.035, r, 0.5)
    wib = 0.7 * wib + 0.5 * marimba("E5", 0.45, damp=0.04, name="rotate")[: len(tt)] / 0.33
    wib = place_at(np.zeros_like(t), wib, 0.045)
    return finish(room(0.45 * swish + 0.6 * wib, 0.08, 0.1), -5.0, fade_ms=20)


def make_miss():
    """Промах (блок вернулся в лоток): тихое «блюк» вниз — не наказывает."""
    r = rng("miss")
    t = t_axis(0.2)
    f = glide(t, 430, 250, 0.09) * wobble(t, 15, 0.05, 0.08)
    x = jelly(t, f, 0.006, 0.055, r)
    x += fizz("miss", 0.2, 0.006, 0.02, 4, 500, 1200) * env(t, 0.006, 0.04) * 0.08
    return finish(room(lowpass(x, 2500), 0.08, 0.1), -6.0, fade_ms=20)


def make_error():
    """Тупик и «подсказке некуда»: мягкое «у-у» окариной музыки вниз (A4 -> E4), вторая нота опускается."""
    out = silence(0.5)
    place_at(out, ocarina("A4", 0.08, 0.55, name="error1"), 0.0)
    place_at(out, 0.95 * ocarina("E4", 0.2, 0.6, droop_cents=50, name="error2"), 0.12)
    return finish(room(out, 0.18, 0.2), -4.0, fade_ms=60)


def make_line():
    """Линия: перелив C5-G5-C6 маримбой и колокольчиком + тихий воздух. Только корень, квинта и октава —
    сдвиг на 0/2/4/5/7 полутонов (сила хода) остаётся в до мажоре."""
    dur = 0.75
    out = silence(dur)
    t = t_axis(dur)
    for k, (n, at) in enumerate([("C5", 0.0), ("G5", 0.035), ("C6", 0.07)]):
        place_at(out, 0.8 * marimba(n, 0.75, damp=0.15, name="line%d" % k), at)
        up = {"C5": "C6", "G5": "G6", "C6": "C7"}[n]
        place_at(out, 0.45 * bell(up, 0.6, damp=0.45, name="lineb%d" % k), at + 0.004)
    shimmer = silence(dur)
    place_at(shimmer, 0.6 * bell("G6", 0.35, damp=0.35, name="lines1"), 0.0)
    place_at(shimmer, 0.5 * bell("C7", 0.3, damp=0.3, name="lines2"), 0.0)
    place_at(out, 0.3 * shimmer * (0.75 + 0.25 * np.sin(2 * np.pi * 14 * t)), 0.07)
    air = bandpass(noise("line", len(t)), 3500, 8000) * env(t, 0.03, 0.12) * 0.05
    return finish(room(out + air, 0.18, 0.3), -3.0, fade_ms=120)


def make_win():
    """Удар победы и перелив волны по полю: мягкий «бум» (бочка музыки + желе) + аккорд C (маримба
    и электропиано), затем колокольчики вверх C6-E6-G6-C7 (идут за волной — она начинается после
    hit-stop 0,07 с и доходит за 0,55 с)."""
    r = rng("win")
    dur = 1.3
    out = silence(dur)
    t = t_axis(dur)
    out += 0.45 * jelly(t, glide(t, 170, 80, 0.08), 0.003, 0.09, r)
    place_at(out, 0.35 * kick(0.7, name="win"), 0.0)
    for k, n in enumerate(["C4", "C5", "E5", "G5"]):
        place_at(out, 0.5 * marimba(n, 0.75, damp=0.45, name="win%d" % k), 0.0)
    for k, n in enumerate(["C4", "G4", "E5"]):
        place_at(out, 0.25 * epiano(n, 0.7, 0.55, name="winep%d" % k), 0.004 + 0.006 * k)
    place_at(out, 0.35 * bell("C6", 0.7, damp=0.6, name="winb"), 0.0)
    for k, n in enumerate(["C6", "E6", "G6", "C7"]):
        place_at(out, (0.34 - 0.03 * k) * bell(n, 0.7, damp=0.45, name="winw%d" % k), 0.09 + 0.13 * k)
    air = bandpass(noise("win", len(t)), 2500, 7000) * env(t, 0.25, 0.25) * 0.04
    return finish(room(out + air, 0.2, 0.3), -2.0, fade_ms=150)


def make_jingle():
    """Джингл после звёзд: «та-да-да-дам» — G5, C6, E6 маримбой и аккорд C (маримба, электропиано,
    колокольчики G6 и C7).
    Версия 3.1 — мягче: затакт тихий (нарастает к аккорду, но на 4–5 dB ниже него; раньше E6 звучала вровень
    со всем аккордом и была самой яркой нотой) и мягкой колотушкой; аккорд — арпеджато снизу вверх (8 мс на ноту),
    а не пять ударов разом; колокольчики тише, с меньшим металлом и вступают после аккорда, продолжая его вверх;
    верх выше 2,5 кГц приглушён на 3 dB, срез — 7 кГц. Аккорд по-прежнему с 0,3 с."""
    dur = 1.55
    out = silence(dur)
    for k, (n, at, v) in enumerate([("G5", 0.0, 0.42), ("C6", 0.09, 0.48), ("E6", 0.18, 0.54)]):
        place_at(out, 0.45 * soft_mallet(marimba(n, v, damp=0.15, name="jg%d" % k), 0.003), at)
    for k, n in enumerate(["C4", "C5", "E5", "G5", "C6"]):
        place_at(out, 0.36 * soft_mallet(marimba(n, 0.6, damp=0.55, name="jc%d" % k), 0.002), 0.3 + 0.008 * k)
    for k, n in enumerate(["C4", "G4", "E5"]):
        place_at(out, 0.22 * epiano(n, 0.9, 0.5, name="jep%d" % k), 0.304 + 0.007 * k)
    place_at(out, 0.26 * bell("G6", 0.45, damp=0.6, name="jb1"), 0.335)
    place_at(out, 0.18 * bell("C7", 0.4, damp=0.5, name="jb2"), 0.365)
    return finish(high_shelf(room(out, 0.2, 0.3), 2500, -3.0), -2.0, fade_ms=200, lp=7000.0)


def make_star():
    """Звезда окна победы: звонкое «динь» колокольчиком C6 с маримбой (до-ми-соль — pitch_scale)."""
    x = silence(0.6)
    place_at(x, 0.8 * bell("C6", 0.8, damp=0.45, name="star"), 0.0)
    place_at(x, 0.45 * marimba("C6", 0.6, damp=0.1, name="starm"), 0.0)
    return finish(room(x, 0.18, 0.2), -3.0, fade_ms=100)


def make_click():
    """Кнопка: «поп» пузырька — тон вверх, мягкий «ток» и лопнувшая плёнка."""
    r = rng("click")
    t = t_axis(0.07)
    pop = jelly(t, glide(t, 620, 1150, 0.014), 0.0015, 0.018, r, 0.6)
    tok = wood(t, glide(t, 380, 260, 0.01), 0.008, r) * 0.5
    film = bandpass(r.standard_normal(len(t)), 1500, 4500) * np.exp(-t / 0.0005) * 0.12
    return finish(room(pop + tok + film, 0.06, 0.05), -5.0, fade_ms=12)


def make_undo():
    """Отмена: «фьють» назад — тон с дыханием вниз и мягкое «блюп», когда блок долетел до лотка."""
    r = rng("undo")
    t = t_axis(0.24)
    sweep = whistle("undo", t, glide(t, 760, 380, 0.13), 0.01, 0.06)
    swish = whoosh("undo", t, 1800, 4200, 600, 1500, 0.12)
    tt = t_axis(0.11)
    blup = jelly(tt, glide(tt, 300, 420, 0.03), 0.003, 0.025, r)
    blup += fizz("undo", 0.11, 0.003, 0.01, 3, 700, 1600) * env(tt, 0.003, 0.02) * 0.12
    blup = place_at(np.zeros_like(t), blup, 0.13)
    return finish(room(0.6 * sweep + 0.3 * swish + 0.5 * blup, 0.08, 0.1), -5.0, fade_ms=20)


## Полёт блока подсказки, с (JuiceConfig.hint_float_time): звук подсказки под него (версия 3.2, 12.10).
HINT_FLY = float(re.search(r"@export var hint_float_time := ([\d.]+)",
                           open(os.path.join(ROOT, "scripts", "juice_config.gd"), encoding="utf-8").read()).group(1))


def make_hint():
    """Подсказка (3.2, 12.10): блок сразу летит на место за HINT_FLY (0,3 с) — быстрый перелив вверх по
    пентатонике (последняя нота — за четверть полёта до касания) и вихрь с дыханием за время полёта, в миг
    касания — «искры». Удар и ноту касания играет сама постановка (Place + Note), поэтому колокольчиков
    прилёта, как в 3.1 (искра 0,42 с, потом блок 0,36 с), нет — две ноты разом были бы кашей."""
    fly = HINT_FLY
    dur = 0.7
    out = silence(dur)
    t = t_axis(dur)
    step = fly * 0.75 / 5
    for k, n in enumerate(["C6", "D6", "E6", "G6", "A6", "C7"]):
        place_at(out, (0.22 + 0.03 * k) * bell(n, 0.5, damp=0.22, name="hint%d" % k), step * k)
    swirl = whistle("hint", t, glide(t, 900, 1900, fly), 0.1, fly * 0.5) * 0.07 * (1 + 0.5 * np.sin(2 * np.pi * 9 * t))
    glints = fizz("hint", dur, fly, 0.03, 6, 2500, 5000) * 0.03
    air = bandpass(noise("hint", len(t)), 3000, 7500) * env(t, 0.15, 0.12) * 0.04
    return finish(room(out + swirl + glints + air, 0.2, 0.25), -4.0, fade_ms=100)


SOUNDS = {
    "pick": make_pick, "place": make_place, "note": make_note, "rotate": make_rotate, "miss": make_miss,
    "error": make_error, "line": make_line, "win": make_win, "jingle": make_jingle, "star": make_star,
    "click": make_click, "undo": make_undo, "hint": make_hint,
}


# --- Сведение (15.5) ------------------------------------------------------------------

## «Телефонная» громкость звука на выходе (phone_loudness + volume_db узла), dBFS. Музыка (bgm_main, −12 dB)
## по той же мерке (окна 50 мс, сессия 74): медиана −29, громкие места (90 %) −25, пик −21. Музыка версии 3
## (сессия 105; моно = среднее каналов): медиана −31, 90 % −29, пик −26,5; прежняя по этой же мерке — −32, −28,
## −24,5: середина та же, пики ниже на 2 dB, поэтому TARGET не менялся. Частые звуки (кнопка,
## подъём, поворот, промах) — чуть над музыкой; постановка (удар + нота) — заметно; тупик, отмена, подсказка —
## ещё громче; линия, звёзды, джингл и удар победы — громче всех (под победу музыка ещё и приглушена на 8 dB).
## Против звуков до этапа 15 (docs/sfx_old): удар, линия, победа, звезда, кнопка — в пределах 2 dB; подъём тише
## на 6 dB (самый частый звук), тупик громче на 5 dB (редкий и важный). Подбирается на слух: правка здесь —
## `python3 tools/make_sfx.py`, затем `python3 tools/sfx_preview.py` (предпрослушка в docs/sfx/).
TARGET = {
    "click": -25, "pick": -25, "rotate": -26, "miss": -25,
    "place": -24, "note": -22, "undo": -22, "error": -22, "hint": -21,
    "line": -18, "star": -18, "jingle": -17, "win": -16,
}
MUSIC_DB = -12.0
SCENE = os.path.join(ROOT, "autoload", "audio.tscn")


def node_name(name):
    return name[:1].upper() + name[1:]


def mix(sounds):
    """volume_db узлов: цель TARGET минус «телефонная» громкость файла (до 0,5 dB)."""
    return {n: round(2 * (TARGET[n] - phone_loudness(x))) / 2 for n, x in sounds.items()}


def write_scene(volumes):
    """autoload/audio.tscn целиком: узел на каждый звук (имя — как константа в audio.gd) и музыка."""
    lines = ["[gd_scene format=3]", "",
             '[ext_resource type="Script" path="res://autoload/audio.gd" id="1_audio"]']
    ids = {}
    for k, n in enumerate(SOUNDS, start=2):
        ids[n] = "%d_%s" % (k, n)
        lines.append('[ext_resource type="AudioStream" path="res://assets/sfx/%s.wav" id="%s"]' % (n, ids[n]))
    music_id = "%d_music" % (len(SOUNDS) + 2)
    lines.append('[ext_resource type="AudioStream" path="res://assets/music/bgm_main.ogg" id="%s"]' % music_id)
    lines += ["", '[node name="Audio" type="Node"]', "process_mode = 3", 'script = ExtResource("1_audio")']
    for n in SOUNDS:
        lines += ["", '[node name="%s" type="AudioStreamPlayer" parent="."]' % node_name(n),
                  'stream = ExtResource("%s")' % ids[n], "volume_db = %.1f" % volumes[n], 'bus = &"SFX"']
    lines += ["", '[node name="Music" type="AudioStreamPlayer" parent="."]', 'stream = ExtResource("%s")' % music_id,
              "volume_db = %.1f" % MUSIC_DB, 'bus = &"Music"', ""]
    with open(SCENE, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


# --- Запись и проверка ---------------------------------------------------------------

def write_wav(path, x):
    data = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def phone_loudness(x):
    """«Телефонная» громкость: без низа ниже 300 Гц (динамик телефона), наибольшее RMS за 50 мс, dBFS."""
    y = highpass(x, 300, order=4)
    win = int(SR * 0.05)
    if len(y) < win:
        y = np.pad(y, (0, win - len(y)))
    c = np.cumsum(np.concatenate([[0.0], y ** 2]))
    rms = np.sqrt((c[win:] - c[:-win]) / win)
    return 20 * np.log10(rms.max() + 1e-12)


def describe(name, x):
    peak = 20 * np.log10(np.abs(x).max() + 1e-12)
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1 / SR)
    centroid = (spec * f).sum() / spec.sum()
    harsh = (spec[(f > 2500) & (f < 5000)] ** 2).sum() / ((spec ** 2).sum() + 1e-12)
    print(f"{name:7s} {len(x) / SR:.3f} с  пик {peak:5.1f} dBFS  телефон {phone_loudness(x):6.1f} dBFS  "
          f"центр {centroid:5.0f} Гц  2,5–5 кГц {100 * harsh:4.1f} %  края {abs(x[0]):.4f}/{abs(x[-1]):.4f}")


def render():
    return {name: fn() for name, fn in SOUNDS.items()}


def main():
    check = "--check" in sys.argv
    sounds = render()
    volumes = mix(sounds)
    for name, x in sounds.items():
        describe(name, x)
        print(f"        volume_db {volumes[name]:5.1f} -> на выходе: телефон {phone_loudness(x) + volumes[name]:6.1f}, "
              f"пик {20 * np.log10(np.abs(x).max()) + volumes[name]:5.1f} dBFS")
        if not check:
            write_wav(os.path.join(OUT_DIR, name + ".wav"), x)
    if not check:
        write_scene(volumes)
        print("Записано в", OUT_DIR, "и", SCENE)


if __name__ == "__main__":
    main()
