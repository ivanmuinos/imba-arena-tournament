extends SceneTree
## Headless test runner: godot --headless --script res://tests/run_tests.gd

const SUITES := ["res://tests/test_rules.gd", "res://tests/test_match.gd", "res://tests/test_logic.gd", "res://tests/test_client_logic.gd", "res://tests/test_net.gd", "res://tests/test_hud_layout.gd", "res://tests/test_quality.gd", "res://tests/test_arenas.gd", "res://tests/test_controls.gd", "res://tests/test_steam.gd", "res://tests/test_menu_logic.gd", "res://tests/test_vfx.gd", "res://tests/test_paths.gd", "res://tests/test_shots.gd", "res://tests/test_specs.gd", "res://tests/test_companions.gd", "res://tests/test_ranked.gd", "res://tests/test_macros.gd"]


func _init() -> void:
	await process_frame  # the tree is only fully running after the first frame (UI tests need _ready)
	GameData.ensure_loaded()
	TestBase.tree = self
	var total := 0
	var failed: Array[String] = []
	# Optional filter: ./run_tests.sh logic net  -> only suites whose path contains one of the words.
	var only: Array = Array(OS.get_cmdline_user_args())
	var verbose := only.has("-v")  # print each test name as it starts (finds hangs)
	only.erase("-v")
	for path in SUITES + ["res://tests/test_warlock.gd", "res://tests/test_druid.gd", "res://tests/test_ct.gd", "res://tests/test_ronin.gd", "res://tests/test_crack.gd", "res://tests/test_wizard.gd", "res://tests/test_ki.gd", "res://tests/test_practice.gd", "res://tests/test_tutorial.gd", "res://tests/test_classes.gd"]:
		if not only.is_empty() and not only.any(func(w): return path.contains(w)):
			continue
		var script = load(path)
		if script == null or not script.can_instantiate():
			failed.append("no se pudo cargar %s" % path)
			continue
		var suite = script.new()
		for m in suite.get_method_list():
			if not String(m.name).begins_with("test_"):
				continue
			total += 1
			if verbose:
				print("» ", m.name)
			suite.current = m.name
			var before: int = suite.failures.size()
			suite.call(m.name)
			if suite.failures.size() > before:
				failed.append_array(suite.failures.slice(before))
	for f in failed:
		printerr("  ✗ ", f)
	print("Tests: %d, fallidos: %d" % [total, failed.size()])
	quit(1 if failed.size() > 0 else 0)
