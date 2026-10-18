class_name Predictor
extends RefCounted
## Client-side prediction for the local unit (port of the frame loop in src/main.ts): the
## same movement rules as the server, gently corrected towards the authoritative position.

class Mover:
	extends RefCounted
	var x := 0.0
	var z := 0.0
	var vx := 0.0
	var vz := 0.0
	var dash_left := 0.0
	var dash_vx := 0.0
	var dash_vz := 0.0

var m := Mover.new()
## While a predicted blink/disengage is in flight, ignore server corrections (ms, local clock).
var predict_until := 0.0
var last_phase := ""


func place(x: float, z: float) -> void:
	m.x = x
	m.z = z
	m.vx = 0.0
	m.vz = 0.0
	m.dash_left = 0.0


static func speed_for(cls: String, me: Dictionary) -> float:
	var s: float = GameData.classes[cls].speed
	if me.cc.has("slow"):
		s *= 0.5
	if me.buffs.has("haste"):
		s *= GameData.C.HASTE_MULT
	return s


## Called for every new snapshot: snaps the prediction on phase changes, big errors and death.
func on_state(me: Dictionary, phase: String, now_ms: float) -> void:
	var phase_changed := phase != last_phase
	last_phase = phase
	if now_ms > predict_until and (phase_changed or Vector2(me.x - m.x, me.z - m.z).length() > 2.5 or not me.alive):
		place(me.x, me.z)


## Advances the local unit one frame. `age_s` = seconds since the last snapshot arrived.
func step(dt: float, input: Vector2, me: Dictionary, cls: String, fighting: bool, map: GameMap, age_s: float, now_ms: float) -> void:
	var cc: Dictionary = me.cc
	if cc.has("fear") or me.get("dashing", false):
		# Server-driven movement: follow it instead of predicting.
		var k := 1.0 - exp(-14.0 * dt)
		m.x += (me.x - m.x) * k
		m.z += (me.z - m.z) * k
		m.vx = 0.0
		m.vz = 0.0
		return
	var casting_still: bool = me.cast != null and input.length() < 1e-6
	var can_move: bool = fighting and me.alive and not cc.has("stun") and not cc.has("incap") and not cc.has("root") and not casting_still
	Rules.step_mover(m, input.x, input.y, dt, speed_for(cls, me), can_move, map)
	if age_s < 0.1 and now_ms > predict_until:
		var c := 1.0 - exp(-(2.0 if m.dash_left > 0.0 else 7.0) * dt)
		m.x += (me.x - m.x) * c
		m.z += (me.z - m.z) * c


## Blink (mage) and Disengage (hunter) feel instant: apply them locally, the server confirms.
## `dir` = direction to move in (blink) / to flee from (disengage). Returns true if predicted.
func predict_movement(cls: String, slot: int, dir: Vector2, me: Dictionary, map: GameMap, now_ms: float) -> bool:
	if slot != 4 or (cls != "mage" and cls != "hunter") or me.cc.has("stun") or me.cc.has("incap"):
		return false
	var len := maxf(dir.length(), 1e-6)
	var d := dir / len
	var spec := GameData.ability(cls, 4)
	if cls == "mage":
		var p := Rules.blink_target(map, m.x, m.z, d.x, d.y, spec.dist)
		m.x = p.x
		m.z = p.y
	elif not me.cc.has("root"):
		m.dash_left = 0.28
		m.dash_vx = -d.x * (spec.dist / 0.28)
		m.dash_vz = -d.y * (spec.dist / 0.28)
	else:
		return false
	predict_until = now_ms + 350.0
	return true
