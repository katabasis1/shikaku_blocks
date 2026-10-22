#!/usr/bin/env python3
"""Размер веб-сборки и время загрузки на мобильном интернете (этап 16.4). Godot не нужен.

    python3 tools/web_build_report.py                 # build/web (путь экспорта из export_presets.cfg)
    python3 tools/web_build_report.py ПАПКА           # другая папка с index.html, index.wasm, index.pck …

Есть экспорт — считает настоящие файлы: размер как есть и после gzip -9 (так их отдаёт сервер со сжатием),
проверяет index.html (оболочка web/shell.html подставилась, нет «$GODOT_…», есть sdk.js, ПКМ без меню).
Экспорта нет — оценка: ресурсы проекта (как tools/build_size.py) + движок по ориентиру ниже.

Время — только передача по сети при скорости пресетов Chrome DevTools (Network → throttling) и трёх
последовательных запросах (страница → index.js и sdk.js → wasm и pck параллельно). Компиляция wasm и старт
движка на телефоне добавят ещё 1–3 с. Точное число — замер в черновике Яндекс Игр с тем же пресетом.
"""
import gzip
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

# Ориентир движка Godot 4 для веба (wasm + js, без потоков) — до экспорта; после экспорта берутся файлы.
ENGINE_RAW = (35 * 1024 * 1024, 40 * 1024 * 1024)
ENGINE_GZIP_RATIO = 0.25

# Пресеты Chrome DevTools: скорость приёма, бит/с, и задержка, с.
PROFILES = [("Wi-Fi 30 Мбит/с", 30_000_000, 0.02), ("Fast 4G (9 Мбит/с)", 9_000_000, 0.06),
            ("Slow 4G (1,6 Мбит/с)", 1_600_000, 0.15), ("3G (0,4 Мбит/с)", 400_000, 0.4)]
ROUND_TRIPS = 3
# Порог: дольше этого на Fast 4G — пора думать о шаблоне без 3D (PLAN 16.4).
FAST4G_LIMIT_S = 10.0


def mb(n: float) -> str:
    return f"{n / 1024 / 1024:5.1f} МБ"


def gz_size(path: str) -> int:
    with open(path, "rb") as f:
        return len(gzip.compress(f.read(), 9))


def export_dir() -> str:
    cfg = open(os.path.join(ROOT, "export_presets.cfg"), encoding="utf-8").read()
    m = re.search(r'^export_path="([^"]+)"', cfg, re.M)
    return os.path.join(ROOT, os.path.dirname(m.group(1) if m else "build/web/index.html"))


def check_html(path: str) -> list:
    html = open(path, encoding="utf-8", errors="replace").read()
    problems = []
    left = sorted(set(re.findall(r"\$GODOT_[A-Z_]+", html)))
    if left:
        problems.append("в index.html остались подстановки: " + ", ".join(left))
    if 'id="logo"' not in html:
        problems.append("index.html — не наша оболочка (нет #logo): html/custom_html_shell не применился")
    if "sdk.js" not in html:
        problems.append("в index.html нет sdk.js (html/head_include)")
    if "contextmenu" not in html:
        problems.append("в index.html нет запрета меню по ПКМ")
    if '"fileSizes"' not in html:
        problems.append("в GODOT_CONFIG нет fileSizes — полоса загрузки будет без процентов")
    return problems


def times(total_bytes: float) -> list:
    return [(name, total_bytes * 8 / bps + ROUND_TRIPS * rtt) for name, bps, rtt in PROFILES]


def report_build(d: str) -> int:
    files = sorted(f for f in os.listdir(d) if os.path.isfile(os.path.join(d, f)))
    rows, raw_total, gz_total = [], 0, 0
    for f in files:
        p = os.path.join(d, f)
        raw = os.path.getsize(p)
        gz = gz_size(p)
        rows.append((f, raw, gz))
        raw_total += raw
        gz_total += gz
    print(f"сборка: {d}")
    print(f"  {'файл':<36} {'как есть':>10} {'gzip -9':>10}")
    for f, raw, gz in sorted(rows, key=lambda r: -r[1]):
        print(f"  {f:<36} {mb(raw):>10} {mb(gz):>10}")
    print(f"  {'всего':<36} {mb(raw_total):>10} {mb(gz_total):>10}")
    print("время передачи (без сжатия / со сжатием):")
    for (name, t_raw), (_, t_gz) in zip(times(raw_total), times(gz_total)):
        print(f"  {name:<24} {t_raw:6.1f} с / {t_gz:6.1f} с")
    problems = []
    html = os.path.join(d, "index.html")
    if os.path.exists(html):
        problems += check_html(html)
    else:
        problems.append("нет index.html")
    fast = times(gz_total)[1][1]
    if fast > FAST4G_LIMIT_S:
        print(f"Fast 4G со сжатием — {fast:.1f} с, больше {FAST4G_LIMIT_S:.0f} с: стоит собрать шаблон без 3D (PLAN 16.4)")
    for p in problems:
        print("ПРОБЛЕМА:", p)
    print("проблем не найдено" if not problems else f"проблем: {len(problems)}")
    return 1 if problems else 0


def report_estimate(d: str) -> int:
    import build_size
    files = build_size.exported_files()
    res_raw = sum(s for _, _, s in files)
    res_gz = 0
    for rel, ext, s in files:
        p = os.path.join(ROOT, rel)
        res_gz += min(s, gz_size(p)) if os.path.exists(p) else s
    print(f"экспорта в {d} нет — оценка до экспорта (Project → Export → Web, затем запустить снова)")
    print(f"  ресурсы (index.pck, по tools/build_size.py): {mb(res_raw)} как есть, ≈{mb(res_gz)} после gzip")
    lo, hi = ENGINE_RAW
    print(f"  движок (index.wasm + index.js, ориентир):    {mb(lo)}–{mb(hi)} как есть, "
          f"≈{mb(lo * ENGINE_GZIP_RATIO)}–{mb(hi * ENGINE_GZIP_RATIO)} после gzip")
    print("время передачи со сжатием (без сжатия движок вчетверо больше):")
    t_lo = times(res_gz + lo * ENGINE_GZIP_RATIO)
    t_hi = times(res_gz + hi * ENGINE_GZIP_RATIO)
    for (name, a), (_, b) in zip(t_lo, t_hi):
        print(f"  {name:<24} {a:6.1f}–{b:.1f} с")
    share = [e * ENGINE_GZIP_RATIO / (e * ENGINE_GZIP_RATIO + res_gz) for e in (lo, hi)]
    print(f"движок — {share[0]:.0%}–{share[1]:.0%} передачи: сокращать в первую очередь его (шаблон без 3D), "
          "а не ресурсы игры")
    return 0


def main(argv) -> int:
    d = os.path.abspath(argv[0]) if argv else export_dir()
    if os.path.isdir(d) and any(f.endswith(".wasm") for f in os.listdir(d)):
        return report_build(d)
    return report_estimate(d)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
