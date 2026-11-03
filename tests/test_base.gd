class_name TestBase
extends RefCounted
## Tiny assertion helpers for the headless test runner.

## Set by the runner so UI tests can add nodes to the live tree.
static var tree: SceneTree = null

var failures: Array[String] = []
var current := ""


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current, msg])


func eq(a, b, msg := "") -> void:
	check(a == b, "%s (esperado %s, obtuvo %s)" % [msg, str(b), str(a)])


func near(a: float, b: float, tol: float, msg := "") -> void:
	check(absf(a - b) <= tol, "%s (esperado ~%s, obtuvo %s)" % [msg, str(b), str(a)])


## Slot that ability `n` of the unit's old 7-slot kit (BotBrain.LEGACY_KITS) has now (see slot_of).
func old(u: ArenaUnit, n: int) -> int:
	var legacy: Array = BotBrain.LEGACY_KITS.get("%s/%s" % [u.cls, u.spec_id], BotBrain.LEGACY_KITS.get(u.cls, []))
	return slot_of(u, legacy[n])


## Slot of ability `id` on the unit. One that is in the reserve gets equipped for the test on slot 3, then 2, then 1
## (each used once per unit), so its mechanics stay covered while it is out of the kit.
func slot_of(u: ArenaUnit, id: String) -> int:
	var ab: Array = u.spec().abilities
	for i in ab.size():
		if ab[i].id == id:
			return i
	var used: Array = u.get_meta("test_equipped", [])
	for slot in [3, 2, 1]:
		if not used.has(slot):
			used.append(slot)
			u.set_meta("test_equipped", used)
			return slot if u.equip(slot, id) else -1
	return -1
