class_name PracticeYard
extends RefCounted
## The "Arena de práctica": which training dummies exist, where they stand and how they behave.
## Dummies are ordinary ArenaUnits flagged with `dummy` (kind): huge health that resets instead of dying, no AI, they can be
## crowd controlled and show debuffs. Kinds: melee, mid (15 m), far (25 m), patrol (walks a line), caster (long spell,
## interruptible), cover (hides behind a pillar), ally (a teammate that is missing health).

const HP := 50000.0
const ALLY_FLOOR := 0.15
const ALLY_START := 0.35
## Health the ally loses per second (fraction of max): there is always something to heal.
const ALLY_DRAIN_PER_S := 0.05
const PATROL_FROM := -14.0
const PATROL_TO := 14.0
const PATROL_Z := 8.0
const CAST_MS := 3000.0
const CAST_GAP_MS := 2500.0
const INTERRUPT_GAP_MS := 4000.0

## kind -> [name, class, spec, x, z, team]
const DUMMIES := {
	"melee": ["Muñeco de cerca", "warrior", "", -1.2, 15.5, "blue"],
	"mid": ["Muñeco a 15 m", "warrior", "", 4.0, 2.5, "blue"],
	"far": ["Muñeco a 25 m", "warrior", "", -4.0, -7.5, "blue"],
	"patrol": ["Muñeco móvil", "warrior", "", PATROL_FROM, PATROL_Z, "blue"],
	"caster": ["Muñeco hechicero", "mage", "fire", 15.0, -2.0, "blue"],
	"cover": ["Muñeco tras el pilar", "warrior", "", -14.0, -2.0, "blue"],
	"ally": ["Aliado herido", "warrior", "", 8.0, 14.0, "red"],
}


## Entries for ArenaMatch: the player first (peer 1... set by the caller via `peer`), then the dummies.
static func entries(player_name: String, cls: String, spec := "", peer := 1) -> Array:
	var out: Array = [{"name": player_name, "cls": cls, "spec": spec, "team": "red", "peer": peer}]
	for kind in DUMMIES:
		var d: Array = DUMMIES[kind]
		out.append({"name": d[0], "cls": d[1], "spec": d[2], "team": d[5], "peer": 0, "dummy": kind, "hp": HP, "x": d[3], "z": d[4]})
	return out
