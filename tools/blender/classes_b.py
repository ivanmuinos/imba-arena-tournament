"""Hunter, Warrior and Rogue."""
import math, random
from lib import *
from char_common import *
from dress import *
import anatomy as A


def open_hood(name, mat_, center, r, scale, front_open=0.55, zlo=-0.12, zhi=0.12):
    """Hood shell: sphere with an opening in the front for the face."""
    p = P(name, mat_, "head", bevel=0, subsurf=1, solid=0.02)
    cx, cy, cz = center
    shell(p, center, r, scale, lambda c: c.y < cy - r * scale[1] * 0.45 and abs(c.x - cx) < r * scale[0] * front_open and zlo < c.z - cz < zhi + 0.06)
    return p


def legs_set(parts, pant, boot, side_pad=None, boot_top=0.3, prefix="", thigh_grow=0.012):
    for side in ("L", "R"):
        parts.append(leg_part(prefix + "pants", pant, side, 0.3, 0.97, thigh_grow, bevel=0.005, subsurf=1))
        parts.append(leg_part(prefix + "boots", boot, side, 0.06, boot_top, 0.02, bevel=0.005, subsurf=1))
        if side_pad is not None:
            k = P(f"{prefix}knee{side}", side_pad, f"thigh.{side}", bevel=0.005, subsurf=1)
            s = 1 if side == "L" else -1
            k.sphere((0.133 * s, -0.062, 0.5), 0.068, (1, 0.7, 1))
            parts.append(k)


def build_hunter(rig):
    leather = mat("hunter_leather", hexc("#7a5230"), 0.65)
    leather_d = mat("hunter_leather_d", hexc("#3e2a1a"), 0.7)
    green = mat("hunter_cloth", hexc("#3a7a34"), 0.85)
    green_d = mat("hunter_cloth_d", hexc("#244a22"), 0.9)
    fur = mat("hunter_fur", hexc("#d8c294"), 0.95)
    skin = mat("skin_olive", hexc("#d09a72"), 0.5)
    wood = mat("hunter_wood", hexc("#9a6a34"), 0.55)
    metal = mat("hunter_metal", hexc("#a8aeb8"), 0.3, 1.0)
    glow = mat("hunter_glow", hexc("#9fff6a"), 0.3, 0, emit=hexc("#7dff3a"), emit_strength=5.0)
    ember = mat("hunter_ember", hexc("#ff8a2a"), 0.3, 0, emit=hexc("#ff6a10"), emit_strength=5.0)
    eyes = mat("hunter_eyes", hexc("#b8ff7a"), 0.3, 0, emit=hexc("#9dff4a"), emit_strength=4.0)
    team = mat("TeamColor", (1, 1, 1), 0.7)
    parts = head_parts("hunter", skin, eyes, w=0.95)
    # open hood with a long tail, face mask below the eyes
    hood = open_hood("hunter_hood", green, (0, 0.035, 1.72), 0.165, (1.0, 1.1, 1.06))
    parts.append(hood)
    tail = P("hunter_hood_tail", green, "head", bevel=0, subsurf=1)
    tail.tube([(0, 0.1, 1.85), (0, 0.22, 1.9), (0, 0.38, 1.82), (0, 0.5, 1.66)], [0.09, 0.065, 0.04, 0.008], seg=10)
    parts.append(tail)
    trim = P("hunter_hood_trim", team, "head", bevel=0, subsurf=0)
    trim.torus((0, -0.07, 1.72), 0.15, 0.011, rot=(math.radians(112), 0, 0), seg=28, rings=5)
    parts.append(trim)
    mask = P("hunter_mask", green_d, "head", bevel=0, subsurf=1)
    mask.sphere((0, -0.08, 1.625), 0.088, (1.12, 0.78, 0.7))
    parts.append(mask)
    # tunic + leather armour
    parts.append(torso_part("hunter_tunic", green, 0.012, 0.92, 1.49, bevel=0.005, subsurf=1))
    parts.append(torso_part("hunter_armor", leather, 0.032, 1.1, 1.44, sx=1.0, sy=1.05, bevel=0.007, subsurf=1))
    parts.append(torso_part("hunter_harness", leather_d, 0.04, 0.98, 1.1, bevel=0.005, subsurf=1))
    cowl = P("hunter_cowl", green, "chest", bevel=0.008, subsurf=1)
    cowl.sphere((0, 0.01, 1.47), 0.27, (1.12, 0.78, 0.42), seg=22, rings=8)
    cowl.weights = w_torso
    parts.append(cowl)
    fr = P("hunter_fur", fur, "chest", bevel=0, subsurf=1)
    rnd = random.Random(3)
    for k in range(22):
        a = 2 * math.pi * k / 22
        fr.sphere((0.28 * math.cos(a), 0.2 * math.sin(a) * 0.95, 1.5 + rnd.uniform(-0.02, 0.035)), 0.065 + rnd.uniform(0, 0.02), (1, 1, 0.8), seg=8, rings=6)
    fr.weights = w_torso
    parts.append(fr)
    strap = P("hunter_strap", leather_d, "chest", bevel=0.004, subsurf=0)
    strap.box((0.04, -0.17, 1.28), (0.045, 0.03, 0.7), (0, 0.5, 0))
    strap.box((0, -0.19, 1.3), (0.08, 0.02, 0.07))
    strap.weights = w_torso
    parts.append(strap)
    band = P("hunter_band", team, "spine", bevel=0.004, subsurf=0)
    band.torus((0, 0, 1.05), 0.185, 0.024, rot=(0.08, 0, 0), seg=28, rings=6)
    band.weights = w_torso
    parts.append(band)
    belt = P("hunter_belt", leather_d, "spine", bevel=0.004, subsurf=0)
    belt.torus((0, 0, 0.97), 0.18, 0.022, seg=28, rings=6)
    belt.box((0.19, -0.05, 0.91), (0.08, 0.1, 0.12)); belt.box((-0.19, -0.05, 0.91), (0.08, 0.1, 0.12))
    parts.append(belt)
    bk = P("hunter_buckle", metal, "spine", bevel=0.003, subsurf=0)
    bk.box((0, -0.19, 0.97), (0.055, 0.015, 0.05))
    bk.cyl((0.12, -0.18, 0.88), (0.12, -0.19, 0.7), 0.014, 0.01)
    parts.append(bk)
    cl = P("hunter_cloak", green, "chest", bevel=0, subsurf=1, solid=0.02)
    cl.grid(lambda u, v: V((-0.27 + 0.54 * u + (u - 0.5) * 0.22 * v, 0.17 + 0.13 * v + 0.03 * math.sin(u * 7), 1.5 - 1.05 * v)), 10, 10)
    cl.weights = cape_weights
    parts.append(cl)
    cl2 = P("hunter_cloak_lining", team, "chest", bevel=0, subsurf=0, solid=0.006)
    cl2.grid(lambda u, v: V((-0.3 + 0.6 * u + (u - 0.5) * 0.2, 0.3 + 0.03 * math.sin(u * 7) - 0.012, 0.5 + 0.1 * (1 - v))), 10, 1)
    cl2.weights = cape_weights
    parts.append(cl2)
    for side in ("L", "R"):
        parts.append(arm_part("hunter_sleeve", green, side, 0.0, 0.95, 0.012, bevel=0.005, subsurf=1))
        parts.append(arm_part("hunter_bracer", leather, side, 0.64, 0.92, 0.026, bevel=0.005, subsurf=1))
        parts.append(hand_part("hunter_glove", leather_d, side))
    legs_set(parts, green_d, leather, leather, 0.3, "hunter_")
    qv = P("hunter_quiver", leather, "chest", bevel=0.006, subsurf=1)
    qv.cyl((0.1, 0.2, 1.05), (0.19, 0.2, 1.6), 0.07, 0.078, seg=12)
    qv.torus((0.19, 0.2, 1.6), 0.078, 0.012, seg=14, rings=5)
    qv.weights = w_torso
    parts.append(qv)
    ar = P("hunter_arrows", wood, "chest", bevel=0, subsurf=0)
    ft = P("hunter_fletch", ember, "chest", bevel=0, subsurf=0)
    for k in range(6):
        x = 0.19 + 0.03 * math.cos(k * 1.1)
        y = 0.2 + 0.03 * math.sin(k * 1.1)
        ar.cyl((x - 0.01, y, 1.58), (x + 0.015 * k - 0.04, y, 1.82 + 0.02 * k), 0.006, 0.006, seg=5)
        ft.sphere((x + 0.015 * k - 0.04, y, 1.82 + 0.02 * k), 0.017, (1, 1, 1.7), seg=6, rings=4)
    ar.weights = w_torso
    ft.weights = w_torso
    parts += [ar, ft]
    bw = P("hunter_bow", wood, "weapon.L", bevel=0.004, subsurf=1)
    bpts = []
    for i in range(9):
        t = i / 8
        bpts.append((0.38, -0.1 - 0.28 * math.sin(math.pi * t), 0.2 + 1.35 * t))
    bw.tube(bpts, [0.012, 0.022, 0.026, 0.03, 0.032, 0.03, 0.026, 0.022, 0.012], seg=8)
    parts.append(bw)
    bs = P("hunter_string", leather_d, "weapon.L", bevel=0, subsurf=0)
    bs.cyl((0.38, -0.1, 0.2), (0.38, 0.0, 0.88), 0.004, 0.004, seg=4)
    bs.cyl((0.38, 0.0, 0.88), (0.38, -0.1, 1.55), 0.004, 0.004, seg=4)
    parts.append(bs)
    br = P("hunter_bowrune", glow, "weapon.L", bevel=0, subsurf=0)
    for t in (0.3, 0.5, 0.7):
        br.sphere((0.38, -0.1 - 0.28 * math.sin(math.pi * t) - 0.03, 0.2 + 1.35 * t), 0.013, seg=6, rings=4)
    parts.append(br)
    return parts


def build_warrior(rig):
    steel = mat("warrior_steel", hexc("#9aa3b2"), 0.38, 0.9)
    steel_d = mat("warrior_steel_d", hexc("#566074"), 0.42, 0.9)
    gold = mat("warrior_gold", hexc("#e0aa44"), 0.3, 1.0)
    cloth = mat("warrior_cloth", hexc("#3a2a24"), 0.85)
    leather = mat("warrior_leather", hexc("#5a3a26"), 0.7)
    glow = mat("warrior_glow", hexc("#ff8a2a"), 0.3, 0, emit=hexc("#ff5a10"), emit_strength=6.0)
    skin = mat("skin_tan2", hexc("#d09870"), 0.55)
    team = mat("TeamColor", (1, 1, 1), 0.65)
    parts = []
    hm = P("warrior_helm", steel, "head", bevel=0.008, subsurf=1)
    hm.sphere((0, 0.0, 1.71), 0.152, (1.0, 1.02, 1.1), seg=22, rings=14)
    hm.box((0, 0.0, 1.6), (0.29, 0.29, 0.14))
    hm.cyl((0, 0, 1.52), (0, 0, 1.62), 0.08, 0.105)
    hm.box((0, -0.15, 1.585), (0.15, 0.04, 0.09), (0.0, 0, 0))
    parts.append(hm)
    vz = P("warrior_visor", glow, "head", bevel=0, subsurf=0)
    vz.box((0, -0.153, 1.7), (0.19, 0.02, 0.024)); vz.box((0, -0.156, 1.65), (0.022, 0.02, 0.1))
    parts.append(vz)
    vf = P("warrior_visor_frame", steel_d, "head", bevel=0.004, subsurf=0)
    vf.box((0, -0.158, 1.7), (0.225, 0.014, 0.05)); vf.box((0, -0.158, 1.65), (0.05, 0.014, 0.13))
    vf.box((0, -0.02, 1.855), (0.04, 0.3, 0.04))
    parts.append(vf)
    for s in (1, -1):
        hn = P(f"warrior_horn{s}", gold, "head", bevel=0, subsurf=1)
        hn.tube([(0.14 * s, 0, 1.76), (0.24 * s, 0, 1.78), (0.32 * s, 0, 1.92), (0.3 * s, 0, 2.08)], [0.045, 0.036, 0.024, 0.004], seg=8)
        parts.append(hn)
    plume = P("warrior_plume", team, "head", bevel=0, subsurf=1)
    plume.tube([(0, 0.0, 1.87), (0, 0.1, 1.99), (0, 0.26, 1.94), (0, 0.38, 1.78)], [0.032, 0.045, 0.034, 0.006], seg=8)
    parts.append(plume)
    parts.append(torso_part("warrior_under", cloth, 0.01, 0.92, 1.49, bevel=0.005, subsurf=1))
    parts.append(torso_part("warrior_breast", steel, 0.045, 1.14, 1.47, sx=1.08, sy=1.12, bevel=0.012, subsurf=1))
    for k in range(4):
        z0 = 0.93 + 0.055 * k
        parts.append(torso_part(f"warrior_lame{k}", steel_d, 0.04 + 0.004 * k, z0, z0 + 0.075, sx=1.02, sy=1.05, bevel=0.006, subsurf=1))
    rg = P("warrior_ridge", gold, "chest", bevel=0.004, subsurf=1)
    rg.box((0, -0.19, 1.3), (0.035, 0.04, 0.4))
    rg.torus((0, -0.005, 1.5), 0.17, 0.02, seg=24, rings=6)
    rg.weights = w_torso
    parts.append(rg)
    belt = P("warrior_belt", leather, "spine", bevel=0.004, subsurf=0)
    belt.torus((0, 0, 0.98), 0.205, 0.032, seg=28, rings=6)
    parts.append(belt)
    bk = P("warrior_buckle", gold, "spine", bevel=0.005, subsurf=1)
    bk.box((0, -0.225, 0.98), (0.1, 0.03, 0.09))
    parts.append(bk)
    tab = P("warrior_tabard", team, "hips", bevel=0, subsurf=1, solid=0.018)
    tab.grid(lambda u, v: V((-0.11 + 0.22 * u, -0.215 - 0.02 * math.sin(v * 3) - 0.08 * v * v, 0.97 - 0.52 * v)), 4, 8)
    tab.weights = skirt_weights
    parts.append(tab)
    for s, side in ((1, "L"), (-1, "R")):
        ts = P(f"warrior_tasset{side}", steel_d, f"thigh.{side}", bevel=0.006, subsurf=1)
        ts.box((0.17 * s, -0.06, 0.84), (0.14, 0.05, 0.2), (0.15, 0, 0.18 * s))
        ts.box((0.2 * s, -0.03, 0.72), (0.12, 0.05, 0.16), (0.2, 0, 0.22 * s))
        parts.append(ts)
        pd = P(f"warrior_pauldron{side}", steel, "chest", bevel=0.01, subsurf=1)
        pd.sphere((0.33 * s, 0, 1.48), 0.155, (1.15, 1.0, 0.8), seg=16, rings=10)
        pd.sphere((0.37 * s, 0, 1.4), 0.145, (1.1, 1.0, 0.7), seg=16, rings=10)
        pd.sphere((0.4 * s, 0, 1.33), 0.125, (1.05, 0.95, 0.6), seg=16, rings=10)
        pd.weights = w_torso
        parts.append(pd)
        sp = P(f"warrior_spike{side}", gold, "chest", bevel=0, subsurf=0)
        sp.cyl((0.35 * s, 0, 1.55), (0.37 * s, 0, 1.78), 0.045, 0.003, seg=8)
        sp.weights = w_torso
        parts.append(sp)
        parts.append(arm_part("warrior_arm", steel_d, side, 0.12, 0.98, 0.03, bevel=0.007, subsurf=1))
        parts.append(arm_part("warrior_vambrace", steel, side, 0.62, 0.93, 0.045, bevel=0.007, subsurf=1))
        parts.append(hand_part("warrior_gauntlet", steel_d, side, 1.15, fist=True))
        parts.append(leg_part("warrior_cuisse", steel_d, side, 0.5, 0.95, 0.032, bevel=0.007, subsurf=1))
        parts.append(leg_part("warrior_greave", steel, side, 0.06, 0.52, 0.036, bevel=0.007, subsurf=1))
        k = P(f"warrior_knee{side}", gold, f"thigh.{side}", bevel=0.005, subsurf=1)
        k.sphere((0.133 * s, -0.07, 0.5), 0.075, (1, 0.75, 1.1))
        parts.append(k)
    cp = P("warrior_cape", team, "chest", bevel=0, subsurf=1, solid=0.02)
    cp.grid(lambda u, v: V((-0.3 + 0.6 * u + (u - 0.5) * 0.15 * v, 0.2 + 0.1 * v + 0.03 * math.sin(u * 6), 1.5 - 0.85 * v)), 10, 9)
    cp.weights = cape_weights
    parts.append(cp)
    sh = P("warrior_shield", steel, "forearm.L", bevel=0.01, subsurf=1)
    sh.grid(lambda u, v: V((0.47 + 0.04 * (1 - (2 * u - 1) ** 2), -0.12 + 0.3 * (2 * u - 1) * (1 - 0.65 * v ** 2), 1.38 - 0.72 * v)), 10, 10)
    sh.solid = 0.03
    parts.append(sh)
    sg = P("warrior_shield_emblem", team, "forearm.L", bevel=0.004, subsurf=1)
    sg.sphere((0.512, -0.12, 1.12), 0.1, (0.3, 0.8, 1.1), seg=14, rings=8)
    parts.append(sg)
    sr = P("warrior_shield_boss", gold, "forearm.L", bevel=0.003, subsurf=0)
    sr.sphere((0.52, -0.12, 1.12), 0.038, (0.6, 1, 1), seg=10, rings=6)
    parts.append(sr)
    bl = P("warrior_blade", steel, "weapon.R", bevel=0.004, subsurf=0)
    bl.box((-0.38, -0.2, 1.35), (0.016, 0.08, 0.95))
    bl.cyl((-0.38, -0.2, 1.82), (-0.38, -0.2, 1.93), 0.04, 0.003, seg=4)
    parts.append(bl)
    gd = P("warrior_guard", gold, "weapon.R", bevel=0.005, subsurf=1)
    gd.box((-0.38, -0.2, 0.86), (0.04, 0.32, 0.036))
    gd.cyl((-0.38, -0.2, 0.84), (-0.38, -0.2, 0.7), 0.02, 0.02)
    gd.sphere((-0.38, -0.2, 0.68), 0.036)
    parts.append(gd)
    rn = P("warrior_blade_rune", glow, "weapon.R", bevel=0, subsurf=0)
    rn.box((-0.389, -0.2, 1.3), (0.004, 0.014, 0.7))
    parts.append(rn)
    return parts


def build_rogue(rig):
    dark = mat("rogue_leather", hexc("#34303e"), 0.6)
    dark2 = mat("rogue_cloth", hexc("#1d1a26"), 0.85)
    strap_m = mat("rogue_strap", hexc("#3e2e24"), 0.6)
    steel = mat("rogue_steel", hexc("#c8d2e0"), 0.22, 1.0)
    blue = mat("rogue_glow", hexc("#7fd8ff"), 0.3, 0, emit=hexc("#3ab8ff"), emit_strength=6.0)
    skin = mat("skin_pale", hexc("#e0bca4"), 0.5)
    eyes = mat("rogue_eyes", hexc("#9fe8ff"), 0.3, 0, emit=hexc("#5ad0ff"), emit_strength=8.0)
    team = mat("TeamColor", (1, 1, 1), 0.7)
    gold = mat("rogue_gold", hexc("#c8963c"), 0.35, 1.0)
    parts = head_parts("rogue", skin, eyes, w=0.9, jaw=0.9)
    hd = open_hood("rogue_hood", dark2, (0, 0.04, 1.72), 0.168, (1.0, 1.12, 1.08), front_open=0.5)
    parts.append(hd)
    pt = P("rogue_hood_point", dark2, "head", bevel=0, subsurf=1)
    pt.tube([(0, 0.1, 1.82), (0, 0.24, 1.84), (0, 0.4, 1.72), (0, 0.5, 1.55)], [0.1, 0.07, 0.04, 0.008], seg=10)
    parts.append(pt)
    sc = P("rogue_mask", dark2, "head", bevel=0, subsurf=1)
    sc.sphere((0, -0.085, 1.63), 0.098, (1.12, 0.78, 0.72))
    parts.append(sc)
    brow = P("rogue_brow", dark2, "head", bevel=0, subsurf=0)
    for s in (1, -1):
        brow.box((0.055 * s, -0.12, 1.745), (0.08, 0.02, 0.02), (0, 0, -0.35 * s))
    parts.append(brow)
    parts.append(torso_part("rogue_shirt", dark2, 0.01, 0.92, 1.49, sx=0.98, bevel=0.005, subsurf=1))
    parts.append(torso_part("rogue_vest", dark, 0.03, 1.02, 1.44, sx=0.98, bevel=0.007, subsurf=1))
    st = P("rogue_straps", strap_m, "chest", bevel=0.004, subsurf=0)
    st.box((0.05, -0.17, 1.28), (0.028, 0.02, 0.72), (0, 0.55, 0)); st.box((-0.05, -0.17, 1.28), (0.028, 0.02, 0.72), (0, -0.55, 0))
    st.weights = w_torso
    parts.append(st)
    bl = P("rogue_belt", strap_m, "spine", bevel=0.004, subsurf=0)
    bl.torus((0, 0, 1.0), 0.17, 0.025, seg=24, rings=6)
    bl.box((0.17, -0.06, 0.94), (0.07, 0.07, 0.1)); bl.box((-0.17, -0.06, 0.94), (0.07, 0.07, 0.1))
    parts.append(bl)
    knv = P("rogue_throwing_knives", steel, "chest", bevel=0, subsurf=0)
    for k in range(4):
        knv.box((-0.06 + 0.04 * k, -0.195, 1.2), (0.012, 0.012, 0.09), (0, 0.3, 0.0))
    knv.weights = w_torso
    parts.append(knv)
    pd = P("rogue_pauldron", dark, "chest", bevel=0.01, subsurf=1)
    pd.sphere((0.3, 0, 1.47), 0.14, (1.2, 1.0, 0.75), seg=16, rings=10)
    pd.sphere((0.33, 0, 1.38), 0.13, (1.15, 1.0, 0.65), seg=16, rings=10)
    pd.weights = w_torso
    parts.append(pd)
    pdt = P("rogue_pauldron_trim", gold, "chest", bevel=0.003, subsurf=0)
    pdt.torus((0.3, 0, 1.455), 0.135, 0.011, rot=(0.2, 0, 0), seg=20, rings=5)
    pdt.weights = w_torso
    parts.append(pdt)
    sm = P("rogue_shoulder_mini", dark2, "chest", bevel=0.01, subsurf=1)
    sm.sphere((-0.285, 0, 1.45), 0.1, (1, 1, 0.8))
    sm.weights = w_torso
    parts.append(sm)
    sf = P("rogue_scarf", team, "chest", bevel=0, subsurf=1)
    sf.tube([(0, -0.08, 1.5), (0.1, -0.12, 1.48), (0.17, 0.02, 1.47), (0.15, 0.2, 1.43)], [0.05, 0.05, 0.045, 0.04], seg=8)
    sf.weights = w_torso
    parts.append(sf)
    tail = P("rogue_scarf_tail", team, "chest", bevel=0, subsurf=1, solid=0.012)
    tail.grid(lambda u, v: V((0.12 + 0.07 * u + 0.06 * v, 0.2 + 0.14 * v + 0.02 * math.sin(u * 5), 1.45 - 0.95 * v)), 2, 12)
    tail.weights = cape_weights
    parts.append(tail)
    tc = P("rogue_tailcoat", dark2, "hips", bevel=0, subsurf=1, solid=0.02)
    tc.grid(lambda u, v: V((-0.2 + 0.4 * u, 0.1 + 0.13 * v + 0.02 * math.sin(u * 8), 1.0 - 0.72 * v)), 8, 8)
    tc.weights = skirt_weights
    parts.append(tc)
    cl = P("rogue_cape", dark2, "chest", bevel=0, subsurf=1, solid=0.016)
    cl.grid(lambda u, v: V((-0.2 + 0.4 * u, 0.15 + 0.08 * v + 0.02 * math.sin(u * 6), 1.44 - 0.62 * v)), 8, 8)
    cl.weights = cape_weights
    parts.append(cl)
    for side in ("L", "R"):
        parts.append(arm_part("rogue_sleeve", dark2, side, 0.0, 0.95, 0.01, bevel=0.005, subsurf=1))
        parts.append(arm_part("rogue_bracer", dark, side, 0.6, 0.92, 0.024, bevel=0.005, subsurf=1))
        parts.append(hand_part("rogue_glove", dark, side))
    legs_set(parts, dark2, dark, dark, 0.28, "rogue_", 0.008)
    wr = P("rogue_wraps", team, "forearm.R", bevel=0, subsurf=0)
    wr.torus((-0.352, -0.04, 1.0), 0.07, 0.012, rot=(0.2, 0, 0), seg=14, rings=5)
    parts.append(wr)
    for s, side, wb in ((-1, "R", "weapon.R"), (1, "L", "weapon.L")):
        b = P(f"rogue_dagger{side}", steel, wb, bevel=0.003, subsurf=0)
        b.tube([(0.38 * s, -0.12, 0.9), (0.38 * s, -0.17, 1.05), (0.38 * s, -0.27, 1.17), (0.38 * s, -0.4, 1.22)], [0.028, 0.028, 0.021, 0.003], seg=4)
        parts.append(b)
        e = P(f"rogue_dagger_glow{side}", blue, wb, bevel=0, subsurf=0)
        e.tube([(0.38 * s, -0.13, 0.93), (0.38 * s, -0.18, 1.06), (0.38 * s, -0.28, 1.17), (0.38 * s, -0.4, 1.221)], [0.008, 0.008, 0.006, 0.001], seg=4)
        parts.append(e)
        g = P(f"rogue_dagger_hilt{side}", dark, wb, bevel=0.003, subsurf=1)
        g.cyl((0.38 * s, -0.1, 0.78), (0.38 * s, -0.1, 0.9), 0.022, 0.022)
        g.box((0.38 * s, -0.11, 0.9), (0.075, 0.025, 0.02))
        parts.append(g)
    return parts
