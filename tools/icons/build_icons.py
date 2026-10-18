#!/usr/bin/env python3
"""Draws the whole icon set as SVG (128x128) into assets/icons/. Run: python3 tools/icons/build_icons.py
Ability/effect icons are rounded tiles tinted by school; UI icons are bare white glyphs."""
import math, os, sys

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "icons")
SCHOOLS = {  # (dark, mid, light border)
    "fire": ("#3a0c04", "#c9421a", "#ffb060"),
    "frost": ("#06203a", "#2a86c8", "#a8e8ff"),
    "arcane": ("#1c0a3a", "#7a3cc8", "#d6a8ff"),
    "physical": ("#161a22", "#56627a", "#d0d8e8"),
    "holy": ("#3a2a04", "#c8962a", "#fff0a8"),
    "shadow": ("#0c0818", "#4a2a7a", "#b890e8"),
    "nature": ("#06260c", "#2c9a44", "#a8ffb8"),
    "blood": ("#2a0408", "#b01830", "#ff8a98"),
}
CSS = ".f{fill:#fff6e0;stroke:#120806;stroke-width:3.5;stroke-linejoin:round}.d{fill:#120806}.a{fill:#ffd070;stroke:#120806;stroke-width:3;stroke-linejoin:round}.s{fill:none;stroke:#fff6e0;stroke-width:8;stroke-linecap:round;stroke-linejoin:round}.o{fill:none;stroke:#120806;stroke-width:13;stroke-linecap:round;stroke-linejoin:round}"


def poly(pts, cls="f", rot=0, cx=64, cy=64):
    p = " ".join(f"{x},{y}" for x, y in pts)
    return f'<polygon class="{cls}" points="{p}" transform="rotate({rot} {cx} {cy})"/>'


def circ(x, y, r, cls="f"):
    return f'<circle class="{cls}" cx="{x}" cy="{y}" r="{r}"/>'


def path(d, cls="f", rot=0, cx=64, cy=64):
    return f'<path class="{cls}" d="{d}" transform="rotate({rot} {cx} {cy})"/>'


def line_s(d):  # outlined stroke path (dark under, light over)
    return f'<path class="o" d="{d}"/><path class="s" d="{d}"/>'


def star(cx, cy, r1, r2, n):
    pts = []
    for i in range(n * 2):
        a = math.pi * i / n - math.pi / 2
        r = r1 if i % 2 == 0 else r2
        pts.append((round(cx + r * math.cos(a), 1), round(cy + r * math.sin(a), 1)))
    return pts


FLAME = "M64 12 C72 34 98 44 94 76 C92 98 78 112 64 112 C48 112 34 98 34 76 C34 60 44 52 50 38 C52 50 58 54 64 12 Z"
G = {}
G["flame"] = path(FLAME) + path("M64 62 C70 74 82 80 80 94 C78 104 70 108 64 108 C56 108 48 104 48 94 C48 84 60 78 64 62 Z", "a")
G["shadowbolt"] = path("M10 118 C22 96 34 78 52 62 C46 78 40 94 36 118 Z", "f") + path("M6 80 C20 74 34 70 52 64 C42 78 28 86 14 92 Z", "f") + path("M44 116 C52 100 62 88 72 80 C70 94 66 106 62 118 Z", "f") + circ(78, 50, 38) + path("M78 20 C100 22 112 44 102 62 C94 76 74 76 68 62 C64 52 72 42 82 44 C88 46 90 54 84 58 C94 56 94 36 78 32 C70 30 62 36 60 44 C58 30 66 22 78 20 Z", "d") + circ(64, 58, 5, "a")
G["meteor"] = circ(50, 80, 28) + circ(40, 72, 6, "d") + circ(58, 92, 5, "d") + poly([(66, 58), (112, 14), (100, 56), (116, 44), (86, 96)], "a")
G["snowflake"] = "".join(line_s(f"M64 64 L{64+46*math.cos(math.radians(a)):.1f} {64+46*math.sin(math.radians(a)):.1f}") for a in range(0, 360, 60)) + "".join(
    line_s(f"M{64+30*math.cos(math.radians(a)):.1f} {64+30*math.sin(math.radians(a)):.1f} L{64+30*math.cos(math.radians(a))+12*math.cos(math.radians(a+50)):.1f} {64+30*math.sin(math.radians(a))+12*math.sin(math.radians(a+50)):.1f} M{64+30*math.cos(math.radians(a)):.1f} {64+30*math.sin(math.radians(a)):.1f} L{64+30*math.cos(math.radians(a))+12*math.cos(math.radians(a-50)):.1f} {64+30*math.sin(math.radians(a))+12*math.sin(math.radians(a-50)):.1f}") for a in range(0, 360, 60))
G["sheep"] = circ(48, 62, 20) + circ(66, 54, 22) + circ(84, 64, 18) + circ(60, 76, 20) + circ(96, 74, 14, "d") + circ(92, 70, 3) + poly([(44, 86), (50, 86), (50, 108), (44, 108)], "d") + poly([(74, 86), (80, 86), (80, 108), (74, 108)], "d")
G["blink"] = poly(star(80, 48, 30, 9, 4)) + line_s("M16 100 L52 72") + line_s("M10 80 L36 62") + poly(star(36, 100, 12, 4, 4), "a")
G["counter"] = f'<circle class="o" cx="64" cy="64" r="44" fill="none"/><circle class="s" cx="64" cy="64" r="44"/>' + path("M50 96 V62 C50 56 60 56 60 62 V40 C60 34 70 34 70 40 V62 V46 C70 40 80 40 80 46 V70 C80 88 74 98 62 98 Z") + line_s("M26 26 L102 102")
G["arrow"] = line_s("M20 108 L96 32") + poly([(104, 24), (104, 62), (84, 44), (66, 24)], "f", 0) + poly([(18, 90), (38, 110), (14, 114)], "a")
G["target"] = '<circle class="o" cx="64" cy="64" r="40" fill="none"/><circle class="s" cx="64" cy="64" r="40"/><circle class="s" cx="64" cy="64" r="18"/>' + line_s("M64 10 V34 M64 94 V118 M10 64 H34 M94 64 H118") + circ(64, 64, 7, "a")
G["snare"] = '<circle class="o" cx="64" cy="64" r="34" fill="none"/><circle class="s" cx="64" cy="64" r="34"/>' + "".join(poly([(64 - 8, 20), (64 + 8, 20), (64, 46)], "f", a) for a in range(0, 360, 60)) + circ(64, 64, 9, "a")
G["spiral"] = line_s("M64 64 m0 0 a6 6 0 1 1 12 0 a14 14 0 1 1 -28 0 a22 22 0 1 1 44 0 a30 30 0 1 1 -60 0 a38 38 0 0 1 76 0") + poly([(100, 80), (116, 62), (116, 98)], "a")
G["disengage"] = path("M28 86 C40 56 70 44 104 52 L96 36 L118 56 L94 74 L100 62 C76 58 54 66 44 90 Z") + line_s("M18 104 L48 104 M8 92 L34 92")
G["silence"] = '<circle class="o" cx="64" cy="64" r="42" fill="none"/><circle class="s" cx="64" cy="64" r="42"/>' + path("M38 70 C50 86 78 86 90 70 C78 62 50 62 38 70 Z", "f") + line_s("M24 24 L104 104")
G["volley"] = "".join(line_s(f"M64 112 L{64+80*math.sin(math.radians(a)):.1f} {112-80*math.cos(math.radians(a)):.1f}") + poly([(0, 0), (14, 0), (7, -20)], "f", a, 64, 112).replace('transform="rotate(%d 64 112)"' % a, 'transform="translate(%.1f %.1f) rotate(%d)"' % (64 + 78 * math.sin(math.radians(a)) - 7, 112 - 78 * math.cos(math.radians(a)), a)) for a in (-32, 0, 32))
G["sword"] = poly([(100, 14), (112, 26), (50, 88), (40, 78)], "f") + poly([(34, 70), (56, 92), (44, 100), (24, 80)], "a") + poly([(30, 90), (38, 98), (20, 116), (12, 108)], "f")
G["mortal"] = poly([(86, 12), (98, 24), (44, 78), (34, 68)], "f") + poly([(28, 62), (50, 84), (38, 92), (18, 72)], "a") + path("M90 70 C100 88 112 98 104 110 C98 118 82 118 78 108 C74 98 84 88 90 70 Z", "f")
G["charge"] = path("M20 28 C14 52 26 66 40 70 L40 100 L88 100 L88 70 C102 66 114 52 108 28 C100 50 88 52 80 50 L48 50 C40 52 28 50 20 28 Z") + circ(54, 78, 5, "d") + circ(74, 78, 5, "d")
G["hamstring"] = path("M44 14 H78 V70 L104 84 C112 90 112 104 100 106 H46 C40 106 36 100 38 94 L44 70 Z") + poly([(30, 30), (58, 54), (46, 58), (74, 90), (22, 56), (40, 52)], "a") 
G["shieldwall"] = path("M64 12 L108 28 V62 C108 88 88 108 64 118 C40 108 20 88 20 62 V28 Z") + path("M64 28 L94 38 V62 C94 80 80 94 64 102 Z", "a") + line_s("M64 28 V102")
G["fist"] = path("M30 56 C30 40 46 34 60 38 C64 28 82 28 86 38 C98 34 108 44 104 58 L104 78 C104 96 88 108 68 108 H58 C42 108 30 96 30 78 Z") + line_s("M48 62 V80 M64 58 V80 M80 62 V80")
G["blades"] = '<circle class="o" cx="64" cy="64" r="22" fill="none"/>' + "".join(poly([(64, 8), (78, 38), (64, 30)], "f", a) for a in range(0, 360, 90)) + circ(64, 64, 14, "a") + '<circle class="s" cx="64" cy="64" r="40" stroke-dasharray="18 14"/>'
G["sun"] = "".join(poly([(58, 8), (70, 8), (64, 30)], "a", a) for a in range(0, 360, 45)) + circ(64, 64, 26) + circ(64, 64, 14, "a")
G["plus"] = poly([(48, 14), (80, 14), (80, 48), (114, 48), (114, 80), (80, 80), (80, 114), (48, 114), (48, 80), (14, 80), (14, 48), (48, 48)]) + poly([(56, 24), (72, 24), (72, 56), (104, 56), (104, 72), (72, 72), (72, 104), (56, 104), (56, 72), (24, 72), (24, 56), (56, 56)], "a")
G["bubble"] = '<circle class="o" cx="64" cy="66" r="42" fill="none"/><circle class="s" cx="64" cy="66" r="42"/>' + path("M40 56 C44 40 56 32 70 32", "s") .replace('class="s"', 'class="s" style="stroke-width:6"') + circ(88, 90, 5, "a") + poly([(64, 46), (84, 54), (84, 72), (64, 90), (44, 72), (44, 54)], "a")
G["scream"] = '<circle class="f" cx="48" cy="64" r="26"/>' + path("M36 52 L44 56 M60 56 L68 52", "o") + '<ellipse class="d" cx="48" cy="74" rx="9" ry="12"/>' + line_s("M84 40 C100 52 100 76 84 88 M96 28 C120 48 120 80 96 100")
G["leaf"] = path("M24 104 C16 56 52 18 108 20 C110 74 78 112 30 108 Z") + line_s("M30 104 C50 80 70 58 96 36") + circ(100, 28, 5, "a")
G["dove"] = path("M16 70 C32 54 54 56 66 66 C72 42 96 28 116 36 C100 40 90 54 90 66 C100 62 108 62 116 66 C104 72 94 80 86 94 C78 106 62 110 46 100 C54 94 62 90 66 82 C50 90 28 86 16 70 Z") + circ(100, 42, 4, "d")
G["note"] = '<circle class="s" cx="64" cy="64" r="48" stroke-dasharray="10 10"/>' + path("M52 92 V36 L88 28 V84", "s") + '<ellipse class="f" cx="44" cy="94" rx="14" ry="11"/><ellipse class="f" cx="80" cy="86" rx="14" ry="11"/>'
G["dagger"] = poly([(100, 12), (112, 24), (56, 78), (46, 68)], "f") + poly([(36, 64), (62, 90), (50, 100), (26, 76)], "a") + poly([(30, 90), (38, 98), (22, 118), (14, 110)], "f")
G["skull"] = path("M64 12 C38 12 24 30 24 50 C24 64 30 72 38 78 V98 H90 V78 C98 72 104 64 104 50 C104 30 90 12 64 12 Z") + circ(46, 56, 11, "d") + circ(82, 56, 11, "d") + poly([(64, 66), (56, 82), (72, 82)], "d") + line_s("M50 98 V110 M64 98 V110 M78 98 V110")
G["claw"] = line_s("M30 20 C44 50 54 80 52 112") + line_s("M56 14 C74 46 82 80 78 116") + line_s("M82 22 C100 50 106 84 102 112") + poly([(86, 20), (110, 14), (98, 36)], "a")
G["burst"] = poly(star(64, 64, 52, 22, 8)) + circ(64, 64, 14, "a")
G["eye"] = path("M8 64 C28 30 100 30 120 64 C100 98 28 98 8 64 Z") + circ(64, 64, 22, "a") + circ(64, 64, 10, "d") + line_s("M20 112 L108 16")
G["ghost"] = path("M64 12 C38 12 24 32 24 56 V112 L40 100 L52 112 L64 100 L76 112 L88 100 L104 112 V56 C104 32 90 12 64 12 Z") + '<ellipse class="d" cx="48" cy="54" rx="8" ry="11"/><ellipse class="d" cx="80" cy="54" rx="8" ry="11"/><ellipse class="d" cx="64" cy="78" rx="7" ry="9"/>'
G["boot"] = path("M40 12 H76 V64 L108 82 C116 88 114 104 102 106 H34 C26 106 22 98 26 90 L40 64 Z") + line_s("M10 40 H30 M4 60 H26 M12 80 H30")
G["stars"] = poly(star(40, 46, 22, 9, 5)) + poly(star(86, 36, 16, 6, 5), "a") + poly(star(76, 88, 22, 9, 5)) + poly(star(30, 96, 12, 5, 5), "a")
G["roots"] = line_s("M64 112 C54 88 74 72 64 52 C58 40 70 28 64 14") + line_s("M64 96 C42 90 30 72 22 56") + line_s("M64 76 C86 72 98 58 108 40") + line_s("M64 112 C40 112 24 100 14 92")
G["drop"] = path("M64 10 C80 40 100 56 100 78 C100 98 84 112 64 112 C44 112 28 98 28 78 C28 56 48 40 64 10 Z") + path("M48 80 C50 92 60 98 70 96", "s").replace('class="s"', 'class="s" style="stroke-width:6"')
G["haste"] = G["boot"] + poly([(70, 20), (118, 20), (104, 36), (118, 52), (80, 52)], "a")
G["storm"] = '<circle class="s" cx="64" cy="64" r="44" stroke-dasharray="26 14"/>' + G["blades"].split("</path>")[0][:0] + poly([(60, 12), (72, 12), (66, 40)], "a") + poly([(116, 58), (116, 70), (88, 64)], "a") + poly([(68, 116), (56, 116), (62, 88)], "a") + poly([(12, 70), (12, 58), (40, 64)], "a") + circ(64, 64, 16)
G["crown"] = poly([(16, 40), (40, 66), (64, 24), (88, 66), (112, 40), (104, 98), (24, 98)]) + poly([(30, 104), (98, 104), (98, 116), (30, 116)], "a")
G["hat"] = poly([(64, 8), (88, 76), (40, 76)]) + '<ellipse class="f" cx="64" cy="84" rx="50" ry="12"/>' + poly([(46, 66), (82, 66), (84, 74), (44, 74)], "a")
G["bow"] = line_s("M42 14 C100 40 100 88 42 114") + line_s("M42 14 L42 114") + line_s("M22 64 L96 64") + poly([(104, 64), (84, 54), (84, 74)], "f")
G["helm"] = path("M22 64 C22 34 40 18 64 18 C88 18 106 34 106 64 V104 H80 V84 H48 V104 H22 Z") + poly([(36, 56), (92, 56), (92, 70), (36, 70)], "d") + poly([(8, 40), (28, 28), (24, 52)], "a") + poly([(120, 40), (100, 28), (104, 52)], "a")
G["halo"] = '<ellipse class="s" cx="64" cy="26" rx="34" ry="12"/>' + circ(64, 62, 22) + path("M24 112 C24 84 44 76 64 76 C84 76 104 84 104 112 Z")
G["mask"] = path("M20 36 C44 24 84 24 108 36 C112 70 98 108 64 112 C30 108 16 70 20 36 Z") + path("M32 50 L54 58 L54 66 L32 62 Z M96 50 L74 58 L74 66 L96 62 Z", "d") + line_s("M54 92 H74")
G["breath"] = poly([(18, 64), (100, 22), (118, 34), (96, 52), (122, 64), (96, 76), (118, 94), (100, 106)], "a") + path("M22 64 L92 38 L80 56 L104 64 L80 72 L92 90 Z", "f") + circ(26, 64, 10)
G["icebolt"] = poly([(20, 100), (44, 76), (52, 84), (28, 108)], "a") + poly([(60, 20), (104, 64), (60, 108), (30, 64)], "f") + poly([(60, 38), (86, 64), (60, 90), (46, 64)], "a") + line_s("M60 20 L60 108 M30 64 L104 64")
G["icelance"] = poly([(112, 16), (118, 22), (60, 82), (46, 68)], "f") + poly([(46, 68), (60, 82), (36, 112), (14, 114), (16, 92)], "a") + line_s("M14 114 L40 88") + poly(star(34, 36, 14, 4, 4), "a") + poly(star(96, 96, 12, 4, 4), "a")
G["blizzard"] = "".join(line_s(f"M{64+44*math.cos(math.radians(a)):.1f} {64+44*math.sin(math.radians(a)):.1f} L{64-44*math.cos(math.radians(a)):.1f} {64-44*math.sin(math.radians(a)):.1f}") for a in (0, 60, 120)) + circ(64, 64, 10, "a") + line_s("M20 20 L34 40 M100 14 L110 34 M18 100 L30 116 M96 106 L108 120")
G["role_dps"] = G["sword"]
G["gear"] = "".join(poly([(54, 6), (74, 6), (74, 24), (54, 24)], "f", a) for a in range(0, 360, 45)) + circ(64, 64, 36) + circ(64, 64, 14, "d")
G["door"] = path("M26 12 H82 V116 H26 Z") + circ(70, 66, 5, "d") + poly([(88, 54), (112, 54), (112, 42), (128, 64), (112, 86), (112, 74), (88, 74)], "a")
G["play"] = poly([(30, 14), (112, 64), (30, 114)])
G["back"] = poly([(100, 14), (20, 64), (100, 114), (100, 84), (118, 84), (118, 44), (100, 44)])
G["user"] = circ(64, 40, 24) + path("M20 114 C20 80 40 68 64 68 C88 68 108 80 108 114 Z")
G["close"] = line_s("M24 24 L104 104 M104 24 L24 104")
G["check"] = line_s("M20 66 L50 96 L108 30")
G["volume"] = poly([(14, 46), (40, 46), (70, 18), (70, 110), (40, 82), (14, 82)]) + line_s("M88 46 C100 56 100 72 88 82 M100 30 C122 48 122 80 100 98")
G["mouse"] = path("M64 8 C90 8 100 28 100 52 V76 C100 100 84 118 64 118 C44 118 28 100 28 76 V52 C28 28 38 8 64 8 Z") + line_s("M64 14 V50 M30 50 H98")
G["keyboard"] = path("M10 36 H118 V94 H10 Z") + "".join(f'<rect class="d" x="{20+i*20}" y="46" width="14" height="12" rx="2"/>' for i in range(5)) + '<rect class="d" x="30" y="72" width="68" height="12" rx="2"/>'
G["monitor"] = path("M12 16 H116 V84 H12 Z") + poly([(48, 112), (80, 112), (76, 84), (52, 84)], "a")
G["copy"] = path("M44 12 H108 V84 H44 Z") + path("M20 36 H36 V92 H92 V108 H20 Z", "a")
G["dead"] = G["skull"]
G["signal"] = "".join(f'<rect class="f" x="{14+i*28}" y="{88-i*22}" width="18" height="{28+i*22}" rx="3"/>' for i in range(4))
G["steam"] = circ(64, 64, 50) + circ(84, 52, 14, "d") + circ(84, 52, 7) + circ(44, 82, 10, "d") + line_s("M44 82 L76 62")
G["globe"] = '<circle class="s" cx="64" cy="64" r="46"/><ellipse class="s" cx="64" cy="64" rx="20" ry="46"/>' + line_s("M18 64 H110 M26 38 H102 M26 90 H102")
G["people"] = circ(44, 40, 18) + path("M10 108 C10 80 26 72 44 72 C62 72 78 80 78 108 Z") + circ(92, 46, 14, "a") + path("M70 108 C72 86 82 80 94 80 C108 80 118 88 118 108 Z", "a")
G["plusu"] = G["user"]
G["edit"] = poly([(86, 14), (114, 42), (50, 106), (18, 110), (22, 78)], "f") + poly([(86, 14), (114, 42), (100, 56), (72, 28)], "a")
G["star"] = poly(star(64, 66, 54, 22, 5))
G["stat_hp"] = G["plus"]
G["stat_speed"] = G["boot"]
G["stat_dmg"] = G["sword"]
G["stat_cc"] = G["snowflake"]
G["stat_diff"] = G["skull"]
G["map_random"] = '<rect class="f" x="18" y="18" width="92" height="92" rx="16"/>' + "".join(circ(x, y, 8, "d") for x, y in [(44, 44), (84, 44), (64, 64), (44, 84), (84, 84)])

ABILITIES = {  # id -> (glyph, school)
    "fireball": ("flame", "fire"), "dragonbreath": ("breath", "fire"), "frostbolt": ("icebolt", "frost"), "icelance": ("icelance", "frost"), "blizzard": ("blizzard", "frost"), "spec_fire": ("flame", "fire"), "spec_frost": ("snowflake", "frost"), "pyro": ("meteor", "fire"), "nova": ("snowflake", "frost"), "poly": ("sheep", "arcane"), "blink": ("blink", "arcane"),
    "counter": ("counter", "arcane"), "meteor": ("meteor", "fire"),
    "shot": ("arrow", "physical"), "aimed": ("target", "physical"), "trap": ("snare", "frost"), "conc": ("spiral", "nature"), "disengage": ("disengage", "physical"),
    "silence": ("silence", "shadow"), "volley": ("volley", "fire"),
    "strike": ("sword", "physical"), "mortal": ("mortal", "blood"), "charge": ("charge", "physical"), "hamstring": ("hamstring", "blood"), "shieldwall": ("shieldwall", "physical"),
    "pummel": ("fist", "physical"), "bladestorm": ("blades", "physical"),
    "smite": ("sun", "holy"), "heal": ("plus", "holy"), "pwshield": ("bubble", "holy"), "scream": ("scream", "shadow"), "renew": ("leaf", "nature"), "dispel": ("dove", "holy"),
    "hymn": ("note", "holy"),
    "stab": ("dagger", "physical"), "eviscerate": ("claw", "blood"), "cheapshot": ("burst", "physical"), "blind": ("eye", "shadow"), "vanish": ("ghost", "shadow"),
    "kick": ("boot", "physical"), "deathmark": ("skull", "shadow"),
    # effects (debuffs/buffs) and power-ups
    "fx_stun": ("stars", "holy"), "fx_fear": ("scream", "shadow"), "fx_silence": ("silence", "shadow"), "fx_root": ("roots", "nature"), "fx_slow": ("spiral", "frost"),
    "fx_poly": ("sheep", "arcane"), "fx_freeze": ("snowflake", "frost"), "fx_blind": ("eye", "shadow"), "fx_mortal": ("drop", "blood"), "fx_burn": ("flame", "fire"), "fx_disorient": ("stars", "fire"), "fx_damp": ("drop", "shadow"), "fx_marked": ("skull", "blood"),
    "fx_wall": ("shieldwall", "physical"), "fx_absorb": ("bubble", "holy"), "fx_hot": ("leaf", "nature"), "fx_storm": ("blades", "physical"),
    "power_crit": ("burst", "fire"), "power_stealth": ("ghost", "shadow"), "power_shield": ("shieldwall", "frost"), "power_haste": ("haste", "nature"), "power_heal": ("plus", "blood"),
    "class_mage": ("hat", "arcane"), "class_hunter": ("bow", "nature"), "class_warrior": ("helm", "physical"), "class_priest": ("halo", "holy"), "class_rogue": ("mask", "shadow"),
    "role_dps": ("sword", "fire"), "role_heal": ("plus", "holy"), "role_tank": ("shieldwall", "physical"), "role_control": ("snowflake", "frost"),
    "kill": ("skull", "blood"),
    "class_warlock": ("skull", "shadow"), "shadowbolt": ("shadowbolt", "shadow"),
    "corruption": ("spiral", "shadow"), "agony": ("claw", "shadow"),
    "fear": ("ghost", "shadow"), "darkpact": ("shieldwall", "shadow"),
    "drainlife": ("drop", "nature"), "soulrot": ("roots", "shadow"),
}
UI = ["gear", "door", "play", "back", "user", "close", "check", "volume", "mouse", "keyboard", "monitor", "copy", "signal", "steam", "globe", "people", "edit", "star", "helm",
      "stat_hp", "stat_speed", "stat_dmg", "stat_cc", "stat_diff", "map_random", "sword", "skull", "plus", "boot"]


def svg(body, tile=None):
    defs = ""
    bg = ""
    if tile:
        dark, mid, light = SCHOOLS[tile]
        defs = f'<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{mid}"/><stop offset="1" stop-color="{dark}"/></linearGradient></defs>'
        bg = f'<rect x="3" y="3" width="122" height="122" rx="24" fill="url(#g)" stroke="{light}" stroke-width="4"/><rect x="9" y="9" width="110" height="52" rx="18" fill="#ffffff" opacity="0.10"/>'
        body = f'<g transform="translate(14 14) scale(0.78)">{body}</g>'
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128"><style>{CSS}</style>{defs}{bg}{body}</svg>'


def main():
    os.makedirs(OUT, exist_ok=True)
    n = 0
    for name, (glyph, school) in ABILITIES.items():
        if len(sys.argv) > 1 and name not in sys.argv[1:]: continue
        open(os.path.join(OUT, name + ".svg"), "w").write(svg(G[glyph], school)); n += 1
    for name in UI:
        if len(sys.argv) > 1 and "ui_" + name not in sys.argv[1:]: continue
        open(os.path.join(OUT, "ui_" + name + ".svg"), "w").write(svg(G[name])); n += 1
    print(n, "icons ->", os.path.abspath(OUT))


main()
