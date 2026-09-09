#!/usr/bin/env python3
"""Draw the app icon by iterating the attractor.

    ./make-icon.py [Attractor.xcassets]

The icon is the same de Jong map the app draws, at 1024x1024 and four million
points, accumulated into a density buffer and log-scaled -- which is what makes
the fine structure visible at all: a linear ramp buries everything but the
brightest folds. Stdlib only, so this needs nothing installed; zlib and struct
are enough to write a PNG.

actool does the rest at build time. Do not put PNGs in the bundle by hand: iOS
wants a family of sizes and a compiled Assets.car, and asdf-ios-app refuses
anything but a catalogue for exactly that reason.
"""

import json, math, os, struct, sys, zlib

SIZE = 1024
ITERATIONS = 4_000_000
A, B, C, D = 1.4, -2.3, 2.4, -2.1
TINT = (0.35, 0.85, 1.0)          # the cold blue-white the app draws with


def density():
    acc = [0.0] * (SIZE * SIZE)
    x = y = 0.1
    for _ in range(ITERATIONS):
        x, y = (math.sin(A * y) - math.cos(B * x),
                math.sin(C * x) - math.cos(D * y))
        # The map's range is [-2,2] in both axes; 4.2 leaves a little margin.
        px = int((x / 4.2 + 0.5) * SIZE)
        py = int((y / 4.2 + 0.5) * SIZE)
        if 0 <= px < SIZE and 0 <= py < SIZE:
            acc[py * SIZE + px] += 1.0
    return acc


def png_bytes(acc):
    peak = max(acc)
    rows = bytearray()
    for row in range(SIZE):
        rows.append(0)                      # PNG filter type 0 for this row
        for col in range(SIZE):
            v = acc[row * SIZE + col]
            t = math.log1p(v) / math.log1p(peak) if v else 0.0
            t = min(1.0, t * 1.35)
            rows += bytes(int(255 * t * channel) for channel in TINT)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data)))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
            + chunk(b"IEND", b""))


def main():
    catalogue = sys.argv[1] if len(sys.argv) > 1 else "Attractor.xcassets"
    iconset = os.path.join(catalogue, "AppIcon.appiconset")
    os.makedirs(iconset, exist_ok=True)

    with open(os.path.join(iconset, "icon.png"), "wb") as out:
        out.write(png_bytes(density()))

    info = {"author": "asdf-ios-app", "version": 1}
    with open(os.path.join(catalogue, "Contents.json"), "w") as out:
        json.dump({"info": info}, out, indent=2)
    with open(os.path.join(iconset, "Contents.json"), "w") as out:
        json.dump({"images": [{"filename": "icon.png", "idiom": "universal",
                               "platform": "ios", "size": "1024x1024"}],
                   "info": info}, out, indent=2)
    print("wrote", iconset)


if __name__ == "__main__":
    main()
