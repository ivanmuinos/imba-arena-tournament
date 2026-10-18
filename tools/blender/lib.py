"""Shared helpers for the Imba Arena Tournament Blender generators (run with: blender -b --python <script>).

Conventions: metres, +Z up, characters face -Y (the glTF exporter turns that into +Z, which is
the forward axis of the game's units). Materials named "TeamColor" are re-tinted in Godot.
"""
import math
import bpy
import bmesh

_mats = {}
from mathutils import Vector, Matrix, Euler, Quaternion

def V(*a):
    return Vector(a[0] if len(a) == 1 else a)


def reset():
    _mats.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)


# ------------------------------------------------------------------ materials

def mat(name, color, rough=0.55, metal=0.0, emit=None, emit_strength=0.0, alpha=1.0):
    if name in _mats and _mats[name].name in bpy.data.materials:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color[:3], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit is not None:
        b.inputs["Emission Color"].default_value = (*emit[:3], 1.0)
        b.inputs["Emission Strength"].default_value = emit_strength
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
    _mats[name] = m
    return m


def hexc(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    # sRGB -> linear for Blender
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


# ------------------------------------------------------------------ part builder

class Part:
    """One mesh object assembled from primitives, rigidly (or softly) bound to bones."""

    def __init__(self, name, material, bone, bevel=0.012, subsurf=1, smooth=True, weights=None):
        self.name = name
        self.material = material
        self.bone = bone
        self.bevel = bevel
        self.subsurf = subsurf
        self.smooth = smooth
        self.weights = weights  # callable(vertex_co) -> {bone: weight}
        self.bm = bmesh.new()
        self.obj = None

    # primitives -----------------------------------------------------
    def sphere(self, center, radius, scale=(1, 1, 1), rot=(0, 0, 0), seg=14, rings=10):
        m = Matrix.Translation(center) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((*[radius * s for s in scale], 1))
        bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=rings, radius=1.0, matrix=m)
        return self

    def cyl(self, p0, p1, r0, r1=None, seg=12, caps=True):
        """Tapered cylinder from p0 (radius r0) to p1 (radius r1)."""
        p0, p1 = V(p0), V(p1)
        r1 = r0 if r1 is None else r1
        d = p1 - p0
        L = d.length
        if L < 1e-6:
            return self
        q = V((0, 0, 1)).rotation_difference(d.normalized())
        m = Matrix.Translation((p0 + p1) / 2) @ q.to_matrix().to_4x4()
        bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=seg, radius1=r0, radius2=r1, depth=L, matrix=m)
        return self

    def box(self, center, size, rot=(0, 0, 0)):
        m = Matrix.Translation(center) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Diagonal((size[0] / 2, size[1] / 2, size[2] / 2, 1))
        bmesh.ops.create_cube(self.bm, size=2.0, matrix=m)
        return self

    def torus(self, center, major, minor, rot=(0, 0, 0), seg=24, rings=8):
        pts = []
        verts = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            ring = []
            for j in range(rings):
                b = 2 * math.pi * j / rings
                x = (major + minor * math.cos(b)) * math.cos(a)
                y = (major + minor * math.cos(b)) * math.sin(a)
                z = minor * math.sin(b)
                ring.append(self.bm.verts.new(Euler(rot).to_matrix() @ V((x, y, z)) + V(center)))
            verts.append(ring)
        for i in range(seg):
            for j in range(rings):
                a, b = verts[i], verts[(i + 1) % seg]
                try:
                    self.bm.faces.new((a[j], a[(j + 1) % rings], b[(j + 1) % rings], b[j]))
                except ValueError:
                    pass
        return self

    def tube(self, pts, radii, seg=8):
        """Smooth tapered tube through a list of points (cloth strips, horns, bows, tails)."""
        for i in range(len(pts) - 1):
            self.cyl(pts[i], pts[i + 1], radii[i], radii[i + 1], seg=seg, caps=(i == 0 or i == len(pts) - 2))
        for p, r in zip(pts[1:-1], radii[1:-1]):
            self.sphere(p, r, seg=seg, rings=max(4, seg // 2))
        return self

    def grid(self, fn, nu, nv):
        """Parametric surface: fn(u, v) -> Vector, u,v in [0,1]; double sided thickness added later by solidify."""
        vs = [[self.bm.verts.new(fn(i / nu, j / nv)) for j in range(nv + 1)] for i in range(nu + 1)]
        for i in range(nu):
            for j in range(nv):
                self.bm.faces.new((vs[i][j], vs[i + 1][j], vs[i + 1][j + 1], vs[i][j + 1]))
        return self

    def deform(self, fn):
        for v in self.bm.verts:
            v.co = fn(v.co.copy())
        return self

    # finish ---------------------------------------------------------
    def displace(self, amp, freq, seed=0, bias=0.0, along_normal=True):
        """Noise displacement of the current bmesh (call after the shape is assembled; subdivide first for detail)."""
        from mathutils import noise
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        for v in self.bm.verts:
            n = noise.noise(v.co * freq + V((seed * 17.3, seed * 5.1, seed * 9.7))) + 0.5 * noise.noise(v.co * freq * 2.3 + V((seed, 3.0, 1.0)))
            d = (n + bias) * amp
            v.co += (v.normal if along_normal else V((0, 0, 1))) * d
        return self

    def scale(self, s):
        bmesh.ops.scale(self.bm, vec=V((s, s, s)), verts=self.bm.verts)
        return self

    def subdivide(self, cuts=1):
        bmesh.ops.subdivide_edges(self.bm, edges=self.bm.edges[:], cuts=cuts, use_grid_fill=True)
        return self

    def build(self, solidify=0.0):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        me.materials.append(self.material)
        if getattr(self, "vcol_fn", None) is not None:
            ca = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
            for loop in me.loops:
                c = self.vcol_fn(me.vertices[loop.vertex_index].co)
                ca.data[loop.index].color = (*c[:3], 1.0)
        self.obj = bpy.data.objects.new(self.name, me)
        bpy.context.collection.objects.link(self.obj)
        if self.smooth:
            for p in me.polygons:
                p.use_smooth = True
        if solidify:
            s = self.obj.modifiers.new("Solid", "SOLIDIFY")
            s.thickness = solidify
            s.offset = 0
        if self.bevel > 0:
            b = self.obj.modifiers.new("Bevel", "BEVEL")
            b.width = self.bevel
            b.segments = 2
            b.limit_method = "ANGLE"
            b.angle_limit = math.radians(35)
        if self.subsurf > 0:
            s = self.obj.modifiers.new("Subsurf", "SUBSURF")
            s.levels = self.subsurf
            s.render_levels = self.subsurf
        return self.obj


# ------------------------------------------------------------------ rig

class Rig:
    def __init__(self, name="Armature"):
        self.arm_data = bpy.data.armatures.new(name)
        self.obj = bpy.data.objects.new(name, self.arm_data)
        bpy.context.collection.objects.link(self.obj)
        self.bones = {}

    def build(self, spec):
        """spec: {bone: (parent, head, tail)} in creation order."""
        bpy.context.view_layer.objects.active = self.obj
        bpy.ops.object.mode_set(mode="EDIT")
        eb = self.arm_data.edit_bones
        for name, (parent, head, tail) in spec.items():
            b = eb.new(name)
            b.head = V(head)
            b.tail = V(tail)
            if parent:
                b.parent = eb[parent]
        bpy.ops.object.mode_set(mode="OBJECT")
        for pb in self.obj.pose.bones:
            pb.rotation_mode = "QUATERNION"

    def bind(self, part_obj, bone, weights=None):
        """Rigid bind to one bone, or soft with weights(co)->{bone: w}."""
        me = part_obj.data
        names = {bone} if weights is None else set()
        if weights is not None:
            for v in me.vertices:
                names.update(weights(v.co).keys())
        groups = {n: part_obj.vertex_groups.new(name=n) for n in names}
        for v in me.vertices:
            if weights is None:
                groups[bone].add([v.index], 1.0, "REPLACE")
            else:
                for n, w in weights(v.co).items():
                    if w > 0.001:
                        groups[n].add([v.index], w, "REPLACE")
        m = part_obj.modifiers.new("Armature", "ARMATURE")
        m.object = self.obj
        part_obj.parent = self.obj

    # posing ---------------------------------------------------------
    def _basis(self, bone):
        return self.obj.data.bones[bone].matrix_local.to_3x3()

    def pose(self, bone, rot=(0, 0, 0), loc=(0, 0, 0)):
        """Rotation (euler XYZ, radians) and offset expressed along ARMATURE axes."""
        pb = self.obj.pose.bones[bone]
        B = self._basis(bone)
        R = Euler(rot).to_matrix()
        pb.rotation_quaternion = (B.inverted() @ R @ B).to_quaternion()
        pb.location = B.inverted() @ V(loc)

    def key(self, frame, bones=None):
        for pb in self.obj.pose.bones:
            if bones is None or pb.name in bones:
                pb.keyframe_insert("rotation_quaternion", frame=frame)
                pb.keyframe_insert("location", frame=frame)

    def reset_pose(self):
        for pb in self.obj.pose.bones:
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)

    def animation(self, name, frames, poses, loop=True):
        """poses: {frame: {bone: (rot, loc)}}; bones not listed rest. Creates an NLA track named `name`."""
        ad = self.obj.animation_data_create()
        act = bpy.data.actions.new(name)
        ad.action = act
        last = None
        for f in sorted(poses):
            self.reset_pose()
            for b, val in poses[f].items():
                rot, loc = (val, (0, 0, 0)) if len(val) == 3 and not isinstance(val[0], (tuple, list)) else val
                self.pose(b, rot, loc)
            self.key(f)
        for fc in act.fcurves if hasattr(act, "fcurves") else []:
            pass
        ad.action = None
        tr = ad.nla_tracks.new()
        tr.name = name
        st = tr.strips.new(name, int(min(poses)), act)
        st.name = name
        act.use_fake_user = True
        return act


def export_glb(path, objs=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.context.scene.objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_animations=True,
        export_animation_mode="NLA_TRACKS", export_skins=True, export_yup=True, export_texcoords=True, export_normals=True,
        export_vertex_color="ACTIVE", export_materials="EXPORT", export_cameras=False, export_lights=False, export_extras=False)
