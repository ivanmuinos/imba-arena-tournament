class_name MenuShots
extends RefCounted
## Cinematic camera shots over the arena behind the menus: eye level to three-quarter views that dolly or orbit a
## hero landmark of the map, cutting every SHOT_LEN seconds through a short dip to black. Pure maths, unit tested
## (the camera must never end up inside a wall, pillar or statue).

const SHOT_LEN := 9.0
const SHOTS := 3
const FADE := 0.45
const LIMIT_X := 24.0
const LIMIT_Z := 19.0

## map -> {look: landmark (y = height of the point the camera looks at), r: orbit half-width in x, rz: in z, h: eye height}
const LANDMARKS := {
	"bridge": {"look": Vector3(0, 1.2, 0), "r": 13.0, "rz": 10.0, "h": 2.4},
	"pillars": {"look": Vector3(10, 4.0, 0), "r": 9.0, "rz": 8.0, "h": 2.4},
	"tomb": {"look": Vector3(0, 6.0, 0), "r": 14.0, "rz": 12.0, "h": 2.2},
	"living": {"look": Vector3(0, 3.5, 0), "r": 15.0, "rz": 12.0, "h": 2.4},
	"spire": {"look": Vector3(0, 4.0, 0), "r": 7.5, "rz": 6.5, "h": 2.4},
}


static func landmark(map_id: String) -> Dictionary:
	return LANDMARKS.get(map_id, LANDMARKS.bridge)


## {pos, look, fov} of `shot` (0..SHOTS-1) at `t` seconds into it.
static func sample(map_id: String, shot: int, t: float) -> Dictionary:
	var lm := landmark(map_id)
	var c: Vector3 = lm.look
	var r: float = lm.r
	var rz: float = lm.rz
	var h: float = lm.h
	var pos := Vector3.ZERO
	var look := c
	var fov := 52.0
	match shot % SHOTS:
		0:  # low orbit around the landmark, looking slightly up at it
			var a := 0.4 + 0.075 * t
			pos = Vector3(c.x + cos(a) * r, h + 0.35 * sin(t * 0.5), c.z + sin(a) * rz)
			look = Vector3(c.x, c.y, c.z)
			fov = 54.0
		1:  # slow dolly in from the side at eye level
			var k := clampf(t / SHOT_LEN, 0.0, 1.0)
			var a := lerpf(2.5, 2.95, k)
			var rr := lerpf(1.15, 0.92, k)
			pos = Vector3(c.x + cos(a) * r * rr, lerpf(h - 0.4, h + 0.2, k), c.z + sin(a) * rz * rr)
			look = Vector3(c.x, c.y - 0.5, c.z)
			fov = lerpf(58.0, 50.0, k)
		_:  # three-quarter orbit the other way, higher
			var a := 4.2 - 0.05 * t
			pos = Vector3(c.x + cos(a) * r * 1.2, h + 4.2 + 0.4 * sin(t * 0.4), c.z + sin(a) * rz * 1.2)
			look = Vector3(c.x, c.y - 0.8, c.z)
			fov = 46.0
	pos.x = clampf(pos.x, -LIMIT_X, LIMIT_X)
	pos.z = clampf(pos.z, -LIMIT_Z, LIMIT_Z)
	return {"pos": pos, "look": look, "fov": fov}


## Which shot plays `elapsed` seconds after the menu opened: {shot, t, dark} (dark = 0..1 amount of the dip to black).
static func at(elapsed: float, first_shot := 0) -> Dictionary:
	var n := int(floor(elapsed / SHOT_LEN))
	var t := elapsed - n * SHOT_LEN
	var edge := minf(t, SHOT_LEN - t)
	return {"shot": (first_shot + n) % SHOTS, "t": t, "dark": clampf(1.0 - edge / FADE, 0.0, 1.0)}
