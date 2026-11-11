#!/usr/bin/env python3
"""Статическая проверка проекта без редактора Godot.

Синтаксис .gd: парность скобок, незакрытые строки, отступы только табами,
вложенный блок после строки с ':' и нет лишних отступов, повторные функции.
Идентификаторы: Класс.член и Автозагрузка.член (class_name, project.godot),
члены через переменные с типом-классом проекта, %Уникальные узлы и $пути
в сцене скрипта, connect(метод), сигнал.emit(), вызовы своих _функций.
Ресурсы .tscn/.tres: файлы ext_resource существуют, ExtResource/SubResource
объявлены, у узлов есть родители.
project.godot: скрипты автозагрузок, главная сцена / иконка / тема, файлы
переводов, пустое поле Locale → Test (оно задаётся только для проверки en / tr
в редакторе); .gdignore в docs/ и music_src/. PROGRESS.md не больше 40 КБ (20.0c).
JuiceConfig (14.8a): каждое число — ровно в одном из списков OFF и
KEEP_ON_OFF, тип значения в OFF — как у числа.
Вывод типа (var x := …): в выражении нет значения без типа (поле словаря
через точку, элемент нетипизированного массива или словаря в выражении,
переменная без типа) — иначе Godot не загрузит скрипт.
Звук (15.6): у каждого звука из Audio.SOUNDS — узел в autoload/audio.tscn
(шина SFX) и файл assets/sfx/*.wav; лишних узлов нет; Audio.play(Audio.X)
в скриптах — только звуки из SOUNDS.
Встроенные методы и свойства (19.5e): функция или var скрипта не совпадает
по имени с методом или свойством встроенного класса, от которого он
унаследован (Control.set_theme, Node2D.rotate, ColorRect.color …) — иначе
Godot не загрузит скрипт («The function signature doesn't match the parent»
или «Member … redefined»). Списки NATIVE_* — основные члены, не все.

Это не замена самопроверке в Godot (tests/selftest.tscn): встроенные классы
движка не проверяются. Запуск из корня проекта:  python3 tools/check_gd.py
Код выхода 0 — проблем не найдено.
"""
import collections
import pathlib
import re
import sys

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent).resolve()
problems = []

# Встроенные члены Godot, к которым скрипты обращаются через переменные с типом-классом проекта.
BUILTINS = set("""
queue_free add_child remove_child get_parent reparent position global_position size scale modulate visible
show hide rotation pivot_offset custom_minimum_size create_tween get_tree is_inside_tree set_anchors_preset
z_index mouse_filter get_global_rect get_rect self_modulate emit connect name get_children get_child
get_child_count is_queued_for_deletion move_to_front material has_method call_deferred text is_node_ready
offset_left offset_top offset_right offset_bottom set_process get_node_or_null disconnect is_connected
process_mode get_viewport_rect get_global_transform vertical get_script add_theme_font_size_override
get_theme_font_size get_theme_font atr tr add_theme_color_override add_theme_constant_override get_theme_color
get_theme_constant texture pressed disabled toggled button_pressed tooltip_text set_anchors_and_offsets_preset
resized minimum_size_changed get_combined_minimum_size icon theme_type_variation get_instance_id
find_children get_path_to queue_redraw texture_filter
""".split())


def problem(where, line, msg):
    problems.append("%s:%s: %s" % (where, line, msg))


def project_files(pattern):
    for p in sorted(ROOT.rglob(pattern)):
        if not any(part.startswith(".") for part in p.relative_to(ROOT).parts):
            yield p


def strip_code(src, where):
    """Код без комментариев; строки заменены пустыми, переносы строк сохранены."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('"""', i) or src.startswith("'''", i):
            j = src.find(src[i:i + 3], i + 3)
            if j < 0:
                problem(where, src[:i].count("\n") + 1, "незакрытая тройная строка")
                j = n
            out.append('""' + "\n" * src[i:j + 3].count("\n"))
            i = j + 3
        elif c in "\"'":
            j = i + 1
            while j < n and src[j] not in (c, "\n"):
                j += 2 if src[j] == "\\" else 1
            if j >= n or src[j] == "\n":
                problem(where, src[:i].count("\n") + 1, "незакрытая строка")
                i = j
            else:
                out.append(c + c)
                i = j + 1
        elif c == "#":
            j = src.find("\n", i)
            i = n if j < 0 else j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def line_of(code, pos):
    return code[:pos].count("\n") + 1


# --- Скрипты -----------------------------------------------------------------
scripts = {}
for p in project_files("*.gd"):
    rel = "res://" + p.relative_to(ROOT).as_posix()
    src = p.read_text(encoding="utf-8")
    code = strip_code(src, rel)
    info = dict(rel=rel, src=src, code=code, funcs={}, members=set(), signals=set(), inner=set())
    m = re.search(r"^class_name\s+(\w+)", code, re.M)
    info["cls"] = m.group(1) if m else None
    m = re.search(r"^extends\s+(\S+)", code, re.M)
    info["extends"] = m.group(1).strip('"') if m else ""
    for m in re.finditer(r"^(?:static\s+)?func\s+(\w+)\s*\(", code, re.M):
        if m.group(1) in info["funcs"]:
            problem(rel, line_of(code, m.start()), "функция %s объявлена дважды" % m.group(1))
        info["funcs"][m.group(1)] = line_of(code, m.start())
    for m in re.finditer(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?(?:var|const)\s+(\w+)", code, re.M):
        info["members"].add(m.group(1))
    info["signals"] = set(re.findall(r"^signal\s+(\w+)", code, re.M))
    info["inner"] = set(re.findall(r"^class\s+(\w+)", code, re.M))
    for m in re.finditer(r"^enum\s*(\w*)\s*\{([^}]*)\}", code, re.M):
        if m.group(1):
            info["members"].add(m.group(1))
        info["members"].update(re.findall(r"(\w+)", re.sub(r"=\s*-?\w+", "", m.group(2))))
    scripts[rel] = info

by_class = {i["cls"]: i for i in scripts.values() if i["cls"]}


def members_of(info, seen=None):
    if info is None:
        return set()
    seen = seen if seen is not None else set()
    if info["rel"] in seen:
        return set()
    seen.add(info["rel"])
    s = set(info["funcs"]) | info["members"] | info["signals"] | info["inner"]
    ext = info["extends"]
    if ext.startswith("res://"):
        s |= members_of(scripts.get(ext), seen)
    elif ext in by_class:
        s |= members_of(by_class[ext], seen)
    return s


def inner_members(info, cname):
    m = re.search(r"^class\s+%s\b[^\n]*\n((?:\t[^\n]*\n|[ \t]*\n)*)" % cname, info["code"], re.M)
    if not m:
        return set()
    body = m.group(1)
    return (set(re.findall(r"^\t(?:static\s+)?func\s+(\w+)", body, re.M))
            | set(re.findall(r"^\t(?:static\s+)?(?:var|const)\s+(\w+)", body, re.M)))


# --- Синтаксис -----------------------------------------------------------------
BLOCK_START = re.compile(r"^\s*(if|elif|else|for|while|match|func|static\s+func|class|enum|var)\b|^\s*@\w+.*\bvar\b")
for rel, info in scripts.items():
    lines = info["code"].split("\n")
    stack = []
    base_indent, expect_block, opener, cont = 0, False, 0, False
    for ln, line in enumerate(lines, 1):
        s = line.rstrip()
        if s.strip() and not stack:
            lead = re.match(r"^[ \t]*", s).group(0)
            if " " in lead and not cont:
                problem(rel, ln, "отступ пробелами")
            ind = len(lead)
            if not cont:
                if expect_block and ind <= base_indent:
                    problem(rel, ln, "после строки %d с ':' нет вложенного блока" % opener)
                if not expect_block and ind > base_indent:
                    problem(rel, ln, "лишний отступ")
                base_indent = ind
                stmt_start = s
        for ch in s:
            if ch in "([{":
                stack.append((ch, ln))
            elif ch in ")]}":
                if not stack or "([{"[")]}".index(ch)] != stack[-1][0]:
                    problem(rel, ln, "непарная скобка " + ch)
                else:
                    stack.pop()
        if s.strip():
            cont = bool(stack) or s.endswith("\\")
            if not cont:
                # блок открывает строка с ':' в конце (match-ветки, if, func, свойства get/set)
                expect_block = s.endswith(":") and (BLOCK_START.match(stmt_start) is not None
                                                    or re.match(r"^\s*(get|set)\b", s) is not None
                                                    or not re.match(r"^\s*const\b", stmt_start))
                opener = ln
    for ch, ln in stack:
        problem(rel, ln, "незакрытая скобка " + ch)

def typed_fields(info, seen=None):
    """Поля скрипта (и его предков) с типом-классом проекта: имя -> info класса."""
    if info is None:
        return {}
    seen = seen if seen is not None else set()
    if info["rel"] in seen:
        return {}
    seen.add(info["rel"])
    res = {}
    ext = info["extends"]
    if ext.startswith("res://"):
        res.update(typed_fields(scripts.get(ext), seen))
    elif ext in by_class:
        res.update(typed_fields(by_class[ext], seen))
    for a in re.finditer(r"^(?:@\w+(?:\([^)]*\))?\s+)*var\s+(\w+)\s*:\s*([A-Z]\w*)", info["code"], re.M):
        if a.group(2) in by_class:
            res[a.group(1)] = by_class[a.group(2)]
    return res


# --- Автозагрузки --------------------------------------------------------------
proj = (ROOT / "project.godot").read_text(encoding="utf-8")
autoloads = {}
sec = re.search(r"\[autoload\](.*?)(?=\n\[|\Z)", proj, re.S)
for name, path in re.findall(r'^(\w+)="\*?(res://[^"]+)"', sec.group(1) if sec else "", re.M):
    if path.endswith(".tscn"):
        t = (ROOT / path[6:]).read_text(encoding="utf-8")
        m = re.search(r'\[node [^\]]*\]\n(?:[^\[\n].*\n)*?script = ExtResource\("([^"]+)"\)', t)
        ids = dict((i, p) for p, i in re.findall(r'\[ext_resource type="Script"[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', t))
        path = ids.get(m.group(1), "") if m else ""
    autoloads[name] = scripts.get(path)
    if autoloads[name] is None:
        problem("project.godot", 0, "автозагрузка %s: нет скрипта %s" % (name, path))
for key in ("run/main_scene", "config/icon", "theme/custom"):
    m = re.search(r'%s="(res://[^"]+)"' % re.escape(key), proj)
    if m and not (ROOT / m.group(1)[6:]).exists():
        problem("project.godot", 0, "%s: нет файла %s" % (key, m.group(1)))
for path in re.findall(r'"(res://[^"]+\.po)"', proj):
    if not (ROOT / path[6:]).exists():
        problem("project.godot", 0, "нет перевода " + path)
# Locale → Test нужен только для проверки en / tr в редакторе (README, «Локализация»). Godot применяет его и
# в экспорте, а GameState._ready ставит его вместо языка системы: забытый Test = выпуск всегда на одном языке.
sec = re.search(r"\[internationalization\](.*?)(?=\n\[|\Z)", proj, re.S)
m = re.search(r'^locale/test="([^"]*)"', sec.group(1) if sec else "", re.M)
if m and m.group(1).strip():
    problem("project.godot", 0, "Locale → Test = \"%s\": выпуск будет всегда на этом языке — очистите поле перед экспортом"
            % m.group(1).strip())

# Папки вне сборки: без .gdignore Godot импортирует их картинки (docs/ — ~10 МБ стиль-кадров), а экспорт
# all_resources берёт их в веб-сборку. 02.10 docs/.gdignore потерялся при загрузке проекта в Pod.
for folder in ("docs", "music_src"):
    if (ROOT / folder).is_dir() and not (ROOT / folder / ".gdignore").is_file():
        problem(folder, 0, "нет .gdignore — папка попадёт в импорт и сборку")

# Корневой PROGRESS.md (20.0c, 23.10): агент новой сессии должен прочитать его целиком. 22.10 он дорос до 518 КБ —
# закрытые этапы и старый лог ушли в docs/log/. Предел — PROGRESS_MAX_KB; вырос — перенесите туда же.
PROGRESS_MAX_KB = 40
_progress = ROOT / "PROGRESS.md"
if _progress.is_file() and _progress.stat().st_size > PROGRESS_MAX_KB * 1024:
    problem("PROGRESS.md", 0, "%d КБ > %d КБ — закрытые пункты и старые записи лога перенесите в docs/log/ "
            "(оглавление — docs/log/README.md)" % (_progress.stat().st_size // 1024, PROGRESS_MAX_KB))

# «Без эффектов» (14.8a): каждое число JuiceConfig (@export в scripts/juice_config.gd) — ровно в одном из списков
# OFF (значение «эффекта нет») и KEEP_ON_OFF (не трогать); значение в OFF — того же типа, что число (Tween не примет
# Vector2 вместо float, int вместо float — set() в Godot 4 приведёт, но лучше явно). То же — off_list_errors() в
# самопроверке; здесь — до запуска Godot.
def _gd_value_type(v):
    v = v.split("#")[0].strip()
    if v.startswith("Vector2"):
        return "Vector2"
    if v in ("true", "false"):
        return "bool"
    if re.fullmatch(r"-?(\d+\.\d*|\.\d+)(e-?\d+)?", v):
        return "float"
    if re.fullmatch(r"-?\d+", v):
        return "int"
    if v.startswith("PackedFloat32Array") or v.startswith("["):
        return "array"
    return "?"


_jc_path = ROOT / "scripts" / "juice_config.gd"
if _jc_path.is_file():
    _jc = _jc_path.read_text(encoding="utf-8")
    _decl = {}
    for m in re.finditer(r"^@export(?:_\w+\([^)]*\))?\s+var\s+(\w+)\s*(?::\s*(\w+)\s*)?:?=\s*(.+)$", _jc, re.M):
        _decl[m.group(1)] = (m.group(2) or _gd_value_type(m.group(3)), line_of(_jc, m.start()))
    _om = re.search(r"^const OFF := \{(.*?)^\}", _jc, re.M | re.S)
    _km = re.search(r"^const KEEP_ON_OFF: Array\[StringName\] = \[(.*?)^\]", _jc, re.M | re.S)
    if not _om or not _km:
        problem("scripts/juice_config.gd", 0, "нет списков OFF / KEEP_ON_OFF (14.8a)")
    else:
        _off_body = re.sub(r"#[^\n]*", "", _om.group(1))
        _keep_body = re.sub(r"#[^\n]*", "", _km.group(1))
        _off = {}
        for m in re.finditer(r'&"(\w+)":\s*(Vector2(?:\([^)]*\)|\.\w+)|[^,\n]+)', _off_body):
            if m.group(1) in _off:
                problem("scripts/juice_config.gd", 0, "OFF.%s: дважды" % m.group(1))
            _off[m.group(1)] = _gd_value_type(m.group(2))
        _keep = re.findall(r'&"(\w+)"', _keep_body)
        for k, n in collections.Counter(_keep).items():
            if n > 1:
                problem("scripts/juice_config.gd", 0, "KEEP_ON_OFF: %s — дважды" % k)
        for name, (typ, ln) in _decl.items():
            a, b = name in _off, name in _keep
            if a and b:
                problem("scripts/juice_config.gd", ln, "%s: и в OFF, и в KEEP_ON_OFF" % name)
            elif not a and not b:
                problem("scripts/juice_config.gd", ln, "%s: нет ни в OFF, ни в KEEP_ON_OFF (14.8a) — решите, куда" % name)
            elif a and _off[name] != typ:
                problem("scripts/juice_config.gd", ln, "%s: в OFF значение %s, а число — %s" % (name, _off[name], typ))
        for name in list(_off) + _keep:
            if name not in _decl:
                problem("scripts/juice_config.gd", 0, "OFF / KEEP_ON_OFF: %s — такого числа нет" % name)

# --- Сцены и ресурсы -------------------------------------------------------------
scenes = {}
for p in list(project_files("*.tscn")) + list(project_files("*.tres")):
    rel = "res://" + p.relative_to(ROOT).as_posix()
    t = p.read_text(encoding="utf-8")
    ext = {}
    for m in re.finditer(r"\[ext_resource ([^\]]*)\]", t):
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        ext[a["id"]] = a
        if not (ROOT / a["path"][6:]).exists():
            problem(rel, 0, "нет файла ресурса " + a["path"])
    for u in sorted(set(re.findall(r'ExtResource\("([^"]+)"\)', t)) - set(ext)):
        problem(rel, 0, "ExtResource(\"%s\") не объявлен" % u)
    subs = set(re.findall(r'\[sub_resource [^\]]*id="([^"]+)"', t))
    for u in sorted(set(re.findall(r'SubResource\("([^"]+)"\)', t)) - subs):
        problem(rel, 0, "SubResource(\"%s\") не объявлен" % u)
    nodes = []
    for m in re.finditer(r"\[node ([^\]]*)\]((?:\n(?!\[).*)*)", t):
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        parent = a.get("parent")
        path = "." if parent is None else (a["name"] if parent == "." else parent + "/" + a["name"])
        if parent not in (None, ".") and parent not in [n["path"] for n in nodes]:
            problem(rel, 0, "узел %s: нет родителя %s" % (a["name"], parent))
        sm = re.search(r'^script = ExtResource\("([^"]+)"\)', m.group(2), re.M)
        nodes.append(dict(path=path, name=a["name"], uniq="unique_name_in_owner = true" in m.group(2),
                          script=ext.get(sm.group(1), {}).get("path") if sm else None))
    for m in re.finditer(r"\[connection ([^\]]*)\]", t):
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        target = next((n for n in nodes if n["path"] == a.get("to")), None)
        if target is None or a.get("method") not in members_of(scripts.get(target["script"])):
            problem(rel, 0, "connection %s -> %s.%s: метод не найден" % (a.get("signal"), a.get("to"), a.get("method")))
    scenes[rel] = nodes

# Скрипт на любом узле сцены: %Имя ищется среди unique_name_in_owner сцены,
# $путь — от узла, к которому прикреплён скрипт.
script_scenes = collections.defaultdict(list)
for rel, nodes in scenes.items():
    for n in nodes:
        if n["script"]:
            script_scenes[n["script"]].append((rel, n["path"]))


def join_node_path(base, rel_path):
    parts = [] if base == "." else base.split("/")
    for seg in rel_path.split("/"):
        if seg == "..":
            if not parts:
                return None
            parts.pop()
        elif seg not in ("", "."):
            parts.append(seg)
    return "/".join(parts) if parts else "."


for srel, info in scripts.items():
    code = info["code"]
    for sc_rel, node_path in script_scenes.get(srel, []):
        where = sc_rel if node_path == "." else "%s (узел %s)" % (sc_rel, node_path)
        uniq = {n["name"] for n in scenes[sc_rel] if n["uniq"]}
        paths = {n["path"] for n in scenes[sc_rel]}
        for m in re.finditer(r"(?<![\w)\]])%([A-Z]\w*)", code):
            if m.group(1) not in uniq:
                problem(srel, line_of(code, m.start()), "%%%s нет в %s (unique_name_in_owner)" % (m.group(1), where))
        for m in re.finditer(r"\$([\w/.]+)", code):
            if join_node_path(node_path, m.group(1).rstrip(".")) not in paths:
                problem(srel, line_of(code, m.start()), "$%s нет в %s" % (m.group(1), where))

# --- Идентификаторы -----------------------------------------------------------------
targets = dict(by_class)
targets.update({k: v for k, v in autoloads.items() if v})
n_static = n_typed = 0
for srel, info in scripts.items():
    code = info["code"]
    for m in re.finditer(r"(?<![\w.])([A-Z]\w*)\.(\w+)(?:\.(\w+))?", code):
        name, mem, sub = m.groups()
        if name not in targets:
            continue
        t = targets[name]
        n_static += 1
        if mem in t["inner"]:
            if sub and sub != "new" and sub not in inner_members(t, mem):
                problem(srel, line_of(code, m.start()), "%s.%s.%s не найден" % (name, mem, sub))
        elif mem != "new" and mem not in members_of(t) and not (name in autoloads and mem in BUILTINS):
            # автозагрузка — узел: встроенные методы Node (Audio.get_node_or_null) у неё есть
            problem(srel, line_of(code, m.start()), "%s.%s не найден в %s" % (name, mem, t["rel"]))

    # переменные с типом-классом проекта: поля скрипта, параметры и локальные переменные функции
    fields = typed_fields(info)
    starts = list(re.finditer(r"^(?:static\s+)?func\s+\w+\s*\(([^)]*)\)", code, re.M))
    spans = []
    for k, m in enumerate(starts):
        end = starts[k + 1].start() if k + 1 < len(starts) else len(code)
        local = {a.group(1): by_class[a.group(2)]
                 for a in re.finditer(r"(\w+)\s*:\s*([A-Z]\w*)", m.group(1)) if a.group(2) in by_class}
        local.update({a.group(1): by_class[a.group(2)]
                      for a in re.finditer(r"\bvar\s+(\w+)\s*:\s*([A-Z]\w*)", code[m.start():end]) if a.group(2) in by_class})
        # var g := _game — тип берётся у переменной справа
        for a in re.finditer(r"\bvar\s+(\w+)\s*:=\s*(\w+)[ \t]*$", code[m.start():end], re.M):
            src_t = local.get(a.group(2)) or fields.get(a.group(2))
            if src_t is not None:
                local[a.group(1)] = src_t
        spans.append((m.start(), end, local))

    def type_at(v, pos):
        for a, b, local in spans:
            if a <= pos < b:
                if v in local:
                    return local[v]
                if re.search(r"\bvar\s+%s\b" % re.escape(v), code[a:pos]):
                    return None   # локальная переменная без класса перекрывает поле
        return fields.get(v)

    for m in re.finditer(r"(?<![\w.])(\w+)((?:\.\w+)+)", code):
        t = type_at(m.group(1), m.start())
        chain = m.group(2).split(".")[1:]
        name = m.group(1)
        # a.b.c: пока поле с типом-классом проекта — идём дальше по цепочке
        while t is not None and chain:
            mem = chain.pop(0)
            n_typed += 1
            if mem not in members_of(t) and mem not in BUILTINS:
                problem(srel, line_of(code, m.start()), "%s.%s: нет в %s" % (name, mem, t["rel"]))
                break
            name += "." + mem
            t = typed_fields(t).get(mem)

    own = members_of(info)
    for m in re.finditer(r"\.connect\(\s*(_\w+)", code):
        if m.group(1) not in own:
            problem(srel, line_of(code, m.start()), "connect(%s): метода нет" % m.group(1))
    for m in re.finditer(r"(?<![\w.])(\w+)\.emit\(", code):
        if m.group(1) not in own:
            problem(srel, line_of(code, m.start()), "%s.emit(): сигнал не объявлен" % m.group(1))
    for m in re.finditer(r"(?<![\w.$%@])(_\w+)\s*\(", code):
        if m.group(1) not in own and m.group(1) not in ("_init",):
            problem(srel, line_of(code, m.start()), "%s(): функции нет в скрипте" % m.group(1))

# --- Вывод типа (:=) ------------------------------------------------------------------------------
# var x := выражение: Godot выводит тип только у значения с известным типом. Ошибка разбора (весь скрипт не
# грузится), если в выражении значение без типа: поле словаря через точку (m.block), элемент нетипизированного
# массива или словаря в выражении (d["a"] + 1, arr.back() == b), переменная или параметр без типа; а от
# Variant-значения само по себе (x := arr[0]) — предупреждение INFERENCE_ON_VARIANT, по умолчанию тоже ошибка.
# Обёртка в int()/float()/str()/вызов функции, «as Тип», сравнение с null и «is» — тип есть.
KW = set("not and or in is as if else true false null self super PI TAU INF NAN await var const func return".split())
VAR, VARH, ARR, DICT, ARRD = "variant", "variant_hard", "array", "dict", "array_dict"
ARR_TO_ELEM = {"back", "front", "pop_back", "pop_front", "pop_at", "pick_random", "min", "max", "get"}
DICT_METHODS = set("""size is_empty has has_all keys values get get_or_add erase clear duplicate merge merged find_key
hash is_read_only make_read_only recursive_equal set sort assign is_typed""".split())


def decl_kind(rest):
    r = rest.lstrip()
    if r.startswith(":="):
        v = r[2:].lstrip()
        return ARR if v[:1] == "[" else DICT if v[:1] == "{" else None
    if r.startswith(":"):
        m = re.match(r"(\w+)\s*(\[\s*(\w+)\s*\])?", r[1:].lstrip())
        if not m: return None
        t, el = m.group(1), m.group(3)
        if t == "Array": return ARR if not m.group(2) else ARRD if el == "Dictionary" else None
        if t == "Dictionary": return DICT if not m.group(2) else None
        if t == "Variant": return VAR
        return None
    return VAR

def statement_end(code, pos):
    depth, i, n = 0, pos, len(code)
    while i < n:
        c = code[i]
        if c in "([{": depth += 1
        elif c in ")]}": depth -= 1
        elif c == "\n" and depth <= 0 and code[i - 1] != "\\": return i
        i += 1
    return n

def chain_type(kind, post):
    t = kind
    for op, name in post:
        if t in (VAR,):
            return VAR
        if t == VARH:
            return VAR
        if t == ARR:
            if op == "[": t = VARH
            elif op == "." and name in ARR_TO_ELEM: t = ("call", VARH)
            else: return None
        elif t == ARRD:
            if op == "[": t = DICT
            elif op == "." and name in ARR_TO_ELEM: t = ("call", DICT)
            else: return None
        elif t == DICT:
            if op == "[": t = VARH
            elif op == "." and name == "get": t = ("call", VARH)
            elif op == "." and name in ("keys", "values"): t = ("call", ARR)
            elif op == "." and name not in DICT_METHODS: t = VAR      # d.key — тип не известен
            else: return None
        elif isinstance(t, tuple):   # ждём (…) после метода
            if op == "(": t = t[1]
            else: return None
        if t is None: return None
    if isinstance(t, tuple): return None   # метод без вызова (Callable)
    return t

def untyped_in(rhs, kind_of):
    n = len(rhs); wrapped = [False] * n; stack = []
    for i, c in enumerate(rhs):
        if c in "([{":
            prev = rhs[:i].rstrip()[-1:]
            if c == "(":
                kind = "call" if prev and (prev.isalnum() or prev in "_)]") else "group"
            elif c == "[":
                kind = "index" if prev and (prev.isalnum() or prev in "_)]") else "lit"
            else:
                kind = "lit"
            wrapped[i] = any(k != "group" for k in stack)
            stack.append(kind)
            continue
        if c in ")]}":
            if stack: stack.pop()
            wrapped[i] = any(k != "group" for k in stack)
            continue
        wrapped[i] = any(k != "group" for k in stack)
    top = "".join(" " if wrapped[i] else rhs[i] for i in range(n))
    if re.search(r"\sas\s", top): return None
    tm = re.search(r"\sif\s(.*?)\selse\s", top, re.S)
    skip = (tm.start(1), tm.end(1)) if tm else (-1, -1)
    operands = 0; worst = None; worst_txt = None
    for cm in re.finditer(r"(?<![\w.$%@&])([A-Za-z_]\w*)", rhs):
        i = cm.start()
        if wrapped[i] or skip[0] <= i < skip[1] or cm.group(1) in KW: continue
        operands += 1
        kind = kind_of(cm.group(1))
        if kind is None: continue
        j = cm.end(); post = []
        while j < n:
            ch = rhs[j:j + 1]
            if ch == ".":
                mm = re.match(r"\.(\w+)", rhs[j:])
                if not mm: break
                post.append((".", mm.group(1))); j += mm.end(); continue
            if ch in "([":
                d, k = 0, j
                while k < n:
                    if rhs[k] in "([{": d += 1
                    elif rhs[k] in ")]}":
                        d -= 1
                        if d == 0: break
                    k += 1
                post.append((ch, None)); j = k + 1; continue
            break
        nxt = rhs[j:].lstrip()
        if re.match(r"is\b", nxt) or re.match(r"(==|!=)\s*null\b", nxt): continue
        t = chain_type(kind, post)
        if t == VAR:
            return "без типа: " + rhs[cm.start():j].strip()
        if t == VARH:
            worst, worst_txt = VARH, rhs[cm.start():j].strip()
    if worst == VARH:
        ops = re.sub(r"\s+", " ", top)
        if re.search(r"(==|!=|<=|>=|<|>|\+|-|\*|/|%|\band\b|\bor\b|\bnot\b|\bin\b|&&|\|\|)", ops):
            return "Variant в выражении: " + worst_txt
        return "тип выводится из Variant: " + worst_txt
    return None

def infer_scan():
    res, count = [], 0
    for rel, info in scripts.items():
        code = info["code"]
        members = {}
        for m in re.finditer(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?var\s+(\w+)([^\n]*)", code, re.M):
            members[m.group(1)] = decl_kind(m.group(2))
        funcs = list(re.finditer(r"^(?:static\s+)?func\s+\w+\s*\(([^)]*)\)", code, re.M))
        spans = []
        for k, f in enumerate(funcs):
            end = funcs[k + 1].start() if k + 1 < len(funcs) else len(code)
            decls = []
            for prm in re.split(r",(?![^()\[\]{}]*[)\]}])", f.group(1)):
                pm = re.match(r"\s*(\w+)(.*)", prm, re.S)
                if not pm: continue
                rest = pm.group(2).strip()
                decls.append((f.start(), pm.group(1), VAR if (rest == "" or rest.startswith("=")) else decl_kind(rest)))
            body = code[f.start():end]
            events = []
            for m in re.finditer(r"\bvar\s+(\w+)([^\n]*)", body):
                events.append((f.start() + m.start(), "var", m))
            for m in re.finditer(r"\bfor\s+(\w+)(\s*:\s*\w+)?\s+in\s+(\w+)(\.(?:keys|values)\(\))?\s*:", body):
                events.append((f.start() + m.start(), "for", m))
            for pos, typ, m in sorted(events, key=lambda e: e[0]):
                if typ == "var":
                    decls.append((pos, m.group(1), decl_kind(m.group(2))))
                    continue
                if m.group(2): continue
                src = m.group(3); sk = None; found = False
                for dpos, nm, kd in decls:
                    if nm == src and dpos <= pos: sk = kd; found = True
                if not found: sk = members.get(src)
                if m.group(4): ek = VAR if sk == DICT else None
                else: ek = {ARR: VAR, VAR: VAR, DICT: VAR, ARRD: DICT}.get(sk)
                decls.append((pos, m.group(1), ek))
            spans.append((f.start(), end, decls))
        def kinds_at(name, pos):
            for a, b, decls in spans:
                if a <= pos < b:
                    found, kd = False, None
                    for dpos, nm, k in decls:
                        if nm == name and dpos < pos: found, kd = True, k
                    if found: return kd
            return members.get(name)
        for m in re.finditer(r"\bvar\s+(\w+)\s*:=", code):
            count += 1
            a = m.end(); b = statement_end(code, a)
            bad = untyped_in(code[a:b], lambda nm: kinds_at(nm, m.start()))
            if bad:
                problem(rel, line_of(code, m.start()), "var %s := … — Godot не выведет тип (%s): укажите тип явно, "
                        "var %s: Тип = …" % (m.group(1), bad, m.group(1)))
    return count


n_infer = infer_scan()

# --- Звук (15.6): Audio.SOUNDS <-> audio.tscn <-> assets/sfx ------------------------------------------
audio_gd = ROOT / "autoload" / "audio.gd"
audio_tscn = ROOT / "autoload" / "audio.tscn"
n_sounds = 0
if audio_gd.exists() and audio_tscn.exists():
    asrc = audio_gd.read_text(encoding="utf-8")
    consts = dict(re.findall(r'^const\s+([A-Z_]+)\s*:=\s*&"(\w+)"', asrc, re.M))
    m = re.search(r"^const\s+SOUNDS\s*:[^=]*=\s*\[([^\]]*)\]", asrc, re.M | re.S)
    if m is None:
        problem("autoload/audio.gd", 1, "нет списка SOUNDS")
        sounds = {}
    else:
        sounds = {}
        for c in re.findall(r"[A-Z_]+", m.group(1)):
            if c not in consts:
                problem("autoload/audio.gd", 1, "SOUNDS: %s — не звук (нет const %s := &\"…\")" % (c, c))
            else:
                sounds[c] = consts[c]
        for c, nm in consts.items():
            if c not in sounds:
                problem("autoload/audio.gd", 1, "звук %s (%s) не в SOUNDS" % (c, nm))
    n_sounds = len(sounds)
    tsrc = audio_tscn.read_text(encoding="utf-8")
    ext = dict((i, pth) for pth, i in re.findall(r'\[ext_resource[^\]]*path="([^"]+)"[^\]]*id="([^"]+)"', tsrc))
    nodes = {}
    for part in re.split(r"\n(?=\[)", tsrc):
        hm = re.match(r'\[node name="(\w+)" type="AudioStreamPlayer" parent="\."\]', part)
        if hm is None:
            continue
        nm, body = hm.group(1), part
        sm = re.search(r'stream = ExtResource\("([^"]+)"\)', body)
        bm = re.search(r'bus = &"(\w+)"', body)
        nodes[nm] = (ext.get(sm.group(1)) if sm else None, bm.group(1) if bm else "Master")
    for c, nm in sounds.items():
        if nm not in nodes:
            problem("autoload/audio.tscn", 1, "нет узла звука %s (Audio.%s)" % (nm, c))
            continue
        pth, bus = nodes[nm]
        if pth is None or not (ROOT / pth.replace("res://", "")).exists():
            problem("autoload/audio.tscn", 1, "у звука %s нет файла (%s)" % (nm, pth))
        elif not pth.startswith("res://assets/sfx/"):
            problem("autoload/audio.tscn", 1, "звук %s не из assets/sfx: %s" % (nm, pth))
        if bus != "SFX":
            problem("autoload/audio.tscn", 1, "звук %s на шине %s (ждали SFX)" % (nm, bus))
    for nm in nodes:
        if nm != "Music" and nm not in sounds.values():
            problem("autoload/audio.tscn", 1, "узел %s — не звук из Audio.SOUNDS" % nm)
    for p in project_files("*.gd"):
        srel = str(p.relative_to(ROOT))
        code = strip_code(p.read_text(encoding="utf-8"), srel)
        for mm in re.finditer(r"\bAudio\.play(?:_pitched)?\(\s*Audio\.([A-Z_]+)", code):
            if mm.group(1) not in sounds:
                problem(srel, line_of(code, mm.start()), "Audio.%s — не звук из Audio.SOUNDS" % mm.group(1))
else:
    problem("autoload", 1, "нет audio.gd или audio.tscn")

# --- Встроенные методы и свойства (19.5e) ------------------------------------
# Основные члены встроенных классов, которые наследуют скрипты проекта. Свойство p даёт и методы set_p / get_p.
NATIVE_PARENT = {"RefCounted": "Object", "Resource": "RefCounted", "Node": "Object", "CanvasItem": "Node",
                 "CanvasLayer": "Node", "Node2D": "CanvasItem", "Control": "CanvasItem", "ColorRect": "Control",
                 "Label": "Control", "BaseButton": "Control", "Button": "BaseButton", "Container": "Control",
                 "BoxContainer": "Container", "PanelContainer": "Container"}
NATIVE_PROPS = {
    "Object": "script",
    "Resource": "resource_name resource_path resource_local_to_scene resource_scene_unique_id",
    "Node": "name owner process_mode process_priority scene_file_path unique_name_in_owner multiplayer "
            "editor_description auto_translate_mode physics_interpolation_mode",
    "CanvasItem": "visible modulate self_modulate show_behind_parent top_level clip_children light_mask "
                  "visibility_layer texture_filter texture_repeat material use_parent_material z_index "
                  "z_as_relative y_sort_enabled",
    "CanvasLayer": "layer visible offset rotation scale transform follow_viewport_enabled follow_viewport_scale "
                   "custom_viewport",
    "Node2D": "position rotation rotation_degrees scale skew transform global_position global_rotation "
              "global_rotation_degrees global_scale global_skew global_transform",
    "Control": "position size scale rotation rotation_degrees pivot_offset global_position custom_minimum_size "
               "anchor_left anchor_top anchor_right anchor_bottom offset_left offset_top offset_right offset_bottom "
               "grow_horizontal grow_vertical layout_direction layout_mode size_flags_horizontal size_flags_vertical "
               "size_flags_stretch_ratio clip_contents mouse_filter mouse_default_cursor_shape focus_mode "
               "tooltip_text theme theme_type_variation localize_numeral_system shortcut_context",
    "ColorRect": "color",
    "Label": "text label_settings horizontal_alignment vertical_alignment autowrap_mode uppercase clip_text "
             "visible_characters visible_ratio lines_skipped max_lines_visible text_overrun_behavior",
    "BaseButton": "disabled toggle_mode button_pressed action_mode button_mask keep_pressed_outside button_group "
                  "shortcut",
    "Button": "text icon flat alignment clip_text expand_icon icon_alignment vertical_icon_alignment "
              "text_overrun_behavior autowrap_mode",
    "BoxContainer": "alignment vertical",
}
NATIVE_METHODS = {
    "Object": "get_class is_class set get call callv emit_signal connect disconnect is_connected notification "
              "get_script set_script free get_instance_id has_method has_signal tr tr_n set_meta get_meta has_meta "
              "set_deferred call_deferred is_queued_for_deletion get_property_list get_method_list",
    "RefCounted": "reference unreference init_ref get_reference_count",
    "Resource": "duplicate emit_changed get_rid get_local_scene setup_local_to_scene take_over_path",
    "Node": "add_child remove_child get_child get_children get_child_count get_node get_node_or_null has_node "
            "get_parent find_child find_children get_tree is_inside_tree queue_free set_process is_processing "
            "set_physics_process set_process_input set_process_unhandled_input get_path get_index move_child "
            "reparent add_sibling add_to_group remove_from_group is_in_group get_groups print_tree propagate_call "
            "duplicate replace_by create_tween get_viewport get_window is_node_ready request_ready atr atr_n "
            "can_process is_ancestor_of get_path_to get_process_delta_time get_physics_process_delta_time",
    "CanvasItem": "show hide is_visible is_visible_in_tree queue_redraw draw_line draw_rect draw_circle draw_arc "
                  "draw_texture draw_texture_rect draw_string draw_polygon draw_colored_polygon draw_polyline "
                  "draw_set_transform draw_style_box get_canvas get_canvas_item get_global_transform get_transform "
                  "get_viewport_rect get_global_mouse_position get_local_mouse_position make_input_local "
                  "move_to_front force_update_transform get_world_2d",
    "CanvasLayer": "show hide get_final_transform get_canvas",
    "Node2D": "rotate translate look_at move_local_x move_local_y global_translate apply_scale get_angle_to "
              "to_local to_global",
    "Control": "get_rect get_global_rect set_anchor set_anchors_preset set_offsets_preset "
               "set_anchors_and_offsets_preset get_minimum_size get_combined_minimum_size grab_focus release_focus "
               "has_focus accept_event get_tooltip update_minimum_size warp_mouse set_drag_preview force_drag "
               "get_parent_control get_screen_position get_parent_area_size get_theme_color get_theme_constant "
               "get_theme_font get_theme_font_size get_theme_icon get_theme_stylebox add_theme_color_override "
               "add_theme_constant_override add_theme_font_override add_theme_font_size_override "
               "add_theme_icon_override add_theme_stylebox_override begin_bulk_theme_override "
               "end_bulk_theme_override is_layout_rtl find_next_valid_focus find_prev_valid_focus",
    "Label": "get_line_count get_visible_line_count get_line_height get_total_character_count",
    "BaseButton": "is_pressed is_hovered get_draw_mode set_pressed_no_signal",
    "Button": "set_button_icon get_button_icon",
    "Container": "queue_sort fit_child_in_rect",
    "BoxContainer": "add_spacer",
}


def native_base(info, seen=None):
    seen = seen if seen is not None else set()
    while info is not None and info["rel"] not in seen:
        seen.add(info["rel"])
        ext = info["extends"]
        if ext.startswith("res://"):
            info = scripts.get(ext)
        elif ext in by_class:
            info = by_class[ext]
        else:
            return ext or "RefCounted"
    return None


def native_members(cls):
    props, methods = set(), set()
    while cls:
        p = NATIVE_PROPS.get(cls, "").split()
        props.update(p)
        methods.update(NATIVE_METHODS.get(cls, "").split())
        methods.update("set_" + x for x in p)
        methods.update("get_" + x for x in p)
        cls = NATIVE_PARENT.get(cls)
    return props, methods


n_native = 0
for rel, info in scripts.items():
    base = native_base(info)
    if base is None:
        continue
    if base not in NATIVE_PARENT and base != "Object":
        problem(rel, 1, "встроенный класс %s не описан в NATIVE_PARENT (tools/check_gd.py)" % base)
        continue
    props, methods = native_members(base)
    for fn, ln in info["funcs"].items():
        n_native += 1
        if fn in methods or fn in props:
            problem(rel, ln, "функция %s совпадает с методом встроенного %s — Godot не загрузит скрипт "
                    "(переименуйте)" % (fn, base))
    for m in re.finditer(r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?var\s+(\w+)", info["code"], re.M):
        n_native += 1
        if m.group(1) in props or m.group(1) in methods:
            problem(rel, line_of(info["code"], m.start()), "var %s совпадает со свойством встроенного %s — "
                    "Godot не загрузит скрипт (переименуйте)" % (m.group(1), base))


print("скриптов: %d, сцен и ресурсов: %d, автозагрузок: %d" % (len(scripts), len(scenes), len(autoloads)))
print("обращений Класс.член: %d, через переменные с типом-классом: %d, звуков: %d, var … := проверено: %d"
      % (n_static, n_typed, n_sounds, n_infer))
print("функций и var сверено со встроенными классами: %d" % n_native)
print("\n".join(problems) if problems else "проблем не найдено")
sys.exit(1 if problems else 0)
