class_name InputLogic
extends RefCounted
## Key/mouse mapping that does not depend on the scene tree.

const SLOT_BY_KEY := {KEY_1: 0, KEY_2: 1, KEY_3: 2, KEY_4: 3, KEY_5: 4, KEY_6: 5, KEY_7: 6}
const DRAG_PX := 5.0
const FOLLOW_RATE := 4.0
const TURN_RATE := 2.6
const PAD_DEADZONE := 0.2


static func stick(raw: Vector2) -> Vector2:
	var length := raw.length()
	return Vector2.ZERO if length <= PAD_DEADZONE else raw.normalized() * clampf((length - PAD_DEADZONE) / (1.0 - PAD_DEADZONE), 0.0, 1.0)


static func pad_slot(button: int) -> int:
	return [JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_B, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT].find(button)


static func slot_for_key(keycode: int) -> int:
	return SLOT_BY_KEY.get(keycode, -1)


## WASD relative to where the camera looks: forward/back and strafe are -1/0/1.
## Returns (dx, dz) in game coordinates, normalised when diagonal.
static func move_vector(fwd: float, strafe: float, yaw: float) -> Vector2:
	var f := Vector2(sin(yaw), cos(yaw))
	var right := Vector2(-f.y, f.x)  # forward x up
	var v := f * float(fwd) + right * float(strafe)
	return v.normalized() if v.length() > 1.0 else v


## Which camera mode the held buttons mean: "none", "orbit" (left: camera only) or "mouselook" (right: camera + character).
static func mouse_mode(lmb: bool, rmb: bool) -> String:
	if rmb:
		return "mouselook"
	return "orbit" if lmb else "none"


## A press becomes a drag once the cursor moved a few pixels (otherwise it is a click).
static func is_drag(press: Vector2, now: Vector2, threshold := DRAG_PX) -> bool:
	return press.distance_to(now) > threshold


## Keyboard to movement, WoW default: A/D turn the character, unless the right button is held (then they strafe);
## both buttons held = run forward. Returns {fwd, strafe, turn} (turn +1 = to the left).
static func keyboard_move(w: bool, s: bool, a: bool, d: bool, rmb: bool, lmb: bool, q := false, e := false) -> Dictionary:
	var fwd := int(w) - int(s)
	if lmb and rmb:
		fwd = clampi(fwd + 1, -1, 1)
	var strafe := 0
	var turn := 0
	if rmb:
		strafe = int(d) - int(a)
	else:
		turn = int(a) - int(d)
	return {"fwd": fwd, "strafe": clampi(strafe + int(e) - int(q), -1, 1), "turn": turn}


## Camera yaw easing back behind the character while moving with no mouse button held.
static func follow_yaw(cam_yaw: float, face: float, dt: float, moving: bool, any_button: bool) -> float:
	if not moving or any_button:
		return cam_yaw
	return lerp_angle(cam_yaw, face, 1.0 - exp(-FOLLOW_RATE * dt))
