class_name FxFilter
extends RefCounted
## Stealth rule for events: the server never tells a team about something that would reveal a
## unit it cannot see (a hit, a cast, a blink out of a bush...).

const ID_EVENTS := ["hit", "heal", "power", "absorb", "charge", "swing", "label", "cast", "breath", "trinket"]
const NEAR := 2.0


## Events from match.fx that `team` is allowed to know about.
static func for_team(m: ArenaMatch, team: String, now: float) -> Array:
	var out: Array = []
	for f in m.fx:
		if _allowed(m, team, f, now):
			out.append(f)
	return out


static func _hidden_enemy_near(m: ArenaMatch, team: String, x: float, z: float, now: float) -> bool:
	for u in m.units:
		if u.team != team and Vector2(u.x - x, u.z - z).length() < NEAR and not m.team_can_see(team, u, now):
			return true
	return false


static func _allowed(m: ArenaMatch, team: String, f: Dictionary, now: float) -> bool:
	var k: String = f.k
	if k in ID_EVENTS:
		var u := m.unit_by_id(int(f.id))
		return u != null and (u.team == team or m.team_can_see(team, u, now))
	match k:
		"death":
			return true
		"blink":
			return not _hidden_enemy_near(m, team, f.x0, f.z0, now) and not _hidden_enemy_near(m, team, f.x1, f.z1, now)
		_:
			return not _hidden_enemy_near(m, team, f.x, f.z, now)
