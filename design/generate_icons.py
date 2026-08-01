#!/usr/bin/env python3
"""Fan the Vellum app icon out into every platform's launcher slot.

Single source of truth: ``design/logo-source.png`` — a square, full-bleed tile
with transparent corners, produced by ``prepare_source.py`` from the original
artwork.

The previous version rendered from SVG via cairosvg. The artwork is now a
raster, so this resamples instead; that also drops the cairosvg dependency,
which was not installed on the machine this was last run from and so had
quietly stopped being runnable.

Requires Pillow. Run from anywhere:
    python3 design/generate_icons.py
"""
import base64
import io
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
DESIGN = ROOT / "design"
APP = ROOT / "app"

SOURCE = DESIGN / "logo-source.png"

#: The tile's own corner radius, measured off the artwork (229/1297).
CORNER_RADIUS = 0.177

#: The tile's background beige, sampled from it. Used as the flat lower layer of
#: the Android adaptive icon, where the launcher masks the corners itself.
TILE_BEIGE = (241, 215, 180, 255)


def load() -> Image.Image:
    if not SOURCE.exists():
        raise SystemExit(
            f"{SOURCE.relative_to(ROOT)} is missing — run design/prepare_source.py first"
        )
    return Image.open(SOURCE).convert("RGBA")


def scaled(master: Image.Image, size: int) -> Image.Image:
    """Resampled to `size`. LANCZOS because these go down by large factors —
    a 1024px tile to a 16px macOS icon — and anything cheaper turns the book's
    linework into mud."""
    return master.resize((size, size), Image.LANCZOS)


def squared(im: Image.Image) -> Image.Image:
    """The tile with its corners filled in, for the slots that apply their own
    mask (Android's legacy launcher, and the adaptive background). Leaving the
    corners transparent there shows the launcher's own backdrop through them."""
    out = Image.new("RGBA", im.size, TILE_BEIGE)
    out.alpha_composite(im)
    return out


def book_only(master: Image.Image) -> Image.Image:
    """The book, cut out of the tile onto transparency.

    For the adaptive icon the *background* is the beige and the *foreground* is
    the artwork, so pasting the whole tile as the foreground would show a tile
    inside a tile. The book's bounding box is found from its own ink rather than
    hardcoded, so re-running this after an artwork change still frames it."""
    import numpy as np

    a = np.asarray(master.convert("RGB")).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    # Dark linework, or the ribbon's red — everything that isn't tile or page.
    ink = (a.sum(axis=2) < 330) | ((r > 100) & (r - g > 60) & (r - b > 60))
    ys, xs = np.where(ink)
    pad = int(master.width * 0.02)
    box = (max(xs.min() - pad, 0), max(ys.min() - pad, 0),
           min(xs.max() + pad, master.width), min(ys.max() + pad, master.height))
    return master.crop(box)


def on_canvas(art: Image.Image, size: int, fraction: float) -> Image.Image:
    """`art` centred on a transparent square of `size`, occupying `fraction` of
    it. Android's adaptive foreground is only guaranteed to show its middle
    ~66%, so anything outside that can be cropped by the launcher's mask."""
    target = int(size * fraction)
    w, h = art.size
    scale = target / max(w, h)
    art = art.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(art, ((size - art.width) // 2, (size - art.height) // 2))
    return out


def svg_wrapper(im: Image.Image, size: int = 512) -> str:
    """A raster wrapped in SVG, for the slots that want a `.svg` — the Linux
    scalable theme icon and the console favicon.

    Embedding rather than tracing: a faithful trace of watercolour shading is
    not something to attempt, and every consumer of these renders them to a
    bitmap anyway. Downscaled first, so the favicon is tens of kilobytes rather
    than the megabytes the full-size art would inline to."""
    buf = io.BytesIO()
    scaled(im, size).save(buf, format="PNG", optimize=True)
    data = base64.b64encode(buf.getvalue()).decode("ascii")
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'xmlns:xlink="http://www.w3.org/1999/xlink" '
        f'viewBox="0 0 {size} {size}" width="{size}" height="{size}">\n'
        f'  <title>Vellum</title>\n'
        f'  <image width="{size}" height="{size}" '
        f'xlink:href="data:image/png;base64,{data}"/>\n'
        f'</svg>\n'
    )


def save(im: Image.Image, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, optimize=True)
    print("wrote", path.relative_to(ROOT))


def write_text(text: str, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    print("wrote", path.relative_to(ROOT))


def main():
    master = load()

    # Android — legacy square launcher icon, full-bleed (pre-API 26 launchers
    # apply their own mask, so the corners are filled).
    for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96,
                     "xxhdpi": 144, "xxxhdpi": 192}.items():
        save(squared(scaled(master, px)),
             APP / f"android/app/src/main/res/mipmap-{name}/ic_launcher.png")

    # Android adaptive icon (API 26+): a flat beige background and the book as
    # the foreground, both on the 108dp canvas. Densities are 108dp * bucket.
    book = book_only(master)
    for name, px in {"mdpi": 108, "hdpi": 162, "xhdpi": 216,
                     "xxhdpi": 324, "xxxhdpi": 432}.items():
        d = APP / f"android/app/src/main/res/mipmap-{name}"
        save(Image.new("RGBA", (px, px), TILE_BEIGE), d / "ic_launcher_background.png")
        fg = on_canvas(book, px, 0.62)
        save(fg, d / "ic_launcher_foreground.png")
        # Monochrome = the silhouette, for Android 13+ themed icons: the system
        # tints it, so only the alpha matters. Taken from the artwork's darkness
        # rather than its alpha, which is opaque everywhere the book is.
        import numpy as np
        # Only the ink and the ribbon. A looser threshold swallows the tile
        # beige (sum 636) and its shading, and the layer comes out a solid
        # black blob — which is what the first attempt did.
        arr = np.asarray(fg.convert("RGB")).astype(int)
        r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
        alpha = np.asarray(fg.split()[3]).astype(int)
        ink = (arr.sum(axis=2) < 380) | ((r > 90) & (r - g > 55) & (r - b > 55))
        solid = (ink & (alpha > 40)).astype("uint8") * 255
        mono = Image.new("RGBA", fg.size, (0, 0, 0, 0))
        mono.paste((0, 0, 0, 255), (0, 0), Image.fromarray(solid, mode="L"))
        save(mono, d / "ic_launcher_monochrome.png")

    adaptive = APP / "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
    write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n', adaptive)

    # macOS — shown as-is in the dock, so it keeps the artwork's own corners.
    for px in (16, 32, 64, 128, 256, 512, 1024):
        save(scaled(master, px),
             APP / f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{px}.png")

    # Windows — a single multi-size .ico.
    ico_path = APP / "windows/runner/resources/app_icon.ico"
    ico_path.parent.mkdir(parents=True, exist_ok=True)
    scaled(master, 256).save(
        ico_path, sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
    print("wrote", ico_path.relative_to(ROOT))

    # In-app — the About dialog icon, bundled as a Flutter asset. Linux also
    # loads this same asset at runtime for the window/taskbar icon
    # (see linux/runner/my_application.cc).
    save(scaled(master, 512), APP / "assets/logo.png")

    # Linux icon theme — named after the application ID so GTK can resolve it as
    # a themed window icon (see linux/install-dev.sh).
    app_id = "com.avladescu.vellum"
    theme = APP / "linux/packaging/icons/hicolor"
    write_text(svg_wrapper(master), theme / f"scalable/apps/{app_id}.svg")
    for px in (48, 64, 128, 256):
        save(scaled(master, px), theme / f"{px}x{px}/apps/{app_id}.png")

    # Server console/public — the favicon and the header mark are the same tile.
    # An earlier version cut the book out for the header, but the "book alone"
    # is a crop of the tile and still carries its beige, so it was the same
    # image with extra steps. 128px for the favicon: it is never shown above
    # 64, and the embedded PNG is the whole file size.
    write_text(svg_wrapper(master, 128), ROOT / "server/web/favicon.svg")
    write_text(svg_wrapper(master, 256), ROOT / "server/web/logo.svg")


if __name__ == "__main__":
    main()
