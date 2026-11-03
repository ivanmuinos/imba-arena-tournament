class_name OnlineApi
extends Node
## HTTP client for Supabase (PostgREST functions + Edge Functions), callback style like the rest of the net code.
## Every call ends in `cb(result)` with {ok, status, data, error, unavailable}:
##   * `error` is a short code ("team_full", "not_signed_in", "session_expired", "forbidden", "disabled", "unavailable").
##   * `unavailable` is true when the service cannot be reached (no network, timeout, 5xx, a paused free-tier project,
##     a non-JSON answer): the API then fails fast for COOLDOWN seconds without touching the network, so a dead backend
##     never stalls the game, and `available()` / `availability_changed` tell the UI to hide online features.
## Needs to be inside the tree for real requests (HTTPRequest children); tests use FakeOnline, which only replaces `_send`.

signal availability_changed(available: bool)

const TIMEOUT := 8.0
const COOLDOWN := 30.0
## What the Steam ticket is bound to (`identity` of GetAuthTicketForWebApi); auth-steam passes the same to Steam.
const IDENTITY := "imba-arena-online"
## The session is treated as over this long before the token really expires.
const EXPIRY_MARGIN := 60.0

var base_url := ""
var anon_key := ""
## Off until Online.on() (the shipped flag or the developer's --online): nothing is sent.
var enabled := Online.on()
## Session JWT from auth-steam and its expiry (unix seconds).
var token := ""
var token_expires := 0.0
## Our Steam id, as text (it does not fit in a JSON double), once signed in.
var steam_id := ""

var _down_until := 0.0
var _was_available := true


func _init() -> void:
	var cfg := Online.config()
	base_url = str(cfg.get("url", "")).trim_suffix("/")
	anon_key = str(cfg.get("anon_key", ""))


func _now() -> float:
	return Time.get_unix_time_from_system()


func configured() -> bool:
	return Online.config_valid({"url": base_url, "anon_key": anon_key})


func signed_in() -> bool:
	return token != "" and _now() < token_expires


## Reachable as far as we know (false during the cooldown after an outage, or when disabled / unconfigured).
func available() -> bool:
	return enabled and configured() and _now() >= _down_until


func sign_out() -> void:
	token = ""
	token_expires = 0.0
	steam_id = ""


## Trades a Steam web-API ticket (see SteamBackend.request_web_auth_ticket) for a session token via auth-steam.
## cb gets the usual result; on success the session is stored. Errors from the server: "ticket_rejected",
## "dev_login_disabled" (a dev ticket on a real server), "invalid_ticket", ...
func sign_in(ticket: String, cb: Callable) -> void:
	if ticket == "":
		cb.call(_fail("no_ticket", false))
		return
	call_edge("auth-steam", {"ticket": ticket}, func(r: Dictionary):
		if r.ok:
			var d = r.data
			if typeof(d) != TYPE_DICTIONARY or str(d.get("token", "")) == "" or str(d.get("steam_id", "")) == "":
				r = _fail("bad_response", false)
			else:
				token = str(d.token)
				token_expires = _now() + float(d.get("expires_in", 0)) - EXPIRY_MARGIN
				steam_id = str(d.steam_id)
		cb.call(r))


## Calls a Postgres function (security definer RPC) as the signed-in player.
func call_rpc(fn: String, args: Dictionary, cb: Callable) -> void:
	_request("/rest/v1/rpc/" + fn, args, true, cb)


## Calls an Edge Function (no session needed: the login itself).
func call_edge(fn: String, body: Dictionary, cb: Callable) -> void:
	_request("/functions/v1/" + fn, body, false, cb)


func _request(path: String, body: Dictionary, needs_session: bool, cb: Callable) -> void:
	var gate := _gate(needs_session)
	if not gate.is_empty():
		cb.call(gate)
		return
	var headers := ["Content-Type: application/json", "apikey: " + anon_key]
	headers.append("Authorization: Bearer " + (token if needs_session else anon_key))
	_send(HTTPClient.METHOD_POST, base_url + path, headers, JSON.stringify(body), func(result: int, code: int, text: String):
		var r := classify(result, code, text)
		_note(r)
		cb.call(r))


## Why a call cannot even start, or {} when it can.
func _gate(needs_session: bool) -> Dictionary:
	if not enabled:
		return _fail("disabled", true)
	if not configured():
		return _fail("not_configured", true)
	if _now() < _down_until:
		return _fail("unavailable", true)
	if needs_session:
		if token == "":
			return _fail("not_signed_in", false)
		if not signed_in():
			return _fail("session_expired", false)
	return {}


func _note(r: Dictionary) -> void:
	if r.get("unavailable", false):
		_down_until = _now() + COOLDOWN
	else:
		_down_until = 0.0
	var now_ok := _now() >= _down_until
	if now_ok != _was_available:
		_was_available = now_ok
		availability_changed.emit(now_ok)


static func _fail(error: String, unavailable: bool) -> Dictionary:
	return {"ok": false, "status": 0, "data": null, "error": error, "unavailable": unavailable}


## HTTPRequest outcome -> result dictionary (see the class comment).
static func classify(result: int, code: int, text: String) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS or code >= 500:
		return _fail("unavailable", true).merged({"status": code})
	var parsed = null
	if text.strip_edges() != "":
		var json := JSON.new()  # not parse_string: that prints an engine error on bad input
		if json.parse(text) == OK:
			parsed = json.data
		else:  # a 2xx/4xx that is not JSON: a portal or proxy is answering, not our backend
			return _fail("unavailable", true).merged({"status": code})
	if code >= 200 and code < 300:
		return {"ok": true, "status": code, "data": parsed, "error": "", "unavailable": false}
	var err := "error"
	if code == 401:
		err = "session_expired"
	elif code == 403:
		err = "forbidden"
	elif code == 429:
		err = "rate_limited"
	if typeof(parsed) == TYPE_DICTIONARY:
		for key in ["message", "error"]:
			var m := str(parsed.get(key, ""))
			if _is_code(m):
				err = m
				break
	return _fail(err, false).merged({"status": code})


## Server error codes are snake_case words; anything else (a Postgres message, HTML) is not shown to the player.
static func _is_code(s: String) -> bool:
	if s.length() < 3 or s.length() > 40:
		return false
	for ch in s:
		if not ((ch >= "a" and ch <= "z") or ch == "_" or (ch >= "0" and ch <= "9")):
			return false
	return true


## Transport: overridden by FakeOnline. cb(result: int, code: int, text: String).
func _send(method: int, url: String, headers: Array, body: String, cb: Callable) -> void:
	if not is_inside_tree():
		cb.call(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
		return
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, b: PackedByteArray):
		http.queue_free()
		cb.call(result, code, b.get_string_from_utf8()), CONNECT_ONE_SHOT)
	if http.request(url, PackedStringArray(headers), method, body) != OK:
		http.queue_free()
		cb.call(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
