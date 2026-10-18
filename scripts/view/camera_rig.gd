class_name CameraRig
extends Camera3D
## Over-the-shoulder chase camera with mouse orbit/zoom, shake and FOV kicks
## (port of chase/crosshairAim/pickNearCrosshair in src/world.ts).

## Facing angle (same convention as unit rot: forward = (sin yaw, cos yaw)), tilt and distance.
var yaw := 0.0
var pitch := 0.16
var dist := 5.0
## Offset to the right, like modern third-person games.
var shoulder := 0.7
var base_fov := 72.0

var _focus := Vector3.ZERO
var _shake := 0.0
var _fov_kick := 0.0


func _ready() -> void:
	fov = base_fov
	far = 800.0
	near = 0.1


func forward() -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


func add_shake(amount: float) -> void:
	_shake = minf(1.0, _shake + amount)


## Brief field-of-view punch for dashes, blinks and big hits.
func kick(amount: float) -> void:
	_fov_kick = minf(1.0, _fov_kick + amount)


## Mouse look. Returns nothing; sensitivities as in the web client.
func look(relative: Vector2) -> void:
	var st := SettingsStore.shared()
	var sens: float = st.get_value("sens")
	yaw -= relative.x * 0.0028 * sens
	pitch = clampf(pitch + relative.y * 0.0022 * sens * (-1.0 if st.get_value("invert") else 1.0), -0.3, 0.85)


func zoom(delta: float) -> void:
	dist = clampf(dist + delta, 2.5, 10.0)


func chase(x: float, z: float, dt: float, world: ArenaWorld, snap := false) -> void:
	var head := 1.2
	var want := Vector3(x, world.h(x, z) + head, z)
	_focus = want if snap else _focus.lerp(want, 1.0 - exp(-30.0 * dt))
	var f := forward()
	var right := Vector2(-f.y, f.x)
	var pivot := Vector2(_focus.x, _focus.z) + right * shoulder
	var flat := cos(pitch)
	var d := dist
	# Pulled in when a wall or pillar blocks the view.
	var back := pivot - f * d * flat
	var t := Rules.obstacle_hit(world.map, pivot.x, pivot.y, back.x, back.y, 0.35)
	if t >= 0.0:
		d = maxf(1.6, d * t * 0.9)
	var cam := pivot - f * d * flat
	var pos := Vector3(cam.x, maxf(world.h(cam.x, cam.y) + 0.5, _focus.y + 0.25 + d * sin(pitch)), cam.y)
	if _shake > 0.0:
		pos.x += randf_range(-0.5, 0.5) * _shake * 0.25
		pos.y += randf_range(-0.5, 0.5) * _shake * 0.25
		_shake = maxf(0.0, _shake - dt * 3.0)
	position = pos
	# Look straight down the aim line so the crosshair is exactly where shots go.
	look_at(Vector3(pos.x + f.x * flat * 20.0, pos.y - sin(pitch) * 20.0, pos.z + f.y * flat * 20.0))
	world.follow(x, z)
	_fov_kick = maxf(0.0, _fov_kick - dt * 2.2)
	fov = base_fov + _fov_kick * 14.0


## Idle orbit around the arena (behind the menus).
func orbit(t: float, world: ArenaWorld) -> void:
	position = Vector3(sin(t * 0.05) * 62.0, 34.0, cos(t * 0.05) * 62.0)
	look_at(Vector3(0, 2, 0))
	world.follow(0.0, 0.0)
	fov = base_fov


## Slow cinematic flight over the arena (title screen and menus): a drifting loop at low height.
func flythrough(t: float, world: ArenaWorld) -> void:
	var a := t * 0.045
	position = Vector3(sin(a) * 38.0, 21.0 + sin(t * 0.11) * 3.0, cos(a * 1.0) * 27.0)
	look_at(Vector3(sin(a * 0.6 + 1.0) * 6.0, 1.5, cos(a * 0.8) * 5.0))
	world.follow(0.0, 0.0)
	fov = 58.0


## Menu backdrop: a MenuShots sample, with optional depth of field focused on the landmark (alta quality only).
func cinematic(sample: Dictionary, dof_on: bool) -> void:
	position = sample.pos
	look_at(sample.look)
	fov = sample.fov
	if dof_on:
		if attributes == null:
			var ca := CameraAttributesPractical.new()
			ca.dof_blur_far_enabled = true
			ca.dof_blur_near_enabled = true
			ca.dof_blur_amount = 0.06
			ca.dof_blur_far_transition = 12.0
			ca.dof_blur_near_transition = 3.0
			attributes = ca
		var d: float = (sample.pos as Vector3).distance_to(sample.look)
		var a := attributes as CameraAttributesPractical
		a.dof_blur_far_distance = d + 5.0
		a.dof_blur_near_distance = maxf(0.5, d - 7.0)
	elif attributes != null:
		attributes = null


## First point where a ray meets the ground (null if none within `far_m`).
func march_ground(origin: Vector3, dir: Vector3, far_m: float, world: ArenaWorld) -> Variant:
	var prev := 0.0
	var t := 0.5
	while t <= far_m:
		var p := origin + dir * t
		if p.y <= world.h(p.x, p.z) + 0.05:
			var lo := prev
			var hi := t
			for k in 8:
				var mid := (lo + hi) / 2.0
				var q := origin + dir * mid
				if q.y <= world.h(q.x, q.z) + 0.05:
					hi = mid
				else:
					lo = mid
			return origin + dir * hi
		prev = t
		t += 0.5
	return null


## Index of the candidate closest to the crosshair, within a small cone (-1 = none).
func pick_near_crosshair(points: Array, max_angle := 0.2) -> int:
	var fwd := -global_transform.basis.z
	var best := -1
	var best_a := max_angle
	for i in points.size():
		var dir: Vector3 = (points[i] - global_position).normalized()
		var a := fwd.angle_to(dir)
		if a < best_a:
			best_a = a
			best = i
	return best
