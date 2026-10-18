class_name PracticeMeter
extends RefCounted
## DPS meter of the practice arena (server side: the numbers are authoritative and travel in the snapshot).
## Per ability: damage, hits, crits and casts; healing done; DPS over the last 10 s and since the first hit.

const WINDOW_MS := 10000.0

var _rows := {}      # ability id -> {dmg, hits, crits, casts}
var _events: Array = []  # [at_ms, amount] inside the window
var _total := 0.0
var _heal := 0.0
var _first_at := -1.0


func reset(_now := 0.0) -> void:
	_rows.clear()
	_events.clear()
	_total = 0.0
	_heal = 0.0
	_first_at = -1.0


func _row(id: String) -> Dictionary:
	if not _rows.has(id):
		_rows[id] = {"dmg": 0.0, "hits": 0, "crits": 0, "casts": 0}
	return _rows[id]


func record_cast(id: String, _now: float) -> void:
	_row(id).casts += 1


func record_damage(id: String, amount: float, crit: bool, now: float) -> void:
	if amount <= 0.0:
		return
	var r := _row(id)
	r.dmg += amount
	r.hits += 1
	if crit:
		r.crits += 1
	_total += amount
	if _first_at < 0.0:
		_first_at = now
	_events.append([now, amount])
	_trim(now)


func record_heal(amount: float, _now: float) -> void:
	if amount > 0.0:
		_heal += amount


func _trim(now: float) -> void:
	while not _events.is_empty() and _events[0][0] <= now - WINDOW_MS:
		_events.pop_front()


## {total, dps (since the first hit), dps10 (last 10 s), heal, rows: [{id, dmg, pct, hits, crits, casts}] by damage}.
func snapshot(now: float) -> Dictionary:
	_trim(now)
	var recent := 0.0
	for e in _events:
		recent += e[1]
	var since := maxf(1000.0, now - _first_at) if _first_at >= 0.0 else 1000.0
	var window := minf(WINDOW_MS, since)
	var rows: Array = []
	for id in _rows:
		var r: Dictionary = _rows[id]
		rows.append({"id": id, "dmg": roundi(r.dmg), "pct": r.dmg / _total * 100.0 if _total > 0.0 else 0.0, "hits": r.hits, "crits": r.crits, "casts": r.casts})
	rows.sort_custom(func(a, b): return a.dmg > b.dmg or (a.dmg == b.dmg and a.casts > b.casts))
	return {
		"total": roundi(_total),
		"dps": _total / (since / 1000.0) if _first_at >= 0.0 else 0.0,
		"dps10": recent / (window / 1000.0),
		"heal": roundi(_heal),
		"rows": rows,
	}
