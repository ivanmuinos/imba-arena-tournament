class_name Wire
extends RefCounted
## Message (de)serialization and validation. Everything that arrives from the network goes
## through here: no objects are ever decoded, numbers must be finite, ranges are clamped.

const MAX_ABS_AIM := 96.0
const CHAT_MAX := 240


static func clean_chat(m: Dictionary) -> String:
	if typeof(m.get("text")) != TYPE_STRING or m.text.length() > CHAT_MAX:
		return ""
	var text := ""
	for ch in m.text:
		var code: int = ch.unicode_at(0)
		if code >= 32 and code != 127 and not (code >= 0x202a and code <= 0x202e) and not (code >= 0x2066 and code <= 0x2069):
			text += ch
		else:
			text += " "
	return " ".join(text.split(" ", false)).strip_edges()


static func encode(msg: Dictionary) -> PackedByteArray:
	return var_to_bytes(msg)


## Returns the decoded message, or null when the bytes are not a valid {"t": String, ...}.
static func decode(bytes: PackedByteArray) -> Variant:
	if bytes.is_empty():
		return null
	var v = bytes_to_var(bytes)  # bytes_to_var never instantiates Objects
	if typeof(v) != TYPE_DICTIONARY or not v.has("t") or typeof(v.t) != TYPE_STRING:
		return null
	return v


static func _num(v) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v))


## {dx, dz, ax, az} sanitised, or {} when the message is malformed.
static func clean_input(m: Dictionary) -> Dictionary:
	for k in ["dx", "dz", "ax", "az"]:
		if not _num(m.get(k)):
			return {}
	return {
		"dx": clampf(float(m.dx), -1.0, 1.0), "dz": clampf(float(m.dz), -1.0, 1.0),
		"ax": clampf(float(m.ax), -MAX_ABS_AIM, MAX_ABS_AIM), "az": clampf(float(m.az), -MAX_ABS_AIM, MAX_ABS_AIM),
	}


## {slot, ax, az, target} (target -1 = none), or {} when malformed.
static func clean_cast(m: Dictionary) -> Dictionary:
	if typeof(m.get("slot")) != TYPE_INT and typeof(m.get("slot")) != TYPE_FLOAT:
		return {}
	var slot := int(m.slot)
	if slot < 0 or slot >= int(GameData.C.SLOT_COUNT) or not _num(m.get("ax")) or not _num(m.get("az")):
		return {}
	var target := -1
	if _num(m.get("target")):
		target = int(m.target)
	return {
		"slot": slot, "target": target,
		"ax": clampf(float(m.ax), -MAX_ABS_AIM, MAX_ABS_AIM), "az": clampf(float(m.az), -MAX_ABS_AIM, MAX_ABS_AIM),
	}


const PRACTICE_CMDS := ["reset", "nocd", "ult", "stun"]


## {cmd, on} for the practice arena controls, or {} when malformed.
static func clean_practice(m: Dictionary) -> Dictionary:
	if typeof(m.get("cmd")) != TYPE_STRING or not PRACTICE_CMDS.has(m.cmd):
		return {}
	return {"cmd": m.cmd, "on": bool(m.get("on", true))}
