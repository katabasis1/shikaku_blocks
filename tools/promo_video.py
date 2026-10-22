#!/usr/bin/env python3
"""Ролики игрового процесса для страницы Яндекс Игр (этап 16.5c): кадры сцены tests/promo_video.tscn -> mp4 со звуком.

  python3 tools/promo_video.py                собрать все снятые ролики:
                                              docs/promo/video/frames_<формат>_<язык>/ -> docs/promo/video/<формат>_<язык>.mp4
  python3 tools/promo_video.py --only vertical_ru   только этот ролик (через запятую — несколько)
  python3 tools/promo_video.py --no-sound     без звука
  python3 tools/promo_video.py --clean        после удачной сборки удалить кадры (≈150–250 МБ на ролик)
  python3 tools/promo_video.py --force        собрать, даже если съёмка с замечаниями (meta.json)
  python3 tools/promo_video.py --check        только проверить готовые mp4
  python3 tools/promo_video.py --selftest     проверка самого скрипта без Godot: искусственные кадры -> mp4

Форматы — поля консоли: horizontal 1920×1080 — «Горизонтальное видео» (обязательное), vertical 1080×1920 —
«Вертикальное видео». Язык в имени — язык интерфейса в кадре (ролик для вкладки этого языка).

Нужен ffmpeg (вместе с ним ffprobe) в PATH. Windows: `winget install Gyan.FFmpeg` и новое окно консоли (или скачать
с ffmpeg.org). Нет ffmpeg — заархивируйте папки docs/promo/video/frames_* и пришлите: соберу в песочнице.

Звук — звук самой игры, сведённый по списку. Сцена пишет каждый запрос звука (сигнал Audio.requested: кадр, звук,
высота) в events.tsv; здесь звук берётся из файла узла autoload/audio.tscn с его volume_db и шиной, играется с той же
высотой (pitch_scale в Godot — ускорение: выше и короче), фоновая музыка — assets/music/bgm_main.ogg с громкостью
Audio.MUSIC_VOLUME_DB и приглушением под победу и джингл (DUCK, MUSIC_DUCK_DB, MUSIC_DUCK_IN, MUSIC_RESTORE_TIME —
числа читаются из autoload/audio.gd). Голоса (Audio.VOICES) не моделируются: звук не обрывает свой прошлый хвост.
Потом громкость ролика выравнивается (loudnorm, LOUDNESS), в конце звук гаснет за FADE_OUT.
Только стандартная библиотека Python (без numpy).
"""
import argparse
import array
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIDEO_DIR = os.path.join(ROOT, "docs", "promo", "video")
AUDIO_TSCN = os.path.join(ROOT, "autoload", "audio.tscn")
AUDIO_GD = os.path.join(ROOT, "autoload", "audio.gd")
BUS_LAYOUT = os.path.join(ROOT, "default_bus_layout.tres")

OUT_FPS = 30
RATE = 44100
CRF = 18
AUDIO_BITRATE = "160k"
LOUDNESS = "I=-16:TP=-1.5:LRA=11"
MUSIC_FADE_IN = 0.3
FADE_OUT = 1.0
## Размеры кадра по формату (как FORMATS в tests/promo_video.gd).
SIZES = {"horizontal": (1920, 1080), "vertical": (1080, 1920)}
## Пределы — ПРЕДПОЛОЖЕНИЕ, сверить с подсказкой «?» у полей видео в консоли; поменялись — поправить здесь.
MAX_SECONDS = 30.0
MIN_SECONDS = 5.0
MAX_MB = 100.0


def fail(msg: str) -> None:
    print("ОШИБКА: " + msg)
    sys.exit(1)


def need_ffmpeg() -> None:
    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            fail(f"нет {tool} в PATH. Windows: winget install Gyan.FFmpeg, затем новое окно консоли. "
                 "Или заархивируйте папки docs/promo/video/frames_* и пришлите — соберу в песочнице.")


def run(cmd: list, quiet: bool = True) -> subprocess.CompletedProcess:
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if res.returncode != 0:
        tail = res.stderr.decode("utf-8", "replace").strip().splitlines()[-12:]
        fail("команда не прошла: " + " ".join(cmd[:6]) + " …\n  " + "\n  ".join(tail))
    return res


# --- Звук игры ----------------------------------------------------------------

def res_path(p: str) -> str:
    return os.path.join(ROOT, p.replace("res://", "").replace("/", os.sep))


def parse_audio_scene() -> dict:
    """{звук: {"file": путь, "db": volume_db узла + шины}} из autoload/audio.tscn и default_bus_layout.tres."""
    text = open(AUDIO_TSCN, encoding="utf-8").read()
    ext = dict((m.group(2), m.group(1)) for m in re.finditer(
        r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', text))
    buses = {}
    if os.path.exists(BUS_LAYOUT):
        lay = open(BUS_LAYOUT, encoding="utf-8").read()
        for m in re.finditer(r'bus/(\d+)/name = &"(\w+)"', lay):
            v = re.search(rf'bus/{m.group(1)}/volume_db = (-?[\d.]+)', lay)
            buses[m.group(2)] = float(v.group(1)) if v else 0.0
    sounds = {}
    for block in re.split(r"\n(?=\[node )", text):
        head = re.match(r'\[node name="(\w+)" type="AudioStreamPlayer"', block)
        if not head:
            continue
        stream = re.search(r'stream = ExtResource\("([^"]+)"\)', block)
        if not stream or stream.group(1) not in ext:
            continue
        db = re.search(r"volume_db = (-?[\d.]+)", block)
        bus = re.search(r'bus = &"(\w+)"', block)
        sounds[head.group(1)] = {
            "file": res_path(ext[stream.group(1)]),
            "db": (float(db.group(1)) if db else 0.0) + buses.get(bus.group(1) if bus else "Master", 0.0),
        }
    return sounds


def parse_audio_consts() -> dict:
    """Числа музыки и приглушения из autoload/audio.gd."""
    text = open(AUDIO_GD, encoding="utf-8").read()

    def num(name: str) -> float:
        m = re.search(rf"^const {name} := (-?[\d.]+)", text, re.M)
        if not m:
            fail(f"в autoload/audio.gd нет const {name}")
        return float(m.group(1))

    duck = {}
    m = re.search(r"^const DUCK := \{([^}]*)\}", text, re.M)
    if m:
        for k, v in re.findall(r"(\w+):\s*(-?[\d.]+)", m.group(1)):
            name = re.search(rf'^const {k} := &"(\w+)"', text, re.M)
            duck[name.group(1) if name else k] = float(v)
    return {"music_db": num("MUSIC_VOLUME_DB"), "duck_db": num("MUSIC_DUCK_DB"), "duck_in": num("MUSIC_DUCK_IN"),
            "restore": num("MUSIC_RESTORE_TIME"), "duck": duck}


def read_wav(path: str) -> list:
    """Моно float -1..1 на частоте RATE (стерео сводится, другая частота — пересчитывается)."""
    with wave.open(path, "rb") as w:
        ch, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if width != 2:
        fail(f"{path}: ждали 16-бит PCM")
    data = array.array("h")
    data.frombytes(raw)
    if sys.byteorder == "big":
        data.byteswap()
    mono = [(data[i] + data[i + 1]) / 65536.0 for i in range(0, len(data), 2)] if ch == 2 else \
        [v / 32768.0 for v in data]
    if rate != RATE:
        mono = resample(mono, rate / RATE)
    return mono


def resample(src: list, speed: float) -> list:
    """Проигрывание со скоростью speed (pitch_scale): линейная интерполяция, как ресэмплер Godot."""
    if abs(speed - 1.0) < 1e-6:
        return list(src)
    n = int(len(src) / speed)
    last = len(src) - 1
    out = [0.0] * n
    for i in range(n):
        x = i * speed
        k = int(x)
        if k >= last:
            out[i] = src[last]
        else:
            f = x - k
            out[i] = src[k] + (src[k + 1] - src[k]) * f
    return out


def decode_music(path: str, seconds: float) -> tuple:
    """Стерео float L, R длиной seconds (трек по кругу, как ogg.loop в Audio._ready)."""
    raw = run(["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-ac", "2", "-ar", str(RATE), "-"]).stdout
    data = array.array("h")
    data.frombytes(raw)
    if sys.byteorder == "big":
        data.byteswap()
    frames = len(data) // 2
    need = int(seconds * RATE) + 1
    left = [0.0] * need
    right = [0.0] * need
    for i in range(need):
        j = (i % frames) * 2
        left[i] = data[j] / 32768.0
        right[i] = data[j + 1] / 32768.0
    return left, right


def music_gain_db(events: list, fps: float, seconds: float, c: dict, step: float = 0.01) -> list:
    """Громкость музыки (dB) с шагом step: Audio.duck_music — к music+duck за duck_in, держать duration, назад за
    restore; повторный вызов убивает прежний твин и начинает от текущей громкости."""
    starts = sorted((int(f) / fps, c["duck"][s]) for f, s, _p in events if s in c["duck"])
    base, low = c["music_db"], c["music_db"] + c["duck_db"]
    out = []
    cur = base
    seg = None  # (t0, from_db, duration)
    k = 0
    n = int(seconds / step) + 2
    for i in range(n):
        t = i * step
        while k < len(starts) and starts[k][0] <= t:
            seg = (starts[k][0], cur, starts[k][1])
            k += 1
        if seg is not None:
            t0, from_db, hold = seg
            dt = t - t0
            if dt < c["duck_in"]:
                cur = from_db + (low - from_db) * dt / c["duck_in"]
            elif dt < c["duck_in"] + hold:
                cur = low
            elif dt < c["duck_in"] + hold + c["restore"]:
                cur = low + (base - low) * (dt - c["duck_in"] - hold) / c["restore"]
            else:
                cur = base
                seg = None
        out.append(cur)
    return out


def read_events(path: str) -> list:
    events = []
    if not os.path.exists(path):
        return events
    for line in open(path, encoding="utf-8"):
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 3:
            events.append((int(parts[0]), parts[1], float(parts[2])))
    return events


def mix_audio(events: list, fps: float, seconds: float, out_wav: str) -> dict:
    """Звуки по events + музыка -> стерео WAV 16 бит. Возвращает {звук: сколько раз} (и пропущенные)."""
    sounds = parse_audio_scene()
    consts = parse_audio_consts()
    n = int(seconds * RATE) + 1
    left = [0.0] * n
    right = [0.0] * n
    cache = {}
    stats = {}
    for frame, name, pitch in events:
        info = sounds.get(name)
        if info is None or not os.path.exists(info["file"]):
            stats["нет звука " + name] = stats.get("нет звука " + name, 0) + 1
            continue
        if name not in cache:
            cache[name] = read_wav(info["file"])
        key = (name, round(pitch, 4))
        src = cache.get(key)
        if src is None:
            src = resample(cache[name], max(pitch, 0.05))
            cache[key] = src
        gain = 10.0 ** (info["db"] / 20.0)
        o = int(round(frame / fps * RATE))
        end = min(n, o + len(src))
        for i in range(o, end):
            v = src[i - o] * gain
            left[i] += v
            right[i] += v
        stats[name] = stats.get(name, 0) + 1
    music = sounds.get("Music")
    if music and os.path.exists(music["file"]):
        ml, mr = decode_music(music["file"], seconds)
        env = music_gain_db(events, fps, seconds, consts)
        block = int(RATE * 0.01)
        fade_in = int(MUSIC_FADE_IN * RATE)
        for i in range(n):
            g = 10.0 ** (env[i // block] / 20.0)
            if i < fade_in:
                g *= i / fade_in
            left[i] += ml[i] * g
            right[i] += mr[i] * g
    else:
        stats["нет музыки"] = 1
    pcm = array.array("h", bytes(4 * n))
    for i in range(n):
        pcm[2 * i] = max(-32767, min(32767, int(left[i] * 32767)))
        pcm[2 * i + 1] = max(-32767, min(32767, int(right[i] * 32767)))
    if sys.byteorder == "big":
        pcm.byteswap()
    with wave.open(out_wav, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    return stats


# --- Ролик --------------------------------------------------------------------

def meta_problems(meta: dict, frames_on_disk: int) -> list:
    probs = []
    if frames_on_disk != int(meta.get("frames", -1)):
        probs.append(f"кадров на диске {frames_on_disk}, в meta.json {meta.get('frames')} — съёмка оборвалась?")
    for key, what in (("misses", "блок не встал"), ("bad_steps", "шаг кадра не постоянный (нужен --fixed-fps)"),
                      ("write_errors", "кадры не записались")):
        if int(meta.get(key, 0)) > 0:
            probs.append(f"{what}: {meta.get(key)}")
    if abs(int(meta.get("skipped", 0))) > 2:
        probs.append(f"пропущено кадров: {meta.get('skipped')} (окно сворачивали?)")
    size = SIZES.get(meta.get("format", ""))
    if size and (int(meta.get("width", 0)), int(meta.get("height", 0))) != size:
        probs.append(f"размер {meta.get('width')}×{meta.get('height')}, ждали {size[0]}×{size[1]}")
    return probs


def build(frames_dir: str, out_mp4: str, sound: bool, force: bool) -> bool:
    name = os.path.basename(frames_dir).replace("frames_", "", 1)
    meta_path = os.path.join(frames_dir, "meta.json")
    if not os.path.exists(meta_path):
        print(f"  {name}: нет meta.json — съёмка не закончилась, пропускаю")
        return False
    meta = json.load(open(meta_path, encoding="utf-8"))
    pattern = meta.get("pattern", "f_%05d.jpg")
    ext = os.path.splitext(pattern)[1]
    count = len([f for f in os.listdir(frames_dir) if f.endswith(ext)])
    probs = meta_problems(meta, count)
    if probs:
        print(f"  {name}: замечания съёмки:\n    - " + "\n    - ".join(probs))
        if not force:
            print("    не собираю: переснимите (tests/promo_video.tscn) или --force")
            return False
    fps = float(meta.get("fps", OUT_FPS))
    seconds = count / fps
    with tempfile.TemporaryDirectory() as tmp:
        cmd = ["ffmpeg", "-y", "-v", "error", "-framerate", f"{fps:g}", "-i", os.path.join(frames_dir, pattern)]
        if sound:
            wav = os.path.join(tmp, "sound.wav")
            stats = mix_audio(read_events(os.path.join(frames_dir, "events.tsv")), fps, seconds, wav)
            cmd += ["-i", wav]
            missing = [k for k in stats if k.startswith("нет")]
            if missing:
                print(f"  {name}: звук — " + ", ".join(missing))
        cmd += ["-map", "0:v:0"]
        if sound:
            fade_at = max(0.0, seconds - FADE_OUT)
            cmd += ["-map", "1:a:0", "-af",
                    f"loudnorm={LOUDNESS},aresample={RATE},afade=t=out:st={fade_at:.3f}:d={FADE_OUT}",
                    "-c:a", "aac", "-b:a", AUDIO_BITRATE, "-ar", str(RATE)]
        cmd += ["-vf", f"fps={OUT_FPS},format=yuv420p", "-c:v", "libx264", "-preset", "slow", "-crf", str(CRF),
                "-profile:v", "high", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                "-t", f"{seconds:.3f}", out_mp4]
        run(cmd)
    print(f"  {name}: {count} кадров, {seconds:.1f} с -> {os.path.relpath(out_mp4, ROOT)}")
    return True


def probe(path: str) -> dict:
    out = run(["ffprobe", "-v", "error", "-show_entries",
               "stream=codec_type,codec_name,width,height,avg_frame_rate:format=duration,size",
               "-of", "json", path]).stdout
    return json.loads(out)


def check_mp4(path: str, fmt: str) -> list:
    info = probe(path)
    probs = []
    video = [s for s in info.get("streams", []) if s.get("codec_type") == "video"]
    audio = [s for s in info.get("streams", []) if s.get("codec_type") == "audio"]
    dur = float(info.get("format", {}).get("duration", 0))
    mb = int(info.get("format", {}).get("size", 0)) / 1e6
    if not video:
        return ["нет видеодорожки"]
    v = video[0]
    want = SIZES.get(fmt)
    if want and (v.get("width"), v.get("height")) != want:
        probs.append(f"размер {v.get('width')}×{v.get('height')}, нужен {want[0]}×{want[1]}")
    if v.get("codec_name") != "h264":
        probs.append(f"кодек {v.get('codec_name')}, ждали h264")
    if dur > MAX_SECONDS or dur < MIN_SECONDS:
        probs.append(f"длина {dur:.1f} с вне {MIN_SECONDS:g}–{MAX_SECONDS:g} с (предел — сверить в консоли)")
    if mb > MAX_MB:
        probs.append(f"{mb:.1f} МБ > {MAX_MB:g} МБ")
    print(f"  {os.path.basename(path)}: {v.get('width')}×{v.get('height')}, {dur:.1f} с, {mb:.1f} МБ, "
          f"{'звук есть' if audio else 'без звука'}" + (" — " + "; ".join(probs) if probs else " — ок"))
    return probs


def check_all(names=None) -> int:
    files = sorted(f for f in os.listdir(VIDEO_DIR) if f.endswith(".mp4")) if os.path.isdir(VIDEO_DIR) else []
    if names:
        files = [f for f in files if f[:-4] in names]
    if not files:
        print("готовых mp4 нет")
        return 1
    bad = 0
    for f in files:
        bad += len(check_mp4(os.path.join(VIDEO_DIR, f), f.split("_")[0]))
    return 1 if bad else 0


# --- Самопроверка ---------------------------------------------------------------

def selftest() -> int:
    """Искусственные кадры (testsrc2) и звуки по событиям -> mp4; проверяем размер, длину, звук не тишина."""
    need_ffmpeg()
    tmp = tempfile.mkdtemp(prefix="promo_video_")
    try:
        frames = os.path.join(tmp, "frames_horizontal_ru")
        os.makedirs(frames)
        fps, count = 30, 165  # 5,5 с — не короче MIN_SECONDS
        run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", f"testsrc2=size=1920x1080:rate={fps}",
             "-frames:v", str(count), "-q:v", "3", "-start_number", "0", os.path.join(frames, "f_%05d.jpg")])
        meta = {"format": "horizontal", "lang": "ru", "fps": fps, "width": 1920, "height": 1080, "frames": count,
                "pattern": "f_%05d.jpg", "misses": 0, "bad_steps": 0, "skipped": 0, "write_errors": 0}
        json.dump(meta, open(os.path.join(frames, "meta.json"), "w"))
        with open(os.path.join(frames, "events.tsv"), "w", encoding="utf-8") as f:
            f.write("# кадр\tзвук\tвысота\n5\tPick\t1.02\n20\tPlace\t0.97\n20\tNote\t1.1225\n40\tWin\t1.0\n"
                    "55\tJingle\t1.0\n60\tStar\t1.12\n70\tUnknownSound\t1.0\n")
        out = os.path.join(tmp, "horizontal_ru.mp4")
        ok = build(frames, out, sound=True, force=False)
        probs = [] if ok else ["сборка не прошла"]
        if ok:
            probs += check_mp4(out, "horizontal")
            info = probe(out)
            dur = float(info["format"]["duration"])
            if abs(dur - count / fps) > 0.15:
                probs.append(f"длина {dur:.2f} с, ждали {count / fps:.2f}")
            if not [s for s in info["streams"] if s.get("codec_type") == "audio"]:
                probs.append("нет звука")
            vol = subprocess.run(["ffmpeg", "-v", "info", "-i", out, "-af", "volumedetect", "-f", "null", "-"],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE).stderr.decode("utf-8", "replace")
            m = re.search(r"max_volume: (-?[\d.]+) dB", vol)
            if not m or float(m.group(1)) < -30:
                probs.append("звук почти тишина")
            # Приглушение музыки под победу: громкость ниже базы сразу после Win и вернулась к концу.
            c = parse_audio_consts()
            env = music_gain_db([(40, "Win", 1.0)], fps, 10.0, c)
            if not (env[0] == c["music_db"] and abs(env[int((40 / fps + 0.5) / 0.01)] - (c["music_db"] + c["duck_db"])) < 1e-6
                    and env[-1] == c["music_db"]):
                probs.append("приглушение музыки посчитано не так")
            # Высота: pitch 2 — вдвое короче.
            if len(resample([0.0] * 1000, 2.0)) != 500:
                probs.append("resample: pitch 2 должен укорачивать вдвое")
        meta["misses"] = 1
        json.dump(meta, open(os.path.join(frames, "meta.json"), "w"))
        if build(frames, os.path.join(tmp, "bad.mp4"), sound=False, force=False):
            probs.append("съёмку с замечаниями собрал без --force")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("selftest: " + ("ок" if not probs else "ПРОБЛЕМЫ:\n  - " + "\n  - ".join(probs)))
    return 1 if probs else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--only", help="ролики через запятую, например vertical_ru,horizontal_ru")
    ap.add_argument("--no-sound", action="store_true")
    ap.add_argument("--clean", action="store_true", help="удалить кадры после удачной сборки")
    ap.add_argument("--force", action="store_true", help="собрать, даже если съёмка с замечаниями")
    ap.add_argument("--check", action="store_true", help="только проверить готовые mp4")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    need_ffmpeg()
    names = set(a.only.split(",")) if a.only else None
    if a.check:
        return check_all(names)
    dirs = sorted(d for d in os.listdir(VIDEO_DIR) if d.startswith("frames_")) if os.path.isdir(VIDEO_DIR) else []
    if names:
        dirs = [d for d in dirs if d[len("frames_"):] in names]
    if not dirs:
        print("кадров нет: сначала снимите ролики — сцена tests/promo_video.tscn в Godot (F6)")
        return 1
    print(f"Сборка роликов ({len(dirs)}):")
    built = []
    for d in dirs:
        name = d[len("frames_"):]
        out = os.path.join(VIDEO_DIR, name + ".mp4")
        if build(os.path.join(VIDEO_DIR, d), out, sound=not a.no_sound, force=a.force):
            built.append((d, name))
    print("Проверка:")
    bad = 0
    for d, name in built:
        bad += len(check_mp4(os.path.join(VIDEO_DIR, name + ".mp4"), name.split("_")[0]))
        if a.clean:
            shutil.rmtree(os.path.join(VIDEO_DIR, d), ignore_errors=True)
    if len(built) < len(dirs):
        print(f"собрано {len(built)} из {len(dirs)}")
    print("Куда: horizontal_<язык>.mp4 — «Горизонтальное видео», vertical_<язык>.mp4 — «Вертикальное видео».")
    return 0 if built and len(built) == len(dirs) and not bad else 1


if __name__ == "__main__":
    sys.exit(main())
