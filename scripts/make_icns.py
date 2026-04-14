#!/usr/bin/env python3
"""Build a modern .icns file from a macOS .iconset directory."""

from __future__ import annotations

import struct
import sys
from pathlib import Path


PNG_ENTRIES = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
]


def chunk(icon_type: str, data: bytes) -> bytes:
    return icon_type.encode("ascii") + struct.pack(">I", len(data) + 8) + data


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: make_icns.py ICONSET_DIR OUTPUT.icns", file=sys.stderr)
        return 2

    iconset_dir = Path(sys.argv[1])
    output_file = Path(sys.argv[2])

    chunks: list[bytes] = []
    for icon_type, filename in PNG_ENTRIES:
        source = iconset_dir / filename
        if not source.is_file():
            print(f"missing required icon file: {source}", file=sys.stderr)
            return 1
        chunks.append(chunk(icon_type, source.read_bytes()))

    body = b"".join(chunks)
    output_file.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
