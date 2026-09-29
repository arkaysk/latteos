#!/usr/bin/env python3
"""Vykreslí logo LatteOS (šálka s parou) do PNG bez externých knižníc.
Použitie: make-logo.py <výstup.png> [veľkosť]   — farby z old/data/themes/latte (accent, fg-dim)."""
import math, struct, sys, zlib

out = sys.argv[1]
N = int(sys.argv[2]) if len(sys.argv) > 2 else 256
SS = 4                                   # supersampling pre hladké hrany
ACCENT = (0xD9, 0x91, 0x3B)              # šálka
STEAM = (0xCD, 0xBF, 0xAF)               # para

def shape(x, y):
    """x, y v súradniciach 0..256; vráti (farba, alfa) alebo None."""
    # para: tri vlnky
    for cx in (100, 128, 156):
        if 40 <= y <= 108:
            wx = cx + 7 * math.sin((y - 40) / 68 * 2 * math.pi + cx)
            if abs(x - wx) < 4.5:
                return STEAM, 0.85
    # telo šálky: lichobežník so zaoblenými spodnými rohmi
    if 122 <= y <= 206:
        t = (y - 122) / 84
        half = 70 - 14 * t
        if abs(x - 128) <= half:
            if y > 186:                   # zaoblenie spodku
                r = 20
                cxr = 128 + (half - r) * (1 if x > 128 else -1)
                if abs(x - 128) > half - r and math.hypot(x - cxr, y - 186) > r:
                    return None
            return ACCENT, 1.0
    # ucho
    d = math.hypot(x - 196, y - 158)
    if x > 190 and 14 <= d <= 26:
        return ACCENT, 1.0
    # tanierik
    if ((x - 128) / 96) ** 2 + ((y - 218) / 9) ** 2 <= 1:
        return ACCENT, 0.9
    return None

rows = []
for py in range(N):
    row = bytearray([0])
    for px in range(N):
        r = g = b = a = 0.0
        for sy in range(SS):
            for sx in range(SS):
                x = (px + (sx + 0.5) / SS) * 256 / N
                y = (py + (sy + 0.5) / SS) * 256 / N
                s = shape(x, y)
                if s:
                    (cr, cg, cb), ca = s
                    r += cr * ca; g += cg * ca; b += cb * ca; a += ca
        n = SS * SS
        if a:
            row += bytes((int(r / a), int(g / a), int(b / a), int(255 * a / n)))
        else:
            row += b"\0\0\0\0"
    rows.append(bytes(row))

def chunk(t, d):
    c = struct.pack(">I", len(d)) + t + d
    return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b"")
open(out, "wb").write(png)
