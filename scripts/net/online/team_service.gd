class_name TeamService
extends RefCounted
## Client side of the persistent teams (2v2 and 3v3) kept on the server. The rules (one team per mode, capacity, only
## the captain edits, ...) are enforced by the database functions; this class validates the same basics before spending
## a request, sends the calls, keeps the last known state in `teams` / `invites` and says "unavailable" quietly when
## Supabase cannot be reached. No ratings: teams do not have one yet.
##
## Every call ends in `cb(result)` (see OnlineApi) and, when it worked, refreshes the state first. Steam ids travel
## as text in both directions: they do not fit in a JSON double.

## The state changed (a refresh finished).
signal changed

const NAME_MIN := 3
const NAME_MAX := 20

var api: OnlineApi
## [{id, mode: int, name, captain: String, members: [{steam_id, name, captain}], invites: [{id, to, to_name, expires_at}]}]
var teams: Array = []
## Invitations to us: [{id, team_id, team_name, mode: int, from, from_name, expires_at}]
var invites: Array = []


func _init(p_api: OnlineApi) -> void:
	api = p_api


func online() -> bool:
	return api.available()


# ---------------------------------------------------------------- pure helpers (also used by tests and the UI)

static func valid_mode(mode: int) -> bool:
	return mode == 2 or mode == 3


## Members a team of this mode can hold (pending invitations count towards it on the server).
static func capacity(mode: int) -> int:
	return mode * 2


## Same cleaning as the server (app_private.clean_name) and Wire.clean_chat: control and bidirectional-override
## characters become spaces, whitespace collapses, and the length must be NAME_MIN..NAME_MAX. "" when invalid.
static func clean_name(raw: String) -> String:
	if raw.length() > NAME_MAX * 4:
		return ""
	var text := ""
	for ch in raw:
		var code: int = ch.unicode_at(0)
		var bad := code < 32 or (code >= 0x7f and code <= 0x9f) or code == 0x61c or (code >= 0x200b and code <= 0x200f) \
			or (code >= 0x2028 and code <= 0x202e) or (code >= 0x2060 and code <= 0x2069) or code == 0xfeff
		text += " " if bad else ch
	var clean := " ".join(text.split(" ", false)).strip_edges()
	return clean if clean.length() >= NAME_MIN and clean.length() <= NAME_MAX else ""


static func valid_steam_id(id: String) -> bool:
	if id == "" or id.length() > 18 or not id.is_valid_int():
		return false
	return id.to_int() > 0


## What to tell the player for a result's `error` code. Unknown codes never show raw.
static func error_text(code: String) -> String:
	match code:
		"invalid_mode": return "Los equipos son de 2 o de 3 jugadores."
		"invalid_name": return "El nombre debe tener entre %d y %d caracteres." % [NAME_MIN, NAME_MAX]
		"name_taken": return "Ya hay un equipo con ese nombre en esta modalidad."
		"already_in_team": return "Ya tenés un equipo en esta modalidad."
		"already_invited": return "Ya invitaste a ese jugador."
		"not_captain": return "Solo el capitán puede hacer eso."
		"not_member": return "Ese jugador no es del equipo."
		"team_not_found": return "El equipo ya no existe."
		"invite_not_found": return "La invitación ya no está disponible."
		"invalid_target": return "Ese jugador no es válido para esta acción."
		"team_full": return "El equipo está completo."
		"invitee_inbox_full": return "Ese jugador tiene demasiadas invitaciones pendientes."
		"captain_must_transfer_or_disband": return "El capitán no puede irse: pasá la capitanía o disolvé el equipo."
		"not_signed_in", "session_expired": return "Tenés que volver a iniciar sesión en línea."
		"unavailable": return "No se pudo conectar con el servidor de equipos. Probá más tarde."
		"disabled", "not_configured": return "Los equipos en línea todavía no están disponibles."
		"rate_limited": return "Demasiados intentos. Esperá un momento."
	return "Ocurrió un error inesperado."


func team_for_mode(mode: int) -> Dictionary:
	for t in teams:
		if int(t.mode) == mode:
			return t
	return {}


func is_captain(team: Dictionary) -> bool:
	return api.steam_id != "" and str(team.get("captain", "")) == api.steam_id


# ---------------------------------------------------------------- reads

## Reloads teams and invitations. Keeps the last known state when the server cannot be reached.
func refresh(cb: Callable = Callable()) -> void:
	api.call_rpc("my_teams", {}, func(r: Dictionary):
		if not r.ok:
			_done(cb, r)
			return
		var fresh_teams := _list(r.data)
		api.call_rpc("my_invites", {}, func(r2: Dictionary):
			if r2.ok:
				teams = fresh_teams
				for t in teams:
					t["mode"] = int(t.get("mode", 0))
				invites = _list(r2.data)
				for i in invites:
					i["mode"] = int(i.get("mode", 0))
				changed.emit()
			_done(cb, r2)))


static func _list(data: Variant) -> Array:
	return (data as Array).duplicate(true) if typeof(data) == TYPE_ARRAY else []


# ---------------------------------------------------------------- writes

func create_team(mode: int, team_name: String, cb: Callable = Callable()) -> void:
	if not valid_mode(mode):
		_done(cb, OnlineApi._fail("invalid_mode", false))
		return
	var clean := clean_name(team_name)
	if clean == "":
		_done(cb, OnlineApi._fail("invalid_name", false))
		return
	_act("create_team", {"p_mode": mode, "p_name": clean}, cb)


func invite(team_id: String, steam_id: String, cb: Callable = Callable()) -> void:
	if not valid_steam_id(steam_id):
		_done(cb, OnlineApi._fail("invalid_target", false))
		return
	_act("invite_to_team", {"p_team": team_id, "p_steam_id": steam_id}, cb)


func accept_invite(invite_id: String, cb: Callable = Callable()) -> void:
	_act("accept_invite", {"p_invite": invite_id}, cb)


func decline_invite(invite_id: String, cb: Callable = Callable()) -> void:
	_act("decline_invite", {"p_invite": invite_id}, cb)


func cancel_invite(invite_id: String, cb: Callable = Callable()) -> void:
	_act("cancel_invite", {"p_invite": invite_id}, cb)


func leave_team(team_id: String, cb: Callable = Callable()) -> void:
	_act("leave_team", {"p_team": team_id}, cb)


func kick_member(team_id: String, steam_id: String, cb: Callable = Callable()) -> void:
	if not valid_steam_id(steam_id):
		_done(cb, OnlineApi._fail("invalid_target", false))
		return
	_act("kick_member", {"p_team": team_id, "p_steam_id": steam_id}, cb)


func transfer_captain(team_id: String, steam_id: String, cb: Callable = Callable()) -> void:
	if not valid_steam_id(steam_id):
		_done(cb, OnlineApi._fail("invalid_target", false))
		return
	_act("transfer_captain", {"p_team": team_id, "p_steam_id": steam_id}, cb)


func disband_team(team_id: String, cb: Callable = Callable()) -> void:
	_act("disband_team", {"p_team": team_id}, cb)


## Runs a write; when it worked, reloads the state and only then reports (so the caller sees the new state).
func _act(fn: String, args: Dictionary, cb: Callable) -> void:
	api.call_rpc(fn, args, func(r: Dictionary):
		if r.ok:
			refresh(func(_r2: Dictionary): _done(cb, r))
		else:
			_done(cb, r))


static func _done(cb: Callable, r: Dictionary) -> void:
	if cb.is_valid():
		cb.call(r)
