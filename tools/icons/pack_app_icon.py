"""Packs the icon_<size>.png files written by tools/icons/build_app_icon.gd into icon.ico (Windows) and icon.icns (macOS).
Both formats can hold PNG data as is.  Usage: python tools/icons/pack_app_icon.py <dir with icon_N.png> <out_dir>"""
import struct
import sys
from pathlib import Path

src, out = Path(sys.argv[1]), Path(sys.argv[2])
png = {n: (src / f"icon_{n}.png").read_bytes() for n in (16, 32, 48, 64, 128, 256, 512, 1024)}

ico_sizes = (16, 32, 48, 64, 128, 256)
head = struct.pack("<HHH", 0, 1, len(ico_sizes))
offset = 6 + 16 * len(ico_sizes)
entries, blobs = b"", b""
for n in ico_sizes:
    data = png[n]
    entries += struct.pack("<BBBBHHII", n % 256, n % 256, 0, 0, 1, 32, len(data), offset)
    blobs += data
    offset += len(data)
(out / "icon.ico").write_bytes(head + entries + blobs)

chunks = b"".join(tag + struct.pack(">I", len(png[n]) + 8) + png[n]
                  for tag, n in ((b"ic07", 128), (b"ic08", 256), (b"ic09", 512), (b"ic10", 1024)))
(out / "icon.icns").write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)
