class_name GameServer
extends RefCounted
## The authoritative side: lobby + one ArenaMatch at a fixed tick (port of server/index.ts).
## It talks to clients only through Transports. A hosting player is just a client attached
## through a LoopbackTransport; a dedicated server has no local player.
##
## Anti-cheat rules kept from the web version: every inbound message is validated (Wire),
## rate limited, snapshots/events only contain what the receiving team can see.

signal match_started
signal match_ended
signal player_joined(name: String)
signal player_left(name: String)

const PROTO := 7


## Game version from project.godot (config/version): client and server must match exactly.
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


const MAX_MSGS_PER_SEC := 120
## A full ranked lobby starts after this short countdown (time to see who you got).
const RANKED_START_MS := 4000.0
## A lobby made by the normal queue: starts this long after everyone matched is in, or after QUEUE_WAIT_MS with bots
## covering whoever never showed up.
const QUEUE_START_MS := 4000.0
const QUEUE_WAIT_MS := 45000.0
const BASE_TIME := 1_000_000.0  # sim clock start; keeps "ms since" fields away from zero

## mode 2|3, diff, map, dedicated (no local host), autopilot (bots drive human units: demos),
## auto_start_ms (dedicated: wait this long after the first player, 0 = never).
## ranked: no bots, teams split by rating, starts by itself when full, settings fixed (see Ranked).
## queue_sides {steam id text: "red"|"blue"} + queue_host (the host's steam id text): a lobby made by the normal queue.
## The online backend chose host and sides; only those players enter, they are placed by Steam id (preferences and
## settings changes are ignored), and it starts by itself (see QUEUE_START_MS).
var cfg := {"mode": 2, "diff": "normal", "map": "random", "dedicated": false, "autopilot": false, "auto_start_ms": 10000.0, "practice": false, "ranked": false, "scripted": [], "queue_sides": {}, "queue_host": "", "lesson": ""}
var state := "lobby"  # lobby | match
var game: ArenaMatch = null
## peer -> {name, cls, pref}
var players := {}
var host_peer := 0
var sim_now := BASE_TIME
## Arena actually used by the running match (cfg.map may be "random").
var resolved_map := ""
## Ranked match in progress: average rating per team ({} otherwise).
var ranked_teams := {}

var _transports: Array[Transport] = []
var _route := {}  # peer id -> Transport
var _hosts := {}  # transports whose peers are the hosting player
var _budget := {}
var _chat_at := {}
var _budget_timer := 0.0
var _acc := 0.0
var _tick_n := 0
var _auto_timer := -1.0
var _queue_wait := 0.0
var _queue_count := 0.0
var _queue_done := false
var _step_ms: float


func _init(p_cfg := {}) -> void:
	GameData.ensure_loaded()
	cfg.merge(p_cfg, true)
	var n := MatchConfig.normalize(cfg)
	cfg.mode = n.mode
	cfg.diff = n.diff
	cfg.map = GameMap.PRACTICE_ID if bool(cfg.get("practice", false)) else n.map
	if str(cfg.lesson) != "":
		cfg.map = GameMap.ACADEMY_ID
	_step_ms = 1000.0 / GameData.C.SIM_HZ


## Starts accepting peers from a transport. `is_host`: the peers arriving through it are the
## hosting player (may start the match and change the settings).
func attach(t: Transport, is_host := false) -> void:
	_transports.append(t)
	if is_host:
		_hosts[t] = true
	t.peer_joined.connect(_on_peer_connected)
	t.peer_disconnected.connect(_on_peer_disconnected)
	t.message.connect(_on_message)


func humans_count() -> int:
	return players.size()


func shutdown() -> void:
	for p in players.keys():
		_send(p, {"t": "closed", "reason": "El anfitrión cerró la partida"})
	for t in _transports:
		t.poll()
		t.close()
	_transports.clear()
	_route.clear()
	_hosts.clear()
	game = null


# ---------------------------------------------------------------- frame

## Advance by `delta_ms` of real time: poll the network, run the fixed-step sim, send updates.
func process(delta_ms: float) -> void:
	for t in _transports.duplicate():
		t.poll()
	_budget_timer += delta_ms
	if _budget_timer >= 1000.0:
		_budget_timer = 0.0
		_budget.clear()
	if state == "match" and game != null:
		_acc = minf(_acc + delta_ms, _step_ms * 15.0)  # never spiral after a long stall
		while _acc >= _step_ms:
			_acc -= _step_ms
			sim_now += _step_ms
			game.tick(sim_now)
			_tick_n += 1
			if _tick_n % int(GameData.C.SNAPSHOT_EVERY) == 0:
				_flush()
			if game.done:
				_finish_match()
				break
	elif state == "lobby" and bool(cfg.ranked):
		if players.size() >= int(cfg.mode) * 2:
			_auto_timer -= delta_ms
			if _auto_timer <= 0.0:
				start_match(true)  # ranked: matchmade, the countdown replaces the Listo check
		else:
			_auto_timer = RANKED_START_MS
	elif state == "lobby" and is_queue_lobby() and not _queue_done:
		_queue_tick(delta_ms)
	elif state == "lobby" and bool(cfg.dedicated) and cfg.auto_start_ms > 0.0 and not players.is_empty():
		_auto_timer -= delta_ms
		if _auto_timer <= 0.0 or players.size() >= int(cfg.mode) * 2:
			start_match()


## A lobby made by the normal queue (host and sides decided by the online backend).
func is_queue_lobby() -> bool:
	return not (cfg.queue_sides as Dictionary).is_empty()


func _queue_tick(delta_ms: float) -> void:
	if players.is_empty():
		_queue_wait = 0.0
		_queue_count = 0.0
		return
	_queue_wait += delta_ms
	if players.size() >= (cfg.queue_sides as Dictionary).size():
		_queue_count += delta_ms
		if _queue_count >= QUEUE_START_MS:
			start_match(true)
	else:
		_queue_count = 0.0
		if _queue_wait >= QUEUE_WAIT_MS:
			start_match(true)


# ---------------------------------------------------------------- peers

func _send(peer: int, msg: Dictionary, reliable := true) -> void:
	var t: Transport = _route.get(peer)
	if t != null:
		t.send(peer, msg, reliable)


func _kick(peer: int, text: String) -> void:
	_send(peer, {"t": "error", "text": text})
	var t: Transport = _route.get(peer)
	if t != null:
		t.kick(peer)


func _on_peer_connected(t: Transport, id: int) -> void:
	_route[id] = t


func _on_peer_disconnected(id: int) -> void:
	_route.erase(id)
	_budget.erase(id)
	_chat_at.erase(id)
	if players.has(id):
		var left_name: String = players[id].name
		players.erase(id)
		player_left.emit(left_name)
		if game != null:
			var u := game.unit_for_peer(id)
			if u != null:
				if _is_walkover(u):
					u.peer = 0
					game.forfeit(u.team, sim_now)  # 1v1 vs another human: the one who stays wins
				else:
					game.leave(u)  # a bot takes over
		if state == "lobby":
			_clear_ready()
			_send_lobby()
		if id == host_peer:
			host_peer = 0


## Offline: the local player gives up the match in progress and their team loses (the usual end message follows, with the
## stats). False when there is no match running, or it is practice or already over.
func forfeit_local() -> bool:
	if state != "match" or game == null or game.practice or game.phase == "over" or game.done:
		return false
	var me := game.unit_for_peer(host_peer)
	if me == null:
		return false
	game.forfeit(me.team, sim_now)
	return true


## 1v1 where the leaver's opponent is a human still connected (a bot opponent keeps the old bot replacement).
func _is_walkover(leaver: ArenaUnit) -> bool:
	if int(cfg.mode) != 1 or game.practice:
		return false
	for u in game.units:
		if u != leaver and u.team != leaver.team and u.peer != 0 and players.has(u.peer):
			return true
	return false


func _on_message(from: int, msg: Dictionary) -> void:
	if not _route.has(from):
		return
	_budget[from] = _budget.get(from, 0) + 1
	if _budget[from] > MAX_MSGS_PER_SEC:
		return
	match msg.t:
		"hello": _on_hello(from, msg)
		"ping":
			if typeof(msg.get("at")) in [TYPE_INT, TYPE_FLOAT]:
				_send(from, {"t": "pong", "at": msg.at})
		_:
			if not players.has(from):
				return
			match msg.t:
				"chat": _on_chat(from, msg)
				"ready":
					if state == "lobby" and typeof(msg.get("on")) == TYPE_BOOL:
						players[from].ready = msg.on
						_send_lobby()
				"set": _on_set(from, msg)
				"start":
					if from == host_peer and state == "lobby":
						if not start_match():
							_send(from, {"t": "error", "text": "Todos los jugadores deben marcar Listo"})
				"leave": _on_peer_disconnected(from)
				"input", "cast", "target", "jump", "auto", "stopcast", "practice", "trinket":
					_on_game_message(from, msg)


func _on_hello(from: int, msg: Dictionary) -> void:
	if players.has(from):
		return
	var their := str(msg.get("ver", "?"))
	if int(msg.get("v", 0)) != PROTO or their != game_version():
		_kick(from, "Versión distinta: el servidor usa la %s y vos la %s. Actualizá el juego (pedile la última versión a quien creó la partida)." % [game_version(), their])
		return
	if state != "lobby":
		_kick(from, "Hay una partida en curso")
		return
	if players.size() >= int(cfg.mode) * 2:
		_kick(from, "La sala está llena")
		return
	if bool(cfg.ranked) != bool(msg.get("ranked", false)):
		_kick(from, "Esta sala es ranked: entrá desde Ranked." if bool(cfg.ranked) else "Esta sala no es ranked.")
		return
	var n := MatchConfig.normalize(msg)
	var sid := 0
	if _route[from].has_method("steam_id_of"):
		sid = _route[from].steam_id_of(from)  # players that arrive through Steam are identified by their SteamID
	elif is_queue_lobby() and _hosts.has(_route[from]) and str(cfg.queue_host).is_valid_int():
		sid = int(str(cfg.queue_host))  # the local host has no Steam transport: the queue told us who it is
	if is_queue_lobby() and not (cfg.queue_sides as Dictionary).has(str(sid)):
		_kick(from, "Esta sala es de una partida en cola: no estás entre los jugadores emparejados.")
		return
	var mmr := Ranked.clamp_mmr(int(msg.get("mmr", Ranked.START))) if typeof(msg.get("mmr")) in [TYPE_INT, TYPE_FLOAT] else Ranked.START
	players[from] = {"name": _unique_name(n.name), "cls": n.cls, "spec": n.spec, "talents": n.talents, "pref": n.pref, "sid": str(sid) if sid != 0 else "", "mmr": mmr, "ready": false}
	_clear_ready()
	var is_host: bool = _hosts.has(_route[from])
	if is_host:
		host_peer = from
	if _auto_timer < 0.0 or players.size() == 1:
		_auto_timer = cfg.auto_start_ms
	_send(from, {"t": "welcome", "peer": from, "host": is_host, "v": PROTO, "ver": game_version()})
	_send_lobby()
	player_joined.emit(players[from].name)


func _on_chat(from: int, msg: Dictionary) -> void:
	var text := Wire.clean_chat(msg)
	var now := Time.get_ticks_msec()
	if text.is_empty() or now - int(_chat_at.get(from, -1000)) < 800:
		return
	_chat_at[from] = now
	var out := {"t": "chat", "peer": from, "name": players[from].name, "text": text}
	for peer in players:
		_send(peer, out)


func _unique_name(wanted: String) -> String:
	var taken: Array = players.values().map(func(p): return p.name)
	var n := wanted
	var i := 2
	while taken.has(n):
		n = "%s %d" % [wanted.substr(0, MatchConfig.MAX_NAME - 3), i]
		i += 1
	return n


func _on_set(from: int, msg: Dictionary) -> void:
	if state != "lobby":
		return
	var p: Dictionary = players[from]
	var before := [p.duplicate(), cfg.duplicate()]
	var n := MatchConfig.normalize({"cls": msg.get("cls", p.cls), "spec": msg.get("spec", p.get("spec", "")), "talents": msg.get("talents", p.get("talents", [])), "pref": msg.get("pref", p.pref)})
	p.cls = n.cls
	p.spec = n.spec
	p.talents = n.talents
	if not is_queue_lobby():
		p.pref = n.pref  # in a queue lobby the backend chose the sides
	if from == host_peer and not bool(cfg.ranked) and not is_queue_lobby():
		var c := MatchConfig.normalize({"mode": msg.get("mode", cfg.mode), "diff": msg.get("diff", cfg.diff), "map": msg.get("map", cfg.map)})
		if c.mode * 2 >= players.size():
			cfg.mode = c.mode
		cfg.diff = c.diff
		cfg.map = c.map
	if p != before[0] or cfg != before[1]:
		_clear_ready()
	_send_lobby()


func _on_game_message(from: int, msg: Dictionary) -> void:
	if state != "match" or game == null:
		return
	var u := game.unit_for_peer(from)
	if u == null:
		return
	match msg.t:
		"input":
			var c := Wire.clean_input(msg)
			if not c.is_empty():
				game.input(u, c.dx, c.dz, c.ax, c.az)
		"cast":
			var c := Wire.clean_cast(msg)
			if not c.is_empty():
				game.cast_ability(u, c.slot, c.ax, c.az, sim_now, c.target)
		"target":
			var id := int(msg.get("id", -1)) if typeof(msg.get("id")) in [TYPE_INT, TYPE_FLOAT] else -1
			game.set_target(u, id)
		"jump":
			game.jump(u, sim_now)
		"trinket":
			game.use_trinket(u, sim_now)
		"stopcast":
			game.cancel_cast(u)
		"practice":
			var c := Wire.clean_practice(msg)
			if c.get("cmd") == "cue":
				if game.stage != null:
					game.stage.cue(game, c.n, sim_now)
			elif not c.is_empty():
				game.practice_command(u, c.cmd, c.on, sim_now)
		"auto":
			if bool(msg.get("on", false)) and typeof(msg.get("id")) in [TYPE_INT, TYPE_FLOAT]:
				game.start_auto(u, int(msg.id))
			else:
				game.stop_auto(u)


# ---------------------------------------------------------------- lobby

func lobby_entries(rng: RandomNumberGenerator = null) -> Array:
	if bool(cfg.ranked):
		return _ranked_entries()
	var humans: Array = []
	for peer in players:
		var p: Dictionary = players[peer]
		var pref: String = p.pref
		if is_queue_lobby():
			pref = str((cfg.queue_sides as Dictionary).get(str(p.get("sid", "")), "any"))
		humans.append({"peer": peer, "name": p.name, "cls": p.cls, "spec": p.get("spec", ""), "talents": p.get("talents", []), "pref": pref})
	if not (cfg.scripted as Array).is_empty():  # tournament: fixed rivals with their own skill, HP and damage
		return MatchConfig.scripted_entries(cfg.scripted, humans)
	return MatchConfig.build_entries(int(cfg.mode), humans, rng)


## Ranked: only the players, split into the two teams with the closest average rating.
func _ranked_entries() -> Array:
	var list: Array = []
	for peer in players:
		list.append({"peer": peer, "mmr": int(players[peer].get("mmr", Ranked.START))})
	var side := Ranked.split_teams(list, int(cfg.mode))
	var entries: Array = []
	for team in ["red", "blue"]:
		for peer in players:
			if side.get(peer, "blue") == team:
				var p: Dictionary = players[peer]
				entries.append({"name": p.name, "cls": p.cls, "spec": p.get("spec", ""), "talents": p.get("talents", []), "team": team, "peer": peer, "mmr": p.get("mmr", Ranked.START)})
	return entries


## Average rating of each team of a ranked match: every client computes its own change from these.
static func team_ratings(entries: Array) -> Dictionary:
	var by := {"red": [], "blue": []}
	for e in entries:
		by[e.team].append(int(e.get("mmr", Ranked.START)))
	return {"red": Ranked.average(by.red), "blue": Ranked.average(by.blue)}


func _send_lobby() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var preview := lobby_entries(rng)
	var teams := {"red": [], "blue": []}
	for e in preview:
		teams[e.team].append({"name": e.name if e.peer != 0 else "", "cls": e.cls if e.peer != 0 else "", "spec": e.get("spec", "") if e.peer != 0 else "", "peer": e.peer, "bot": e.peer == 0, "ready": players.get(e.peer, {}).get("ready", true)})
	var members: Array = []
	for peer in players:
		members.append({"peer": peer, "name": players[peer].name, "cls": players[peer].cls, "spec": players[peer].get("spec", ""), "pref": players[peer].pref, "sid": players[peer].get("sid", ""), "mmr": players[peer].get("mmr", Ranked.START), "ready": players[peer].ready})
	for peer in players:
		_send(peer, {"t": "lobby", "mode": cfg.mode, "diff": cfg.diff, "map": cfg.map, "host": host_peer, "you": peer,
			"dedicated": cfg.dedicated, "members": members, "teams": teams, "ranked": cfg.ranked, "can_start": all_ready()})


func _clear_ready() -> void:
	for p in players.values():
		p.ready = false


func all_ready() -> bool:
	return players.size() <= 1 or players.values().all(func(p): return p.get("ready", false))


## An Academia lesson runs for one local player only. `cfg.lesson` can only be set when creating the server (no lobby message
## touches it), and this refuses it anyway if any network transport is attached.
func _lesson_allowed() -> bool:
	return players.size() == 1 and not LessonScenarios.scenario(str(cfg.lesson)).is_empty() and _transports.all(func(t): return t is LoopbackTransport)


func start_match(skip_ready := false) -> bool:
	if state != "lobby" or players.is_empty() or not (skip_ready or all_ready()):
		return false
	var lesson := str(cfg.lesson)
	if lesson != "" and not _lesson_allowed():
		return false
	# "random": the host picks (seeded) and every client receives the resolved arena in the match message.
	var map_id: String = cfg.map
	if map_id == "random":
		map_id = GameMap.pick_id(int(cfg.get("seed", randi())))
	resolved_map = map_id
	if bool(cfg.get("practice", false)):
		map_id = GameMap.PRACTICE_ID
		resolved_map = map_id
		var peer: int = players.keys()[0]
		var p: Dictionary = players[peer]
		game = ArenaMatch.new(2, PracticeYard.entries(p.name, p.cls, p.get("spec", ""), peer, p.get("talents", [])), sim_now, cfg.diff, map_id)
	elif lesson != "":
		map_id = GameMap.ACADEMY_ID
		resolved_map = map_id
		var peer: int = players.keys()[0]
		var p: Dictionary = players[peer]
		var sc := LessonScenarios.scenario(lesson)
		game = ArenaMatch.new(2, LessonScenarios.entries(sc, p.name, p.cls, p.get("spec", ""), peer, p.get("talents", [])), sim_now, cfg.diff, map_id)
		game.journal = []
		game.stage = LessonStage.new(sc)
		game.stage.setup(game, sim_now)
	else:
		var entries := lobby_entries()
		ranked_teams = team_ratings(entries) if bool(cfg.ranked) else {}
		game = ArenaMatch.new(int(cfg.mode), entries, sim_now, cfg.diff, map_id)
	game.god = bool(cfg.get("god", false))
	if cfg.autopilot:
		for u in game.units:
			if u.peer != 0 and u.brain == null:
				u.brain = BotBrain.new(cfg.diff)
	state = "match"
	if is_queue_lobby():
		_queue_done = true  # one match per queue lobby
	_acc = 0.0
	_tick_n = 0
	var roster := game.roster()
	for peer in players:
		var u := game.unit_for_peer(peer)
		var msg := {"t": "match", "you": u.id, "mode": cfg.mode, "map": map_id, "roster": roster}
		if not ranked_teams.is_empty():
			msg["ranked"] = ranked_teams
		if lesson != "":
			msg["lesson"] = lesson
			msg["spawn"] = {"x": u.x, "z": u.z}
		_send(peer, msg)
	match_started.emit()
	return true


func _finish_match() -> void:
	_flush()
	game = null
	state = "lobby"
	_clear_ready()
	_auto_timer = cfg.auto_start_ms
	_send_lobby()
	match_ended.emit()


# ---------------------------------------------------------------- updates

func _flush() -> void:
	var m := game
	var humans: Array = []
	for u in m.units:
		if u.peer != 0 and players.has(u.peer):
			humans.append(u)
	if not m.fx.is_empty():
		for team in ArenaMatch.TEAMS:
			var list := FxFilter.for_team(m, team, sim_now)
			if list.is_empty():
				continue
			var msg := {"t": "fx", "list": list}
			for u in humans:
				if u.team == team:
					_send(u.peer, msg)
		m.fx.clear()
	for b in m.broadcasts:
		for u in humans:
			_send(u.peer, b)
	m.broadcasts.clear()
	for e in m.errors:
		_send(e.peer, {"t": "error", "text": e.text})
	m.errors.clear()
	if m.journal != null and not m.journal.is_empty():
		for u in humans:
			_send(u.peer, {"t": "lesson", "ev": m.journal})
		m.journal = []
	for u in humans:
		var snap := m.snapshot_for(u, sim_now)
		snap["ts"] = sim_now
		_send(u.peer, SnapshotCodec.pack(snap), false)
