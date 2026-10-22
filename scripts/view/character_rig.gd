class_name CharacterRig
extends RefCounted
## A class character from assets/models/<class>.glb (built by tools/blender/build_characters.py):
## team-colour material slot + animation set idle/run/cast/attack/hit/death/stun.

const LOOPING := ["idle", "run", "stun"]
## Use the CC0 KayKit characters (assets/third_party/kaykit) when present; false falls back to the procedural Blender models.
static var use_kaykit := true
## Ink outline pass on every character part (unifies the hand-painted look); off on the lowest quality level.
static var outlines := true
const KAYKIT := {
	"warlock": {"file": "Mage", "show": ["2H_Staff", "Spellbook_open"], "hide": ["Mage_Hat"], "scale": 0.86, "recolor": {"hue": 0.10, "sat": 0.15, "val": -0.35},
		"clips": {"idle": "Idle", "run": "Running_A", "cast": "Spellcasting", "attack": "Spellcast_Raise", "hit": "Hit_A", "death": "Death_B", "stun": "Sit_Floor_Idle"}},
	"mage": {"file": "Mage", "show": ["2H_Staff"], "scale": 0.86, "hue": 0.0,
		"clips": {"idle": "Idle", "run": "Running_A", "cast": "Spellcasting", "attack": "Spellcast_Shoot", "hit": "Hit_A", "death": "Death_A", "stun": "Sit_Floor_Idle"}},
	"priest": {"file": "Mage", "show": ["Spellbook_open"], "hide": ["Mage_Hat"], "extras": "priest", "scale": 0.86, "recolor": {"hue": -0.12, "sat": -0.75, "val": 0.65},
		"clips": {"idle": "Idle", "run": "Running_A", "cast": "Spellcasting", "attack": "Spellcast_Raise", "hit": "Hit_A", "death": "Death_B", "stun": "Sit_Floor_Idle"}},
	"warrior": {"file": "Knight", "show": ["1H_Sword", "Round_Shield"], "scale": 0.84,
		"clips": {"idle": "Idle", "run": "Running_A", "cast": "Block", "attack": "1H_Melee_Attack_Slice_Diagonal", "hit": "Hit_A", "death": "Death_B", "stun": "Sit_Floor_Idle"}},
	"rogue": {"file": "Rogue", "show": ["Knife", "Knife_Offhand"], "scale": 0.86, "recolor": {"hue": 0.42, "sat": -0.15, "val": -0.45},
		"clips": {"idle": "Idle", "run": "Running_B", "cast": "Throw", "attack": "Dualwield_Melee_Attack_Slice", "hit": "Hit_B", "death": "Death_A", "stun": "Sit_Floor_Idle"}},
	"hunter": {"file": "Rogue_Hooded", "show": ["2H_Crossbow"], "scale": 0.86,
		"clips": {"idle": "2H_Ranged_Aiming", "run": "Running_A", "cast": "2H_Ranged_Aiming", "attack": "2H_Ranged_Shoot", "hit": "Hit_A", "death": "Death_A", "stun": "Sit_Floor_Idle"}},
}
## Attack clips per class: [clip, contact_time_s] (the moment the weapon/hands land or release, measured from the clips).
## Rogue alternates its two light swings (left/right dagger); the warrior swings overhead.
const ATTACKS := {
	"warlock": {"light": [["Spellcast_Shoot", 0.10]], "heavy": [["Spellcast_Raise", 0.10]]},
	"rogue": {"light": [["1H_Melee_Attack_Slice_Horizontal", 0.27], ["1H_Melee_Attack_Slice_Diagonal", 0.40]], "heavy": [["Dualwield_Melee_Attack_Stab", 0.40]]},
	"warrior": {"light": [["1H_Melee_Attack_Chop", 0.60]], "heavy": [["1H_Melee_Attack_Chop", 0.60]]},
	"hunter": {"light": [["2H_Ranged_Shoot", 0.13]], "heavy": [["2H_Ranged_Shoot", 0.13]]},
	"mage": {"light": [["Spellcast_Shoot", 0.10]], "heavy": [["Spellcast_Shoot", 0.10]]},
	"priest": {"light": [["Spellcast_Shoot", 0.10]], "heavy": [["Spellcast_Shoot", 0.10]]},
}
## How long before the contact frame a swing starts: the server event arrives at the moment of the hit, so the clip
## begins this far (seconds of clip time) before contact to show a short wind-up, the strike, then the recovery.
const SWING_LEAD := 0.14
const HIT_STOP_S := 0.05
const KK_LOOPS := ["Idle", "Running_A", "Running_B", "Walking_A", "Spellcasting", "Sit_Floor_Idle", "2H_Ranged_Aiming", "Block"]
static var _tex_cache := {}

var root: Node3D
var player: AnimationPlayer
var parts: Array[MeshInstance3D] = []
var team_mats: Array[StandardMaterial3D] = []
var _current := ""
var _once_until := 0.0
var _lengths := {}
var _atk_node: AnimationNodeAnimation = null
var _atk_n := 0
## Locomotion blend point set by the unit view each frame (strafe, forward) from its real ground velocity.
var move_xy := Vector2.ZERO
var _stop_at := -1.0
var _stop_until := -1.0
var cls_id := ""
var _tree: AnimationTree = null  # KayKit characters are driven by this blend tree (locomotion blend space + state + one-shots)
var _clips := {}  # logical animation -> clip name (identity for the procedural models)


static func available(cls: String) -> bool:
	return _kk_ok(cls) or ResourceLoader.exists("res://assets/models/%s.glb" % ("mage" if cls == "warlock" else cls))


static func _kk_ok(cls: String) -> bool:
	return use_kaykit and KAYKIT.has(cls) and ResourceLoader.exists("res://assets/third_party/kaykit/%s.glb" % KAYKIT[cls].file)


## Hue/saturation/value shifted copy of a texture (cached), used to turn the mage into a priest and the rogue into a ranger.
static func _recolored(tex: Texture2D, key: String, rc: Dictionary) -> Texture2D:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(256, 256, Image.INTERPOLATE_BILINEAR)
	for y in 256:
		for x in 256:
			var c := img.get_pixel(x, y)
			if c.h < 0.14 and c.s < 0.75 and c.v > 0.45 and c.s > 0.08:
				continue  # skin tones stay as they are
			c.h = fposmod(c.h + float(rc.hue), 1.0)
			c.s = clampf(c.s + float(rc.sat) * c.s, 0.0, 1.0)
			c.v = clampf(c.v + float(rc.val) * (1.0 - c.v), 0.0, 1.0) if float(rc.val) >= 0.0 else clampf(c.v * (1.0 + float(rc.val)), 0.0, 1.0)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t


func _setup_kaykit(cls: String, team: Color) -> void:
	var def: Dictionary = KAYKIT[cls]
	cls_id = cls
	var scene := load("res://assets/third_party/kaykit/%s.glb" % def.file) as PackedScene
	var inner: Node3D = scene.instantiate()
	root = Node3D.new()
	root.add_child(inner)
	inner.scale = Vector3.ONE * float(def.scale)
	player = inner.find_children("*", "AnimationPlayer", true, false)[0]
	_clips = def.clips
	var prefix: String = str(def.file).split("_")[0] + "_"
	for mi in inner.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var nm := String(m.name)
		var is_body := nm.begins_with(prefix)
		m.visible = (is_body or def.show.has(nm)) and not def.get("hide", []).has(nm)
		if not m.visible:
			continue
		parts.append(m)
		var src: Material = m.get_active_material(0)
		if src is StandardMaterial3D:
			var sm := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			sm.roughness = 0.8
			sm.metallic = 0.0
			sm.albedo_color = Color(0.84, 0.84, 0.86)  # the atlas is bright; keeps white armour from clipping under strong ambient light
			if def.has("recolor") and sm.albedo_texture != null:
				sm.albedo_texture = _recolored(sm.albedo_texture, "%s_%s" % [cls, def.file], def.recolor)
			if nm.ends_with("Cape"):  # the cape carries the team colour
				sm.albedo_texture = null
				sm.albedo_color = team.darkened(0.15)
				sm.emission_enabled = true
				sm.emission = team
				sm.emission_energy_multiplier = 0.18
				team_mats.append(sm)
			if outlines:
				sm.next_pass = _outline_mat()
			m.set_surface_override_material(0, sm)
	if def.get("extras", "") == "priest":
		_priest_extras(inner)
	if cls == "warlock":
		_warlock_extras(inner)
	for logical in _clips:
		var clip: String = _clips[logical]
		if player.has_animation(clip):
			var anim := player.get_animation(clip)
			anim.loop_mode = Animation.LOOP_LINEAR if KK_LOOPS.has(clip) else Animation.LOOP_NONE
			_lengths[logical] = anim.length
	for extra in ["Walking_A", "Walking_Backwards", "Running_Strafe_Left", "Running_Strafe_Right", "Jump_Full_Short"]:
		if player.has_animation(extra):
			player.get_animation(extra).loop_mode = Animation.LOOP_NONE if extra == "Jump_Full_Short" else Animation.LOOP_LINEAR
	_lengths["jump"] = player.get_animation("Jump_Full_Short").length if player.has_animation("Jump_Full_Short") else 0.6
	_build_tree()


func setup(cls: String, team: Color) -> void:
	if _kk_ok(cls):
		_setup_kaykit(cls, team)
		return
	var scene := load("res://assets/models/%s.glb" % ("mage" if cls == "warlock" else cls)) as PackedScene
	root = scene.instantiate()
	player = root.find_children("*", "AnimationPlayer", true, false)[0]
	for a in player.get_animation_list():
		var anim := player.get_animation(a)
		anim.loop_mode = Animation.LOOP_LINEAR if a in LOOPING else Animation.LOOP_NONE
		_lengths[a] = anim.length
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		parts.append(m)
		for s in m.mesh.get_surface_count():
			var sm: Material = m.get_active_material(s)
			if sm != null and sm.resource_name == "TeamColor":
				var tm := StandardMaterial3D.new()
				tm.albedo_color = team
				tm.roughness = 0.55
				tm.emission_enabled = true
				tm.emission = team
				tm.emission_energy_multiplier = 0.22
				m.set_surface_override_material(s, tm)
				team_mats.append(tm)
	_play("idle", 1.0, 0.0)


static var _outline: ShaderMaterial = null


static func _outline_mat() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = load("res://assets/shaders/outline.gdshader")
	return _outline


## Occult identity on the KayKit mage body: horned hood, glowing fel eyes and hands, shoulder spikes, a long shadow cloak,
## a skull staff burning with fel fire and a dark grimoire. Everything is bone-bound to the licensed skeleton.
func _warlock_extras(inner: Node3D) -> void:
	var sk: Skeleton3D = inner.find_children("*", "Skeleton3D", true, false)[0]
	var head := sk.get_node_or_null("head") as Node3D
	var chest := sk.get_node_or_null("chest") as Node3D
	var hand := sk.get_node_or_null("handslot_r") as Node3D
	var hand_l := sk.get_node_or_null("handslot_l") as Node3D
	var shadow := UnitModels.std(Color("#2a1840"), Color.BLACK, 0.0, 0.8)
	var deep := UnitModels.std(Color("#150b22"), Color.BLACK, 0.0, 0.9)
	var iron := UnitModels.std(Color("#3a2a4a"), Color.BLACK, 0.0, 0.5)
	var bone := UnitModels.std(Color("#cbbf9f"), Color.BLACK, 0.0, 0.35)
	var fel := UnitModels.std(Color("#4fa83a"), Color("#4fe03a"), 1.0)
	if head != null:
		# hood: a dark dome behind and above the face, with a peaked back and two curved horns
		_add_mesh(head, MeshBuilder.sphere(0.62, 14, 8), shadow, Vector3(0, 0.44, -0.5), Vector3.ZERO, Vector3(1.25, 1.05, 0.8))
		_add_mesh(head, MeshBuilder.cylinder(0.0, 0.4, 0.8, 8), shadow, Vector3(0, 0.95, -0.7), Vector3(-30, 0, 0))
		for side in [-1.0, 1.0]:
			# one continuous horn (out of the hood, then up and back), not two loose cones that read as bent legs
			_tube(head, [Vector3(side * 0.42, 0.92, -0.15), Vector3(side * 0.68, 1.12, -0.22), Vector3(side * 0.82, 1.4, -0.34),
				Vector3(side * 0.8, 1.68, -0.5), Vector3(side * 0.68, 1.88, -0.66)], [0.15, 0.12, 0.09, 0.055, 0.0], bone)
			_add_mesh(head, MeshBuilder.sphere(0.075, 6, 4), fel, Vector3(side * 0.2, 0.36, 0.56), Vector3.ZERO, Vector3(1.2, 0.8, 0.6))  # fel eyes
	if chest != null:
		for side in [-1.0, 1.0]:
			_add_mesh(chest, MeshBuilder.sphere(0.3, 10, 6), iron, Vector3(side * 0.56, 0.1, 0.0), Vector3.ZERO, Vector3(1.1, 0.7, 1.0))
			for k in 3:
				_add_mesh(chest, MeshBuilder.cylinder(0.0, 0.09, 0.45, 5), bone, Vector3(side * (0.5 + 0.1 * k), 0.36 - 0.03 * k, -0.02 + 0.1 * (k - 1)), Vector3(0, 0, -side * (20 + 30 * k)))
		# long shadow cloak hanging behind, with a fel hem
		_add_mesh(chest, MeshBuilder.cylinder(0.38, 0.62, 1.15, 12), deep, Vector3(0, -0.6, -0.5), Vector3(10, 0, 0), Vector3(1.0, 1.0, 0.3))
		_add_mesh(chest, MeshBuilder.torus(0.62, 0.025, 20, 6), fel, Vector3(0, -1.15, -0.55), Vector3(10, 0, 0), Vector3(1.0, 1.0, 0.3))
		# a skull charm on the belt
		_add_mesh(chest, MeshBuilder.sphere(0.13, 8, 5), bone, Vector3(0.0, -0.62, 0.52))
	if hand != null:
		var staff := hand.get_node_or_null("2H_Staff") as MeshInstance3D
		if staff != null:
			staff.visible = false
			parts.erase(staff)
		_add_mesh(hand, MeshBuilder.cylinder(0.045, 0.06, 2.0, 8), iron, Vector3(0, 0.1, 0))
		# skull topper with fel flame
		_add_mesh(hand, MeshBuilder.sphere(0.2, 10, 6), bone, Vector3(0, 1.22, 0), Vector3.ZERO, Vector3(1.0, 1.1, 0.95))
		_add_mesh(hand, MeshBuilder.box(Vector3(0.22, 0.1, 0.18)), bone, Vector3(0, 1.06, 0.03))
		for side in [-1.0, 1.0]:
			_add_mesh(hand, MeshBuilder.sphere(0.055, 6, 4), fel, Vector3(side * 0.08, 1.25, 0.16))
			_add_mesh(hand, MeshBuilder.cylinder(0.0, 0.04, 0.34, 5), iron, Vector3(side * 0.14, 1.0, 0.0), Vector3(0, 0, -side * 28))
		_add_mesh(hand, MeshBuilder.cylinder(0.0, 0.12, 0.5, 7), fel, Vector3(0, 1.62, 0))
		_add_mesh(hand, MeshBuilder.sphere(0.08, 6, 4), fel, Vector3(0.0, 0.05, 0.0))   # fel glow in the grip
	if hand_l != null:
		_add_mesh(hand_l, MeshBuilder.sphere(0.09, 6, 4), fel, Vector3(0, 0.0, 0.0))


## A tapering tube through `points` (radius per point): one cone frustum per segment, a ball on each joint so it bends
## smoothly.
func _tube(parent: Node3D, points: Array, radii: Array, mat: Material) -> void:
	for i in points.size() - 1:
		var p0: Vector3 = points[i]
		var p1: Vector3 = points[i + 1]
		var dir := p1 - p0
		var mi := _add_mesh(parent, MeshBuilder.cylinder(radii[i + 1], radii[i], dir.length(), 8), mat, (p0 + p1) * 0.5)
		var y := dir.normalized()
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		mi.basis = Basis(x, y, x.cross(y))
		if i > 0:
			_add_mesh(parent, MeshBuilder.sphere(radii[i], 8, 5), mat, p0)


func _holy_mat(gold: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.3 if gold else 0.55
	m.metallic = 0.85 if gold else 0.0
	m.albedo_color = Color(0.9, 0.66, 0.24) if gold else Color(0.9, 0.84, 0.72)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.2) if gold else Color(1.0, 0.95, 0.8)
	m.emission_energy_multiplier = 0.22 if gold else 0.04
	return m


func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if outlines and mat is StandardMaterial3D and not (mat as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		(mat as StandardMaterial3D).next_pass = _outline_mat()
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	parts.append(mi)
	return mi


## Priest kit-bash on the KayKit mage body: tall white mitre with a gold band and cross, a halo behind the head, gold
## pauldrons, a long white tabard with gold trim and a holy staff topped by a radiant sun. Gives a silhouette
## nothing else in the roster has (tall pointed head, ring, wide shoulders, long front panel, big sun on a staff).
func _priest_extras(inner: Node3D) -> void:
	var cloth := _holy_mat(false)
	var gold := _holy_mat(true)
	var sk: Skeleton3D = inner.find_children("*", "Skeleton3D", true, false)[0]
	var head := sk.get_node_or_null("head") as Node3D
	var chest := sk.get_node_or_null("chest") as Node3D
	var hand := sk.get_node_or_null("handslot_r") as Node3D
	var hat := head.get_node_or_null("Mage_Hat") as Node3D if head != null else null
	if head != null:
		# mitre: a flat four-sided pointed crown with a split top
		_add_mesh(head, MeshBuilder.cylinder(0.12, 0.72, 1.25, 4), cloth, Vector3(0, 1.08, 0), Vector3(-6, 45, 0), Vector3(1.0, 1.0, 0.55))
		_add_mesh(head, MeshBuilder.cylinder(0.78, 0.78, 0.14, 20), gold, Vector3(0, 0.46, 0), Vector3(-6, 0, 0), Vector3(1.0, 1.0, 0.9))
		_add_mesh(head, MeshBuilder.box(Vector3(0.12, 0.6, 0.05)), gold, Vector3(0, 0.95, 0.34), Vector3(-6, 0, 0))
		_add_mesh(head, MeshBuilder.box(Vector3(0.4, 0.1, 0.05)), gold, Vector3(0, 1.05, 0.34), Vector3(-6, 0, 0))
		# halo standing behind the head
		var halo := _add_mesh(head, MeshBuilder.torus(0.8, 0.035, 36, 8), gold, Vector3(0, 0.3, -0.6), Vector3(90, 0, 0))
		halo.set_meta("halo", true)
	if chest != null:
		for side in [-1.0, 1.0]:
			_add_mesh(chest, MeshBuilder.sphere(0.27, 12, 6), gold, Vector3(side * 0.55, 0.12, 0.0), Vector3.ZERO, Vector3(1.0, 0.7, 1.0))
		# tabard
		_add_mesh(chest, MeshBuilder.cylinder(0.5, 0.66, 0.6, 18), cloth, Vector3(0, -0.52, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.85))
		_add_mesh(chest, MeshBuilder.torus(0.64, 0.03, 28, 6), gold, Vector3(0, -0.82, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.85))
		_add_mesh(chest, MeshBuilder.box(Vector3(0.3, 0.75, 0.05)), gold, Vector3(0, -0.45, 0.45))
		_add_mesh(chest, MeshBuilder.box(Vector3(0.2, 0.7, 0.07)), cloth, Vector3(0, -0.45, 0.46))
		_add_mesh(chest, MeshBuilder.box(Vector3(0.06, 0.3, 0.09)), gold, Vector3(0, -0.1, 0.46))
		_add_mesh(chest, MeshBuilder.box(Vector3(0.2, 0.06, 0.09)), gold, Vector3(0, -0.02, 0.46))
	if hand != null:
		var staff := hand.get_node_or_null("2H_Staff") as MeshInstance3D
		if staff != null:
			staff.visible = false
			parts.erase(staff)
		_add_mesh(hand, MeshBuilder.cylinder(0.05, 0.05, 2.0, 8), gold, Vector3(0, 0.1, 0), Vector3(0, 180, 0))
		_add_mesh(hand, MeshBuilder.torus(0.26, 0.04, 28, 8), gold, Vector3(0, 1.25, 0), Vector3(90, 180, 0))
		var core := _add_mesh(hand, MeshBuilder.sphere(0.13, 10, 6), cloth, Vector3(0, 1.25, 0), Vector3(0, 180, 0))
		core.material_override = _glow_mat()
		for i in 8:
			var a := TAU * i / 8.0
			_add_mesh(hand, MeshBuilder.cylinder(0.0, 0.05, 0.22, 4), gold, Vector3(sin(a) * 0.4, 1.25 + cos(a) * 0.4, 0), Vector3(0, 180, -rad_to_deg(a)))
	if hat != null:
		hat.visible = false


func _glow_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.5, 1.25, 0.8)
	return m


func _anim_node(clip: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = StringName(clip)
	return n


## Blend tree: locomotion (idle/walk/run blend space) -> state (locomotion | cast loop | stun loop)
## -> attack, hit and jump one-shots -> alive/dead. Transitions cross-fade instead of popping.
func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace2D.new()
	loco.min_space = Vector2(-1.0, -1.0)
	loco.max_space = Vector2(1.0, 1.0)
	loco.auto_triangles = true
	loco.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	loco.add_blend_point(_anim_node(_clips.idle), Vector2(0.0, 0.0), -1, &"idle")
	loco.add_blend_point(_anim_node("Walking_A"), Vector2(0.0, 0.4), -1, &"walk")
	loco.add_blend_point(_anim_node(_clips.run), Vector2(0.0, 1.0), -1, &"run")
	loco.add_blend_point(_anim_node("Walking_Backwards"), Vector2(0.0, -LocoBlend.BACK_SCALE), -1, &"back")
	loco.add_blend_point(_anim_node("Running_Strafe_Left"), Vector2(-1.0, 0.0), -1, &"strafe_l")
	loco.add_blend_point(_anim_node("Running_Strafe_Right"), Vector2(1.0, 0.0), -1, &"strafe_r")
	bt.add_node("loco", loco, Vector2(0, 0))
	var loco_ts := AnimationNodeTimeScale.new()
	bt.add_node("loco_ts", loco_ts, Vector2(200, 0))
	bt.connect_node("loco_ts", 0, "loco")
	var state := AnimationNodeTransition.new()
	state.input_count = 3
	state.xfade_time = 0.18
	bt.add_node("state", state, Vector2(400, 0))
	bt.add_node("cast_anim", _anim_node(_clips.cast), Vector2(200, 120))
	bt.add_node("stun_anim", _anim_node(_clips.stun), Vector2(200, 240))
	bt.connect_node("state", 0, "loco_ts")
	bt.connect_node("state", 1, "cast_anim")
	bt.connect_node("state", 2, "stun_anim")
	var last := "state"
	for pair in [["attack", _clips.attack], ["hit", _clips.hit], ["jump", "Jump_Full_Short"]]:
		var nm: String = pair[0]
		var os := AnimationNodeOneShot.new()
		if nm in ["attack", "hit"]:
			_filter_upper_body(os)
		os.fadein_time = 0.06
		os.fadeout_time = 0.18
		var an := _anim_node(pair[1])
		if nm == "attack":
			_atk_node = an
		bt.add_node(nm + "_anim", an, Vector2(500, 300))
		var ts := AnimationNodeTimeScale.new()
		bt.add_node(nm + "_ts", ts, Vector2(600, 300))
		bt.connect_node(nm + "_ts", 0, nm + "_anim")
		bt.add_node(nm, os, Vector2(800, 0))
		bt.connect_node(nm, 0, last)
		bt.connect_node(nm, 1, nm + "_ts")
		last = nm
	var death := AnimationNodeTransition.new()
	death.input_count = 2
	death.xfade_time = 0.12
	bt.add_node("death", death, Vector2(1000, 0))
	bt.add_node("death_anim", _anim_node(_clips.death), Vector2(800, 400))
	bt.connect_node("death", 0, last)
	bt.connect_node("death", 1, "death_anim")
	bt.connect_node("output", 0, "death")
	_tree = AnimationTree.new()
	_tree.tree_root = bt
	root.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(player)
	_tree.active = true


## Keep locomotion on the hips/legs even while repeated attacks and hit reactions play.
func _filter_upper_body(node: AnimationNodeOneShot) -> void:
	var skeleton: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var spine := skeleton.find_bone("spine")
	if spine < 0:
		return
	node.filter_enabled = true
	for clip in player.get_animation_list():
		var anim := player.get_animation(clip)
		for i in anim.get_track_count():
			var path := anim.track_get_path(i)
			if path.get_subname_count() != 1:
				continue
			var bone := skeleton.find_bone(str(path.get_subname(0)))
			while bone >= 0:
				if bone == spine:
					node.set_filter_path(path, true)
					break
				bone = skeleton.get_bone_parent(bone)


## Starts a swing/cast gesture synced to a server event: a short wind-up, the strike frame, a hit-stop and the recovery.
## `heavy` = a special melee ability; `ranged` = projectile classes (draw/release, hand-cast).
func swing(now_s: float, heavy: bool, speed := 1.5) -> void:
	if _tree == null or _atk_node == null:
		once("attack", now_s, speed)
		return
	var set: Dictionary = ATTACKS.get(cls_id, ATTACKS.mage)
	var list: Array = set.heavy if heavy else set.light
	var pick: Array = list[_atk_n % list.size()]
	_atk_n += 1
	var clip: String = pick[0]
	var contact: float = pick[1]
	var start := maxf(0.0, contact - SWING_LEAD)
	_atk_node.animation = StringName(clip)
	_atk_node.use_custom_timeline = true
	_atk_node.timeline_length = player.get_animation(clip).length
	_atk_node.start_offset = start
	_atk_node.loop_mode = Animation.LOOP_NONE
	_tp("attack_ts/scale", speed)
	_tp("attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_stop_at = now_s + (contact - start) / speed
	_stop_until = -1.0


func _tp(path: String, value: Variant) -> void:
	_tree.set("parameters/" + path, value)


func length_of(anim: String) -> float:
	return _lengths.get(anim, 1.0)


func _clip(anim: String) -> String:
	return _clips.get(anim, anim)


func _play(anim: String, speed: float, blend: float) -> void:
	if not player.has_animation(_clip(anim)):
		return
	if _current != anim:
		player.play(_clip(anim), blend)
		_current = anim
	player.speed_scale = speed


## Picks the animation for the unit's state. `once` animations (attack/hit) hold the floor until they finish.
func drive(now_s: float, alive: bool, stunned: bool, casting: bool, cast_total_ms: float, moving: bool, speed_ratio: float) -> void:
	if _tree != null:
		if _stop_at >= 0.0 and now_s >= _stop_at:  # hit-stop: the attacker's animation holds for a few frames on contact
			_tp("attack_ts/scale", 0.0)
			_stop_until = now_s + HIT_STOP_S
			_stop_at = -1.0
		elif _stop_until >= 0.0 and now_s >= _stop_until:
			_tp("attack_ts/scale", 1.4)
			_stop_until = -1.0
		_tp("death/transition_request", "state_0" if alive else "state_1")
		_tp("state/transition_request", "state_2" if stunned else ("state_1" if casting else "state_0"))
		var run: float = clampf(speed_ratio, 0.0, 1.3) if moving else 0.0
		var xy := move_xy if moving else Vector2.ZERO
		if moving and xy == Vector2.ZERO:
			xy = Vector2(0.0, minf(run, 1.0))   # callers that do not know the direction: forward
		_tp("loco/blend_position", xy)
		_tp("loco_ts/scale", LocoBlend.foot_sync(run * 7.0, 7.0) if run > 0.05 else 1.0)
		return
	if not alive:
		if _current != "death":
			_play("death", 1.0, 0.1)
		return
	if _current == "death":
		_current = ""
	if now_s < _once_until:
		return
	if stunned:
		_play("stun", 1.0, 0.15)
	elif casting:
		var len := length_of("cast")
		_play("cast", clampf(len / maxf(cast_total_ms / 1000.0, 0.3), 0.5, 2.5), 0.1)
	elif moving:
		_play("run", clampf(speed_ratio, 0.6, 1.5), 0.15)
	else:
		_play("idle", 1.0, 0.2)


## Short one-shot animation ("attack", "hit") that takes over for its duration.
func once(anim: String, now_s: float, speed := 1.0) -> void:
	if _tree != null:
		var node := "hit" if anim == "hit" else "attack"
		_tp(node + "_ts/scale", speed)
		_tp(node + "/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		return
	if not player.has_animation(_clip(anim)):
		return
	_current = ""
	player.stop()
	player.play(_clip(anim), 0.05)
	player.speed_scale = speed
	_current = anim
	_once_until = now_s + length_of(anim) / speed


## Jump hop (about 650 ms) as a one-shot over locomotion; no-op for the procedural models.
func jump(_now_s: float) -> void:
	if _tree == null:
		return
	_tp("jump_ts/scale", float(_lengths.get("jump", 0.6)) / 0.65)
	_tp("jump/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
