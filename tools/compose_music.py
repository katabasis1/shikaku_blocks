#!/usr/bin/env python3
"""Фоновая музыка «Шикаку: Блоки»: партитура, синтез и экспорт (версия 3).

Лёгкий lo-fi для головоломки: до мажор (звуки игры тоже в C), 92 BPM,
32 такта ≈ 83,5 с, форма A1–A2–B–A3, бесшовная петля. Хвосты нот, эха и
реверберации заворачиваются в начало, а фильтры мастера с памятью
считаются «по кругу». Партитура (мелодии, гармония, форма) — как в версии 1.

Версия 3 (поверх версии 2):
  * Малый барабан заново: моды мембраны + пружины, которые шлёпают по нижней
    мембране, + щелчок палочки. Спектр и затухание подогнаны под записанный
    lo-fi малый: «тело» около 320 Гц, основная энергия 0,3–2,5 кГц, без шипящего
    хвоста выше 5 кГц; затухает естественно (раньше шум обрывался на 350 мс).
  * Ударные в своей короткой комнате (RT ≈ 0,5 с), а не в общей (≈ 1,5 с).
  * Хвост ударных больше не попадает в начало трека: последний такт без брейка
    малого (ударные уходят на 3-й доле), шина ударных за полдоли до конца петли
    плавно гаснет, и её хвосты не заворачиваются. Такты 1–4 — без ударных совсем.
  * Хвосты бочки, открытого хэта, маримбы, колокольчика и пэда больше не
    обрезаются на −20…−30 дБ: звуки длиннее, в конце каждого — плавный спад 20 мс.

Что изменилось в версии 2 по сравнению с версией 1:
  * Инструменты. Модальный синтез и упрощённые физические модели вместо
    синуса с одним обертоном. Маримба: пять мод бруска, резонатор, мягкая
    колотушка (громче удар — ярче). Электропиано: язычок, тонбар и
    нелинейный звукосниматель (сильнее удар — больше «рычания»). Окарина:
    подъезд к ноте, живое вибрато, колебания дыхания, шум воздуха. Бас: щипок
    струны. Пэд: расстроенные пилы с плавающей подстройкой и «раскрытием»
    фильтра. Ударные модальные, и каждый удар звучит по-новому.
  * Живая игра. Громкость: метрические и фразовые акценты плюс разброс
    σ 4–8 из 127. Тайминг: σ 3–12 мс и своё смещение у каждого инструмента
    (малый барабан чуть позади, бас и клавиши чуть «за долей»), общее
    «дыхание» темпа ±5 мс, свинг 55,5 % (у шейкера сильнее), аккорды
    электропиано слегка раскатаны снизу вверх.
  * Шейкер. Вступает в 9-м такте вместе с полным битом. Фраза на 2 такта с
    паузой в конце, восьмые с редкими тихими шестнадцатыми, ударение на «и».
    Звук собирается из отдельных бусин, «туда» и «обратно» звучат по-разному.
    В части B — только два коротких удара, в A3 вместо него хэт.
  * Реверберация. Ранние отражения комнаты 7,2 × 5,1 × 3,1 м (метод мнимых
    источников, у дальних отражений меньше верха) плюс диффузный хвост,
    у которого высокие затухают быстрее низких (RT от 1,6 с до 0,4 с).
  * Мастер тёплый: без подъёма верха (было +2,5 дБ выше 3,5 кГц), мягкий
    срез сверху, лёгкая «лента» (сатурация с передискретизацией и едва
    заметное плавание тона), мягкая склейка компрессором.

Выход (в папку из аргумента, по умолчанию ./music_out):
  bgm_main.wav  — мастер 44,1 кГц / 16 бит, стерео
  bgm_main.ogg  — Ogg Vorbis для игры (нужен ffmpeg с libvorbis)
  bgm_main.mid  — MIDI (тип 1, дорожка на инструмент; тайминг и громкости
                  «живые», как в аудио)

Запуск: python3 tools/compose_music.py [папка]
Переменная MUSIC_STEMS=<папка> дополнительно сохраняет дорожки (.npy) для анализа.
Результат детерминирован (фиксированное зерно).
"""
import os
import pathlib
import struct
import subprocess
import sys

import numpy as np
from scipy import signal
from scipy.interpolate import CubicSpline
from scipy.io import wavfile

SR = 44100
BPM = 92
BAR = 4                      # долей в такте
BARS = 32
SPB = 60.0 / BPM             # секунд в доле
LOOP_BEATS = BARS * BAR
N = int(round(LOOP_BEATS * SPB * SR))   # длина петли в сэмплах
LOOP_SEC = N / SR
TAIL = 6 * SR                # запас под хвосты перед заворачиванием
SEED = 20261010
DETUNE = 1.0                 # разброс строя нот; make_sfx.py ставит 0 — ноты звуков ровно в строе

rng = np.random.default_rng(SEED)

# --- Грув и «живая» игра --------------------------------------------------------
SWING8 = 0.055     # «и» позже на 0,055 доли (≈36 мс): 55,5 % вместо ровных 50 %
SWING16 = 0.58     # чётная шестнадцатая внутри восьмой: 58 : 42
GROOVE = {         # насколько инструмент следует свингу
    "tops": 1.0, "shaker": 1.3, "kick": 0.7, "snare": 0.9,
    "keys": 0.5, "lead": 0.45, "bass": 0.6, "bell": 0.7, "pad": 0.0,
}
TIMING = {         # (σ, смещение) в мс: + значит позже доли
    "marimba": (6, 0), "ocarina": (8, 6), "epiano": (7, 4), "bass": (5, 4),
    "pad": (12, 0), "bell": (5, 1), "kick": (3, 0), "snare": (4, 8),
    "hat": (5, 2), "shaker": (6, 3),
}
PUSH_MS = 5.0      # общее «дыхание» темпа: ±5 мс, 4 волны за петлю (петля не сдвигается)
DYN = {"A1": -8, "A2": 0, "B": -4, "A3": 4}   # громкость частей


def swing(beat, depth):
    b = np.floor(beat + 1e-9)
    f = beat - b
    mid = 0.5 + SWING8 * depth
    p16 = 0.5 + (SWING16 - 0.5) * min(depth, 1.0)
    if abs(f - 0.25) < 1e-6:
        return b + mid * p16
    if abs(f - 0.5) < 1e-6:
        return b + mid
    if abs(f - 0.75) < 1e-6:
        return b + mid + (1 - mid) * p16
    return beat


def perf_time(beat, inst, groove):
    """Доля партитуры → время исполнения в секундах (свинг, смещение, разброс, дыхание)."""
    sd, bias = TIMING[inst]
    j = float(np.clip(rng.normal(0, sd), -2.5 * sd, 2.5 * sd))
    push = PUSH_MS * np.sin(2 * np.pi * beat / 32)
    return swing(beat, GROOVE[groove]) * SPB + (bias + j + push) / 1000.0


def hv(base, spread):
    """Громкость 1..127 с «человеческим» гауссовым разбросом."""
    d = float(np.clip(rng.normal(0, spread), -2.5 * spread, 2.5 * spread))
    return int(np.clip(round(base + d), 1, 127))


# --- Гармония (как в версии 1) --------------------------------------------------
CHORDS = {
    "Cmaj9":  (36, [59, 62, 64, 67]),   # B3 D4 E4 G4
    "C69":    (36, [57, 62, 64, 67]),   # A3 D4 E4 G4
    "Em7":    (40, [62, 64, 67, 71]),   # D4 E4 G4 B4
    "Fmaj9":  (41, [57, 60, 64, 67]),   # A3 C4 E4 G4
    "Gadd9":  (43, [59, 62, 67, 69]),   # B3 D4 G4 A4
    "Am7":    (45, [55, 60, 64, 69]),   # G3 C4 E4 A4
    "Dm7":    (38, [53, 57, 60, 62]),   # F3 A3 C4 D4
    "G7sus4": (43, [53, 60, 62, 67]),   # F3 C4 D4 G4
    "G7":     (43, [53, 59, 62, 67]),   # F3 B3 D4 G4
}
PROG_A = ["Cmaj9", "Em7", "Fmaj9", "Gadd9", "C69", "Am7", "Dm7", "G7sus4"]
PROG_B = ["Am7", "Fmaj9", "Em7", "Dm7", "Am7", "Fmaj9", "Dm7", ("G7sus4", "G7")]
SECTIONS = [("A1", PROG_A), ("A2", PROG_A), ("B", PROG_B), ("A3", PROG_A)]


def bar_chords(bar):
    sec, prog = SECTIONS[bar // 8]
    c = prog[bar % 8]
    if isinstance(c, tuple):
        return [(0.0, 2.0, c[0]), (2.0, 2.0, c[1])]
    return [(0.0, 4.0, c)]


def section(bar):
    return SECTIONS[bar // 8][0]


# --- Мелодии (доля, длительность, нота) — как в версии 1 -----------------------
MELODY_A = [
    [(0, .5, 79), (.5, .5, 76), (1, 1, 79), (2, 1.5, 83), (3.5, .5, 81)],
    [(0, 1, 79), (1, .5, 76), (1.5, .5, 74), (2, 2, 76)],
    [(0, .5, 81), (.5, .5, 79), (1, 1, 81), (2, 1.5, 84), (3.5, .5, 81)],
    [(0, 1.5, 83), (1.5, .5, 81), (2, 1, 79), (3, 1, 74)],
    [(0, .5, 76), (.5, .5, 79), (1, 1, 84), (2, 1, 83), (3, 1, 79)],
    [(0, 1.5, 81), (1.5, .5, 84), (2, .5, 83), (2.5, .5, 81), (3, 1, 79)],
    [(0, 1, 77), (1, 1, 81), (2, .5, 79), (2.5, .5, 77), (3, 1, 76)],
    [(0, 2.5, 74), (3, .5, 76), (3.5, .5, 77)],
]
MELODY_A2_LAST = [(0, 1, 74), (1, 1, 72), (2, 2, 67)]
MELODY_B = [
    [(0, 1.5, 76), (1.5, .5, 74), (2, 2, 72)],
    [(0, 1, 72), (1, 1, 69), (2, .5, 72), (2.5, .5, 74), (3, 1, 76)],
    [(0, 1.5, 74), (1.5, .5, 71), (2, 2, 67)],
    [(0, 1, 69), (1, 1, 72), (2, 1, 71), (3, 1, 69)],
    [(0, 1.5, 76), (1.5, .5, 79), (2, 1, 76), (3, 1, 74)],
    [(0, 1.5, 72), (1.5, .5, 74), (2, 1, 76), (3, 1, 72)],
    [(0, 1, 74), (1, 1, 72), (2, 1, 69), (3, 1, 65)],
    [(0, 1.5, 67), (1.5, .5, 69), (2, 2, 71)],
]
ARP_ORDER = [0, 1, 2, 3, 2, 1, 2, 3]

# Шейкер: фраза на 2 такта в шестнадцатых (0..31): (позиция, движение, громкость).
# «и» — резкое движение «туда» с ударением, доли — мягкое «обратно», редкие тихие
# шестнадцатые; в конце второго такта пауза.
SHAKER_PHRASES = [
    [(0, "back", 46), (2, "fwd", 80), (4, "back", 42), (6, "fwd", 74), (7, "ghost", 30),
     (8, "back", 44), (10, "fwd", 82), (12, "back", 40), (14, "fwd", 72),
     (16, "back", 46), (18, "fwd", 78), (20, "back", 42), (22, "fwd", 76),
     (24, "back", 44), (26, "fwd", 70), (27, "ghost", 28)],
    [(0, "back", 46), (2, "fwd", 78), (3, "ghost", 28), (4, "back", 42), (6, "fwd", 76),
     (8, "back", 44), (10, "fwd", 82), (11, "ghost", 30), (12, "back", 40), (14, "fwd", 74),
     (16, "back", 46), (18, "fwd", 80), (20, "back", 42), (22, "fwd", 72), (23, "ghost", 26),
     (24, "back", 44), (26, "fwd", 68)],
]
DRUM_NOTE = {"kick": 36, "snare": 38, "rim": 37, "hat": 42, "ohat": 46,
             "fwd": 82, "back": 82, "ghost": 82}
DRUM_TRACK = {"kick": "kick", "snare": "snare", "rim": "snare", "hat": "hat", "ohat": "ohat",
              "fwd": "shaker", "back": "shaker", "ghost": "shaker"}
DRUM_FEEL = {  # (тайминг, свинг)
    "kick": ("kick", "kick"), "snare": ("snare", "snare"), "rim": ("snare", "snare"),
    "hat": ("hat", "tops"), "ohat": ("hat", "tops"),
    "fwd": ("shaker", "shaker"), "back": ("shaker", "shaker"), "ghost": ("shaker", "shaker"),
}


# --- Партитура ------------------------------------------------------------------
# score[дорожка] = [(доля, длительность, нота, громкость, время исполнения в с, вид)]
def compose():
    s = {k: [] for k in ("marimba", "ocarina", "epiano", "bass", "pad", "bell", "drums")}
    for bar in range(BARS):
        b0 = bar * BAR
        sec = section(bar)
        k8 = bar % 8
        dyn = DYN[sec]
        chords = bar_chords(bar)
        split = len(chords) > 1

        # мелодия: акцент на 1 и 3, фразовая дуга на 2 такта, верх чуть громче
        if sec != "B":
            notes = MELODY_A2_LAST if (sec == "A2" and k8 == 7) else MELODY_A[k8]
            for st, du, p in notes:
                acc = {0: 12, 2: 6}.get(st, 0) + (2 if st % 1 == 0 else -5)
                arc = 5 * np.sin(np.pi * ((k8 % 2) * 4 + st + du / 2) / 8)
                v = hv(80 + acc + arc + (p - 79) * 0.6 + dyn, 7)
                s["marimba"].append((b0 + st, du, p, v, perf_time(b0 + st, "marimba", "lead"), None))
        else:
            for st, du, p in MELODY_B[k8]:
                arc = 6 * np.sin(np.pi * ((k8 % 2) * 4 + st + du / 2) / 8)
                v = hv(78 + arc + (p - 72) * 0.5 + (5 if st == 0 else 0), 5)
                s["ocarina"].append((b0 + st, du, p, v, perf_time(b0 + st, "ocarina", "lead"), None))

        for cst, cdu, name in chords:
            root, voices = CHORDS[name]
            # электропиано: аккорд раскатан снизу вверх, верхний голос чуть громче
            if split:
                hits = [(0, cdu - .1, 66)]
            elif sec == "A1":
                hits = [(0, 2.4, 70), (2.5, 1.4, 56)]
            elif sec == "B":
                hits = [(0, 3.9, 64)]
            else:
                hits = [(0, 1.4, 72), (1.5, 1.4, 60), (3, .9, 62)]
            for hs, hd, h0 in hits:
                beat = b0 + cst + hs
                v0 = hv(h0 + dyn * 0.5, 6)
                t0 = perf_time(beat, "epiano", "keys")
                roll = (0.004, 0.010) if hd > 2 else (0.0015, 0.005)
                for i, p in enumerate(voices):
                    vi = int(np.clip(round(v0 + (i - 1.5) * 2.5 + rng.normal(0, 4)), 1, 127))
                    s["epiano"].append((beat, hd, p, vi, t0 + i * rng.uniform(*roll), None))

            # бас
            fifth = root + 7
            if split:
                bl = [(0, cdu - .1, root, 88)]
            elif sec == "A1":
                bl = [(0, 3.8, root, 84)]
            elif sec == "B":
                bl = [(0, 2.4, root, 88), (2.5, 1.4, root, 74)]
            else:
                bl = [(0, 1.4, root, 92), (1.5, 1.4, root, 76), (3, .9, fifth, 80)]
            for bs, bd, bp, bv in bl:
                beat = b0 + cst + bs
                s["bass"].append((beat, bd, bp, hv(bv + dyn * 0.4, 5), perf_time(beat, "bass", "bass"), None))

            # пэд — в B громче, в A3 фоном
            if sec in ("B", "A3"):
                pv = 72 if sec == "B" else 56
                for p in voices + [root + 24]:
                    beat = b0 + cst
                    s["pad"].append((beat, cdu, p, hv(pv, 4), perf_time(beat, "pad", "pad"), None))

            # колокольчик-арпеджио восьмыми; изредка нота пропускается
            if sec in ("A2", "A3"):
                for k in range(int(cdu * 2)):
                    if k > 0 and rng.random() < 0.12:
                        continue
                    idx = ARP_ORDER[(int(cst * 2) + k) % 8]
                    beat = b0 + cst + k * .5
                    v = hv((66 if k % 2 == 0 else 54) + dyn * 0.5, 7)
                    s["bell"].append((beat, .45, voices[idx] + 24, v, perf_time(beat, "bell", "bell"), None))

        # --- ударные ---
        d = s["drums"]

        def hit(pos, kind, v):
            beat = b0 + pos
            inst, groove = DRUM_FEEL[kind]
            d.append((beat, 0.1, DRUM_NOTE[kind], v, perf_time(beat, inst, groove), kind))

        last = bar == BARS - 1
        if sec == "A1":
            # такты 1–4 без ударных; 5–8: мягкая бочка и тихий хэт на «и»
            if k8 >= 4:
                hit(0, "kick", hv(74, 4))
                hit(2.5, "kick", hv(60, 4))
                for p in (0.5, 1.5, 2.5, 3.5):
                    hit(p, "hat", hv(46, 6))
                if k8 == 7:
                    hit(3.5, "snare", hv(36, 4))
                    hit(3.75, "snare", hv(50, 4))
        elif sec == "B":
            # тише и интимнее: бочка и римшот, шейкер только дважды за часть
            hit(0, "kick", hv(86 + dyn, 4))
            hit(2.5, "kick", hv(66 + dyn, 5))
            hit(1, "rim", hv(76, 6))
            hit(3, "rim", hv(80, 6))
            if bar in (19, 21):
                hit(3.5, "fwd", hv(56, 5))
                hit(3.75, "back", hv(36, 4))
            if bar == 23:
                hit(3.5, "snare", hv(56, 4))
                hit(3.75, "snare", hv(70, 4))
        else:   # A2, A3
            hit(0, "kick", hv(96 + dyn, 4))
            if last:
                hit(2, "kick", hv(72, 4))   # последний удар петли; дальше ударных нет
            else:
                hit(2.5, "kick", hv(84 + dyn, 5))
            if bar % 2 == 1 and not last:
                hit(1.75, "kick", hv(54, 6))
            hit(1, "snare", hv(94 + dyn, 5))
            if not last:
                hit(3, "snare", hv(96 + dyn, 5))
            if bar % 4 == 2:
                hit(3.75, "snare", hv(28, 4))
            if bar % 4 == 1:
                hit(2.25, "snare", hv(24, 4))
            if bar == 15:
                hit(3.5, "snare", hv(62, 4))
                hit(3.75, "snare", hv(74, 4))
            if sec == "A2":
                # шейкер: фраза на 2 такта, чередуются два варианта
                ph = SHAKER_PHRASES[(bar // 2) % 2]
                half = bar % 2
                for pos16, kind, v in ph:
                    if pos16 // 16 != half:
                        continue
                    if kind == "ghost" and rng.random() < 0.3:
                        continue
                    hit((pos16 % 16) / 4, kind, hv(v, 5))
            else:
                # A3: хэт вместо шейкера; ударение на «и», редкие шестнадцатые
                for i in range(8):
                    pos = i * .5
                    if last and pos > 2:
                        continue
                    if bar == 27 and pos == 3.5:
                        hit(pos, "ohat", hv(66, 4))
                        continue
                    hit(pos, "hat", hv(78 if i % 2 else 50, 6))
                if bar % 2 == 1 and not last:
                    for pos in (1.75, 3.25):
                        if rng.random() < 0.7:
                            hit(pos, "hat", hv(32, 5))
    return s


# --- Синтез: общие кирпичики ------------------------------------------------------
def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def tvec(sec):
    return np.arange(int(sec * SR)) / SR


def release(t, dur, tau):
    return np.where(t < dur, 1.0, np.exp(-np.maximum(t - dur, 0) / tau))


def sos_lp(fc, order=2):
    return signal.butter(order, min(fc, SR * 0.45), "lowpass", fs=SR, output="sos")


def sos_hp(fc, order=2):
    return signal.butter(order, fc, "highpass", fs=SR, output="sos")


def sos_bp(lo, hi, order=2):
    return signal.butter(order, [lo, min(hi, SR * 0.45)], "bandpass", fs=SR, output="sos")


def wander(n, rate):
    """Плавная случайная кривая (σ≈1), меняется примерно `rate` раз в секунду."""
    m = int(n / SR * rate) + 4
    cs = CubicSpline(np.arange(m), rng.standard_normal(m))
    return cs(np.arange(n) / SR * rate) * 0.8


def noise(n):
    return rng.standard_normal(n)


def vgain(v, curve=1.4):
    return v ** curve


# --- Маримба: пять мод бруска + резонатор + мягкая колотушка ----------------------
MAR_MODES = [   # (отношение к основному, уровень, доля времени затухания)
    (1.000, 1.00, 1.00),
    (3.990, 0.45, 0.22),    # настроенный второй обертон (≈ две октавы)
    (9.850, 0.30, 0.07),    # третий (≈ три октавы и терция)
    (2.710, 0.03, 0.10),    # крутильная мода — «деревянный» призвук
    (6.300, 0.04, 0.05),
]


def syn_marimba(p, dur, v):
    f = hz(p) * 2 ** (DETUNE * rng.normal(0, 3) / 1200)
    tau1 = float(np.clip(1.25 * (330 / f) ** 0.6, 0.18, 2.2))
    t = tvec(float(np.clip(7.0 * tau1, 2.4, 7.0)))     # до −45 дБ, а не обрыв на −30
    fc = 1200 + 3800 * v ** 1.5            # колотушка: чем сильнее удар, тем ярче
    out = np.zeros_like(t)
    for ratio, amp, dk in MAR_MODES:
        fk = f * ratio * (1 + rng.normal(0, 0.0015) if ratio > 1 else 1)
        if fk > 15000:
            continue
        a = amp / (1 + (fk / fc) ** 4) * 10 ** (rng.normal(0, 1.5) / 20)   # место удара гуляет
        out += a * np.sin(2 * np.pi * fk * t) * np.exp(-t / (tau1 * dk))
    # резонаторная трубка: тот же тон, мягче вступает и дольше звучит, лёгкие биения
    det = rng.uniform(-0.4, 0.4)
    out += 0.35 * np.sin(2 * np.pi * (f + det) * t) * (1 - np.exp(-t / 0.012)) * np.exp(-t / (tau1 * 1.3))
    out *= 1 - np.exp(-t / 0.0006)
    k = int(0.012 * SR)
    thock = signal.sosfilt(sos_lp(1800 + 2500 * v), noise(k)) * np.exp(-t[:k] / 0.0015)
    out[:k] += 0.06 * v * thock
    return out * vgain(v)


# --- Электропиано: язычок + тонбар + нелинейный звукосниматель ------------------
def syn_epiano(p, dur, v):
    f = hz(p) * 2 ** (DETUNE * rng.normal(0, 2.5) / 1200)
    t = tvec(dur + 1.0)
    tau = float(np.clip(3.2 * (220 / f) ** 0.5, 0.7, 5.0))
    att = 1 - np.exp(-t / 0.0012)
    x = np.sin(2 * np.pi * f * t) * np.exp(-t / tau)
    x += 0.10 * np.sin(2 * np.pi * f * 1.0011 * t + 0.6) * np.exp(-t / (tau * 0.7))   # тонбар
    r = 6.27 * (1 + rng.normal(0, 0.012))           # вторая мода консольного язычка
    if r * f < 15000:
        x += 0.16 * v ** 1.5 * np.sin(2 * np.pi * r * f * t) * np.exp(-t / rng.uniform(0.025, 0.05))
    k = int(0.01 * SR)
    x[:k] += 0.05 * v * signal.sosfilt(sos_lp(1500), noise(k)) * np.exp(-t[:k] / 0.002)   # молоточек
    amp = 0.25 + 0.75 * v
    d = amp * x * att
    drive, off = 2.4, 0.32                           # асимметрия: язычок смещён от магнита
    y = (np.tanh(drive * (d + off)) - np.tanh(drive * off)) / drive
    return y * release(t, dur, 0.09) * (0.35 + 0.65 * v)


# --- Окарина: подъезд к ноте, вибрато, дыхание -------------------------------------
def syn_ocarina(p, dur, v):
    f = hz(p)
    t = tvec(dur + 0.3)
    n = len(t)
    pres = 0.035 * wander(n, 4.0)                    # колебания давления воздуха
    att = 0.030 + 0.020 * (1 - v)
    env = np.clip(t / att, 0, 1) ** 1.5 * (0.92 + 0.08 * np.exp(-t / 0.25))
    env = env * release(t, dur, 0.07) * (1 + pres)
    scoop = -28 * np.exp(-t / 0.045)                 # подъезд к ноте снизу, в центах
    depth = 14 * np.clip((t - 0.22) / 0.4, 0, 1) * (1 + 0.25 * wander(n, 1.5))
    rate = 5.1 + 0.35 * wander(n, 1.0)
    vib = depth * np.sin(2 * np.pi * np.cumsum(rate) / SR + rng.uniform(0, 6.28))
    cents = scoop + vib + 120 * pres                 # сильнее дуешь — чуть выше
    ph = 2 * np.pi * np.cumsum(f * 2 ** (cents / 1200)) / SR
    tone = np.sin(ph) + (0.05 + 0.05 * v) * np.sin(2 * ph + 0.4) + 0.022 * np.sin(3 * ph + 1.1)
    band = signal.sosfilt(sos_bp(f * 0.85, f * 1.18), noise(n)) * 0.45   # воздух у тона, ≈ −24 дБ
    chiff = signal.sosfilt(sos_hp(1500), noise(n)) * np.exp(-t / 0.018) * 0.10 * v
    hiss = signal.sosfilt(sos_bp(1800, 6000, 1), noise(n)) * 0.010
    return ((tone + band) * env + chiff * np.clip(t / 0.002, 0, 1) + hiss * env) * (0.4 + 0.6 * v)


# --- Бас: щипок струны (сумма гармоник со своими затуханиями) -------------------
def syn_bass(p, dur, v):
    f = hz(p)
    t = tvec(dur + 0.3)
    pos = rng.uniform(0.16, 0.24)                    # место щипка
    glide = 1 + 0.006 * v * np.exp(-t / 0.05)        # натяжение струны в атаке
    ph = 2 * np.pi * np.cumsum(f * glide) / SR
    tau1 = float(np.clip(1.3 * (55 / f) ** 0.25, 0.6, 1.6))
    bright = 500 + 1300 * v
    out = np.zeros_like(t)
    for k in range(1, 20):
        fk = f * k
        if fk > 4000:
            break
        a = abs(np.sin(np.pi * k * pos)) / k ** 0.9 / (1 + (fk / bright) ** 2)
        out += a * np.sin(k * ph * (1 + 0.00015 * k * k)) * np.exp(-t * (1 + 0.45 * (k - 1) ** 1.15) / tau1)
    m = int(0.03 * SR)
    out[:m] += 0.35 * v * signal.sosfilt(sos_lp(250), noise(m)) * np.exp(-t[:m] / 0.006)
    out *= np.clip(t / 0.004, 0, 1) * release(t, dur, 0.035)
    return np.tanh(1.3 * out) * (0.5 + 0.5 * v)


# --- Пэд: расстроенные пилы с плавающей подстройкой, фильтр «раскрывается» ------
def saw_blep(freq, phase0):
    dt = freq / SR
    ph = (phase0 + np.cumsum(dt)) % 1.0
    y = 2 * ph - 1
    m = ph < dt
    x = ph[m] / dt[m]
    y[m] -= x + x - x * x - 1
    m = ph > 1 - dt
    x = (ph[m] - 1) / dt[m]
    y[m] -= x * x + x + x + 1
    return y


def syn_pad(p, dur, v):
    f = hz(p)
    t = tvec(dur + 3.2)
    n = len(t)
    out = np.zeros((2, n))
    fc = 650 + 900 * v
    sw = 0.65 * (1 - np.exp(-t / 1.1))
    for ch, dets in enumerate(((-10, 4), (-4, 10))):
        acc = np.zeros(n)
        for dc in dets:
            drift = 2.5 * wander(n, 0.5)
            acc += saw_blep(f * 2 ** ((dc + drift) / 1200), rng.random())
        dark = signal.sosfilt(sos_lp(fc), acc)
        bright = signal.sosfilt(sos_lp(fc * 2.2), acc)
        out[ch] = dark * (1 - sw) + bright * sw
    env = (1 - np.exp(-t / 0.45)) * release(t, dur, 0.7) * (0.3 + 0.7 * v)
    return out * env


# --- Колокольчик: мягкий металлофон (неровные обертоны бруска) -------------------
def syn_bell(p, dur, v):
    f = hz(p) * 2 ** (DETUNE * rng.normal(0, 2) / 1200)
    tau = float(np.clip(0.9 * (1000 / f) ** 0.5, 0.25, 1.4))
    t = tvec(max(1.6, 6.0 * tau))
    s = np.sin(2 * np.pi * f * t) * np.exp(-t / tau)
    for ratio, a, dk in ((2.76, 0.16, 0.25), (5.40, 0.05, 0.08)):
        if ratio * f < 15000:
            s += a * v * np.sin(2 * np.pi * ratio * f * t) * np.exp(-t / (tau * dk))
    s *= 1 - np.exp(-t / 0.0008)
    return s * vgain(v)


# --- Ударные ---------------------------------------------------------------------
def syn_kick(v):
    t = tvec(1.0)
    f0 = 47 * (1 + rng.normal(0, 0.012))
    freq = f0 + (70 + 40 * v) * np.exp(-t / 0.028)
    ph = 2 * np.pi * np.cumsum(freq) / SR
    body = np.sin(ph) * np.exp(-t / (0.22 + rng.normal(0, 0.015)))
    body += 0.15 * np.sin(1.58 * ph) * np.exp(-t / 0.06)          # призвук корпуса
    k = int(0.02 * SR)
    beater = np.zeros_like(t)
    beater[:k] = signal.sosfilt(sos_lp(2500), noise(k)) * np.exp(-t[:k] / 0.002) * 0.25 * v
    y = np.tanh(1.6 * (body * (1 - np.exp(-t / 0.0008)) + beater))
    return y * vgain(v, 1.2)


# Малый барабан. Моды круглой мембраны (нули функций Бесселя): отношение к основной,
# уровень, затухание в секундах. Основная мода тише моды (1,1) — как у настоящего
# малого, у которого «тело» звучит около 320 Гц, а не гудит на 200 Гц.
SNARE_HEAD = [(1.000, 0.55, 0.035), (1.594, 1.00, 0.028), (2.136, 0.70, 0.022), (2.296, 0.45, 0.021),
              (2.653, 0.55, 0.018), (2.918, 0.40, 0.016), (3.156, 0.38, 0.015), (3.501, 0.30, 0.013),
              (3.600, 0.25, 0.013), (4.060, 0.22, 0.011), (4.154, 0.18, 0.011), (4.601, 0.14, 0.009),
              (4.832, 0.12, 0.008), (5.135, 0.10, 0.008)]


def syn_snare(v):
    """Мембрана + пружины, которые бьются о нижнюю мембрану, + щелчок палочки.
    Спектр и затухание подогнаны под записанный lo-fi малый (центроид ≈ 1 кГц,
    −40 дБ примерно через 150–170 мс), без шипящего «тссс» выше 5 кГц."""
    t = tvec(0.6)
    n = len(t)
    f0 = 205 * (1 + rng.normal(0, 0.008))
    fc_stick = 1 / (0.0011 - 0.0005 * v)               # сильнее удар — короче контакт — ярче
    glide = 1 + 0.045 * v ** 2 * np.exp(-t / 0.012)    # натяжение мембраны в атаке
    head = np.zeros(n)
    for r, a, tau in SNARE_HEAD:
        fk = f0 * r * (1 + rng.normal(0, 0.006))
        ak = a * 10 ** (rng.normal(0, 1.5) / 20) / (1 + (fk / fc_stick) ** 2)   # место удара гуляет
        ph = 2 * np.pi * np.cumsum(fk * glide) / SR + rng.uniform(0, 0.3)
        head += ak * np.sin(ph) * np.exp(-t / tau)
    head *= 1 - np.exp(-t / 0.0004)
    hn = head / (np.abs(head).max() + 1e-12)
    # пружины шлёпают по нижней мембране (запаздывание 0,4 мс) и шуршат чуть дольше неё
    lag = int(0.0004 * SR)
    drive = np.concatenate([np.zeros(lag), hn[:-lag]])
    slap = signal.sosfilt(sos_lp(1200), np.maximum(drive, 0) + 0.3 * np.maximum(-drive, 0))
    slap /= slap.max() + 1e-12
    tw = 0.035 * (0.85 + 0.3 * v)
    wenv = 0.6 * slap + 0.5 * np.exp(-t / tw) * (1 - np.exp(-t / 0.002))
    nz = noise(n)
    low = signal.sosfilt(sos_bp(450, 2200), nz)
    high = signal.sosfilt(sos_bp(2200, 7500), nz) * np.exp(-t / 0.035)   # верх пружин гаснет быстрее
    wires = (low + 0.3 * high) * wenv
    k = int(0.012 * SR)
    stick = np.zeros(n)
    stick[:k] = signal.sosfilt(sos_bp(900, 5000), noise(k)) * np.exp(-t[:k] / 0.0009)
    shell = np.sin(2 * np.pi * 780 * (1 + rng.normal(0, 0.01)) * t) * np.exp(-t / 0.012)   # корпус
    y = head + 4.5 * (0.7 + 0.3 * v) * wires + 0.5 * v * stick + 0.12 * shell
    y = np.tanh(1.4 * y / np.abs(y).max()) / np.tanh(1.4)   # лёгкое сжатие атаки
    y = signal.sosfilt(sos_lp(6500), y)
    return y * vgain(v, 1.3)


RIM_MODES = [(480, 1.0, 0.012), (1180, 0.6, 0.008), (1730, 0.4, 0.006), (3100, 0.2, 0.004)]


def syn_rim(v):
    t = tvec(0.15)
    tune = 1 + rng.normal(0, 0.02)
    y = sum(a * np.sin(2 * np.pi * fr * tune * t) * np.exp(-t / tau) for fr, a, tau in RIM_MODES)
    y += 0.3 * np.sin(2 * np.pi * 182 * tune * t) * np.exp(-t / 0.03)
    y += 0.5 * signal.sosfilt(sos_hp(1500), noise(len(t))) * np.exp(-t / 0.0008)
    return 0.6 * y * (1 - np.exp(-t / 0.0003)) * vgain(v, 1.3)


HAT_MODES = [3150, 4580, 5920, 7340, 8650, 10400, 12300]


def syn_hat(v, open_=False):
    t = tvec(1.6 if open_ else 0.14)
    n = len(t)
    nz = noise(n)
    metal = np.zeros(n)
    for fm in HAT_MODES:
        b, a = signal.iirpeak(fm * (1 + rng.normal(0, 0.02)), rng.uniform(6, 12), fs=SR)
        metal += signal.lfilter(b, a, nz) * rng.uniform(0.5, 1.0)
    metal = 0.6 * metal + 0.5 * signal.sosfilt(sos_hp(7000), nz)
    dec = 0.32 if open_ else 0.020 + 0.018 * v
    env = (1 - np.exp(-t / 0.0007)) * np.exp(-t / dec)
    tick = signal.sosfilt(sos_bp(2000, 6000), noise(n)) * np.exp(-t / 0.0015) * 0.3
    y = signal.sosfilt(sos_hp(4500), metal * env + tick)
    return y * vgain(v, 1.3)


def syn_shaker(kind, v):
    """Модель из отдельных бусин: поток коротких щелчков, плотность — по энергии движения.
    «Туда» — резкий старт и удар бусин о стенку; «обратно» — мягче, темнее, реже."""
    fwd = kind == "fwd"
    t = tvec(0.17 if fwd else 0.15)
    n = len(t)
    if fwd:
        rise, dec, rate, lo, hi = 0.005, 0.030, 9000, 3200, 8500
    else:
        rise, dec, rate, lo, hi = 0.016, 0.042, 5500, 2400, 6200
    env = (1 - np.exp(-t / rise)) * np.exp(-t / dec)
    env /= env.max()
    if fwd:
        tw = rng.uniform(0.010, 0.016)
        env = env + 0.8 * np.exp(-np.maximum(t - tw, 0) / 0.007) * (t >= tw)
    dens = env * rate * (0.5 + 0.5 * v) / SR
    hits = rng.random(n) < np.clip(dens, 0, 0.9)
    amp = np.where(hits, rng.exponential(1.0, n) * np.sqrt(env / env.max()), 0.0)
    fam = rng.integers(0, 8, n)       # 8 «семейств» бусин со своими резонансами
    out = np.zeros(n)
    for k in range(8):
        f0 = rng.uniform(lo, hi)
        dk = rng.uniform(0.0007, 0.002)
        tau = np.arange(int(6 * dk * SR)) / SR
        click = np.sin(2 * np.pi * f0 * tau) * np.exp(-tau / dk)
        out += np.convolve(amp * (fam == k), click)[:n]
    b, a = signal.iirpeak(rng.uniform(3000, 3800) if fwd else rng.uniform(2500, 3200), 1.4, fs=SR)
    out = 0.6 * out + 0.5 * signal.lfilter(b, a, out)
    out = signal.sosfilt(sos_lp(11000 if fwd else 7500), out)
    return out * vgain(v, 1.3)


# --- Рендер ----------------------------------------------------------------------
MELODIC_SYN = {"marimba": syn_marimba, "ocarina": syn_ocarina, "epiano": syn_epiano,
               "bass": syn_bass, "pad": syn_pad, "bell": syn_bell}
DRUM_PAN = {"kick": 0.0, "snare": 0.06, "rim": 0.10, "hat": 0.30, "ohat": 0.32,
            "fwd": -0.32, "back": -0.32, "ghost": -0.32}


def pan_gains(p):
    a = (p + 1) * np.pi / 4          # постоянная мощность: в центре 0,707 / 0,707
    return np.cos(a), np.sin(a)


def place(buf, sig, t_sec, pan=0.0):
    st = int(round(t_sec * SR)) % N  # раньше начала петли — значит в её конец
    k = min(int(0.02 * SR), sig.shape[-1])            # последние 20 мс — плавно в ноль
    sig = sig.copy()
    sig[..., -k:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, k))
    if sig.ndim == 1:
        gl, gr = pan_gains(pan)
        sig = np.stack([sig * gl, sig * gr])
    n = min(sig.shape[1], buf.shape[1] - st)
    buf[:, st:st + n] += sig[:, :n]


def render_track(name, events):
    buf = np.zeros((2, N + TAIL))
    if name == "drums":
        raise ValueError
    fn = MELODIC_SYN[name]
    for beat, du, p, ve, t, _ in events:
        v = ve / 127
        sig = fn(p, du * SPB, v)
        if name == "marimba":
            pn = float(np.clip(-0.12 + (p - 79) * 0.03, -0.4, 0.4))   # низ левее, верх правее
        elif name == "bell":
            pn = -0.45 if int(round(beat * 2)) % 2 == 0 else 0.45
        elif name == "ocarina":
            pn = 0.05
        else:
            pn = 0.0
        place(buf, sig, t, pn)
    return buf


def render_drums(events):
    tracks = {k: np.zeros((2, N + TAIL)) for k in ("kick", "snare", "hat", "ohat", "shaker")}
    hat_times = sorted(e[4] for e in events if e[5] in ("hat", "ohat"))
    for beat, du, p, ve, t, kind in events:
        v = ve / 127
        if kind == "kick":
            sig = syn_kick(v)
        elif kind == "snare":
            sig = syn_snare(v)
        elif kind == "rim":
            sig = syn_rim(v)
        elif kind == "hat":
            sig = syn_hat(v)
        elif kind == "ohat":
            sig = syn_hat(v, open_=True)
            nxt = [h for h in hat_times if h > t + 1e-4]       # следующий хэт глушит открытый
            if nxt:
                cut = int((nxt[0] - t) * SR)
                if cut < len(sig):
                    f = min(int(0.015 * SR), len(sig) - cut)
                    sig[cut:cut + f] *= np.linspace(1, 0, f)
                    sig[cut + f:] = 0
        else:
            sig = syn_shaker("fwd" if kind == "fwd" else "back", v)
        place(tracks[DRUM_TRACK[kind]], sig, t, DRUM_PAN[kind])
    return tracks


# --- Реверберация: ранние отражения комнаты + хвост с частотным затуханием ------
ROOM = np.array([7.2, 5.1, 3.1])      # м
SRC = np.array([2.4, 3.3, 1.3])
MICS = [np.array([4.50, 1.6, 1.5]), np.array([4.70, 1.6, 1.5])]
RT_F = np.array([63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])
RT_S = np.array([1.6, 1.55, 1.5, 1.4, 1.3, 1.1, 0.85, 0.6, 0.4])


def room_ir(length=2.8, beta=0.78, er_max=0.085, pre=0.006, er_share=0.45, rt_scale=1.0):
    n = int(length * SR)
    tt = np.arange(n) / SR
    rn = np.arange(-4, 5)

    def axis(i):
        nn, pp = np.meshgrid(rn, [0, 1], indexing="ij")
        nn, pp = nn.ravel(), pp.ravel()
        return (1 - 2 * pp) * SRC[i] + 2 * nn * ROOM[i], np.abs(nn - pp) + np.abs(nn)

    (X, OX), (Y, OY), (Z, OZ) = axis(0), axis(1), axis(2)
    PX, PY, PZ = np.meshgrid(X, Y, Z, indexing="ij")
    QX, QY, QZ = np.meshgrid(OX, OY, OZ, indexing="ij")
    order = (QX + QY + QZ).ravel()
    ir = np.zeros((2, n))
    for ch, m in enumerate(MICS):
        d0 = np.linalg.norm(SRC - m)
        dist = np.sqrt((PX - m[0]) ** 2 + (PY - m[1]) ** 2 + (PZ - m[2]) ** 2).ravel()
        delay = (dist - d0) / 343.0 + pre
        ok = (order > 0) & (delay < er_max + pre)
        er = np.zeros(n)
        for o, fc in zip(range(1, 6), (9000, 6500, 4800, 3600, 2800)):   # дальше — темнее
            sel = ok & ((order == o) if o < 5 else (order >= 5))
            b = np.zeros(n)
            np.add.at(b, np.round(delay[sel] * SR).astype(int), beta ** order[sel] * d0 / dist[sel])
            er += signal.sosfilt(sos_lp(fc), b)
        # хвост: шум, у которого каждая частота гаснет со своим RT
        f, tf, Zs = signal.stft(noise(n), SR, nperseg=1024, noverlap=768)
        rt = np.interp(np.log(np.maximum(f, 20)), np.log(RT_F), RT_S * rt_scale)
        _, tail = signal.istft(Zs * np.exp(-6.91 * tf[None, :] / rt[:, None]), SR, nperseg=1024, noverlap=768)
        tail = np.pad(tail, (0, max(0, n - len(tail))))[:n]
        t0 = pre + 0.010
        tail *= (tt >= t0) * (1 - np.exp(-np.maximum(tt - t0, 0) / 0.025))
        tail /= np.sqrt((tail ** 2).sum())
        er /= np.sqrt((er ** 2).sum())
        ir[ch] = tail + np.sqrt(er_share) * er
    return ir / np.sqrt((ir ** 2).sum(axis=1).mean())


def ping_pong(x, beats=0.75, wet=0.55, fb=0.32, repeats=8):
    """Эхо на пунктирную восьмую, повторы попеременно слева/справа, каждый темнее."""
    d = int(round(beats * SPB * SR))
    cur = signal.sosfilt(sos_bp(350, 3800), x) * wet
    out = np.zeros((2, len(x)))
    darker = sos_lp(3200, 1)
    for k in range(1, repeats + 1):
        if k > 1:
            cur = signal.sosfilt(darker, cur) * fb
        sh = k * d
        if sh >= len(x):
            break
        out[(k - 1) % 2, sh:] += cur[:len(x) - sh]
    return out


# --- Сведение --------------------------------------------------------------------
# дорожка: (уровень, дБ; посыл в реверб; посыл в эхо). Уровень — RMS активной части
# по сумме мощностей каналов; у шейкера — RMS в части A2 (такты 9–16).
# Ударные идут в свою короткую комнату (RT ≈ 0,5 с), остальное — в общую (≈ 1,5 с).
MIX = {
    "marimba": (-20.0, 0.26, 0.18),
    "ocarina": (-20.5, 0.30, 0.14),
    "epiano":  (-23.5, 0.22, 0.0),
    "bass":    (-23.5, 0.0, 0.0),
    "pad":     (-29.5, 0.38, 0.0),
    "bell":    (-33.5, 0.38, 0.0),
    "kick":    (-27.3, 0.05, 0.0),    # хвост бочки больше не обрезан: та же громкость удара
    "snare":   (-26.0, 0.26, 0.0),    # новый малый короче и темнее: по A-взвешенной громкости ≈ как старый, на 1 дБ тише
    "hat":     (-35.5, 0.10, 0.0),
    "ohat":    (-38.0, 0.12, 0.0),
    "shaker":  (-41.0, 0.12, 0.0),
}
FILTERS = {  # (тип, частота) — 2-й порядок
    "marimba": [("highpass", 120)], "ocarina": [("highpass", 180)],
    "epiano": [("highpass", 90), ("lowpass", 7000)], "bass": [("highpass", 32), ("lowpass", 2600)],
    "pad": [("highpass", 140)], "bell": [("highpass", 400), ("lowpass", 9000)],
    "kick": [("highpass", 28)], "snare": [("highpass", 90), ("lowpass", 9000)],
    "hat": [("lowpass", 11500)], "ohat": [("lowpass", 11000)],
    "shaker": [("highpass", 1500), ("lowpass", 10500)],
}
WET = 0.9
DRUM_ROOM_RT = 0.32    # короткая комната ударных: RT общей × 0,32 (≈ 0,5 с внизу, 0,2 с на 8 кГц)
DRUM_FADE_BEATS = 0.5  # за полдоли до конца петли шина ударных плавно уходит в ноль


def power(x):
    return (x ** 2).sum(axis=0)


def active_rms_db(x):
    pw = power(x)
    hop = int(0.05 * SR)
    fr = pw[: len(pw) // hop * hop].reshape(-1, hop).mean(axis=1)
    act = fr[fr > fr.max() * 1e-4]
    return 10 * np.log10(act.mean() + 1e-20)


def track_level_db(name, x):
    if name == "shaker":
        a, b = 8 * N // BARS, 16 * N // BARS
        return 10 * np.log10(power(x[:, a:b]).mean() + 1e-20)
    return active_rms_db(x)


def fold(x):
    """Заворачивает всё, что дальше N сэмплов, в начало: так петля бесшовна."""
    out = np.zeros((x.shape[0], N))
    for k in range(0, x.shape[1], N):
        seg = x[:, k:k + N]
        out[:, : seg.shape[1]] += seg
    return out


def drum_gate():
    """Окно шины ударных: единица, в последние полдоли — спад в ноль, после конца петли — ноль.
    Так ни хвост малого, ни его реверберация не заворачиваются в начало трека,
    где в тактах 1–4 ударных нет."""
    g = np.zeros(N + TAIL)
    k = int(DRUM_FADE_BEATS * SPB * SR)
    g[:N - k] = 1.0
    g[N - k:N] = 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, k))
    return g


def mix(score, stems_dir=None):
    length = N + TAIL
    dry = np.zeros((2, length))
    rev = np.zeros((2, length))
    ddry = np.zeros((2, length))     # шина ударных
    drev = np.zeros((2, length))
    echo = np.zeros(length)
    lfo = np.sin(2 * np.pi * (BPM / 120) * np.arange(length) / SR)   # 64 цикла за петлю

    def add(name, x, drums=False):
        nonlocal echo
        for kind, fc in FILTERS.get(name, []):
            x = signal.sosfilt(signal.butter(2, fc, kind, fs=SR, output="sos"), x, axis=-1)
        target, rs, es = MIX[name]
        x = x * 10 ** ((target - track_level_db(name, x)) / 20)
        if name == "epiano":           # лёгкое стерео-тремоло
            m = x.sum(axis=0) * 0.7071
            x = np.stack([m * (1 - 0.18 * lfo), m * (1 + 0.18 * lfo)]) * 0.7071
        (ddry if drums else dry)[:] += x
        (drev if drums else rev)[:] += x * rs
        if es:
            echo += x.sum(axis=0) * 0.7071 * es
        if stems_dir:
            np.save(pathlib.Path(stems_dir) / f"{name}.npy",
                    fold(x * drum_gate() if drums else x).astype(np.float32))

    for name in ("marimba", "ocarina", "epiano", "bass", "pad", "bell"):
        add(name, render_track(name, score[name]))
    for name, x in render_drums(score["drums"]).items():
        add(name, x, drums=True)
    e = ping_pong(echo)
    dry += e
    rev += e * 0.5
    ir = room_ir()
    wet = np.stack([signal.oaconvolve(rev[c], ir[c]) for c in range(2)])
    wet = signal.sosfilt(sos_hp(150), wet, axis=-1)
    wet = signal.sosfilt(sos_lp(8500), wet, axis=-1)
    total = np.zeros((2, wet.shape[1]))
    total[:, :length] += dry
    total += wet * WET
    ir_d = room_ir(length=1.4, er_share=0.6, rt_scale=DRUM_ROOM_RT)
    dwet = np.stack([signal.oaconvolve(drev[c], ir_d[c])[:length] for c in range(2)])
    dwet = signal.sosfilt(sos_hp(180), dwet, axis=-1)
    dwet = signal.sosfilt(sos_lp(8000), dwet, axis=-1)
    total[:, :length] += (ddry + dwet * WET) * drum_gate()
    if stems_dir:
        np.save(pathlib.Path(stems_dir) / "drum_bus.npy",
                fold((ddry + dwet * WET) * drum_gate()).astype(np.float32))
    return fold(total)


# --- Тёплый мастер (всё с памятью — по кругу, чтобы петля не щёлкала) ---------
def circ(fn, x, margin=SR):
    """Обрабатывает петлю как бесконечную: добавляет по секунде с другого конца."""
    ext = np.concatenate([x[:, -margin:], x, x[:, :margin]], axis=1)
    return fn(ext)[:, margin:margin + x.shape[1]]


def biquad(kind, f0, gain_db, q=0.707):
    """RBJ: highshelf / lowshelf / peaking → sos."""
    a = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / SR
    cw, sw = np.cos(w0), np.sin(w0)
    if kind in ("highshelf", "lowshelf"):
        al = sw / 2 * np.sqrt(2)
        s = 1 if kind == "highshelf" else -1
        b = [a * ((a + 1) + s * (a - 1) * cw + 2 * np.sqrt(a) * al), -2 * s * a * ((a - 1) + s * (a + 1) * cw),
             a * ((a + 1) + s * (a - 1) * cw - 2 * np.sqrt(a) * al)]
        den = [(a + 1) - s * (a - 1) * cw + 2 * np.sqrt(a) * al, 2 * s * ((a - 1) - s * (a + 1) * cw),
               (a + 1) - s * (a - 1) * cw - 2 * np.sqrt(a) * al]
    else:
        al = sw / (2 * q)
        b = [1 + al * a, -2 * cw, 1 - al * a]
        den = [1 + al / a, -2 * cw, 1 - al / a]
    return np.array([b + den]) / den[0]


def tape(x, drive=1.6, bias=0.05):
    """Лёгкая ленточная сатурация с 2× передискретизацией (без алиасинга)."""
    up = signal.resample_poly(x, 2, 1, axis=-1)
    y = (np.tanh(drive * (up + bias)) - np.tanh(drive * bias)) / drive
    return signal.resample_poly(y, 1, 2, axis=-1)


def glue(x, thresh_db=-20.0, ratio=1.6):
    lvl = np.sqrt(signal.sosfiltfilt(sos_lp(8, 1), x.mean(axis=0) ** 2) + 1e-12)
    over = np.maximum(20 * np.log10(lvl) - thresh_db, 0)
    return x * 10 ** (-over * (1 - 1 / ratio) / 20)


def wow_flutter(x):
    """«Плавание» тона: ±2,5 цента медленно и чуть-чуть быстрее; целое число волн за петлю."""
    n = x.shape[1]
    tt = np.arange(n) / SR
    wow = 2.5 / 1200 * np.sin(2 * np.pi * round(0.55 * LOOP_SEC) / LOOP_SEC * tt)
    flut = 0.6 / 1200 * np.sin(2 * np.pi * round(6.1 * LOOP_SEC) / LOOP_SEC * tt + 1.0)
    rate = wow + flut
    shift = np.cumsum(rate - rate.mean())          # смещение чтения в сэмплах, периодическое
    pos = (np.arange(n) + shift) % n
    i0 = np.floor(pos).astype(int)
    fr = pos - i0
    i1 = (i0 + 1) % n
    return x[:, i0] * (1 - fr) + x[:, i1] * fr


def master(x, target_rms_db=-16.5, thresh=0.70, ceiling=0.891):
    x = circ(lambda z: signal.sosfilt(sos_hp(28), z, axis=-1), x)
    eq = np.vstack([biquad("lowshelf", 100, 1.0),      # «головка» ленты: чуть теплее низ
                    biquad("peaking", 250, -1.5, 0.9),  # меньше «каши»
                    biquad("highshelf", 8000, -1.5)])   # мягкий срез сверху вместо подъёма
    x = circ(lambda z: signal.sosfilt(eq, z, axis=-1), x)
    x = x * 10 ** ((-18.0 - 10 * np.log10((x ** 2).mean())) / 20)
    x = circ(tape, x)
    x = circ(lambda z: signal.sosfilt(sos_hp(20, 1), z, axis=-1), x)   # убрать постоянку от ленты
    x = circ(glue, x)
    x = wow_flutter(x)
    x = circ(lambda z: signal.sosfilt(sos_lp(14500), z, axis=-1), x)  # потеря верха на ленте
    x = x * 10 ** ((target_rms_db - 10 * np.log10((x ** 2).mean())) / 20)
    a = np.abs(x)
    over = a > thresh
    y = np.where(over, np.sign(x) * (thresh + (ceiling - thresh) * np.tanh((a - thresh) / (ceiling - thresh))), x)
    return y, over.mean()


# --- MIDI -----------------------------------------------------------------------
PPQ = 480
MIDI_TRACKS = [  # дорожка партитуры, имя, канал, программа GM, громкость CC7, панорама CC10
    ("marimba", "Marimba Lead", 0, 12, 110, 60),
    ("ocarina", "Ocarina Lead (part B)", 1, 79, 105, 67),
    ("epiano", "E.Piano Chords", 2, 4, 90, 64),
    ("bass", "Bass", 3, 33, 100, 64),
    ("pad", "Warm Pad", 4, 89, 70, 64),
    ("bell", "Bell Arp", 5, 10, 60, 64),
    ("drums", "Drums (GM: 36 kick, 37 rim, 38 snare, 42/46 hat, 82 shaker)", 9, 0, 100, 64),
]


def vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    return bytes(reversed(out))


def chunk(events):
    events.sort(key=lambda e: (e[0], e[1]))
    data = b""
    last = 0
    for tick, _, ev in events:
        data += vlq(tick - last) + ev
        last = tick
    data += b"\x00\xff\x2f\x00"
    return b"MTrk" + struct.pack(">I", len(data)) + data


def meta(kind, payload):
    return b"\xff" + bytes([kind]) + vlq(len(payload)) + payload


def write_midi(score, path):
    tempo = int(round(60_000_000 / BPM))
    conductor = [
        (0, 0, meta(0x03, b"Shikaku Blocks - Main Theme (loop)")),
        (0, 0, meta(0x51, tempo.to_bytes(3, "big"))),
        (0, 0, meta(0x58, bytes([4, 2, 24, 8]))),
        (0, 0, meta(0x59, bytes([0, 0]))),   # C major
    ]
    for i, (name, _) in enumerate(SECTIONS):
        conductor.append((i * 8 * BAR * PPQ, 1, meta(0x06, name.encode())))
    conductor.append((LOOP_BEATS * PPQ, 1, meta(0x06, b"LOOP")))
    chunks = [chunk(conductor)]
    span = LOOP_BEATS * PPQ
    for key, name, ch, prog, vol, pn in MIDI_TRACKS:
        ev = [(0, 0, meta(0x03, name.encode())),
              (0, 0, bytes([0xB0 | ch, 7, vol])),
              (0, 0, bytes([0xB0 | ch, 10, pn]))]
        if ch != 9:
            ev.append((0, 0, bytes([0xC0 | ch, prog])))
        for st, du, p, v, t, _ in score[key]:
            on = int(round(t / SPB * PPQ)) % span          # «живое» время, как в аудио
            off = max(on + 1, on + int(round(du * PPQ)))
            ev.append((on, 2, bytes([0x90 | ch, p, v])))
            ev.append((off, 1, bytes([0x80 | ch, p, 0])))   # note-off раньше note-on на том же тике
        chunks.append(chunk(ev))
    head = b"MThd" + struct.pack(">IHHH", 6, 1, len(chunks), PPQ)
    pathlib.Path(path).write_bytes(head + b"".join(chunks))


# --- main -----------------------------------------------------------------------
def main():
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "music_out")
    out.mkdir(parents=True, exist_ok=True)
    stems = os.environ.get("MUSIC_STEMS")
    if stems:
        pathlib.Path(stems).mkdir(parents=True, exist_ok=True)
    score = compose()
    write_midi(score, out / "bgm_main.mid")
    stereo = mix(score, stems)
    y, clipped = master(stereo)
    dither = (rng.random(y.shape) - rng.random(y.shape)) / 32768
    pcm = np.clip(np.round((y + dither) * 32767), -32768, 32767).astype(np.int16)
    wavfile.write(out / "bgm_main.wav", SR, pcm.T)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(out / "bgm_main.wav"),
                    "-c:a", "libvorbis", "-q:a", "4", str(out / "bgm_main.ogg")], check=True)
    peak = 20 * np.log10(np.abs(y).max())
    rms = 10 * np.log10((y ** 2).mean())
    print(f"петля {N} сэмплов = {N / SR:.2f} с; пик {peak:.2f} dBFS; RMS {rms:.2f} dBFS; "
          f"в мягком лимитере {clipped * 100:.3f}% сэмплов")
    print("нот:", {k: len(v) for k, v in score.items()})


if __name__ == "__main__":
    main()
