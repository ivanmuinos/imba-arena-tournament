class_name StepCadence
extends RefCounted
## When a walking unit's foot lands: one step per stride, and the stride shortens as it goes faster (a slowed unit
## takes fewer steps per second, a hasted one more). No steps in the air or standing still.

const STRIDE_S := 0.33  # seconds between footfalls at the unit's own run speed
const MIN_SPEED := 0.5

var _t := 0.0


## Advances by `dt`; true on the frame a foot lands.
func advance(dt: float, speed: float, run_speed: float, grounded: bool) -> bool:
	if not grounded or speed < MIN_SPEED:
		_t = STRIDE_S * 0.5  # the first step comes half a stride after it starts walking
		return false
	_t += dt * clampf(speed / maxf(run_speed, 0.1), 0.4, 1.6)
	if _t < STRIDE_S:
		return false
	_t -= STRIDE_S
	return true
