#!/usr/bin/env python3
"""Проверка HTML-оболочки экспорта web/shell.html (этап 16.4) без Godot и браузера.

  python3 tools/check_shell.py

1. export_presets.cfg ссылается на res://web/shell.html, файл на месте.
2. В оболочке есть все подстановки Godot ($GODOT_URL, $GODOT_CONFIG, …) и нет неизвестных (Godot заменяет
   строки как есть: опечатка осталась бы в странице и сломала бы скрипт).
3. Подстановки заменяются как при экспорте, встроенный скрипт запускается в node (или bun) с заглушками DOM и
   Engine: полоса растёт и не откатывается, без размера — бегущие полосы, после старта экран гаснет, при ошибке
   и без нужных функций браузера — понятный текст (ru / en / tr), ПКМ без меню браузера.
4. Ветка сервис-воркера (только с PWA): ставит воркер и перезагружает один раз за сессию вкладки; воркер уже
   стоит, установка упала или перезагрузка уже была — текст ошибки, а не перезагрузка по кругу.
5. Метрика (этап 16.1): скрипт счётчика в <head> — с METRIKA_ID = 0 тег не грузится и цели не уходят, с номером —
   тег tag.js асинхронно, init без вебвизора и карты кликов, цели игры (JSON-строкой и объектом) уходят в ym
   reachGoal, испорченный JSON — цель без параметров; итог загрузки один раз: load_done / load_error с интервалом
   секунд; интервалы — те же, что Analytics.SPAN_EDGES (autoload/analytics.gd). Скрипт запуска сообщает итог:
   старт — load_done, ошибка — load_error start, нет функций браузера — load_error features.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL = os.path.join(ROOT, "web", "shell.html")
KNOWN = {"$GODOT_URL", "$GODOT_CONFIG", "$GODOT_HEAD_INCLUDE", "$GODOT_PROJECT_NAME", "$GODOT_THREADS_ENABLED",
         "$GODOT_SPLASH", "$GODOT_SPLASH_COLOR", "$GODOT_SPLASH_CLASSES"}
REQUIRED = {"$GODOT_URL", "$GODOT_CONFIG", "$GODOT_HEAD_INCLUDE", "$GODOT_PROJECT_NAME", "$GODOT_THREADS_ENABLED"}

HARNESS = r"""
const fs = require('fs');
const src = fs.readFileSync(process.argv[2], 'utf8');
const srcSw = fs.readFileSync(process.argv[3], 'utf8');
const headOff = fs.readFileSync(process.argv[4], 'utf8');
const headOn = fs.readFileSync(process.argv[5], 'utf8');
function el(id) {
  const cls = new Set();
  return { id, style: {}, textContent: '',
    classList: { add: (...c) => c.forEach((x) => cls.add(x)), remove: (...c) => c.forEach((x) => cls.delete(x)),
                 contains: (c) => cls.has(c) }, cls };
}
function run(scenario, lang, sw) {
  sw = sw || null;
  const els = { status: el('status'), bar: el('bar'), fill: el('fill'), notice: el('notice') };
  els.bar.cls.add('unknown');
  const listeners = {};
  const timers = [];
  let progress = null, settle = null;
  const store = {};
  const nav = { language: lang };
  if (sw) {
    nav.serviceWorker = { getRegistration: () => (sw.exists ? Promise.resolve({}) : Promise.resolve(undefined)) };
    if (sw.flag) { store.shikaku_sw_reload = '1'; }
  }
  const ctx = {
    document: { getElementById: (id) => els[id], addEventListener: (t, f) => { listeners[t] = f; } },
    navigator: nav,
    window: { location: { reload: () => { ctx.reloaded = true; } },
              sessionStorage: sw && sw.noStorage ? null : { getItem: (k) => (k in store ? store[k] : null),
                                                             setItem: (k, v) => { store[k] = String(v); } },
              ShikakuMetrika: { loaded: (ok, kind) => { ctx.metrika.push([ok, kind || '']); } } },
    metrika: [],
    setTimeout: (f) => timers.push(f),
    console: { error: () => {} },
    Promise,
    Engine: class {
      constructor(cfg) { ctx.config = cfg; }
      static getMissingFeatures() { return scenario === 'missing' ? ['WebGL2'] : []; }
      installServiceWorker() { ctx.installed = true; return sw && sw.installFails ? Promise.reject(new Error('sw')) : Promise.resolve(); }
      startGame(opts) { progress = opts.onProgress; return new Promise((ok, bad) => { settle = { ok, bad }; }); }
    },
  };
  const body = (sw ? srcSw : src).replace(/^[\s\S]*?<script>\s*/m, '');
  new Function(...Object.keys(ctx), body)(...Object.values(ctx));
  return { els, listeners, timers, ctx, store, progress: (c, t) => progress(c, t), settle: () => settle };
}
// Скрипт Метрики из <head> (16.1) с заглушками window / document; perf — performance.now() в мс (null — нет).
function runHead(src, perf) {
  const appended = [];
  const w = {};
  if (perf !== null) { w.performance = { now: () => perf }; }
  const d = { createElement: (tag) => ({ tag }), head: { appendChild: (e) => appended.push(e) } };
  new Function('window', 'document', src.replace(/^<script>\s*/, ''))(w, d);
  return { w, appended, calls: () => (w.ym && w.ym.a ? w.ym.a.map((a) => Array.from(a)) : []) };
}
const out = {};
const flush = () => new Promise((r) => setImmediate(r));
(async () => {
  // Размер известен: растёт, не откатывается, до старта не больше 99 %.
  let r = run('ok', 'ru-RU');
  const w = [];
  r.progress(0, 0); w.push(r.els.bar.cls.has('unknown'));
  r.progress(25, 100); w.push(r.els.fill.style.width, r.els.bar.cls.has('unknown'));
  r.progress(10, 100); w.push(r.els.fill.style.width);
  r.progress(100, 100); w.push(r.els.fill.style.width);
  let ev = { prevented: false, preventDefault() { this.prevented = true; } };
  r.listeners.contextmenu(ev);
  r.settle().ok(); await flush();
  w.push(r.els.status.cls.has('hidden'), r.els.fill.style.width);
  r.timers.forEach((f) => f());
  w.push(r.els.status.cls.has('gone'), ev.prevented, r.ctx.config.executable);
  out.known = w;
  out.metrika_ok = r.ctx.metrika;
  // Размер неизвестен: бегущие полосы, ширина не задаётся.
  r = run('ok', 'en-US');
  r.progress(5000, 0); r.progress(9000, 0);
  out.unknown = [r.els.bar.cls.has('unknown'), r.els.fill.style.width || ''];
  // Ошибка запуска: текст по языку, экран не гаснет.
  for (const lang of ['ru', 'en-GB', 'tr-TR', 'de']) {
    r = run('ok', lang);
    r.settle().bad(new Error('boom')); await flush();
    out['fail_' + lang] = [r.els.status.cls.has('failed'), r.els.status.cls.has('hidden'), r.els.notice.textContent];
    out.metrika_fail = r.ctx.metrika;
  }
  r = run('missing', 'ru');
  out.missing = [r.els.status.cls.has('failed'), r.els.notice.textContent];
  out.metrika_missing = r.ctx.metrika;
  // Сервис-воркер (PWA): [поставлен, перезагрузка, ошибка на экране, отметка в sessionStorage].
  const swCases = { fresh: {}, exists: { exists: true }, again: { flag: true }, install_fails: { installFails: true },
                    no_storage: { noStorage: true } };
  for (const name of Object.keys(swCases)) {
    r = run('missing', 'ru', swCases[name]); await flush(); await flush(); await flush();
    out['sw_' + name] = [!!r.ctx.installed, !!r.ctx.reloaded, r.els.status.cls.has('failed'),
                         r.store.shikaku_sw_reload || ''];
    out['sw_metrika_' + name] = r.ctx.metrika;
  }
  // Метрика выключена: [есть API, goal, тегов, ym, load_done]
  let h = runHead(headOff, 1000);
  const offGoal = h.w.ShikakuMetrika.goal('level_win', '{"level_win":{"L0001":1}}');
  h.w.ShikakuMetrika.loaded(true);
  out.head_off = [typeof h.w.ShikakuMetrika, offGoal, h.appended.length, typeof h.w.ym, h.calls().length];
  // Метрика включена: тег, init, цели (строкой, объектом, испорченный JSON), итог загрузки один раз.
  h = runHead(headOn, 12345);
  const M = h.w.ShikakuMetrika;
  out.head_on_tag = h.appended.map((e) => [e.tag, e.src, !!e.async]);
  out.head_on_goals = [M.goal('level_win', '{"level_win":{"L0012":{"stars":3}}}'), M.goal('hint', { hint: { L0012: 'ad' } }),
                       M.goal('undo', '{oops'), M.goal('game_ready', '')];
  M.loaded(true); M.loaded(false, 'start');
  out.head_on_calls = h.calls();
  out.head_on_id = M.id;
  h = runHead(headOn, 1500);
  h.w.ShikakuMetrika.loaded(false, 'features');
  out.head_err_calls = h.calls().slice(1);
  out.spans = [0, 2.99, 3, 59.9, 60, 299.99, 300, 1000].map((x) => M.span(x));
  h = runHead(headOn, null);
  out.no_perf = [typeof h.w.ShikakuMetrika.seconds(), h.w.ShikakuMetrika.seconds() >= 0];
  console.log(JSON.stringify(out));
})();
"""


TEST_ID = 12345678  # номер счётчика для проверки ветки «Метрика включена»


def check_metrika(out: dict) -> list:
    """Скрипт Метрики (16.1) в node: выключен — ничего; включён — тег, init, цели, итог загрузки один раз."""
    bad = []
    if out["head_off"] != ["object", False, 0, "undefined", 0]:
        bad.append("Метрика с METRIKA_ID = 0: %s (ждали API без тега, ym и целей)" % out["head_off"])
    if out["head_on_tag"] != [["script", "https://mc.yandex.ru/metrika/tag.js", True]]:
        bad.append("Метрика: тег %s" % out["head_on_tag"])
    calls = out["head_on_calls"]
    init = calls[0] if calls else []
    opts = init[2] if len(init) > 2 else {}
    if init[:2] != [TEST_ID, "init"] or opts.get("webvisor") is not False or opts.get("clickmap") is not False \
            or opts.get("accurateTrackBounce") is not True:
        bad.append("Метрика: init %s" % init)
    expect = [[TEST_ID, "reachGoal", "level_win", {"level_win": {"L0012": {"stars": 3}}}],
              [TEST_ID, "reachGoal", "hint", {"hint": {"L0012": "ad"}}],
              [TEST_ID, "reachGoal", "undo"], [TEST_ID, "reachGoal", "game_ready"],
              [TEST_ID, "reachGoal", "load_done", {"load_done": {"sec": "10-20"}}]]
    # undefined в аргументах JSON отдаёт как null — срезаем хвостовые null
    got = [[a for a in c if a is not None] for c in calls[1:]]
    if got != expect:
        bad.append("Метрика: цели %s, ждали %s" % (got, expect))
    if out["head_on_goals"] != [True, True, True, True] or out["head_on_id"] != TEST_ID:
        bad.append("Метрика: goal вернул %s, id %s" % (out["head_on_goals"], out["head_on_id"]))
    if [[a for a in c if a is not None] for c in out["head_err_calls"]] != \
            [[TEST_ID, "reachGoal", "load_error", {"load_error": {"features": "0-3"}}]]:
        bad.append("Метрика: ошибка загрузки %s" % out["head_err_calls"])
    spans = ["0-3", "0-3", "3-5", "30-60", "60-120", "120-300", "300+", "300+"]
    if out["spans"] != spans:
        bad.append("Метрика: интервалы %s, ждали %s" % (out["spans"], spans))
    if out["no_perf"] != ["number", True]:
        bad.append("Метрика без performance.now: %s" % out["no_perf"])
    return bad


def main() -> int:
    problems = []
    preset = open(os.path.join(ROOT, "export_presets.cfg"), encoding="utf-8").read()
    if 'html/custom_html_shell="res://web/shell.html"' not in preset:
        problems.append("export_presets.cfg: html/custom_html_shell не указывает на res://web/shell.html")
    if "sdk.js" not in preset:
        problems.append("export_presets.cfg: в head_include нет sdk.js")
    html = open(SHELL, encoding="utf-8").read()
    found = set(re.findall(r"\$GODOT_[A-Z_]+", html))
    for p in sorted(REQUIRED - found):
        problems.append("нет подстановки %s" % p)
    for p in sorted(found - KNOWN):
        problems.append("неизвестная подстановка %s (Godot её не заменит)" % p)
    # Подстановки как при экспорте (длинные имена раньше коротких: $GODOT_SPLASH_COLOR до $GODOT_SPLASH).
    cfg = {"canvasResizePolicy": 2, "executable": "index", "mainPack": "index.pck", "fileSizes": {}}
    cfg_sw = dict(cfg, serviceWorker="index.service.worker.js", ensureCrossOriginIsolationHeaders=True)

    def export_page(config: dict) -> str:
        sub = {"$GODOT_CONFIG": json.dumps(config), "$GODOT_THREADS_ENABLED": "false", "$GODOT_URL": "index.js",
               "$GODOT_HEAD_INCLUDE": "<script src='/sdk.js'></script>", "$GODOT_PROJECT_NAME": "Shikaku"}
        page = html
        for k in sorted(sub, key=len, reverse=True):
            page = page.replace(k, sub[k])
        return page

    inline = re.findall(r"<script>(.*?)</script>", export_page(cfg), re.S)
    scripts = [x for x in inline if "new Engine(" in x]
    scripts_sw = [x for x in re.findall(r"<script>(.*?)</script>", export_page(cfg_sw), re.S) if "new Engine(" in x]
    heads = [x for x in inline if "METRIKA_ID" in x and "new Engine(" not in x]
    if len(inline) != 2 or len(scripts) != 1 or len(heads) != 1:
        problems.append("встроенных скриптов %d (запуска %d, Метрики %d), ждали 2 (по одному)"
                        % (len(inline), len(scripts), len(heads)))
    # Метрика (16.1): номер — одна строка; скрипт счётчика — до $GODOT_HEAD_INCLUDE и до движка.
    ids = re.findall(r"^var METRIKA_ID = (\d+);$", html, re.M)
    if len(ids) != 1:
        problems.append("строка «var METRIKA_ID = <номер>;» найдена %d раз, ждали 1" % len(ids))
    metrika_id = int(ids[0]) if ids else 0
    if html.find("var METRIKA_ID") > html.find("$GODOT_HEAD_INCLUDE") or html.find("var METRIKA_ID") > html.find("$GODOT_URL"):
        problems.append("скрипт Метрики не в начале страницы (ждали до $GODOT_HEAD_INCLUDE и движка)")
    edges_js = re.search(r"var SPAN_EDGES = \[([0-9, ]+)\];", html)
    an_path = os.path.join(ROOT, "autoload", "analytics.gd")
    an = open(an_path, encoding="utf-8").read() if os.path.exists(an_path) else ""
    edges_gd = re.search(r"const SPAN_EDGES: Array\[int\] = \[([0-9, ]+)\]", an)
    if not edges_js or not edges_gd or [int(x) for x in edges_js.group(1).split(",")] != \
            [int(x) for x in edges_gd.group(1).split(",")]:
        problems.append("интервалы секунд в оболочке (SPAN_EDGES) и в autoload/analytics.gd (SPAN_EDGES) разные: %s / %s"
                        % (edges_js and edges_js.group(1), edges_gd and edges_gd.group(1)))
    runner = shutil.which("node") or shutil.which("bun")
    if not runner:
        print("node / bun не найдены — проверка скрипта пропущена")
    elif scripts:
        with tempfile.TemporaryDirectory() as tmp:
            js, h = os.path.join(tmp, "page.js"), os.path.join(tmp, "harness.js")
            js_sw = os.path.join(tmp, "page_sw.js")
            head_off, head_on = os.path.join(tmp, "head_off.js"), os.path.join(tmp, "head_on.js")
            open(js, "w", encoding="utf-8").write("<script>\n" + scripts[0])
            open(js_sw, "w", encoding="utf-8").write("<script>\n" + scripts_sw[0])
            head_src = heads[0] if heads else ""
            open(head_off, "w", encoding="utf-8").write(
                re.sub(r"^var METRIKA_ID = \d+;$", "var METRIKA_ID = 0;", head_src, flags=re.M))
            open(head_on, "w", encoding="utf-8").write(
                re.sub(r"^var METRIKA_ID = \d+;$", "var METRIKA_ID = %d;" % TEST_ID, head_src, flags=re.M))
            open(h, "w", encoding="utf-8").write(HARNESS)
            res = subprocess.run([runner, h, js, js_sw, head_off, head_on], capture_output=True, text=True,
                                 timeout=60)
        if res.returncode != 0:
            problems.append("скрипт оболочки упал: " + (res.stderr.strip() or res.stdout.strip())[-600:])
        else:
            out = json.loads(res.stdout.strip().splitlines()[-1])
            expect_known = [True, "25.0%", False, "25.0%", "99.0%", True, "100%", True, True, "index"]
            if out["known"] != expect_known:
                problems.append("полоса загрузки: %s, ждали %s" % (out["known"], expect_known))
            if out["unknown"] != [True, ""]:
                problems.append("без размера: %s" % out["unknown"])
            starts = {"ru": "Не удалось запустить", "en-GB": "The game failed", "tr-TR": "Oyun başlatılamadı",
                      "de": "The game failed"}
            for lang, head in starts.items():
                failed, hidden, text = out["fail_" + lang]
                if not failed or hidden or not text.startswith(head) or "boom" not in text:
                    problems.append("ошибка (%s): %s" % (lang, out["fail_" + lang]))
            if (not out["missing"][0] or "WebGL2" not in out["missing"][1]
                    or not out["missing"][1].startswith("Браузер не поддерживает")
                    or "другом браузере" not in out["missing"][1]):
                problems.append("нет функций браузера: %s" % out["missing"])
            # [поставлен, перезагрузка, ошибка на экране, отметка]
            expect_sw = {"fresh": [True, True, False, "1"], "exists": [False, False, True, ""],
                         "again": [False, False, True, "1"], "install_fails": [True, False, True, ""],
                         "no_storage": [False, False, True, ""]}
            for name, exp in expect_sw.items():
                if out["sw_" + name] != exp:
                    problems.append("сервис-воркер (%s): %s, ждали %s" % (name, out["sw_" + name], exp))
            # Итог загрузки из скрипта запуска в ShikakuMetrika.loaded: [ok, kind].
            expect_loaded = {"metrika_ok": [[True, ""]], "metrika_fail": [[False, "start"]],
                             "metrika_missing": [[False, "features"]], "sw_metrika_fresh": [],
                             "sw_metrika_exists": [[False, "features"]], "sw_metrika_install_fails": [[False, "features"]]}
            for name, exp in expect_loaded.items():
                if out[name] != exp:
                    problems.append("итог загрузки в Метрику (%s): %s, ждали %s" % (name, out[name], exp))
            problems.extend(check_metrika(out))
            print("скрипт оболочки (%s): полоса %s, ошибки ru / en / tr, нет функций браузера, сервис-воркер"
                  " (5 случаев), Метрика (выключена / включена, цели, итог загрузки) — %s"
                  % (os.path.basename(runner), " → ".join(x for x in out["known"] if isinstance(x, str) and "%" in x),
                     "ок" if not problems else "см. ниже"))
    print("подстановки: %s" % ", ".join(sorted(found)))
    print("Метрика: %s" % ("выключена (METRIKA_ID = 0) — номер счётчика вписать в web/shell.html"
                           if not metrika_id else "включена, счётчик %d" % metrika_id))
    for p in problems:
        print("ПРОБЛЕМА:", p)
    print("проблем не найдено" if not problems else "проблем: %d" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
