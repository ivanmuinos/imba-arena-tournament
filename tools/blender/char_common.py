"""Skeleton + animation set shared by the five class characters."""
import math
from lib import *

SK = {
    "root": (None, (0, 0, 0), (0, 0, 0.1)),
    "hips": ("root", (0, 0, 0.95), (0, 0, 1.05)),
    "spine": ("hips", (0, 0, 1.05), (0, 0, 1.28)),
    "chest": ("spine", (0, 0, 1.28), (0, 0, 1.48)),
    "neck": ("chest", (0, 0, 1.48), (0, 0, 1.56)),
    "head": ("neck", (0, 0, 1.56), (0, 0, 1.86)),
}
for side, sx in (("L", 1), ("R", -1)):
    SK[f"upper_arm.{side}"] = ("chest", (0.27 * sx, 0, 1.42), (0.34 * sx, 0, 1.15))
    SK[f"forearm.{side}"] = (f"upper_arm.{side}", (0.34 * sx, 0, 1.15), (0.37 * sx, -0.06, 0.92))
    SK[f"hand.{side}"] = (f"forearm.{side}", (0.37 * sx, -0.06, 0.92), (0.38 * sx, -0.1, 0.8))
    SK[f"thigh.{side}"] = ("hips", (0.12 * sx, 0, 0.95), (0.13 * sx, 0, 0.5))
    SK[f"shin.{side}"] = (f"thigh.{side}", (0.13 * sx, 0, 0.5), (0.13 * sx, 0.02, 0.08))
    SK[f"foot.{side}"] = (f"shin.{side}", (0.13 * sx, 0.02, 0.08), (0.13 * sx, -0.16, 0.03))
SK["cape1"] = ("chest", (0, 0.15, 1.46), (0, 0.2, 1.16))
SK["cape2"] = ("cape1", (0, 0.2, 1.16), (0, 0.25, 0.86))
SK["cape3"] = ("cape2", (0, 0.25, 0.86), (0, 0.28, 0.56))
SK["skirt1"] = ("hips", (0, 0, 0.98), (0, 0, 0.7))
SK["skirt2"] = ("skirt1", (0, 0, 0.7), (0, 0, 0.4))
SK["skirt3"] = ("skirt2", (0, 0, 0.4), (0, 0, 0.1))
# Held items live on their own bones so weapons can have idle motion (sway, spin).
SK["weapon.R"] = ("hand.R", (-0.38, -0.1, 0.84), (-0.38, -0.1, 1.2))
SK["weapon.L"] = ("hand.L", (0.38, -0.1, 0.84), (0.38, -0.1, 1.2))
SK["orb"] = ("weapon.R", (-0.38, -0.1, 1.9), (-0.38, -0.1, 2.05))


def sstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def skirt_weights(co):
    z = co.z
    w3 = sstep(0.45, 0.15, z)
    w2 = sstep(0.8, 0.5, z) * (1 - w3)
    w1 = 1 - w2 - w3
    return {"skirt1": w1, "skirt2": w2, "skirt3": w3} if z < 0.98 else {"hips": 1.0}


def cape_weights(co):
    z = co.z
    w3 = sstep(0.95, 0.6, z)
    w2 = sstep(1.3, 0.95, z) * (1 - w3)
    w1 = 1 - w2 - w3
    return {"cape1": w1, "cape2": w2, "cape3": w3}


def make_rig(name):
    rig = Rig(name)
    rig.build(SK)
    return rig


def R(x=0.0, y=0.0, z=0.0):
    return (x, y, z)


def animations(rig, style=None):
    """idle, run, cast, attack, hit, death, stun. `style` tweaks: two_hand (cast with both arms), ranged (attack = draw/release)."""
    style = style or {}
    ranged = style.get("ranged", False)
    robe = style.get("robe", False)

    def sway(a, s=1.0):
        return {"cape1": R(0.05 * a * s), "cape2": R(0.08 * a * s), "cape3": R(0.1 * a * s),
                "skirt1": R(0.02 * a * s), "skirt2": R(0.04 * a * s), "skirt3": R(0.06 * a * s)}

    def merge(*ds):
        o = {}
        for d in ds:
            o.update(d)
        return o

    # idle: breathing + weapon sway, 48 frames loop
    def idle(a, w):
        return merge({
            "chest": R(-0.02 * a), "head": R(0.03 * a, 0, 0.04 * w), "spine": R(0.01 * a),
            "upper_arm.L": R(0.04 * a, 0, -0.03 * a), "upper_arm.R": R(-0.03 * a, 0, 0.03 * a),
            "forearm.L": R(-0.12 - 0.05 * a), "forearm.R": R(-0.12 - 0.05 * a),
            "hips": (R(), (0, 0, -0.012 * a)), "weapon.R": R(0.03 * w, 0, 0.02 * w), "orb": R(0, 0.3 * w, 0),
        }, sway(a, 0.5))
    rig.animation("idle", 48, {1: idle(0, -1), 13: idle(1, 0), 25: idle(0, 1), 37: idle(1, 0), 49: idle(0, -1)})

    # run: 24 frames
    def run(ph):
        s = math.sin(ph)
        c = math.cos(ph)
        d = {
            "hips": (R(0, 0, 0.05 * s), (0, 0, -0.035 * abs(c))), "spine": R(0.12, 0, -0.08 * s), "chest": R(0.05, 0, 0.1 * s), "head": R(-0.1, 0, -0.04 * s),
            "thigh.L": R(-0.75 * s), "thigh.R": R(0.75 * s),
            "shin.L": R(0.15 + 0.7 * max(0.0, -c * 0 + math.sin(ph + 1.2))), "shin.R": R(0.15 + 0.7 * max(0.0, math.sin(ph + 1.2 + math.pi))),
            "foot.L": R(0.15 * s), "foot.R": R(-0.15 * s),
            "upper_arm.L": R(0.6 * s), "upper_arm.R": R(-0.6 * s),
            "forearm.L": R(-0.9 - 0.2 * s), "forearm.R": R(-0.9 + 0.2 * s),
            "weapon.R": R(0.1 * s), "orb": R(0, 0.3 * s, 0),
        }
        d.update({"cape1": R(0.35 + 0.1 * s), "cape2": R(0.3 + 0.12 * math.sin(ph - 0.6)), "cape3": R(0.25 + 0.15 * math.sin(ph - 1.2)),
                  "skirt1": R(-0.05 + 0.05 * s), "skirt2": R(-0.08 + 0.07 * math.sin(ph - 0.5)), "skirt3": R(-0.1 + 0.08 * math.sin(ph - 1.0))})
        return d
    rig.animation("run", 24, {1 + i * 4: run(i * math.pi / 3) for i in range(7)})

    # cast: raise arms, glow, release
    def cast(t):
        up = sstep(0, 1, t)
        return merge({
            "upper_arm.R": R(-1.5 * up, 0, -0.2 * up), "forearm.R": R(-0.5 * up), "upper_arm.L": R(-1.1 * up, 0, 0.5 * up), "forearm.L": R(-0.6 * up),
            "chest": R(-0.15 * up), "head": R(-0.2 * up), "spine": R(-0.1 * up), "hips": (R(), (0, 0, 0.02 * up)),
            "weapon.R": R(-0.2 * up), "orb": R(0, 0.9 * up, 0),
        }, sway(-up * 1.5))
    rig.animation("cast", 30, {1: cast(0), 8: cast(1), 22: cast(1), 31: cast(0)})

    # attack: wind-up, strike, recover (ranged: draw and release)
    if ranged:
        def atk(t):
            return merge({
                "upper_arm.L": R(-1.45 * t, 0, 0.1 * t), "forearm.L": R(-0.05 * t),
                "upper_arm.R": R(-1.35 * t, 0, -0.9 * t), "forearm.R": R(-1.8 * t, 0, 0), "chest": R(0, 0, 0.35 * t), "head": R(0, 0, -0.3 * t), "spine": R(0, 0, 0.1 * t),
            }, sway(0.5 * t))
        rig.animation("attack", 20, {1: atk(0), 9: atk(1), 12: atk(0.1), 21: atk(0)})
    else:
        def atk(t, strike):
            w = t * (1 - strike)
            s = strike
            return merge({
                "upper_arm.R": R(1.1 * w - 1.5 * s, 0, -0.5 * w + 0.3 * s), "forearm.R": R(-0.8 * w - 0.2 * s),
                "chest": R(0.1 * w - 0.2 * s, 0, 0.5 * w - 0.6 * s), "spine": R(0, 0, 0.25 * w - 0.3 * s), "head": R(0, 0, -0.2 * w + 0.3 * s),
                "weapon.R": R(0.5 * w - 0.5 * s), "hips": (R(0, 0, 0.1 * w - 0.2 * s), (0, -0.05 * s, 0)),
                "thigh.L": R(-0.3 * s), "thigh.R": R(0.2 * s), "upper_arm.L": R(-0.4 * s, 0, 0.6 * s),
            }, sway(0.6 * s))
        rig.animation("attack", 20, {1: atk(0, 0), 6: atk(1, 0), 11: atk(0, 1), 21: atk(0, 0)})

    # hit: recoil
    def hit(k):
        return merge({"chest": R(0.35 * k), "head": R(0.35 * k), "spine": R(0.2 * k), "upper_arm.L": R(0.4 * k), "upper_arm.R": R(0.4 * k),
                      "hips": (R(0.1 * k), (0, 0.06 * k, 0))}, sway(1.0 * k))
    rig.animation("hit", 12, {1: hit(0), 4: hit(1), 13: hit(0)})

    # death: fall backwards and stay down
    def death(t):
        e = sstep(0, 1, t)
        return merge({
            "root": (R(-1.5 * e), (0, 0.15 * e, -0.08 * e)), "head": R(0.3 * e), "upper_arm.L": R(-0.2 * e, 0, 0.9 * e), "upper_arm.R": R(-0.2 * e, 0, -0.9 * e),
            "thigh.L": R(-0.2 * e, 0, 0.2 * e), "thigh.R": R(-0.1 * e, 0, -0.2 * e), "shin.L": R(0.3 * e),
        }, sway(0.5 * e))
    rig.animation("death", 36, {1: death(0), 14: death(0.6), 36: death(1)})

    # stun: dizzy wobble
    def stun(a):
        return merge({"head": R(0.2, 0.2 * a, 0.35 * a), "chest": R(0.1, 0, -0.1 * a), "spine": R(0.12, 0, 0.1 * a), "upper_arm.L": R(0.2, 0, 0.2),
                      "upper_arm.R": R(0.2, 0, -0.2), "forearm.L": R(-0.3), "forearm.R": R(-0.3), "hips": (R(0, 0, 0.05 * a), (0, 0, -0.03))}, sway(a * 0.6))
    rig.animation("stun", 30, {1: stun(0), 8: stun(1), 16: stun(0), 24: stun(-1), 31: stun(0)})
    rig.reset_pose()


# ---- soft skinning weights for lofted body parts -------------------------------------------
def w_torso(co):
    z = co.z
    if z < 1.0:
        return {"hips": 1.0}
    if z < 1.16:
        t = sstep(1.0, 1.16, z)
        return {"hips": 1 - t, "spine": t}
    if z < 1.3:
        t = sstep(1.16, 1.3, z)
        return {"spine": 1 - t, "chest": t}
    return {"chest": 1.0}


def w_arm(side):
    def f(co):
        z = co.z
        t = sstep(1.22, 1.08, z)       # 0 upper arm -> 1 forearm
        t2 = sstep(0.95, 0.88, z)      # -> hand
        return {f"upper_arm.{side}": 1 - t, f"forearm.{side}": t * (1 - t2), f"hand.{side}": t2}
    return f


def w_leg(side):
    def f(co):
        z = co.z
        t = sstep(0.56, 0.44, z)
        t2 = sstep(0.12, 0.05, z)
        if z > 0.9:
            t_h = sstep(0.9, 1.0, z)
            return {f"thigh.{side}": 1 - t_h, "hips": t_h}
        return {f"thigh.{side}": 1 - t, f"shin.{side}": t * (1 - t2), f"foot.{side}": t2}
    return f
