class_name Social
extends RefCounted
## Pure rules of the social panel: Steam friends grouped and described, and the rich presence we publish so friends
## see where we are (and can join a lobby with room from their Steam friends list). Unit tested.
##
## A friend is {id, name, state, app, lobby, status}: `state` is Steam's persona state (0 offline, 1 online, 2 busy,
## 3 away, 4 snooze, 5 trade, 6 play), `app` the app id they are playing (0 = none), `lobby` their lobby in that game,
## `status` our rich presence "status" key when they are in this game.

const GROUPS := [["playing", "Jugando Imba Arena"], ["online", "En línea"], ["offline", "Desconectados"]]


## [{key, title, items}] in GROUPS order, each sorted by name; empty groups are left out.
static func group(friends: Array, app_id: int) -> Array:
	var buckets := {"playing": [], "online": [], "offline": []}
	for f in friends:
		buckets[_bucket(f, app_id)].append(f)
	var out: Array = []
	for g in GROUPS:
		var items: Array = buckets[g[0]]
		if items.is_empty():
			continue
		items.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
		out.append({"key": g[0], "title": g[1], "items": items})
	return out


static func _bucket(f: Dictionary, app_id: int) -> String:
	if int(f.state) == 0:
		return "offline"
	return "playing" if app_id != 0 and int(f.app) == app_id else "online"


static func state_text(f: Dictionary, app_id: int) -> String:
	match _bucket(f, app_id):
		"offline":
			return "Desconectado"
		"playing":
			return str(f.status) if str(f.get("status", "")) != "" else "Jugando Imba Arena"
	if int(f.app) != 0:
		return "En otro juego"
	match int(f.state):
		2:
			return "Ocupado"
		3, 4:
			return "Ausente"
	return "En línea"


static func can_join(f: Dictionary, app_id: int) -> bool:
	return app_id != 0 and int(f.app) == app_id and int(f.lobby) != 0


## The Steam client window for an overlay action: the overlay only exists when Steam launched the game, so a copy
## started any other way (editor, zip) opens the client instead. "" when there is no such page.
static func steam_url(kind: String, steam_id: int) -> String:
	match kind:
		"chat":
			return "steam://friends/message/%d" % steam_id
		"steamid":
			return "steam://url/SteamIDPage/%d" % steam_id
		"friendadd":
			return "steam://friends/add/%d" % steam_id
		"friends":
			return "steam://open/friends"
	return ""


## What to tell the player when the Steam overlay cannot open (simulated Steam, or the overlay is off).
static func overlay_note(kind: String) -> String:
	match kind:
		"friends", "friendadd":
			return "Sin la superposición de Steam no se pueden agregar amigos desde acá. En el Steam simulado todas las copias del juego en tu red ya son tus amigos."
		"chat":
			return "El chat privado se abre en la superposición de Steam, que no está disponible. Usá el chat de la sala."
		"steamid":
			return "El perfil se abre en la superposición de Steam, que no está disponible."
	return "La superposición de Steam no está disponible."


## Rich presence for where we are. ctx: {where: menu|practice|lobby|match, lobby, members, max, mode, map_name}.
## "connect" makes Steam offer "Join game" to friends; only a lobby with room gets one.
static func presence(ctx: Dictionary) -> Dictionary:
	var status := "En el menú"
	var connect := ""
	match str(ctx.get("where", "menu")):
		"practice":
			status = "En la arena de práctica"
		"lobby":
			var members := int(ctx.get("members", 1))
			var cap := int(ctx.get("max", 0))
			status = "En sala (%d/%d)" % [members, cap]
			if int(ctx.get("lobby", 0)) != 0 and members < cap:
				connect = "+connect_lobby %d" % int(ctx.lobby)
		"match":
			var mode := int(ctx.get("mode", 2))
			status = "En partida %dv%d" % [mode, mode]
			if str(ctx.get("map_name", "")) != "":
				status += " · %s" % ctx.map_name
	return {"status": status, "connect": connect}
