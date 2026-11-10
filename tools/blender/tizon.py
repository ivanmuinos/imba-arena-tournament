"""Tizón, the coach of the Academia: a chibi magma salamander, standing up, with a lit tail, an old bronze medal and a whistle.

Model:     blender -b --python tools/blender/build_characters.py -- tizon
Portraits: blender -b --python tools/blender/tizon.py -- portraits <dir>      (tizon_<mood>.png, 512x640, plus a full-body shot)
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from lib import *

MOODS = ["neutral", "contenta", "burlona", "seria", "orgullosa"]

# Head: a long blunt snout, the salamander's silhouette (a wide round head reads as a frog).
HC = (0.0, -0.07, 0.90)
HR = (0.36, 0.46, 0.285)

SK = {
    "root": (None, (0, 0, 0), (0, 0, 0.1)),
    "body": ("root", (0, 0, 0.26), (0, 0, 0.62)),
    "head": ("body", (0, 0, 0.62), (0, 0, 1.05)),
    "medal": ("body", (0.05, -0.22, 0.63), (0.05, -0.26, 0.45)),
    "whistle": ("body", (-0.13, -0.2, 0.63), (-0.13, -0.24, 0.48)),
}
for side, sx in (("L", 1), ("R", -1)):
    SK[f"arm.{side}"] = ("body", (0.25 * sx, -0.02, 0.56), (0.40 * sx, -0.04, 0.40))
    SK[f"hand.{side}"] = (f"arm.{side}", (0.40 * sx, -0.04, 0.40), (0.45 * sx, -0.05, 0.32))
    SK[f"leg.{side}"] = ("root", (0.15 * sx, 0, 0.26), (0.17 * sx, -0.01, 0.09))
    SK[f"foot.{side}"] = (f"leg.{side}", (0.17 * sx, -0.01, 0.09), (0.19 * sx, -0.16, 0.05))
# The tail sweeps out to his left and up, so tail and flame show beside him from the front.
TAIL = [(0.05, 0.17, 0.27), (0.30, 0.30, 0.17), (0.56, 0.32, 0.18), (0.76, 0.22, 0.34), (0.82, 0.14, 0.58)]
TAIL_R = [0.15, 0.115, 0.085, 0.058, 0.032]
for i in range(len(TAIL) - 1):
    SK[f"tail{i + 1}"] = ("root" if i == 0 else f"tail{i}", TAIL[i], TAIL[i + 1])
SK["flame"] = ("tail4", TAIL[-1], (TAIL[-1][0], TAIL[-1][1], TAIL[-1][2] + 0.34))


def on_head(x, z, off=0.012):
    """A point on the front of the head."""
    t = 1.0 - (x / HR[0]) ** 2 - ((z - HC[2]) / HR[2]) ** 2
    return V((x, HC[1] - HR[1] * math.sqrt(max(t, 0.0)) - off, z))


def _materials():
    return {
        "skin": mat("TizonSkin", hexc("#4b3a48"), rough=0.7),
        "belly": mat("TizonBelly", hexc("#f0a060"), rough=0.8),
        "spot": mat("TizonSpot", hexc("#ff8a1e"), rough=0.5, emit=hexc("#ff7a1a"), emit_strength=0.7),
        "eye": mat("TizonEye", hexc("#ffc23e"), rough=0.3),
        "pupil": mat("TizonPupil", hexc("#150c10"), rough=0.2),
        "lid": mat("TizonLid", hexc("#5a4655"), rough=0.7),
        "line": mat("TizonLine", hexc("#150c10"), rough=0.9),
        "mouth": mat("TizonMouth", hexc("#3a0f12"), rough=0.8),
        "tongue": mat("TizonTongue", hexc("#e0524a"), rough=0.6),
        "ribbon": mat("TizonRibbon", hexc("#b8322a"), rough=0.7),
        "bronze": mat("TizonBronze", hexc("#e39a55"), rough=0.4, metal=0.25),
        "steel": mat("TizonSteel", hexc("#e8edf2"), rough=0.3, metal=0.2),
        "fire": mat("TizonFire", hexc("#ff6a14"), rough=0.6, emit=hexc("#ff4d12"), emit_strength=0.9),
        "shine": mat("TizonShine", hexc("#ffffff"), rough=0.2, emit=hexc("#ffffff"), emit_strength=1.0),
        "core": mat("TizonFireCore", hexc("#ffd257"), rough=0.6, emit=hexc("#ffc23a"), emit_strength=1.0),
    }


def _tail_weights(co):
    """Soft along the tail, so it bends instead of snapping at each joint."""
    best = []
    for i in range(len(TAIL) - 1):
        a, b = V(TAIL[i]), V(TAIL[i + 1])
        ab = b - a
        t = max(0.0, min(1.0, (co - a).dot(ab) / ab.length_squared))
        best.append(((a + ab * t - co).length, i))
    best.sort()
    d0, i0 = best[0]
    d1, i1 = best[1]
    w1 = max(0.0, 0.5 - (d1 - d0) * 6.0)
    return {f"tail{i0 + 1}": 1.0 - w1, f"tail{i1 + 1}": w1}


def head_top(x, y, off=0.0):
    """A point on top of the head."""
    t = 1.0 - (x / HR[0]) ** 2 - ((y - HC[1]) / HR[1]) ** 2
    return V((x, y, HC[2] + HR[2] * math.sqrt(max(t, 0.0)) + off))


def _spots(p):
    """The blotches of a fire salamander: on the snout and crown too, so they read from the front."""
    for x, y, r, sc in [(-0.02, -0.17, 0.05, (1.25, 1.0, 0.4)), (0.13, -0.03, 0.058, (1.2, 1.4, 0.4)),
                        (-0.15, 0.06, 0.05, (1.3, 1.0, 0.4)), (0.03, 0.16, 0.06, (1.5, 1.0, 0.4)), (0.08, -0.46, 0.022, (1.0, 1.0, 0.4)),
                        (-0.085, -0.45, 0.02, (1.0, 1.0, 0.4))]:
        p.sphere(head_top(x, y, -0.006), r, sc, seg=10, rings=6)
    for sx in (1, -1):
        p.sphere((0.345 * sx, -0.02, 0.86), 0.05, (0.35, 1.3, 0.9), seg=10, rings=6)


def _body_spots(p):
    for c, r, sc in [((0.20, -0.13, 0.57), 0.045, (0.9, 0.5, 1.0)), ((-0.21, -0.11, 0.55), 0.04, (0.9, 0.5, 1.1)), ((0.255, 0.0, 0.41), 0.05, (0.4, 1.0, 1.25)),
                     ((-0.255, 0.01, 0.38), 0.05, (0.4, 1.0, 1.2)), ((0.0, 0.22, 0.56), 0.07, (1.4, 0.4, 1.0)), ((0.14, 0.19, 0.38), 0.06, (1.1, 0.45, 1.0)),
                     ((-0.15, 0.18, 0.44), 0.05, (1.1, 0.45, 1.0))]:
        p.sphere(c, r, sc, seg=10, rings=6)


def _eye(side, m, lid_top, lid_tilt, look=(0.0, 0.0), closed=False):
    """One bulging eye. lid_top: 0 wide open .. 1 shut. Happy closed eyes are an arc instead of an eye."""
    sx = 1 if side == "L" else -1
    c = V((0.235 * sx, HC[1] - 0.25, 1.005))
    r = 0.118
    out = []
    bulge = Part(f"eyebump{side}", m["skin"], "head", bevel=0, subsurf=1)
    bulge.sphere(c + V((0, 0.025, -0.012)), r * 1.12, seg=16, rings=10)
    out.append(bulge)
    if closed:
        arc = Part(f"eyearc{side}", m["line"], "head", bevel=0, subsurf=0)
        pts = [c + V((math.cos(a) * r * 0.82 * 1.0, -r * 1.08, -0.035 + math.sin(a) * r * 0.62)) for a in [math.pi * i / 6 for i in range(7)]]
        arc.tube(pts, [0.014, 0.019, 0.022, 0.024, 0.022, 0.019, 0.014], seg=8)
        out.append(arc)
        return out
    eye = Part(f"eye{side}", m["eye"], "head", bevel=0, subsurf=1)
    eye.sphere(c, r, seg=18, rings=12)
    out.append(eye)
    pu = Part(f"pupil{side}", m["pupil"], "head", bevel=0, subsurf=1)
    pc = c + V((look[0] * 0.04 - sx * 0.008, -r * 0.8, -0.004 + look[1] * 0.04))
    pu.sphere(pc, 0.078, (1.0, 0.45, 1.12), seg=14, rings=10)
    out.append(pu)
    shine = Part(f"shine{side}", m["shine"], "head", bevel=0, subsurf=0)
    shine.sphere(pc + V((0.022, -0.026, 0.032)), 0.018, seg=8, rings=6)
    out.append(shine)
    if lid_top > 0.0:
        # An upper eyelid: a shell cut by a plane that drops with lid_top and tilts towards the nose.
        lid = Part(f"lid{side}", m["lid"], "head", bevel=0, subsurf=1)
        lid.sphere(c, r * 1.08, seg=22, rings=16)
        cut_z = r * (1.0 - 1.45 * lid_top)
        slope = lid_tilt * sx  # positive: inner side lower (frown)
        faces = []
        for f in lid.bm.faces:
            q = f.calc_center_median() - c
            if q.z < cut_z + slope * q.x:
                faces.append(f)
        bmesh.ops.delete(lid.bm, geom=faces, context="FACES")
        out.append(lid)
    return out


def _mouth(m, mood):
    parts = []
    line = Part("mouth", m["mouth"], "head", bevel=0, subsurf=0)
    if mood in ("contenta", "orgullosa"):
        # Open grin: a dark half moon with a tongue.
        n = 14
        width = 0.235
        top = 0.86
        depth = 0.125
        def f(u, v):
            x = (u - 0.5) * 2 * width
            bottom = top - depth * math.sqrt(max(0.0, 1 - (x / width) ** 2))
            arch = 0.03 * (x / width) ** 2
            return on_head(x, top + arch + (bottom - top) * v, 0.016)
        line.grid(f, n, 5)
        parts.append(line)
        tongue = Part("tongue", m["tongue"], "head", bevel=0, subsurf=1)
        tongue.sphere(on_head(0.0, top - depth * 0.68, 0.022), 0.1, (1.0, 0.2, 0.42), seg=12, rings=8)
        parts.append(tongue)
        lip = Part("lip", m["line"], "head", bevel=0, subsurf=0)
        pts = [on_head(-width - 0.02 + (2 * width + 0.04) * i / 12, top + 0.03 * ((-width - 0.02 + (2 * width + 0.04) * i / 12) / width) ** 2, 0.02) for i in range(13)]
        lip.tube(pts, [0.012] * 13, seg=6)
        parts.append(lip)
        return parts
    if mood == "burlona":
        shape = lambda t: 0.85 + 0.055 * max(0.0, t) ** 1.6 - 0.02 * (1 - t * t)  # a smirk: it rises on one side
        w = 0.25
    elif mood == "seria":
        shape = lambda t: 0.84 - 0.012 * t * t
        w = 0.2
    else:
        shape = lambda t: 0.84 + 0.04 * t * t
        w = 0.265
    pts = []
    for i in range(15):
        t = -1 + 2 * i / 14
        pts.append(on_head(t * w, shape(t), 0.018))
    line.tube(pts, [0.011 + 0.006 * (1 - t * t) for t in [-1 + 2 * i / 14 for i in range(15)]], seg=6)
    parts.append(line)
    return parts


def _build_parts(rig, mood):
    m = _materials()
    parts = []

    def part(name, material, bone, **kw):
        p = Part(name, material, bone, **{"bevel": 0, "subsurf": 1, **kw})
        parts.append(p)
        return p

    part("head", m["skin"], "head").sphere(HC, 1.0, HR, seg=26, rings=18)
    _spots(part("headspots", m["spot"], "head"))
    # Smoulder crest on the back of the head and neck.
    crest = part("crest", m["spot"], "head", subsurf=0)
    for x, y, z, h in [(0.0, 0.0, 1.17, 0.13), (0.0, 0.14, 1.145, 0.14), (0.0, 0.26, 1.08, 0.13), (0.0, 0.34, 0.97, 0.11)]:
        crest.cyl((x, y - 0.01, z - 0.04), (x * 1.1, y + 0.05, z + h), 0.045, 0.004, seg=6)
    for sx in (1, -1):
        nos = part(f"nostril{sx}", m["pupil"], "head", subsurf=0)
        nos.sphere(on_head(0.06 * sx, 0.955, 0.002), 0.015, seg=8, rings=6)

    lids = {"neutral": (0.12, 0.0, 0.12, 0.0), "contenta": (0.0, 0.0, 0.0, 0.0), "burlona": (0.15, -0.25, 0.58, 0.1),
            "seria": (0.5, 0.75, 0.5, 0.75), "orgullosa": (0.0, 0.0, 0.0, 0.0)}[mood]
    closed = mood == "orgullosa"
    look = {"burlona": (0.5, 0.1), "seria": (0.0, -0.1)}.get(mood, (0.0, 0.0))
    for pr in _eye("L", m, lids[0], lids[1], look, closed) + _eye("R", m, lids[2], lids[3], look, closed):
        parts.append(pr)
    parts.extend(_mouth(m, mood))

    part("torso", m["skin"], "body").sphere((0, 0, 0.43), 0.27, (0.98, 0.86, 1.24), seg=22, rings=14)
    part("belly", m["belly"], "body").sphere((0, -0.07, 0.40), 0.205, (0.92, 0.86, 1.3), seg=20, rings=12)
    rows = part("bellyrows", m["mouth"], "body", subsurf=0)
    for z, w in [(0.46, 0.105), (0.37, 0.12), (0.28, 0.105)]:  # a reptile's belly scales, not a frog's smooth one
        rows.tube([(x * w, -0.247 + abs(x) * 0.03, z - abs(x) * 0.012) for x in (-1, -0.5, 0, 0.5, 1)], [0.0045] * 5, seg=5)
    _body_spots(part("bodyspots", m["spot"], "body"))

    for side, sx in (("L", 1), ("R", -1)):
        part(f"arm{side}", m["skin"], f"arm.{side}").tube([(0.24 * sx, -0.01, 0.57), (0.40 * sx, -0.04, 0.40)], [0.075, 0.066], seg=10)
        part(f"armspot{side}", m["spot"], f"arm.{side}").sphere((0.33 * sx, -0.04, 0.50), 0.03, (0.8, 0.7, 1.2), seg=8, rings=6)
        h = part(f"hand{side}", m["skin"], f"hand.{side}")
        h.sphere((0.42 * sx, -0.05, 0.37), 0.075, seg=12, rings=8)
        for a in (-0.65, 0.0, 0.65):
            h.sphere((0.42 * sx + 0.075 * sx * math.cos(a) * 0.45, -0.05 - 0.07 * math.sin(a), 0.30), 0.031, seg=8, rings=6)
        part(f"leg{side}", m["skin"], f"leg.{side}").tube([(0.15 * sx, 0, 0.27), (0.17 * sx, -0.01, 0.10)], [0.10, 0.082], seg=10)
        part(f"legspot{side}", m["spot"], f"leg.{side}").sphere((0.235 * sx, -0.01, 0.18), 0.03, (0.45, 0.9, 1.1), seg=8, rings=6)
        f = part(f"foot{side}", m["skin"], f"foot.{side}")
        f.sphere((0.18 * sx, -0.07, 0.055), 0.095, (1.0, 1.25, 0.58), seg=12, rings=8)
        for a in (-0.55, 0.0, 0.55):
            f.sphere((0.18 * sx + math.sin(a) * 0.082, -0.07 - math.cos(a) * 0.115, 0.042), 0.034, seg=8, rings=6)

    tail = part("tail", m["skin"], "tail1")
    tail.tube(TAIL, TAIL_R, seg=12)
    tail.weights = _tail_weights
    ts = part("tailspots", m["spot"], "tail1")
    for i, (a, b) in enumerate(zip(TAIL[:-1], TAIL[1:])):
        c = (V(a) + V(b)) / 2
        ts.sphere(c + V((0, 0.0, TAIL_R[i] * 0.72)), TAIL_R[i] * 0.42, (1.0, 1.4, 0.4), seg=10, rings=6)
    ts.weights = _tail_weights

    # The fire on the tip: an outer flame with a hot core. Pointy, like the champions' low-poly props.
    tip = V(TAIL[-1])
    fl = part("flame", m["fire"], "flame", subsurf=0)
    fl.sphere(tip + V((0, 0, 0.09)), 0.125, seg=12, rings=8)
    fl.cyl(tip + V((0, 0, 0.13)), tip + V((0.025, 0, 0.47)), 0.112, 0.004, seg=10)
    fl.cyl(tip + V((0.06, 0, 0.11)), tip + V((0.17, 0, 0.32)), 0.06, 0.003, seg=8)
    fl.cyl(tip + V((-0.06, 0, 0.11)), tip + V((-0.15, 0, 0.29)), 0.06, 0.003, seg=8)
    co = part("flamecore", m["core"], "flame", subsurf=0)
    co.sphere(tip + V((0, -0.09, 0.09)), 0.072, seg=10, rings=8)
    co.cyl(tip + V((0, -0.082, 0.12)), tip + V((0.012, -0.03, 0.33)), 0.066, 0.003, seg=8)

    # Ribbon, medal, whistle.
    part("ribbon", m["ribbon"], "body", subsurf=0).torus((0, -0.01, 0.645), 0.185, 0.024, rot=(0.2, 0, 0), seg=26, rings=7)
    rb = part("medalstrap", m["ribbon"], "medal", subsurf=0)
    rb.box((0.05, -0.222, 0.585), (0.05, 0.016, 0.1), rot=(0.25, 0, 0))
    md = part("medal", m["bronze"], "medal", subsurf=0, bevel=0.006)
    md.cyl((0.05, -0.25, 0.495), (0.05, -0.272, 0.495), 0.082, 0.082, seg=20)
    md.cyl((0.05, -0.272, 0.495), (0.05, -0.28, 0.495), 0.05, 0.05, seg=5)  # a worn star
    cord = part("cord", m["pupil"], "whistle", subsurf=0)
    cord.tube([(-0.10, -0.17, 0.64), (-0.13, -0.235, 0.555)], [0.007, 0.007], seg=5)
    wh = part("whistle", m["steel"], "whistle", subsurf=0, bevel=0.003)
    wh.sphere((-0.135, -0.245, 0.525), 0.044, (1.0, 0.8, 1.0), seg=12, rings=8)
    wh.box((-0.195, -0.245, 0.545), (0.08, 0.05, 0.04))
    return parts


def _finish(rig, parts):
    for p in parts:
        o = p.build()
        rig.bind(o, p.bone, p.weights)


def _make(mood):
    reset()
    rig = Rig("TizonRig")
    rig.build(SK)
    _finish(rig, _build_parts(rig, mood))
    return rig


def _sway(a):
    return {"tail1": (0, 0, 0.1 * a), "tail2": (0, 0, 0.14 * a), "tail3": (0, 0, 0.18 * a), "tail4": (0, 0, 0.22 * a), "flame": (0.12 * a, 0, 0.1 * a)}


def _animations(rig):
    def idle(a, w):
        d = {"body": (0.02 * a, 0, 0), "head": (-0.03 * a, 0, 0.05 * w), "hand.L": (0.1 * a, 0, 0), "hand.R": (-0.1 * a, 0, 0),
             "arm.L": (0, 0, -0.04 * a), "arm.R": (0, 0, 0.04 * a), "medal": (0.06 * w, 0, 0), "whistle": (-0.08 * w, 0, 0)}
        d.update(_sway(w))
        return d
    rig.animation("idle", 48, {1: idle(0, -1), 13: idle(1, 0), 25: idle(0, 1), 37: idle(1, 0), 49: idle(0, -1)})

    def walk(ph):
        s = math.sin(ph)
        c = math.cos(ph)
        d = {"root": ((0, 0.1 * s, 0.05 * s), (0, 0, 0.035 * abs(c))), "body": (0.12, 0, -0.06 * s), "head": (-0.1, 0.05 * s, 0.05 * s),
             "leg.L": (0.75 * s, 0, 0), "leg.R": (-0.75 * s, 0, 0), "foot.L": (-0.3 * s, 0, 0), "foot.R": (0.3 * s, 0, 0),
             "arm.L": (-0.55 * s, 0, 0), "arm.R": (0.55 * s, 0, 0), "medal": (0.25 * c, 0, 0), "whistle": (-0.25 * c, 0, 0)}
        d.update(_sway(-c * 1.6))
        return d
    rig.animation("walk", 24, {1 + i * 4: walk(i * math.pi / 3) for i in range(7)})

    def celebrate(j, a):
        d = {"root": ((0, 0, 0), (0, 0, 0.28 * j)), "body": (-0.1 * j, 0, 0), "head": (-0.25 * j, 0, 0.08 * a),
             "arm.L": (-2.2 - 0.3 * j, 0, -0.5), "arm.R": (-2.2 - 0.3 * j, 0, 0.5), "hand.L": (-0.3 * a, 0, 0), "hand.R": (0.3 * a, 0, 0),
             "leg.L": (0.35 * j, 0, 0), "leg.R": (0.35 * j, 0, 0), "foot.L": (-0.4 * j, 0, 0), "foot.R": (-0.4 * j, 0, 0),
             "medal": (-0.7 * j, 0, 0), "whistle": (-0.5 * j, 0, 0)}
        d.update(_sway(a * 1.8))
        return d
    rig.animation("celebrate", 36, {1: celebrate(0, -1), 7: celebrate(0.5, -0.4), 10: celebrate(1, 0), 13: celebrate(0.5, 0.4), 19: celebrate(0, 1),
                                     25: celebrate(0.5, 0.4), 28: celebrate(1, 0), 31: celebrate(0.5, -0.4), 37: celebrate(0, -1)})

    def point(t, a):
        # Out to his right and up: straight ahead the short arm hides under the snout.
        d = {"arm.R": (-0.3 * t, 1.3 * t, 0), "hand.R": (0, 0.35 * t + 0.1 * a * t, 0), "arm.L": (0.1 * t, 0, -0.65 * t), "hand.L": (-1.3 * t, 0, 0),
             "body": (0.03 * t, 0.08 * t, -0.14 * t), "head": (-0.05 * t, -0.06 * t, -0.34 * t), "medal": (0.05 * a, 0, 0), "whistle": (-0.06 * a, 0, 0)}
        d.update(_sway(a * 0.7))
        return d
    rig.animation("point", 48, {1: point(0, -1), 9: point(1, -0.5), 21: point(1, 0.5), 33: point(1, -0.5), 41: point(1, 0), 49: point(0, -1)})
    rig.reset_pose()


def build_glb(path):
    rig = _make("neutral")
    _animations(rig)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    export_glb(path)
    print("built tizon", path)


# ------------------------------------------------------------------ portraits

def _outline(width=0.012):
    """The champions' black contour: an inflated copy showing only its back faces."""
    line = bpy.data.materials.new("Outline")
    line.use_nodes = True
    b = line.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0, 0, 0, 1)
    b.inputs["Roughness"].default_value = 1.0
    b.inputs["Specular IOR Level"].default_value = 0.0
    line.use_backface_culling = True
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH" or o.data.materials[0].name.startswith(("TizonLine", "TizonShine", "TizonPupil", "TizonEye", "TizonMouth", "TizonTongue", "TizonFireCore")):
            continue
        o.data.materials.append(line)
        s = o.modifiers.new("OutlineHull", "SOLIDIFY")
        s.thickness = width
        s.offset = 1.0
        s.use_flip_normals = True
        s.material_offset = 1
        s.use_rim = False


def _stage(path, cam_at, target, lens, res):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items.keys() else "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (1.0, 0.93, 0.86, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.05
    sc.world = w
    for name, energy, rot, col in [("Key", 3.2, (0.95, 0.0, 0.5), (1.0, 0.96, 0.9)), ("Rim", 2.4, (-1.1, 0.0, 3.0), (1.0, 0.55, 0.25))]:
        d = bpy.data.lights.new(name, "SUN")
        d.energy = energy
        d.color = col
        ob = bpy.data.objects.new(name, d)
        ob.rotation_euler = rot
        sc.collection.objects.link(ob)
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    cam.location = cam_at
    cam.rotation_euler = (V(target) - V(cam_at)).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    bpy.ops.render.render(write_still=True)


def portraits(out):
    """Head-and-shoulders portraits, framed like the champions' (head in the top part, for Portraits.bust)."""
    os.makedirs(out, exist_ok=True)
    for mood in MOODS:
        rig = _make(mood)
        rig.reset_pose()
        if mood == "orgullosa":
            rig.pose("head", (-0.2, 0, 0.1))
            rig.pose("arm.L", (-0.1, 0, -0.5))
        elif mood == "burlona":
            rig.pose("head", (0.03, 0.14, -0.12))
        elif mood == "seria":
            rig.pose("head", (0.09, 0, 0))
        elif mood == "contenta":
            rig.pose("head", (-0.08, -0.07, 0.06))
        bpy.context.view_layer.update()
        _outline(0.011)
        _stage(os.path.join(out, f"tizon_{mood}.png"), (0.62, -3.0, 1.2), (0.0, -0.03, 0.80), 86, (512, 640))
    rig = _make("neutral")
    rig.reset_pose()
    bpy.context.view_layer.update()
    _outline(0.011)
    _stage(os.path.join(out, "tizon_full.png"), (1.3, -3.4, 1.15), (0.22, 0.1, 0.55), 50, (800, 800))


if __name__ == "__main__" and "portraits" in sys.argv:
    portraits(os.path.abspath(sys.argv[sys.argv.index("portraits") + 1]))
