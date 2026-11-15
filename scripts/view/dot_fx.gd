class_name DotFx
extends Node3D
## Aftermath of a hit: while a unit carries damage over time its body shows it, not only the HUD icon.
## Burning = flames licking up the body, poison = green drips, curses = shadow wisps (denser per curse, thickest with
## Soul Rot). One looping emitter per layer, attached to the unit; particles stay in the world so they trail behind it.

## Particle multiplier of the quality level (1 / 0.6 / 0.3), set by MatchView when the level changes.
static var particles := 1.0

## Layer -> look. `n` particles at full intensity, `rise` = upward pull (negative falls), `speed`, `life`, `size`, `school`.
const LOOK := {
	"burn": {"school": "fire", "n": 28, "rise": 3.6, "speed": 1.0, "life": 0.55, "size": 0.7, "spread": 0.3},
	"poison": {"school": "nature", "n": 14, "rise": -4.0, "speed": 0.4, "life": 0.7, "size": 0.32, "spread": 0.36},
	"curse": {"school": "shadow", "n": 14, "rise": 0.9, "speed": 0.5, "life": 1.3, "size": 0.8, "spread": 0.42},
}
const CURSES := ["corruption", "agony", "soulrot"]
## Body height the layers spread over (character scale VS already applied by the caller).
const BODY_H := 1.3

var _layers := {}   # layer -> CPUParticles3D
var _mat: StandardMaterial3D


## Which layers a unit's crowd-control dictionary turns on, with their intensity (0 = off, 1 = normal, up to 2).
static func layers_for(cc: Dictionary, alive := true) -> Dictionary:
	var out := {"burn": 0.0, "poison": 0.0, "curse": 0.0}
	if not alive:
		return out
	if cc.has("burn"):
		out.burn = 1.0
	if cc.has("poison"):
		out.poison = 1.0
	var curses := 0
	for k in CURSES:
		if cc.has(k):
			curses += 1
	if curses > 0:
		out.curse = minf(2.0, 0.7 + 0.3 * curses + (0.4 if cc.has("soulrot") else 0.0))
	return out


## Particle count of a layer at `intensity`, scaled by the quality level; never 0 while on.
static func amount_for(layer: String, intensity: float, mult: float) -> int:
	if intensity <= 0.0:
		return 0
	return maxi(2, int(round(float(LOOK[layer].n) * intensity * mult)))


## Particle size of a layer at `intensity`: stacking adds wisps but thins each one, so three curses read as a denser
## shroud without swallowing the character.
static func size_for(layer: String, intensity: float) -> float:
	return float(LOOK[layer].size) / pow(maxf(intensity, 1.0), 0.4)


func _init() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = Textures.glow_dot()
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	_mat = mat


func _make(layer: String) -> CPUParticles3D:
	var look: Dictionary = LOOK[layer]
	var pal := SpellSchools.palette(look.school)
	var p := CPUParticles3D.new()
	# The quad itself carries the size: the per-particle scale range does not reach billboarded particles.
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * float(look.size)
	quad.material = _mat
	p.mesh = quad
	p.local_coords = false  # a running unit leaves its flames behind
	p.emitting = false
	p.lifetime = look.life
	p.explosiveness = 0.0
	p.randomness = 0.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(look.spread, BODY_H * 0.45, look.spread)
	p.position.y = BODY_H * 0.5
	p.direction = Vector3.UP
	p.spread = 25.0 if layer != "curse" else 70.0
	p.initial_velocity_min = look.speed * 0.4
	p.initial_velocity_max = look.speed
	p.gravity = Vector3(0, look.rise, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A brief hot flicker, then the school's body colour (not white: additive white on a bright arena reads as smoke).
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.08, 0.45, 1.0])
	var core: Color = pal.core
	var mid: Color = pal.mid
	var edge: Color = pal.edge
	if layer == "curse":  # shadow's palette is near black: added onto the scene it vanishes, so the wisps glow violet
		mid = mid.lightened(0.35)
		edge = mid
	ramp.colors = PackedColorArray([Color(core, 0.0), Color(mid.lerp(core, 0.35), 0.9), Color(mid, 0.7), Color(edge, 0.0)])
	p.color_ramp = ramp
	var shape := Curve.new()  # flames shrink as they rise, wisps swell and thin out
	if layer == "curse":
		shape.add_point(Vector2(0.0, 0.3))
		shape.add_point(Vector2(0.5, 1.0))
		shape.add_point(Vector2(1.0, 0.6))
	else:
		shape.add_point(Vector2(0.0, 1.0))
		shape.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = shape
	if layer == "curse":
		p.tangential_accel_min = 1.5  # wisps coil around the body
		p.tangential_accel_max = 3.0
	add_child(p)
	return p


## Turns layers on and off to match the unit's state. Cheap when nothing changes.
func sync(cc: Dictionary, alive: bool) -> void:
	var want := layers_for(cc, alive)
	for layer in want:
		var n := amount_for(layer, want[layer], particles)
		var p: CPUParticles3D = _layers.get(layer)
		if n == 0:
			if p != null and p.emitting:
				p.emitting = false  # the last flames finish their life instead of vanishing
			continue
		if p == null:
			p = _make(layer)
			_layers[layer] = p
		if p.amount != n:
			p.amount = n  # changing the amount restarts the emitter: only on a real change (a curse added, quality)
			(p.mesh as QuadMesh).size = Vector2.ONE * size_for(layer, want[layer])
		if not p.emitting:
			p.emitting = true


func is_on(layer: String) -> bool:
	return _layers.has(layer) and (_layers[layer] as CPUParticles3D).emitting
