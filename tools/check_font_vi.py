"""Checks that the bundled Baloo 2 static fonts contain Vietnamese glyphs.

Usage: python3 tools/check_font_vi.py   (needs `pip install fonttools`)
"""
import sys
from fontTools.ttLib import TTFont

CHARS = "ếặữơưđĐăồẫỷỳạộớự"
ok = True
for n in ("Regular", "Medium", "SemiBold", "Bold"):
    f = TTFont(f"assets/fonts/Baloo2-{n}.ttf")
    cmap = f.getBestCmap()
    missing = [c for c in CHARS if ord(c) not in cmap]
    print(n, "fvar" in f, f["OS/2"].usWeightClass, "missing:", missing)
    ok = ok and not missing and "fvar" not in f
sys.exit(0 if ok else 1)
