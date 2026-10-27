class_name NewsFeed
extends RefCounted
## News for the home screen, without a server of our own: Steam's public news feed of the app (announcements posted in
## Steamworks), a local cache for starting offline, and the news bundled with the game (data/news.json) as the last
## fallback. Pure parsing and choosing, unit tested; the download itself lives in NewsPanel.
##
## An item is {id, title, body, url, date (unix seconds), tag ("Parche" | "Noticia" | ...)}.

const STEAM_URL := "https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=%d&count=10&maxlength=0&format=json"
const BUNDLED := "res://data/news.json"
const CACHE := "user://news_cache.json"
const DEV_APP_ID := 480  # Spacewar: its feed is not ours
const MAX_BODY := 220
## How many seen news ids the settings keep.
const SEEN_KEEP := 50


static func url(app_id: int) -> String:
	return STEAM_URL % app_id


static func remote_enabled(app_id: int) -> bool:
	return app_id != 0 and app_id != DEV_APP_ID


static func parse_steam(text: String) -> Array:
	var data = _json(text)
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("appnews")) != TYPE_DICTIONARY:
		return []
	var out: Array = []
	for n in data.appnews.get("newsitems", []):
		if typeof(n) != TYPE_DICTIONARY or str(n.get("title", "")) == "":
			continue
		var tags: Array = n.get("tags", []) if typeof(n.get("tags")) == TYPE_ARRAY else []
		out.append({"id": str(n.get("gid", "")), "title": str(n.title), "body": clean(str(n.get("contents", ""))),
			"url": str(n.get("url", "")), "date": int(n.get("date", 0)), "tag": "Parche" if tags.has("patchnotes") else "Noticia"})
	return _newest_first(out)


## data/news.json: [{id, title, body, date: "YYYY-MM-DD", tag?, url?, map?, champion?}] (map/champion: banner art)
static func parse_local(text: String) -> Array:
	var data = _json(text)
	if typeof(data) != TYPE_ARRAY:
		return []
	var out: Array = []
	for n in data:
		if typeof(n) != TYPE_DICTIONARY or str(n.get("title", "")) == "":
			continue
		out.append({"id": str(n.get("id", n.title)), "title": str(n.title), "body": str(n.get("body", "")), "url": str(n.get("url", "")),
			"date": Time.get_unix_time_from_datetime_string(str(n.get("date", "1970-01-01"))), "tag": str(n.get("tag", "Noticia")),
			"map": str(n.get("map", "")), "champion": str(n.get("champion", ""))})
	return _newest_first(out)


static func load_bundled() -> Array:
	return parse_local(FileAccess.get_file_as_string(BUNDLED)) if FileAccess.file_exists(BUNDLED) else []


static func load_cache(path := CACHE) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var data = _json(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_ARRAY:
		return []
	# JSON brings numbers back as floats
	return data.map(func(i): i.date = int(i.get("date", 0)); return i)


static func save_cache(items: Array, path := CACHE) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(items))
	return true


## Downloaded first, then what was cached last time, then what ships with the game.
static func pick(remote: Array, cache: Array, bundled: Array) -> Array:
	for list in [remote, cache, bundled]:
		if not list.is_empty():
			return list
	return []


static func unseen(items: Array, seen: Array) -> Array:
	return items.filter(func(i): return not seen.has(str(i.id))).map(func(i): return str(i.id))


## Steam announcement markup (BBCode, clan images, line breaks) to one plain paragraph, cut at MAX_BODY.
static func clean(text: String) -> String:
	var re := RegEx.create_from_string("\\[img\\].*?\\[/img\\]|\\[/?[a-zA-Z0-9*]+(=[^\\]]*)?\\]|\\{STEAM_CLAN_IMAGE\\}\\S*")
	var t := re.sub(text, "", true)
	t = RegEx.create_from_string("\\s+").sub(t, " ", true).strip_edges()
	if t.length() > MAX_BODY:
		t = t.substr(0, MAX_BODY).strip_edges() + "…"
	return t


## Parsed JSON or null, without printing an engine error for bad input (a broken download is normal).
static func _json(text: String) -> Variant:
	var j := JSON.new()
	return j.data if j.parse(text) == OK else null


static func _newest_first(items: Array) -> Array:
	items.sort_custom(func(a, b): return int(a.date) > int(b.date))
	return items
