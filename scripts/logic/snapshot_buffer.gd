class_name SnapshotBuffer
extends RefCounted
## Keeps the latest server snapshots and samples unit transforms a little in the past, so
## other players move smoothly between the ~30 Hz updates. `ts` is the server's sim clock (ms).

const DELAY_MS := 100.0
const MAX_SNAPS := 16

var _snaps: Array = []  # [{ts, units: {id: unit}, snap}]
## local_clock - server_clock, smoothed but pulled down by the fastest packets.
var offset := NAN


func clear() -> void:
	_snaps.clear()
	offset = NAN


func is_empty() -> bool:
	return _snaps.is_empty()


## Stores a snapshot received at local time `local_ms`. Out-of-order ones are dropped.
func push(snap: Dictionary, local_ms: float) -> bool:
	var ts: float = snap.get("ts", 0.0)
	if not _snaps.is_empty() and ts <= _snaps[-1].ts:
		return false
	var by_id := {}
	for u in snap.units:
		by_id[int(u.id)] = u
	_snaps.append({"ts": ts, "units": by_id, "snap": snap})
	if _snaps.size() > MAX_SNAPS:
		_snaps.pop_front()
	var raw := local_ms - ts
	if is_nan(offset) or raw < offset - 30.0:
		offset = raw
	else:
		offset += (raw - offset) * 0.05
	return true


func latest() -> Dictionary:
	return _snaps[-1].snap if not _snaps.is_empty() else {}


func latest_ts() -> float:
	return _snaps[-1].ts if not _snaps.is_empty() else 0.0


## Server time to render at, given the local clock.
func render_time(local_ms: float) -> float:
	return local_ms - offset - DELAY_MS


## Interpolated {id: {x, z, rot, unit}} for every unit present in the newest snapshot
## (units missing from it are not visible to us and must not be shown).
func sample(local_ms: float) -> Dictionary:
	var out := {}
	if _snaps.is_empty():
		return out
	var t := render_time(local_ms)
	var newest: Dictionary = _snaps[-1]
	var a: Dictionary = _snaps[0]
	var b: Dictionary = _snaps[0]
	if t >= newest.ts:
		a = newest
		b = newest
	elif t > _snaps[0].ts:
		for i in range(_snaps.size() - 1):
			if _snaps[i].ts <= t and t <= _snaps[i + 1].ts:
				a = _snaps[i]
				b = _snaps[i + 1]
				break
	for id in newest.units:
		var cur: Dictionary = newest.units[id]
		var ua = a.units.get(id)
		var ub = b.units.get(id)
		var x: float = cur.x
		var z: float = cur.z
		var rot: float = cur.rot
		if ua != null and ub != null:
			var span: float = b.ts - a.ts
			var k := clampf((t - a.ts) / span, 0.0, 1.0) if span > 0.0 else 1.0
			x = lerpf(ua.x, ub.x, k)
			z = lerpf(ua.z, ub.z, k)
			rot = lerp_angle(ua.rot, ub.rot, k)
			# Teleports (blink, charge, new round) must not slide across the map.
			if Vector2(ub.x - ua.x, ub.z - ua.z).length() > 6.0:
				x = ub.x
				z = ub.z
		elif ub != null:
			x = ub.x
			z = ub.z
			rot = ub.rot
		out[id] = {"x": x, "z": z, "rot": rot, "unit": cur}
	return out
