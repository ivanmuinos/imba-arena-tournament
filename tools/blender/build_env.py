"""Environment kit for the four arenas -> assets/models/env/*.glb
Run: blender -b --python tools/blender/build_env.py [-- wall pillar ...]
Everything is modular: Godot instances/scales these pieces to the collision shapes in core/game_map.gd."""
import math, os, random, sys
sys.path.insert(0, os.path.dirname(__file__))
from lib import *
import anatomy as A
from dress import P

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "models", "env"))


def M():
    return dict(
        basalt=mat("basalt", hexc("#3a3430"), 0.85),
        basalt_l=mat("basalt_light", hexc("#5a4e46"), 0.8),
        obsidian=mat("obsidian", hexc("#1a1620"), 0.18, 0.1),
        stone=mat("carved_stone", hexc("#7a6c5e"), 0.78),
        stone_d=mat("carved_stone_dark", hexc("#4a4038"), 0.82),
        pale=mat("pale_stone", hexc("#9a9488"), 0.75),
        ember=mat("ember", hexc("#ff7a20"), 0.4, 0, emit=hexc("#ff5a08"), emit_strength=6.0),
        ember_s=mat("ember_soft", hexc("#ff7a20"), 0.5, 0, emit=hexc("#ff4a00"), emit_strength=2.5),
        wood=mat("dead_wood", hexc("#33241c"), 0.9),
        iron=mat("dark_iron", hexc("#3c3c48"), 0.5, 0.85),
        gold=mat("old_gold", hexc("#b88a3a"), 0.35, 1.0),
        eye=mat("titan_eye", hexc("#9fe8ff"), 0.3, 0, emit=hexc("#6fd8ff"), emit_strength=8.0),
        rune=mat("ancient_rune", hexc("#ff9a40"), 0.4, 0, emit=hexc("#ff7a10"), emit_strength=5.0),
    )


def ao(h, base=0.45, var=0.25, seed=0):
    """Vertex-colour ambient occlusion stand-in: darker at the foot and noisy variation (multiplies albedo in Godot)."""
    from mathutils import noise

    def f(co):
        t = max(0.0, min(1.0, co.z / h))
        n = noise.noise(co * 0.9 + V((seed, seed * 2, 0))) * var
        g = base + (1 - base) * t ** 0.6 + n
        g = max(0.25, min(1.0, g))
        return (g, g * 0.97, g * 0.94)
    return f


def part(name, m, h=8.0, **kw):
    p = P(name, m, "none", **kw)
    p.vcol_fn = ao(h, seed=hash(name) % 50)
    return p


def build_parts(parts):
    for p in parts:
        p.build(solidify=getattr(p, "solid", 0.0))


def export(name):
    os.makedirs(OUT, exist_ok=True)
    export_glb(os.path.join(OUT, name + ".glb"))
    print("built", name)


def bricks(m, rnd, length, thick, height, row_h=0.62, name="wall"):
    p = part(name + "_bricks", m["stone"], height, bevel=0.035, subsurf=0)
    z = 0.8
    row = 0
    while z + row_h <= height - 0.2:
        x = -length / 2
        off = 0.0 if row % 2 == 0 else -0.55
        x += off
        while x < length / 2:
            w = rnd.uniform(0.9, 1.35)
            x0, x1 = max(x, -length / 2), min(x + w - 0.04, length / 2)
            if x1 - x0 > 0.15:
                j = rnd.uniform(-0.03, 0.03)
                p.box(((x0 + x1) / 2, j, z + row_h / 2), (x1 - x0, thick - 0.1 + rnd.uniform(-0.04, 0.04), row_h - 0.05))
            x += w
        z += row_h
        row += 1
    return p, z


def wall():
    rnd = random.Random(5)
    m = M()
    L, T, H = 4.0, 1.5, 7.0
    p, ztop = bricks(m, rnd, L, T, H)
    base = part("wall_plinth", m["basalt"], H, bevel=0.05, subsurf=0)
    base.box((0, 0, 0.4), (L, T + 0.5, 0.8))
    base.box((0, 0, 0.9), (L, T + 0.25, 0.25))
    cap = part("wall_cap", m["basalt_l"], H, bevel=0.04, subsurf=0)
    cap.box((0, 0, ztop + 0.15), (L, T + 0.35, 0.3))
    for k in range(2):  # merlons
        cap.box((-1.0 + 2.0 * k, 0, ztop + 0.65), (1.0, T - 0.2, 0.7))
    seams = part("wall_seams", m["ember"], H, bevel=0, subsurf=0)
    for k in range(5):
        x = rnd.uniform(-1.8, 1.8)
        seams.box((x, -T / 2 + 0.02, 0.9 + rnd.uniform(0, 1.6)), (rnd.uniform(0.25, 0.6), 0.05, 0.07))
        seams.box((x * 0.7, T / 2 - 0.02, 0.9 + rnd.uniform(0, 1.6)), (rnd.uniform(0.25, 0.6), 0.05, 0.07))
    build_parts([p, base, cap, seams])
    export("wall")


def pillar():
    rnd = random.Random(2)
    m = M()
    H = 9.2
    shaft = part("pillar_shaft", m["stone"], H, bevel=0, subsurf=1)
    nu, nv = 36, 6

    def fn(u, v):
        a = 2 * math.pi * u
        z = 1.2 + v * 6.8
        r = (1.0 - 0.12 * v) * (1 + 0.055 * math.cos(12 * a))
        return V((r * math.cos(a), r * math.sin(a), z))
    shaft.grid(fn, nu, nv)
    shaft.solid = 0.05
    base = part("pillar_base", m["basalt_l"], H, bevel=0.06, subsurf=0)
    base.box((0, 0, 0.4), (2.7, 2.7, 0.8))
    base.cyl((0, 0, 1.0), (0, 0, 1.3), 1.25, 1.05, seg=24)
    cap = part("pillar_cap", m["basalt_l"], H, bevel=0.05, subsurf=0)
    cap.cyl((0, 0, 8.0), (0, 0, 8.5), 0.92, 1.3, seg=24)
    cap.box((0, 0, 8.85), (2.9, 2.9, 0.5))
    cap.box((0, 0, 9.15), (2.5, 2.5, 0.2))
    rune = part("pillar_rune", m["rune"], H, bevel=0, subsurf=0)
    rune.torus((0, 0, 7.7), 0.9, 0.05, seg=36, rings=6)
    for k in range(6):
        a = k * math.pi / 3
        rune.box((0.97 * math.cos(a), 0.97 * math.sin(a), 6.0 + rnd.uniform(-1, 0.8)), (0.06, 0.06, rnd.uniform(0.6, 1.6)), (0, 0, a))
    build_parts([shaft, base, cap, rune])
    export("pillar")


def gate_leaf():
    m = M()
    W, T, H = 6.0, 0.8, 6.4
    slab = part("leaf_slab", m["obsidian"], H, bevel=0.05, subsurf=0)
    slab.box((W / 2, 0, H / 2 + 0.1), (W, T, H))
    bands = part("leaf_bands", m["iron"], H, bevel=0.03, subsurf=0)
    for k in range(5):
        bands.box((0.6 + k * 1.2, -T / 2 - 0.05, H / 2 + 0.1), (0.3, 0.12, H + 0.1))
    for zz in (0.9, H / 2 + 0.1, H - 0.7):
        bands.box((W / 2, -T / 2 - 0.08, zz), (W, 0.14, 0.35))
    for k in range(5):
        for zz in (0.9, H - 0.7):
            bands.sphere((0.6 + k * 1.2, -T / 2 - 0.18, zz), 0.1, seg=8, rings=5)
    hinge = part("leaf_hinge", m["gold"], H, bevel=0.02, subsurf=0)
    for zz in (1.0, H / 2, H - 0.6):
        hinge.cyl((0.0, 0.0, zz - 0.35), (0.0, 0.0, zz + 0.35), 0.28, 0.28, seg=12)
    rune = part("leaf_rune", m["rune"], H, bevel=0, subsurf=0)
    rune.torus((W / 2 + 0.2, -T / 2 - 0.1, H / 2 + 0.3), 1.0, 0.05, rot=(math.pi / 2, 0, 0), seg=40, rings=6)
    rune.box((W / 2 + 0.2, -T / 2 - 0.1, H / 2 + 0.3), (0.08, 0.06, 2.2))
    rune.box((W / 2 + 0.2, -T / 2 - 0.1, H / 2 + 0.3), (2.2, 0.06, 0.08))
    build_parts([slab, bands, hinge, rune])
    export("gate_leaf")


def gate_frame():
    m = M()
    H = 8.6
    posts = part("frame_posts", m["basalt_l"], H, bevel=0.06, subsurf=0)
    for s in (1, -1):
        posts.box((s * 6.9, 0, H / 2), (1.8, 2.0, H))
        posts.box((s * 6.9, 0, 0.5), (2.3, 2.5, 1.0))
    arch = part("frame_lintel", m["stone"], H, bevel=0.06, subsurf=0)
    arch.box((0, 0, 7.6), (14.8, 2.0, 1.4))
    arch.box((0, 0, 8.6), (15.4, 2.2, 0.5))
    for k in range(7):  # corbels under the lintel
        arch.box((-5.4 + k * 1.8, -1.0, 6.7), (0.7, 0.5, 0.7))
    gl = part("frame_glow", m["rune"], H, bevel=0, subsurf=0)
    gl.sphere((0, -1.05, 7.7), 0.45, (1, 0.4, 1.3), seg=12, rings=8)
    for s in (1, -1):
        gl.box((s * 6.9, -1.02, 5.0), (0.12, 0.06, 3.2))
    skull = part("frame_skulls", m["pale"], H, bevel=0, subsurf=1)
    for s in (1, -1):
        skull.sphere((s * 4.2, -1.1, 7.7), 0.5, (1, 0.8, 1.1))
        skull.sphere((s * 4.2, -1.45, 7.45), 0.3, (1, 0.7, 0.8))
    build_parts([posts, arch, gl, skull])
    export("gate_frame")


def rock(seed, name):
    rnd = random.Random(seed)
    m = M()
    p = part(name, m["basalt"], 3.5, bevel=0, subsurf=0, smooth=False)
    for k in range(3 if seed % 2 else 2):
        p.sphere((rnd.uniform(-0.8, 0.8), rnd.uniform(-0.6, 0.6), 0.9 + rnd.uniform(0, 0.8)), rnd.uniform(0.9, 1.5), (1.1, 1.0, rnd.uniform(1.0, 1.6)), (rnd.random(), rnd.random(), rnd.random()), seg=18, rings=12)
    p.displace(0.28, 1.1, seed)
    p.deform(lambda c: V((c.x, c.y, max(c.z, 0.0) if c.z > 0 else c.z * 0.15)))
    cr = part(name + "_glow", m["ember_s"], 3.5, bevel=0, subsurf=0)
    for k in range(3):
        a = rnd.random() * 6.28
        cr.box((math.cos(a) * 1.0, math.sin(a) * 1.0, rnd.uniform(0.4, 1.4)), (0.05, 0.4, 0.06), (0, 0, a))
    build_parts([p, cr])
    export(name)


def statue():
    """Titan: armoured colossus leaning on a greatsword, ~13 m tall on a stepped plinth."""
    m = M()
    S = 6.6
    plinth = part("statue_plinth", m["basalt_l"], 3.0, bevel=0.08, subsurf=0)
    plinth.box((0, 0, 0.5), (8.0, 8.0, 1.0)); plinth.box((0, 0, 1.3), (6.8, 6.8, 0.8)); plinth.box((0, 0, 2.0), (5.6, 5.6, 0.7))
    body = part("statue_body", m["stone"], 13.0, bevel=0, subsurf=1)
    ax = A  # reuse the hero anatomy at human scale, then scale up
    ax.torso(body, 0.92, 1.49, 0.045, 1.1, 1.15)
    for side in ("L", "R"):
        ax.leg(body, side, 0.06, 0.97, 0.03)
        ax.arm(body, side, 0.0, 1.0, 0.03)
    body.sphere((0, 0, 0.95), 0.2, (1.4, 1.0, 0.8))
    body.sphere((0.32, 0, 1.45), 0.16, (1.2, 1.1, 0.8)); body.sphere((-0.32, 0, 1.45), 0.16, (1.2, 1.1, 0.8))  # pauldrons
    body.sphere((0, -0.0, 1.69), 0.15, (0.95, 1.0, 1.1))
    body.cyl((0, 0, 1.5), (0, 0, 1.62), 0.08, 0.1)
    body.tube([(0.14, 0, 1.76), (0.24, 0, 1.8), (0.3, 0, 1.95)], [0.04, 0.03, 0.005], seg=8)
    body.tube([(-0.14, 0, 1.76), (-0.24, 0, 1.8), (-0.3, 0, 1.95)], [0.04, 0.03, 0.005], seg=8)
    body.grid(lambda u, v: V((-0.3 + 0.6 * u, 0.17 + 0.1 * v, 1.5 - 1.3 * v)), 6, 8)  # cape
    body.solid = 0.03
    body.scale(S)
    body.deform(lambda c: c + V((0, 0, 2.3)))
    eyes = part("statue_eyes", m["eye"], 13.0, bevel=0, subsurf=0)
    for s in (1, -1):
        eyes.sphere((0.05 * s * S, -0.11 * S, 1.69 * S + 2.3), 0.12, (1.3, 0.5, 0.8), seg=8, rings=5)
    sword = part("statue_sword", m["iron"], 13.0, bevel=0.04, subsurf=0)
    sword.box((0, -1.4, 5.8), (0.55, 0.16, 7.6))
    sword.box((0, -1.4, 9.8), (2.6, 0.4, 0.4)); sword.cyl((0, -1.4, 9.9), (0, -1.4, 11.0), 0.2, 0.2); sword.sphere((0, -1.4, 11.2), 0.35)
    runes = part("statue_runes", m["rune"], 13.0, bevel=0, subsurf=0)
    runes.box((0, -1.52, 6.2), (0.06, 0.04, 5.0)); runes.torus((0, -0.4, 8.2), 0.95 * 1.1, 0.05, rot=(0, 0, 0), seg=30, rings=5)
    for k in range(6):
        runes.sphere((math.cos(k * 1.047) * 3.1, math.sin(k * 1.047) * 3.1, 1.02), 0.14, seg=8, rings=5)
    build_parts([plinth, body, eyes, sword, runes])
    export("statue")


def gravestone():
    m = M()
    p = part("grave", m["pale"], 2.0, bevel=0.05, subsurf=0)
    p.box((0, 0, 0.6), (1.4, 0.45, 1.2))
    p.cyl((0, -0.0, 1.2), (0.0, 0.0, 1.2), 0.0, 0.0, seg=3)
    p.sphere((0, 0, 1.2), 0.7, (1.0, 0.33, 0.7), seg=14, rings=8)
    p.box((0, 0, 0.12), (2.0, 1.0, 0.24))
    p.displace(0.03, 3.0, 1)
    r = part("grave_rune", m["rune"], 2.0, bevel=0, subsurf=0)
    r.box((0, -0.24, 1.15), (0.08, 0.04, 0.7)); r.box((0, -0.24, 1.25), (0.4, 0.04, 0.08))
    build_parts([p, r])
    export("gravestone")


def broken_column():
    rnd = random.Random(8)
    m = M()
    p = part("bcol", m["pale"], 4.0, bevel=0.04, subsurf=0)
    z = 0.0
    for k in range(4):
        h = rnd.uniform(0.7, 1.1)
        p.cyl((rnd.uniform(-0.05, 0.05), 0, z), (rnd.uniform(-0.05, 0.05), 0, z + h), 1.0 - 0.04 * k, 0.97 - 0.04 * k, seg=14)
        z += h + 0.02
    p.cyl((1.6, 0.4, 0.8), (3.0, 0.9, 0.9), 0.9, 0.9, seg=14)
    p.displace(0.05, 2.5, 4)
    build_parts([p])
    export("broken_column")


def dead_tree(seed, name):
    rnd = random.Random(seed)
    m = M()
    pts, rad = [], []
    for i in range(9):
        t = i / 8
        pts.append((math.sin(t * 5 + seed) * 0.5 * t, math.cos(t * 4 + seed) * 0.5 * t, t * 8.5))
        rad.append(0.85 * (1 - t) ** 0.8 + 0.12)
    trunk = part(name + "_trunk", m["wood"], 9.0, bevel=0, subsurf=1)
    trunk.tube(pts, rad, seg=10)
    for k in range(5):
        a = rnd.random() * 6.28
        trunk.tube([(0, 0, 0.4), (math.cos(a) * 0.8, math.sin(a) * 0.8, 0.2), (math.cos(a) * 1.7, math.sin(a) * 1.7, -0.1)], [0.45, 0.3, 0.08], seg=8)
    ember = part(name + "_embers", m["ember_s"], 9.0, bevel=0, subsurf=1)
    for k in range(4):
        t0 = rnd.uniform(0.45, 0.9)
        a = rnd.random() * 6.28
        bp = [pts[int(t0 * 8)], (pts[int(t0 * 8)][0] + math.cos(a) * 1.3, pts[int(t0 * 8)][1] + math.sin(a) * 1.3, pts[int(t0 * 8)][2] + 0.9), (pts[int(t0 * 8)][0] + math.cos(a) * 2.5, pts[int(t0 * 8)][1] + math.sin(a) * 2.5, pts[int(t0 * 8)][2] + 1.2)]
        trunk.tube(bp, [0.2, 0.12, 0.03], seg=6)
        for j in range(6):
            ember.sphere((bp[2][0] + rnd.uniform(-0.8, 0.8), bp[2][1] + rnd.uniform(-0.8, 0.8), bp[2][2] + rnd.uniform(-0.3, 0.8)), rnd.uniform(0.18, 0.34), (1, 1, 0.6), seg=8, rings=5)
    for j in range(12):
        ember.sphere((pts[-1][0] + rnd.uniform(-1.0, 1.0), pts[-1][1] + rnd.uniform(-1.0, 1.0), pts[-1][2] + rnd.uniform(-0.6, 0.8)), rnd.uniform(0.2, 0.4), (1, 1, 0.6), seg=8, rings=5)
    build_parts([trunk, ember])
    export(name)


def bridge():
    rnd = random.Random(9)
    m = M()
    L, Wd = 19.4, 4.4
    deck = part("bridge_deck", m["basalt_l"], 3.0, bevel=0.02, subsurf=0)
    y = -L / 2
    while y < L / 2 - 0.1:
        w = rnd.uniform(0.42, 0.6)
        deck.box((rnd.uniform(-0.02, 0.02), y + w / 2, -0.12), (Wd - 0.5, w - 0.04, 0.24))
        y += w
    for s in (1, -1):
        deck.box((s * (Wd / 2 - 0.15), 0, -0.1), (0.5, L, 0.5))
    under = part("bridge_under", m["stone_d"], 8.0, bevel=0.05, subsurf=0)
    under.box((0, 0, -0.6), (Wd - 0.4, L, 0.5))
    for yy in (-L / 2 + 1.5, 0, L / 2 - 1.5):
        under.box((0, yy, -1.4), (Wd - 0.2, 1.4, 1.2))  # transverse beams
        for s in (1, -1):
            under.cyl((s * 1.3, yy, -1.9), (s * 1.6, yy, -7.0), 0.55, 0.75, seg=10)  # supports
    for k in range(5):  # half-arches between supports
        yy = -L / 2 + 2.2 + k * 3.7
        under.torus((0, yy, -1.2), 1.7, 0.18, rot=(0, math.pi / 2, math.pi / 2), seg=20, rings=6)
    posts = part("bridge_posts", m["iron"], 3.0, bevel=0.03, subsurf=0)
    for s in (1, -1):
        for k in range(9):
            yy = -L / 2 + 0.5 + k * (L - 1.0) / 8
            posts.cyl((s * (Wd / 2 - 0.15), yy, 0.1), (s * (Wd / 2 - 0.15), yy, 1.25), 0.1, 0.07, seg=8)
            posts.sphere((s * (Wd / 2 - 0.15), yy, 1.3), 0.12, seg=8, rings=5)
        posts.tube([(s * (Wd / 2 - 0.15), -L / 2 + 0.5, 1.1), (s * (Wd / 2 - 0.15), 0, 0.75), (s * (Wd / 2 - 0.15), L / 2 - 0.5, 1.1)], [0.03, 0.03, 0.03], seg=5)
    glow = part("bridge_glow", m["ember_s"], 3.0, bevel=0, subsurf=0)
    for k in range(10):
        glow.box((rnd.uniform(-1.6, 1.6), rnd.uniform(-L / 2, L / 2), -0.01), (0.04, rnd.uniform(0.3, 0.9), 0.02))
    build_parts([deck, under, posts, glow])
    export("bridge")


def torch():
    m = M()
    b = part("torch_bowl", m["iron"], 2.4, bevel=0.02, subsurf=0)
    b.cyl((0, 0, 1.4), (0, 0, 1.9), 0.35, 0.55, seg=12)
    for k in range(3):
        a = k * 2.094
        b.cyl((math.cos(a) * 0.5, math.sin(a) * 0.5, 0.0), (math.cos(a) * 0.1, math.sin(a) * 0.1, 1.45), 0.06, 0.05, seg=6)
    b.torus((0, 0, 1.9), 0.55, 0.05, seg=16, rings=6)
    f = part("torch_fire", m["ember"], 2.4, bevel=0, subsurf=1)
    f.sphere((0, 0, 2.2), 0.4, (1, 1, 1.7), seg=10, rings=8)
    f.sphere((0.1, 0.05, 2.5), 0.22, (1, 1, 1.9), seg=8, rings=6)
    build_parts([b, f])
    export("torch")


def crystal():
    rnd = random.Random(4)
    m = M()
    c = part("crystal", m["ember"], 3.0, bevel=0.01, subsurf=0)
    for k in range(6):
        a = rnd.random() * 6.28
        d = rnd.uniform(0.0, 0.6)
        h = rnd.uniform(0.9, 2.2)
        tilt = rnd.uniform(0.05, 0.4)
        base = V((math.cos(a) * d, math.sin(a) * d, 0))
        top = base + V((math.cos(a) * tilt * h, math.sin(a) * tilt * h, h))
        c.cyl(base, top, 0.22, 0.02, seg=6)
    rk = part("crystal_rock", m["basalt"], 3.0, bevel=0, subsurf=0, smooth=False)
    rk.sphere((0, 0, 0.1), 0.9, (1, 1, 0.4), seg=12, rings=8).displace(0.1, 2.0, 3)
    build_parts([c, rk])
    export("crystal")


def cliff():
    m = M()
    p = part("cliff", m["basalt"], 14.0, bevel=0, subsurf=0, smooth=False)
    rnd = random.Random(12)
    for k in range(7):
        p.sphere((rnd.uniform(-5, 5), rnd.uniform(-2, 2), rnd.uniform(1, 9)), rnd.uniform(2.5, 4.2), (1.0, 0.8, 1.6), (rnd.random(), rnd.random(), rnd.random()), seg=16, rings=10)
    p.displace(0.7, 0.5, 6)
    g = part("cliff_glow", m["ember_s"], 14.0, bevel=0, subsurf=0)
    for k in range(6):
        g.box((rnd.uniform(-4, 4), -2.2, rnd.uniform(1, 8)), (rnd.uniform(0.1, 0.25), 0.1, rnd.uniform(0.8, 2.4)), (0, 0, rnd.uniform(-0.4, 0.4)))
    build_parts([p, g])
    export("cliff")


JOBS = {"wall": wall, "pillar": pillar, "gate_leaf": gate_leaf, "gate_frame": gate_frame, "statue": statue, "gravestone": gravestone,
        "broken_column": broken_column, "bridge": bridge, "torch": torch, "crystal": crystal, "cliff": cliff,
        "rock_a": lambda: rock(1, "rock_a"), "rock_b": lambda: rock(2, "rock_b"), "rock_c": lambda: rock(3, "rock_c"),
        "tree_a": lambda: dead_tree(1, "tree_a"), "tree_b": lambda: dead_tree(2, "tree_b"), "tree_c": lambda: dead_tree(3, "tree_c")}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for k in (argv or list(JOBS)):
        reset()
        JOBS[k]()
