"""Generates the flight map's textures in textures/ (32-bit uncompressed TGA, power-of-two sizes).

Run from the repo root:  python tools/make_textures.py

Everything is drawn white (or white with a dark edge), so the game tints it with SetVertexColor.
Masks keep colour equal to alpha, so they work whichever channel the client reads.

  MapMask.tga         the original soft edge (fades over the outer quarter); kept for reference
  MapTerrainMask.tga  terrain: a smaller solid centre and a shorter, steeper fade than MapMask
  MapBacking.tga      the dark backing's mask: a soft rounded falloff that reaches nothing well
                      inside its edges
  MapGlowLine.tga     route glow: white along the middle row, fading to clear across the width
                      (a Line stretches a texture's width along its length)
  MapGlow.tga         round soft glow behind the destination and the marker
  MapArrow.tga        the flight marker: a filled arrow pointing right, white with a dark edge
"""
import math
import os
import struct

OUT = "textures"


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def write_tga(name, w, h, pixel):
    """pixel(x, y) -> (r, g, b, a) floats 0..1, with y = 0 at the top."""
    data = bytearray()
    # Uncompressed TGA rows run bottom to top.
    for row in range(h - 1, -1, -1):
        for x in range(w):
            r, g, b, a = pixel(x, row)
            data += bytes((round(b * 255), round(g * 255), round(r * 255), round(a * 255)))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8)
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(header + data)


def mask(value):
    return (value, value, value, value)


def edge_mask(size, margin, fade):
    """Clear for `margin` px from each edge, then a smoothstep to solid over `fade` px. Each axis
    separately, multiplied, so the corners round off."""
    def pixel(x, y):
        ax = smoothstep((min(x + 0.5, size - x - 0.5) - margin) / fade)
        ay = smoothstep((min(y + 0.5, size - y - 0.5) - margin) / fade)
        return mask(ax * ay)
    return pixel


def map_mask():
    # The original MapMask.tga: written straight from alpha bytes, as it was first made.
    size, feather = 128, 32.0
    data = bytearray()
    for y in range(size):
        for x in range(size):
            ax = smoothstep(min(x + 0.5, size - x - 0.5) / feather)
            ay = smoothstep(min(y + 0.5, size - y - 0.5) / feather)
            a = int(round(255 * ax * ay))
            data += bytes((a, a, a, a))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8)
    with open(os.path.join(OUT, "MapMask.tga"), "wb") as f:
        f.write(header + data)


def backing(size=128, inner=0.5, outer=0.9):
    """Solid inside `inner`, nothing beyond `outer`, as a fraction of the half-size, measured as a
    superellipse (power 4) so it covers the box's corners better than a circle."""
    half = size / 2

    def pixel(x, y):
        nx, ny = abs(x + 0.5 - half) / half, abs(y + 0.5 - half) / half
        r = (nx ** 4 + ny ** 4) ** 0.25
        return mask(1 - smoothstep((r - inner) / (outer - inner)))
    return pixel


def glow_line(size=32):
    half = size / 2

    def pixel(x, y):
        v = abs(y + 0.5 - half) / half
        a = smoothstep(1 - v) ** 1.5
        return (1, 1, 1, a)
    return pixel


def glow(size=64):
    half = size / 2

    def pixel(x, y):
        r = math.hypot(x + 0.5 - half, y + 0.5 - half) / half
        a = smoothstep(1 - r) ** 2
        return (1, 1, 1, a)
    return pixel


def arrow(size=64, edge=3.0, dark=0.08, samples=4):
    # A notched arrow pointing right (+x), symmetric top to bottom.
    poly = [(58, 32), (8, 10), (21, 32), (8, 54)]

    def inside(px, py):
        hit = False
        for i in range(len(poly)):
            (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % len(poly)]
            if (y1 > py) != (y2 > py) and px < x1 + (py - y1) * (x2 - x1) / (y2 - y1):
                hit = not hit
        return hit

    def to_edge(px, py):
        best = float("inf")
        for i in range(len(poly)):
            (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % len(poly)]
            vx, vy = x2 - x1, y2 - y1
            t = max(0.0, min(1.0, ((px - x1) * vx + (py - y1) * vy) / (vx * vx + vy * vy)))
            best = min(best, math.hypot(px - (x1 + vx * t), py - (y1 + vy * t)))
        return best

    def pixel(x, y):
        cover, colour = 0, 0.0
        for i in range(samples):
            for j in range(samples):
                px, py = x + (i + 0.5) / samples, y + (j + 0.5) / samples
                if inside(px, py):
                    cover += 1
                    colour += 1.0 if to_edge(px, py) > edge else dark
        n = samples * samples
        c = colour / cover if cover else 0.0
        return (c, c, c, cover / n)
    return pixel


def main():
    os.makedirs(OUT, exist_ok=True)
    map_mask()
    write_tga("MapTerrainMask.tga", 128, 128, edge_mask(128, margin=24, fade=16))
    write_tga("MapBacking.tga", 128, 128, backing())
    write_tga("MapGlowLine.tga", 32, 32, glow_line())
    write_tga("MapGlow.tga", 64, 64, glow())
    write_tga("MapArrow.tga", 64, 64, arrow())


if __name__ == "__main__":
    main()
