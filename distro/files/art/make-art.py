#!/usr/bin/env python3
"""Generate Dive's wallpaper and GRUB background as PNG, with no dependencies.

    make-art.py --wallpaper out.png [--grub out2.png]

The look: deep navy water, soft aqua/blue light pools, a few faint rays.
"""
import argparse, math, struct, zlib

def png(path, w, h, rows):
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    raw = b''.join(b'\x00' + r for r in rows)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b'IDAT', zlib.compress(raw, 6)))
        f.write(chunk(b'IEND', b''))

BLOBS = [  # x, y (0..1), radius (fraction of width), rgb, strength  (black + light blue)
    (0.68, 0.78, 0.55, (58, 160, 255), 0.42),
    (0.20, 0.30, 0.45, (40, 110, 200), 0.20),
    (0.85, 0.25, 0.35, (120, 190, 255), 0.12),
]
RAYS = [0.20, 0.39, 0.58, 0.77]

def render(w, h, scale=1):
    # render at reduced resolution, then upscale rows/pixels (it is a soft gradient anyway)
    sw, sh = max(1, w // scale), max(1, h // scale)
    rows = []
    for y in range(sh):
        t = y / (sh - 1)
        # base vertical gradient  #0C2A46 -> #07182B -> #040C16
        if t < .55:
            k = t / .55; base = (3 + (6 - 3) * k, 6 + (12 - 6) * k, 10 + (22 - 10) * k)
        else:
            k = (t - .55) / .45; base = (6 + (4 - 6) * k, 12 + (8 - 12) * k, 22 + (14 - 22) * k)
        row = bytearray()
        for x in range(sw):
            u = x / (sw - 1)
            r, g, b = base
            for bx, by, br, col, s in BLOBS:
                dx, dy = (u - bx), (t - by) * (h / w)
                d = math.sqrt(dx * dx + dy * dy) / (br * .6)
                if d < 1:
                    a = (1 - d) ** 2 * s
                    r += col[0] * a; g += col[1] * a; b += col[2] * a
            for rx in RAYS:
                # slanted ray: x position drifts right as y goes down
                left = rx + t * .11; width = .035 + t * .05
                if left <= u <= left + width:
                    a = .045 * (1 - t) * (1 - abs((u - left) / width - .5) * 2)
                    r += 120 * a; g += 190 * a; b += 255 * a
            row += bytes((min(255, int(r)), min(255, int(g)), min(255, int(b))))
        # upscale horizontally
        if scale > 1:
            full = bytearray()
            for i in range(0, len(row), 3):
                full += row[i:i + 3] * scale
            row = full[:w * 3] + row[-3:] * max(0, w - len(full) // 3)
        rows.append(bytes(row))
    out = []
    for r in rows:
        out.extend([r] * scale)
    return out[:h] + [rows[-1]] * max(0, h - len(out))

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--wallpaper'); ap.add_argument('--grub')
    a = ap.parse_args()
    if a.wallpaper:
        png(a.wallpaper, 2560, 1600, render(2560, 1600, scale=4))
    if a.grub:
        png(a.grub, 1920, 1080, render(1920, 1080, scale=4))
