#!/usr/bin/env python3
"""Render the Vellum logo SVGs into every platform's launcher-icon slot plus the
in-app and server assets. Single source of truth: logo-icon.svg (app tile) and
logo-mark.svg (transparent mark).

Requires cairosvg + Pillow. Run from anywhere:
    python3 design/generate_icons.py
"""
import io
import os
from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
DESIGN = ROOT / "design"
APP = ROOT / "app"


def render(svg: Path, size: int) -> Image.Image:
    png = cairosvg.svg2png(url=str(svg), output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def rounded(im: Image.Image, radius_frac: float = 0.22) -> Image.Image:
    r = int(im.size[0] * radius_frac)
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, im.size[0] - 1, im.size[1] - 1], radius=r, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out


def rounded_svg(svg_text: str) -> str:
    """Give the full-bleed tile its own rounded corners, so the SVG outputs
    (favicon, scalable theme icon) match the rounded raster icons instead of
    showing hard square corners. ~0.22 of the side, matching rounded()."""
    return svg_text.replace(
        '<rect width="512" height="512" fill="url(#tile)"/>',
        '<rect width="512" height="512" rx="112" ry="112" fill="url(#tile)"/>')


def save(im: Image.Image, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path)
    print("wrote", path.relative_to(ROOT))


def main():
    icon = DESIGN / "logo-icon.svg"
    mark = DESIGN / "logo-mark.svg"

    # Android — legacy square launcher icon, full-bleed (pre-API 26 launchers
    # apply their own mask).
    for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96,
                     "xxhdpi": 144, "xxxhdpi": 192}.items():
        save(render(icon, px),
             APP / f"android/app/src/main/res/mipmap-{name}/ic_launcher.png")

    # Android adaptive icon (API 26+): separate foreground (book) + background
    # (ink tile) layers on the 108dp canvas, plus a monochrome layer for the
    # Android 13+ themed-icon treatment. Densities are 108dp * bucket scale.
    fg = DESIGN / "logo-adaptive-foreground.svg"
    bg = DESIGN / "logo-adaptive-background.svg"
    for name, px in {"mdpi": 108, "hdpi": 162, "xhdpi": 216,
                     "xxhdpi": 324, "xxxhdpi": 432}.items():
        d = APP / f"android/app/src/main/res/mipmap-{name}"
        save(render(bg, px), d / "ic_launcher_background.png")
        fg_img = render(fg, px)
        save(fg_img, d / "ic_launcher_foreground.png")
        # Monochrome = the foreground silhouette in one flat colour; the system
        # tints it. Keep only the alpha, fill it solid black.
        mono = Image.new("RGBA", fg_img.size, (0, 0, 0, 0))
        mono.paste((0, 0, 0, 255), (0, 0), fg_img.split()[3])
        save(mono, d / "ic_launcher_monochrome.png")

    adaptive = APP / "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
    adaptive.parent.mkdir(parents=True, exist_ok=True)
    adaptive.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n')
    print("wrote", adaptive.relative_to(ROOT))

    # macOS — rounded, shown as-is in the dock.
    for px in (16, 32, 64, 128, 256, 512, 1024):
        save(rounded(render(icon, px)),
             APP / f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{px}.png")

    # Windows — a single multi-size .ico.
    ico = rounded(render(icon, 256))
    ico_path = APP / "windows/runner/resources/app_icon.ico"
    ico_path.parent.mkdir(parents=True, exist_ok=True)
    ico.save(ico_path, sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
    print("wrote", ico_path.relative_to(ROOT))

    # In-app — the About dialog icon, bundled as a Flutter asset. Linux also
    # loads this same asset at runtime for the window/taskbar icon
    # (see linux/runner/my_application.cc).
    save(rounded(render(icon, 512)), APP / "assets/logo.png")

    # Linux icon theme — named after the application ID so GTK can resolve it as
    # a themed window icon (see linux/install-dev.sh). Scalable SVG + a few PNG
    # sizes, installed under ~/.local/share/icons/hicolor by the install script.
    app_id = "com.avladescu.vellum"
    theme = APP / "linux/packaging/icons/hicolor"
    (theme / "scalable/apps").mkdir(parents=True, exist_ok=True)
    (theme / f"scalable/apps/{app_id}.svg").write_text(rounded_svg(icon.read_text()))
    print("wrote", (theme / f"scalable/apps/{app_id}.svg").relative_to(ROOT))
    for px in (48, 64, 128, 256):
        save(rounded(render(icon, px)),
             theme / f"{px}x{px}/apps/{app_id}.png")

    # Server console/public — favicon (rounded tile) + header mark, as SVGs.
    for text, dst in [(rounded_svg(icon.read_text()), "server/web/favicon.svg"),
                      (mark.read_text(), "server/web/logo.svg")]:
        out = ROOT / dst
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text)
        print("wrote", dst)


if __name__ == "__main__":
    main()
