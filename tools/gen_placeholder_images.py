#!/usr/bin/env python3
"""Generate placeholder picture cards (256x256 PNG) for every word in assets/content.

Solid pastel background (tinted from the Space Cadets palette), a big white
first letter (the word itself is not printed, so it cannot leak the answer). Real artwork replaces these later;
keep the file names (assets/images/grade<N>/<word>.png) when swapping them in.

Usage (from the project root): python3 tools/gen_placeholder_images.py
Requires Pillow.
"""
import json
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


def draw_card(word: str, color: str) -> Image.Image:
    img = Image.new("RGB", (SIZE, SIZE), tint(color))
    d = ImageDraw.Draw(img)
    # Only the initial letter: the full word would give the answer away in
    # "which picture is ...?" questions.
    d.text((SIZE / 2, SIZE / 2), word[0].upper(), font=font(160), fill="white", anchor="mm")
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
