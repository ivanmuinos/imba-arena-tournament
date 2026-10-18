"""Part factories that wrap the anatomy lofts with the right skinning."""
from lib import *
from char_common import *
import anatomy as A


def P(name, material, bone, **kw):
    solid = kw.pop("solid", 0.0)
    p = Part(name, material, bone, **kw)
    p.solid = solid
    return p


def finish(rig, parts):
    for p in parts:
        o = p.build(solidify=getattr(p, "solid", 0.0))
        rig.bind(o, p.bone, p.weights)


def torso_part(name, m, grow=0.0, z0=0.92, z1=1.49, sx=1.0, sy=1.0, **kw):
    p = P(name, m, "chest", **kw)
    A.torso(p, z0, z1, grow, sx, sy)
    p.weights = w_torso
    return p


def arm_part(name, m, side, t0=0.0, t1=1.0, grow=0.0, flare=0.0, **kw):
    p = P(f"{name}{side}", m, f"upper_arm.{side}", **kw)
    A.arm(p, side, t0, t1, grow, flare=flare)
    p.weights = w_arm(side)
    return p


def leg_part(name, m, side, z0=0.06, z1=0.97, grow=0.0, **kw):
    p = P(f"{name}{side}", m, f"thigh.{side}", **kw)
    A.leg(p, side, z0, z1, grow)
    p.weights = w_leg(side)
    return p


def hand_part(name, m, side, scale=1.0, fist=False, **kw):
    p = P(f"{name}{side}", m, f"hand.{side}", **kw)
    A.hand(p, side, scale, fist)
    return p


def head_parts(prefix, skin, eyes, w=1.0, jaw=1.0, hz=1.69):
    h = P(prefix + "_head", skin, "head", bevel=0, subsurf=1)
    e = P(prefix + "_eyes", eyes, "head", bevel=0, subsurf=0)
    A.head(h, e, w=w, jaw=jaw, hz=hz)
    return [h, e]


def shell(part, center, r, scale, cut):
    """Sphere shell with the faces for which cut(face_center) is True removed (open hood / helm front)."""
    part.sphere(center, r, scale, seg=24, rings=16)
    import bmesh
    dele = [f for f in part.bm.faces if cut(f.calc_center_median())]
    bmesh.ops.delete(part.bm, geom=dele, context="FACES")
    return part
