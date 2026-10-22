#!/usr/bin/env python3
"""Оценка размера сборки без Godot: что попадёт в .pck и сколько это весит (этап 13.8, бюджет STYLE 14).

Godot экспортирует ресурсы проекта (export_filter=all_resources): сцены, скрипты, шейдеры, переводы и
импортированные файлы. Не попадают: папки с .gdignore (docs/, music_src/), .godot/, exclude_filter из
export_presets.cfg (tests/*) и файлы, которые Godot не считает ресурсами (.py, .md, .txt, .zip …).

Оценка размера по видам (ориентир, а не точное число — точное даст только экспорт):
  PNG / SVG с compress/mode=0 (lossless) — размер файла; mipmaps/generate=true — ×4/3;
  WAV — как есть (без сжатия при импорте — верхняя граница; QOA уменьшил бы ≈ в 3,5 раза);
  OGG, TTF — как есть; текст (.gd, .tscn, .tres, .gdshader, .po) — как есть (в .pck он ещё сжимается).
Движок (wasm + js, ≈ 35–40 МБ до сжатия) сюда не входит — это общая часть любой сборки.

    python3 tools/build_size.py            # таблица по папкам и видам + проверка бюджета этапа 13
    python3 tools/build_size.py --files    # и список файлов по убыванию
"""
import fnmatch
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

RESOURCE_EXT = {".tscn", ".tres", ".gd", ".gdshader", ".gdshaderinc", ".po", ".png", ".svg", ".wav", ".ogg",
                ".ttf", ".otf", ".godot", ".cfg"}
NOT_EXPORTED = {"export_presets.cfg", "export_credentials.cfg"}
KIND = {".png": "картинки", ".svg": "картинки", ".wav": "звуки", ".ogg": "музыка", ".ttf": "шрифты",
        ".otf": "шрифты"}

# Бюджет этапа 13 (PLAN, «Готово, когда»; STYLE 14): сборка вырастает не больше чем на 3 МБ.
BUDGET_13 = 3 * 1024 * 1024
# Что этап 13 убрал из сборки (байт): game_font.ttf (подмножество Noto Sans ExtraBold, лог 29.09 13:53 — 98 КБ)
# и SVG-иконки (13.4: перенесены в docs/icons/svg_old/, их размер считается по этой папке).
REMOVED_13 = {"assets/fonts/game_font.ttf": 98 * 1024}
# Что этап 13 добавил (шаблоны путей от корня проекта).
ADDED_13 = ["assets/icons/*.png", "assets/fonts/nunito_*.ttf",
            "shaders/block.gdshader", "shaders/board.gdshader", "shaders/nest.gdshader", "shaders/ghost.gdshader",
            "shaders/shelf.gdshader", "shaders/sdf.gdshaderinc", "shaders/card.gdshader", "shaders/win_rays.gdshader",
            "shaders/pill.gdshader", "shaders/soft_shadow.gdshader", "shaders/tex_shadow.gdshader",
            "scripts/candy_button.gd", "scripts/candy_card.gd", "scripts/pill_button.gd", "scripts/pill_label.gd",
            "scripts/soft_shadow.gd", "scripts/tex_shadow.gd", "scripts/confetti.gd",
            "scenes/ui/background.gd", "scenes/game/win_backdrop.gd"]


def exclude_patterns() -> list:
    try:
        text = open(os.path.join(ROOT, "export_presets.cfg"), encoding="utf-8").read()
    except OSError:
        return []
    m = re.search(r'^exclude_filter="([^"]*)"', text, re.M)
    return [p.strip() for p in m.group(1).split(",") if p.strip()] if m else []


def import_params(path: str) -> dict:
    out = {}
    try:
        for line in open(path + ".import", encoding="utf-8"):
            if "=" in line and not line.startswith("["):
                k, v = line.strip().split("=", 1)
                out[k] = v.strip('"')
    except OSError:
        pass
    return out


def estimate(path: str, ext: str) -> int:
    size = os.path.getsize(path)
    if ext in (".png", ".svg"):
        p = import_params(path)
        if p.get("mipmaps/generate") == "true":
            size = size * 4 // 3
    return size


def exported_files() -> list:
    excl = exclude_patterns()
    out = []
    for d, dirs, files in os.walk(ROOT):
        if ".gdignore" in files:
            dirs[:] = []
            continue
        dirs[:] = sorted(x for x in dirs if not x.startswith(".") and x not in ("build", "__pycache__"))
        for f in sorted(files):
            rel = os.path.relpath(os.path.join(d, f), ROOT).replace(os.sep, "/")
            ext = os.path.splitext(f)[1].lower()
            if ext not in RESOURCE_EXT or f in NOT_EXPORTED:
                continue
            if any(fnmatch.fnmatch(rel, p) for p in excl):
                continue
            out.append((rel, ext, estimate(os.path.join(d, f), ext)))
    return out


def kb(n: int) -> str:
    return f"{n / 1024:,.0f} КБ".replace(",", " ")


def main(argv) -> int:
    files = exported_files()
    total = sum(s for _, _, s in files)
    by_dir, by_kind = {}, {}
    for rel, ext, s in files:
        top = rel.split("/")[0] if "/" in rel else "(корень)"
        by_dir[top] = by_dir.get(top, 0) + s
        k = KIND.get(ext, "текст (сцены, скрипты, шейдеры, переводы)")
        by_kind[k] = by_kind.get(k, 0) + s
    print(f"в сборку (оценка): {len(files)} файлов, {kb(total)}")
    print("по папкам:")
    for k, v in sorted(by_dir.items(), key=lambda x: -x[1]):
        print(f"  {k:<12} {kb(v):>10}")
    print("по видам:")
    for k, v in sorted(by_kind.items(), key=lambda x: -x[1]):
        print(f"  {k:<44} {kb(v):>10}")

    added = sum(s for rel, _, s in files if any(fnmatch.fnmatch(rel, p) for p in ADDED_13))
    svg_old = os.path.join(ROOT, "docs", "icons", "svg_old")
    removed = sum(REMOVED_13.values())
    if os.path.isdir(svg_old):
        removed += sum(os.path.getsize(os.path.join(svg_old, f)) for f in os.listdir(svg_old) if f.endswith(".svg"))
    growth = added - removed
    ok = growth <= BUDGET_13
    print(f"этап 13: добавлено {kb(added)}, убрано {kb(removed)}, рост {kb(growth)} "
          f"(бюджет {kb(BUDGET_13)}) — {'в бюджете' if ok else 'ПРЕВЫШЕН'}")
    if "--files" in argv:
        for rel, _, s in sorted(files, key=lambda x: -x[2]):
            print(f"  {kb(s):>10}  {rel}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
