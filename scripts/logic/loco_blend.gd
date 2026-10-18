class_name LocoBlend
extends RefCounted
## Locomotion blend coordinates: ground velocity relative to where the character faces -> a point on the 2D blend space
## (x = strafe right +, y = forward +), so backpedalling and strafing use their own clips instead of moonwalking.

const BACK_SCALE := 0.7   # how far "full speed backwards" sits on the y axis (walking backwards is slower)


## vel: world velocity on the ground (x, z). rot: facing yaw (forward = (sin, cos)). full_speed: the class run speed.
static func blend_xy(vel: Vector2, rot: float, full_speed: float) -> Vector2:
	if full_speed <= 0.01 or vel.length() < 0.3:
		return Vector2.ZERO
	var fwd := Vector2(sin(rot), cos(rot))
	var right := Vector2(cos(rot), -sin(rot))
	var f := vel.dot(fwd) / full_speed
	var r := vel.dot(right) / full_speed
	return Vector2(clampf(r, -1.0, 1.0), clampf(f, -BACK_SCALE, 1.0))


## Playback speed multiplier that keeps the feet planted: actual ground speed over the speed the clip was authored for.
static func foot_sync(speed: float, full_speed: float) -> float:
	if full_speed <= 0.01 or speed < 0.3:
		return 1.0
	return clampf(speed / full_speed * 1.25, 0.7, 1.7)
