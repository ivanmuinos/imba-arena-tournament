class_name NetChoice
extends RefCounted
## Which network backend to use. Steam is optional: if the extension or the Steam client is missing the game
## falls back to ENet exactly as before.


## requested: "steam" | "enet". Returns {use: "steam"|"enet", note: Spanish message or ""}.
static func resolve(requested: String, steam_available: bool, steam_status: String = "") -> Dictionary:
	if requested == "steam":
		if steam_available:
			return {"use": "steam", "note": ""}
		return {"use": "enet", "note": "Steam no está disponible (%s). Se usa conexión directa por IP." % steam_status}
	return {"use": "enet", "note": ""}


## Name to use in a Steam match: your Steam persona name when you have one.
static func player_name(typed: String, persona: String, via_steam: bool) -> String:
	if via_steam and persona.strip_edges() != "":
		return MatchConfig.sanitize_name(persona)
	return MatchConfig.sanitize_name(typed)
