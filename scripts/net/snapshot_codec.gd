class_name SnapshotCodec
extends RefCounted
## Compact wire form of ArenaMatch.snapshot_for(): numbers go into PackedFloat32Arrays instead
## of one dictionary per entity, which keeps a snapshot far below one MTU (ENet fragments and
## drops large unreliable packets). pack() and unpack() are exact inverses up to float32.

const U := 12  # id, x, z, rot, hp, alive, dashing, jump, cast slot/total/left/target id
const P := 6   # id, kind, x, z, vx, vz
const A := 6   # id, x, z, r, left, kind (index into the ability ids)
const T := 4   # id, x, z, armed
const W := 4   # id, kind, x, z

static var _ability_ids: Array = []
static var _power_kinds: Array = []


static func _tables() -> void:
	if not _ability_ids.is_empty():
		return
	GameData.ensure_loaded()
	var ids := {}
	for cls in GameData.classes:
		for a in GameData.classes[cls].abilities:
			ids[a.id] = true
		for sid in GameData.spec_ids(cls):
			for a in GameData.abilities(cls, sid):
				ids[a.id] = true
	_ability_ids = ids.keys()
	_ability_ids.sort()
	_power_kinds = GameData.powers.keys()
	_power_kinds.sort()


static func pack(s: Dictionary) -> Dictionary:
	_tables()
	var u := PackedFloat32Array()
	var effects := {}
	for x in s.units:
		var c = x.cast
		u.append_array(PackedFloat32Array([x.id, x.x, x.z, x.rot, x.hp, 1.0 if x.alive else 0.0, 1.0 if x.dashing else 0.0, x.jump,
			c.slot if c != null else -1.0, c.total if c != null else 0.0, c.left if c != null else 0.0, c.get("tid", -1) if c != null else -1.0]))
		if not x.cc.is_empty() or not x.buffs.is_empty():
			effects[int(x.id)] = [x.cc, x.buffs]
	var pr := PackedFloat32Array()
	for p in s.projs:
		pr.append_array(PackedFloat32Array([p.id, _ability_ids.find(p.kind), p.x, p.z, p.vx, p.vz]))
	var ao := PackedFloat32Array()
	for a in s.aoes:
		ao.append_array(PackedFloat32Array([a.id, a.x, a.z, a.r, a.left, _ability_ids.find(a.get("kind", "meteor"))]))
	var tr := PackedFloat32Array()
	for t in s.traps:
		tr.append_array(PackedFloat32Array([t.id, t.x, t.z, 1.0 if t.armed else 0.0]))
	var pw := PackedFloat32Array()
	for p in s.powers:
		pw.append_array(PackedFloat32Array([p.id, _power_kinds.find(p.kind), p.x, p.z]))
	return {
		"t": "state", "ts": s.get("ts", 0.0), "phase": s.phase, "phaseLeft": s.phaseLeft, "round": s.round,
		"sr": s.score.red, "sb": s.score.blue, "damp": s.damp, "gt": s.gates, "ft": s.ft,
		"u": u, "e": effects, "pr": pr, "ao": ao, "tr": tr, "pw": pw, "you": s.you,
	}


static func unpack(m: Dictionary) -> Dictionary:
	_tables()
	var units: Array = []
	var u: PackedFloat32Array = m.u
	for i in range(0, u.size(), U):
		var id := int(u[i])
		var eff: Array = m.e.get(id, [{}, {}])
		units.append({
			"id": id, "x": u[i + 1], "z": u[i + 2], "rot": u[i + 3], "hp": int(u[i + 4]), "alive": u[i + 5] > 0.5,
			"dashing": u[i + 6] > 0.5, "jump": int(u[i + 7]),
			"cast": null if u[i + 8] < 0 else {"slot": int(u[i + 8]), "total": u[i + 9], "left": u[i + 10], "tid": int(u[i + 11])},
			"cc": eff[0], "buffs": eff[1],
		})
	var projs: Array = []
	var pr: PackedFloat32Array = m.pr
	for i in range(0, pr.size(), P):
		projs.append({"id": int(pr[i]), "kind": _ability_ids[int(pr[i + 1])], "x": pr[i + 2], "z": pr[i + 3], "vx": pr[i + 4], "vz": pr[i + 5]})
	var aoes: Array = []
	var ao: PackedFloat32Array = m.ao
	for i in range(0, ao.size(), A):
		aoes.append({"id": int(ao[i]), "x": ao[i + 1], "z": ao[i + 2], "r": ao[i + 3], "left": ao[i + 4], "kind": _ability_ids[int(ao[i + 5])] if int(ao[i + 5]) >= 0 and int(ao[i + 5]) < _ability_ids.size() else "meteor"})
	var traps: Array = []
	var tr: PackedFloat32Array = m.tr
	for i in range(0, tr.size(), T):
		traps.append({"id": int(tr[i]), "x": tr[i + 1], "z": tr[i + 2], "armed": tr[i + 3] > 0.5})
	var powers: Array = []
	var pw: PackedFloat32Array = m.pw
	for i in range(0, pw.size(), W):
		powers.append({"id": int(pw[i]), "kind": _power_kinds[int(pw[i + 1])], "x": pw[i + 2], "z": pw[i + 3]})
	return {
		"t": "state", "ts": m.ts, "phase": m.phase, "phaseLeft": m.phaseLeft, "round": int(m.round),
		"score": {"red": int(m.sr), "blue": int(m.sb)}, "damp": m.damp, "gates": bool(m.gt), "ft": m.ft,
		"units": units, "projs": projs, "aoes": aoes, "traps": traps, "powers": powers, "you": m.you,
	}


## True when `m` has the shape of a packed state (guards the client against bad servers).
static func is_valid(m: Dictionary) -> bool:
	for k in ["ts", "phase", "phaseLeft", "round", "sr", "sb", "damp", "gt", "ft", "u", "e", "pr", "ao", "tr", "pw", "you"]:
		if not m.has(k):
			return false
	for k in ["u", "pr", "ao", "tr", "pw"]:
		if typeof(m[k]) != TYPE_PACKED_FLOAT32_ARRAY:
			return false
	return m.u.size() % U == 0 and m.pr.size() % P == 0 and m.ao.size() % A == 0 and m.tr.size() % T == 0 and m.pw.size() % W == 0 and typeof(m.e) == TYPE_DICTIONARY and typeof(m.you) == TYPE_DICTIONARY
