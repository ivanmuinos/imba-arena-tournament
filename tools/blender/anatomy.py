"""Stylised heroic anatomy as lofted surfaces. Armour/clothing are the same lofts, inflated."""
import math
from lib import *


def _lerp(a, b, t):
    return a + (b - a) * t


def loft(part, sections, seg=18, caps=True):
    """sections: [(center, rx, ry)] ordered along the path; ellipse in the XY plane at each centre."""
    bm = part.bm
    rings = []
    for c, rx, ry in sections:
        c = V(c)
        rings.append([bm.verts.new(V((c.x + rx * math.cos(2 * math.pi * k / seg), c.y + ry * math.sin(2 * math.pi * k / seg), c.z))) for k in range(seg)])
    for i in range(len(rings) - 1):
        for k in range(seg):
            a, b = rings[i], rings[i + 1]
            try:
                bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]))
            except ValueError:
                pass
    if caps:
        for ring, c in ((rings[0], sections[0][0]), (rings[-1], sections[-1][0])):
            cv = bm.verts.new(V(c))
            for k in range(seg):
                try:
                    bm.faces.new((ring[(k + 1) % seg], ring[k], cv) if ring is rings[0] else (ring[k], ring[(k + 1) % seg], cv))
                except ValueError:
                    pass
    return part


# (z, rx, ry) torso profile: hips -> waist -> chest -> shoulder line (heroic V taper)
TORSO = [(0.92, 0.165, 0.115), (1.0, 0.17, 0.118), (1.1, 0.152, 0.108), (1.2, 0.18, 0.125), (1.32, 0.225, 0.14), (1.42, 0.245, 0.135), (1.49, 0.14, 0.095)]


def _interp_profile(prof, z):
    z = max(prof[0][0], min(prof[-1][0], z))
    for i in range(len(prof) - 1):
        if prof[i][0] <= z <= prof[i + 1][0]:
            t = (z - prof[i][0]) / (prof[i + 1][0] - prof[i][0])
            t = t * t * (3 - 2 * t)
            return _lerp(prof[i][1], prof[i + 1][1], t), _lerp(prof[i][2], prof[i + 1][2], t)
    return prof[-1][1], prof[-1][2]


def torso(part, z0=0.92, z1=1.49, grow=0.0, sx=1.0, sy=1.0, n=9, seg=20, caps=True, ycenter=0.0):
    secs = []
    for i in range(n):
        z = _lerp(z0, z1, i / (n - 1))
        rx, ry = _interp_profile(TORSO, z)
        secs.append(((0, ycenter, z), (rx + grow) * sx, (ry + grow) * sy))
    return loft(part, secs, seg, caps)


def leg(part, side, z0=0.06, z1=0.97, grow=0.0, n=9, seg=14):
    sx = 1 if side == "L" else -1
    prof = [(0.06, 0.05, 0.055), (0.15, 0.047, 0.05), (0.3, 0.068, 0.075), (0.42, 0.062, 0.07), (0.5, 0.066, 0.068), (0.62, 0.08, 0.082), (0.8, 0.098, 0.095), (0.97, 0.105, 0.1)]
    secs = []
    for i in range(n):
        z = _lerp(z0, z1, i / (n - 1))
        rx, ry = _interp_profile(prof, z)
        secs.append(((0.12 * sx + (0.015 * sx) * (1 - z), 0.0 + 0.012 * (0.5 - z) * 0, z), rx + grow, ry + grow))
    return loft(part, secs, seg)


ARM_PATH = [(0.27, 0.0, 1.42), (0.30, 0.0, 1.35), (0.335, 0.0, 1.2), (0.345, -0.005, 1.15), (0.355, -0.03, 1.03), (0.37, -0.06, 0.92)]
ARM_R = [0.07, 0.078, 0.062, 0.056, 0.062, 0.042]


def arm_point(side, t):
    sx = 1 if side == "L" else -1
    f = t * (len(ARM_PATH) - 1)
    i = min(int(f), len(ARM_PATH) - 2)
    u = f - i
    a, b = V(ARM_PATH[i]), V(ARM_PATH[i + 1])
    p = a.lerp(b, u)
    r = _lerp(ARM_R[i], ARM_R[i + 1], u)
    return V((p.x * sx, p.y, p.z)), r


def arm(part, side, t0=0.0, t1=1.0, grow=0.0, n=8, seg=12, flare=0.0):
    secs = []
    for i in range(n):
        t = _lerp(t0, t1, i / (n - 1))
        p, r = arm_point(side, t)
        k = 1.0 + flare * t * t
        secs.append((p, (r + grow) * k, (r + grow) * k))
    return loft(part, secs, seg)


def hand(part, side, scale=1.0, fist=False):
    scale *= 1.3
    sx = 1 if side == "L" else -1
    c = V((0.378 * sx, -0.1, 0.845))
    part.box(c, (0.06 * scale, 0.032 * scale, 0.075 * scale))
    part.sphere(c + V((0, 0, -0.04)), 0.034 * scale, (1.0, 0.7, 0.8))
    for k in range(4):
        x = (k - 1.5) * 0.017 * scale * sx
        a = c + V((x, -0.012, -0.05 * scale))
        b = a + V((0, -0.012 - (0.02 if fist else 0.0), -0.05 * scale + (0.03 if fist else 0.0)))
        part.cyl(a, b, 0.009 * scale, 0.0075 * scale, seg=6)
    th_a = c + V((-0.032 * sx * scale, -0.01, 0.0))
    part.cyl(th_a, th_a + V((-0.012 * sx, -0.03, -0.035)), 0.011 * scale, 0.008 * scale, seg=6)
    return part


def head(part_skin, part_eyes, part_extra=None, w=1.0, jaw=1.0, ycen=0.0, hz=1.69, hair=None):
    """Skull, jaw, nose, brows, lips, ears, neck. Returns nothing; fills the given parts."""
    h = part_skin
    h.sphere((0, ycen + 0.005, hz), 0.128, (0.88 * w, 0.98, 1.08), seg=22, rings=14)           # cranium
    h.sphere((0, ycen - 0.045, hz - 0.07), 0.09 * jaw, (0.92 * w, 0.95, 0.85), seg=16, rings=10)  # jaw / chin mass
    h.sphere((0, ycen - 0.125, hz - 0.012), 0.024, (0.8, 1.2, 1.0), seg=10, rings=7)            # nose tip
    h.cyl((0, ycen - 0.1, hz + 0.03), (0, ycen - 0.12, hz - 0.01), 0.015, 0.02, seg=8)           # nose bridge
    h.sphere((0, ycen - 0.108, hz - 0.058), 0.026, (1.7, 0.6, 0.4), seg=10, rings=6)           # lips
    for s in (1, -1):
        h.sphere((0.118 * w * s, ycen, hz - 0.01), 0.032, (0.35, 0.8, 1.1), seg=8, rings=6)     # ears
        h.sphere((0.06 * s, ycen - 0.093, hz + 0.022), 0.034, (1.0, 0.45, 0.6), seg=10, rings=6)  # brow ridge / eye socket
        part_eyes.sphere((0.05 * s, ycen - 0.108, hz + 0.015), 0.015, (1.4, 0.5, 0.8), seg=10, rings=6)
    h.cyl((0, 0, 1.5), (0, 0, hz - 0.08), 0.058, 0.07, seg=12)
    return h
