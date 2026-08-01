#!/usr/bin/env python3
"""Turn the original icon artwork into ``design/logo-source.png``.

The artwork arrives as a tile floating on a white backdrop with a drop shadow.
An app icon has to be the tile alone, square, with transparent corners — a
launcher, a dock and a title bar all round or mask the corners themselves, and
baked-in white ones show up as bright wedges against a dark theme.

Separated from ``generate_icons.py`` because it runs once per new artwork, while
that runs whenever a slot changes. Run:

    python3 design/prepare_source.py ~/Downloads/whatever.png

Requires Pillow and NumPy.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "design" / "logo-source.png"

#: The tile's corner radius as a fraction of its side, measured off the artwork.
CORNER_RADIUS = 0.177

#: Side of the master. Everything else is downscaled from it; the largest
#: consumer is the 1024px macOS icon.
MASTER = 1024


def tile_bounds(rgb: np.ndarray) -> tuple[int, int, int, int]:
    """The tile's bounding box.

    Masks on *saturation* rather than brightness: the backdrop is near-white and
    the drop shadow is grey, both with almost no saturation, while the tile is
    strongly warm. A brightness threshold catches the shadow too and stretches
    the box past the tile's bottom-right.

    Each row and column votes, and the median wins, so a stray pixel cannot move
    an edge.
    """
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    mask = (sat > 25) | (rgb.sum(axis=2) < 400)  # warm tile, or dark ink
    rows = [np.where(mask[y])[0] for y in range(mask.shape[0])]
    cols = [np.where(mask[:, x])[0] for x in range(mask.shape[1])]
    keep = 200  # ignore rows/columns that barely clip the artwork
    left = int(np.median([r.min() for r in rows if r.size > keep]))
    right = int(np.median([r.max() for r in rows if r.size > keep]))
    top = int(np.median([c.min() for c in cols if c.size > keep]))
    bottom = int(np.median([c.max() for c in cols if c.size > keep]))
    return left, top, right, bottom


def main():
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} <artwork.png>")
    src = Image.open(sys.argv[1]).convert("RGB")
    left, top, right, bottom = tile_bounds(np.asarray(src).astype(int))
    side = min(right - left + 1, bottom - top + 1)
    print(f"tile found at ({left}, {top}), {side}px square")

    tile = src.crop((left, top, left + side, top + side)).resize(
        (MASTER, MASTER), Image.LANCZOS).convert("RGBA")

    # Replace the backdrop showing through the rounded corners with
    # transparency. Antialiased by masking at 4x and scaling down, or the
    # corners come out with visible stair-steps at small sizes.
    scale = 4
    mask = Image.new("L", (MASTER * scale, MASTER * scale), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, MASTER * scale - 1, MASTER * scale - 1],
        radius=int(MASTER * scale * CORNER_RADIUS), fill=255)
    mask = mask.resize((MASTER, MASTER), Image.LANCZOS)

    out = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    out.paste(tile, (0, 0), mask)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT, optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)} ({MASTER}x{MASTER})")
    print("now run: python3 design/generate_icons.py")


if __name__ == "__main__":
    main()
