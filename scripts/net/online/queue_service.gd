class_name QueueService
extends RefCounted
## Client side of the normal queue (1v1, 2v2, 3v3) and of play groups. Pairing, sides, host and the hidden skill live on
## the server; this class sends the calls, polls `queue_status`, and tells the game when a match is formed and when the
## host's Steam lobby id is known. It never sees skill: no RPC returns it.
##
## Flow: join -> poll every few seconds -> match_found (sides and host chosen by the server) -> the host opens a Steam
## lobby and publishes its id (publish_lobby); guests get lobby_published and join it -> after the match both sides
## report the winner (report_result), then finish() frees the slot. Quitting a match calls abandon() (no report).
## Every call ends in `cb(result)` (see OnlineApi) and quietly says "unavailable" when Supabase cannot be reached.

## The group, its invitations or the queue state changed.
signal changed
## A match was formed for us (once per match). `info`: {id, host, is_host, lobby_id, side, sides}.
signal match_found(info: Dictionary)
## A guest learns the host's Steam lobby id (once per match).
signal lobby_published(info: Dictionary)

const POLL_SEARCHING := 6.0
const POLL_MATCHED := 3.0
const POLL_GROUP := 8.0

var api: OnlineApi
## idle | searching | matched
var state := "idle"
var mode := 0
## People searching in our mode, and how long we have waited (seconds).
var searching := 0
var wait := 0
## The server's match info while matched ({} otherwise).
var current := {}
## Our confirmed group ({id, mode, team_id, leader, queued, members: [{steam_id, name, confirmed}]}) or {}.
var group := {}
## Invitations to join someone's group: [{id, mode, from, from_name, team_name}]
var group_invites: Array = []
var version := GameServer.game_version()

var _acc := 0.0
var _polling := false
var _announced := ""
var _lobby_announced := ""
var _reported := ""


func _init(p_api: OnlineApi) -> void:
	api = p_api


# ---------------------------------------------------------------- pure helpers

## Seconds between polls for a state (0: do not poll).
static func poll_interval(p_state: String, in_group: bool) -> float:
	match p_state:
		"searching": return POLL_SEARCHING
		"matched": return POLL_MATCHED
	return POLL_GROUP if in_group else 0.0


## {steam_id text: "red"|"blue"} from a match info.
static func side_map(info: Dictionary) -> Dictionary:
	var out := {}
	var sides = info.get("sides", {})
	if typeof(sides) != TYPE_DICTIONARY:
		return out
	for side in ["red", "blue"]:
		for p in sides.get(side, []):
			out[str(p.get("steam_id", ""))] = side
	return out


static func error_text(code: String) -> String:
	match code:
		"invalid_mode": return "Esa modalidad no está disponible para este grupo."
		"invalid_version": return "No se pudo identificar la versión del juego."
		"already_in_group": return "Ya estás en un grupo."
		"not_leader": return "Solo quien armó el grupo puede hacer eso."
		"group_not_found": return "El grupo ya no existe."
		"group_full": return "El grupo está completo."
		"not_confirmed": return "Faltan jugadores por confirmar."
		"group_locked": return "No se puede cambiar el grupo mientras busca partida."
		"already_queued": return "Ya estás buscando partida."
		"already_in_match": return "Ya tenés una partida en curso."
		"not_in_match": return "No tenés una partida en cola."
		"not_host": return "Solo el anfitrión puede hacer eso."
		"invalid_lobby": return "La sala no es válida."
		"invalid_winner": return "Resultado inválido."
		"already_reported": return "Ya informaste el resultado."
		"match_closed": return "La partida ya se cerró."
		"rate_limited": return "Demasiados intentos. Esperá un momento."
		"not_member": return "Ese jugador no es del equipo."
		"not_captain": return "Solo el capitán puede hacer eso."
		"invalid_target": return "Ese jugador no es válido para esta acción."
		"already_invited": return "Ya invitaste a ese jugador."
		"invitee_inbox_full": return "Ese jugador tiene demasiadas invitaciones pendientes."
		"not_signed_in", "session_expired": return "Tenés que volver a iniciar sesión en línea."
		"unavailable": return "No se pudo conectar con el servidor. Probá más tarde."
		"disabled", "not_configured": return "El juego en línea todavía no está disponible."
	return "Ocurrió un error inesperado."


func in_group() -> bool:
	return not group.is_empty()


func is_leader() -> bool:
	return in_group() and api.steam_id != "" and str(group.get("leader", "")) == api.steam_id


## True while a queue match is our current game (formed, not yet reported or abandoned).
func has_match() -> bool:
	return state == "matched" and not current.is_empty()


# ---------------------------------------------------------------- pacing

## Called every frame with the frame time in seconds: polls when the interval for the current state has passed.
func tick(delta: float) -> void:
	var every := poll_interval(state, in_group())
	if every <= 0.0:
		_acc = 0.0
		return
	_acc += delta
	if _acc >= every and not _polling:
		_acc = 0.0
		poll()


# ---------------------------------------------------------------- queue

## Searches for a match in `p_mode` (1-3), alone or with our group (leader only; the server checks everything).
func join(p_mode: int, use_group: bool, cb: Callable = Callable()) -> void:
	if p_mode < 1 or p_mode > 3 or (use_group and p_mode < 2):
		_done(cb, OnlineApi._fail("invalid_mode", false))
		return
	var args := {"p_mode": p_mode, "p_version": version}
	if use_group:
		if not in_group():
			_done(cb, OnlineApi._fail("group_not_found", false))
			return
		args["p_group"] = str(group.id)
	api.call_rpc("join_queue", args, func(r: Dictionary):
		if r.ok:
			state = "searching"
			mode = p_mode
			searching = 0
			wait = 0
			_acc = 99.0  # poll right away: the ticket may already be matched
			changed.emit()
		_done(cb, r))


## Asks the server where we are. Keeps the last known state when it cannot be reached.
func poll(cb: Callable = Callable()) -> void:
	if _polling:
		return
	_polling = true
	api.call_rpc("queue_status", {}, func(r: Dictionary):
		_polling = false
		if r.ok and typeof(r.data) == TYPE_DICTIONARY:
			_apply(r.data)
		if state == "idle" and in_group() and r.ok:
			refresh_group()
		_done(cb, r))


func _apply(d: Dictionary) -> void:
	match str(d.get("state", "idle")):
		"searching":
			state = "searching"
			mode = int(d.get("mode", mode))
			searching = int(d.get("searching", 0))
			wait = int(d.get("wait", 0))
			current = {}
			changed.emit()
		"matched":
			state = "matched"
			mode = int(d.get("mode", mode))
			wait = int(d.get("wait", 0))
			current = _clean_match(d.get("match", {}))
			changed.emit()
			if str(current.id) != _announced:
				_announced = str(current.id)
				match_found.emit(current)
			if str(current.lobby_id) != "" and not current.is_host and _lobby_announced != str(current.id):
				_lobby_announced = str(current.id)
				lobby_published.emit(current)
		_:
			if state != "idle":
				state = "idle"
				current = {}
				changed.emit()


static func _clean_match(raw) -> Dictionary:
	var m: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	return {
		"id": str(m.get("id", "")),
		"host": str(m.get("host", "")),
		"is_host": bool(m.get("is_host", false)),
		"lobby_id": "" if m.get("lobby_id") == null else str(m.get("lobby_id")),
		"side": str(m.get("side", "")),
		"sides": m.get("sides", {}),
	}


## The host publishes its Steam lobby so the others can join it (the id travels as text).
func publish_lobby(lobby_id: int, cb: Callable = Callable()) -> void:
	if not has_match():
		_done(cb, OnlineApi._fail("not_in_match", false))
		return
	api.call_rpc("publish_lobby", {"p_match": str(current.id), "p_lobby": str(lobby_id)}, func(r: Dictionary):
		_done(cb, r))


## Each side tells who won ("red" or "blue"); the server only counts it when both sides agree. Once per match.
func report_result(winner: String, cb: Callable = Callable()) -> void:
	if not has_match():
		_done(cb, OnlineApi._fail("not_in_match", false))
		return
	if _reported == str(current.id):
		_done(cb, OnlineApi._fail("already_reported", false))
		return
	var id := str(current.id)
	_reported = id
	api.call_rpc("report_result", {"p_match": id, "p_winner": winner}, func(r: Dictionary):
		if not r.ok and r.get("unavailable", false):
			_reported = ""  # a cut: try again later
		_done(cb, r))


## The match is over for us (reported or not): free the slot and go back to idle.
func finish(cb: Callable = Callable()) -> void:
	_leave(cb)


## Left the match or the search without a result: nothing is reported, nothing is lost.
func abandon(cb: Callable = Callable()) -> void:
	_leave(cb)


func cancel(cb: Callable = Callable()) -> void:
	_leave(cb)


func _leave(cb: Callable) -> void:
	var was := state
	state = "idle"
	current = {}
	searching = 0
	wait = 0
	_acc = 0.0
	if was != "idle":
		changed.emit()
	api.call_rpc("leave_queue", {}, func(r: Dictionary): _done(cb, r))


func team_history(team_id: String, cb: Callable) -> void:
	api.call_rpc("team_history", {"p_team": team_id}, func(r: Dictionary):
		_done(cb, r))


# ---------------------------------------------------------------- groups

func refresh_group(cb: Callable = Callable()) -> void:
	api.call_rpc("my_group", {}, func(r: Dictionary):
		if not r.ok:
			_done(cb, r)
			return
		var fresh: Dictionary = (r.data as Dictionary).duplicate(true) if typeof(r.data) == TYPE_DICTIONARY else {}
		api.call_rpc("my_group_invites", {}, func(r2: Dictionary):
			if r2.ok:
				group = fresh
				if not group.is_empty():
					group["mode"] = int(group.get("mode", 0))
				group_invites = (r2.data as Array).duplicate(true) if typeof(r2.data) == TYPE_ARRAY else []
				for i in group_invites:
					i["mode"] = int(i.get("mode", 0))
				changed.emit()
			_done(cb, r2)))


func create_group(p_mode: int, team_id := "", cb: Callable = Callable()) -> void:
	if p_mode != 2 and p_mode != 3:
		_done(cb, OnlineApi._fail("invalid_mode", false))
		return
	var args := {"p_mode": p_mode}
	if team_id != "":
		args["p_team"] = team_id
	_act("create_group", args, cb)


func group_add(steam_id: String, cb: Callable = Callable()) -> void:
	if not TeamService.valid_steam_id(steam_id):
		_done(cb, OnlineApi._fail("invalid_target", false))
		return
	_act("group_add", {"p_group": str(group.get("id", "")), "p_steam_id": steam_id}, cb)


func group_confirm(group_id: String, cb: Callable = Callable()) -> void:
	_act("group_confirm", {"p_group": group_id}, cb)


func group_decline(group_id: String, cb: Callable = Callable()) -> void:
	_act("group_decline", {"p_group": group_id}, cb)


func leave_group(cb: Callable = Callable()) -> void:
	_act("leave_group", {"p_group": str(group.get("id", ""))}, cb)


func group_kick(steam_id: String, cb: Callable = Callable()) -> void:
	if not TeamService.valid_steam_id(steam_id):
		_done(cb, OnlineApi._fail("invalid_target", false))
		return
	_act("group_kick", {"p_group": str(group.get("id", "")), "p_steam_id": steam_id}, cb)


func _act(fn: String, args: Dictionary, cb: Callable) -> void:
	api.call_rpc(fn, args, func(r: Dictionary):
		if r.ok:
			refresh_group(func(_r2: Dictionary): _done(cb, r))
		else:
			_done(cb, r))


static func _done(cb: Callable, r: Dictionary) -> void:
	if cb.is_valid():
		cb.call(r)
