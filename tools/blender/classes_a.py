"""Mage and Priest (robed casters)."""
import math
from lib import *
from char_common import *
from dress import *
import anatomy as A


def _interp(profile, v):
    n = len(profile) - 1
    f = v * n
    i = min(int(f), n - 1)
    t = f - i
    t = t * t * (3 - 2 * t)
    return (profile[i][0] + (profile[i + 1][0] - profile[i][0]) * t, profile[i][1] + (profile[i + 1][1] - profile[i][1]) * t)


def lathe(part, profile, nu=32, wave=0.0, folds=0.0, phase=0.0):
    """Robe surface of revolution (z, radius bottom->top) with a wavy hem and vertical folds."""
    n = len(profile) - 1

    def fn(u, v):
        z, r = _interp(profile, v)
        a = 2 * math.pi * u
        hem = (1 - v) ** 2
        rr = r * (1 + wave * hem * math.sin(5 * a + phase) + folds * hem * math.sin(13 * a))
        zz = z + wave * hem * 0.05 * math.sin(7 * a)
        return V((rr * math.sin(a), -rr * math.cos(a) * 0.88, zz))
    part.grid(fn, nu, n * 3)
    return part


def build_mage(rig):
    robe = mat("mage_robe", hexc("#5a34b8"), 0.7)
    robe_d = mat("mage_robe_dark", hexc("#2a1560"), 0.8)
    skin = mat("skin_fair", hexc("#f2cba4"), 0.5)
    beard = mat("mage_beard", hexc("#eceaf5"), 0.9)
    leather = mat("mage_leather", hexc("#6a4426"), 0.65)
    gold = mat("mage_gold", hexc("#e8b040"), 0.28, 1.0)
    wood = mat("mage_wood", hexc("#5a3a22"), 0.75)
    rune = mat("mage_rune", hexc("#ff8a2a"), 0.4, 0, emit=hexc("#ff7a10"), emit_strength=4.0)
    eyes = mat("mage_eyes", hexc("#9fe8ff"), 0.3, 0, emit=hexc("#6fd8ff"), emit_strength=6.0)
    orb = mat("mage_orb", hexc("#ff9a30"), 0.2, 0, emit=hexc("#ff6a10"), emit_strength=8.0)
    team = mat("TeamColor", (1, 1, 1), 0.6)
    parts = head_parts("mage", skin, eyes, w=0.95)
    b = P("mage_beard", beard, "head", bevel=0, subsurf=1)
    b.tube([(0, -0.1, 1.62), (0.0, -0.15, 1.5), (0, -0.16, 1.36), (0, -0.12, 1.24)], [0.085, 0.08, 0.055, 0.012], seg=12)
    for s in (1, -1):
        b.tube([(0.07 * s, -0.09, 1.66), (0.085 * s, -0.12, 1.6), (0.04 * s, -0.15, 1.56)], [0.03, 0.04, 0.045], seg=8)
    parts.append(b)
    hair = P("mage_hair", beard, "head", bevel=0, subsurf=1)
    hair.sphere((0, 0.06, 1.68), 0.12, (1.05, 0.9, 1.0))
    for s in (1, -1):
        hair.box((0.062 * s, -0.115, 1.74), (0.075, 0.025, 0.02), (0, 0, -0.25 * s))
    parts.append(hair)
    hat = P("mage_hat", robe_d, "head", bevel=0.01, subsurf=1)
    hat.cyl((0, 0, 1.775), (0, 0, 1.79), 0.38, 0.37, seg=32)
    hat.tube([(0, 0, 1.78), (0, 0.0, 1.95), (0, 0.04, 2.1), (0, 0.14, 2.24), (0, 0.32, 2.27), (0, 0.42, 2.17)], [0.185, 0.15, 0.105, 0.065, 0.032, 0.008], seg=16)
    parts.append(hat)
    band = P("mage_hatband", gold, "head", bevel=0.004, subsurf=0)
    band.torus((0, 0, 1.805), 0.185, 0.016, seg=32, rings=6)
    band.box((0, -0.19, 1.805), (0.06, 0.014, 0.06))
    parts.append(band)
    hr = P("mage_hatrune", rune, "head", bevel=0, subsurf=0)
    hr.sphere((0, -0.2, 1.805), 0.014, seg=8, rings=5)
    parts.append(hr)

    sk = P("mage_skirt", robe, "hips", bevel=0, subsurf=1, solid=0.03)
    lathe(sk, [(0.05, 0.56), (0.35, 0.42), (0.7, 0.31), (0.97, 0.205), (1.03, 0.19)], wave=0.08, folds=0.05)
    sk.weights = skirt_weights
    parts.append(sk)
    trim = P("mage_hem_trim", rune, "hips", bevel=0, subsurf=0, solid=0.012)
    lathe(trim, [(0.07, 0.552), (0.095, 0.545)], wave=0.08, folds=0.05)
    trim.weights = skirt_weights
    parts.append(trim)
    parts.append(torso_part("mage_torso", robe, 0.03, 0.98, 1.49, bevel=0.006, subsurf=1))
    for s, side in ((1, "L"), (-1, "R")):
        parts.append(arm_part("mage_sleeve", robe, side, 0.0, 0.98, 0.022, flare=1.1, bevel=0.005, subsurf=1))
        parts.append(hand_part("mage_hand", skin, side))
        cuff = arm_part("mage_cuff", rune, side, 0.93, 0.975, 0.014, flare=1.1, bevel=0, subsurf=0)
        parts.append(cuff)
        boot = leg_part("mage_boot", leather, side, 0.06, 0.26, 0.012, bevel=0.004, subsurf=1)
        parts.append(boot)
    mantle = P("mage_mantle", robe_d, "chest", bevel=0.01, subsurf=1)
    mantle.sphere((0, 0.01, 1.455), 0.3, (1.12, 0.8, 0.36), seg=24, rings=10)
    mantle.torus((0, 0, 1.5), 0.15, 0.055, seg=24)
    for s in (1, -1):
        mantle.sphere((0.27 * s, 0, 1.4), 0.1, (1, 1, 0.9))
    mantle.weights = w_torso
    parts.append(mantle)
    mtr = P("mage_mantle_trim", gold, "chest", bevel=0.003, subsurf=0)
    mtr.torus((0, 0.01, 1.455), 0.3, 0.013, seg=32, rings=6)
    mtr.box((0, -0.2, 1.42), (0.05, 0.02, 0.07))
    parts.append(mtr)
    gem = P("mage_gem", rune, "chest", bevel=0, subsurf=0)
    gem.sphere((0, -0.215, 1.4), 0.028, (1, 0.5, 1.4), seg=8, rings=5)
    parts.append(gem)
    belt = P("mage_belt", leather, "spine", bevel=0.004, subsurf=0)
    belt.torus((0, 0, 1.02), 0.2, 0.024, seg=28, rings=6)
    belt.box((0.18, -0.1, 0.98), (0.09, 0.07, 0.11)); belt.box((-0.19, -0.04, 0.98), (0.07, 0.08, 0.1))
    belt.cyl((-0.1, -0.2, 0.95), (-0.1, -0.2, 0.75), 0.012)
    parts.append(belt)
    buckle = P("mage_buckle", gold, "spine", bevel=0.003, subsurf=0)
    buckle.box((0, -0.215, 1.02), (0.07, 0.015, 0.06))
    parts.append(buckle)
    sash = P("mage_sash", team, "hips", bevel=0, subsurf=1, solid=0.014)
    sash.grid(lambda u, v: V((0.13 + 0.04 * u - 0.03 * v, -0.215 - 0.02 * math.sin(v * 3) - 0.1 * v * v, 1.0 - v * 0.6)), 3, 8)
    sash.weights = skirt_weights
    parts.append(sash)
    cape = P("mage_cape", robe_d, "chest", bevel=0, subsurf=1, solid=0.02)
    cape.grid(lambda u, v: V((-0.2 + 0.4 * u + (u - 0.5) * 0.2 * v, 0.14 + 0.15 * v + 0.03 * math.sin(u * 6), 1.46 - 0.95 * v)), 8, 10)
    cape.weights = cape_weights
    parts.append(cape)

    staff = P("mage_staff", wood, "weapon.R", bevel=0.004, subsurf=1)
    staff.tube([(-0.38, -0.1, 0.25), (-0.38, -0.1, 1.0), (-0.37, -0.1, 1.7), (-0.38, -0.1, 1.9)], [0.022, 0.026, 0.03, 0.04], seg=10)
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        staff.tube([(-0.38, -0.1, 1.88), (-0.38 + 0.09 * math.cos(a), -0.1 + 0.09 * math.sin(a), 1.98), (-0.38 + 0.07 * math.cos(a), -0.1 + 0.07 * math.sin(a), 2.1)], [0.02, 0.014, 0.006], seg=6)
    parts.append(staff)
    sg = P("mage_staff_gold", gold, "weapon.R", bevel=0.003, subsurf=0)
    sg.cyl((-0.38, -0.1, 0.22), (-0.38, -0.1, 0.34), 0.03, 0.026)
    sg.torus((-0.38, -0.1, 1.2), 0.03, 0.01, seg=14, rings=5)
    sg.torus((-0.38, -0.1, 1.84), 0.05, 0.012, seg=16, rings=5)
    parts.append(sg)
    ob = P("mage_orb", orb, "orb", bevel=0, subsurf=1)
    ob.sphere((-0.38, -0.1, 2.04), 0.085, seg=16, rings=10)
    parts.append(ob)
    ring = P("mage_orb_ring", rune, "orb", bevel=0, subsurf=0)
    ring.torus((-0.38, -0.1, 2.04), 0.14, 0.008, rot=(0.5, 0.3, 0), seg=26, rings=5)
    ring.torus((-0.38, -0.1, 2.04), 0.17, 0.006, rot=(-0.6, 0.2, 0.5), seg=26, rings=5)
    parts.append(ring)
    return parts


def build_priest(rig):
    white = mat("priest_cloth", hexc("#efe8d6"), 0.7)
    cream = mat("priest_cloth2", hexc("#cfc2a6"), 0.75)
    gold = mat("priest_gold", hexc("#ffd36a"), 0.25, 1.0)
    holy = mat("priest_holy", hexc("#fff0b0"), 0.3, 0, emit=hexc("#ffd060"), emit_strength=5.0)
    skin = mat("skin_tan", hexc("#dba57c"), 0.5)
    hair = mat("priest_hair", hexc("#8a5230"), 0.7)
    eyes = mat("priest_eyes", hexc("#fff0b0"), 0.3, 0, emit=hexc("#ffd060"), emit_strength=5.0)
    leather = mat("priest_leather", hexc("#8a6038"), 0.7)
    team = mat("TeamColor", (1, 1, 1), 0.6)
    parts = head_parts("priest", skin, eyes, w=0.92, jaw=0.9)
    hr = P("priest_hair", hair, "head", bevel=0, subsurf=1)
    hr.sphere((0, 0.04, 1.72), 0.13, (1, 1.05, 0.95))
    hr.tube([(0, 0.1, 1.7), (0, 0.16, 1.5), (0.0, 0.17, 1.3)], [0.08, 0.06, 0.02], seg=8)
    parts.append(hr)
    mit = P("priest_mitre", white, "head", bevel=0.006, subsurf=1)
    mit.cyl((0, 0, 1.79), (0, 0, 1.93), 0.135, 0.125, seg=20)
    mit.cyl((0, 0, 1.93), (0, 0, 2.12), 0.125, 0.05, seg=20)
    mit.sphere((0, 0, 2.13), 0.05)
    parts.append(mit)
    mg = P("priest_mitre_gold", gold, "head", bevel=0.003, subsurf=0)
    mg.torus((0, 0, 1.8), 0.135, 0.015, seg=24, rings=6)
    mg.box((0, -0.125, 1.97), (0.016, 0.012, 0.11)); mg.box((0, -0.125, 1.98), (0.065, 0.012, 0.018))
    parts.append(mg)
    halo = P("priest_halo", holy, "head", bevel=0, subsurf=0)
    halo.torus((0, 0.07, 2.03), 0.27, 0.012, rot=(math.radians(80), 0, 0), seg=40, rings=6)
    parts.append(halo)
    sk = P("priest_skirt", white, "hips", bevel=0, subsurf=1, solid=0.03)
    lathe(sk, [(0.05, 0.54), (0.35, 0.4), (0.7, 0.3), (0.97, 0.205), (1.03, 0.19)], wave=0.05, folds=0.04)
    sk.weights = skirt_weights
    parts.append(sk)
    tr = P("priest_hem", gold, "hips", bevel=0, subsurf=0, solid=0.012)
    lathe(tr, [(0.065, 0.532), (0.1, 0.524)], wave=0.05, folds=0.04)
    tr.weights = skirt_weights
    parts.append(tr)
    parts.append(torso_part("priest_torso", white, 0.03, 0.98, 1.49, bevel=0.006, subsurf=1))
    stole = P("priest_stole", team, "spine", bevel=0, subsurf=1, solid=0.02)
    stole.grid(lambda u, v: V((-0.08 + 0.16 * u, -0.215 - 0.02 * math.sin(v * 3) - 0.12 * v * v, 1.5 - 1.2 * v)), 3, 12)
    stole.weights = lambda co: skirt_weights(co) if co.z < 0.98 else w_torso(co)
    parts.append(stole)
    stg = P("priest_stole_gold", gold, "spine", bevel=0.003, subsurf=0)
    stg.box((0, -0.24, 1.28), (0.055, 0.012, 0.055)); stg.box((0, -0.26, 1.12), (0.035, 0.012, 0.035))
    parts.append(stg)
    for s, side in ((1, "L"), (-1, "R")):
        w = P(f"priest_wing{side}", cream, "chest", bevel=0.004, subsurf=1)
        for k in range(5):
            a = 0.25 * k
            w.sphere((0.3 * s + 0.045 * k * s, 0.05 + 0.03 * k, 1.55 - 0.05 * k), 0.07 + 0.01 * (4 - k), (0.5, 1.5 + 0.2 * k, 0.55), rot=(0.2, 0, -0.5 * s * (0.5 + a)))
        w.weights = w_torso
        parts.append(w)
        pg = P(f"priest_pauld{side}", gold, "chest", bevel=0.004, subsurf=1)
        pg.sphere((0.29 * s, 0, 1.44), 0.105, (1, 1, 0.7))
        parts.append(pg)
        parts.append(arm_part("priest_sleeve", white, side, 0.0, 0.98, 0.02, flare=0.7, bevel=0.005, subsurf=1))
        parts.append(arm_part("priest_bracer", gold, side, 0.62, 0.9, 0.03, bevel=0.004, subsurf=1))
        parts.append(hand_part("priest_hand", skin, side))
        parts.append(leg_part("priest_boot", leather, side, 0.06, 0.26, 0.012, bevel=0.004, subsurf=1))
    belt = P("priest_belt", gold, "spine", bevel=0.004, subsurf=0)
    belt.torus((0, 0, 1.02), 0.2, 0.022, seg=28, rings=6)
    belt.sphere((0, -0.21, 1.02), 0.038, (1, 0.5, 1))
    parts.append(belt)
    cp = P("priest_cape", white, "chest", bevel=0, subsurf=1, solid=0.02)
    cp.grid(lambda u, v: V((-0.2 + 0.4 * u + (u - 0.5) * 0.2 * v, 0.15 + 0.12 * v + 0.03 * math.sin(u * 6), 1.44 - 0.85 * v)), 8, 10)
    cp.weights = cape_weights
    parts.append(cp)
    st = P("priest_staff", gold, "weapon.R", bevel=0.004, subsurf=1)
    st.tube([(-0.38, -0.1, 0.2), (-0.38, -0.1, 1.0), (-0.38, -0.1, 1.75)], [0.022, 0.025, 0.03], seg=10)
    st.torus((-0.38, -0.1, 1.95), 0.15, 0.022, rot=(math.radians(90), 0, 0), seg=28, rings=7)
    for k in range(10):
        a = k * 2 * math.pi / 10
        st.cyl((-0.38 + 0.17 * math.cos(a), -0.1, 1.95 + 0.17 * math.sin(a)), (-0.38 + 0.27 * math.cos(a), -0.1, 1.95 + 0.27 * math.sin(a)), 0.02, 0.004, seg=6)
    parts.append(st)
    core = P("priest_core", holy, "orb", bevel=0, subsurf=1)
    core.sphere((-0.38, -0.1, 1.95), 0.09, seg=16, rings=10)
    parts.append(core)
    return parts
