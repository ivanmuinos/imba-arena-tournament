class_name AutoQuality
extends RefCounted
## Drops one quality level when fps stays under the threshold for a few seconds in a row.

const LOW_FPS := 54  # 90% of the 60 FPS floor; lowering resolution alone may not fix expensive effects
const NEEDED := 4
const COOLDOWN_MS := 6000.0

var _bad := 0
var _last_change := -1e9


static func real_delta(delta: float, time_scale: float) -> float:
	return delta / maxf(time_scale, 0.01)


## Call once per second with the measured fps. Returns the level to use.
func feed(fps: int, now_ms: float, level: String) -> String:
	if fps >= LOW_FPS:
		_bad = 0
		return level
	if now_ms - _last_change < COOLDOWN_MS:
		return level
	_bad += 1
	if _bad >= NEEDED:
		_bad = 0
		var lower := Quality.lower(level)
		if lower != level:
			_last_change = now_ms
		return lower
	return level


# ---------------------------------------------------------------- dynamic resolution (tried before dropping a whole level)

const MIN_SCALE := 0.5
const SCALE_STEP := 0.1
const SCALE_COOLDOWN_MS := 2500.0
const RECOVER_S := 12

var _slow := 0
var _fast := 0
var _last_scale_change := -1e9


func at_floor(scale: float) -> bool:
	return scale <= MIN_SCALE + 1e-6


## Call once per second. Two slow seconds in a row lower the 3D render scale by one step (with a cooldown); a long run of
## comfortable fps raises it again, never above `base` (the scale the pixel budget allows).
func step_scale(fps: int, now_ms: float, scale: float, base: float, target_fps: int) -> float:
	if fps < target_fps * 0.9:
		_fast = 0
		_slow += 1
		if _slow >= 2 and now_ms - _last_scale_change >= SCALE_COOLDOWN_MS and not at_floor(scale):
			_slow = 0
			_last_scale_change = now_ms
			return maxf(MIN_SCALE, snappedf(scale - SCALE_STEP, 0.05))
		return scale
	_slow = 0
	if fps >= target_fps * 1.15 and scale < base - 1e-6:
		_fast += 1
		if _fast >= RECOVER_S and now_ms - _last_scale_change >= SCALE_COOLDOWN_MS:
			_fast = 0
			_last_scale_change = now_ms
			return minf(base, snappedf(scale + 0.05, 0.05))
	else:
		_fast = 0
	return scale
