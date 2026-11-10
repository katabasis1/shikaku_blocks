#!/usr/bin/env python3
"""Сохранение рабочей копии «Шикаку: Блоки» в Pod и архив после каждого шага.

Живёт в проекте: tools/save.py (поэтому попадает в каждый архив и не теряется при пересоздании Pod).

  Песочница:  /tmp/w/shikaku_blocks           — здесь работаем
  Pod:        /files/pod/shikaku_blocks       — постоянная копия
  Архивы:     /files/pod/backups/*.zip
  Беседа:     /files/conversation/shikaku_blocks_latest.zip — копия свежего архива в файлах текущей беседы
              (скачивается прямо из чата; backups/ при пересоздании Pod не приезжает)

Команды:
  python3 save.py                 новые и изменённые файлы -> Pod, затем пересобрать backups/shikaku_blocks_latest.zip
  python3 save.py --zip NAME.zip  то же + стабильная копия backups/NAME.zip
  python3 save.py --dry           только показать различия (ничего не пишет)
  python3 save.py --delete        ещё и удалить из Pod файлы, которых нет в песочнице
  python3 save.py --no-zip        без пересборки latest.zip (для серии мелких сохранений)
  python3 save.py --no-conv       не класть копию latest.zip в файлы беседы
  python3 save.py --pull          Pod -> песочница (если песочницы ещё нет). Если /files/pod/shikaku_blocks нет,
                                  ищет project.godot по всему Pod (проект могли загрузить во вложенную папку);
                                  нашлось несколько копий — показывает их последние записи журнала и ждёт
                                  --from ПАПКА (не угадывает: даты файлов у копий бывают одинаковые).

Беседа вне Pod (24.10): /files/pod не смонтирован — save.py пишет только архив в файлы беседы
(/files/conversation/shikaku_blocks_latest.zip) и печатает, куда его скопировать в Pod инструментом files `copy`
(`conversation-<id>/shikaku_blocks_latest.zip` -> `pod-<podId>/backups/shikaku_blocks_latest.zip`). Pod проекта —
«шикаку» (vlt_iNDjfx6LL931Sa). Лучше работать в беседе внутри Pod: тогда всё как раньше.

Что не сохраняется: кэши (__pycache__, *.pyc, tools/.levels_cache.jsonl), .godot/, build/.
Что есть в Pod, но не идёт в архив (ZIP_SKIP, с 07.10): кадры проверок docs/style_frames/G<этап>_*.png — их
пересобирают tools/*_preview.py (список — docs/style_frames/README.md). Архив от этого легче на ≈10 МБ; если Pod
пересоздадут из архива, этих кадров не будет — пересоберите нужные. С 11.10 — и скриншоты страницы docs/promo/shots/*.png (24 кадра по 1–3 МБ): их снимает сцена
tests/promo_shots.tscn в Godot у пользователя, держите их у себя или переснимите. С 12.10 — и docs/promo/video/*
(кадры и mp4 видео геймплея: сотни МБ, снимает tests/promo_video.tscn).
"""
import argparse
import fnmatch
import hashlib
import os
import shutil
import sys
import time
import zipfile

LOCAL = "/tmp/w/shikaku_blocks"
POD_ROOT = "/files/pod"
POD = os.path.join(POD_ROOT, "shikaku_blocks")
BACKUPS = os.path.join(POD_ROOT, "backups")
CONV = "/files/conversation"   # файлы текущей беседы: туда же копия latest.zip
LATEST = "shikaku_blocks_latest.zip"
ZIP_ROOT = "shikaku_blocks"

SKIP_DIRS = {"__pycache__", ".godot", "build", ".import"}
SKIP_FILES = {"tools/.levels_cache.jsonl"}
SKIP_EXT = {".pyc"}
# Только для архива: в Pod эти файлы сохраняются как обычно.
ZIP_SKIP = ["docs/style_frames/G[0-9]*.png", "docs/promo/shots/*.png", "docs/promo/video/*"]


def skipped(rel: str) -> bool:
    parts = rel.split("/")
    if any(p in SKIP_DIRS for p in parts[:-1]):
        return True
    if rel in SKIP_FILES:
        return True
    return os.path.splitext(rel)[1] in SKIP_EXT


def walk(root: str) -> dict:
    """rel -> абсолютный путь всех файлов (без пропускаемых)."""
    out = {}
    for d, dirs, files in os.walk(root, followlinks=True):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
        for f in files:
            p = os.path.join(d, f)
            rel = os.path.relpath(p, root).replace(os.sep, "/")
            if not skipped(rel):
                out[rel] = p
    return out


def sha1(path: str) -> str:
    h = hashlib.sha1()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def same(a: str, b: str) -> bool:
    if os.path.getsize(a) != os.path.getsize(b):
        return False
    return sha1(a) == sha1(b)


def diff(src: str, dst: str):
    s, d = walk(src), walk(dst) if os.path.isdir(dst) else {}
    new = sorted(r for r in s if r not in d)
    changed = sorted(r for r in s if r in d and not same(s[r], d[r]))
    extra = sorted(r for r in d if r not in s)
    return s, d, new, changed, extra


def last_log_line(proj: str) -> str:
    """Последняя запись журнала PROGRESS.md копии — чтобы различать копии с одинаковой датой файлов."""
    try:
        lines = [x for x in open(os.path.join(proj, "PROGRESS.md"), encoding="utf-8") if x.startswith("- ")]
        return lines[-1].strip()[:110] if lines else "(журнал пуст)"
    except OSError:
        return "(нет PROGRESS.md)"


def find_pod_project(choice: str = "") -> str:
    if choice:
        if not os.path.isfile(os.path.join(choice, "project.godot")):
            sys.exit(f"В {choice} нет project.godot")
        return choice
    if os.path.isfile(os.path.join(POD, "project.godot")):
        return POD
    found = []
    for d, dirs, files in os.walk(POD_ROOT, followlinks=True):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS and x != "backups"]
        if "project.godot" in files:
            found.append(d)
    if not found:
        sys.exit("В Pod нет project.godot — загрузите архив и распакуйте его в Pod")
    if len(found) > 1:
        # Дата файлов не помогает: при загрузке папкой у всех копий она одна (02.10 так чуть не взяли старую).
        print("Несколько копий проекта в Pod — выберите нужную: --pull --from ПАПКА")
        for p in found:
            print(f"  {p}\n      последняя запись: {last_log_line(p)}")
        sys.exit(1)
    return found[0]


def make_zip(src: str, name: str, conv: bool = False, pod: bool = True) -> str:
    tmp = os.path.join("/tmp", name)
    files = walk(src)
    left_out = [r for r in files if any(fnmatch.fnmatch(r, p) for p in ZIP_SKIP)]
    for r in left_out:
        del files[r]
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for rel in sorted(files):
            z.write(files[rel], ZIP_ROOT + "/" + rel)
    with zipfile.ZipFile(tmp) as z:
        bad = z.testzip()
        if bad:
            sys.exit(f"Архив повреждён: {bad}")
    if not pod:  # беседа вне Pod: архив только в файлы беседы (без .part — иначе тип файла x-partial-download)
        out = os.path.join(CONV, name)
        shutil.copyfile(tmp, out)
        if not same(tmp, out):
            sys.exit(f"Копия архива в беседе не совпала: {out}")
        print(f"архив (только беседа): {out} ({len(files)} файлов, {os.path.getsize(out) // 1024} КБ)")
        return out
    os.makedirs(BACKUPS, exist_ok=True)
    out = os.path.join(BACKUPS, name)
    shutil.copyfile(tmp, out + ".part")
    os.replace(out + ".part", out)
    if not same(tmp, out):
        sys.exit(f"Архив в Pod не совпал с собранным: {out}")
    print(f"архив: {out} ({len(files)} файлов, {os.path.getsize(out) // 1024} КБ; "
          f"кадров проверок и скриншотов не в архиве: {len(left_out)}, см. ZIP_SKIP)")
    if conv and os.path.isdir(CONV):
        c = os.path.join(CONV, name)
        shutil.copyfile(tmp, c + ".part")
        os.replace(c + ".part", c)
        if not same(tmp, c):
            sys.exit(f"Копия архива в беседе не совпала: {c}")
        print(f"копия в беседе: {c}")
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--pull", action="store_true")
    ap.add_argument("--delete", action="store_true")
    ap.add_argument("--no-zip", action="store_true")
    ap.add_argument("--no-conv", action="store_true")
    ap.add_argument("--zip", metavar="NAME.zip")
    ap.add_argument("--from", dest="src", metavar="ПАПКА", default="",
                    help="с --pull: какую копию проекта в Pod взять, если их несколько")
    a = ap.parse_args()
    t0 = time.time()

    if a.pull:
        src = find_pod_project(a.src)
        if os.path.exists(LOCAL):
            _, _, new, changed, extra = diff(LOCAL, src)
            sys.exit(f"{LOCAL} уже есть (возможны несохранённые правки: только в песочнице {len(new)}, "
                     f"отличаются {len(changed)}, только в Pod {len(extra)}). Сначала: save.py --dry")
        os.makedirs(os.path.dirname(LOCAL), exist_ok=True)
        files = walk(src)
        for rel, p in files.items():
            q = os.path.join(LOCAL, rel)
            os.makedirs(os.path.dirname(q), exist_ok=True)
            shutil.copyfile(p, q)
        print(f"взято из {src}: {len(files)} файлов -> {LOCAL}")
        if src != POD:
            print(f"ВНИМАНИЕ: проект лежит не в {POD}. Переложите: save.py --delete (запишет в {POD})")
        return

    if not os.path.isdir(LOCAL):
        sys.exit(f"Нет {LOCAL}. Сначала: python3 save.py --pull")
    if not os.path.isdir(POD_ROOT):
        # Беседа вне Pod (24.10): Pod не смонтирован — только архив в беседе, в Pod его копирует агент.
        if a.dry:
            print(f"{POD_ROOT} не смонтирован (беседа вне Pod) — сравнивать не с чем")
            return
        out = make_zip(LOCAL, a.zip or LATEST, pod=False)
        print("Pod не смонтирован. Скопируйте архив в Pod инструментом files copy:\n"
              f"  source: conversation-<id>/{os.path.basename(out)}\n"
              f"  dest:   pod-vlt_iNDjfx6LL931Sa/backups/{os.path.basename(out)}")
        print(f"готово за {time.time() - t0:.1f} с")
        return
    s, d, new, changed, extra = diff(LOCAL, POD)
    for r in new:
        print("+", r)
    for r in changed:
        print("~", r)
    for r in extra:
        print("-" if a.delete else "?", r)
    if a.dry:
        print(f"новых {len(new)}, изменённых {len(changed)}, только в Pod {len(extra)} (--dry: ничего не записано)")
        return

    for r in new + changed:
        q = os.path.join(POD, r)
        os.makedirs(os.path.dirname(q), exist_ok=True)
        shutil.copyfile(s[r], q + ".part")
        os.replace(q + ".part", q)
        if not same(s[r], q):
            sys.exit(f"Не совпало после записи: {r}")
    if a.delete:
        for r in extra:
            os.remove(d[r])
    elif extra:
        print(f"{len(extra)} файлов только в Pod (?) — оставлены; удалить: --delete. "
              "Если файл записан прямо в Pod, сначала заберите его в песочницу")
    print(f"Pod: записано {len(new) + len(changed)} (новых {len(new)}, изменённых {len(changed)})"
          + (f", удалено {len(extra)}" if a.delete else ""))

    if not a.no_zip:
        make_zip(LOCAL, LATEST, conv=not a.no_conv)
    if a.zip:
        make_zip(LOCAL, a.zip)
    print(f"готово за {time.time() - t0:.1f} с")


if __name__ == "__main__":
    main()
