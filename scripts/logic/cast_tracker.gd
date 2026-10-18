class_name CastTracker
extends RefCounted
## Follows the local player's cast from snapshots: tells the HUD when a cast started, finished or was interrupted.
## A cast that disappears with more than SLACK_MS left was cut short (movement, jump, Esc, silence/stun...).

const SLACK_MS := 160.0

var slot := -1
var total := 0.0
var left := 0.0
var _active := false


## cast: the snapshot's {slot, total, left} or null. Returns "" | "start" | "complete" | "interrupted".
func update(cast) -> String:
	if cast != null:
		var fresh := not _active or int(cast.slot) != slot
		_active = true
		slot = int(cast.slot)
		total = float(cast.total)
		left = float(cast.left)
		return "start" if fresh else ""
	if _active:
		_active = false
		return "complete" if left <= SLACK_MS else "interrupted"
	return ""


func active() -> bool:
	return _active


## 0..1 progress of the current cast.
func progress() -> float:
	return clampf(1.0 - left / maxf(total, 1.0), 0.0, 1.0)
