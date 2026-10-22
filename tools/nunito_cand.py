#!/usr/bin/env python3
"""Восстановление docs/fonts/cand/Nunito-ExtraBlack.ttf (вес 1000) и Nunito-ExtraBold.ttf (вес 800).

Нужны кадрам A2/A3 (tools/style_a2.py, style_a3.py, style_a3b.py) и листу иконок (tools/icons_sheet.py).
Источник — переменный Nunito[wght].ttf из google/fonts (ofl/nunito, v3.602, OFL):
https://github.com/google/fonts/raw/main/ofl/nunito/Nunito%5Bwght%5D.ttf
Вес замораживается instancer'ом, набор символов — как у прежнего game_font.ttf (лог 29.09 20:30).
С 13.3 Nunito-ExtraBold.ttf = assets/fonts/nunito_extrabold.ttf (шрифт темы), ExtraBlack = nunito_black.ttf.

    python3 tools/nunito_cand.py ПУТЬ/Nunito[wght].ttf
"""
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "fonts", "cand")
UNICODES = "U+0020-007E,U+00A0-017F,U+0400-045F,U+0490-0491,U+2010-2027,U+2030-203A,U+2116,U+20BA,U+20BD,U+2212"


def main(src):
    os.makedirs(OUT, exist_ok=True)
    for wght, name in ((1000, "Nunito-ExtraBlack"), (800, "Nunito-ExtraBold")):
        tmp = os.path.join(OUT, name + ".full.ttf")
        instancer.instantiateVariableFont(TTFont(src), {"wght": wght}).save(tmp)
        subset.main([tmp, "--unicodes=" + UNICODES, "--layout-features=*", "--no-hinting", "--desubroutinize",
                     "--name-IDs=*", "--notdef-outline", "--output-file=" + os.path.join(OUT, name + ".ttf")])
        os.remove(tmp)
        print(name + ".ttf", os.path.getsize(os.path.join(OUT, name + ".ttf")))


if __name__ == "__main__":
    main(sys.argv[1])
