#!/usr/bin/env python3
"""Generate placeholder picture cards (256x256 PNG) for every word in assets/content.

Solid pastel background (tinted from the Space Cadets palette) with a neutral
white glyph - a ring of dots and a centre shape - whose shape, count and
rotation come from a hash of the word.

Deliberately NOT the word, and NOT its initial letter: in a
"which picture is ...?" question a letter lets a child who knows the alphabet
pick the right card without recognising the picture at all (ball / cat / dog
used to show B, C and D). The glyph still differs per word, so the cards are
told apart and a tester can see which is which, but it teaches nothing and
gives nothing away.

Real artwork replaces these later; keep the file names
(assets/images/grade<N>/<word>.png) when swapping them in.

Usage (from the project root): python3 tools/gen_placeholder_images.py
Requires Pillow.
"""
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SIZE = 256
IMAGES = Path(__file__).resolve().parent.parent / "assets" / "images"

# Space Cadets accents (lib/ui/theme/app_theme.dart), mixed 25% towards the
# dark background so the white lettering stays readable on a pastel tone.
PALETTE = ["#4DE1FF", "#FFD84D", "#5CF2A0", "#FF5CAA", "#FF8A5B", "#7B61FF"]
BG = (0x14, 0x12, 0x3A)

CONTENT = Path(__file__).resolve().parent.parent / "assets" / "content"


def words_by_grade() -> dict[str, list[str]]:
    """Every distinct `image` file name referenced by assets/content/grade*/u*.json."""
    out: dict[str, list[str]] = {}
    for f in sorted(CONTENT.glob("grade*/u*.json")):
        for item in json.loads(f.read_text(encoding="utf-8"))["items"]:
            grade, name = item["image"].split("/")
            words = out.setdefault(grade, [])
            word = name.removesuffix(".png")
            if word not in words:
                words.append(word)
    return out


FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf",
    "DejaVuSans-Bold.ttf",
    "Arial Bold.ttf",
]


def font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default(size)


def tint(hex_color: str) -> tuple[int, int, int]:
    rgb = [int(hex_color[i : i + 2], 16) for i in (1, 3, 5)]
    return tuple(round(c * 0.75 + b * 0.25) for c, b in zip(rgb, BG))


def glyph_seed(word: str) -> int:
    """Stable per word (and so per file), unrelated to its spelling."""
    return int.from_bytes(hashlib.sha256(word.encode("utf-8")).digest()[:4], "big")


def draw_card(word: str, color: str) -> Image.Image:
    """A neutral, word-specific shape. Never a letter (see the module docstring)."""
    img = Image.new("RGB", (SIZE, SIZE), tint(color))
    d = ImageDraw.Draw(img)
    h = glyph_seed(word)
    c = SIZE / 2
    dots = 5 + h % 7              # 5..11 dots around the centre
    radius = SIZE * 0.3
    dot_r = SIZE * (0.035 + 0.02 * ((h >> 3) % 3))
    phase = ((h >> 6) % 360) * math.pi / 180
    for i in range(dots):
        a = phase + i * 2 * math.pi / dots
        x, y = c + radius * math.cos(a), c + radius * math.sin(a)
        d.ellipse((x - dot_r, y - dot_r, x + dot_r, y + dot_r), fill="white")
    inner = SIZE * 0.11
    shape = (h >> 12) % 3
    box = (c - inner, c - inner, c + inner, c + inner)
    if shape == 0:
        d.ellipse(box, fill="white")
    elif shape == 1:
        d.rectangle(box, fill="white")
    else:
        d.regular_polygon((c, c, inner), n_sides=3, rotation=int((h >> 18) % 360), fill="white")
    return img


def main() -> None:
    for grade, words in words_by_grade().items():
        out = IMAGES / grade
        out.mkdir(parents=True, exist_ok=True)
        for i, word in enumerate(words):
            draw_card(word, PALETTE[i % len(PALETTE)]).save(out / f"{word}.png", optimize=True)
        print(f"wrote {len(words)} images to {out}")


if __name__ == "__main__":
    main()
