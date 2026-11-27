#!/usr/bin/env python3
"""Кадр шейдеров рядом с картинкой-референсом (20.8, правило пользователя 27.11: шейдер — сначала картинка).

Кадр игры считает tools/shader_preview.py (те же .gdshader на numpy), референс — docs/shader_refs/<ref>
(сгенерирован по кадру игры, промпт — docs/shader_refs/PROMPTS.md), приводится к 720×1280.

  python3 tools/shader_ref_compare.py [область] [--ref game_scene.jpg] [--out /tmp/shader_cmp]
  область: board, blocks, yellow, tray, top, full (по умолчанию board) — с общим референсом game_scene.jpg;
           nest, shelf, background — со своим референсом (OWN ниже: картинка генератора по вырезке кадра)

Пишет <out>/cmp_<область>.png: слева референс, справа шейдеры. Только смотреть глазами — числовой оценки нет:
референс нарисован генератором и не совпадает с раскладкой до пикселя."""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import shader_preview as sp  # noqa: E402

BOXES = {"board": (20, 180, 700, 870), "blocks": (40, 200, 470, 640), "yellow": (350, 300, 700, 870),
         "tray": (0, 990, 720, 1270), "top": (0, 0, 720, 180), "full": (0, 0, 720, 1280)}
SCALE = {"blocks": 1.4, "yellow": 1.2, "full": 0.6}
# Свои референсы (20.8): генератору давали вырезку кадра shader_preview (box) крупно — картинка покрывает ровно её.
# background — кадр одного фона (Background без поля и кнопок).
OWN = {"nest": ("nest.jpg", (140, 520, 470, 850), 2.4),
       "shelf": ("shelf.jpg", (0, 1000, 720, 1280), 1.0),
       "background": ("background.jpg", (0, 0, 720, 1280), 0.5)}
FONT = os.path.join(ROOT, "assets", "fonts", "nunito_extrabold.ttf")


def side(ref, img, box, scale):
    a, b = ref.crop(box), img.crop(box)
    if scale != 1.0:
        size = (int(a.width * scale), int(a.height * scale))
        a, b = a.resize(size, Image.LANCZOS), b.resize(size, Image.LANCZOS)
    out = Image.new("RGB", (a.width * 2 + 10, a.height + 30), (30, 30, 30))
    out.paste(a, (0, 30))
    out.paste(b, (a.width + 10, 30))
    d = ImageDraw.Draw(out)
    f = ImageFont.truetype(FONT, 20)
    d.text((8, 4), "референс", fill=(255, 255, 255), font=f)
    d.text((a.width + 18, 4), "шейдеры", fill=(255, 255, 255), font=f)
    return out


def own(area, out_dir):
    name, box, scale = OWN[area]
    w, h = box[2] - box[0], box[3] - box[1]
    ref = Image.open(os.path.join(ROOT, "docs", "shader_refs", name)).convert("RGB").resize((w, h), Image.LANCZOS)
    img = sp.background(720, 1280).image() if area == "background" else sp.render()[0]
    canvas = Image.new("RGB", (720, 1280))
    canvas.paste(ref, box[:2])
    path = os.path.join(out_dir, "cmp_%s.png" % area)
    side(canvas, img, box, scale).save(path)
    return path


def main(argv):
    out_dir = argv[argv.index("--out") + 1] if "--out" in argv else "/tmp/shader_cmp"
    area = next((a for a in argv if not a.startswith("--") and a in OWN), None)
    if area:
        os.makedirs(out_dir, exist_ok=True)
        print(own(area, out_dir))
        return
    area = next((a for a in argv if not a.startswith("--") and a in BOXES), "board")
    ref_name = argv[argv.index("--ref") + 1] if "--ref" in argv else "game_scene.jpg"
    os.makedirs(out_dir, exist_ok=True)
    ref = Image.open(os.path.join(ROOT, "docs", "shader_refs", ref_name)).convert("RGB").resize((720, 1280), Image.LANCZOS)
    img, _ = sp.render()
    path = os.path.join(out_dir, "cmp_%s.png" % area)
    side(ref, img, BOXES[area], SCALE.get(area, 1.0)).save(path)
    print(path)


if __name__ == "__main__":
    main(sys.argv[1:])
