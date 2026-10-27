extends TestBase
## Windows/Linux robustness: exported builds are case-sensitive and use forward slashes, but macOS dev machines are not.
## Every literal res:// path in the code must exist with the exact case, and exports must not depend on dev-only folders.


func _scripts(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_scripts(dir.path_join(sub), out)


## Exact-case existence: walks the path comparing directory listings (the OS lookup would be case-insensitive on macOS).
func _exists_exact(path: String) -> bool:
	var rel := path.trim_prefix("res://")
	var parts := rel.split("/")
	var dir := "res://"
	for i in parts.size():
		var d := DirAccess.open(dir)
		if d == null:
			return false
		var names: PackedStringArray = d.get_directories() if i < parts.size() - 1 else d.get_files()
		var want := parts[i]
		var ok := want in names
		if not ok and i == parts.size() - 1:
			ok = (want + ".import") in names or (want + ".remap") in names  # imported assets
		if not ok:
			return false
		dir = dir.path_join(want)
	return true


func test_all_literal_res_paths_exist_with_exact_case() -> void:
	var files: Array = []
	for root in ["res://scripts", "res://core", "res://tools/icons", "res://tests"]:
		_scripts(root, files)
	var re := RegEx.new()
	re.compile("\"(res://[A-Za-z0-9_./\\-]+)\"")
	var seen := {}
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		for m in re.search_all(text):
			var p: String = m.get_string(1)
			if seen.has(p) or p.ends_with("/") or p.contains("_dbg") or p.contains("/tests/test_") or f.begins_with("res://tests"):
				continue
			seen[p] = true
			check(_exists_exact(p), "%s: la ruta %s no existe con ese mayúsculas/minúsculas" % [f, p])


func test_no_backslashes_or_absolute_paths_in_game_code() -> void:
	var files: Array = []
	for root in ["res://scripts", "res://core"]:
		_scripts(root, files)
	var bad := RegEx.new()
	bad.compile("\"(?:[A-Za-z]:\\\\|/Users/|/home/)")
	for f in files:
		check(bad.search(FileAccess.get_file_as_string(f)) == null, "%s: ruta absoluta o con barras invertidas" % f)


func test_export_presets_ship_icon_and_exclude_dev_folders() -> void:
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(cfg.contains("res://assets/app_icon/icon.ico"), "Windows: ícono .ico")
	check(cfg.contains("res://assets/app_icon/icon.icns"), "macOS: ícono .icns")
	check(cfg.contains("exclude_filter=\"tests/*, tools/*, build/*, compartir/*, docs/*"), "no se exportan tests, tools, compartir ni docs")
	for f in ["icon.ico", "icon.icns", "icon.png", "icon.svg"]:
		check(_exists_exact("res://assets/app_icon/" + f), "existe " + f)
	var sdl := FileAccess.get_file_as_string("res://addons/godotsteam/godotsteam.gdextension")
	check(sdl.contains("steam_api64.dll") and sdl.contains("libsteam_api.dylib"), "las dependencias de Steam viajan junto al ejecutable")


func test_version_is_consistent_across_project_and_export_presets() -> void:
	var v := str(ProjectSettings.get_setting("application/config/version"))
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(cfg.contains("application/file_version=\"%s.0\"" % v), "versión de archivo del .exe = %s" % v)
	check(cfg.contains("application/short_version=\"%s\"" % v), "versión de macOS = %s" % v)
	check(cfg.contains("application/product_name=\"Imba Arena Tournament\""), "nombre de producto")
	eq(GameServer.game_version(), v, "el handshake usa la misma versión")


func test_version_flag_parses_and_prints_the_handshake_version() -> void:
	var main_script = load("res://scripts/main.gd")
	check(main_script._parse(PackedStringArray(["--version"])).has("version"), "-- --version se reconoce")
	check(not main_script._parse(PackedStringArray(["--offline", "version"])).has("version"), "sólo con guiones")
	eq(main_script.version_line(), "Imba Arena Tournament v%s" % GameServer.game_version(), "una línea con nombre y versión del handshake")
