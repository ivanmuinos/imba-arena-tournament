class_name RankedService
extends RefCounted
## Ranked outside the match: the player's ratings (RankedStore, mirrored to one Steam leaderboard per bracket with
## details [games, wins]), the global top lists, and the queue that finds or opens a ranked Steam lobby near your rating.
##
## Queue: look for open ranked lobbies of the bracket whose host rating is within Ranked.window(waited); join the closest.
## None: open our own (public, data ranked=1, mode, mmr) and keep looking every RESEARCH_S while we are alone, moving to
## an older lobby if one shows up (so two players searching at once do not both wait in empty lobbies).

signal changed  # ratings or top lists updated
signal join(lobby_id: int)  # the queue picked a lobby to join
signal host(mode: int)  # the queue found nothing: open a ranked lobby
signal status(text: String)

const BOARD := "imba_ranked_%dv%d"
const RESEARCH_S := 8.0
const TOP_N := 10

var store: RankedStore
var backend: SteamBackend
## mode -> [{rank, name, mmr, games, wins, me}]
var top := {}
## The last finished match: RankedStore.finish() result, for the end screen.
var last_result := {}

var searching := 0  # bracket being searched (0 = idle)
var hosting_lobby := 0
var _waited := 0.0
var _next_search := 0.0
var _asked := false


func _init(p_backend: SteamBackend, p_store: RankedStore = null) -> void:
	backend = p_backend
	store = p_store if p_store != null else RankedStore.new()
	var abandoned := store.settle_abandoned()
	if not abandoned.is_empty():
		last_result = abandoned
	if backend == null or not backend.available():
		return
	backend.leaderboard_ready.connect(_on_board_ready)
	backend.leaderboard_entries.connect(_on_entries)
	backend.lobby_list.connect(_on_lobbies)
	for mode in Ranked.BRACKETS:
		backend.find_leaderboard(board_name(mode))


static func board_name(mode: int) -> String:
	return BOARD % [mode, mode]


func online() -> bool:
	return backend != null and backend.available()


func rating(mode: int) -> Dictionary:
	return store.rating(mode)


func refresh_top(mode: int) -> void:
	if online():
		backend.request_top(board_name(mode), 1, TOP_N)


# ---------------------------------------------------------------- match

func begin_match(mode: int, team_avg: float, foe_avg: float) -> void:
	stop_search()
	store.begin(mode, team_avg, foe_avg)


func finish_match(won: bool) -> Dictionary:
	last_result = store.finish(won)
	if not last_result.is_empty():
		_upload(int(last_result.mode))
		changed.emit()
	return last_result


## Left or lost the connection mid-match: a loss.
func abandon_match() -> void:
	var r := store.settle_abandoned()
	if not r.is_empty():
		last_result = r
		_upload(int(r.mode))
		changed.emit()


func _upload(mode: int) -> void:
	if online():
		var r := store.rating(mode)
		backend.upload_score(board_name(mode), int(r.mmr), PackedInt32Array([int(r.games), int(r.wins)]))
		refresh_top(mode)


# ---------------------------------------------------------------- queue

func start_search(mode: int) -> void:
	if not online():
		status.emit("Ranked necesita Steam abierto")
		return
	searching = mode
	hosting_lobby = 0
	_waited = 0.0
	_next_search = 0.0
	_asked = false
	status.emit("Buscando rivales %s…" % Ranked.bracket_key(mode))


func stop_search() -> void:
	searching = 0
	hosting_lobby = 0
	_asked = false


## We opened our own lobby and wait in it (keep looking for an older one while alone).
func hosting(lobby_id: int) -> void:
	hosting_lobby = lobby_id
	_next_search = _waited + RESEARCH_S


func tick(dt: float, alone := true) -> void:
	if searching == 0:
		return
	_waited += dt
	if _asked or _waited < _next_search or (hosting_lobby != 0 and not alone):
		return
	_asked = true
	backend.request_ranked_lobbies(GameServer.game_version(), {"ranked": "1", "mode": str(searching)}, "mmr", int(rating(searching).mmr))


## Lobby ids whose host rating fits our window, closest rating first (ties: the older lobby).
static func pick(entries: Array, mmr: int, waited_s: float, own_lobby := 0) -> Array:
	var w := Ranked.window(waited_s)
	var ok: Array = entries.filter(func(e): return str(e.get("ranked", "")) == "1" and int(e.id) != own_lobby
		and int(e.members) < int(e.max) and absi(int(e.get("mmr", Ranked.START)) - mmr) <= w
		and (own_lobby == 0 or int(e.id) < own_lobby))
	ok.sort_custom(func(a, b):
		var da := absi(int(a.get("mmr", 0)) - mmr)
		var db := absi(int(b.get("mmr", 0)) - mmr)
		return da < db if da != db else int(a.id) < int(b.id))
	return ok.map(func(e): return int(e.id))


func _on_lobbies(entries: Array) -> void:
	if searching == 0 or not _asked:
		return
	_asked = false
	_next_search = _waited + RESEARCH_S
	var ids := pick(entries, int(rating(searching).mmr), _waited, hosting_lobby)
	if not ids.is_empty():
		status.emit("Rivales encontrados: entrando…")
		join.emit(ids[0])
	elif hosting_lobby == 0:
		host.emit(searching)


# ---------------------------------------------------------------- leaderboards

func _on_board_ready(board: String, ok: bool) -> void:
	if not ok:
		return
	backend.request_mine(board)
	backend.request_top(board, 1, TOP_N)


func _on_entries(board: String, entries: Array) -> void:
	var mode := 0
	for m in Ranked.BRACKETS:
		if board_name(m) == board:
			mode = m
	if mode == 0:
		return
	var me := backend.my_id()
	for e in entries:
		if int(e.steam_id) == me:
			var d: Array = e.details
			store.merge(mode, {"mmr": int(e.score), "games": int(d[0]) if d.size() > 0 else 0, "wins": int(d[1]) if d.size() > 1 else 0})
	if entries.size() > 1 or (entries.size() == 1 and int(entries[0].rank) == 1):
		var rows: Array = []
		for e in entries:
			var d: Array = e.details
			rows.append({"rank": int(e.rank), "name": backend.persona_of(int(e.steam_id)), "mmr": int(e.score),
				"games": int(d[0]) if d.size() > 0 else 0, "wins": int(d[1]) if d.size() > 1 else 0, "me": int(e.steam_id) == me})
		top[mode] = rows
	changed.emit()
