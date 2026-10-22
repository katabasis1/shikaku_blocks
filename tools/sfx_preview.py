#!/usr/bin/env python3
"""Предпрослушка звука (этап 15.5): «уровень» под музыку — как в игре, без Godot.

Сводит assets/sfx/*.wav с громкостью узлов autoload/audio.tscn (volume_db), высотами как в игре
(Audio.place_semitones — нота постановки по площади и серии, JuiceConfig.combo_semitones — линия по силе хода,
star_semitones — звёзды до-ми-соль) и приглушением музыки (Audio.DUCK: удар победы и джингл, −8 dB, вход 0,15 с,
возврат 0,8 с). Музыка — assets/music/bgm_main.ogg на −12 dB. Числа берутся из файлов проекта, поэтому после
`make_sfx.py` предпрослушку достаточно пересобрать.

    python3 tools/sfx_preview.py      # docs/sfx/preview_level.mp3, preview_level_phone.mp3, all_sounds.mp3

preview_level.mp3        — уровень целиком: подъём, поворот, постановки с нотами (серия растёт), промах, линия,
                           тупик и отмена, подсказка, линия сильнее, последний блок — удар победы, звёзды, джингл,
                           «Далее»; музыка приглушается под победу и возвращается.
preview_level_phone.mp3  — то же «через динамик телефона»: без низа ниже 300 Гц и верха выше 8 кГц, моно.
all_sounds.mp3           — все звуки по очереди, без музыки (каждый на своей громкости из audio.tscn).

Нужны numpy, scipy и ffmpeg (декод ogg, кодирование mp3).
"""
import os
import re
import subprocess
import sys
import wave

import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "sfx")


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def const_num(src, name):
    m = re.search(r"^const\s+%s\s*(?::\s*\w+\s*)?:?=\s*(-?[\d.]+)" % name, src, re.M)
    if m is None:
        sys.exit("нет const %s" % name)
    return float(m.group(1))


def const_ints(src, name, export=False):
    pat = (r"@export var %s\s*:=\s*PackedInt32Array\(\[([^\]]*)\]\)" if export
           else r"^const\s+%s\s*:\s*Array\[int\]\s*=\s*\[([^\]]*)\]") % name
    m = re.search(pat, src, re.M)
    if m is None:
        sys.exit("нет %s" % name)
    return [int(v) for v in m.group(1).split(",")]


AUDIO = read("autoload/audio.gd")
JUICE = read("scripts/juice_config.gd")
GAME = read("scenes/game/game.gd")
PANEL = read("scenes/ui/win_panel.gd")
SCENE = read("autoload/audio.tscn")

PLACE_SCALE = const_ints(AUDIO, "PLACE_SCALE")
PLACE_AREA_MIN = const_ints(AUDIO, "PLACE_AREA_MIN")
STREAK_WINDOW = const_num(AUDIO, "PLACE_STREAK_WINDOW")
STREAK_MAX = int(const_num(AUDIO, "PLACE_STREAK_MAX"))
MUSIC_DB = const_num(AUDIO, "MUSIC_VOLUME_DB")
DUCK_DB = const_num(AUDIO, "MUSIC_DUCK_DB")
DUCK_IN = const_num(AUDIO, "MUSIC_DUCK_IN")
RESTORE = const_num(AUDIO, "MUSIC_RESTORE_TIME")
DUCK = {k: float(v) for k, v in re.findall(r"(\w+):\s*([\d.]+)", re.search(r"^const DUCK := \{([^}]*)\}", AUDIO, re.M).group(1))}
COMBO = const_ints(JUICE, "combo_semitones", export=True)
STARS = const_ints(JUICE, "star_semitones", export=True)
STAR_SLAM = float(re.search(r"@export var star_slam_time := ([\d.]+)", JUICE).group(1))
FLOAT = float(re.search(r"@export var hint_float_time := ([\d.]+)", JUICE).group(1))
WIN_SHOW_AT = const_num(GAME, "WIN_SHOW_AT")
STARS_AT = const_num(PANEL, "STARS_AT")
STAR_STEP = const_num(PANEL, "STAR_STEP")
JINGLE_AT = const_num(PANEL, "JINGLE_AT")
CONST_NAME = dict((n, c) for c, n in re.findall(r'^const ([A-Z_]+) := &"(\w+)"', AUDIO, re.M))


def volumes():
    """volume_db узлов audio.tscn: {Имя: dB}."""
    res = {}
    for part in re.split(r"\n(?=\[)", SCENE):
        m = re.match(r'\[node name="(\w+)" type="AudioStreamPlayer"', part)
        if m:
            v = re.search(r"volume_db = (-?[\d.]+)", part)
            res[m.group(1)] = float(v.group(1)) if v else 0.0
    return res


VOL = volumes()


def load_wav(name):
    with wave.open(os.path.join(ROOT, "assets", "sfx", name.lower() + ".wav")) as w:
        assert w.getframerate() == SR and w.getsampwidth() == 2
        x = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float64) / 32768.0
        if w.getnchannels() == 2:
            x = x.reshape(-1, 2).mean(axis=1)
    return x


WAV = {n: load_wav(n) for n in VOL if n != "Music"}


def place_semitones(area, streak):
    step = len(PLACE_AREA_MIN) - 1
    for k, a in enumerate(PLACE_AREA_MIN):
        if area >= a:
            step = k
            break
    step += max(0, min(streak, STREAK_MAX))
    return PLACE_SCALE[min(step, len(PLACE_SCALE) - 1)]


def pitched(x, pitch):
    """pitch_scale как в Godot: быстрее и выше (пересэмплирование)."""
    if abs(pitch - 1.0) < 1e-9:
        return x
    n = int(len(x) / pitch)
    return np.interp(np.arange(n) * pitch, np.arange(len(x)), x)


def music(total):
    """bgm_main.ogg -> моно float, с начала трека, длиной total с (петля, если короче)."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(ROOT, "assets", "music", "bgm_main.ogg"),
                          "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], check=True, capture_output=True).stdout
    m = np.frombuffer(raw, "<f4").astype(np.float64)
    n = int(total * SR)
    return np.tile(m, n // len(m) + 1)[:n]


class Mix:
    def __init__(self, total):
        self.n = int(total * SR)
        self.sfx = np.zeros(self.n)
        self.log = []
        self.ducks = []          # (t, duration)
        self.rand = np.random.default_rng(15)
        self.last_note = -1e9
        self.streak = 0

    def play(self, name, t, variation=0.05, base=1.0):
        pitch = max(0.05, base + (self.rand.uniform(-variation, variation) if variation else 0.0))
        x = pitched(WAV[name], pitch) * 10 ** (VOL[name] / 20)
        i = int(t * SR)
        end = min(self.n, i + len(x))
        self.sfx[i:end] += x[:end - i]
        self.log.append((t, name, pitch))
        const = CONST_NAME.get(name)
        if const in DUCK:
            self.ducks.append((t, DUCK[const]))

    def note(self, t, area, silent=False):
        """Нота постановки как Game._play_place_note (silent — только серия: ноту заменяет линия или победа)."""
        self.streak = self.streak + 1 if t - self.last_note <= STREAK_WINDOW else 0
        self.last_note = t
        if not silent:
            self.play("Note", t, 0.0, 2 ** (place_semitones(area, self.streak) / 12))

    def reset_streak(self):
        self.streak = 0
        self.last_note = -1e9

    def place(self, t, area, line_power=None, last=False):
        """Блок лёг (Game._on_block_landed): удар, нота (у хода с линией и последнего — нет), линия по силе хода."""
        self.play("Place", t, 0.08)
        self.note(t, area, silent=last or line_power is not None)
        if line_power is not None:
            self.play("Line", t, 0.0, 2 ** (COMBO[min(line_power, len(COMBO) - 1)] / 12))

    def music_gain_db(self):
        """volume_db музыки по времени: твины Audio.duck_music (новый вызов гасит прошлый, идёт от текущего)."""
        g = np.full(self.n, MUSIC_DB)
        lo = MUSIC_DB + DUCK_DB
        for t, dur in sorted(self.ducks):
            i = int(t * SR)
            start = g[i] if i < self.n else MUSIC_DB
            seg = np.arange(self.n - i) / SR
            v = np.where(seg < DUCK_IN, start + (lo - start) * seg / DUCK_IN, lo)
            back = DUCK_IN + dur
            v = np.where(seg >= back, lo + (MUSIC_DB - lo) * np.clip((seg - back) / RESTORE, 0, 1), v)
            g[i:] = v
        return g

    def render(self, with_music=True):
        out = self.sfx.copy()
        if with_music:
            out += music(self.n / SR) * 10 ** (self.music_gain_db() / 20)
        return out


def level():
    """Сценарий уровня: времена — как живой игрок, правила звука — как в игре."""
    m = Mix(26.0)
    t = 1.0
    m.play("Pick", t); m.place(t + 0.55, 6)                                   # 2×3: нота по площади
    t = 2.3
    m.play("Pick", t); m.play("Rotate", t + 0.35); m.place(t + 0.9, 4)        # поворот, серия +1
    t = 4.1
    m.play("Pick", t); m.play("Miss", t + 0.6)                                # промах — тихое «блюк»
    t = 5.3
    m.play("Pick", t); m.place(t + 0.5, 3, line_power=0)                      # линия: «Отлично!»
    t = 6.9
    m.play("Pick", t); m.place(t + 0.5, 2)                                    # серия выше
    m.reset_streak(); m.play("Error", t + 0.5 + 0.45, 0.0)                    # тупик: «у-у» через 0,45 с
    t = 8.6
    m.play("Undo", t); m.reset_streak()                                       # отмена
    t = 10.6                                                                  # пауза дольше окна серии
    m.play("Hint", t, 0.0); m.place(t + FLOAT, 2)                             # подсказка: блок долетел
    t = 12.3
    m.play("Pick", t); m.place(t + 0.45, 4, line_power=1)                     # две линии сразу
    t = 13.8
    m.play("Pick", t); m.place(t + 0.5, 1, line_power=2)                      # серия линий: «Супер!»
    t = 15.6
    m.play("Pick", t)
    hit = t + 0.5
    m.place(hit, 3, last=True)                                                # последний блок: удар победы
    m.play("Win", hit, 0.0)
    panel = hit + WIN_SHOW_AT
    for i in range(2):                                                        # 2 звезды (отмена и подсказка)
        m.play("Star", panel + STARS_AT + STAR_STEP * i + STAR_SLAM, 0.0, 2 ** (STARS[i] / 12))
    m.play("Jingle", panel + JINGLE_AT, 0.0)
    m.play("Click", panel + 3.2)                                              # «Далее»
    return m


def all_sounds():
    order = ["Click", "Pick", "Rotate", "Miss", "Place", "Note", "Undo", "Error", "Hint", "Line", "Star",
             "Jingle", "Win"]
    m = Mix(sum(len(WAV[n]) / SR + 0.6 for n in order) + 0.5)
    t = 0.4
    for n in order:
        m.play(n, t, 0.0)
        t += len(WAV[n]) / SR + 0.6
    return m


def phone(x):
    """«Динамик телефона»: без низа ниже 300 Гц и верха выше 8 кГц."""
    x = sosfilt(butter(4, 300, "highpass", fs=SR, output="sos"), x)
    return sosfilt(butter(2, 8000, "lowpass", fs=SR, output="sos"), x)


def write_mp3(path, x):
    peak = np.abs(x).max()
    if peak > 0.98:
        print("  внимание: %s — пик %.2f, ограничен до 0,98" % (os.path.basename(path), peak))
        x = x * (0.98 / peak)
    data = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libmp3lame", "-b:a", "128k", path], input=data, check=True)
    print("  %s  %.1f с  пик %.1f dBFS" % (os.path.relpath(path, ROOT), len(x) / SR, 20 * np.log10(peak + 1e-12)))


def main():
    os.makedirs(OUT, exist_ok=True)
    lv = level()
    for t, n, p in lv.log:
        print("  %6.2f с  %-6s ×%.3f" % (t, n, p))
    full = lv.render()
    write_mp3(os.path.join(OUT, "preview_level.mp3"), full)
    write_mp3(os.path.join(OUT, "preview_level_phone.mp3"), phone(full))
    write_mp3(os.path.join(OUT, "all_sounds.mp3"), all_sounds().render(with_music=False))


if __name__ == "__main__":
    main()
