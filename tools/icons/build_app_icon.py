#!/usr/bin/env python3
"""Generates the app icon: assets/app_icon/icon.svg -> PNG sizes (rasterised by Godot) -> icon.ico (Windows) + icon.icns (macOS).
Run: python3 tools/icons/build_app_icon.py   (needs `godot` on PATH)"""
import os, struct, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "app_icon")
SIZES = [16, 32, 48, 64, 128, 256, 512, 1024]

SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3b1708"/><stop offset="1" stop-color="#120604"/></linearGradient>
<radialGradient id="glow" cx="0.5" cy="0.62" r="0.55"><stop offset="0" stop-color="#ff7a1a" stop-opacity="0.75"/><stop offset="1" stop-color="#ff7a1a" stop-opacity="0"/></radialGradient>
<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffe9a8"/><stop offset="0.55" stop-color="#ffb84d"/><stop offset="1" stop-color="#c8741a"/></linearGradient>
<linearGradient id="fl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff3c4"/><stop offset="0.5" stop-color="#ff9a2a"/><stop offset="1" stop-color="#e03a08"/></linearGradient>
</defs>
<rect x="24" y="24" width="976" height="976" rx="210" fill="url(#bg)"/>
<rect x="24" y="24" width="976" height="976" rx="210" fill="url(#glow)"/>
<rect x="40" y="40" width="944" height="944" rx="196" fill="none" stroke="#ffb84d" stroke-opacity="0.55" stroke-width="10"/>
<path d="M512 150 L820 262 V540 C820 722 692 850 512 912 C332 850 204 722 204 540 V262 Z" fill="#1c0b06" stroke="url(#gold)" stroke-width="30" stroke-linejoin="round"/>
<path d="M512 205 L770 296 V536 C770 690 662 800 512 856 C362 800 254 690 254 536 V296 Z" fill="none" stroke="#ffb84d" stroke-opacity="0.35" stroke-width="8"/>
<path d="M512 262 C548 372 668 420 650 566 C642 668 580 724 512 724 C444 724 382 668 374 566 C368 492 412 450 440 380 C450 440 480 462 512 262 Z" fill="url(#fl)"/>
<path d="M512 470 C544 530 590 556 582 626 C578 668 548 690 512 690 C476 690 446 668 442 626 C436 574 490 540 512 470 Z" fill="#fff3c4" fill-opacity="0.9"/>
</svg>
"""


def main():
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, "icon.svg"), "w").write(SVG)
    # Rasterise through Godot (ThorVG), headless.
    script = os.path.join(ROOT, "tools", "icons", "render_app_icon.gd")
    subprocess.run(["godot", "--headless", "--path", ROOT, "--script", "res://tools/icons/render_app_icon.gd"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    png = {s: open(os.path.join(OUT, f"icon_{s}.png"), "rb").read() for s in SIZES}
    # ICO with PNG-compressed entries (Vista+): 16..256
    ico_sizes = [16, 32, 48, 64, 128, 256]
    header = struct.pack("<HHH", 0, 1, len(ico_sizes))
    entries, data, offset = b"", b"", 6 + 16 * len(ico_sizes)
    for s in ico_sizes:
        b = png[s]
        entries += struct.pack("<BBBBHHII", 0 if s >= 256 else s, 0 if s >= 256 else s, 0, 0, 1, 32, len(b), offset)
        data += b
        offset += len(b)
    open(os.path.join(OUT, "icon.ico"), "wb").write(header + entries + data)
    # ICNS with PNG payloads
    types = {16: b"icp4", 32: b"icp5", 64: b"icp6", 128: b"ic07", 256: b"ic08", 512: b"ic09", 1024: b"ic10"}
    body = b"".join(types[s] + struct.pack(">I", 8 + len(png[s])) + png[s] for s in types)
    open(os.path.join(OUT, "icon.icns"), "wb").write(b"icns" + struct.pack(">I", 8 + len(body)) + body)
    os.replace(os.path.join(OUT, "icon_1024.png"), os.path.join(OUT, "icon.png"))
    for s in SIZES:
        p = os.path.join(OUT, f"icon_{s}.png")
        if os.path.exists(p):
            os.remove(p)
    print("icon.svg, icon.png, icon.ico, icon.icns ->", OUT)


main()
