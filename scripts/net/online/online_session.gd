class_name OnlineSession
extends RefCounted
## Keeps the online session alive: asks Steam for a web-API ticket bound to OnlineApi.IDENTITY, trades it for a token
## (auth-steam), tells the server our Steam name (touch_player) and signs in again before the one-hour token expires.
## Failures are quiet: `state` and `note` say what to show, and a retry follows later. Without Steam, with the online
## switch off or without a configured server it stays "off" and never touches the network.

signal state_changed

## Sign in again when the token has less than this left.
const REFRESH_BEFORE := 300.0
const RETRY_AFTER := 30.0

var api: OnlineApi
var steam: SteamBackend
## off | signing_in | ready | failed
var state := "off"
## What to tell the player when it is not ready (Spanish, never a raw error code).
var note := ""

var _retry_at := 0.0


func _init(p_api: OnlineApi, p_steam: SteamBackend) -> void:
	api = p_api
	steam = p_steam
	if steam != null:
		steam.web_auth_ticket.connect(_on_ticket)


func is_ready() -> bool:
	return state == "ready" and api.signed_in()


## Online features can be tried at all (switch on, server configured, Steam running).
func usable() -> bool:
	return api.enabled and api.configured() and steam != null and steam.available()


func start() -> void:
	if state == "signing_in":
		return
	if not api.enabled or not api.configured():
		_enter("off", "El juego en línea todavía no está disponible.")
		return
	if steam == null or not steam.available():
		_enter("off", "Abrí Steam para jugar en línea.")
		return
	_enter("signing_in", "Iniciando sesión en línea…")
	steam.request_web_auth_ticket(OnlineApi.IDENTITY)


## Called about once a second: refreshes the token before it expires and retries after a failure.
func tick() -> void:
	match state:
		"ready":
			if api.token_expires - api._now() < REFRESH_BEFORE:
				start()
		"failed":
			if api._now() >= _retry_at:
				start()


func _on_ticket(ok: bool, ticket: String) -> void:
	if state != "signing_in":
		return
	if not ok or ticket == "":
		_fail("Steam no pudo darnos la identidad para jugar en línea.")
		return
	api.sign_in(ticket, func(r: Dictionary):
		if not r.ok:
			_fail(_text(r))
			return
		api.call_rpc("touch_player", {"p_name": steam.persona_name()}, func(r2: Dictionary):
			if r2.ok:
				_enter("ready", "")
			else:
				_fail(_text(r2))))


func _text(r: Dictionary) -> String:
	match str(r.get("error", "")):
		"ticket_rejected": return "Steam no aceptó tu sesión en línea."
		"banned": return "Tu cuenta no puede jugar en línea."
		"dev_login_disabled": return "Este servidor no acepta el inicio de sesión de desarrollo."
	return TeamService.error_text(str(r.get("error", "")))


func _fail(text: String) -> void:
	_retry_at = api._now() + RETRY_AFTER
	_enter("failed", text)


func _enter(s: String, text: String) -> void:
	var changed := s != state or text != note
	state = s
	note = text
	if changed:
		state_changed.emit()
