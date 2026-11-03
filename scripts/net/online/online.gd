class_name Online
extends RefCounted
## Switchboard for the online features (teams, and later queues): shipped OFF. Nothing in the game reaches the network
## unless `ENABLED` is true and the config is valid. Supabase being down, paused or unconfigured only hides the features.

## Shipped OFF: there is no cloud project yet. Developers turn it on for a run with `--online` or IMBA_ONLINE=1 (see
## `dev_flag`), against the local Supabase; flipping this constant is the one-line switch for the day there is a backend.
const ENABLED := false
const ENV_FLAG := "IMBA_ONLINE"
const CONFIG_PATH := "res://data/online.json"
const ENV_URL := "IMBA_ONLINE_URL"
const ENV_KEY := "IMBA_ONLINE_ANON_KEY"


## The switch itself: the shipped constant or the developer's run flag.
static func on() -> bool:
	return ENABLED or dev_flag(OS.get_cmdline_user_args(), {ENV_FLAG: OS.get_environment(ENV_FLAG)})


## `--online` after `--`, or IMBA_ONLINE=1 / true in the environment. Never set in a shipped build's launch options.
static func dev_flag(user_args: PackedStringArray, env: Dictionary) -> bool:
	return user_args.has("--online") or str(env.get(ENV_FLAG, "")) in ["1", "true"]


## True when online features may be shown: the switch is on and there is somewhere to talk to.
static func enabled() -> bool:
	return on() and config_valid(config())


## data/online.json ({url, anon_key}) with the IMBA_ONLINE_* environment variables on top. The file holds the LOCAL
## Supabase URL only; the anon key is public by design but the local demo key is not committed: dev and tests pass
## it through the environment (or a production build fills the file).
static func config() -> Dictionary:
	var cfg := {"url": "", "anon_key": ""}
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f != null:
		var v = JSON.parse_string(f.get_as_text())
		if typeof(v) == TYPE_DICTIONARY:
			cfg["url"] = str(v.get("url", ""))
			cfg["anon_key"] = str(v.get("anon_key", ""))
	return merge_env(cfg, {ENV_URL: OS.get_environment(ENV_URL), ENV_KEY: OS.get_environment(ENV_KEY)})


static func merge_env(cfg: Dictionary, env: Dictionary) -> Dictionary:
	var out := cfg.duplicate()
	if str(env.get(ENV_URL, "")) != "":
		out["url"] = str(env[ENV_URL])
	if str(env.get(ENV_KEY, "")) != "":
		out["anon_key"] = str(env[ENV_KEY])
	return out


## https anywhere; plain http only for this machine (local Supabase).
static func config_valid(cfg: Dictionary) -> bool:
	var url := str(cfg.get("url", ""))
	if str(cfg.get("anon_key", "")) == "":
		return false
	if url.begins_with("https://"):
		return url.length() > 8
	for local in ["http://127.0.0.1", "http://localhost"]:
		if url == local or url.begins_with(local + ":") or url.begins_with(local + "/"):
			return true
	return false
