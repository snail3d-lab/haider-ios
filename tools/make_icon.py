#!/usr/bin/env python3
"""Draw the Haider app icon.

The icon has to say the whole product in one glance, so it uses the product's own
material rather than an illustration: a field of speckle with one block of it
resolving into an "H". That is literally what the app does — the shape exists only
where the motion differs.

Rendered at 1024 for the modern single-size asset catalog.

    python3 tools/make_icon.py
"""

from __future__ import annotations

import os
import struct
import zlib

W = H = 1024
SHELL = (11, 14, 12)      # #0B0E0C snail shell
NEUTRINO = (242, 245, 238)  # #F2F5EE
LIME = (163, 230, 53)     # #A3E635

# An icon is not a still of the product — it is a mark. So the letter is SOLID
# and the speckle around it is faint texture, at low contrast. Filling the glyph
# at the field's own 50% density (the first attempt) makes it melt into the noise
# and it stops reading at 40 px, which is what an icon has to survive.
CELL = 16
COLS = W // CELL
SPECKLE_CONTRAST = 0.10   # how far a speckle block lifts off the shell


def _mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def h_mask(cols: int, rows: int) -> list[bool]:
    """An 'H' as a boolean mask, centred, drawn in cells."""
    m = [False] * (cols * rows)
    stroke = max(3, cols // 8)          # stem width
    bar = max(3, rows // 7)             # crossbar height
    left = cols // 2 - cols // 4
    right = cols // 2 + cols // 4
    top = rows // 2 - rows // 4
    bottom = rows // 2 + rows // 4
    for y in range(top, bottom):
        for x in range(left, left + stroke):
            m[y * cols + x] = True
        for x in range(right - stroke, right):
            m[y * cols + x] = True
    cross_top = rows // 2 - bar // 2
    for y in range(cross_top, cross_top + bar):
        for x in range(left, right):
            m[y * cols + x] = True
    return m


def build() -> bytes:
    rows = H // CELL
    mask = h_mask(COLS, rows)

    # Deterministic speckle, faint: texture, not content.
    state = 0x5EEDBEEF

    def rnd() -> float:
        nonlocal state
        state = (state * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
        return ((state >> 33) & 0xFFFFFF) / float(0xFFFFFF)

    speck = [[rnd() < 0.42 for _ in range(COLS)] for _ in range(rows)]
    lift = [[rnd() for _ in range(COLS)] for _ in range(rows)]
    base = _mix(SHELL, (0, 0, 0), 0.25)

    px = bytearray()
    for y in range(H):
        cy = y // CELL
        row = bytearray()
        for x in range(W):
            cx = x // CELL
            if mask[cy * COLS + cx]:
                # Solid lime. A two-pixel seam between cells keeps the dot
                # language without punching holes in the letterform.
                on_seam = (x % CELL < 2) or (y % CELL < 2)
                row += b"\x08\x0c\x08" if on_seam else bytes(LIME)
            elif speck[cy][cx]:
                t = SPECKLE_CONTRAST * (0.35 + 0.65 * lift[cy][cx])
                row += bytes(_mix(base, NEUTRINO, t))
            else:
                row += bytes(base)
        px += b"\x00" + bytes(row)
    return bytes(px)


def write_png(path: str, raw: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)  # 8-bit RGB
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", header)
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(png)


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(here, "..", "Haider", "Assets.xcassets",
                           "AppIcon.appiconset")
    os.makedirs(out_dir, exist_ok=True)
    write_png(os.path.join(out_dir, "icon-1024.png"), build())

    with open(os.path.join(out_dir, "Contents.json"), "w") as fh:
        fh.write('''{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}\n''')
    print(f"wrote {out_dir}/icon-1024.png")


if __name__ == "__main__":
    main()