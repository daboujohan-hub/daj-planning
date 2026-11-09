import math
import os
import struct
import sys
import zlib

# Icône DAJ Planning : une horloge avec 5 points colorés (une couleur par matière).
DOTS = ["#3B82F6", "#EF4444", "#22C55E", "#F97316", "#A855F7"]


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def render(size, bg, ring_r, dot_r):
    c = size / 2.0
    ring_w = size * 0.028
    hand_w = size * 0.030
    dots = []
    for i, col in enumerate(DOTS):
        ang = math.radians(-90 + i * 72)
        dots.append((c + ring_r * math.cos(ang), c + ring_r * math.sin(ang), hexrgb(col)))
    # aiguilles : minutes vers 12h, heures vers 4h
    h1 = (c, c - ring_r * 0.66)
    h2 = (c + ring_r * 0.40 * math.cos(math.radians(-30)),
          c + ring_r * 0.40 * math.sin(math.radians(-30)) * -1)
    h2 = (c + ring_r * 0.42 * math.cos(math.radians(30)),
          c + ring_r * 0.42 * math.sin(math.radians(30)))
    white = (243, 244, 246)
    gray = (156, 163, 175)
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        py = y + 0.5
        for x in range(size):
            px = x + 0.5
            if bg is None:
                r = g = b = 0.0
                a = 0.0
            else:
                r, g, b = bg
                a = 1.0
            layers = []
            d = abs(math.hypot(px - c, py - c) - ring_r) - ring_w / 2
            layers.append((d, gray))
            for (dx_, dy_, col) in dots:
                layers.append((math.hypot(px - dx_, py - dy_) - dot_r, col))
            layers.append((seg_dist(px, py, c, c, h1[0], h1[1]) - hand_w / 2, white))
            layers.append((seg_dist(px, py, c, c, h2[0], h2[1]) - hand_w / 2, white))
            layers.append((math.hypot(px - c, py - c) - hand_w * 0.9, white))
            for d, col in layers:
                cov = 0.5 - d
                if cov <= 0:
                    continue
                if cov > 1:
                    cov = 1.0
                na = cov + a * (1 - cov)
                r = (col[0] * cov + r * a * (1 - cov)) / na
                g = (col[1] * cov + g * a * (1 - cov)) / na
                b = (col[2] * cov + b * a * (1 - cov)) / na
                a = na
            raw += bytes((int(r + .5), int(g + .5), int(b + .5), int(a * 255 + .5)))
    return bytes(raw)


def write_png(path, size, raw):
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


out = sys.argv[1] if len(sys.argv) > 1 else "assets"
os.makedirs(out, exist_ok=True)
S = 512
write_png(os.path.join(out, "icon.png"), S, render(S, hexrgb("#0B0F14"), S * 0.30, S * 0.065))
write_png(os.path.join(out, "icon_fg.png"), S, render(S, None, S * 0.22, S * 0.050))
print("icônes créées dans", out)
