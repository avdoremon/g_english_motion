"""Generates the Tin Tin 'Jump Star' logo assets (SVG + PNG) from one source.

Run: python3 tools/gen_logo.py   (needs rsvg-convert and ImageMagick `convert`)
"""
import subprocess, pathlib
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "branding"
NAVY, PUR, CY, YEL, COR = "#1B1F4B", "#6C4DFF", "#35D0FF", "#FFD23F", "#FF6B6B"
STAR = "0,-10 3,-3 10,-3 4.5,2 6.5,9.5 0,5 -6.5,9.5 -4.5,2 -10,-3 -3,-3"
V = dict(b="#fff", l=NAVY, v=NAVY, e=CY, s=YEL, p=PUR, y=YEL, c=CY, r=COR, w="#fff")

def star(x, y, s, fill, sw=2.5):
    return (f'<polygon transform="translate({x} {y}) scale({s})" points="{STAR}" '
            f'fill="{fill}" stroke="var(--l)" stroke-width="{sw}" stroke-linejoin="round"/>')

def head(cx=100, cy=112):
    return (f'<line x1="{cx}" y1="{cy-70}" x2="{cx}" y2="{cy-90}" stroke="var(--l)" stroke-width="6" stroke-linecap="round"/>'
            + star(cx, cy-96, 1.5, "var(--s)") +
            f'<circle cx="{cx}" cy="{cy}" r="64" fill="var(--b)" stroke="var(--l)" stroke-width="8"/>'
            f'<rect x="{cx-48}" y="{cy-28}" width="96" height="66" rx="33" fill="var(--v)" stroke="var(--l)" stroke-width="5"/>'
            f'<circle cx="{cx-18}" cy="{cy+4}" r="9" fill="var(--e)"/><circle cx="{cx+18}" cy="{cy+4}" r="9" fill="var(--e)"/>'
            f'<path d="M{cx-10} {cy+20} Q{cx} {cy+29} {cx+10} {cy+20}" fill="none" stroke="var(--e)" stroke-width="4" stroke-linecap="round"/>')

def arm(d):
    return (f'<path d="{d}" fill="none" stroke="var(--l)" stroke-width="20" stroke-linecap="round"/>'
            f'<path d="{d}" fill="none" stroke="var(--w)" stroke-width="7" stroke-linecap="round"/>')

BODY = (star(100, 252, 1.1, "var(--y)") + star(62, 262, .7, "var(--c)", 3) + star(138, 262, .7, "var(--c)", 3)
        + arm("M84 190 Q16 190 22 112") + arm("M116 190 Q184 190 178 112")
        + '<path d="M92 206 L82 230" stroke="var(--l)" stroke-width="18" stroke-linecap="round"/>'
          '<path d="M108 206 L118 230" stroke="var(--l)" stroke-width="18" stroke-linecap="round"/>'
          '<circle cx="82" cy="234" r="11" fill="var(--r)" stroke="var(--l)" stroke-width="5"/>'
          '<circle cx="118" cy="234" r="11" fill="var(--r)" stroke="var(--l)" stroke-width="5"/>'
          '<rect x="76" y="166" width="48" height="46" rx="18" fill="var(--p)" stroke="var(--l)" stroke-width="6"/>'
        + head()
        + '<circle cx="22" cy="106" r="11" fill="var(--w)" stroke="var(--l)" stroke-width="5"/>'
          '<circle cx="178" cy="106" r="11" fill="var(--w)" stroke="var(--l)" stroke-width="5"/>')

def resolve(s, v):
    for k, c in v.items():
        s = s.replace(f"var(--{k})", c)
    return s

def mark_svg(v, w=200, h=280, bg=None, pad_h=None, canvas=None):
    """Mark centred in a canvas x canvas square (or its own size)."""
    body = resolve(BODY, v)
    if canvas is None:
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'
    scale = pad_h / h
    tx, ty = (canvas - w * scale) / 2, (canvas - h * scale) / 2
    rect = f'<rect width="{canvas}" height="{canvas}" fill="{bg}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{canvas}" height="{canvas}" viewBox="0 0 {canvas} {canvas}">'
            f'{rect}<g transform="translate({tx} {ty}) scale({scale})">{body}</g></svg>')

def png(svg_text, name, size):
    svg_path = OUT / (name + ".svg")
    svg_path.write_text(svg_text)
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size) if "square" in name else "0", str(svg_path),
                    "-o", str(OUT / (name + ".png"))], check=True) if False else None

def render(svg_text, stem, width=None, height=None):
    p = OUT / f"{stem}.svg"
    p.write_text(svg_text)
    cmd = ["rsvg-convert"] + (["-w", str(width)] if width else []) + (["-h", str(height)] if height else []) + [str(p), "-o", str(OUT / f"{stem}.png")]
    subprocess.run(cmd, check=True)

OUT.mkdir(parents=True, exist_ok=True)
# Master mark (transparent) and the 1024 launcher icon (purple square, mark in the inner 66%).
render(mark_svg(V), "tintin_mark", height=1024)
render(mark_svg(V, canvas=1024, bg=PUR, pad_h=640), "tintin_icon_1024", 1024, 1024)
# Adaptive-icon foreground: transparent 1024 canvas, mark inside the 66% safe zone.
render(mark_svg(V, canvas=1024, pad_h=600), "tintin_icon_foreground", 1024, 1024)
# Splash image: transparent, mark only.
render(mark_svg(V, canvas=768, pad_h=600), "tintin_splash", 768, 768)
# Android 13 themed icon: alpha-only. Light parts become transparent, ink stays opaque.
mono = dict(V, b="#fff", l="#000", v="#000", e="#fff", s="#000", p="#000", y="#000", c="#000", r="#000", w="#fff")
render(mark_svg(mono, canvas=1024, pad_h=600), "tintin_icon_monochrome", 1024, 1024)
subprocess.run(["convert", str(OUT / "tintin_icon_monochrome.png"), "-fuzz", "12%", "-transparent", "white",
                str(OUT / "tintin_icon_monochrome.png")], check=True)
print("ok")
