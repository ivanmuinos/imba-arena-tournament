class_name Progress
extends RefCounted
## Account progression rules, no I/O (docs/progresion-talentos-sinergias.md): every champion levels 1-20 on its own
## (mastery); a match gives XP for the result and for what you did, the first win of the day counts double and games
## against bots count half. ProgressStore keeps the numbers. Talents and skill ranks read the level from here.

const LEVEL_MAX := 20
const WIN_XP := 100
const LOSS_XP := 40
## +1 XP for every this much damage plus healing, up to PERF_MAX.
const PERF_PER := 10
const PERF_MAX := 60
## XP to go from level 1 to 2, and from 19 to 20 (linear in between): about 4 games early on and 12 near the top.
const NEED_FIRST := 400
const NEED_LAST := 1200
## Talent rows open at these champion levels (row 1..4).
const TALENT_ROWS := [5, 10, 15, 20]


## XP needed to go from `level` to the next one (0 at the top).
static func xp_to_next(level: int) -> int:
	if level >= LEVEL_MAX:
		return 0
	var t := float(clampi(level, 1, LEVEL_MAX - 1) - 1) / float(LEVEL_MAX - 2)
	return int(round(lerpf(NEED_FIRST, NEED_LAST, t) / 10.0)) * 10


## XP earned by one match.
static func match_xp(won: bool, dmg: float, heal: float, first_win_today: bool, vs_bots: bool) -> int:
	var xp := (WIN_XP if won else LOSS_XP) + mini(int((maxf(dmg, 0.0) + maxf(heal, 0.0)) / PERF_PER), PERF_MAX)
	if won and first_win_today:
		xp *= 2
	if vs_bots:
		xp = int(xp / 2.0)
	return xp


## Adds `gain` XP to a champion at {level, xp}; returns the new {level, xp} (levels can chain, XP stops at the top).
static func add_xp(state: Dictionary, gain: int) -> Dictionary:
	var level := clampi(int(state.get("level", 1)), 1, LEVEL_MAX)
	var xp := maxi(int(state.get("xp", 0)), 0) + maxi(gain, 0)
	while level < LEVEL_MAX and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
	if level >= LEVEL_MAX:
		xp = 0
	return {"level": level, "xp": xp}


## How many talent rows a champion of `level` has open (0-4).
static func talent_rows(level: int) -> int:
	return TALENT_ROWS.filter(func(l): return level >= l).size()


## Skill rank points earned at `level`: one every 2 levels (10 at the top), spent on the 4 powers, 5 ranks each.
static func rank_points(level: int) -> int:
	return clampi(level, 1, LEVEL_MAX) / 2
